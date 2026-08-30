//
//  BTPluginPackageStructuralVerifier.m
//  Battman
//

#import "BTPluginPackageStructuralVerifier.h"

#import "BTPluginPackageInspectionPrivate.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <limits.h>
#import <mach/machine.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <stddef.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../Model/BTPluginPackageErrors.h"

NSUInteger const BTPluginPackageMaximumRegularFileCount = 512;
uint64_t const BTPluginPackageMaximumTotalByteCount = 128ULL * 1024ULL * 1024ULL;
uint64_t const BTPluginPackageMaximumSingleFileByteCount = 64ULL * 1024ULL * 1024ULL;

static const uint64_t BTPluginPackageMaximumInfoPlistByteCount = 64ULL * 1024ULL;
static const uint64_t BTPluginPackageMaximumSignatureByteCount = 256;
static const uint64_t BTPluginPackageP256PublicKeyByteCount = 65;

static NSString *BTPluginHexString(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *output = [NSMutableData dataWithLength:length * 2];
	char *characters = output.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

static BOOL BTPluginStructuralFail(NSError **error,
									 BTPluginPackageErrorCode code,
									 NSString *description,
									 NSString *relativePath,
									 NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, relativePath, underlyingError);
	return NO;
}

typedef struct {
	uint64_t offset;
	uint64_t length;
} BTPluginMachONormalizedRange;

static BOOL BTPluginPReadExact(int descriptor, void *bytes, size_t length, uint64_t offset) {
	uint8_t *cursor = bytes;
	while (length > 0) {
		if (offset > (uint64_t)LLONG_MAX)
			return NO;
		ssize_t count = pread(descriptor, cursor, length, (off_t)offset);
		if (count <= 0)
			return NO;
		cursor += count;
		length -= (size_t)count;
		offset += (uint64_t)count;
	}
	return YES;
}

static BOOL BTPluginMachOIdentityStatsMatch(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_size == right->st_size && left->st_mode == right->st_mode &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

BOOL BTPluginComputeMachOCodeIdentityAtURL(NSURL *executableURL,
	NSString *relativePath, uint64_t *unsignedByteCount, NSString **sha256, NSError **error) {
	if (![executableURL isKindOfClass:[NSURL class]] || !executableURL.isFileURL) {
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
			@"A Mach-O code identity requires a local executable file.", relativePath, nil);
	}
	int descriptor = open(executableURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0) {
		return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"The payload executable could not be opened for code-identity inspection.", relativePath,
			[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
	}
	struct stat before;
	if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_nlink != 1 ||
		before.st_size < (off_t)sizeof(struct mach_header_64) ||
		(uint64_t)before.st_size > BTPluginPackageMaximumSingleFileByteCount) {
		close(descriptor);
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
			@"The payload executable is not one bounded regular Mach-O file.", relativePath, nil);
	}

	struct mach_header_64 header;
	if (!BTPluginPReadExact(descriptor, &header, sizeof(header), 0) || header.magic != MH_MAGIC_64 ||
		header.cputype != CPU_TYPE_ARM64 || (header.cpusubtype & ~CPU_SUBTYPE_MASK) != CPU_SUBTYPE_ARM64_ALL ||
		header.ncmds == 0 || header.ncmds > 4096 || header.sizeofcmds > 16 * 1024 * 1024 ||
		(uint64_t)header.sizeofcmds > (uint64_t)before.st_size - sizeof(header)) {
		close(descriptor);
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
			@"The resignable code identity requires one thin canonical arm64 Mach-O image.", relativePath, nil);
	}

	BTPluginMachONormalizedRange normalized[4];
	NSUInteger normalizedCount = 0;
	uint64_t commandOffset = sizeof(header);
	uint64_t commandEnd = sizeof(header) + (uint64_t)header.sizeofcmds;
	BOOL foundLinkedit = NO;
	BOOL foundCodeSignature = NO;
	struct segment_command_64 linkedit = {0};
	struct linkedit_data_command signature = {0};
	for (uint32_t index = 0; index < header.ncmds; index++) {
		struct load_command command;
		if (commandOffset > commandEnd || commandEnd - commandOffset < sizeof(command) ||
			!BTPluginPReadExact(descriptor, &command, sizeof(command), commandOffset) ||
			command.cmdsize < sizeof(command) || command.cmdsize % 8 != 0 ||
			(uint64_t)command.cmdsize > commandEnd - commandOffset) {
			close(descriptor);
			return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
				@"The Mach-O load-command table is malformed during code-identity inspection.", relativePath, nil);
		}
		if (command.cmd == LC_SEGMENT_64) {
			struct segment_command_64 segment;
			if (command.cmdsize < sizeof(segment) ||
				!BTPluginPReadExact(descriptor, &segment, sizeof(segment), commandOffset)) {
				close(descriptor);
				return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
					@"A Mach-O segment command is truncated during code-identity inspection.", relativePath, nil);
			}
			if (strncmp(segment.segname, SEG_LINKEDIT, sizeof(segment.segname)) == 0) {
				if (foundLinkedit) {
					close(descriptor);
					return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
						@"The Mach-O contains duplicate __LINKEDIT segments.", relativePath, nil);
				}
				foundLinkedit = YES;
				linkedit = segment;
				normalized[normalizedCount++] = (BTPluginMachONormalizedRange){
					commandOffset + offsetof(struct segment_command_64, vmsize), sizeof(segment.vmsize) };
				normalized[normalizedCount++] = (BTPluginMachONormalizedRange){
					commandOffset + offsetof(struct segment_command_64, filesize), sizeof(segment.filesize) };
			}
		} else if (command.cmd == LC_CODE_SIGNATURE) {
			if (foundCodeSignature || command.cmdsize != sizeof(signature) ||
				!BTPluginPReadExact(descriptor, &signature, sizeof(signature), commandOffset)) {
				close(descriptor);
				return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
					@"The Mach-O contains duplicate or malformed code-signature metadata.", relativePath, nil);
			}
			foundCodeSignature = YES;
			normalized[normalizedCount++] = (BTPluginMachONormalizedRange){
				commandOffset + offsetof(struct linkedit_data_command, dataoff), sizeof(signature.dataoff) };
			normalized[normalizedCount++] = (BTPluginMachONormalizedRange){
				commandOffset + offsetof(struct linkedit_data_command, datasize), sizeof(signature.datasize) };
		}
		commandOffset += command.cmdsize;
	}

	uint64_t fileByteCount = (uint64_t)before.st_size;
	uint64_t signatureEnd = (uint64_t)signature.dataoff + signature.datasize;
	uint64_t linkeditEnd = linkedit.fileoff + linkedit.filesize;
	uint64_t trailingByteCount = fileByteCount >= signatureEnd ? fileByteCount - signatureEnd : UINT64_MAX;
	if (commandOffset != commandEnd || !foundLinkedit || !foundCodeSignature || normalizedCount != 4 ||
		signature.dataoff < commandEnd || signature.dataoff % 16 != 0 || signature.datasize < 12 ||
		signatureEnd < signature.dataoff || signatureEnd > fileByteCount || trailingByteCount > 15 ||
		linkedit.filesize > linkedit.vmsize || linkedit.fileoff > signature.dataoff ||
		linkeditEnd < signatureEnd || linkeditEnd > fileByteCount) {
		close(descriptor);
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O code-signature envelope is not a bounded final __LINKEDIT region.", relativePath, nil);
	}
	if (trailingByteCount > 0) {
		uint8_t trailing[15] = {0};
		if (!BTPluginPReadExact(descriptor, trailing, (size_t)trailingByteCount, signatureEnd)) {
			close(descriptor);
			return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
				@"The Mach-O trailing signature padding could not be read.", relativePath, nil);
		}
		for (uint64_t index = 0; index < trailingByteCount; index++) {
			if (trailing[index] != 0) {
				close(descriptor);
				return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
					@"The Mach-O contains nonzero bytes after its code-signature envelope.", relativePath, nil);
			}
		}
	}

	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	while (offset < signature.dataoff) {
		size_t wanted = (size_t)MIN((uint64_t)sizeof(buffer), (uint64_t)signature.dataoff - offset);
		if (!BTPluginPReadExact(descriptor, buffer, wanted, offset)) {
			close(descriptor);
			return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
				@"The Mach-O changed while its code identity was computed.", relativePath, nil);
		}
		for (NSUInteger index = 0; index < normalizedCount; index++) {
			uint64_t rangeStart = normalized[index].offset;
			uint64_t rangeEnd = rangeStart + normalized[index].length;
			uint64_t blockEnd = offset + wanted;
			uint64_t overlapStart = MAX(offset, rangeStart);
			uint64_t overlapEnd = MIN(blockEnd, rangeEnd);
			if (overlapStart < overlapEnd)
				memset(buffer + (overlapStart - offset), 0, (size_t)(overlapEnd - overlapStart));
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)wanted);
		offset += wanted;
	}
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	struct stat after;
	BOOL unchanged = fstat(descriptor, &after) == 0 && BTPluginMachOIdentityStatsMatch(&before, &after);
	close(descriptor);
	if (!unchanged)
		return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"The Mach-O changed during code-identity inspection.", relativePath, nil);
	if (unsignedByteCount)
		*unsignedByteCount = signature.dataoff;
	if (sha256)
		*sha256 = BTPluginHexString(digest, sizeof(digest));
	return YES;
}

static NSComparisonResult BTPluginCompareRelativePaths(NSString *left, NSString *right) {
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

@interface BTPluginInspectedFile ()
@property (nonatomic, copy, readwrite) NSString *relativePath;
@property (nonatomic, readwrite) uint64_t fileSize;
@property (nonatomic, copy, readwrite) NSString *modeClass;
@property (nonatomic, copy, readwrite) NSString *sha256;
@property (nonatomic, copy) NSData *rawSHA256;
@property (nonatomic, copy) NSData *leadingBytes;
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic) dev_t device;
@property (nonatomic) ino_t inode;
@property (nonatomic) mode_t fileMode;
@property (nonatomic) time_t modificationSeconds;
@property (nonatomic) long modificationNanoseconds;
@property (nonatomic) time_t changeSeconds;
@property (nonatomic) long changeNanoseconds;
- (instancetype)bt_init;
@end

@implementation BTPluginInspectedFile
- (instancetype)bt_init { return [super init]; }
+ (instancetype)bt_fileWithRelativePath:(NSString *)relativePath
								 fileSize:(uint64_t)fileSize
								modeClass:(NSString *)modeClass
									sha256:(NSString *)sha256 {
	BTPluginInspectedFile *file = [[BTPluginInspectedFile alloc] bt_init];
	file.relativePath = relativePath;
	file.fileSize = fileSize;
	file.modeClass = modeClass;
	file.sha256 = sha256;
	return file;
}
@end

@interface BTPluginPackageInspection ()
@property (nonatomic, strong, readwrite) NSURL *packageURL;
@property (nonatomic, strong, readwrite) BTPluginPackageManifest *manifest;
@property (nonatomic, copy, readwrite) NSData *manifestData;
@property (nonatomic, copy, readwrite) NSString *manifestSHA256;
@property (nonatomic, copy, readwrite) NSString *packageSHA256;
@property (nonatomic, copy, readwrite) NSDictionary *outerInfoDictionary;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, BTPluginInspectedFile *> *filesByPath;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSData *> *signatureDataByKeyIdentifier;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSData *> *includedPublisherKeysByIdentifier;
@property (nonatomic, strong, readwrite) NSURL *payloadURL;
@property (nonatomic, strong, readwrite) NSURL *executableURL;
@property (nonatomic, readwrite, getter=isSealedAppBundleRepresentation) BOOL sealedAppBundleRepresentation;
- (instancetype)bt_init;
@end

@implementation BTPluginPackageInspection
- (instancetype)bt_init { return [super init]; }
+ (instancetype)bt_inspectionWithPackageURL:(NSURL *)packageURL
									 manifest:(BTPluginPackageManifest *)manifest
								 manifestData:(NSData *)manifestData
							 manifestSHA256:(NSString *)manifestSHA256
								 packageSHA256:(NSString *)packageSHA256
							 outerInfoDictionary:(NSDictionary *)outerInfoDictionary
									filesByPath:(NSDictionary<NSString *,BTPluginInspectedFile *> *)filesByPath
				 signatureDataByKeyIdentifier:(NSDictionary<NSString *,NSData *> *)signatureDataByKeyIdentifier
	includedPublisherKeysByIdentifier:(NSDictionary<NSString *,NSData *> *)includedPublisherKeysByIdentifier
									 payloadURL:(NSURL *)payloadURL
								 executableURL:(NSURL *)executableURL
				 sealedAppBundleRepresentation:(BOOL)sealedAppBundleRepresentation {
	BTPluginPackageInspection *inspection = [[BTPluginPackageInspection alloc] bt_init];
	inspection.packageURL = packageURL;
	inspection.manifest = manifest;
	inspection.manifestData = manifestData;
	inspection.manifestSHA256 = manifestSHA256;
	inspection.packageSHA256 = packageSHA256;
	inspection.outerInfoDictionary = outerInfoDictionary;
	inspection.filesByPath = filesByPath;
	inspection.signatureDataByKeyIdentifier = signatureDataByKeyIdentifier;
	inspection.includedPublisherKeysByIdentifier = includedPublisherKeysByIdentifier;
	inspection.payloadURL = payloadURL;
	inspection.executableURL = executableURL;
	inspection.sealedAppBundleRepresentation = sealedAppBundleRepresentation;
	return inspection;
}
@end

static BOOL BTPluginStatIsUnchanged(const struct stat *expected, const struct stat *actual) {
	return expected->st_dev == actual->st_dev && expected->st_ino == actual->st_ino &&
		expected->st_size == actual->st_size && expected->st_mtimespec.tv_sec == actual->st_mtimespec.tv_sec &&
		expected->st_mtimespec.tv_nsec == actual->st_mtimespec.tv_nsec &&
		expected->st_ctimespec.tv_sec == actual->st_ctimespec.tv_sec &&
		expected->st_ctimespec.tv_nsec == actual->st_ctimespec.tv_nsec && expected->st_mode == actual->st_mode;
}

static BOOL BTPluginReadAndHashFile(BTPluginInspectedFile *file,
											 uint64_t captureLimit,
											 NSData **capturedData,
											 NSError **error) {
	if (captureLimit > 0 && file.fileSize > captureLimit)
		return BTPluginStructuralFail(error, BTPluginPackageErrorLimitExceeded,
			@"A bounded package metadata file exceeds its size limit.", file.relativePath, nil);
	int descriptor = open(file.fileURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0)
		return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"A package file could not be opened without following links.", file.relativePath, nil);

	struct stat before;
	if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_nlink != 1 ||
		before.st_dev != file.device || before.st_ino != file.inode || before.st_size < 0 ||
		(uint64_t)before.st_size != file.fileSize || before.st_mode != file.fileMode ||
		before.st_mtimespec.tv_sec != file.modificationSeconds || before.st_mtimespec.tv_nsec != file.modificationNanoseconds ||
		before.st_ctimespec.tv_sec != file.changeSeconds || before.st_ctimespec.tv_nsec != file.changeNanoseconds) {
		close(descriptor);
		return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"A package file changed between enumeration and opening.", file.relativePath, nil);
	}

	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	NSMutableData *captured = capturedData ? [NSMutableData dataWithCapacity:(NSUInteger)file.fileSize] : nil;
	NSMutableData *leadingBytes = [NSMutableData dataWithCapacity:sizeof(uint32_t)];
	uint8_t buffer[64 * 1024];
	uint64_t totalRead = 0;
	while (YES) {
		ssize_t count = read(descriptor, buffer, sizeof(buffer));
		if (count < 0) {
			close(descriptor);
			return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidPackage,
				@"A package file could not be read.", file.relativePath, nil);
		}
		if (count == 0)
			break;
		totalRead += (uint64_t)count;
		if (totalRead > file.fileSize) {
			close(descriptor);
			return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
				@"A package file grew while it was being inspected.", file.relativePath, nil);
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		if (leadingBytes.length < sizeof(uint32_t)) {
			NSUInteger wanted = sizeof(uint32_t) - leadingBytes.length;
			[leadingBytes appendBytes:buffer length:MIN(wanted, (NSUInteger)count)];
		}
		[captured appendBytes:buffer length:(NSUInteger)count];
	}

	struct stat after;
	BOOL unchanged = fstat(descriptor, &after) == 0 && BTPluginStatIsUnchanged(&before, &after) && totalRead == file.fileSize;
	close(descriptor);
	if (!unchanged)
		return BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"A package file changed while it was being inspected.", file.relativePath, nil);

	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	file.rawSHA256 = [NSData dataWithBytes:digest length:sizeof(digest)];
	file.sha256 = BTPluginHexString(digest, sizeof(digest));
	file.leadingBytes = leadingBytes;
	if (capturedData)
		*capturedData = captured;
	return YES;
}

static BOOL BTPluginValidateEntryMode(struct stat entryStat,
										NSString *relativePath,
										NSError **error) {
	mode_t unsafe = S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX;
	if ((entryStat.st_mode & unsafe) != 0)
		return BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
			@"Package entries cannot be set-id, sticky, or group/other writable.", relativePath, nil);
	if (S_ISDIR(entryStat.st_mode)) {
		if ((entryStat.st_mode & (S_IRUSR | S_IXUSR)) != (S_IRUSR | S_IXUSR))
			return BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
				@"Package directories must be readable and searchable by their owner.", relativePath, nil);
		return YES;
	}
	if (S_ISREG(entryStat.st_mode)) {
		if ((entryStat.st_mode & S_IRUSR) == 0)
			return BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
				@"Package files must be readable by their owner.", relativePath, nil);
		return YES;
	}
	return BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
		@"Packages may contain only directories and regular files.", relativePath, nil);
}

static NSString *BTPluginModeClass(mode_t mode) {
	return (mode & (S_IXUSR | S_IXGRP | S_IXOTH)) == 0 ? @"data" : @"executable";
}

static BOOL BTPluginFileHasMachOMagic(BTPluginInspectedFile *file) {
	if (file.leadingBytes.length != sizeof(uint32_t))
		return NO;
	uint32_t magic = 0;
	memcpy(&magic, file.leadingBytes.bytes, sizeof(magic));
	return magic == MH_MAGIC || magic == MH_CIGAM || magic == MH_MAGIC_64 || magic == MH_CIGAM_64 ||
		magic == FAT_MAGIC || magic == FAT_CIGAM || magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64;
}

static BOOL BTPluginPathHasAllowedRootRole(NSString *path, BTPluginPackageManifest *manifest) {
	if ([path isEqualToString:@"Info.plist"])
		return YES;
	if ([path hasPrefix:@"PublisherKeys/"])
		return YES;
	if ([manifest.payload.kind isEqualToString:@"so"])
		return [path isEqualToString:manifest.payload.path];
	return [path hasPrefix:[manifest.payload.path stringByAppendingString:@"/"]];
}

static BOOL BTPluginOuterInfoMatchesManifest(NSDictionary *info,
														 BTPluginPackageManifest *manifest,
														 NSError **error) {
	NSDictionary<NSString *, NSString *> *expectedStrings = @{
		@"CFBundleIdentifier": manifest.pluginIdentifier,
		@"CFBundleDisplayName": manifest.displayName,
		@"CFBundleShortVersionString": manifest.displayVersion,
		@"CFBundleVersion": manifest.buildVersion,
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPublisherKeyIdentifier": manifest.publisher.primaryKeyIdentifier,
	};
	for (NSString *key in expectedStrings) {
		id value = info[key];
		if (![value isKindOfClass:[NSString class]] || ![value isEqualToString:expectedStrings[key]])
			return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"Info.plist preview metadata does not match the signed manifest.", @"Info.plist", nil);
	}
	id formatVersion = info[@"BTPluginPackageFormatVersion"];
	if (![formatVersion isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)formatVersion) == CFBooleanGetTypeID() ||
		CFNumberIsFloatType((__bridge CFNumberRef)formatVersion) || [formatVersion longLongValue] != 1)
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"Info.plist has an invalid package format version.", @"Info.plist", nil);
	return YES;
}

static BOOL BTPluginBundleInfoMatchesManifest(NSDictionary *info,
	BTPluginPackageManifest *manifest, NSString *relativePath, NSError **error) {
	NSString *executableName = info[@"CFBundleExecutable"];
	NSString *executablePrefix = [manifest.payload.path stringByAppendingString:@"/"];
	NSString *declaredExecutableName = [manifest.payload.executablePath hasPrefix:executablePrefix] ?
		[manifest.payload.executablePath substringFromIndex:executablePrefix.length] : nil;
	if (![executableName isKindOfClass:[NSString class]] || executableName.length == 0 ||
		executableName.length > 255 || [executableName containsString:@"/"] ||
		![declaredExecutableName isEqualToString:executableName]) {
		return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"The bundle Info.plist executable does not match the direct signed payload executable.",
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
			return BTPluginStructuralFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"The bundle Info.plist identity does not match the signed manifest.", relativePath, nil);
	}
	return YES;
}

@implementation BTPluginPackageStructuralVerifier

- (BTPluginPackageInspection *)inspectPackageAtURL:(NSURL *)packageURL error:(NSError **)error {
	if (![packageURL isKindOfClass:[NSURL class]] || !packageURL.isFileURL ||
		![[packageURL.path pathExtension] isEqualToString:@"battman"]) {
		BTPluginStructuralFail(error, BTPluginPackageErrorInvalidPackage,
			@"A plug-in package must be a local directory with the .battman extension.", nil, nil);
		return nil;
	}
	NSURL *standardURL = packageURL.URLByStandardizingPath;
	struct stat rootStat;
	if (lstat(standardURL.fileSystemRepresentation, &rootStat) != 0 || !S_ISDIR(rootStat.st_mode) ||
		!BTPluginValidateEntryMode(rootStat, @".", error)) {
		if (error && !*error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidPackage,
				@"The .battman path is not a readable directory package.", nil, nil);
		return nil;
	}
	char resolvedRoot[PATH_MAX];
	if (!realpath(standardURL.fileSystemRepresentation, resolvedRoot)) {
		BTPluginStructuralFail(error, BTPluginPackageErrorInvalidPackage,
			@"The package root could not be resolved.", nil, nil);
		return nil;
	}
	NSURL *rootURL = [NSURL fileURLWithFileSystemRepresentation:resolvedRoot isDirectory:YES relativeToURL:nil];

	NSString *rootPath = rootURL.path;
	NSString *rootPrefix = [rootPath stringByAppendingString:@"/"];
	NSMutableDictionary<NSString *, BTPluginInspectedFile *> *regularFiles = [NSMutableDictionary dictionary];
	NSMutableSet<NSString *> *directoryPaths = [NSMutableSet set];
	NSMutableSet<NSString *> *allPaths = [NSMutableSet set];
	NSMutableSet<NSString *> *foldedPaths = [NSMutableSet set];
	NSMutableDictionary<NSString *, NSData *> *capturedData = [NSMutableDictionary dictionary];
	__block NSError *enumerationError = nil;
	NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
		enumeratorAtURL:rootURL
		includingPropertiesForKeys:nil
		options:0
		errorHandler:^BOOL(NSURL *url, NSError *underlyingError) {
			(void)url;
			enumerationError = BTPluginPackageMakeError(BTPluginPackageErrorInvalidPackage,
				@"The package directory could not be enumerated.", nil, underlyingError);
			return NO;
		}];

	uint64_t totalBytes = 0;
	for (NSURL *entryURL in enumerator) {
		NSString *entryPath = entryURL.path;
		if (![entryPath hasPrefix:rootPrefix]) {
			BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
				@"A package entry escapes its directory.", nil, nil);
			return nil;
		}
		NSString *relativePath = [entryPath substringFromIndex:rootPrefix.length];
		NSString *foldedPath = [relativePath lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
		if (!BTPluginPackageRelativePathIsValid(relativePath) || [foldedPaths containsObject:foldedPath]) {
			BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
				@"A package path is unsafe, non-canonical, duplicated, or case-colliding.", relativePath, nil);
			return nil;
		}
		[foldedPaths addObject:foldedPath];
		[allPaths addObject:relativePath];

		struct stat entryStat;
		if (lstat(entryURL.fileSystemRepresentation, &entryStat) != 0 ||
			!BTPluginValidateEntryMode(entryStat, relativePath, error))
			return nil;
		if (S_ISLNK(entryStat.st_mode)) {
			BTPluginStructuralFail(error, BTPluginPackageErrorUnsafePath,
				@"Symbolic links are not permitted in plug-in packages.", relativePath, nil);
			return nil;
		}
		if (S_ISDIR(entryStat.st_mode)) {
			[directoryPaths addObject:relativePath];
			continue;
		}
		if (entryStat.st_nlink != 1 || entryStat.st_size < 0 ||
			(uint64_t)entryStat.st_size > BTPluginPackageMaximumSingleFileByteCount) {
			BTPluginStructuralFail(error, entryStat.st_nlink != 1 ? BTPluginPackageErrorUnsafePath : BTPluginPackageErrorLimitExceeded,
				entryStat.st_nlink != 1 ? @"Hard-linked files are not permitted in plug-in packages." : @"A package file exceeds 64 MiB.",
				relativePath, nil);
			return nil;
		}
		if (regularFiles.count + 1 > BTPluginPackageMaximumRegularFileCount ||
			UINT64_MAX - totalBytes < (uint64_t)entryStat.st_size ||
			(totalBytes += (uint64_t)entryStat.st_size) > BTPluginPackageMaximumTotalByteCount) {
			BTPluginStructuralFail(error, BTPluginPackageErrorLimitExceeded,
				@"The package exceeds its file-count or 128 MiB total-size limit.", relativePath, nil);
			return nil;
		}

		BTPluginInspectedFile *file = [[BTPluginInspectedFile alloc] bt_init];
		file.relativePath = relativePath;
		file.fileSize = (uint64_t)entryStat.st_size;
		file.modeClass = BTPluginModeClass(entryStat.st_mode);
		file.fileURL = entryURL;
		file.device = entryStat.st_dev;
		file.inode = entryStat.st_ino;
		file.fileMode = entryStat.st_mode;
		file.modificationSeconds = entryStat.st_mtimespec.tv_sec;
		file.modificationNanoseconds = entryStat.st_mtimespec.tv_nsec;
		file.changeSeconds = entryStat.st_ctimespec.tv_sec;
		file.changeNanoseconds = entryStat.st_ctimespec.tv_nsec;
		uint64_t captureLimit = 0;
		if ([relativePath isEqualToString:@"Manifest.json"])
			captureLimit = BTPluginManifestMaximumByteCount;
		else if ([relativePath isEqualToString:@"Info.plist"])
			captureLimit = BTPluginPackageMaximumInfoPlistByteCount;
		else if ([relativePath hasPrefix:@"Signatures/"])
			captureLimit = BTPluginPackageMaximumSignatureByteCount;
		else if ([relativePath hasPrefix:@"PublisherKeys/"])
			captureLimit = BTPluginPackageP256PublicKeyByteCount;
		NSData *data = nil;
		if (!BTPluginReadAndHashFile(file, captureLimit, captureLimit > 0 ? &data : NULL, error))
			return nil;
		if (data)
			capturedData[relativePath] = data;
		regularFiles[relativePath] = file;
	}
	if (enumerationError) {
		if (error)
			*error = enumerationError;
		return nil;
	}

	NSData *manifestData = capturedData[@"Manifest.json"];
	if (!manifestData || !regularFiles[@"Info.plist"] || ![directoryPaths containsObject:@"Signatures"]) {
		BTPluginStructuralFail(error, BTPluginPackageErrorMissingFile,
			@"The package must contain Manifest.json, Info.plist, and Signatures/.", nil, nil);
		return nil;
	}
	BTPluginPackageManifest *manifest = [BTPluginPackageManifest manifestWithData:manifestData error:error];
	if (!manifest)
		return nil;

	NSMutableSet<NSString *> *allowedFiles = [NSMutableSet setWithObject:@"Manifest.json"];
	for (BTPluginManifestFile *declaredFile in manifest.files) {
		if (!BTPluginPathHasAllowedRootRole(declaredFile.path, manifest)) {
			BTPluginStructuralFail(error, BTPluginPackageErrorInvalidManifest,
				@"A manifest file has no v1 package role.", declaredFile.path, nil);
			return nil;
		}
		[allowedFiles addObject:declaredFile.path];
	}

	NSMutableDictionary<NSString *, NSData *> *signatures = [NSMutableDictionary dictionary];
	for (NSString *keyIdentifier in manifest.publisher.signatureKeyIdentifiers) {
		NSString *signaturePath = [NSString stringWithFormat:@"Signatures/%@.sig", keyIdentifier];
		BTPluginInspectedFile *signatureFile = regularFiles[signaturePath];
		NSData *signatureData = capturedData[signaturePath];
		if (!signatureFile || !signatureData || signatureData.length == 0 || signatureData.length > BTPluginPackageMaximumSignatureByteCount ||
			![signatureFile.modeClass isEqualToString:@"data"]) {
			BTPluginStructuralFail(error, BTPluginPackageErrorMissingFile,
				@"A declared publisher signature is missing or invalid.", signaturePath, nil);
			return nil;
		}
		signatures[keyIdentifier] = signatureData;
		[allowedFiles addObject:signaturePath];
	}
	NSSet *actualFilePaths = [NSSet setWithArray:regularFiles.allKeys];
	if (![actualFilePaths isEqualToSet:allowedFiles]) {
		NSMutableSet *unexpected = [actualFilePaths mutableCopy];
		[unexpected minusSet:allowedFiles];
		NSMutableSet *missing = [allowedFiles mutableCopy];
		[missing minusSet:actualFilePaths];
		NSString *path = unexpected.anyObject ?: missing.anyObject;
		BTPluginStructuralFail(error, unexpected.count ? BTPluginPackageErrorUnexpectedFile : BTPluginPackageErrorMissingFile,
			unexpected.count ? @"The package contains a file absent from the signed inventory." : @"The package is missing a signed inventory file.",
			path, nil);
		return nil;
	}

	for (BTPluginManifestFile *declaredFile in manifest.files) {
		BTPluginInspectedFile *actualFile = regularFiles[declaredFile.path];
		if (actualFile.fileSize != declaredFile.size || ![actualFile.modeClass isEqualToString:declaredFile.mode] ||
			![actualFile.sha256 isEqualToString:declaredFile.sha256]) {
			BTPluginStructuralFail(error, BTPluginPackageErrorHashMismatch,
				@"A package file does not match its signed size, mode, or SHA-256.", declaredFile.path, nil);
			return nil;
		}
		if ([actualFile.modeClass isEqualToString:@"executable"]) {
			struct stat executableStat;
			if (lstat(actualFile.fileURL.fileSystemRepresentation, &executableStat) != 0 ||
				(executableStat.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != (S_IXUSR | S_IXGRP | S_IXOTH)) {
				BTPluginStructuralFail(error, BTPluginPackageErrorHashMismatch,
					@"The declared payload executable does not have normalized executable permissions.", declaredFile.path, nil);
				return nil;
			}
		}
		if (![declaredFile.path isEqualToString:manifest.payload.executablePath] && BTPluginFileHasMachOMagic(actualFile)) {
			BTPluginStructuralFail(error, BTPluginPackageErrorInvalidMachO,
				@"The package contains a Mach-O image outside the single declared payload executable.",
				declaredFile.path, nil);
			return nil;
		}
	}

	if ([manifest.payload.kind isEqualToString:@"bundle"]) {
		NSString *bundleInfoPath = [manifest.payload.path stringByAppendingPathComponent:@"Info.plist"];
		BTPluginManifestFile *declaredBundleInfo = manifest.filesByPath[bundleInfoPath];
		BTPluginInspectedFile *actualBundleInfo = regularFiles[bundleInfoPath];
		if (!declaredBundleInfo || !actualBundleInfo || ![declaredBundleInfo.mode isEqualToString:@"data"] ||
			declaredBundleInfo.size > BTPluginPackageMaximumInfoPlistByteCount) {
			BOOL oversized = declaredBundleInfo && declaredBundleInfo.size > BTPluginPackageMaximumInfoPlistByteCount;
			BTPluginStructuralFail(error, oversized ? BTPluginPackageErrorLimitExceeded : BTPluginPackageErrorMissingFile,
				oversized ? @"The signed bundle Info.plist exceeds 64 KiB." :
				@"A bundle payload must contain one bounded signed Info.plist.", bundleInfoPath, nil);
			return nil;
		}
		NSData *bundleInfoData = nil;
		if (!BTPluginReadAndHashFile(actualBundleInfo, BTPluginPackageMaximumInfoPlistByteCount,
			&bundleInfoData, error) || actualBundleInfo.fileSize != declaredBundleInfo.size ||
			![actualBundleInfo.sha256 isEqualToString:declaredBundleInfo.sha256]) {
			if (error && !*error)
				BTPluginStructuralFail(error, BTPluginPackageErrorHashMismatch,
					@"The bundle Info.plist changed after signed inventory verification.", bundleInfoPath, nil);
			return nil;
		}
		NSError *bundlePropertyListError = nil;
		id bundleInfo = [NSPropertyListSerialization propertyListWithData:bundleInfoData
			options:NSPropertyListImmutable format:NULL error:&bundlePropertyListError];
		if (![bundleInfo isKindOfClass:[NSDictionary class]] ||
			!BTPluginBundleInfoMatchesManifest(bundleInfo, manifest, bundleInfoPath, error)) {
			if (error && !*error)
				*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidInfoPlist,
					@"The signed bundle Info.plist is not a valid property-list dictionary.",
					bundleInfoPath, bundlePropertyListError);
			return nil;
		}
	}
	if (manifest.payload.codeIdentity) {
		uint64_t unsignedByteCount = 0;
		NSString *codeSHA256 = nil;
		BTPluginInspectedFile *executableFile = regularFiles[manifest.payload.executablePath];
		if (!BTPluginComputeMachOCodeIdentityAtURL(executableFile.fileURL,
			manifest.payload.executablePath, &unsignedByteCount, &codeSHA256, error) ||
			unsignedByteCount != manifest.payload.codeIdentity.unsignedByteCount ||
			![codeSHA256 isEqualToString:manifest.payload.codeIdentity.sha256]) {
			if (error && !*error)
				BTPluginStructuralFail(error, BTPluginPackageErrorHashMismatch,
					@"The payload executable does not match its signed code identity.",
					manifest.payload.executablePath, nil);
			return nil;
		}
	}

	if ([manifest.payload.kind isEqualToString:@"bundle"] && ![directoryPaths containsObject:manifest.payload.path]) {
		BTPluginStructuralFail(error, BTPluginPackageErrorMissingFile,
			@"The declared bundle payload directory is missing.", manifest.payload.path, nil);
		return nil;
	}
	for (NSString *directoryPath in directoryPaths) {
		BOOL used = NO;
		NSString *prefix = [directoryPath stringByAppendingString:@"/"];
		for (NSString *filePath in allowedFiles) {
			if ([filePath hasPrefix:prefix]) {
				used = YES;
				break;
			}
		}
		if (!used) {
			BTPluginStructuralFail(error, BTPluginPackageErrorUnexpectedFile,
				@"The package contains an empty or unlisted directory.", directoryPath, nil);
			return nil;
		}
	}

	NSMutableDictionary<NSString *, NSData *> *publisherKeys = [NSMutableDictionary dictionary];
	for (NSString *path in regularFiles) {
		if (![path hasPrefix:@"PublisherKeys/"])
			continue;
		NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
		NSString *fileName = components.lastObject;
		NSString *keyIdentifier = fileName.stringByDeletingPathExtension;
		NSData *keyData = capturedData[path];
		if (components.count != 2 || ![[fileName pathExtension] isEqualToString:@"p256"] ||
			!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) || keyData.length != BTPluginPackageP256PublicKeyByteCount ||
			((const uint8_t *)keyData.bytes)[0] != 0x04 || ![regularFiles[path].sha256 isEqualToString:keyIdentifier] ||
			![manifest.publisher.signatureKeyIdentifiers containsObject:keyIdentifier]) {
			BTPluginStructuralFail(error, BTPluginPackageErrorInvalidManifest,
				@"An included publisher key has an invalid path, size, encoding, fingerprint, or signature role.", path, nil);
			return nil;
		}
		publisherKeys[keyIdentifier] = keyData;
	}

	NSData *infoData = capturedData[@"Info.plist"];
	NSError *propertyListError = nil;
	id info = [NSPropertyListSerialization propertyListWithData:infoData
		options:NSPropertyListImmutable format:NULL error:&propertyListError];
	if (![info isKindOfClass:[NSDictionary class]] || !BTPluginOuterInfoMatchesManifest(info, manifest, error)) {
		if (error && !*error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidInfoPlist,
				@"Info.plist is not a valid property-list dictionary.", @"Info.plist", propertyListError);
		return nil;
	}

	NSArray<BTPluginInspectedFile *> *sortedFiles = [regularFiles.allValues sortedArrayUsingComparator:^NSComparisonResult(BTPluginInspectedFile *left, BTPluginInspectedFile *right) {
		return BTPluginCompareRelativePaths(left.relativePath, right.relativePath);
	}];
	CC_SHA256_CTX packageContext;
	CC_SHA256_Init(&packageContext);
	for (BTPluginInspectedFile *file in sortedFiles) {
		NSData *pathData = [file.relativePath dataUsingEncoding:NSUTF8StringEncoding];
		uint8_t marker = 'F';
		uint32_t pathLength = CFSwapInt32HostToBig((uint32_t)pathData.length);
		uint8_t mode = [file.modeClass isEqualToString:@"executable"] ? 1 : 0;
		uint64_t fileLength = CFSwapInt64HostToBig(file.fileSize);
		CC_SHA256_Update(&packageContext, &marker, sizeof(marker));
		CC_SHA256_Update(&packageContext, &pathLength, sizeof(pathLength));
		CC_SHA256_Update(&packageContext, pathData.bytes, (CC_LONG)pathData.length);
		CC_SHA256_Update(&packageContext, &mode, sizeof(mode));
		CC_SHA256_Update(&packageContext, &fileLength, sizeof(fileLength));
		CC_SHA256_Update(&packageContext, file.rawSHA256.bytes, (CC_LONG)file.rawSHA256.length);
	}
	uint8_t packageDigest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(packageDigest, &packageContext);

	NSMutableSet<NSString *> *secondPathSet = [NSMutableSet set];
	__block NSError *secondEnumerationError = nil;
	NSDirectoryEnumerator<NSURL *> *secondEnumerator = [[NSFileManager defaultManager]
		enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:0 errorHandler:^BOOL(NSURL *url, NSError *underlyingError) {
			(void)url;
			secondEnumerationError = underlyingError;
			return NO;
		}];
	for (NSURL *entryURL in secondEnumerator) {
		NSString *entryPath = entryURL.path;
		if (![entryPath hasPrefix:rootPrefix])
			continue;
		[secondPathSet addObject:[entryPath substringFromIndex:rootPrefix.length]];
	}
	if (secondEnumerationError || ![secondPathSet isEqualToSet:allPaths]) {
		BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
			@"The package tree changed while it was being inspected.", nil, secondEnumerationError);
		return nil;
	}
	for (BTPluginInspectedFile *file in sortedFiles) {
		struct stat current;
		if (lstat(file.fileURL.fileSystemRepresentation, &current) != 0 || current.st_dev != file.device ||
			current.st_ino != file.inode || current.st_size < 0 || (uint64_t)current.st_size != file.fileSize ||
			current.st_mode != file.fileMode || current.st_mtimespec.tv_sec != file.modificationSeconds ||
			current.st_mtimespec.tv_nsec != file.modificationNanoseconds || current.st_ctimespec.tv_sec != file.changeSeconds ||
			current.st_ctimespec.tv_nsec != file.changeNanoseconds) {
			BTPluginStructuralFail(error, BTPluginPackageErrorRaceDetected,
				@"A package file identity changed during inspection.", file.relativePath, nil);
			return nil;
		}
	}

	BTPluginPackageInspection *inspection = [[BTPluginPackageInspection alloc] bt_init];
	inspection.packageURL = rootURL;
	inspection.manifest = manifest;
	inspection.manifestData = manifestData;
	inspection.manifestSHA256 = regularFiles[@"Manifest.json"].sha256;
	inspection.packageSHA256 = BTPluginHexString(packageDigest, sizeof(packageDigest));
	inspection.outerInfoDictionary = info;
	inspection.filesByPath = regularFiles;
	inspection.signatureDataByKeyIdentifier = signatures;
	inspection.includedPublisherKeysByIdentifier = publisherKeys;
	inspection.payloadURL = [rootURL URLByAppendingPathComponent:manifest.payload.path isDirectory:[manifest.payload.kind isEqualToString:@"bundle"]];
	inspection.executableURL = [rootURL URLByAppendingPathComponent:manifest.payload.executablePath isDirectory:NO];
	return inspection;
}

@end
