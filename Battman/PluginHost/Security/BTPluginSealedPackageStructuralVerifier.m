//
//  BTPluginSealedPackageStructuralVerifier.m
//  Battman
//

#import "BTPluginSealedPackageStructuralVerifier.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <limits.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <sys/stat.h>
#import <unistd.h>

#import "BTPluginPackageInspectionPrivate.h"
#import "../Model/BTPluginPackageErrors.h"

static const uint64_t BTPluginSealedInfoPlistMaximumBytes = 64ULL * 1024ULL;
static const uint64_t BTPluginSealedSignatureMaximumBytes = 256;
static const uint64_t BTPluginSealedP256KeyBytes = 65;

static BOOL BTPluginSealedFail(NSError **error, BTPluginPackageErrorCode code,
	NSString *description, NSString *relativePath, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, relativePath, underlyingError);
	return NO;
}

static NSString *BTPluginSealedHex(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *output = [NSMutableData dataWithLength:length * 2];
	char *characters = output.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

static NSData *BTPluginSealedDataFromHex(NSString *value) {
	if (!BTPluginPackageLowercaseSHA256IsValid(value))
		return nil;
	NSMutableData *data = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
	uint8_t *bytes = data.mutableBytes;
	const char *characters = value.UTF8String;
	for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
		char high = characters[index * 2];
		char low = characters[index * 2 + 1];
		uint8_t highValue = high <= '9' ? (uint8_t)(high - '0') : (uint8_t)(high - 'a' + 10);
		uint8_t lowValue = low <= '9' ? (uint8_t)(low - '0') : (uint8_t)(low - 'a' + 10);
		bytes[index] = (uint8_t)((highValue << 4) | lowValue);
	}
	return data;
}

static NSComparisonResult BTPluginSealedComparePaths(NSString *left, NSString *right) {
	NSData *leftData = [left dataUsingEncoding:NSUTF8StringEncoding];
	NSData *rightData = [right dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger common = MIN(leftData.length, rightData.length);
	int comparison = common == 0 ? 0 : memcmp(leftData.bytes, rightData.bytes, common);
	if (comparison < 0)
		return NSOrderedAscending;
	if (comparison > 0)
		return NSOrderedDescending;
	if (leftData.length < rightData.length)
		return NSOrderedAscending;
	if (leftData.length > rightData.length)
		return NSOrderedDescending;
	return NSOrderedSame;
}

static BOOL BTPluginSealedEntryModeIsSafe(struct stat entryStat, NSString *relativePath, NSError **error) {
	mode_t unsafe = S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX;
	if ((entryStat.st_mode & unsafe) != 0)
		return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
			@"Sealed plug-in entries cannot be set-id, sticky, or group/other writable.", relativePath, nil);
	if (S_ISDIR(entryStat.st_mode)) {
		if ((entryStat.st_mode & (S_IRUSR | S_IXUSR)) == (S_IRUSR | S_IXUSR))
			return YES;
		return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
			@"Sealed plug-in directories must be readable and searchable by their owner.", relativePath, nil);
	}
	if (S_ISREG(entryStat.st_mode)) {
		if ((entryStat.st_mode & S_IRUSR) != 0)
			return YES;
		return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
			@"Sealed plug-in files must be readable by their owner.", relativePath, nil);
	}
	return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
		@"Sealed plug-ins may contain only directories and regular files.", relativePath, nil);
}

static BOOL BTPluginSealedStatsMatch(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_size == right->st_size && left->st_mode == right->st_mode &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static NSString *BTPluginSealedModeClass(mode_t mode) {
	return (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) == 0 ? @"data" : @"executable";
}

@interface BTPluginSealedFileState : NSObject
@property (nonatomic, copy) NSString *logicalPath;
@property (nonatomic, strong) NSURL *physicalURL;
@property (nonatomic) struct stat initialStat;
@property (nonatomic, copy) NSString *modeClass;
@property (nonatomic, copy) NSData *rawSHA256;
@property (nonatomic, copy) NSString *sha256;
@property (nonatomic, copy) NSData *leadingBytes;
@end

@implementation BTPluginSealedFileState
@end

static BOOL BTPluginSealedReadFile(BTPluginSealedFileState *file, uint64_t captureLimit,
	NSData **capturedData, NSError **error) {
	if (captureLimit > 0 && (uint64_t)file.initialStat.st_size > captureLimit)
		return BTPluginSealedFail(error, BTPluginPackageErrorLimitExceeded,
			@"A bounded sealed metadata file exceeds its size limit.", file.logicalPath, nil);
	int descriptor = open(file.physicalURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0)
		return BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
			@"A sealed plug-in file could not be opened without following links.", file.logicalPath,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
	struct stat expected = file.initialStat;
	struct stat before;
	if (fstat(descriptor, &before) != 0 || !BTPluginSealedStatsMatch(&before, &expected) ||
		!S_ISREG(before.st_mode) || before.st_nlink != 1 || before.st_size < 0) {
		close(descriptor);
		return BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
			@"A sealed plug-in file changed between enumeration and opening.", file.logicalPath, nil);
	}

	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	NSMutableData *captured = capturedData ? [NSMutableData dataWithCapacity:(NSUInteger)before.st_size] : nil;
	NSMutableData *leading = [NSMutableData dataWithCapacity:sizeof(uint32_t)];
	uint8_t buffer[64 * 1024];
	uint64_t total = 0;
	while (YES) {
		ssize_t count = read(descriptor, buffer, sizeof(buffer));
		if (count < 0) {
			close(descriptor);
			return BTPluginSealedFail(error, BTPluginPackageErrorInvalidPackage,
				@"A sealed plug-in file could not be read.", file.logicalPath, nil);
		}
		if (count == 0)
			break;
		total += (uint64_t)count;
		if (total > (uint64_t)before.st_size) {
			close(descriptor);
			return BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
				@"A sealed plug-in file grew during inspection.", file.logicalPath, nil);
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		if (leading.length < sizeof(uint32_t)) {
			NSUInteger wanted = sizeof(uint32_t) - leading.length;
			[leading appendBytes:buffer length:MIN(wanted, (NSUInteger)count)];
		}
		[captured appendBytes:buffer length:(NSUInteger)count];
	}
	struct stat after;
	BOOL unchanged = fstat(descriptor, &after) == 0 && BTPluginSealedStatsMatch(&before, &after) &&
		total == (uint64_t)before.st_size;
	close(descriptor);
	if (!unchanged)
		return BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
			@"A sealed plug-in file changed during inspection.", file.logicalPath, nil);
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	file.rawSHA256 = [NSData dataWithBytes:digest length:sizeof(digest)];
	file.sha256 = BTPluginSealedHex(digest, sizeof(digest));
	file.leadingBytes = leading;
	if (capturedData)
		*capturedData = captured;
	return YES;
}

static BOOL BTPluginSealedFileHasMachOMagic(BTPluginSealedFileState *file) {
	if (file.leadingBytes.length != sizeof(uint32_t))
		return NO;
	uint32_t magic = 0;
	memcpy(&magic, file.leadingBytes.bytes, sizeof(magic));
	return magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
		magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
}

static BOOL BTPluginSealedOuterInfoMatchesManifest(NSDictionary *info,
	BTPluginPackageManifest *manifest, NSError **error) {
	NSDictionary<NSString *, NSString *> *expected = @{
		@"CFBundleIdentifier": manifest.pluginIdentifier,
		@"CFBundleDisplayName": manifest.displayName,
		@"CFBundleShortVersionString": manifest.displayVersion,
		@"CFBundleVersion": manifest.buildVersion,
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPublisherKeyIdentifier": manifest.publisher.primaryKeyIdentifier,
	};
	for (NSString *key in expected) {
		if (![info[key] isKindOfClass:[NSString class]] || ![info[key] isEqualToString:expected[key]])
			return BTPluginSealedFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"Sealed preview metadata does not match the signed manifest.", @"Info.plist", nil);
	}
	id formatVersion = info[@"BTPluginPackageFormatVersion"];
	if (![formatVersion isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)formatVersion) == CFBooleanGetTypeID() ||
		CFNumberIsFloatType((__bridge CFNumberRef)formatVersion) || [formatVersion longLongValue] != 1)
		return BTPluginSealedFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"Sealed preview metadata has an invalid package format version.", @"Info.plist", nil);
	return YES;
}

static BOOL BTPluginSealedBundleInfoMatchesManifest(NSDictionary *info,
	BTPluginPackageManifest *manifest, NSString *relativePath, NSError **error) {
	NSString *executableName = info[@"CFBundleExecutable"];
	NSString *executablePrefix = [manifest.payload.path stringByAppendingString:@"/"];
	NSString *declaredExecutableName = [manifest.payload.executablePath hasPrefix:executablePrefix] ?
		[manifest.payload.executablePath substringFromIndex:executablePrefix.length] : nil;
	if (![executableName isKindOfClass:[NSString class]] || executableName.length == 0 ||
		executableName.length > 255 || [executableName containsString:@"/"] ||
		![declaredExecutableName isEqualToString:executableName]) {
		return BTPluginSealedFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"The sealed bundle Info.plist executable does not match the direct signed payload executable.",
			relativePath, nil);
	}
	NSDictionary<NSString *, NSString *> *expectedStrings = @{
		@"CFBundleIdentifier": manifest.pluginIdentifier,
		@"CFBundlePackageType": @"BNDL",
		@"CFBundleShortVersionString": manifest.displayVersion,
		@"CFBundleVersion": manifest.buildVersion,
	};
	for (NSString *key in expectedStrings) {
		id value = info[key];
		if (![value isKindOfClass:[NSString class]] || ![value isEqualToString:expectedStrings[key]])
			return BTPluginSealedFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"The sealed bundle Info.plist identity does not match the signed manifest.", relativePath, nil);
	}
	return YES;
}

static BOOL BTPluginSealedResolveRoot(NSURL *inputURL, NSString *role, NSURL **resolvedURL,
	struct stat *rootStat, NSError **error) {
	if (![inputURL isKindOfClass:[NSURL class]] || !inputURL.isFileURL || !inputURL.path.isAbsolutePath)
		return BTPluginSealedFail(error, BTPluginPackageErrorSealedPackage,
			[NSString stringWithFormat:@"The sealed %@ root is not an absolute local path.", role], nil, nil);
	NSURL *standardURL = inputURL.URLByStandardizingPath;
	struct stat unresolvedStat;
	if (lstat(standardURL.fileSystemRepresentation, &unresolvedStat) != 0 || !S_ISDIR(unresolvedStat.st_mode) ||
		!BTPluginSealedEntryModeIsSafe(unresolvedStat, @".", error))
		return NO;
	char resolved[PATH_MAX];
	if (!realpath(standardURL.fileSystemRepresentation, resolved))
		return BTPluginSealedFail(error, BTPluginPackageErrorSealedPackage,
			[NSString stringWithFormat:@"The sealed %@ root could not be resolved.", role], nil, nil);
	NSURL *url = [NSURL fileURLWithFileSystemRepresentation:resolved isDirectory:YES relativeToURL:nil];
	struct stat resolvedStat;
	if (lstat(url.fileSystemRepresentation, &resolvedStat) != 0 || !S_ISDIR(resolvedStat.st_mode) ||
		!BTPluginSealedStatsMatch(&unresolvedStat, &resolvedStat))
		return BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
			[NSString stringWithFormat:@"The sealed %@ root changed while being resolved.", role], nil, nil);
	if (resolvedURL)
		*resolvedURL = url;
	if (rootStat)
		*rootStat = resolvedStat;
	return YES;
}

static BOOL BTPluginSealedEnumerateRoot(NSURL *rootURL, NSString *logicalPrefix,
	NSMutableDictionary<NSString *, BTPluginSealedFileState *> *files,
	NSMutableSet<NSString *> *directories, NSMutableSet<NSString *> *allPaths,
	NSMutableSet<NSString *> *foldedPaths, NSMutableDictionary<NSString *, NSData *> *captured,
	uint64_t *totalBytes, NSError **error) {
	NSString *rootPrefix = [rootURL.path stringByAppendingString:@"/"];
	__block NSError *enumerationError = nil;
	NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
		enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:0
		errorHandler:^BOOL(NSURL *url, NSError *underlyingError) {
			(void)url;
			enumerationError = underlyingError;
			return NO;
		}];
	for (NSURL *entryURL in enumerator) {
		if (allPaths.count >= BTPluginPackageMaximumRegularFileCount * 4) {
			BTPluginSealedFail(error, BTPluginPackageErrorLimitExceeded,
				@"The sealed plug-in tree exceeds its bounded entry limit.", nil, nil);
			return NO;
		}
		if (![entryURL.path hasPrefix:rootPrefix])
			return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
				@"A sealed plug-in entry escapes its physical root.", nil, nil);
		NSString *physicalRelativePath = [entryURL.path substringFromIndex:rootPrefix.length];
		NSString *logicalPath = logicalPrefix.length > 0 ?
			[logicalPrefix stringByAppendingPathComponent:physicalRelativePath] : physicalRelativePath;
		NSString *folded = [logicalPath lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
		if (!BTPluginPackageRelativePathIsValid(logicalPath) || [foldedPaths containsObject:folded])
			return BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
				@"A sealed plug-in path is unsafe, non-canonical, duplicated, or case-colliding.", logicalPath, nil);
		[foldedPaths addObject:folded];
		[allPaths addObject:logicalPath];
		struct stat entryStat;
		if (lstat(entryURL.fileSystemRepresentation, &entryStat) != 0 ||
			!BTPluginSealedEntryModeIsSafe(entryStat, logicalPath, error))
			return NO;
		if (S_ISDIR(entryStat.st_mode)) {
			[directories addObject:logicalPath];
			continue;
		}
		if (entryStat.st_nlink != 1 || entryStat.st_size < 0 ||
			(uint64_t)entryStat.st_size > BTPluginPackageMaximumSingleFileByteCount)
			return BTPluginSealedFail(error,
				entryStat.st_nlink != 1 ? BTPluginPackageErrorUnsafePath : BTPluginPackageErrorLimitExceeded,
				entryStat.st_nlink != 1 ? @"Hard-linked sealed plug-in files are not permitted." :
				@"A sealed plug-in file exceeds 64 MiB.", logicalPath, nil);
		if (files.count + 1 > BTPluginPackageMaximumRegularFileCount ||
			UINT64_MAX - *totalBytes < (uint64_t)entryStat.st_size ||
			(*totalBytes += (uint64_t)entryStat.st_size) > BTPluginPackageMaximumTotalByteCount)
			return BTPluginSealedFail(error, BTPluginPackageErrorLimitExceeded,
				@"The sealed plug-in exceeds its file-count or 128 MiB total-size limit.", logicalPath, nil);

		BTPluginSealedFileState *file = [BTPluginSealedFileState new];
		file.logicalPath = logicalPath;
		file.physicalURL = entryURL;
		file.initialStat = entryStat;
		file.modeClass = BTPluginSealedModeClass(entryStat.st_mode);
		uint64_t captureLimit = 0;
		if ([logicalPath isEqualToString:@"Manifest.json"])
			captureLimit = BTPluginManifestMaximumByteCount;
		else if ([logicalPath isEqualToString:@"Info.plist"])
			captureLimit = BTPluginSealedInfoPlistMaximumBytes;
		else if ([logicalPath hasPrefix:@"Signatures/"])
			captureLimit = BTPluginSealedSignatureMaximumBytes;
		else if ([logicalPath hasPrefix:@"PublisherKeys/"])
			captureLimit = BTPluginSealedP256KeyBytes;
		NSData *data = nil;
		if (!BTPluginSealedReadFile(file, captureLimit, captureLimit > 0 ? &data : NULL, error))
			return NO;
		if (data)
			captured[logicalPath] = data;
		files[logicalPath] = file;
	}
	if (enumerationError)
		return BTPluginSealedFail(error, BTPluginPackageErrorInvalidPackage,
			@"A sealed plug-in root could not be enumerated.", nil, enumerationError);
	return YES;
}

static NSSet<NSString *> *BTPluginSealedCurrentPathSet(NSURL *rootURL, NSString *logicalPrefix,
	NSError **error) {
	NSString *rootPrefix = [rootURL.path stringByAppendingString:@"/"];
	NSMutableSet<NSString *> *paths = [NSMutableSet set];
	__block NSError *enumerationError = nil;
	NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
		enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:0
		errorHandler:^BOOL(NSURL *url, NSError *underlyingError) {
			(void)url;
			enumerationError = underlyingError;
			return NO;
		}];
	for (NSURL *entryURL in enumerator) {
		if (paths.count >= BTPluginPackageMaximumRegularFileCount * 4 ||
			![entryURL.path hasPrefix:rootPrefix]) {
			BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
				@"A sealed plug-in root changed beyond its bounded tree.", nil, enumerationError);
			return nil;
		}
		NSString *relative = [entryURL.path substringFromIndex:rootPrefix.length];
		[paths addObject:logicalPrefix.length > 0 ?
			[logicalPrefix stringByAppendingPathComponent:relative] : relative];
	}
	if (enumerationError) {
		BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
			@"A sealed plug-in root changed during final enumeration.", nil, enumerationError);
		return nil;
	}
	return paths;
}

@implementation BTPluginSealedPackageStructuralVerifier

- (BTPluginPackageInspection *)inspectMetadataAtURL:(NSURL *)metadataURL
											 payloadURL:(NSURL *)payloadURL
												  error:(NSError **)error {
	NSURL *metadataRoot = nil;
	NSURL *payloadRoot = nil;
	struct stat metadataRootStat;
	struct stat payloadRootStat;
	if (!BTPluginSealedResolveRoot(metadataURL, @"metadata", &metadataRoot, &metadataRootStat, error) ||
		!BTPluginSealedResolveRoot(payloadURL, @"payload", &payloadRoot, &payloadRootStat, error))
		return nil;
	NSString *metadataPrefix = [metadataRoot.path stringByAppendingString:@"/"];
	NSString *payloadPrefix = [payloadRoot.path stringByAppendingString:@"/"];
	if ([metadataRoot.path isEqualToString:payloadRoot.path] ||
		[metadataPrefix hasPrefix:payloadPrefix] || [payloadPrefix hasPrefix:metadataPrefix]) {
		BTPluginSealedFail(error, BTPluginPackageErrorUnsafePath,
			@"The sealed metadata and payload roots must be distinct, non-nested directories.", nil, nil);
		return nil;
	}

	NSMutableDictionary<NSString *, BTPluginSealedFileState *> *files = [NSMutableDictionary dictionary];
	NSMutableSet<NSString *> *directories = [NSMutableSet set];
	NSMutableSet<NSString *> *allPaths = [NSMutableSet set];
	NSMutableSet<NSString *> *foldedPaths = [NSMutableSet set];
	NSMutableDictionary<NSString *, NSData *> *captured = [NSMutableDictionary dictionary];
	uint64_t totalBytes = 0;
	if (!BTPluginSealedEnumerateRoot(metadataRoot, nil, files, directories, allPaths,
		foldedPaths, captured, &totalBytes, error))
		return nil;
	NSData *manifestData = captured[@"Manifest.json"];
	if (!manifestData || !files[@"Info.plist"] || ![directories containsObject:@"Signatures"]) {
		BTPluginSealedFail(error, BTPluginPackageErrorMissingFile,
			@"Sealed metadata must contain Manifest.json, Info.plist, and Signatures/.", nil, nil);
		return nil;
	}
	BTPluginPackageManifest *manifest = [BTPluginPackageManifest manifestWithData:manifestData error:error];
	if (!manifest)
		return nil;
	NSString *logicalPayloadPrefix = [manifest.payload.path stringByAppendingString:@"/"];
	for (NSString *metadataPath in allPaths) {
		if ([metadataPath isEqualToString:manifest.payload.path] ||
			[metadataPath hasPrefix:logicalPayloadPrefix]) {
			BTPluginSealedFail(error, BTPluginPackageErrorUnexpectedFile,
				@"Sealed metadata must not contain a duplicate logical payload tree.", metadataPath, nil);
			return nil;
		}
	}
	if (![manifest.payload.kind isEqualToString:@"bundle"] ||
		![metadataRoot.lastPathComponent isEqualToString:manifest.pluginIdentifier] ||
		![payloadRoot.lastPathComponent isEqualToString:
			[manifest.pluginIdentifier stringByAppendingPathExtension:@"bundle"]]) {
		BTPluginSealedFail(error, BTPluginPackageErrorSealedPackage,
			@"Sealed directory names or payload kind do not match the signed plug-in identifier.", nil, nil);
		return nil;
	}
	[directories addObject:manifest.payload.path];
	[allPaths addObject:manifest.payload.path];
	[foldedPaths addObject:[manifest.payload.path lowercaseStringWithLocale:
		[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]]];
	if (!BTPluginSealedEnumerateRoot(payloadRoot, manifest.payload.path, files, directories, allPaths,
		foldedPaths, captured, &totalBytes, error))
		return nil;

	NSMutableSet<NSString *> *allowedFiles = [NSMutableSet setWithObject:@"Manifest.json"];
	for (BTPluginManifestFile *declaredFile in manifest.files) {
		BOOL roleAllowed = [declaredFile.path isEqualToString:@"Info.plist"] ||
			[declaredFile.path hasPrefix:@"PublisherKeys/"] ||
			[declaredFile.path hasPrefix:[manifest.payload.path stringByAppendingString:@"/"]];
		if (!roleAllowed) {
			BTPluginSealedFail(error, BTPluginPackageErrorInvalidManifest,
				@"A sealed manifest file has no v1 installed role.", declaredFile.path, nil);
			return nil;
		}
		[allowedFiles addObject:declaredFile.path];
	}
	NSMutableDictionary<NSString *, NSData *> *signatures = [NSMutableDictionary dictionary];
	for (NSString *keyIdentifier in manifest.publisher.signatureKeyIdentifiers) {
		NSString *signaturePath = [NSString stringWithFormat:@"Signatures/%@.sig", keyIdentifier];
		BTPluginSealedFileState *signatureFile = files[signaturePath];
		NSData *signatureData = captured[signaturePath];
		if (!signatureFile || !signatureData || signatureData.length == 0 ||
			signatureData.length > BTPluginSealedSignatureMaximumBytes ||
			![signatureFile.modeClass isEqualToString:@"data"]) {
			BTPluginSealedFail(error, BTPluginPackageErrorMissingFile,
				@"A declared sealed publisher signature is missing or invalid.", signaturePath, nil);
			return nil;
		}
		signatures[keyIdentifier] = signatureData;
		[allowedFiles addObject:signaturePath];
	}
	NSSet *actualFilePaths = [NSSet setWithArray:files.allKeys];
	if (![actualFilePaths isEqualToSet:allowedFiles]) {
		NSMutableSet *unexpected = [actualFilePaths mutableCopy];
		[unexpected minusSet:allowedFiles];
		NSMutableSet *missing = [allowedFiles mutableCopy];
		[missing minusSet:actualFilePaths];
		NSString *path = unexpected.anyObject ?: missing.anyObject;
		BTPluginSealedFail(error, unexpected.count ? BTPluginPackageErrorUnexpectedFile : BTPluginPackageErrorMissingFile,
			unexpected.count ? @"The sealed representation contains a file absent from the signed inventory." :
			@"The sealed representation is missing a signed inventory file.", path, nil);
		return nil;
	}
	if (manifest.payload.codeIdentity) {
		BTPluginSealedFileState *executable = files[manifest.payload.executablePath];
		uint64_t unsignedByteCount = 0;
		NSString *codeSHA256 = nil;
		if (!executable || !BTPluginComputeMachOCodeIdentityAtURL(executable.physicalURL,
			manifest.payload.executablePath, &unsignedByteCount, &codeSHA256, error) ||
			unsignedByteCount != manifest.payload.codeIdentity.unsignedByteCount ||
			![codeSHA256 isEqualToString:manifest.payload.codeIdentity.sha256]) {
			if (error && !*error)
				BTPluginSealedFail(error, BTPluginPackageErrorHashMismatch,
					@"The sealed payload executable does not match its signed code identity.",
					manifest.payload.executablePath, nil);
			return nil;
		}
	}

	for (BTPluginManifestFile *declaredFile in manifest.files) {
		BTPluginSealedFileState *actual = files[declaredFile.path];
		BOOL exactBytes = (uint64_t)actual.initialStat.st_size == declaredFile.size &&
			[actual.sha256 isEqualToString:declaredFile.sha256];
		BOOL boundedResign = manifest.payload.codeIdentity &&
			[declaredFile.path isEqualToString:manifest.payload.executablePath];
		if ((!exactBytes && !boundedResign) || ![actual.modeClass isEqualToString:declaredFile.mode]) {
			BTPluginSealedFail(error, BTPluginPackageErrorHashMismatch,
				@"A sealed file does not match its signed bytes or bounded Mach-O resigning identity.", declaredFile.path, nil);
			return nil;
		}
		if ([actual.modeClass isEqualToString:@"executable"] &&
			(actual.initialStat.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != (S_IXUSR | S_IXGRP | S_IXOTH)) {
			BTPluginSealedFail(error, BTPluginPackageErrorHashMismatch,
				@"The sealed payload executable lacks normalized executable permissions.", declaredFile.path, nil);
			return nil;
		}
		if (![declaredFile.path isEqualToString:manifest.payload.executablePath] &&
			BTPluginSealedFileHasMachOMagic(actual)) {
			BTPluginSealedFail(error, BTPluginPackageErrorInvalidMachO,
				@"The sealed representation contains an undeclared additional Mach-O image.", declaredFile.path, nil);
			return nil;
		}
	}

	NSString *bundleInfoPath = [manifest.payload.path stringByAppendingPathComponent:@"Info.plist"];
	BTPluginManifestFile *declaredBundleInfo = manifest.filesByPath[bundleInfoPath];
	BTPluginSealedFileState *actualBundleInfo = files[bundleInfoPath];
	if (!declaredBundleInfo || !actualBundleInfo || ![declaredBundleInfo.mode isEqualToString:@"data"] ||
		declaredBundleInfo.size > BTPluginSealedInfoPlistMaximumBytes) {
		BOOL oversized = declaredBundleInfo && declaredBundleInfo.size > BTPluginSealedInfoPlistMaximumBytes;
		BTPluginSealedFail(error, oversized ? BTPluginPackageErrorLimitExceeded : BTPluginPackageErrorMissingFile,
			oversized ? @"The sealed signed bundle Info.plist exceeds 64 KiB." :
			@"A sealed bundle payload must contain one bounded signed Info.plist.", bundleInfoPath, nil);
		return nil;
	}
	NSData *bundleInfoData = nil;
	if (!BTPluginSealedReadFile(actualBundleInfo, BTPluginSealedInfoPlistMaximumBytes,
		&bundleInfoData, error) || (uint64_t)actualBundleInfo.initialStat.st_size != declaredBundleInfo.size ||
		![actualBundleInfo.sha256 isEqualToString:declaredBundleInfo.sha256]) {
		if (error && !*error)
			BTPluginSealedFail(error, BTPluginPackageErrorHashMismatch,
				@"The sealed bundle Info.plist changed after signed inventory verification.", bundleInfoPath, nil);
		return nil;
	}
	NSError *bundlePropertyListError = nil;
	id bundleInfo = [NSPropertyListSerialization propertyListWithData:bundleInfoData
		options:NSPropertyListImmutable format:NULL error:&bundlePropertyListError];
	if (![bundleInfo isKindOfClass:[NSDictionary class]] ||
		!BTPluginSealedBundleInfoMatchesManifest(bundleInfo, manifest, bundleInfoPath, error)) {
		if (error && !*error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidInfoPlist,
				@"The sealed signed bundle Info.plist is not a valid property-list dictionary.",
				bundleInfoPath, bundlePropertyListError);
		return nil;
	}
	for (NSString *directoryPath in directories) {
		BOOL used = NO;
		NSString *prefix = [directoryPath stringByAppendingString:@"/"];
		for (NSString *filePath in allowedFiles) {
			if ([filePath hasPrefix:prefix]) {
				used = YES;
				break;
			}
		}
		if (!used) {
			BTPluginSealedFail(error, BTPluginPackageErrorUnexpectedFile,
				@"The sealed representation contains an empty or unlisted directory.", directoryPath, nil);
			return nil;
		}
	}

	NSMutableDictionary<NSString *, NSData *> *publisherKeys = [NSMutableDictionary dictionary];
	for (NSString *path in files) {
		if (![path hasPrefix:@"PublisherKeys/"])
			continue;
		NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
		NSString *fileName = components.lastObject;
		NSString *keyIdentifier = fileName.stringByDeletingPathExtension;
		NSData *keyData = captured[path];
		if (components.count != 2 || ![fileName.pathExtension isEqualToString:@"p256"] ||
			!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) ||
			keyData.length != BTPluginSealedP256KeyBytes || ((const uint8_t *)keyData.bytes)[0] != 0x04 ||
			![files[path].sha256 isEqualToString:keyIdentifier] ||
			![manifest.publisher.signatureKeyIdentifiers containsObject:keyIdentifier]) {
			BTPluginSealedFail(error, BTPluginPackageErrorInvalidManifest,
				@"A sealed publisher key has an invalid path, encoding, fingerprint, or signature role.", path, nil);
			return nil;
		}
		publisherKeys[keyIdentifier] = keyData;
	}

	NSError *propertyListError = nil;
	id info = [NSPropertyListSerialization propertyListWithData:captured[@"Info.plist"]
		options:NSPropertyListImmutable format:NULL error:&propertyListError];
	if (![info isKindOfClass:[NSDictionary class]] ||
		!BTPluginSealedOuterInfoMatchesManifest(info, manifest, error)) {
		if (error && !*error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidInfoPlist,
				@"The sealed Info.plist is not a valid property-list dictionary.", @"Info.plist", propertyListError);
		return nil;
	}

	NSArray<BTPluginSealedFileState *> *sortedFiles = [files.allValues
		sortedArrayUsingComparator:^NSComparisonResult(BTPluginSealedFileState *left, BTPluginSealedFileState *right) {
			return BTPluginSealedComparePaths(left.logicalPath, right.logicalPath);
		}];
	CC_SHA256_CTX packageContext;
	CC_SHA256_Init(&packageContext);
	NSMutableDictionary<NSString *, BTPluginInspectedFile *> *publicFiles = [NSMutableDictionary dictionary];
	for (BTPluginSealedFileState *file in sortedFiles) {
		NSData *pathData = [file.logicalPath dataUsingEncoding:NSUTF8StringEncoding];
		uint8_t marker = 'F';
		uint32_t pathLength = CFSwapInt32HostToBig((uint32_t)pathData.length);
		uint8_t mode = [file.modeClass isEqualToString:@"executable"] ? 1 : 0;
		uint64_t logicalFileByteCount = (uint64_t)file.initialStat.st_size;
		NSData *logicalSHA256 = file.rawSHA256;
		if (manifest.payload.codeIdentity &&
			[file.logicalPath isEqualToString:manifest.payload.executablePath]) {
			BTPluginManifestFile *declaredExecutable = manifest.filesByPath[file.logicalPath];
			logicalFileByteCount = declaredExecutable.size;
			logicalSHA256 = BTPluginSealedDataFromHex(declaredExecutable.sha256);
		}
		uint64_t fileLength = CFSwapInt64HostToBig(logicalFileByteCount);
		CC_SHA256_Update(&packageContext, &marker, sizeof(marker));
		CC_SHA256_Update(&packageContext, &pathLength, sizeof(pathLength));
		CC_SHA256_Update(&packageContext, pathData.bytes, (CC_LONG)pathData.length);
		CC_SHA256_Update(&packageContext, &mode, sizeof(mode));
		CC_SHA256_Update(&packageContext, &fileLength, sizeof(fileLength));
		CC_SHA256_Update(&packageContext, logicalSHA256.bytes, (CC_LONG)logicalSHA256.length);
		publicFiles[file.logicalPath] = [BTPluginInspectedFile bt_fileWithRelativePath:file.logicalPath
			fileSize:(uint64_t)file.initialStat.st_size modeClass:file.modeClass sha256:file.sha256];
	}
	uint8_t packageDigest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(packageDigest, &packageContext);

	NSSet *currentMetadataPaths = BTPluginSealedCurrentPathSet(metadataRoot, nil, error);
	NSSet *currentPayloadPaths = BTPluginSealedCurrentPathSet(payloadRoot, manifest.payload.path, error);
	NSMutableSet *currentPaths = currentMetadataPaths ? [currentMetadataPaths mutableCopy] : nil;
	[currentPaths addObject:manifest.payload.path];
	[currentPaths unionSet:currentPayloadPaths];
	struct stat currentMetadataRootStat;
	struct stat currentPayloadRootStat;
	if (!currentMetadataPaths || !currentPayloadPaths || ![currentPaths isEqualToSet:allPaths] ||
		lstat(metadataRoot.fileSystemRepresentation, &currentMetadataRootStat) != 0 ||
		lstat(payloadRoot.fileSystemRepresentation, &currentPayloadRootStat) != 0 ||
		!BTPluginSealedStatsMatch(&metadataRootStat, &currentMetadataRootStat) ||
		!BTPluginSealedStatsMatch(&payloadRootStat, &currentPayloadRootStat)) {
		if (error && !*error)
			BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
				@"A sealed plug-in root changed during inspection.", nil, nil);
		return nil;
	}
	for (BTPluginSealedFileState *file in sortedFiles) {
		struct stat expected = file.initialStat;
		struct stat current;
		if (lstat(file.physicalURL.fileSystemRepresentation, &current) != 0 ||
			!BTPluginSealedStatsMatch(&expected, &current)) {
			BTPluginSealedFail(error, BTPluginPackageErrorRaceDetected,
				@"A sealed plug-in file identity changed during inspection.", file.logicalPath, nil);
			return nil;
		}
	}

	NSString *executablePrefix = [manifest.payload.path stringByAppendingString:@"/"];
	if (![manifest.payload.executablePath hasPrefix:executablePrefix]) {
		BTPluginSealedFail(error, BTPluginPackageErrorInvalidManifest,
			@"The sealed executable path is outside its logical bundle root.", manifest.payload.executablePath, nil);
		return nil;
	}
	NSString *physicalExecutableRelativePath = [manifest.payload.executablePath
		substringFromIndex:executablePrefix.length];
	return [BTPluginPackageInspection bt_inspectionWithPackageURL:metadataRoot
		manifest:manifest manifestData:manifestData manifestSHA256:files[@"Manifest.json"].sha256
		packageSHA256:BTPluginSealedHex(packageDigest, sizeof(packageDigest))
		outerInfoDictionary:info filesByPath:publicFiles signatureDataByKeyIdentifier:signatures
		includedPublisherKeysByIdentifier:publisherKeys payloadURL:payloadRoot
		executableURL:[payloadRoot URLByAppendingPathComponent:physicalExecutableRelativePath isDirectory:NO]
		sealedAppBundleRepresentation:YES];
}

@end
