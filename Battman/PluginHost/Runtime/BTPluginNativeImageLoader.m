//
//  BTPluginNativeImageLoader.m
//  Battman
//

#import "BTPluginNativeImageLoaderPrivate.h"

#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../BTEmbeddedPluginRegistration.h"
#import "../BTPluginIdentifiers.h"
#import "../BTPluginRegistry.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Security/BTPluginPackageVerifier.h"
#include "../../../PluginSDK/include/BattmanPluginABI.h"

// Keep the staging boundary independently linkable for the fixture-only native
// loader tests while enforcing the same published structural limits.
static const NSUInteger BTPluginStageMaximumRegularFileCount = 512;
static const uint64_t BTPluginStageMaximumSingleFileByteCount = 64ULL * 1024ULL * 1024ULL;
static const uint64_t BTPluginStageMaximumTotalByteCount = 128ULL * 1024ULL * 1024ULL;

static BOOL BTPluginRuntimeFail(NSError **error, NSString *description, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorRuntime, description, nil, underlyingError);
	return NO;
}

static BOOL BTPluginStageFail(NSError **error, NSString *description,
	NSString *relativePath, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
			description, relativePath, underlyingError);
	return NO;
}

static NSError *BTPluginPOSIXError(int value) {
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:value userInfo:nil];
}

static BOOL BTPluginNativeStringMatches(const char *value, NSString *expected) {
	if (!value || !expected)
		return NO;
	size_t maximumLength = 256;
	size_t length = strnlen(value, maximumLength + 1);
	if (length == 0 || length > maximumLength)
		return NO;
	NSString *string = [[NSString alloc] initWithBytes:value length:length encoding:NSUTF8StringEncoding];
	return [string isEqualToString:expected];
}

static NSString *BTPluginHexDigest(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *data = [NSMutableData dataWithLength:length * 2];
	char *characters = data.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
}

static BOOL BTPluginSHA256IsCanonical(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != CC_SHA256_DIGEST_LENGTH * 2)
		return NO;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')))
			return NO;
	}
	return YES;
}

static BOOL BTPluginStatsMatch(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_size == right->st_size && left->st_mode == right->st_mode &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static BOOL BTPluginWriteAll(int descriptor, const uint8_t *bytes, size_t length) {
	while (length > 0) {
		ssize_t count = write(descriptor, bytes, length);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return NO;
		bytes += count;
		length -= (size_t)count;
	}
	return YES;
}

static BOOL BTPluginHashDescriptor(int descriptor, uint64_t expectedSize,
	NSString *expectedSHA256, NSString *relativePath, NSError **error) {
	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	while (offset < expectedSize) {
		size_t requested = (size_t)MIN((uint64_t)sizeof(buffer), expectedSize - offset);
		ssize_t count;
		do {
			count = pread(descriptor, buffer, requested, (off_t)offset);
		} while (count < 0 && errno == EINTR);
		if (count <= 0) {
			return BTPluginStageFail(error,
				@"A staged payload file became unreadable or shorter than its signed inventory.",
				relativePath, count < 0 ? BTPluginPOSIXError(errno) : nil);
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		offset += (uint64_t)count;
	}
	uint8_t extra = 0;
	ssize_t extraCount;
	do {
		extraCount = pread(descriptor, &extra, sizeof(extra), (off_t)expectedSize);
	} while (extraCount < 0 && errno == EINTR);
	if (extraCount != 0) {
		return BTPluginStageFail(error,
			@"A staged payload file became longer than its signed inventory.", relativePath,
			extraCount < 0 ? BTPluginPOSIXError(errno) : nil);
	}
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	if (![BTPluginHexDigest(digest, sizeof(digest)) isEqualToString:expectedSHA256]) {
		return BTPluginStageFail(error,
			@"A payload file no longer matches the bytes accepted by offline verification.",
			relativePath, nil);
	}
	return YES;
}

@interface BTPluginStageFile : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, strong) NSURL *sourceURL;
@property (nonatomic) uint64_t fileSize;
@property (nonatomic, copy) NSString *sha256;
@property (nonatomic) BOOL executable;
@end

@implementation BTPluginStageFile
@end

@interface BTPluginPreparedNativeImage ()
@property (nonatomic, strong, readwrite) NSURL *stageRootURL;
@property (nonatomic, strong, readwrite) NSURL *stagedExecutableURL;
@property (nonatomic, copy, readwrite) NSString *contentSHA256;
@property (nonatomic, copy) NSString *executableRelativePath;
@property (nonatomic, copy) NSString *executableSHA256;
@property (nonatomic) uint64_t executableSize;
@property (nonatomic) int rootDescriptor;
@property (nonatomic) int contentDescriptor;
@property (nonatomic) int executableDescriptor;
@property (nonatomic) int lockDescriptor;
@property (nonatomic) dev_t rootDevice;
@property (nonatomic) ino_t rootInode;
@property (nonatomic) dev_t contentDevice;
@property (nonatomic) ino_t contentInode;
@property (nonatomic) struct stat executableStat;
@property (nonatomic, getter=isMapped) BOOL mapped;
- (instancetype)initPrivate;
@end

static void BTPluginRemoveOwnedStage(NSURL *rootURL, dev_t device, ino_t inode) {
	if (!rootURL)
		return;
	struct stat current;
	if (lstat(rootURL.fileSystemRepresentation, &current) != 0 || !S_ISDIR(current.st_mode) ||
		current.st_dev != device || current.st_ino != inode)
		return;
	(void)chmod(rootURL.fileSystemRepresentation, 0700);
	[[NSFileManager defaultManager] removeItemAtURL:rootURL error:nil];
}

static BOOL BTPluginRuntimeStageNameIsValid(NSString *name) {
	NSString *prefix = @".battman-runtime-";
	if (![name hasPrefix:prefix])
		return NO;
	NSString *suffix = [name substringFromIndex:prefix.length];
	if (suffix.length != 60 || [suffix characterAtIndex:16] != '-' ||
		[suffix characterAtIndex:53] != '.')
		return NO;
	for (NSUInteger index = 0; index < 16; index++) {
		unichar character = [suffix characterAtIndex:index];
		if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')))
			return NO;
	}
	NSString *uuidString = [suffix substringWithRange:NSMakeRange(17, 36)];
	if (![[NSUUID alloc] initWithUUIDString:uuidString])
		return NO;
	for (NSUInteger index = 54; index < suffix.length; index++) {
		unichar character = [suffix characterAtIndex:index];
		if (!((character >= '0' && character <= '9') ||
			(character >= 'A' && character <= 'Z') ||
			(character >= 'a' && character <= 'z')))
			return NO;
	}
	return YES;
}

static void BTPluginCleanupStaleRuntimeStages(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSURL *temporaryURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
		NSArray<NSURL *> *entries = [[NSFileManager defaultManager]
			contentsOfDirectoryAtURL:temporaryURL includingPropertiesForKeys:nil
			options:0 error:nil];
		for (NSURL *entryURL in entries) {
			if (!BTPluginRuntimeStageNameIsValid(entryURL.lastPathComponent))
				continue;
			struct stat pathStat;
			if (lstat(entryURL.fileSystemRepresentation, &pathStat) != 0 ||
				!S_ISDIR(pathStat.st_mode) || pathStat.st_uid != geteuid() ||
				(pathStat.st_mode & 0777) != 0700)
				continue;
			int root = open(entryURL.fileSystemRepresentation,
				O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
			if (root < 0)
				continue;
			struct stat openedStat;
			BOOL sameRoot = fstat(root, &openedStat) == 0 &&
				openedStat.st_dev == pathStat.st_dev && openedStat.st_ino == pathStat.st_ino;
			int lock = sameRoot ? openat(root, ".lock", O_RDWR | O_CLOEXEC | O_NOFOLLOW) : -1;
			struct stat lockStat;
			BOOL ownsLock = lock >= 0 && fstat(lock, &lockStat) == 0 &&
				S_ISREG(lockStat.st_mode) && lockStat.st_nlink == 1 &&
				lockStat.st_uid == geteuid() && (lockStat.st_mode & 0777) == 0600 &&
				flock(lock, LOCK_EX | LOCK_NB) == 0;
			if (ownsLock)
				BTPluginRemoveOwnedStage(entryURL, pathStat.st_dev, pathStat.st_ino);
			if (lock >= 0) {
				if (ownsLock)
					(void)flock(lock, LOCK_UN);
				close(lock);
			}
			close(root);
		}
	});
}

@implementation BTPluginPreparedNativeImage

- (instancetype)initPrivate {
	self = [super init];
	if (self) {
		_rootDescriptor = -1;
		_contentDescriptor = -1;
		_executableDescriptor = -1;
		_lockDescriptor = -1;
	}
	return self;
}

- (void)dealloc {
	if (_executableDescriptor >= 0)
		close(_executableDescriptor);
	if (_contentDescriptor >= 0)
		close(_contentDescriptor);
	if (_rootDescriptor >= 0)
		close(_rootDescriptor);
	if (!_mapped)
		BTPluginRemoveOwnedStage(_stageRootURL, _rootDevice, _rootInode);
	if (_lockDescriptor >= 0) {
		(void)flock(_lockDescriptor, LOCK_UN);
		close(_lockDescriptor);
	}
}

@end


static int BTPluginOpenStageDirectory(int rootDescriptor, NSArray<NSString *> *components,
	BOOL create, NSString *relativePath, NSError **error) {
	int current = dup(rootDescriptor);
	if (current < 0) {
		BTPluginStageFail(error, @"The private staging root could not be duplicated.",
			relativePath, BTPluginPOSIXError(errno));
		return -1;
	}
	for (NSString *component in components) {
		if (component.length == 0 || [component isEqualToString:@"."] ||
			[component isEqualToString:@".."] || [component rangeOfString:@"/"].location != NSNotFound) {
			close(current);
			BTPluginStageFail(error, @"A signed payload path is unsafe for private staging.",
				relativePath, nil);
			return -1;
		}
		if (create && mkdirat(current, component.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
			int savedErrno = errno;
			close(current);
			BTPluginStageFail(error, @"A private payload directory could not be created.",
				relativePath, BTPluginPOSIXError(savedErrno));
			return -1;
		}
		int next = openat(current, component.fileSystemRepresentation,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
		if (next < 0) {
			int savedErrno = errno;
			close(current);
			BTPluginStageFail(error, @"A private payload directory could not be opened safely.",
				relativePath, BTPluginPOSIXError(savedErrno));
			return -1;
		}
		struct stat status;
		if (fstat(next, &status) != 0 || !S_ISDIR(status.st_mode) ||
			(status.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0) {
			close(next);
			close(current);
			BTPluginStageFail(error, @"A private payload directory has an unsafe identity or mode.",
				relativePath, nil);
			return -1;
		}
		if (create && fsync(current) != 0) {
			int savedErrno = errno;
			close(next);
			close(current);
			BTPluginStageFail(error, @"A private payload directory entry could not be synchronized.",
				relativePath, BTPluginPOSIXError(savedErrno));
			return -1;
		}
		close(current);
		current = next;
	}
	return current;
}

static BOOL BTPluginCopyVerifiedStageFile(BTPluginStageFile *file,
	int contentDescriptor, NSError **error) {
	NSArray<NSString *> *components = [file.relativePath componentsSeparatedByString:@"/"];
	if (components.count == 0)
		return BTPluginStageFail(error, @"A signed payload file has no staging path.", file.relativePath, nil);
	NSString *leaf = components.lastObject;
	NSArray<NSString *> *parents = components.count > 1 ?
		[components subarrayWithRange:NSMakeRange(0, components.count - 1)] : @[];
	int parent = BTPluginOpenStageDirectory(contentDescriptor, parents, YES, file.relativePath, error);
	if (parent < 0)
		return NO;

	int source = open(file.sourceURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (source < 0) {
		int savedErrno = errno;
		close(parent);
		return BTPluginStageFail(error, @"A verified payload file could not be reopened for staging.",
			file.relativePath, BTPluginPOSIXError(savedErrno));
	}
	struct stat before;
	BOOL sourceExecutable = NO;
	if (fstat(source, &before) != 0 || !S_ISREG(before.st_mode) || before.st_nlink != 1 ||
		before.st_size < 0 || (uint64_t)before.st_size != file.fileSize) {
		close(source);
		close(parent);
		return BTPluginStageFail(error,
			@"A verified payload file changed identity or size before private staging.",
			file.relativePath, nil);
	}
	sourceExecutable = (before.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0;
	if (sourceExecutable != file.executable) {
		close(source);
		close(parent);
		return BTPluginStageFail(error,
			@"A verified payload file changed its signed mode before private staging.",
			file.relativePath, nil);
	}

	int destination = openat(parent, leaf.fileSystemRepresentation,
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (destination < 0) {
		int savedErrno = errno;
		close(source);
		close(parent);
		return BTPluginStageFail(error, @"A private payload file could not be created exclusively.",
			file.relativePath, BTPluginPOSIXError(savedErrno));
	}

	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	BOOL copied = YES;
	while (offset < file.fileSize) {
		size_t requested = (size_t)MIN((uint64_t)sizeof(buffer), file.fileSize - offset);
		ssize_t count;
		do {
			count = pread(source, buffer, requested, (off_t)offset);
		} while (count < 0 && errno == EINTR);
		if (count <= 0 || !BTPluginWriteAll(destination, buffer, (size_t)count)) {
			copied = NO;
			break;
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		offset += (uint64_t)count;
	}
	uint8_t extra = 0;
	ssize_t extraCount = -1;
	if (copied) {
		do {
			extraCount = pread(source, &extra, sizeof(extra), (off_t)file.fileSize);
		} while (extraCount < 0 && errno == EINTR);
		copied = extraCount == 0;
	}
	struct stat after;
	BOOL unchanged = fstat(source, &after) == 0 && BTPluginStatsMatch(&before, &after);
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	BOOL digestMatches = copied && offset == file.fileSize &&
		[BTPluginHexDigest(digest, sizeof(digest)) isEqualToString:file.sha256];
	mode_t finalMode = file.executable ? 0500 : 0400;
	BOOL durable = digestMatches && unchanged && fchmod(destination, finalMode) == 0 &&
		fsync(destination) == 0 && fsync(parent) == 0;
	int savedErrno = errno;
	close(destination);
	close(source);
	if (!durable)
		(void)unlinkat(parent, leaf.fileSystemRepresentation, 0);
	close(parent);
	if (!durable) {
		return BTPluginStageFail(error,
			digestMatches && unchanged ? @"A private payload file could not be synchronized." :
			@"A payload file changed after verification and before private staging completed.",
			file.relativePath, digestMatches && unchanged ? BTPluginPOSIXError(savedErrno) : nil);
	}
	return YES;
}

static int BTPluginOpenRelativeFile(int rootDescriptor, NSString *relativePath, NSError **error) {
	NSArray<NSString *> *components = [relativePath componentsSeparatedByString:@"/"];
	if (components.count == 0) {
		BTPluginStageFail(error, @"The staged executable path is empty.", relativePath, nil);
		return -1;
	}
	NSString *leaf = components.lastObject;
	NSArray<NSString *> *parents = components.count > 1 ?
		[components subarrayWithRange:NSMakeRange(0, components.count - 1)] : @[];
	int parent = BTPluginOpenStageDirectory(rootDescriptor, parents, NO, relativePath, error);
	if (parent < 0)
		return -1;
	int descriptor = openat(parent, leaf.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0) {
		int savedErrno = errno;
		close(parent);
		BTPluginStageFail(error, @"The staged executable could not be opened safely.",
			relativePath, BTPluginPOSIXError(savedErrno));
		return -1;
	}
	close(parent);
	return descriptor;
}

static BOOL BTPluginAuthorizeStagedExecutable(int descriptor,
	BTPluginMachOInspection *machOInspection, NSString *relativePath, NSError **error) {
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
	if (!machOInspection)
		return BTPluginStageFail(error, @"The staged iOS image has no verified Mach-O identity.", relativePath, nil);
	fsignatures_t signature = {0};
	signature.fs_file_start = (off_t)machOInspection.sliceFileOffset;
	signature.fs_blob_start = (void *)(uintptr_t)machOInspection.codeSignatureOffsetInSlice;
	signature.fs_blob_size = machOInspection.codeSignatureByteCount;
	if (fcntl(descriptor, F_ADDFILESIGS_RETURN, &signature) == -1) {
		return BTPluginStageFail(error,
			@"The iOS kernel rejected the staged image's verified code signature.",
			relativePath, BTPluginPOSIXError(errno));
	}
	if ((uint64_t)signature.fs_file_start < machOInspection.codeSignatureOffsetInSlice) {
		return BTPluginStageFail(error,
			@"The staged image's code signature does not cover all executable bytes.",
			relativePath, nil);
	}
	char message[512] = {0};
	fchecklv_t check = {
		.lv_file_start = (off_t)machOInspection.sliceFileOffset,
		.lv_error_message_size = sizeof(message),
		.lv_error_message = message,
	};
	if (fcntl(descriptor, F_CHECK_LV, &check) == -1) {
		NSString *kernelMessage = [[NSString alloc] initWithBytes:message
			length:strnlen(message, sizeof(message)) encoding:NSUTF8StringEncoding];
		NSString *description = kernelMessage.length > 0 ?
			[NSString stringWithFormat:@"The iOS library-validation policy rejected the staged image: %@",
				kernelMessage] : @"The iOS library-validation policy rejected the staged image.";
		return BTPluginStageFail(error, description, relativePath, BTPluginPOSIXError(errno));
	}
#else
	(void)descriptor;
	(void)machOInspection;
	(void)relativePath;
	(void)error;
#endif
	return YES;
}

static BTPluginPreparedNativeImage *BTPluginCreatePreparedImage(
	NSArray<BTPluginStageFile *> *files, NSString *contentSHA256,
	NSString *executableRelativePath, BTPluginMachOInspection *machOInspection,
	NSError **error) {
	if (files.count == 0 || files.count > BTPluginStageMaximumRegularFileCount ||
		!BTPluginSHA256IsCanonical(contentSHA256) ||
		executableRelativePath.length == 0) {
		BTPluginStageFail(error, @"The verified payload inventory is malformed.", nil, nil);
		return nil;
	}
	uint64_t totalByteCount = 0;
	for (BTPluginStageFile *file in files) {
		if (!file.sourceURL.isFileURL || !file.sourceURL.path.isAbsolutePath ||
			file.relativePath.length == 0 || !BTPluginSHA256IsCanonical(file.sha256) ||
			file.fileSize > BTPluginStageMaximumSingleFileByteCount ||
			UINT64_MAX - totalByteCount < file.fileSize ||
			(totalByteCount += file.fileSize) > BTPluginStageMaximumTotalByteCount) {
			BTPluginStageFail(error, @"The verified payload inventory exceeds its staging bounds.",
				file.relativePath, nil);
			return nil;
		}
	}
	BTPluginCleanupStaleRuntimeStages();
	NSString *temporaryDirectory = NSTemporaryDirectory();
	if (![temporaryDirectory isKindOfClass:[NSString class]] || !temporaryDirectory.isAbsolutePath) {
		BTPluginStageFail(error, @"A private runtime staging directory is unavailable.", nil, nil);
		return nil;
	}
	NSString *templatePath = [temporaryDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@".battman-runtime-%@-%@.XXXXXX",
			[contentSHA256 substringToIndex:16], NSUUID.UUID.UUIDString]];
	if (strlen(templatePath.fileSystemRepresentation) >= PATH_MAX) {
		BTPluginStageFail(error, @"The private runtime staging path is too long.", nil, nil);
		return nil;
	}
	char *mutableTemplate = strdup(templatePath.fileSystemRepresentation);
	if (!mutableTemplate) {
		BTPluginStageFail(error, @"The private runtime staging path could not be allocated.", nil, nil);
		return nil;
	}
	char *createdPath = mkdtemp(mutableTemplate);
	if (!createdPath) {
		int savedErrno = errno;
		free(mutableTemplate);
		BTPluginStageFail(error, @"The private runtime staging root could not be created atomically.",
			nil, BTPluginPOSIXError(savedErrno));
		return nil;
	}
	NSURL *stageRootURL = [NSURL fileURLWithFileSystemRepresentation:createdPath
		isDirectory:YES relativeToURL:nil];
	free(mutableTemplate);
	struct stat rootStat = {0};
	int rootDescriptor = -1;
	int contentDescriptor = -1;
	int executableDescriptor = -1;
	int lockDescriptor = -1;
	BOOL rootIdentityKnown = NO;
	BTPluginStageFile *executableFile = nil;
	BTPluginPreparedNativeImage *result = nil;
	NSURL *contentURL = nil;
	struct stat contentStat = {0};
	if (lstat(stageRootURL.fileSystemRepresentation, &rootStat) != 0 || !S_ISDIR(rootStat.st_mode)) {
		BTPluginStageFail(error, @"The private runtime staging root has an unsafe identity.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	rootIdentityKnown = YES;
	if (fchmodat(AT_FDCWD, stageRootURL.fileSystemRepresentation, 0700, AT_SYMLINK_NOFOLLOW) != 0 ||
		(rootDescriptor = open(stageRootURL.fileSystemRepresentation,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)) < 0) {
		BTPluginStageFail(error, @"The private runtime staging root has an unsafe identity.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	struct stat openedRootStat;
	if (fstat(rootDescriptor, &openedRootStat) != 0 ||
		rootStat.st_dev != openedRootStat.st_dev || rootStat.st_ino != openedRootStat.st_ino) {
		BTPluginStageFail(error, @"The private runtime staging root changed while it was opened.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	lockDescriptor = openat(rootDescriptor, ".lock",
		O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (lockDescriptor < 0 || fchmod(lockDescriptor, 0600) != 0 ||
		flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 || fsync(lockDescriptor) != 0 ||
		fsync(rootDescriptor) != 0) {
		BTPluginStageFail(error, @"The private runtime staging lifetime lock could not be acquired.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	if (mkdirat(rootDescriptor, contentSHA256.fileSystemRepresentation, 0700) != 0 ||
		(contentDescriptor = openat(rootDescriptor, contentSHA256.fileSystemRepresentation,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)) < 0 || fsync(rootDescriptor) != 0) {
		BTPluginStageFail(error, @"The content-addressed private payload root could not be created safely.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	for (BTPluginStageFile *file in files) {
		if (!BTPluginCopyVerifiedStageFile(file, contentDescriptor, error))
			goto cleanup;
	}
	if (fstat(contentDescriptor, &contentStat) != 0 || !S_ISDIR(contentStat.st_mode) ||
		fsync(contentDescriptor) != 0 || fsync(rootDescriptor) != 0) {
		BTPluginStageFail(error, @"The private payload inventory could not be synchronized.",
			nil, BTPluginPOSIXError(errno));
		goto cleanup;
	}
	for (BTPluginStageFile *file in files) {
		if ([file.relativePath isEqualToString:executableRelativePath]) {
			executableFile = file;
			break;
		}
	}
	if (!executableFile || !executableFile.executable) {
		BTPluginStageFail(error, @"The signed payload inventory has no executable image.",
			executableRelativePath, nil);
		goto cleanup;
	}
	executableDescriptor = BTPluginOpenRelativeFile(contentDescriptor, executableRelativePath, error);
	struct stat executableStat;
	if (executableDescriptor < 0 || fstat(executableDescriptor, &executableStat) != 0 ||
		!S_ISREG(executableStat.st_mode) || executableStat.st_nlink != 1 ||
		executableStat.st_size < 0 || (uint64_t)executableStat.st_size != executableFile.fileSize ||
		!BTPluginHashDescriptor(executableDescriptor, executableFile.fileSize,
			executableFile.sha256, executableRelativePath, error) ||
		!BTPluginAuthorizeStagedExecutable(executableDescriptor, machOInspection,
			executableRelativePath, error)) {
		if (error && !*error)
			BTPluginStageFail(error, @"The staged executable identity is invalid.", executableRelativePath, nil);
		goto cleanup;
	}

	result = [[BTPluginPreparedNativeImage alloc] initPrivate];
	result.stageRootURL = stageRootURL;
	result.contentSHA256 = contentSHA256;
	result.executableRelativePath = executableRelativePath;
	result.executableSHA256 = executableFile.sha256;
	result.executableSize = executableFile.fileSize;
	result.rootDescriptor = rootDescriptor;
	result.contentDescriptor = contentDescriptor;
	result.executableDescriptor = executableDescriptor;
	result.lockDescriptor = lockDescriptor;
	result.rootDevice = openedRootStat.st_dev;
	result.rootInode = openedRootStat.st_ino;
	result.contentDevice = contentStat.st_dev;
	result.contentInode = contentStat.st_ino;
	result.executableStat = executableStat;
	contentURL = [stageRootURL URLByAppendingPathComponent:contentSHA256 isDirectory:YES];
	result.stagedExecutableURL = [contentURL URLByAppendingPathComponent:executableRelativePath isDirectory:NO];
	rootDescriptor = -1;
	contentDescriptor = -1;
	executableDescriptor = -1;
	lockDescriptor = -1;
	return result;

cleanup:
	if (executableDescriptor >= 0)
		close(executableDescriptor);
	if (contentDescriptor >= 0)
		close(contentDescriptor);
	if (rootDescriptor >= 0)
		close(rootDescriptor);
	if (rootIdentityKnown)
		BTPluginRemoveOwnedStage(stageRootURL, rootStat.st_dev, rootStat.st_ino);
	else
		(void)rmdir(stageRootURL.fileSystemRepresentation);
	if (lockDescriptor >= 0) {
		(void)flock(lockDescriptor, LOCK_UN);
		close(lockDescriptor);
	}
	return nil;
}

static BOOL BTPluginHashLooseFile(NSURL *url, uint64_t *size, NSString **sha256, NSError **error) {
	int descriptor = open(url.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0)
		return BTPluginStageFail(error, @"The fixture image could not be opened for private staging.",
			url.lastPathComponent, BTPluginPOSIXError(errno));
	struct stat status;
	if (fstat(descriptor, &status) != 0 || !S_ISREG(status.st_mode) || status.st_nlink != 1 ||
		status.st_size < 0 || (uint64_t)status.st_size > BTPluginStageMaximumSingleFileByteCount) {
		close(descriptor);
		return BTPluginStageFail(error, @"The fixture image is not one bounded regular file.",
			url.lastPathComponent, nil);
	}
	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	BOOL valid = YES;
	while (offset < (uint64_t)status.st_size) {
		size_t requested = (size_t)MIN((uint64_t)sizeof(buffer), (uint64_t)status.st_size - offset);
		ssize_t count;
		do {
			count = pread(descriptor, buffer, requested, (off_t)offset);
		} while (count < 0 && errno == EINTR);
		if (count <= 0) {
			valid = NO;
			break;
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		offset += (uint64_t)count;
	}
	struct stat after;
	valid = valid && fstat(descriptor, &after) == 0 && BTPluginStatsMatch(&status, &after);
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	close(descriptor);
	if (!valid)
		return BTPluginStageFail(error, @"The fixture image changed during digest inspection.",
			url.lastPathComponent, nil);
	if (size)
		*size = (uint64_t)status.st_size;
	if (sha256)
		*sha256 = BTPluginHexDigest(digest, sizeof(digest));
	return YES;
}

static NSMutableArray<NSValue *> *BTPluginProcessMappedHandles(void) {
	static NSMutableArray<NSValue *> *handles;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ handles = [NSMutableArray array]; });
	return handles;
}

static void BTPluginCleanupMappedStagesAtExit(void);

static NSMutableArray<BTPluginPreparedNativeImage *> *BTPluginProcessPinnedImages(void) {
	static NSMutableArray<BTPluginPreparedNativeImage *> *images;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		images = [NSMutableArray array];
		(void)atexit(BTPluginCleanupMappedStagesAtExit);
	});
	return images;
}

static void BTPluginCleanupMappedStagesAtExit(void) {
	@autoreleasepool {
		for (BTPluginPreparedNativeImage *image in [BTPluginProcessPinnedImages() copy])
			BTPluginRemoveOwnedStage(image.stageRootURL, image.rootDevice, image.rootInode);
	}
}

static NSMutableSet<NSString *> *BTPluginProcessMappedIdentities(void) {
	static NSMutableSet<NSString *> *identities;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ identities = [NSMutableSet set]; });
	return identities;
}

@implementation BTPluginNativeImageLoader

- (BTPluginPreparedNativeImage *)prepareImageForVerifiedPackage:
	(BTPluginVerifiedPackage *)verifiedPackage error:(NSError **)error {
	if (!verifiedPackage || ![verifiedPackage respondsToSelector:@selector(packageInspection)] ||
		![verifiedPackage respondsToSelector:@selector(machOInspection)]) {
		BTPluginStageFail(error, @"Private staging requires one completely verified package.", nil, nil);
		return nil;
	}
	BTPluginPackageInspection *inspection = verifiedPackage.packageInspection;
	BTPluginMachOInspection *machOInspection = verifiedPackage.machOInspection;
	BTPluginPackageManifest *manifest = inspection.manifest;
	NSString *payloadPath = manifest.payload.path;
	NSString *payloadPrefix = [payloadPath stringByAppendingString:@"/"];
	if (!inspection || !machOInspection || !manifest || !BTPluginSHA256IsCanonical(inspection.packageSHA256) ||
		payloadPath.length == 0 || manifest.payload.executablePath.length == 0 ||
		![inspection.executableURL isEqual:machOInspection.executableURL]) {
		BTPluginStageFail(error, @"The verified package has an inconsistent payload identity.", nil, nil);
		return nil;
	}
	NSMutableArray<BTPluginStageFile *> *files = [NSMutableArray array];
	uint64_t totalByteCount = 0;
	NSArray<NSString *> *paths = [inspection.filesByPath.allKeys
		sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *logicalPath in paths) {
		if (![logicalPath isEqualToString:payloadPath] && ![logicalPath hasPrefix:payloadPrefix])
			continue;
		BTPluginInspectedFile *inspectedFile = inspection.filesByPath[logicalPath];
		if (!BTPluginSHA256IsCanonical(inspectedFile.sha256) || inspectedFile.fileSize >
			BTPluginStageMaximumSingleFileByteCount ||
			UINT64_MAX - totalByteCount < inspectedFile.fileSize ||
			(totalByteCount += inspectedFile.fileSize) > BTPluginStageMaximumTotalByteCount ||
			(![inspectedFile.modeClass isEqualToString:@"data"] &&
			 ![inspectedFile.modeClass isEqualToString:@"executable"])) {
			BTPluginStageFail(error, @"The verified payload inventory contains an invalid file record.",
				logicalPath, nil);
			return nil;
		}
		NSURL *sourceURL = nil;
		if (inspection.isSealedAppBundleRepresentation) {
			if ([logicalPath isEqualToString:payloadPath]) {
				sourceURL = inspection.payloadURL;
			} else {
				NSString *physicalPath = [logicalPath substringFromIndex:payloadPrefix.length];
				sourceURL = [inspection.payloadURL URLByAppendingPathComponent:physicalPath isDirectory:NO];
			}
		} else {
			sourceURL = [inspection.packageURL URLByAppendingPathComponent:logicalPath isDirectory:NO];
		}
		BTPluginStageFile *file = [BTPluginStageFile new];
		file.relativePath = logicalPath;
		file.sourceURL = sourceURL;
		file.fileSize = inspectedFile.fileSize;
		file.sha256 = inspectedFile.sha256;
		file.executable = [inspectedFile.modeClass isEqualToString:@"executable"];
		[files addObject:file];
	}
	if (files.count == 0 || files.count > BTPluginStageMaximumRegularFileCount) {
		BTPluginStageFail(error, @"The verified payload inventory is empty or exceeds its file limit.", nil, nil);
		return nil;
	}
	return BTPluginCreatePreparedImage(files, inspection.packageSHA256,
		manifest.payload.executablePath, machOInspection, error);
}

- (BTPluginPreparedNativeImage *)bt_prepareLooseImageAtURL:(NSURL *)executableURL
	error:(NSError **)error {
	if (![executableURL isKindOfClass:[NSURL class]] || !executableURL.isFileURL ||
		!executableURL.path.isAbsolutePath) {
		BTPluginStageFail(error, @"The fixture native image path is malformed.", nil, nil);
		return nil;
	}
	uint64_t size = 0;
	NSString *sha256 = nil;
	if (!BTPluginHashLooseFile(executableURL, &size, &sha256, error))
		return nil;
	BTPluginStageFile *file = [BTPluginStageFile new];
	file.relativePath = @"Fixture.bundle";
	file.sourceURL = executableURL;
	file.fileSize = size;
	file.sha256 = sha256;
	file.executable = YES;
	return BTPluginCreatePreparedImage(@[ file ], sha256, file.relativePath, nil, error);
}

- (BOOL)loadPreparedImage:(BTPluginPreparedNativeImage *)preparedImage
	expectedPluginIdentifier:(NSString *)pluginIdentifier
		 expectedPluginVersion:(NSString *)pluginVersion
		 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
						 registry:(BTPluginRegistry *)registry
							 error:(NSError **)error {
	if (![NSThread isMainThread])
		return BTPluginRuntimeFail(error, @"Native plug-ins must be mapped and registered on the main thread.", nil);
	if (![preparedImage isKindOfClass:[BTPluginPreparedNativeImage class]] || preparedImage.isMapped ||
		!BTPluginSHA256IsCanonical(preparedImage.contentSHA256) ||
		!BTPluginIdentifierIsValid(pluginIdentifier) ||
		![pluginVersion isKindOfClass:[NSString class]] || pluginVersion.length == 0 || pluginVersion.length > 128 ||
		![declaredExtensionPoints isKindOfClass:[NSSet class]] || declaredExtensionPoints.count == 0 ||
		![registry isKindOfClass:[BTPluginRegistry class]]) {
		return BTPluginRuntimeFail(error, @"The prepared native image load request is malformed.", nil);
	}
	struct stat rootPathStat;
	struct stat rootDescriptorStat;
	struct stat contentPathStat;
	struct stat contentDescriptorStat;
	struct stat executablePathStat;
	struct stat executableDescriptorStat;
	struct stat expectedExecutableStat = preparedImage.executableStat;
	NSURL *contentURL = [preparedImage.stageRootURL
		URLByAppendingPathComponent:preparedImage.contentSHA256 isDirectory:YES];
	BOOL pinned = lstat(preparedImage.stageRootURL.fileSystemRepresentation, &rootPathStat) == 0 &&
		fstat(preparedImage.rootDescriptor, &rootDescriptorStat) == 0 &&
		rootPathStat.st_dev == preparedImage.rootDevice && rootPathStat.st_ino == preparedImage.rootInode &&
		rootDescriptorStat.st_dev == preparedImage.rootDevice && rootDescriptorStat.st_ino == preparedImage.rootInode &&
		(rootPathStat.st_mode & 0777) == 0700 && (rootDescriptorStat.st_mode & 0777) == 0700 &&
		lstat(contentURL.fileSystemRepresentation, &contentPathStat) == 0 &&
		fstat(preparedImage.contentDescriptor, &contentDescriptorStat) == 0 &&
		contentPathStat.st_dev == preparedImage.contentDevice &&
		contentPathStat.st_ino == preparedImage.contentInode &&
		contentDescriptorStat.st_dev == preparedImage.contentDevice &&
		contentDescriptorStat.st_ino == preparedImage.contentInode &&
		(contentPathStat.st_mode & 0777) == 0700 && (contentDescriptorStat.st_mode & 0777) == 0700 &&
		lstat(preparedImage.stagedExecutableURL.fileSystemRepresentation, &executablePathStat) == 0 &&
		fstat(preparedImage.executableDescriptor, &executableDescriptorStat) == 0 &&
		BTPluginStatsMatch(&expectedExecutableStat, &executableDescriptorStat) &&
		executablePathStat.st_dev == executableDescriptorStat.st_dev &&
		executablePathStat.st_ino == executableDescriptorStat.st_ino &&
		BTPluginHashDescriptor(preparedImage.executableDescriptor, preparedImage.executableSize,
			preparedImage.executableSHA256, preparedImage.executableRelativePath, error);
	if (!pinned) {
		if (error && !*error)
			BTPluginStageFail(error, @"The private staged image changed before native mapping.",
				preparedImage.executableRelativePath, nil);
		return NO;
	}

	@synchronized ([BTPluginNativeImageLoader class]) {
		if ([BTPluginProcessMappedIdentities() containsObject:preparedImage.contentSHA256])
			return BTPluginRuntimeFail(error, @"The native plug-in image is already mapped for this process.", nil);
		[BTPluginProcessMappedIdentities() addObject:preparedImage.contentSHA256];
	}

	dlerror();
	void *handle = dlopen(preparedImage.stagedExecutableURL.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
	if (!handle) {
		@synchronized ([BTPluginNativeImageLoader class]) {
			[BTPluginProcessMappedIdentities() removeObject:preparedImage.contentSHA256];
		}
		const char *message = dlerror();
		NSString *description = message ? [[NSString alloc] initWithBytes:message
			length:MIN(strnlen(message, 1024), (size_t)1024) encoding:NSUTF8StringEncoding] : nil;
		return BTPluginRuntimeFail(error,
			description.length > 0 ? [NSString stringWithFormat:@"The platform could not map the verified native plug-in: %@", description] :
			@"The platform could not map the verified native plug-in.", nil);
	}
	// There is intentionally no dlclose path. Even a failed entry/registration
	// may have installed Objective-C classes or callbacks during initialization.
	preparedImage.mapped = YES;
	@synchronized ([BTPluginNativeImageLoader class]) {
		[BTPluginProcessMappedHandles() addObject:[NSValue valueWithPointer:handle]];
		[BTPluginProcessPinnedImages() addObject:preparedImage];
	}

	dlerror();
	BTPluginEntryPointV1 entryPoint = (BTPluginEntryPointV1)dlsym(handle, BT_PLUGIN_ENTRY_POINT_SYMBOL_V1);
	const char *symbolError = dlerror();
	if (!entryPoint || symbolError)
		return BTPluginRuntimeFail(error, @"The mapped native plug-in does not expose its verified entry point.", nil);

	const BTPluginDescriptorV1 *descriptor = NULL;
	@try {
		descriptor = entryPoint();
	} @catch (NSException *exception) {
		return BTPluginRuntimeFail(error,
			[NSString stringWithFormat:@"The native plug-in entry point raised %@.", exception.name], nil);
	}
	if (!descriptor || descriptor->structSize < BT_PLUGIN_DESCRIPTOR_V1_MINIMUM_SIZE ||
		descriptor->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		descriptor->minimumHostABIVersion > BT_PLUGIN_ABI_VERSION_1 ||
		descriptor->maximumHostABIVersion < BT_PLUGIN_ABI_VERSION_1 || !descriptor->registerPlugin ||
		!BTPluginNativeStringMatches(descriptor->pluginIdentifier, pluginIdentifier) ||
		!BTPluginNativeStringMatches(descriptor->pluginVersion, pluginVersion)) {
		return BTPluginRuntimeFail(error,
			@"The native plug-in descriptor does not match its verified manifest identity or host ABI.", nil);
	}
	return BTRegisterPluginDescriptorV1(descriptor, registry, declaredExtensionPoints, error);
}

- (BOOL)loadImageAtURL:(NSURL *)executableURL
	 expectedPluginIdentifier:(NSString *)pluginIdentifier
		  expectedPluginVersion:(NSString *)pluginVersion
	 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
						 registry:(BTPluginRegistry *)registry
							 error:(NSError **)error {
	BTPluginPreparedNativeImage *preparedImage = [self bt_prepareLooseImageAtURL:executableURL error:error];
	if (!preparedImage)
		return NO;
	return [self loadPreparedImage:preparedImage expectedPluginIdentifier:pluginIdentifier
		expectedPluginVersion:pluginVersion declaredExtensionPoints:declaredExtensionPoints
		registry:registry error:error];
}

@end
