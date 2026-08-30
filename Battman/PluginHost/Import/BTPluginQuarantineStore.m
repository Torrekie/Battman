//
//  BTPluginQuarantineStore.m
//  Battman
//

#import "BTPluginQuarantineStore.h"

#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <limits.h>
#import <stdio.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../Model/BTPluginPackageErrors.h"
#import "../BTPluginIdentifiers.h"

static BOOL BTPluginQuarantineFail(NSError **error,
									NSString *description,
									NSString *relativePath,
									NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorQuarantine,
			description, relativePath, underlyingError);
	return NO;
}

static NSString *BTPluginHexDigest(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *output = [NSMutableData dataWithLength:length * 2];
	char *characters = output.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

static BOOL BTPluginQuarantineDirectoryModeIsSafe(mode_t mode) {
	return S_ISDIR(mode) && (mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) == 0 &&
		(mode & (S_IRUSR | S_IXUSR)) == (S_IRUSR | S_IXUSR);
}

static BOOL BTPluginQuarantineFileModeMatchesClass(mode_t mode, NSString *modeClass) {
	if (!S_ISREG(mode) || (mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0 ||
		(mode & S_IRUSR) == 0)
		return NO;
	BOOL executable = (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0;
	return executable == [modeClass isEqualToString:@"executable"];
}

static int BTPluginOpenDirectoryPath(int rootDescriptor,
									 NSString *relativeDirectoryPath,
									 BOOL create,
									 NSError **error) {
	int current = dup(rootDescriptor);
	if (current < 0) {
		BTPluginQuarantineFail(error, @"A quarantine directory descriptor could not be duplicated.",
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
			BTPluginQuarantineFail(error, @"A staging directory could not be created.", relativeDirectoryPath,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return -1;
		}
		int next = openat(current, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
		if (next < 0) {
			int savedErrno = errno;
			close(current);
			BTPluginQuarantineFail(error, @"A package directory could not be opened without following links.",
				relativeDirectoryPath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return -1;
		}
		struct stat directoryStat;
		if (fstat(next, &directoryStat) != 0 || !BTPluginQuarantineDirectoryModeIsSafe(directoryStat.st_mode)) {
			close(next);
			close(current);
			BTPluginQuarantineFail(error, @"A package directory has unsafe type or permissions.",
				relativeDirectoryPath, nil);
			return -1;
		}
		close(current);
		current = next;
	}
	return current;
}

static BOOL BTPluginCopyVerifiedFile(int sourceRootDescriptor,
									 int destinationRootDescriptor,
									 BTPluginInspectedFile *expectedFile,
									 NSError **error) {
	NSString *relativePath = expectedFile.relativePath;
	NSString *parentPath = relativePath.stringByDeletingLastPathComponent;
	if ([parentPath isEqualToString:@"."])
		parentPath = @"";
	int sourceParent = BTPluginOpenDirectoryPath(sourceRootDescriptor, parentPath, NO, error);
	if (sourceParent < 0)
		return NO;
	int destinationParent = BTPluginOpenDirectoryPath(destinationRootDescriptor, parentPath, YES, error);
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
		return BTPluginQuarantineFail(error, @"A verified package file could not be reopened without following links.",
			relativePath, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	struct stat before;
	if (fstat(source, &before) != 0 || before.st_nlink != 1 || before.st_size < 0 ||
		(uint64_t)before.st_size != expectedFile.fileSize ||
		!BTPluginQuarantineFileModeMatchesClass(before.st_mode, expectedFile.modeClass)) {
		close(source);
		close(sourceParent);
		close(destinationParent);
		return BTPluginQuarantineFail(error, @"A verified source file changed before quarantine copying.", relativePath, nil);
	}
	int destination = openat(destinationParent, fileName,
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (destination < 0) {
		int savedErrno = errno;
		close(source);
		close(sourceParent);
		close(destinationParent);
		return BTPluginQuarantineFail(error, @"A quarantine staging file could not be created exclusively.",
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
		before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec &&
		before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec &&
		[BTPluginHexDigest(digest, sizeof(digest)) isEqualToString:expectedFile.sha256];
	mode_t destinationMode = [expectedFile.modeClass isEqualToString:@"executable"] ? 0755 : 0644;
	copied = copied && fchmod(destination, destinationMode) == 0 && fsync(destination) == 0;
	close(destination);
	close(source);
	close(sourceParent);
	close(destinationParent);
	if (!copied) {
		(void)unlinkat(destinationRootDescriptor, relativePath.fileSystemRepresentation, 0);
		return BTPluginQuarantineFail(error, @"A source file changed or failed its streaming hash while being copied.",
			relativePath, nil);
	}
	return YES;
}

static void BTPluginRemoveOwnedStagingURL(NSURL *stagingURL, NSURL *rootURL) {
	NSString *rootPrefix = [rootURL.path stringByAppendingString:@"/"];
	if (stagingURL.isFileURL && [stagingURL.path hasPrefix:rootPrefix])
		(void)[[NSFileManager defaultManager] removeItemAtURL:stagingURL error:NULL];
}

@interface BTPluginQuarantinedPackage ()
@property (nonatomic, strong, readwrite) NSURL *packageURL;
@property (nonatomic, strong, readwrite) BTPluginVerifiedPackage *verification;
- (instancetype)bt_init;
@end

@implementation BTPluginQuarantinedPackage
- (instancetype)bt_init { return [super init]; }
- (BOOL)isApprovedForActivation { return self.verification.isApprovedForActivation; }
@end

@interface BTPluginQuarantineStore ()
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@end

@implementation BTPluginQuarantineStore

static NSUInteger const BTPluginQuarantineMaximumPublisherDirectories = 128;
static NSUInteger const BTPluginQuarantineMaximumPackages = 512;

- (instancetype)initWithRootURL:(NSURL *)rootURL
					packageVerifier:(BTPluginPackageVerifier *)packageVerifier
								 error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (![rootURL isKindOfClass:[NSURL class]] || !rootURL.isFileURL ||
		![packageVerifier isKindOfClass:[BTPluginPackageVerifier class]]) {
		BTPluginQuarantineFail(error, @"Quarantine requires a local root and complete package verifier.", nil, nil);
		return nil;
	}
	NSError *directoryError = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtURL:rootURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0700 } error:&directoryError]) {
		BTPluginQuarantineFail(error, @"The private plug-in quarantine directory could not be created.", nil, directoryError);
		return nil;
	}
	if (![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0700 }
		ofItemAtPath:rootURL.path error:&directoryError]) {
		BTPluginQuarantineFail(error, @"The private plug-in quarantine permissions could not be enforced.", nil, directoryError);
		return nil;
	}
	char resolved[PATH_MAX];
	struct stat rootStat;
	if (!realpath(rootURL.fileSystemRepresentation, resolved) || lstat(resolved, &rootStat) != 0 ||
		!BTPluginQuarantineDirectoryModeIsSafe(rootStat.st_mode)) {
		BTPluginQuarantineFail(error, @"The quarantine root is not a safe resolved directory.", nil, nil);
		return nil;
	}
	_rootURL = [NSURL fileURLWithFileSystemRepresentation:resolved isDirectory:YES relativeToURL:nil];
	_packageVerifier = packageVerifier;
	return self;
}

- (BTPluginQuarantinedPackage *)quarantinePackageAtURL:(NSURL *)sourcePackageURL
										  developerMode:(BOOL)developerMode
													error:(NSError **)error {
	BTPluginVerifiedPackage *sourceVerification = [self.packageVerifier verifyPackageAtURL:sourcePackageURL
		developerMode:developerMode error:error];
	if (!sourceVerification)
		return nil;
	BTPluginPackageInspection *sourceInspection = sourceVerification.packageInspection;
	int sourceRoot = open(sourceInspection.packageURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	int quarantineRoot = open(self.rootURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (sourceRoot < 0 || quarantineRoot < 0) {
		if (sourceRoot >= 0)
			close(sourceRoot);
		if (quarantineRoot >= 0)
			close(quarantineRoot);
		BTPluginQuarantineFail(error, @"The source package or quarantine root could not be opened safely.", nil, nil);
		return nil;
	}

	NSString *pluginIdentifier = sourceInspection.manifest.pluginIdentifier;
	if (mkdirat(quarantineRoot, pluginIdentifier.fileSystemRepresentation, 0700) != 0 && errno != EEXIST) {
		int savedErrno = errno;
		close(sourceRoot);
		close(quarantineRoot);
		BTPluginQuarantineFail(error, @"The plug-in's private quarantine directory could not be created.", nil,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		return nil;
	}
	int pluginRoot = openat(quarantineRoot, pluginIdentifier.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	struct stat pluginRootStat;
	if (pluginRoot < 0 || fstat(pluginRoot, &pluginRootStat) != 0 ||
		!BTPluginQuarantineDirectoryModeIsSafe(pluginRootStat.st_mode)) {
		if (pluginRoot >= 0)
			close(pluginRoot);
		close(sourceRoot);
		close(quarantineRoot);
		BTPluginQuarantineFail(error, @"The plug-in quarantine subdirectory is unsafe.", nil, nil);
		return nil;
	}

	NSString *stagingName = [NSString stringWithFormat:@".incoming-%@.battman", NSUUID.UUID.UUIDString.lowercaseString];
	NSString *finalName = [sourceInspection.packageSHA256 stringByAppendingPathExtension:@"battman"];
	NSURL *pluginRootURL = [self.rootURL URLByAppendingPathComponent:pluginIdentifier isDirectory:YES];
	NSURL *stagingURL = [pluginRootURL URLByAppendingPathComponent:stagingName isDirectory:YES];
	NSURL *finalURL = [pluginRootURL URLByAppendingPathComponent:finalName isDirectory:YES];
	if (mkdirat(pluginRoot, stagingName.fileSystemRepresentation, 0700) != 0) {
		int savedErrno = errno;
		close(pluginRoot);
		close(sourceRoot);
		close(quarantineRoot);
		BTPluginQuarantineFail(error, @"An exclusive quarantine staging directory could not be created.", nil,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
		return nil;
	}
	int stagingRoot = openat(pluginRoot, stagingName.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	BOOL copied = stagingRoot >= 0;
	NSArray<BTPluginInspectedFile *> *files = [sourceInspection.filesByPath.allValues
		sortedArrayUsingComparator:^NSComparisonResult(BTPluginInspectedFile *left, BTPluginInspectedFile *right) {
			return [left.relativePath compare:right.relativePath options:NSLiteralSearch];
		}];
	for (BTPluginInspectedFile *file in files) {
		if (!copied || !BTPluginCopyVerifiedFile(sourceRoot, stagingRoot, file, error)) {
			copied = NO;
			break;
		}
	}
	if (stagingRoot >= 0) {
		copied = copied && fsync(stagingRoot) == 0;
		close(stagingRoot);
	}
	close(sourceRoot);
	if (!copied) {
		close(pluginRoot);
		close(quarantineRoot);
		BTPluginRemoveOwnedStagingURL(stagingURL, self.rootURL);
		if (error && !*error)
			BTPluginQuarantineFail(error, @"The verified package could not be copied into quarantine.", nil, nil);
		return nil;
	}

	BTPluginVerifiedPackage *stagingVerification = [self.packageVerifier verifyPackageAtURL:stagingURL
		developerMode:developerMode error:error];
	if (!stagingVerification ||
		![stagingVerification.packageInspection.packageSHA256 isEqualToString:sourceInspection.packageSHA256]) {
		close(pluginRoot);
		close(quarantineRoot);
		BTPluginRemoveOwnedStagingURL(stagingURL, self.rootURL);
		if (error && !*error)
			BTPluginQuarantineFail(error, @"The staging package differs from the verified source.", nil, nil);
		return nil;
	}

	BOOL installedExisting = NO;
	if (renameatx_np(pluginRoot, stagingName.fileSystemRepresentation,
		pluginRoot, finalName.fileSystemRepresentation, RENAME_EXCL) != 0) {
		if (errno == EEXIST) {
			installedExisting = YES;
			BTPluginRemoveOwnedStagingURL(stagingURL, self.rootURL);
		} else {
			int savedErrno = errno;
			close(pluginRoot);
			close(quarantineRoot);
			BTPluginRemoveOwnedStagingURL(stagingURL, self.rootURL);
			BTPluginQuarantineFail(error, @"The verified staging package could not be atomically installed.", nil,
				[NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
			return nil;
		}
	}
	if (!installedExisting && fsync(pluginRoot) != 0) {
		close(pluginRoot);
		close(quarantineRoot);
		BTPluginRemoveOwnedStagingURL(finalURL, self.rootURL);
		BTPluginQuarantineFail(error, @"The atomic quarantine directory update could not be synchronized.", nil, nil);
		return nil;
	}
	close(pluginRoot);
	close(quarantineRoot);

	BTPluginVerifiedPackage *finalVerification = [self.packageVerifier verifyPackageAtURL:finalURL
		developerMode:developerMode error:error];
	if (!finalVerification ||
		![finalVerification.packageInspection.packageSHA256 isEqualToString:sourceInspection.packageSHA256]) {
		if (!installedExisting)
			BTPluginRemoveOwnedStagingURL(finalURL, self.rootURL);
		if (error && !*error)
			BTPluginQuarantineFail(error, @"The content-addressed quarantine copy failed final verification.", nil, nil);
		return nil;
	}

	BTPluginQuarantinedPackage *result = [[BTPluginQuarantinedPackage alloc] bt_init];
	result.packageURL = finalVerification.packageInspection.packageURL;
	result.verification = finalVerification;
	return result;
}

- (NSArray<BTPluginQuarantinedPackage *> *)quarantinedPackagesWithDeveloperMode:(BOOL)developerMode
																				 error:(NSError **)error {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *listingError = nil;
	NSArray<NSURL *> *identifierURLs = [manager contentsOfDirectoryAtURL:self.rootURL
		includingPropertiesForKeys:nil options:0 error:&listingError];
	if (!identifierURLs) {
		BTPluginQuarantineFail(error, @"The plug-in quarantine could not be inventoried.", nil, listingError);
		return nil;
	}
	if (identifierURLs.count > BTPluginQuarantineMaximumPublisherDirectories) {
		BTPluginQuarantineFail(error, @"The plug-in quarantine identifier limit was exceeded.", nil, nil);
		return nil;
	}
	NSMutableArray<BTPluginQuarantinedPackage *> *results = [NSMutableArray array];
	NSArray<NSURL *> *sortedIdentifiers = [identifierURLs sortedArrayUsingComparator:
		^NSComparisonResult(NSURL *left, NSURL *right) {
			return [left.lastPathComponent compare:right.lastPathComponent options:NSLiteralSearch];
		}];
	for (NSURL *identifierURL in sortedIdentifiers) {
		NSString *pluginIdentifier = identifierURL.lastPathComponent;
		if (!BTPluginIdentifierIsValid(pluginIdentifier))
			continue;
		struct stat identifierStat;
		if (lstat(identifierURL.fileSystemRepresentation, &identifierStat) != 0 ||
			!BTPluginQuarantineDirectoryModeIsSafe(identifierStat.st_mode) || identifierStat.st_uid != geteuid()) {
			BTPluginQuarantineFail(error, @"A plug-in quarantine identifier directory is unsafe.",
				pluginIdentifier, nil);
			return nil;
		}
		NSArray<NSURL *> *packageURLs = [manager contentsOfDirectoryAtURL:identifierURL
			includingPropertiesForKeys:nil options:0 error:&listingError];
		if (!packageURLs) {
			BTPluginQuarantineFail(error, @"A plug-in quarantine directory could not be inventoried.",
				pluginIdentifier, listingError);
			return nil;
		}
		NSArray<NSURL *> *sortedPackages = [packageURLs sortedArrayUsingComparator:
			^NSComparisonResult(NSURL *left, NSURL *right) {
				return [left.lastPathComponent compare:right.lastPathComponent options:NSLiteralSearch];
			}];
		for (NSURL *packageURL in sortedPackages) {
			NSString *name = packageURL.lastPathComponent;
			if ([name hasPrefix:@".incoming-"] || [name hasPrefix:@".removing-"])
				continue;
			NSString *digest = name.stringByDeletingPathExtension;
			if (![name.pathExtension isEqualToString:@"battman"] ||
				!BTPluginPackageLowercaseSHA256IsValid(digest))
				continue;
			if (results.count >= BTPluginQuarantineMaximumPackages) {
				BTPluginQuarantineFail(error, @"The plug-in quarantine package limit was exceeded.", nil, nil);
				return nil;
			}
			BTPluginVerifiedPackage *verification = [self.packageVerifier verifyPackageAtURL:packageURL
				developerMode:developerMode error:&listingError];
			if (!verification ||
				![verification.packageInspection.manifest.pluginIdentifier isEqualToString:pluginIdentifier] ||
				![verification.packageInspection.packageSHA256 isEqualToString:digest]) {
				if (error)
					*error = listingError ?: BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
						@"A quarantined package no longer matches its content-addressed location.", name, nil);
				return nil;
			}
			BTPluginQuarantinedPackage *package = [[BTPluginQuarantinedPackage alloc] bt_init];
			package.packageURL = verification.packageInspection.packageURL;
			package.verification = verification;
			[results addObject:package];
		}
	}
	return results;
}

- (BOOL)removeQuarantinedPluginIdentifier:(NSString *)pluginIdentifier
									 packageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(packageSHA256))
		return BTPluginQuarantineFail(error, @"Quarantine removal requires an exact identifier and digest.", nil, nil);
	int quarantineRoot = open(self.rootURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (quarantineRoot < 0)
		return BTPluginQuarantineFail(error, @"The quarantine root could not be opened for removal.", nil, nil);
	int pluginRoot = openat(quarantineRoot, pluginIdentifier.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (pluginRoot < 0) {
		close(quarantineRoot);
		return BTPluginQuarantineFail(error, @"The plug-in quarantine directory does not exist.",
			pluginIdentifier, nil);
	}
	NSString *packageName = [packageSHA256 stringByAppendingPathExtension:@"battman"];
	struct stat packageStat;
	if (fstatat(pluginRoot, packageName.fileSystemRepresentation, &packageStat, AT_SYMLINK_NOFOLLOW) != 0 ||
		!S_ISDIR(packageStat.st_mode) || packageStat.st_uid != geteuid()) {
		close(pluginRoot);
		close(quarantineRoot);
		return BTPluginQuarantineFail(error, @"The exact quarantine package is missing or unsafe.", packageName, nil);
	}
	NSString *removingName = [NSString stringWithFormat:@".removing-%@.battman", NSUUID.UUID.UUIDString.lowercaseString];
	if (renameatx_np(pluginRoot, packageName.fileSystemRepresentation,
		pluginRoot, removingName.fileSystemRepresentation, RENAME_EXCL) != 0) {
		int savedErrno = errno;
		close(pluginRoot);
		close(quarantineRoot);
		return BTPluginQuarantineFail(error, @"The exact quarantine package could not be deactivated for removal.",
			packageName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	if (fsync(pluginRoot) != 0) {
		int savedErrno = errno;
		(void)renameatx_np(pluginRoot, removingName.fileSystemRepresentation,
			pluginRoot, packageName.fileSystemRepresentation, RENAME_EXCL);
		(void)fsync(pluginRoot);
		close(pluginRoot);
		close(quarantineRoot);
		return BTPluginQuarantineFail(error, @"The quarantine removal could not be synchronized.",
			packageName, [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil]);
	}
	close(pluginRoot);
	close(quarantineRoot);
	NSURL *pluginURL = [self.rootURL URLByAppendingPathComponent:pluginIdentifier isDirectory:YES];
	NSURL *removingURL = [pluginURL URLByAppendingPathComponent:removingName isDirectory:YES];
	NSError *removeError = nil;
	if (![[NSFileManager defaultManager] removeItemAtURL:removingURL error:&removeError])
		return BTPluginQuarantineFail(error, @"The deactivated quarantine package could not be removed.",
			packageName, removeError);
	return YES;
}

@end
