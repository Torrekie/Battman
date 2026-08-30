//
//  BTPluginApplicationDataStore.m
//  Battman
//

#import "BTPluginApplicationDataStore.h"

#import <CommonCrypto/CommonDigest.h>
#import <dirent.h>
#import <fcntl.h>
#import <limits.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"

static BOOL BTPluginDataStoreFail(NSError **error, NSString *description,
	NSString *relativePath, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorImport,
			description, relativePath, underlyingError);
	return NO;
}

static BOOL BTPluginDataDirectoryModeIsSafe(mode_t mode) {
	return S_ISDIR(mode) && (mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) == 0 &&
		(mode & (S_IRUSR | S_IWUSR | S_IXUSR)) == (S_IRUSR | S_IWUSR | S_IXUSR);
}

static BOOL BTPluginDataFileModeMatchesClass(mode_t mode, NSString *modeClass) {
	if (!S_ISREG(mode) || (mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0 ||
		(mode & S_IRUSR) == 0)
		return NO;
	BOOL executable = (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0;
	return executable == [modeClass isEqualToString:@"executable"];
}

static NSString *BTPluginDataHexDigest(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *output = [NSMutableData dataWithLength:length * 2];
	char *characters = output.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

static int BTPluginDataOpenDirectoryPath(int rootDescriptor, NSString *relativeDirectoryPath,
	BOOL create, NSError **error) {
	int current = dup(rootDescriptor);
	if (current < 0) {
		BTPluginDataStoreFail(error, @"An installation directory descriptor could not be duplicated.",
			relativeDirectoryPath, nil);
		return -1;
	}
	if (relativeDirectoryPath.length == 0)
		return current;
	for (NSString *component in [relativeDirectoryPath componentsSeparatedByString:@"/"]) {
		const char *name = component.fileSystemRepresentation;
		if (create && mkdirat(current, name, 0755) != 0 && errno != EEXIST) {
			int savedErrno = errno;
			close(current);
			BTPluginDataStoreFail(error, @"A package staging directory could not be created.",
				relativeDirectoryPath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return -1;
		}
		int next = openat(current, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
		if (next < 0) {
			int savedErrno = errno;
			close(current);
			BTPluginDataStoreFail(error, @"A package directory could not be opened without following links.",
				relativeDirectoryPath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return -1;
		}
		struct stat directoryStat;
		if (fstat(next, &directoryStat) != 0 || !S_ISDIR(directoryStat.st_mode) ||
			(directoryStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0) {
			close(next);
			close(current);
			BTPluginDataStoreFail(error, @"A package directory has unsafe type or permissions.",
				relativeDirectoryPath, nil);
			return -1;
		}
		close(current);
		current = next;
	}
	return current;
}

static BOOL BTPluginDataCopyVerifiedFile(int sourceRootDescriptor, int destinationRootDescriptor,
	BTPluginInspectedFile *expectedFile, NSError **error) {
	NSString *relativePath = expectedFile.relativePath;
	NSString *parentPath = relativePath.stringByDeletingLastPathComponent;
	if ([parentPath isEqualToString:@"."])
		parentPath = @"";
	int sourceParent = BTPluginDataOpenDirectoryPath(sourceRootDescriptor, parentPath, NO, error);
	if (sourceParent < 0)
		return NO;
	int destinationParent = BTPluginDataOpenDirectoryPath(destinationRootDescriptor, parentPath, YES, error);
	if (destinationParent < 0) {
		close(sourceParent);
		return NO;
	}
	const char *fileName = relativePath.lastPathComponent.fileSystemRepresentation;
	int source = openat(sourceParent, fileName, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (source < 0) {
		int savedErrno = errno;
		close(sourceParent);
		close(destinationParent);
		return BTPluginDataStoreFail(error, @"A verified package file could not be reopened safely.",
			relativePath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	struct stat before;
	if (fstat(source, &before) != 0 || before.st_nlink != 1 || before.st_size < 0 ||
		(uint64_t)before.st_size != expectedFile.fileSize ||
		!BTPluginDataFileModeMatchesClass(before.st_mode, expectedFile.modeClass)) {
		close(source);
		close(sourceParent);
		close(destinationParent);
		return BTPluginDataStoreFail(error, @"A verified source file changed before installation copying.",
			relativePath, nil);
	}
	int destination = openat(destinationParent, fileName,
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (destination < 0) {
		int savedErrno = errno;
		close(source);
		close(sourceParent);
		close(destinationParent);
		return BTPluginDataStoreFail(error, @"A staging file could not be created exclusively.",
			relativePath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}

	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t total = 0;
	BOOL copied = YES;
	while (total < expectedFile.fileSize) {
		NSUInteger wanted = (NSUInteger)MIN((uint64_t)sizeof(buffer), expectedFile.fileSize - total);
		ssize_t count = read(source, buffer, wanted);
		if (count <= 0 || (NSUInteger)count != wanted) {
			copied = NO;
			break;
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		NSUInteger written = 0;
		while (written < (NSUInteger)count) {
			ssize_t writeCount = write(destination, buffer + written, (NSUInteger)count - written);
			if (writeCount <= 0) {
				copied = NO;
				break;
			}
			written += (NSUInteger)writeCount;
		}
		if (!copied)
			break;
		total += (uint64_t)count;
	}
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	struct stat after;
	copied = copied && total == expectedFile.fileSize && fstat(source, &after) == 0 &&
		before.st_dev == after.st_dev && before.st_ino == after.st_ino && before.st_size == after.st_size &&
		before.st_mode == after.st_mode && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
		before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec &&
		before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec &&
		before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec &&
		[BTPluginDataHexDigest(digest, sizeof(digest)) isEqualToString:expectedFile.sha256];
	mode_t destinationMode = [expectedFile.modeClass isEqualToString:@"executable"] ? 0755 : 0644;
	copied = copied && fchmod(destination, destinationMode) == 0 && fsync(destination) == 0;
	close(destination);
	close(source);
	close(sourceParent);
	close(destinationParent);
	if (!copied)
		return BTPluginDataStoreFail(error, @"A source file changed or failed its streaming hash while being copied.",
			relativePath, nil);
	return YES;
}

static BOOL BTPluginDataSyncCopiedDirectories(int rootDescriptor,
	NSArray<BTPluginInspectedFile *> *files, NSError **error) {
	NSMutableSet<NSString *> *directoryPaths = [NSMutableSet setWithObject:@""];
	for (BTPluginInspectedFile *file in files) {
		NSString *path = file.relativePath.stringByDeletingLastPathComponent;
		if ([path isEqualToString:@"."])
			path = @"";
		while (path.length > 0) {
			[directoryPaths addObject:path];
			NSString *parent = path.stringByDeletingLastPathComponent;
			path = [parent isEqualToString:@"."] ? @"" : parent;
		}
	}
	NSArray<NSString *> *ordered = [directoryPaths.allObjects sortedArrayUsingComparator:
		^NSComparisonResult(NSString *left, NSString *right) {
			NSUInteger leftDepth = left.length == 0 ? 0 : [left componentsSeparatedByString:@"/"].count;
			NSUInteger rightDepth = right.length == 0 ? 0 : [right componentsSeparatedByString:@"/"].count;
			if (leftDepth != rightDepth)
				return leftDepth > rightDepth ? NSOrderedAscending : NSOrderedDescending;
			return [left compare:right options:NSLiteralSearch];
		}];
	for (NSString *path in ordered) {
		int directory = BTPluginDataOpenDirectoryPath(rootDescriptor, path, NO, error);
		if (directory < 0)
			return NO;
		BOOL synced = fsync(directory) == 0;
		int savedErrno = errno;
		close(directory);
		if (!synced)
			return BTPluginDataStoreFail(error,
				@"A prepared package directory could not be synchronized.", path,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	return YES;
}

static BOOL BTPluginDataSyncRootURL(NSURL *rootURL) {
	int root = open(rootURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (root < 0)
		return NO;
	int result = fsync(root);
	int savedErrno = errno;
	close(root);
	if (result != 0)
		errno = savedErrno;
	return result == 0;
}

static void BTPluginDataRemoveOwnedURL(NSURL *url, NSURL *rootURL) {
	NSString *rootPrefix = [rootURL.path stringByAppendingString:@"/"];
	if (url.isFileURL && [url.path hasPrefix:rootPrefix] &&
		[[NSFileManager defaultManager] removeItemAtURL:url error:NULL])
		BTPluginDataSyncRootURL(rootURL);
}

static BOOL BTPluginDataTransactionIdentifierIsValid(NSString *identifier) {
	return [identifier isKindOfClass:[NSString class]] && identifier.length == 36 &&
		[identifier isEqualToString:identifier.lowercaseString] &&
		[[NSUUID alloc] initWithUUIDString:identifier] != nil;
}

static NSString *BTPluginDataTransactionStagingName(NSString *identifier) {
	return [NSString stringWithFormat:@".transaction-%@.battman", identifier];
}

static NSString *BTPluginDataTransactionRemovingName(NSString *identifier) {
	return [NSString stringWithFormat:@".removing-%@.battman", identifier];
}

static NSString *BTPluginDataTransactionIdentifierFromHiddenName(NSString *name) {
	NSString *prefix = nil;
	if ([name hasPrefix:@".transaction-"])
		prefix = @".transaction-";
	else if ([name hasPrefix:@".removing-"])
		prefix = @".removing-";
	else
		return nil;
	if (![name hasSuffix:@".battman"] || name.length != prefix.length + 36 + @".battman".length)
		return nil;
	NSString *identifier = [name substringWithRange:NSMakeRange(prefix.length, 36)];
	return BTPluginDataTransactionIdentifierIsValid(identifier) ? identifier : nil;
}

static BOOL BTPluginDataPathIsDirectoryOwned(NSURL *url) {
	struct stat value;
	return lstat(url.fileSystemRepresentation, &value) == 0 && S_ISDIR(value.st_mode) &&
		value.st_uid == geteuid() &&
		(value.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) == 0;
}

static BOOL BTPluginDataRemovalStatMatches(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_mode == right->st_mode && left->st_uid == right->st_uid &&
		left->st_size == right->st_size &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static int BTPluginDataOpenOwnedRoot(NSURL *rootURL, NSError **error) {
	int root = open(rootURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	struct stat rootStat;
	if (root >= 0 && fstat(root, &rootStat) == 0 &&
		BTPluginDataDirectoryModeIsSafe(rootStat.st_mode) && rootStat.st_uid == geteuid())
		return root;
	int savedErrno = root < 0 ? errno : 0;
	if (root >= 0)
		close(root);
	BTPluginDataStoreFail(error, @"The private app-data plug-in root could not be opened with safe ownership.",
		nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	return -1;
}

static BOOL BTPluginDataRemovalNameIsSafe(NSString *name) {
	if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 255 ||
		![name isEqualToString:[name precomposedStringWithCanonicalMapping]] ||
		[name isEqualToString:@"."] || [name isEqualToString:@".."] ||
		[name rangeOfString:@"/"].location != NSNotFound ||
		[name rangeOfString:@"\\"].location != NSNotFound)
		return NO;
	for (NSUInteger index = 0; index < name.length; index++) {
		unichar character = [name characterAtIndex:index];
		if (character < 0x20 || character == 0x7f)
			return NO;
	}
	return YES;
}

static BOOL BTPluginDataRemovalObjectIdentityMatches(const struct stat *left,
	const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_mode == right->st_mode && left->st_uid == right->st_uid;
}

static BOOL BTPluginDataRemovePinnedDirectoryContents(int directoryDescriptor,
	NSUInteger depth, NSUInteger *entryCount, NSError **error) {
	if (depth > 64)
		return BTPluginDataStoreFail(error, @"The inspected removal tree exceeds its bounded depth.", nil, nil);
	int enumerationDescriptor = dup(directoryDescriptor);
	DIR *directory = enumerationDescriptor >= 0 ? fdopendir(enumerationDescriptor) : NULL;
	if (!directory) {
		int savedErrno = errno;
		if (enumerationDescriptor >= 0)
			close(enumerationDescriptor);
		return BTPluginDataStoreFail(error, @"The inspected removal directory could not be enumerated by descriptor.",
			nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	int enumerationError = 0;
	while (YES) {
		errno = 0;
		struct dirent *entry = readdir(directory);
		if (!entry) {
			enumerationError = errno;
			break;
		}
		if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
			continue;
		NSString *name = [[NSString alloc] initWithBytes:entry->d_name
			length:strlen(entry->d_name) encoding:NSUTF8StringEncoding];
		if (!BTPluginDataRemovalNameIsSafe(name) || ++*entryCount > 1024) {
			enumerationError = EOVERFLOW;
			break;
		}
		[names addObject:name];
	}
	closedir(directory);
	if (enumerationError != 0)
		return BTPluginDataStoreFail(error, @"The inspected removal tree changed or exceeded its entry bound.",
			nil, [NSError errorWithDomain:NSPOSIXErrorDomain code:enumerationError userInfo:nil]);
	[names sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
		return [left compare:right options:NSLiteralSearch];
	}];
	for (NSString *name in names) {
		struct stat namedStat;
		if (fstatat(directoryDescriptor, name.fileSystemRepresentation, &namedStat,
			AT_SYMLINK_NOFOLLOW) != 0) {
			int savedErrno = errno;
			return BTPluginDataStoreFail(error, @"An inspected removal entry changed before descriptor opening.",
				name, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		}
		if (namedStat.st_uid != geteuid() ||
			(namedStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0)
			return BTPluginDataStoreFail(error, @"An inspected removal entry has unsafe ownership or permissions.",
				name, nil);
		if (S_ISDIR(namedStat.st_mode)) {
			int child = openat(directoryDescriptor, name.fileSystemRepresentation,
				O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
			struct stat openedStat;
			if (child < 0 || fstat(child, &openedStat) != 0 ||
				!BTPluginDataRemovalObjectIdentityMatches(&namedStat, &openedStat) ||
				!BTPluginDataDirectoryModeIsSafe(openedStat.st_mode)) {
				int savedErrno = child < 0 ? errno : 0;
				if (child >= 0)
					close(child);
				return BTPluginDataStoreFail(error, @"An inspected removal directory changed before traversal.",
					name, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			}
			if (!BTPluginDataRemovePinnedDirectoryContents(child, depth + 1, entryCount, error)) {
				close(child);
				return NO;
			}
			struct stat currentStat;
			BOOL sameName = fstatat(directoryDescriptor, name.fileSystemRepresentation, &currentStat,
				AT_SYMLINK_NOFOLLOW) == 0 &&
				BTPluginDataRemovalObjectIdentityMatches(&openedStat, &currentStat);
			if (!sameName || unlinkat(directoryDescriptor, name.fileSystemRepresentation, AT_REMOVEDIR) != 0) {
				int savedErrno = sameName ? errno : ESTALE;
				close(child);
				return BTPluginDataStoreFail(error, @"An inspected removal directory changed before unlinking.",
					name, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			}
			close(child);
		} else if (S_ISREG(namedStat.st_mode) && namedStat.st_nlink == 1 &&
			(namedStat.st_mode & S_IRUSR) != 0) {
			int file = openat(directoryDescriptor, name.fileSystemRepresentation,
				O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
			struct stat openedStat;
			if (file < 0 || fstat(file, &openedStat) != 0 ||
				!BTPluginDataRemovalObjectIdentityMatches(&namedStat, &openedStat)) {
				int savedErrno = file < 0 ? errno : 0;
				if (file >= 0)
					close(file);
				return BTPluginDataStoreFail(error, @"An inspected removal file changed before unlinking.",
					name, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			}
			struct stat currentStat;
			BOOL sameName = fstatat(directoryDescriptor, name.fileSystemRepresentation, &currentStat,
				AT_SYMLINK_NOFOLLOW) == 0 &&
				BTPluginDataRemovalObjectIdentityMatches(&openedStat, &currentStat);
			if (!sameName || unlinkat(directoryDescriptor, name.fileSystemRepresentation, 0) != 0) {
				int savedErrno = sameName ? errno : ESTALE;
				close(file);
				return BTPluginDataStoreFail(error, @"An inspected removal file changed before unlinking.",
					name, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			}
			close(file);
		} else {
			return BTPluginDataStoreFail(error,
				@"The pinned removal tree contains a non-regular, linked, or unreadable entry.", name, nil);
		}
	}
	if (fsync(directoryDescriptor) != 0) {
		int savedErrno = errno;
		return BTPluginDataStoreFail(error, @"The pinned removal directory could not be synchronized.", nil,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	return YES;
}

static BOOL BTPluginDataRemovePinnedOwnedDirectory(int parentDescriptor, NSString *childName,
	const struct stat *expectedStat, NSError **error) {
	int directory = openat(parentDescriptor, childName.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	struct stat openedStat;
	if (directory < 0 || fstat(directory, &openedStat) != 0 ||
		!BTPluginDataRemovalStatMatches(expectedStat, &openedStat) ||
		openedStat.st_uid != geteuid() || !BTPluginDataDirectoryModeIsSafe(openedStat.st_mode)) {
		int savedErrno = directory < 0 ? errno : ESTALE;
		if (directory >= 0)
			close(directory);
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"The exact removal tombstone changed before descriptor-pinned cleanup.", childName,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		return NO;
	}
	NSUInteger entryCount = 0;
	if (!BTPluginDataRemovePinnedDirectoryContents(directory, 0, &entryCount, error)) {
		close(directory);
		return NO;
	}
	struct stat currentStat;
	BOOL sameName = fstatat(parentDescriptor, childName.fileSystemRepresentation, &currentStat,
		AT_SYMLINK_NOFOLLOW) == 0 &&
		BTPluginDataRemovalObjectIdentityMatches(&openedStat, &currentStat);
	if (!sameName || unlinkat(parentDescriptor, childName.fileSystemRepresentation, AT_REMOVEDIR) != 0) {
		int savedErrno = sameName ? errno : ESTALE;
		close(directory);
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"The exact removal tombstone changed before its final unlink.", childName,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		return NO;
	}
	close(directory);
	if (fsync(parentDescriptor) != 0) {
		int savedErrno = errno;
		return BTPluginDataStoreFail(error, @"The exact removal tombstone cleanup could not be synchronized.",
			childName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	return YES;
}

@interface BTPluginApplicationDataStore ()
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@property (nonatomic, strong) BTPluginPackageStructuralVerifier *removalStructuralVerifier;
- (nullable BTPluginPackageInspection *)bt_inspectPackageForRemovalAtURL:(NSURL *)packageURL
	childName:(NSString *)childName
	claimedPluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString *)expectedPackageSHA256
	rootDescriptor:(int)rootDescriptor
	inspectedStat:(struct stat * _Nullable)inspectedStat
	error:(NSError **)error;
@end

@implementation BTPluginApplicationDataStore

- (instancetype)initWithRootURL:(NSURL *)rootURL packageVerifier:(BTPluginPackageVerifier *)packageVerifier
							 error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (![rootURL isKindOfClass:[NSURL class]] || !rootURL.isFileURL ||
		![packageVerifier isKindOfClass:[BTPluginPackageVerifier class]]) {
		BTPluginDataStoreFail(error, @"App-data installation requires a local root and complete verifier.", nil, nil);
		return nil;
	}
	NSError *directoryError = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtURL:rootURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0700 } error:&directoryError] ||
		![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0700 }
		ofItemAtPath:rootURL.path error:&directoryError]) {
		BTPluginDataStoreFail(error, @"The private app-data plug-in directory could not be prepared.", nil,
			directoryError);
		return nil;
	}
	char resolved[PATH_MAX];
	struct stat rootStat;
	if (!realpath(rootURL.fileSystemRepresentation, resolved) || lstat(resolved, &rootStat) != 0 ||
		!BTPluginDataDirectoryModeIsSafe(rootStat.st_mode) || rootStat.st_uid != geteuid()) {
		BTPluginDataStoreFail(error, @"The app-data plug-in root is not a private owned directory.", nil, nil);
		return nil;
	}
	_rootURL = [NSURL fileURLWithFileSystemRepresentation:resolved isDirectory:YES relativeToURL:nil];
	_packageVerifier = packageVerifier;
	_removalStructuralVerifier = [BTPluginPackageStructuralVerifier new];
	return self;
}

- (BTPluginPackageInspection *)bt_inspectPackageForRemovalAtURL:(NSURL *)packageURL
	childName:(NSString *)childName claimedPluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString *)expectedPackageSHA256 rootDescriptor:(int)rootDescriptor
	inspectedStat:(struct stat *)inspectedStat error:(NSError **)error {
	if (rootDescriptor < 0 || !BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(expectedPackageSHA256) ||
		![packageURL isKindOfClass:[NSURL class]] || !packageURL.isFileURL ||
		![childName isKindOfClass:[NSString class]] || childName.length == 0 || childName.length > 255 ||
		[childName rangeOfString:@"/"].location != NSNotFound ||
		[childName rangeOfString:@"\\"].location != NSNotFound) {
		BTPluginDataStoreFail(error, @"The exact app-data removal inspection request is invalid.", nil, nil);
		return nil;
	}
	NSURL *expectedURL = [self.rootURL URLByAppendingPathComponent:childName isDirectory:YES];
	NSURL *selectedURL = packageURL.URLByStandardizingPath;
	char resolvedSelectedParent[PATH_MAX];
	BOOL selectedParentIsRoot = realpath(selectedURL.URLByDeletingLastPathComponent.fileSystemRepresentation,
		resolvedSelectedParent) != NULL &&
		strcmp(resolvedSelectedParent, self.rootURL.fileSystemRepresentation) == 0;
	if (![selectedURL.lastPathComponent isEqualToString:childName] || !selectedParentIsRoot) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorUnsafePath,
				@"The removal selection is not the exact canonical app-data path.", childName, nil);
		return nil;
	}
	// Discovery may preserve a system path alias such as /var while the store
	// keeps realpath's /private/var spelling. Once the selected parent descriptor
	// resolves to this exact owned root, inspect only the store-derived child URL.
	NSURL *standardURL = expectedURL;

	struct stat rootBefore;
	struct stat descriptorBefore;
	struct stat pathBefore;
	if (fstat(rootDescriptor, &rootBefore) != 0 ||
		!BTPluginDataDirectoryModeIsSafe(rootBefore.st_mode) || rootBefore.st_uid != geteuid() ||
		fstatat(rootDescriptor, childName.fileSystemRepresentation, &descriptorBefore,
			AT_SYMLINK_NOFOLLOW) != 0 ||
		lstat(standardURL.fileSystemRepresentation, &pathBefore) != 0 ||
		!BTPluginDataDirectoryModeIsSafe(descriptorBefore.st_mode) ||
		descriptorBefore.st_uid != geteuid() ||
		!BTPluginDataRemovalStatMatches(&descriptorBefore, &pathBefore)) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorUnsafePath,
				@"The removal target is not one safe owned app-data directory.", childName, nil);
		return nil;
	}

	BTPluginPackageInspection *inspection = [self.removalStructuralVerifier
		inspectPackageAtURL:standardURL error:error];
	if (!inspection)
		return nil;
	struct stat rootAfter;
	struct stat descriptorAfter;
	struct stat pathAfter;
	if (fstat(rootDescriptor, &rootAfter) != 0 ||
		rootBefore.st_dev != rootAfter.st_dev || rootBefore.st_ino != rootAfter.st_ino ||
		rootBefore.st_mode != rootAfter.st_mode || rootBefore.st_uid != rootAfter.st_uid ||
		fstatat(rootDescriptor, childName.fileSystemRepresentation, &descriptorAfter,
			AT_SYMLINK_NOFOLLOW) != 0 ||
		lstat(standardURL.fileSystemRepresentation, &pathAfter) != 0 ||
		!BTPluginDataRemovalStatMatches(&descriptorBefore, &descriptorAfter) ||
		!BTPluginDataRemovalStatMatches(&descriptorAfter, &pathAfter)) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"The app-data removal target changed during structural inspection.", childName, nil);
		return nil;
	}
	if (![inspection.packageURL.path isEqualToString:standardURL.path] ||
		![inspection.manifest.pluginIdentifier isEqualToString:pluginIdentifier]) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorUnsafePath,
				@"The structurally inspected package identity does not match its app-data path.", childName, nil);
		return nil;
	}
	if (![inspection.packageSHA256 isEqualToString:expectedPackageSHA256]) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"The installed app-data bytes no longer match the exact removal selection.", childName, nil);
		return nil;
	}
	if (inspectedStat)
		*inspectedStat = descriptorAfter;
	return inspection;
}

- (BTPluginPackageInspection *)inspectInstalledPackageForRemovalAtURL:(NSURL *)packageURL
	claimedPluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString *)expectedPackageSHA256 error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(expectedPackageSHA256)) {
		BTPluginDataStoreFail(error, @"Removal requires an exact plug-in identifier and package digest.", nil, nil);
		return nil;
	}
	NSString *childName = [pluginIdentifier stringByAppendingPathExtension:@"battman"];
	int root = BTPluginDataOpenOwnedRoot(self.rootURL, error);
	if (root < 0)
		return nil;
	BTPluginPackageInspection *inspection = [self bt_inspectPackageForRemovalAtURL:packageURL
		childName:childName claimedPluginIdentifier:pluginIdentifier
		expectedPackageSHA256:expectedPackageSHA256 rootDescriptor:root
		inspectedStat:NULL error:error];
	close(root);
	return inspection;
}

- (BTPluginVerifiedPackage *)installedPackageForPluginIdentifier:(NSString *)pluginIdentifier
	error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier)) {
		BTPluginDataStoreFail(error, @"The app-data plug-in identifier is invalid.", nil, nil);
		return nil;
	}
	NSURL *packageURL = [self.rootURL URLByAppendingPathComponent:
		[pluginIdentifier stringByAppendingPathExtension:@"battman"] isDirectory:YES];
	struct stat value;
	if (lstat(packageURL.fileSystemRepresentation, &value) != 0) {
		if (errno == ENOENT)
			return nil;
		int savedErrno = errno;
		BTPluginDataStoreFail(error, @"The installed app-data plug-in could not be inspected safely.",
			packageURL.lastPathComponent,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		return nil;
	}
	if (!S_ISDIR(value.st_mode) || value.st_uid != geteuid() ||
		(value.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0) {
		BTPluginDataStoreFail(error, @"The installed app-data plug-in has unsafe type or ownership.",
			packageURL.lastPathComponent, nil);
		return nil;
	}
	BTPluginVerifiedPackage *verified = [self.packageVerifier verifyPackageAtURL:packageURL
		developerMode:NO error:error];
	if (verified && ![verified.packageInspection.manifest.pluginIdentifier isEqualToString:pluginIdentifier]) {
		BTPluginDataStoreFail(error, @"The installed app-data plug-in identity does not match its path.",
			packageURL.lastPathComponent, nil);
		return nil;
	}
	return verified;
}

- (BOOL)prepareQuarantinedPackage:(BTPluginQuarantinedPackage *)quarantinedPackage
	transactionIdentifier:(NSString *)transactionIdentifier developerMode:(BOOL)developerMode
	error:(NSError **)error {
	if (![quarantinedPackage isKindOfClass:[BTPluginQuarantinedPackage class]] ||
		!BTPluginDataTransactionIdentifierIsValid(transactionIdentifier))
		return BTPluginDataStoreFail(error, @"The app-data transaction preparation request is invalid.", nil, nil);
	BTPluginVerifiedPackage *freshSource = [self.packageVerifier
		verifyPackageAtURL:quarantinedPackage.packageURL developerMode:developerMode error:error];
	if (!freshSource || !freshSource.isApprovedForActivation ||
		![freshSource.packageInspection.packageSHA256
			isEqualToString:quarantinedPackage.verification.packageInspection.packageSHA256]) {
		if (freshSource && error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"The quarantine package changed before transaction preparation.", nil, nil);
		return NO;
	}
	NSString *stagingName = BTPluginDataTransactionStagingName(transactionIdentifier);
	NSURL *stagingURL = [self.rootURL URLByAppendingPathComponent:stagingName isDirectory:YES];
	if ([NSFileManager.defaultManager fileExistsAtPath:stagingURL.path]) {
		if (!BTPluginDataPathIsDirectoryOwned(stagingURL))
			return BTPluginDataStoreFail(error, @"An existing app-data transaction staging path is unsafe.", stagingName, nil);
		BTPluginVerifiedPackage *existing = [self.packageVerifier verifyPackageAtURL:stagingURL
			developerMode:developerMode error:error];
		if (existing && [existing.packageInspection.packageSHA256
			isEqualToString:freshSource.packageInspection.packageSHA256])
			return YES;
		return BTPluginDataStoreFail(error, @"An app-data transaction staging path contains different bytes.",
			stagingName, nil);
	}
	NSFileManager *manager = NSFileManager.defaultManager;
	NSError *directoryError = nil;
	if (![manager createDirectoryAtURL:stagingURL withIntermediateDirectories:NO
		attributes:@{ NSFilePosixPermissions: @0700 } error:&directoryError])
		return BTPluginDataStoreFail(error, @"The app-data transaction staging directory could not be created.",
			stagingName, directoryError);
	int root = open(self.rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	int sourceRoot = open(freshSource.packageInspection.packageURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	int stagingRoot = open(stagingURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (root < 0 || sourceRoot < 0 || stagingRoot < 0) {
		int savedErrno = errno;
		if (root >= 0) close(root);
		if (sourceRoot >= 0) close(sourceRoot);
		if (stagingRoot >= 0) close(stagingRoot);
		BTPluginDataRemoveOwnedURL(stagingURL, self.rootURL);
		return BTPluginDataStoreFail(error, @"The app-data transaction descriptors could not be opened safely.",
			stagingName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	NSArray<BTPluginInspectedFile *> *files = [freshSource.packageInspection.filesByPath.allValues
		sortedArrayUsingComparator:^NSComparisonResult(BTPluginInspectedFile *left, BTPluginInspectedFile *right) {
		return [left.relativePath compare:right.relativePath options:NSLiteralSearch];
	}];
	BOOL copied = YES;
	for (BTPluginInspectedFile *file in files) {
		if (!BTPluginDataCopyVerifiedFile(sourceRoot, stagingRoot, file, error)) {
			copied = NO;
			break;
		}
	}
	copied = copied && fchmod(stagingRoot, 0755) == 0 &&
		BTPluginDataSyncCopiedDirectories(stagingRoot, files, error);
	close(sourceRoot);
	close(stagingRoot);
	if (copied)
		copied = fsync(root) == 0;
	close(root);
	if (!copied) {
		BTPluginDataRemoveOwnedURL(stagingURL, self.rootURL);
		if (error && !*error)
			BTPluginDataStoreFail(error, @"The verified package could not be prepared durably.", stagingName, nil);
		return NO;
	}
	BTPluginVerifiedPackage *staged = [self.packageVerifier verifyPackageAtURL:stagingURL
		developerMode:developerMode error:error];
	if (!staged || ![staged.packageInspection.packageSHA256
		isEqualToString:freshSource.packageInspection.packageSHA256]) {
		BTPluginDataRemoveOwnedURL(stagingURL, self.rootURL);
		if (error && !*error)
			BTPluginDataStoreFail(error, @"The prepared app-data package failed final verification.", stagingName, nil);
		return NO;
	}
	return YES;
}

- (BTPluginVerifiedPackage *)publishPreparedApplicationDataTransaction:
	(BTPluginApplicationDataTransaction *)transaction error:(NSError **)error {
	if (![transaction isKindOfClass:[BTPluginApplicationDataTransaction class]]) {
		BTPluginDataStoreFail(error, @"The app-data transaction to publish is invalid.", nil, nil);
		return nil;
	}
	NSString *pluginIdentifier = transaction.pluginIdentifier;
	NSString *finalName = [pluginIdentifier stringByAppendingPathExtension:@"battman"];
	NSURL *finalURL = [self.rootURL URLByAppendingPathComponent:finalName isDirectory:YES];
	NSURL *stagingURL = [self.rootURL URLByAppendingPathComponent:
		BTPluginDataTransactionStagingName(transaction.transactionIdentifier) isDirectory:YES];
	if (transaction.operation == BTPluginApplicationDataTransactionOperationRemove) {
		NSString *removingName = BTPluginDataTransactionRemovingName(transaction.transactionIdentifier);
		NSURL *removingURL = [self.rootURL URLByAppendingPathComponent:removingName isDirectory:YES];
		struct stat finalStat;
		struct stat removingStat;
		BOOL finalExists = lstat(finalURL.fileSystemRepresentation, &finalStat) == 0;
		int finalErrno = errno;
		BOOL removingExists = lstat(removingURL.fileSystemRepresentation, &removingStat) == 0;
		int removingErrno = errno;
		if ((!finalExists && finalErrno != ENOENT) || (!removingExists && removingErrno != ENOENT)) {
			BTPluginDataStoreFail(error, @"The app-data removal namespace could not be inspected safely.",
				finalName, nil);
			return nil;
		}
		if (finalExists) {
			if (![self inspectInstalledPackageForRemovalAtURL:finalURL
				claimedPluginIdentifier:pluginIdentifier
				expectedPackageSHA256:transaction.expectedPackageSHA256 error:error])
				return nil;
			if (removingExists) {
				BTPluginDataStoreFail(error,
					@"The app-data removal found both canonical bytes and a transaction tombstone.", finalName, nil);
				return nil;
			}
		} else if (removingExists) {
			int inspectionRoot = BTPluginDataOpenOwnedRoot(self.rootURL, error);
			if (inspectionRoot < 0)
				return nil;
			BTPluginPackageInspection *removingInspection = [self bt_inspectPackageForRemovalAtURL:removingURL
				childName:removingName claimedPluginIdentifier:pluginIdentifier
				expectedPackageSHA256:transaction.expectedPackageSHA256
				rootDescriptor:inspectionRoot inspectedStat:NULL error:error];
			close(inspectionRoot);
			if (!removingInspection)
				return nil;
		}
		int root = BTPluginDataOpenOwnedRoot(self.rootURL, error);
		if (root < 0) {
			return nil;
		}
		if (finalExists && renameatx_np(root, finalName.fileSystemRepresentation,
			root, removingName.fileSystemRepresentation, RENAME_EXCL) != 0) {
			int savedErrno = errno;
			close(root);
			BTPluginDataStoreFail(error, @"The app-data package could not be moved to its removal tombstone.",
				finalName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return nil;
			}
			BOOL synced = fsync(root) == 0;
			close(root);
		if (!synced) {
			BTPluginDataStoreFail(error, @"The app-data removal tombstone could not be synchronized.", finalName, nil);
				return nil;
			}
			struct stat retiredStat;
			if (lstat(removingURL.fileSystemRepresentation, &retiredStat) == 0) {
				int inspectionRoot = BTPluginDataOpenOwnedRoot(self.rootURL, error);
				if (inspectionRoot < 0)
					return nil;
				struct stat inspectedRetiredStat;
				BTPluginPackageInspection *retiredInspection = [self bt_inspectPackageForRemovalAtURL:removingURL
					childName:removingName claimedPluginIdentifier:pluginIdentifier
					expectedPackageSHA256:transaction.expectedPackageSHA256
					rootDescriptor:inspectionRoot inspectedStat:&inspectedRetiredStat error:error];
				BOOL removed = retiredInspection && BTPluginDataRemovePinnedOwnedDirectory(
					inspectionRoot, removingName, &inspectedRetiredStat, error);
				close(inspectionRoot);
				if (!removed)
					return nil;
			} else if (errno != ENOENT) {
				int savedErrno = errno;
				BTPluginDataStoreFail(error, @"The app-data removal tombstone could not be re-inspected.",
					removingName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
				return nil;
			}
			return nil;
		}
	struct stat finalStat;
	BOOL finalExists = lstat(finalURL.fileSystemRepresentation, &finalStat) == 0;
	int finalErrno = errno;
	if (!finalExists && finalErrno != ENOENT) {
		BTPluginDataStoreFail(error, @"The app-data publication target could not be inspected safely.",
			finalName, nil);
		return nil;
	}
	BTPluginVerifiedPackage *existing = finalExists ? [self.packageVerifier verifyPackageAtURL:finalURL
		developerMode:NO error:NULL] : nil;
	if (finalExists && !existing) {
		BTPluginDataStoreFail(error, @"The app-data publication found unverifiable canonical bytes.",
			finalName, nil);
		return nil;
	}
	BOOL existingIsTarget = existing && [existing.packageInspection.packageSHA256
		isEqualToString:transaction.targetPackageSHA256];
	BOOL existingIsExpected = existing && transaction.expectedPackageSHA256 &&
		[existing.packageInspection.packageSHA256 isEqualToString:transaction.expectedPackageSHA256];
	if (transaction.operation == BTPluginApplicationDataTransactionOperationInstall && existing && !existingIsTarget) {
		BTPluginDataStoreFail(error, @"A fresh app-data installation found unexpected existing bytes.", finalName, nil);
		return nil;
	}
	if (transaction.operation == BTPluginApplicationDataTransactionOperationUpdate && existing &&
		!existingIsExpected && !existingIsTarget) {
		BTPluginDataStoreFail(error, @"The app-data update found an unexpected installed digest.", finalName, nil);
		return nil;
	}
	BTPluginVerifiedPackage *alreadyPublished = existing &&
		[existing.packageInspection.packageSHA256 isEqualToString:transaction.targetPackageSHA256] ? existing : nil;
	if (!alreadyPublished) {
		if (!BTPluginDataPathIsDirectoryOwned(stagingURL)) {
			BTPluginDataStoreFail(error, @"The prepared app-data transaction path is missing or unsafe.",
				stagingURL.lastPathComponent, nil);
			return nil;
		}
		BTPluginVerifiedPackage *prepared = [self.packageVerifier verifyPackageAtURL:stagingURL
			developerMode:NO error:NULL];
		if (!prepared || ![prepared.packageInspection.packageSHA256
			isEqualToString:transaction.targetPackageSHA256]) {
			BTPluginDataStoreFail(error, @"The prepared app-data transaction bytes changed before publication.",
				stagingURL.lastPathComponent, nil);
			return nil;
		}
		int root = open(self.rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
		if (root < 0) {
			BTPluginDataStoreFail(error, @"The app-data publication root could not be opened safely.", finalName, nil);
			return nil;
		}
		BOOL replacing = existing != nil;
		int flags = replacing ? RENAME_SWAP : RENAME_EXCL;
		if (renameatx_np(root, stagingURL.lastPathComponent.fileSystemRepresentation,
			root, finalName.fileSystemRepresentation, flags) != 0) {
			int savedErrno = errno;
			close(root);
			BTPluginDataStoreFail(error, @"The prepared app-data package could not be published atomically.",
				finalName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return nil;
		}
		if (fsync(root) != 0) {
			close(root);
			BTPluginDataStoreFail(error, @"The published app-data package could not be synchronized.", finalName, nil);
			return nil;
		}
		close(root);
	}
	BTPluginVerifiedPackage *finalVerification = [self.packageVerifier verifyPackageAtURL:finalURL
		developerMode:NO error:error];
	if (!finalVerification || ![finalVerification.packageInspection.packageSHA256
		isEqualToString:transaction.targetPackageSHA256]) {
		BTPluginDataStoreFail(error, @"The published app-data package failed its target digest check.", finalName, nil);
		return nil;
	}
	// RENAME_SWAP leaves the displaced old package at the deterministic
	// transaction name.  The canonical target is already durable and verified,
	// so the displaced tree is now bounded garbage; remove it without ever
	// following a caller-controlled path.  Cleanup failure is intentionally not
	// allowed to turn a committed update into an activation rollback.  Startup
	// reconciliation retries it before discovery.
	if ([NSFileManager.defaultManager fileExistsAtPath:stagingURL.path] &&
		BTPluginDataPathIsDirectoryOwned(stagingURL)) {
		if ([NSFileManager.defaultManager removeItemAtURL:stagingURL error:NULL]) {
			int cleanupRoot = open(self.rootURL.fileSystemRepresentation,
				O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
			if (cleanupRoot >= 0) {
				(void)fsync(cleanupRoot);
				close(cleanupRoot);
			}
		}
	}
	return finalVerification;
}

- (BOOL)reconcileApplicationDataTransaction:(BTPluginApplicationDataTransaction *)transaction
	committed:(BOOL *)committed error:(NSError **)error {
	if (committed)
		*committed = NO;
	if (![transaction isKindOfClass:[BTPluginApplicationDataTransaction class]])
		return BTPluginDataStoreFail(error, @"The app-data transaction to reconcile is invalid.", nil, nil);
	NSString *finalName = [transaction.pluginIdentifier stringByAppendingPathExtension:@"battman"];
	NSURL *finalURL = [self.rootURL URLByAppendingPathComponent:finalName isDirectory:YES];
	NSURL *stagingURL = [self.rootURL URLByAppendingPathComponent:
		BTPluginDataTransactionStagingName(transaction.transactionIdentifier) isDirectory:YES];
	if (transaction.operation == BTPluginApplicationDataTransactionOperationRemove) {
		NSError *publishError = nil;
		(void)[self publishPreparedApplicationDataTransaction:transaction error:&publishError];
		// A removal publish can fail after moving the canonical tree (for
		// example, when the first directory fsync is interrupted).  Retry the
		// idempotent publish path once so a later successful fsync can establish
		// the durable commit; never clear the journal merely because the name is
		// absent while an unsafe tombstone or publish error remains.
		if (publishError) {
			NSError *retryError = nil;
			(void)[self publishPreparedApplicationDataTransaction:transaction error:&retryError];
			if (retryError) {
				if (error) *error = publishError ?: retryError;
				return NO;
			}
		}
		struct stat finalStat;
		if (lstat(finalURL.fileSystemRepresentation, &finalStat) == 0) {
			if (error) *error = publishError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
				@"The app-data removal did not retire the canonical package.", finalName, nil);
			return NO;
		}
		if (errno != ENOENT) {
			if (error) *error = publishError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
				@"The app-data removal target could not be inspected after publication.", finalName, nil);
			return NO;
		}
		NSURL *removingURL = [self.rootURL URLByAppendingPathComponent:
			BTPluginDataTransactionRemovingName(transaction.transactionIdentifier) isDirectory:YES];
		struct stat removingStat;
		if (lstat(removingURL.fileSystemRepresentation, &removingStat) == 0) {
			int inspectionRoot = BTPluginDataOpenOwnedRoot(self.rootURL, error);
			if (inspectionRoot < 0)
				return NO;
			struct stat inspectedRemovingStat;
			BTPluginPackageInspection *removingInspection = [self bt_inspectPackageForRemovalAtURL:removingURL
				childName:removingURL.lastPathComponent claimedPluginIdentifier:transaction.pluginIdentifier
				expectedPackageSHA256:transaction.expectedPackageSHA256
				rootDescriptor:inspectionRoot inspectedStat:&inspectedRemovingStat error:error];
			BOOL removed = removingInspection && BTPluginDataRemovePinnedOwnedDirectory(
				inspectionRoot, removingURL.lastPathComponent, &inspectedRemovingStat, error);
			close(inspectionRoot);
			if (!removed)
				return NO;
		} else if (errno != ENOENT) {
			int savedErrno = errno;
			return BTPluginDataStoreFail(error, @"The recovered app-data removal tombstone could not be inspected.",
				removingURL.lastPathComponent,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		}
		if (!BTPluginDataSyncRootURL(self.rootURL))
			return BTPluginDataStoreFail(error, @"The recovered app-data removal could not be made durable.",
				finalName, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
		if (committed) *committed = YES;
		return YES;
	}
	BTPluginVerifiedPackage *current = [self.packageVerifier verifyPackageAtURL:finalURL developerMode:NO error:NULL];
	if (current && [current.packageInspection.packageSHA256 isEqualToString:transaction.targetPackageSHA256]) {
		// A prior publish may have returned an error after rename (for example,
		// directory fsync failure).  Re-open and synchronize the parent before
		// clearing the Keychain journal; otherwise a crash can resurrect the old
		// canonical tree under the new activation record.
		if (!BTPluginDataSyncRootURL(self.rootURL))
			return BTPluginDataStoreFail(error, @"The committed app-data package could not be made durable during recovery.",
				finalName, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
		if ([NSFileManager.defaultManager fileExistsAtPath:stagingURL.path]) {
			NSError *cleanupError = nil;
			if (!BTPluginDataPathIsDirectoryOwned(stagingURL) ||
				![NSFileManager.defaultManager removeItemAtURL:stagingURL error:&cleanupError])
				return BTPluginDataStoreFail(error, @"The committed app-data staging tree could not be retired during recovery.",
					stagingURL.lastPathComponent, cleanupError);
			if (!BTPluginDataSyncRootURL(self.rootURL))
				return BTPluginDataStoreFail(error, @"The recovered app-data cleanup could not be synchronized.",
					stagingURL.lastPathComponent, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
		}
		if (committed) *committed = YES;
		return YES;
	}
	if ([NSFileManager.defaultManager fileExistsAtPath:stagingURL.path]) {
		BTPluginVerifiedPackage *staged = [self.packageVerifier verifyPackageAtURL:stagingURL developerMode:NO error:NULL];
		if (!staged || ![staged.packageInspection.packageSHA256 isEqualToString:transaction.targetPackageSHA256])
			return BTPluginDataStoreFail(error, @"The pending app-data transaction has unexpected staged bytes.",
				stagingURL.lastPathComponent, nil);
		BTPluginVerifiedPackage *published = [self publishPreparedApplicationDataTransaction:transaction error:error];
		if (published) {
			if (committed) *committed = YES;
			return YES;
		}
		return NO;
	}
	if (current && transaction.expectedPackageSHA256 &&
		[current.packageInspection.packageSHA256 isEqualToString:transaction.expectedPackageSHA256])
		return YES; // caller aborts the journal while the known old bytes remain.
	if (transaction.operation == BTPluginApplicationDataTransactionOperationInstall &&
		!current && ![NSFileManager.defaultManager fileExistsAtPath:finalURL.path])
		return YES; // caller aborts a fresh install with no canonical bytes.
	return BTPluginDataStoreFail(error, @"The pending app-data transaction cannot be reconciled without guessing.",
		finalName, nil);
}

- (BOOL)discardUnjournaledPreparedTransactionsExceptIdentifier:(NSString *)transactionIdentifier
	error:(NSError **)error {
	if (transactionIdentifier && !BTPluginDataTransactionIdentifierIsValid(transactionIdentifier))
		return BTPluginDataStoreFail(error, @"The retained app-data transaction identifier is invalid.", nil, nil);
	NSArray<NSURL *> *entries = [NSFileManager.defaultManager
		contentsOfDirectoryAtURL:self.rootURL includingPropertiesForKeys:nil options:0 error:error];
	if (!entries)
		return NO;
	BOOL removedAny = NO;
	for (NSURL *entry in entries) {
		NSString *name = entry.lastPathComponent;
		BOOL transactionEntry = [name hasPrefix:@".transaction-"] || [name hasPrefix:@".removing-"];
		if (!transactionEntry)
			continue;
		NSString *entryIdentifier = BTPluginDataTransactionIdentifierFromHiddenName(name);
		if (!entryIdentifier)
			return BTPluginDataStoreFail(error,
				@"An app-data transaction cleanup entry has a malformed name.", name, nil);
		if ([entryIdentifier isEqualToString:transactionIdentifier])
			continue;
		if (!BTPluginDataPathIsDirectoryOwned(entry) ||
			![NSFileManager.defaultManager removeItemAtURL:entry error:error])
			return NO;
		removedAny = YES;
	}
	if (removedAny)
		BTPluginDataSyncRootURL(self.rootURL);
	return YES;
}

@end
