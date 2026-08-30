//
//  BTPluginMachOInspector.m
//  Battman
//

#import "BTPluginMachOInspector.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <TargetConditionals.h>
#import <fcntl.h>
#import <mach/machine.h>
#import <mach-o/fat.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/vm_prot.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../Model/BTPluginPackageErrors.h"

static const uint32_t BTPluginMaximumFatArchitectureCount = 16;
static const uint32_t BTPluginMaximumLoadCommandCount = 4096;
static const uint32_t BTPluginMaximumSymbolCount = 262144;
static const uint32_t BTPluginMaximumStringTableByteCount = 16 * 1024 * 1024;
static const uint32_t BTPluginMaximumExportTrieByteCount = 1024 * 1024;
static const NSUInteger BTPluginMaximumExportTrieNodeCount = 4096;
static const uint32_t BTPluginMaximumCodeSignatureBlobCount = 64;
static const uint32_t BTPluginMaximumCodeSignatureByteCount = 16 * 1024 * 1024;

static const uint32_t BTPluginCodeSigningMagicCodeDirectory = 0xfade0c02;
static const uint32_t BTPluginCodeSigningMagicEmbeddedSignature = 0xfade0cc0;
static const uint32_t BTPluginCodeSigningSlotCodeDirectory = 0;
static const uint32_t BTPluginCodeSigningSlotFirstAlternateCodeDirectory = 0x1000;
static const uint32_t BTPluginCodeSigningSlotLastAlternateCodeDirectory = 0x1005;
static const uint8_t BTPluginCodeSigningHashTypeSHA1 = 1;
static const uint8_t BTPluginCodeSigningHashTypeSHA256 = 2;

static BOOL BTPluginMachOBuildPlatformMatchesHost(uint32_t platform) {
#if TARGET_OS_SIMULATOR
	return platform == PLATFORM_IOSSIMULATOR;
#else
	return platform == PLATFORM_IOS;
#endif
}

static BOOL BTPluginMachOLegacyIOSVersionCommandMatchesHost(void) {
#if TARGET_OS_SIMULATOR
	return NO;
#else
	return YES;
#endif
}

static BOOL BTPluginMachOFail(NSError **error,
							 BTPluginPackageErrorCode code,
							 NSString *description,
							 NSString *relativePath,
							 NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, relativePath, underlyingError);
	return NO;
}

static BOOL BTPluginRangeIsValid(uint64_t offset, uint64_t length, uint64_t limit) {
	return offset <= limit && length <= limit - offset;
}

static BOOL BTPluginRangesOverlap(uint64_t firstOffset,
								  uint64_t firstLength,
								  uint64_t secondOffset,
								  uint64_t secondLength) {
	return firstLength != 0 && secondLength != 0 && firstOffset < secondOffset + secondLength &&
		secondOffset < firstOffset + firstLength;
}

static uint32_t BTPluginReadBig32(const uint8_t *bytes) {
	uint32_t value = 0;
	memcpy(&value, bytes, sizeof(value));
	return CFSwapInt32BigToHost(value);
}

static uint64_t BTPluginReadBig64(const uint8_t *bytes) {
	uint64_t value = 0;
	memcpy(&value, bytes, sizeof(value));
	return CFSwapInt64BigToHost(value);
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

@interface BTPluginMachOReader : NSObject
@property (nonatomic) int descriptor;
@property (nonatomic) uint64_t fileByteCount;
@property (nonatomic) struct stat openingStat;
@property (nonatomic, copy) NSString *relativePath;
- (nullable instancetype)initWithInspection:(BTPluginPackageInspection *)inspection
										 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)readBytes:(void *)bytes
				length:(NSUInteger)length
				 offset:(uint64_t)offset
				 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)verifyUnchanged:(NSError * _Nullable * _Nullable)error;
@end

@implementation BTPluginMachOReader

- (instancetype)initWithInspection:(BTPluginPackageInspection *)inspection error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	_descriptor = -1;
	_relativePath = [inspection.manifest.payload.executablePath copy];
	_descriptor = open(inspection.executableURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (_descriptor < 0) {
		BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
			@"The payload executable could not be reopened without following links.", _relativePath, nil);
		return nil;
	}
	if (fstat(_descriptor, &_openingStat) != 0 || !S_ISREG(_openingStat.st_mode) || _openingStat.st_nlink != 1 ||
		_openingStat.st_size < 0 || (uint64_t)_openingStat.st_size != inspection.filesByPath[_relativePath].fileSize) {
		BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
			@"The payload executable identity changed after structural verification.", _relativePath, nil);
		close(_descriptor);
		_descriptor = -1;
		return nil;
	}
	_fileByteCount = (uint64_t)_openingStat.st_size;

	CC_SHA256_CTX hashContext;
	CC_SHA256_Init(&hashContext);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	while (offset < _fileByteCount) {
		NSUInteger wanted = (NSUInteger)MIN((uint64_t)sizeof(buffer), _fileByteCount - offset);
		ssize_t count = pread(_descriptor, buffer, wanted, (off_t)offset);
		if (count <= 0 || (NSUInteger)count != wanted) {
			BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
				@"The payload executable changed while its content hash was checked.", _relativePath, nil);
			close(_descriptor);
			_descriptor = -1;
			return nil;
		}
		CC_SHA256_Update(&hashContext, buffer, (CC_LONG)count);
		offset += (uint64_t)count;
	}
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &hashContext);
	if (![BTPluginHexDigest(digest, sizeof(digest)) isEqualToString:inspection.filesByPath[_relativePath].sha256] ||
		![self verifyUnchanged:error]) {
		if (error && !*error)
			BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
				@"The payload executable no longer matches its structurally verified digest.", _relativePath, nil);
		close(_descriptor);
		_descriptor = -1;
		return nil;
	}
	return self;
}

- (void)dealloc {
	if (_descriptor >= 0)
		close(_descriptor);
}

- (BOOL)readBytes:(void *)bytes length:(NSUInteger)length offset:(uint64_t)offset error:(NSError **)error {
	if (!BTPluginRangeIsValid(offset, length, self.fileByteCount) || offset > (uint64_t)LLONG_MAX) {
		return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"A Mach-O structure points outside the executable file.", self.relativePath, nil);
	}
	uint8_t *cursor = bytes;
	NSUInteger remaining = length;
	while (remaining > 0) {
		ssize_t count = pread(self.descriptor, cursor, remaining, (off_t)offset);
		if (count <= 0) {
			return BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
				@"The payload executable could not be read completely during inspection.", self.relativePath, nil);
		}
		cursor += count;
		remaining -= (NSUInteger)count;
		offset += (uint64_t)count;
	}
	return YES;
}

- (BOOL)verifyUnchanged:(NSError **)error {
	struct stat current;
	if (fstat(self.descriptor, &current) != 0 || current.st_dev != self.openingStat.st_dev ||
		current.st_ino != self.openingStat.st_ino || current.st_size != self.openingStat.st_size ||
		current.st_mode != self.openingStat.st_mode ||
		current.st_mtimespec.tv_sec != self.openingStat.st_mtimespec.tv_sec ||
		current.st_mtimespec.tv_nsec != self.openingStat.st_mtimespec.tv_nsec ||
		current.st_ctimespec.tv_sec != self.openingStat.st_ctimespec.tv_sec ||
		current.st_ctimespec.tv_nsec != self.openingStat.st_ctimespec.tv_nsec) {
		return BTPluginMachOFail(error, BTPluginPackageErrorRaceDetected,
			@"The payload executable changed during non-executing inspection.", self.relativePath, nil);
	}
	return YES;
}

@end

@interface BTPluginMachOInspection ()
@property (nonatomic, strong, readwrite) NSURL *executableURL;
@property (nonatomic, readwrite) uint64_t sliceFileOffset;
@property (nonatomic, readwrite) uint64_t sliceByteCount;
@property (nonatomic, readwrite) uint32_t machOFileType;
@property (nonatomic, copy, readwrite) NSString *minimumIOSVersion;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *linkedDependencies;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *nonSystemDependencies;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *runpaths;
@property (nonatomic, readwrite) uint32_t codeSignatureOffsetInSlice;
@property (nonatomic, readwrite) uint32_t codeSignatureByteCount;
- (instancetype)bt_init;
@end

@implementation BTPluginMachOInspection
- (instancetype)bt_init { return [super init]; }
@end

static BOOL BTPluginSelectMachOSlice(BTPluginMachOReader *reader,
									  uint64_t *sliceOffset,
									  uint64_t *sliceSize,
									  NSError **error) {
	uint8_t prefix[sizeof(struct fat_header)] = {0};
	if (![reader readBytes:prefix length:sizeof(prefix) offset:0 error:error])
		return NO;
	uint32_t nativeMagic = 0;
	memcpy(&nativeMagic, prefix, sizeof(nativeMagic));
	if (nativeMagic == MH_MAGIC_64) {
		*sliceOffset = 0;
		*sliceSize = reader.fileByteCount;
		return YES;
	}

	uint32_t fatMagic = BTPluginReadBig32(prefix);
	BOOL isFat64 = fatMagic == FAT_MAGIC_64;
	if (fatMagic != FAT_MAGIC && !isFat64)
		return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The declared payload is not a supported 64-bit Mach-O image.", reader.relativePath, nil);
	uint32_t architectureCount = BTPluginReadBig32(prefix + sizeof(uint32_t));
	if (architectureCount != 1 || architectureCount > BTPluginMaximumFatArchitectureCount) {
		return BTPluginMachOFail(error, BTPluginPackageErrorUnsupportedArchitecture,
			@"ABI v1 accepts exactly one arm64 architecture slice.", reader.relativePath, nil);
	}
	NSUInteger recordSize = isFat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
	uint8_t record[sizeof(struct fat_arch_64)] = {0};
	if (![reader readBytes:record length:recordSize offset:sizeof(struct fat_header) error:error])
		return NO;
	int32_t cpuType = (int32_t)BTPluginReadBig32(record);
	int32_t cpuSubtype = (int32_t)BTPluginReadBig32(record + 4);
	uint64_t offset = isFat64 ? BTPluginReadBig64(record + 8) : BTPluginReadBig32(record + 8);
	uint64_t size = isFat64 ? BTPluginReadBig64(record + 16) : BTPluginReadBig32(record + 12);
	uint32_t alignment = isFat64 ? BTPluginReadBig32(record + 24) : BTPluginReadBig32(record + 16);
	uint32_t reserved = isFat64 ? BTPluginReadBig32(record + 28) : 0;
	if (cpuType != CPU_TYPE_ARM64 || (cpuSubtype & ~CPU_SUBTYPE_MASK) != CPU_SUBTYPE_ARM64_ALL ||
		alignment > 30 || (offset & (((uint64_t)1 << alignment) - 1)) != 0 || reserved != 0 ||
		size < sizeof(struct mach_header_64) || !BTPluginRangeIsValid(offset, size, reader.fileByteCount)) {
		return BTPluginMachOFail(error, BTPluginPackageErrorUnsupportedArchitecture,
			@"The universal wrapper does not contain one canonical arm64 slice.", reader.relativePath, nil);
	}
	*sliceOffset = offset;
	*sliceSize = size;
	return YES;
}

static BOOL BTPluginParseVersionString(NSString *value, uint32_t *packedVersion) {
	NSArray<NSString *> *components = [value componentsSeparatedByString:@"."];
	if (components.count == 0 || components.count > 3)
		return NO;
	uint64_t numbers[3] = {0, 0, 0};
	for (NSUInteger index = 0; index < components.count; index++) {
		NSScanner *scanner = [NSScanner scannerWithString:components[index]];
		unsigned long long number = 0;
		if (![scanner scanUnsignedLongLong:&number] || !scanner.isAtEnd || number > (index == 0 ? 65535 : 255))
			return NO;
		numbers[index] = number;
	}
	*packedVersion = (uint32_t)((numbers[0] << 16) | (numbers[1] << 8) | numbers[2]);
	return YES;
}

static uint32_t BTPluginPackedOperatingSystemVersion(NSOperatingSystemVersion version) {
	NSInteger major = MAX(0, MIN(version.majorVersion, 65535));
	NSInteger minor = MAX(0, MIN(version.minorVersion, 255));
	NSInteger patch = MAX(0, MIN(version.patchVersion, 255));
	return ((uint32_t)major << 16) | ((uint32_t)minor << 8) | (uint32_t)patch;
}

static NSString *BTPluginVersionString(uint32_t packedVersion) {
	return [NSString stringWithFormat:@"%u.%u.%u", packedVersion >> 16,
		(packedVersion >> 8) & 0xff, packedVersion & 0xff];
}

static NSString *BTPluginLoadCommandString(const uint8_t *command,
										 uint32_t commandSize,
										 uint32_t stringOffset) {
	if (stringOffset < sizeof(struct load_command) || stringOffset >= commandSize)
		return nil;
	const uint8_t *bytes = command + stringOffset;
	NSUInteger maximumLength = commandSize - stringOffset;
	const void *terminator = memchr(bytes, 0, maximumLength);
	if (!terminator)
		return nil;
	NSUInteger length = (const uint8_t *)terminator - bytes;
	if (length == 0 || length > 512)
		return nil;
	NSString *value = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
	if (!value || [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
		return nil;
	return value;
}

static NSSet<NSString *> *BTPluginAllowedSystemDependencies(void) {
	static NSSet<NSString *> *dependencies;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dependencies = [NSSet setWithArray:@[
			@"/usr/lib/libSystem.B.dylib",
			@"/usr/lib/libobjc.A.dylib",
			@"/usr/lib/libc++.1.dylib",
			@"/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
			@"/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
			@"/System/Library/Frameworks/Foundation.framework/Foundation",
			@"/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
			@"/System/Library/Frameworks/UIKit.framework/UIKit",
		]];
	});
	return dependencies;
}

static BOOL BTPluginRelativeDependencySuffixIsSafe(NSString *suffix) {
	if (suffix.length == 0 || [suffix hasPrefix:@"/"] || [suffix hasSuffix:@"/"] ||
		[suffix rangeOfString:@"\\"].location != NSNotFound ||
		[suffix rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
		return NO;
	for (NSString *component in [suffix componentsSeparatedByString:@"/"]) {
		if (component.length == 0 || [component isEqualToString:@"."] || [component isEqualToString:@".."])
			return NO;
	}
	return YES;
}

static BOOL BTPluginClassifyDependency(NSString *dependency, BOOL *isSystem) {
	if ([BTPluginAllowedSystemDependencies() containsObject:dependency]) {
		*isSystem = YES;
		return YES;
	}
	*isSystem = NO;
	NSArray<NSString *> *prefixes = @[ @"@loader_path/", @"@rpath/" ];
	for (NSString *prefix in prefixes) {
		if ([dependency hasPrefix:prefix])
			return BTPluginRelativeDependencySuffixIsSafe([dependency substringFromIndex:prefix.length]);
	}
	return NO;
}

static BOOL BTPluginRunpathIsSafe(NSString *runpath) {
	return [runpath isEqualToString:@"@loader_path"] ||
		[runpath isEqualToString:@"@loader_path/Frameworks"];
}

static BOOL BTPluginVerifyEntryPoint(BTPluginMachOReader *reader,
									 uint64_t sliceOffset,
									 uint64_t sliceSize,
									 struct symtab_command symtab,
									 NSString *entryPoint,
									 NSUInteger dependencyCount,
									 NSDictionary<NSNumber *, NSValue *> *executableSectionRanges,
									 uint64_t *entryPointAddress,
									 NSError **error) {
	uint64_t symbolBytes = (uint64_t)symtab.nsyms * sizeof(struct nlist_64);
	if (symtab.nsyms == 0 || symtab.nsyms > BTPluginMaximumSymbolCount ||
		symtab.strsize == 0 || symtab.strsize > BTPluginMaximumStringTableByteCount ||
		!BTPluginRangeIsValid(symtab.symoff, symbolBytes, sliceSize) ||
		!BTPluginRangeIsValid(symtab.stroff, symtab.strsize, sliceSize)) {
		return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O symbol or string table is missing or out of bounds.", reader.relativePath, nil);
	}
	NSData *expectedData = [[@"_" stringByAppendingString:entryPoint] dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t candidate[257];
	BOOL foundEntryPoint = NO;
	const NSUInteger symbolsPerChunk = 256;
	struct nlist_64 symbols[symbolsPerChunk];
	for (uint32_t base = 0; base < symtab.nsyms; base += symbolsPerChunk) {
		NSUInteger count = MIN((uint32_t)symbolsPerChunk, symtab.nsyms - base);
		uint64_t symbolsOffset = sliceOffset + symtab.symoff + (uint64_t)base * sizeof(struct nlist_64);
		if (![reader readBytes:symbols length:count * sizeof(struct nlist_64) offset:symbolsOffset error:error])
			return NO;
		for (NSUInteger index = 0; index < count; index++) {
			struct nlist_64 symbol = symbols[index];
			if ((symbol.n_type & N_STAB) == 0 && (symbol.n_type & N_EXT) != 0 &&
				(symbol.n_type & N_TYPE) == N_UNDF) {
				uint8_t ordinal = GET_LIBRARY_ORDINAL(symbol.n_desc);
				if (ordinal == SELF_LIBRARY_ORDINAL || ordinal == DYNAMIC_LOOKUP_ORDINAL ||
					ordinal == EXECUTABLE_ORDINAL || ordinal > dependencyCount) {
					return BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"An undefined symbol uses dynamic, executable, self, or invalid library lookup.",
						reader.relativePath, nil);
				}
			}
			// Hidden Objective-C class/ivar records may retain N_PEXT while N_EXT is
			// clear. They are required runtime metadata, not public image exports.
			if ((symbol.n_type & N_STAB) != 0 || (symbol.n_type & N_EXT) == 0 ||
				(symbol.n_type & N_TYPE) == N_UNDF)
				continue;
			NSValue *executableRangeValue = executableSectionRanges[@(symbol.n_sect)];
			NSRange executableRange = executableRangeValue.rangeValue;
			BOOL addressIsExecutable = executableRangeValue && symbol.n_value >= executableRange.location &&
				symbol.n_value - executableRange.location < executableRange.length;
			if ((symbol.n_type & (N_TYPE | N_EXT | N_PEXT)) != (N_SECT | N_EXT) ||
				symbol.n_sect == NO_SECT || symbol.n_value == 0 ||
				!addressIsExecutable ||
				(symbol.n_desc & N_WEAK_DEF) != 0) {
				return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"The payload export surface must contain only one strong entry point in executable code.",
					reader.relativePath, nil);
			}
			uint32_t stringIndex = symbol.n_un.n_strx;
			if (stringIndex == 0 || stringIndex >= symtab.strsize) {
				return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"An externally defined payload symbol has an invalid name.", reader.relativePath, nil);
			}
			NSUInteger maximum = MIN((NSUInteger)(symtab.strsize - stringIndex), sizeof(candidate));
			if (![reader readBytes:candidate length:maximum offset:sliceOffset + symtab.stroff + stringIndex error:error])
				return NO;
			const void *terminator = memchr(candidate, 0, maximum);
			if (!terminator) {
				return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"An externally defined payload symbol has an invalid name.", reader.relativePath, nil);
			}
			NSUInteger length = (const uint8_t *)terminator - candidate;
			if (foundEntryPoint || length != expectedData.length ||
				memcmp(candidate, expectedData.bytes, length) != 0) {
				return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"The payload exports a symbol other than its one declared Battman entry point.",
					reader.relativePath, nil);
			}
			foundEntryPoint = YES;
			*entryPointAddress = symbol.n_value;
		}
	}
	if (foundEntryPoint)
		return YES;
	return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
		@"The payload does not export the required Battman entry-point symbol.", reader.relativePath, nil);
}

static BOOL BTPluginReadULEB128(const uint8_t *bytes,
	NSUInteger byteCount,
	NSUInteger *cursor,
	uint64_t *value) {
	uint64_t result = 0;
	NSUInteger shift = 0;
	for (NSUInteger index = 0; index < 10 && *cursor < byteCount; index++) {
		uint8_t byte = bytes[(*cursor)++];
		uint64_t payload = byte & 0x7f;
		if (shift == 63 && payload > 1)
			return NO;
		result |= payload << shift;
		if ((byte & 0x80) == 0) {
			*value = result;
			return YES;
		}
		shift += 7;
	}
	return NO;
}

static BOOL BTPluginWalkExportTrie(const uint8_t *bytes,
	NSUInteger byteCount,
	NSUInteger nodeOffset,
	NSUInteger depth,
	NSMutableData *symbolPrefix,
	NSData *expectedSymbol,
	uint64_t expectedAddress,
	NSMutableIndexSet *visitedNodeOffsets,
	NSUInteger *nodeCount,
	NSUInteger *exportCount,
	BOOL *foundExpectedExport) {
	if (nodeOffset >= byteCount || depth > expectedSymbol.length + 1 ||
		*nodeCount >= BTPluginMaximumExportTrieNodeCount ||
		[visitedNodeOffsets containsIndex:nodeOffset])
		return NO;
	[visitedNodeOffsets addIndex:nodeOffset];
	(*nodeCount)++;

	NSUInteger cursor = nodeOffset;
	uint64_t terminalByteCount = 0;
	if (!BTPluginReadULEB128(bytes, byteCount, &cursor, &terminalByteCount) ||
		terminalByteCount > byteCount - cursor)
		return NO;
	NSUInteger terminalEnd = cursor + (NSUInteger)terminalByteCount;
	if (terminalByteCount > 0) {
		uint64_t flags = 0;
		uint64_t address = 0;
		NSUInteger terminalCursor = cursor;
		if (!BTPluginReadULEB128(bytes, terminalEnd, &terminalCursor, &flags) ||
			!BTPluginReadULEB128(bytes, terminalEnd, &terminalCursor, &address) ||
			terminalCursor != terminalEnd || flags != EXPORT_SYMBOL_FLAGS_KIND_REGULAR ||
			++*exportCount != 1 || ![symbolPrefix isEqualToData:expectedSymbol] ||
			address != expectedAddress)
			return NO;
		*foundExpectedExport = YES;
	}

	cursor = terminalEnd;
	if (cursor >= byteCount)
		return NO;
	uint8_t childCount = bytes[cursor++];
	for (uint8_t childIndex = 0; childIndex < childCount; childIndex++) {
		const uint8_t *terminator = memchr(bytes + cursor, 0, byteCount - cursor);
		if (!terminator)
			return NO;
		NSUInteger labelByteCount = (NSUInteger)(terminator - (bytes + cursor));
		NSUInteger originalPrefixLength = symbolPrefix.length;
		if (labelByteCount == 0 || labelByteCount > expectedSymbol.length - originalPrefixLength)
			return NO;
		[symbolPrefix appendBytes:bytes + cursor length:labelByteCount];
		if (memcmp(symbolPrefix.bytes, expectedSymbol.bytes, symbolPrefix.length) != 0)
			return NO;
		cursor += labelByteCount + 1;
		uint64_t childOffset = 0;
		if (!BTPluginReadULEB128(bytes, byteCount, &cursor, &childOffset) ||
			childOffset > NSUIntegerMax || childOffset >= byteCount ||
			!BTPluginWalkExportTrie(bytes, byteCount, (NSUInteger)childOffset, depth + 1,
				symbolPrefix, expectedSymbol, expectedAddress, visitedNodeOffsets,
				nodeCount, exportCount, foundExpectedExport))
			return NO;
		[symbolPrefix setLength:originalPrefixLength];
	}
	return YES;
}

static BOOL BTPluginVerifyExportTrie(BTPluginMachOReader *reader,
	uint64_t sliceOffset,
	uint64_t sliceSize,
	uint32_t exportOffset,
	uint32_t exportSize,
	NSString *entryPoint,
	uint64_t entryPointAddress,
	uint64_t imageBaseAddress,
	NSError **error) {
	if (exportSize == 0 || exportSize > BTPluginMaximumExportTrieByteCount ||
		!BTPluginRangeIsValid(exportOffset, exportSize, sliceSize) ||
		entryPointAddress < imageBaseAddress) {
		return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O dyld export trie is missing or out of bounds.", reader.relativePath, nil);
	}
	NSMutableData *trie = [NSMutableData dataWithLength:exportSize];
	if (![reader readBytes:trie.mutableBytes length:exportSize offset:sliceOffset + exportOffset error:error])
		return NO;
	NSData *expectedSymbol = [[@"_" stringByAppendingString:entryPoint] dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *symbolPrefix = [NSMutableData data];
	NSMutableIndexSet *visitedNodeOffsets = [NSMutableIndexSet indexSet];
	NSUInteger nodeCount = 0;
	NSUInteger exportCount = 0;
	BOOL foundExpectedExport = NO;
	if (!BTPluginWalkExportTrie(trie.bytes, trie.length, 0, 0, symbolPrefix, expectedSymbol,
		entryPointAddress - imageBaseAddress, visitedNodeOffsets, &nodeCount, &exportCount,
		&foundExpectedExport) || exportCount != 1 || !foundExpectedExport) {
		return BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O dyld export trie must contain only the declared Battman entry point.",
			reader.relativePath, nil);
	}
	return YES;
}

static BOOL BTPluginVerifyCodeDirectory(BTPluginMachOReader *reader,
										 uint64_t sliceOffset,
										 uint32_t signatureOffset,
										 const uint8_t *codeDirectory,
										 uint32_t codeDirectoryLength,
										 NSString *pluginIdentifier,
										 NSError **error) {
	if (codeDirectoryLength < 44 || BTPluginReadBig32(codeDirectory) != BTPluginCodeSigningMagicCodeDirectory ||
		BTPluginReadBig32(codeDirectory + 4) != codeDirectoryLength) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The embedded CodeDirectory is malformed.", reader.relativePath, nil);
	}
	uint32_t version = BTPluginReadBig32(codeDirectory + 8);
	uint32_t hashOffset = BTPluginReadBig32(codeDirectory + 16);
	uint32_t identifierOffset = BTPluginReadBig32(codeDirectory + 20);
	uint32_t specialSlotCount = BTPluginReadBig32(codeDirectory + 24);
	uint32_t codeSlotCount = BTPluginReadBig32(codeDirectory + 28);
	uint64_t codeLimit = BTPluginReadBig32(codeDirectory + 32);
	uint8_t hashSize = codeDirectory[36];
	uint8_t hashType = codeDirectory[37];
	uint8_t pageSizeShift = codeDirectory[39];
	if (version >= 0x20300) {
		if (codeDirectoryLength < 64)
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"The embedded CodeDirectory is truncated for its declared version.", reader.relativePath, nil);
		uint64_t extendedCodeLimit = BTPluginReadBig64(codeDirectory + 56);
		if (codeLimit == 0)
			codeLimit = extendedCodeLimit;
	}
	uint32_t scatterOffset = version >= 0x20100 && codeDirectoryLength >= 48 ? BTPluginReadBig32(codeDirectory + 44) : 0;
	if (hashType != BTPluginCodeSigningHashTypeSHA256 || hashSize != CC_SHA256_DIGEST_LENGTH ||
		(pageSizeShift != 12 && pageSizeShift != 14) || scatterOffset != 0 ||
		codeLimit != signatureOffset || identifierOffset >= codeDirectoryLength) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The CodeDirectory must use contiguous SHA-256 page hashes covering the bytes before LC_CODE_SIGNATURE.",
			reader.relativePath, nil);
	}
	uint64_t pageSize = (uint64_t)1 << pageSizeShift;
	uint64_t expectedSlotCount = (codeLimit + pageSize - 1) / pageSize;
	uint64_t specialBytes = (uint64_t)specialSlotCount * hashSize;
	uint64_t codeBytes = (uint64_t)codeSlotCount * hashSize;
	if (codeSlotCount != expectedSlotCount || hashOffset < specialBytes ||
		!BTPluginRangeIsValid(hashOffset, codeBytes, codeDirectoryLength)) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The CodeDirectory hash-slot table is inconsistent with its signed code limit.", reader.relativePath, nil);
	}
	const uint8_t *identifierBytes = codeDirectory + identifierOffset;
	NSUInteger identifierMaximum = codeDirectoryLength - identifierOffset;
	const void *identifierTerminator = memchr(identifierBytes, 0, identifierMaximum);
	if (!identifierTerminator) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The CodeDirectory identifier is unterminated.", reader.relativePath, nil);
	}
	NSUInteger identifierLength = (const uint8_t *)identifierTerminator - identifierBytes;
	NSString *identifier = [[NSString alloc] initWithBytes:identifierBytes length:identifierLength encoding:NSUTF8StringEncoding];
	if (![identifier isEqualToString:pluginIdentifier]) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The platform-signature identifier does not match the signed plug-in manifest.", reader.relativePath, nil);
	}

	NSMutableData *page = [NSMutableData dataWithLength:(NSUInteger)pageSize];
	for (uint32_t slot = 0; slot < codeSlotCount; slot++) {
		uint64_t pageOffset = (uint64_t)slot * pageSize;
		NSUInteger byteCount = (NSUInteger)MIN(pageSize, codeLimit - pageOffset);
		if (![reader readBytes:page.mutableBytes length:byteCount offset:sliceOffset + pageOffset error:error])
			return NO;
		uint8_t digest[CC_SHA256_DIGEST_LENGTH];
		CC_SHA256(page.bytes, (CC_LONG)byteCount, digest);
		const uint8_t *expected = codeDirectory + hashOffset + (uint64_t)slot * hashSize;
		if (memcmp(digest, expected, sizeof(digest)) != 0) {
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"A Mach-O code page does not match its embedded SHA-256 CodeDirectory hash.", reader.relativePath, nil);
		}
	}
	return YES;
}

static BOOL BTPluginVerifyCodeSignature(BTPluginMachOReader *reader,
											uint64_t sliceOffset,
											uint64_t sliceSize,
											uint32_t signatureOffset,
											uint32_t signatureSize,
											NSString *pluginIdentifier,
											NSString *hostApplicationBundleIdentifier,
											BOOL allowsTrollStoreEnvelope,
											BOOL allowsResignedEnvelopePadding,
											NSError **error) {
	uint64_t signatureEnd = (uint64_t)signatureOffset + signatureSize;
	uint64_t trailingByteCount = signatureEnd <= sliceSize ? sliceSize - signatureEnd : UINT64_MAX;
	if (signatureSize < 12 || signatureSize > BTPluginMaximumCodeSignatureByteCount || signatureOffset % 16 != 0 ||
		!BTPluginRangeIsValid(signatureOffset, signatureSize, sliceSize) ||
		(trailingByteCount != 0 && (!allowsResignedEnvelopePadding || trailingByteCount > 15))) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"LC_CODE_SIGNATURE must describe the bounded final bytes of the Mach-O slice.", reader.relativePath, nil);
	}
	if (trailingByteCount > 0) {
		uint8_t trailing[15] = {0};
		if (![reader readBytes:trailing length:(NSUInteger)trailingByteCount
			offset:sliceOffset + signatureEnd error:error])
			return NO;
		for (uint64_t index = 0; index < trailingByteCount; index++) {
			if (trailing[index] != 0)
				return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
					@"The resigned Mach-O has nonzero bytes after its signature envelope.", reader.relativePath, nil);
		}
	}
	NSMutableData *signature = [NSMutableData dataWithLength:signatureSize];
	if (![reader readBytes:signature.mutableBytes length:signatureSize offset:sliceOffset + signatureOffset error:error])
		return NO;
	const uint8_t *bytes = signature.bytes;
	uint32_t superBlobLength = BTPluginReadBig32(bytes + 4);
	if (BTPluginReadBig32(bytes) != BTPluginCodeSigningMagicEmbeddedSignature ||
		superBlobLength < 12 || superBlobLength > signatureSize) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The embedded platform signature is not one bounded SuperBlob.", reader.relativePath, nil);
	}
	for (uint32_t index = superBlobLength; index < signatureSize; index++) {
		if (bytes[index] != 0) {
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"The platform-signature region has nonzero bytes after its bounded SuperBlob.", reader.relativePath, nil);
		}
	}
	uint32_t blobCount = BTPluginReadBig32(bytes + 8);
	uint64_t indexBytes = (uint64_t)blobCount * 8;
	if (blobCount == 0 || blobCount > BTPluginMaximumCodeSignatureBlobCount ||
		!BTPluginRangeIsValid(12, indexBytes, superBlobLength)) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The embedded platform signature has an invalid blob index.", reader.relativePath, nil);
	}
	BOOL foundPrimaryCodeDirectory = NO;
	BOOL foundSecurePrimaryCodeDirectory = NO;
	BOOL foundSecureAlternateCodeDirectory = NO;
	NSMutableIndexSet *occupiedOffsets = [NSMutableIndexSet indexSet];
	NSMutableSet<NSNumber *> *slotTypes = [NSMutableSet set];
	for (uint32_t index = 0; index < blobCount; index++) {
		const uint8_t *record = bytes + 12 + (uint64_t)index * 8;
		uint32_t slotType = BTPluginReadBig32(record);
		uint32_t blobOffset = BTPluginReadBig32(record + 4);
		NSNumber *slotNumber = @(slotType);
		if ([slotTypes containsObject:slotNumber]) {
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"The embedded platform signature contains duplicate blob slots.", reader.relativePath, nil);
		}
		[slotTypes addObject:slotNumber];
		if (!BTPluginRangeIsValid(blobOffset, 8, superBlobLength)) {
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"A platform-signature blob offset is out of bounds.", reader.relativePath, nil);
		}
		uint32_t blobLength = BTPluginReadBig32(bytes + blobOffset + 4);
		if (blobLength < 8 || !BTPluginRangeIsValid(blobOffset, blobLength, superBlobLength) ||
			[occupiedOffsets intersectsIndexesInRange:NSMakeRange((NSUInteger)blobOffset, (NSUInteger)blobLength)]) {
			return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
				@"Platform-signature blobs overlap or extend outside the SuperBlob.", reader.relativePath, nil);
		}
		[occupiedOffsets addIndexesInRange:NSMakeRange((NSUInteger)blobOffset, (NSUInteger)blobLength)];
		if (slotType == BTPluginCodeSigningSlotCodeDirectory) {
			foundPrimaryCodeDirectory = YES;
			const uint8_t *codeDirectory = bytes + blobOffset;
			if (blobLength < 44 || BTPluginReadBig32(codeDirectory) != BTPluginCodeSigningMagicCodeDirectory ||
				BTPluginReadBig32(codeDirectory + 4) != blobLength) {
				return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
					@"The primary CodeDirectory is malformed.", reader.relativePath, nil);
			}
			uint8_t hashSize = codeDirectory[36];
			uint8_t hashType = codeDirectory[37];
			if (hashType == BTPluginCodeSigningHashTypeSHA256) {
				if (!BTPluginVerifyCodeDirectory(reader, sliceOffset, signatureOffset,
					codeDirectory, blobLength, pluginIdentifier, error))
					return NO;
				foundSecurePrimaryCodeDirectory = YES;
			} else if (!allowsTrollStoreEnvelope || hashType != BTPluginCodeSigningHashTypeSHA1 || hashSize != 20) {
				return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
					@"The primary CodeDirectory must use SHA-256 unless a sealed TrollStore envelope supplies one host-bound alternate.",
					reader.relativePath, nil);
			}
		} else if (slotType >= BTPluginCodeSigningSlotFirstAlternateCodeDirectory &&
			slotType <= BTPluginCodeSigningSlotLastAlternateCodeDirectory) {
			if (!allowsTrollStoreEnvelope ||
				slotType != BTPluginCodeSigningSlotFirstAlternateCodeDirectory ||
				foundSecureAlternateCodeDirectory || hostApplicationBundleIdentifier.length == 0) {
				return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
					@"Only one host-bound alternate CodeDirectory is allowed in a sealed TrollStore envelope.",
					reader.relativePath, nil);
			}
			if (!BTPluginVerifyCodeDirectory(reader, sliceOffset, signatureOffset,
				bytes + blobOffset, blobLength, hostApplicationBundleIdentifier, error))
				return NO;
			foundSecureAlternateCodeDirectory = YES;
		}
	}
	if (!foundPrimaryCodeDirectory) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The embedded signature has no primary CodeDirectory.", reader.relativePath, nil);
	}
	if (!foundSecurePrimaryCodeDirectory && !foundSecureAlternateCodeDirectory) {
		return BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
			@"The embedded signature has no validated SHA-256 CodeDirectory covering the plug-in image.",
			reader.relativePath, nil);
	}
	return YES;
}

@interface BTPluginMachOInspector ()
@property (nonatomic, copy, nullable) NSString *hostApplicationBundleIdentifier;
@end

@implementation BTPluginMachOInspector

- (instancetype)init {
	return [self initWithHostApplicationBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
}

- (instancetype)initWithHostApplicationBundleIdentifier:(NSString *)hostApplicationBundleIdentifier {
	self = [super init];
	if (!self)
		return nil;
	if ([hostApplicationBundleIdentifier isKindOfClass:[NSString class]] &&
		hostApplicationBundleIdentifier.length > 0 && hostApplicationBundleIdentifier.length <= 255)
		_hostApplicationBundleIdentifier = [hostApplicationBundleIdentifier copy];
	return self;
}

- (BTPluginMachOInspection *)inspectPackageInspection:(BTPluginPackageInspection *)inspection
										 hostIOSVersion:(NSOperatingSystemVersion)hostIOSVersion
												  error:(NSError **)error {
	if (![inspection isKindOfClass:[BTPluginPackageInspection class]]) {
		BTPluginMachOFail(error, BTPluginPackageErrorInvalidPackage,
			@"Mach-O inspection requires a completed structural inspection.", nil, nil);
		return nil;
	}
	BTPluginMachOReader *reader = [[BTPluginMachOReader alloc] initWithInspection:inspection error:error];
	if (!reader)
		return nil;
	uint64_t sliceOffset = 0;
	uint64_t sliceSize = 0;
	if (!BTPluginSelectMachOSlice(reader, &sliceOffset, &sliceSize, error))
		return nil;

	struct mach_header_64 header;
	if (![reader readBytes:&header length:sizeof(header) offset:sliceOffset error:error])
		return nil;
	uint32_t expectedFileType = [inspection.manifest.payload.kind isEqualToString:@"bundle"] ? MH_BUNDLE : MH_DYLIB;
	if (header.magic != MH_MAGIC_64 || header.cputype != CPU_TYPE_ARM64 ||
		(header.cpusubtype & ~CPU_SUBTYPE_MASK) != CPU_SUBTYPE_ARM64_ALL || header.filetype != expectedFileType ||
		header.ncmds == 0 || header.ncmds > BTPluginMaximumLoadCommandCount ||
		header.sizeofcmds > 16 * 1024 * 1024 ||
		!BTPluginRangeIsValid(sizeof(header), header.sizeofcmds, sliceSize) ||
		(header.flags & MH_DYLDLINK) == 0 || (header.flags & (MH_PREBOUND | MH_ALLOW_STACK_EXECUTION)) != 0) {
		BTPluginMachOFail(error, header.cputype != CPU_TYPE_ARM64 ? BTPluginPackageErrorUnsupportedArchitecture : BTPluginPackageErrorInvalidMachO,
			@"The payload is not a canonical arm64 MH_BUNDLE or MH_DYLIB for its declared kind.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	NSMutableData *commandsData = [NSMutableData dataWithLength:header.sizeofcmds];
	if (![reader readBytes:commandsData.mutableBytes length:header.sizeofcmds
		offset:sliceOffset + sizeof(header) error:error])
		return nil;
	const uint8_t *commands = commandsData.bytes;
	uint64_t commandOffset = 0;
	BOOL foundPlatformVersion = NO;
	BOOL foundSymbolTable = NO;
	BOOL foundCodeSignature = NO;
	BOOL foundInstallName = NO;
	BOOL foundDyldInfoCommand = NO;
	BOOL foundExportsTrieCommand = NO;
	BOOL foundExportTrie = NO;
	BOOL foundImageBase = NO;
	uint32_t minimumVersion = 0;
	struct symtab_command symbolTable = {0};
	uint32_t codeSignatureOffset = 0;
	uint32_t codeSignatureSize = 0;
	uint32_t exportTrieOffset = 0;
	uint32_t exportTrieSize = 0;
	uint64_t imageBaseAddress = 0;
	NSMutableArray<NSString *> *dependencies = [NSMutableArray array];
	NSMutableArray<NSString *> *nonSystemDependencies = [NSMutableArray array];
	NSMutableArray<NSString *> *runpaths = [NSMutableArray array];
	NSMutableSet<NSString *> *dependencySet = [NSMutableSet set];
	NSMutableSet<NSString *> *runpathSet = [NSMutableSet set];
	NSMutableArray<NSValue *> *fileRanges = [NSMutableArray array];
	NSMutableDictionary<NSNumber *, NSValue *> *executableSectionRanges = [NSMutableDictionary dictionary];
	NSUInteger globalSectionOrdinal = 0;

	for (uint32_t index = 0; index < header.ncmds; index++) {
		if (!BTPluginRangeIsValid(commandOffset, sizeof(struct load_command), header.sizeofcmds)) {
			BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
				@"The Mach-O load-command table is truncated.", inspection.manifest.payload.executablePath, nil);
			return nil;
		}
		struct load_command command;
		memcpy(&command, commands + commandOffset, sizeof(command));
		if (command.cmdsize < sizeof(command) || command.cmdsize % 8 != 0 ||
			!BTPluginRangeIsValid(commandOffset, command.cmdsize, header.sizeofcmds)) {
			BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
				@"A Mach-O load command has an invalid aligned size.", inspection.manifest.payload.executablePath, nil);
			return nil;
		}
		const uint8_t *commandBytes = commands + commandOffset;
		switch (command.cmd) {
			case LC_BUILD_VERSION: {
				if (foundPlatformVersion || command.cmdsize < sizeof(struct build_version_command))
					goto invalid_platform_version;
				struct build_version_command versionCommand;
				memcpy(&versionCommand, commandBytes, sizeof(versionCommand));
				uint64_t expectedSize = sizeof(versionCommand) + (uint64_t)versionCommand.ntools * sizeof(struct build_tool_version);
				if (!BTPluginMachOBuildPlatformMatchesHost(versionCommand.platform) ||
					expectedSize != command.cmdsize)
					goto invalid_platform_version;
				foundPlatformVersion = YES;
				minimumVersion = versionCommand.minos;
				break;
			}
			case LC_VERSION_MIN_IPHONEOS: {
				if (foundPlatformVersion || command.cmdsize != sizeof(struct version_min_command) ||
					!BTPluginMachOLegacyIOSVersionCommandMatchesHost())
					goto invalid_platform_version;
				struct version_min_command versionCommand;
				memcpy(&versionCommand, commandBytes, sizeof(versionCommand));
				foundPlatformVersion = YES;
				minimumVersion = versionCommand.version;
				break;
			}
			case LC_VERSION_MIN_MACOSX:
			case LC_VERSION_MIN_TVOS:
			case LC_VERSION_MIN_WATCHOS:
			invalid_platform_version:
				BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"The Mach-O must contain exactly one platform minimum-version command compatible with this Battman process.",
					inspection.manifest.payload.executablePath, nil);
				return nil;
			case LC_SYMTAB:
				if (foundSymbolTable || command.cmdsize != sizeof(struct symtab_command)) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"The Mach-O has a duplicate or malformed LC_SYMTAB.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				foundSymbolTable = YES;
				memcpy(&symbolTable, commandBytes, sizeof(symbolTable));
				break;
			case LC_DYLD_INFO:
			case LC_DYLD_INFO_ONLY: {
				if (foundDyldInfoCommand || command.cmdsize != sizeof(struct dyld_info_command)) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"The Mach-O has duplicate or malformed compressed dyld metadata.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				foundDyldInfoCommand = YES;
				struct dyld_info_command dyldInfo;
				memcpy(&dyldInfo, commandBytes, sizeof(dyldInfo));
				if (dyldInfo.export_size != 0) {
					if (foundExportTrie) {
						BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
							@"The Mach-O declares more than one dyld export trie.",
							inspection.manifest.payload.executablePath, nil);
						return nil;
					}
					foundExportTrie = YES;
					exportTrieOffset = dyldInfo.export_off;
					exportTrieSize = dyldInfo.export_size;
				}
				break;
			}
			case LC_DYLD_EXPORTS_TRIE: {
				if (foundExportsTrieCommand || command.cmdsize != sizeof(struct linkedit_data_command) ||
					foundExportTrie) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"The Mach-O has duplicate or malformed dyld export metadata.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				foundExportsTrieCommand = YES;
				struct linkedit_data_command exportsTrieCommand;
				memcpy(&exportsTrieCommand, commandBytes, sizeof(exportsTrieCommand));
				foundExportTrie = YES;
				exportTrieOffset = exportsTrieCommand.dataoff;
				exportTrieSize = exportsTrieCommand.datasize;
				break;
			}
			case LC_CODE_SIGNATURE: {
				if (foundCodeSignature || command.cmdsize != sizeof(struct linkedit_data_command)) {
					BTPluginMachOFail(error, BTPluginPackageErrorPlatformSignature,
						@"The Mach-O has a duplicate or malformed LC_CODE_SIGNATURE.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				struct linkedit_data_command signatureCommand;
				memcpy(&signatureCommand, commandBytes, sizeof(signatureCommand));
				foundCodeSignature = YES;
				codeSignatureOffset = signatureCommand.dataoff;
				codeSignatureSize = signatureCommand.datasize;
				break;
			}
			case LC_LOAD_DYLIB:
			case LC_LOAD_WEAK_DYLIB:
			{
				if (command.cmdsize < sizeof(struct dylib_command)) {
					BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"A dependency load command is truncated.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				struct dylib_command dependencyCommand;
				memcpy(&dependencyCommand, commandBytes, sizeof(dependencyCommand));
				NSString *dependency = BTPluginLoadCommandString(commandBytes, command.cmdsize, dependencyCommand.dylib.name.offset);
				BOOL isSystem = NO;
				if (!dependency || [dependencySet containsObject:dependency] || !BTPluginClassifyDependency(dependency, &isSystem)) {
					BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"The Mach-O contains an unsafe, duplicate, or unapproved dependency path.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				[dependencySet addObject:dependency];
				[dependencies addObject:dependency];
				if (!isSystem)
					[nonSystemDependencies addObject:dependency];
				break;
			}
			case LC_REEXPORT_DYLIB:
			case LC_LAZY_LOAD_DYLIB:
			case LC_LOAD_UPWARD_DYLIB:
				BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
					@"Plug-ins cannot re-export, lazily load, or upward-load libraries.",
					inspection.manifest.payload.executablePath, nil);
				return nil;
			case LC_ID_DYLIB: {
				if (foundInstallName || command.cmdsize < sizeof(struct dylib_command) ||
					![inspection.manifest.payload.kind isEqualToString:@"so"]) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"Only a raw .so payload may declare one dylib install name.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				struct dylib_command identifierCommand;
				memcpy(&identifierCommand, commandBytes, sizeof(identifierCommand));
				NSString *installName = BTPluginLoadCommandString(commandBytes, command.cmdsize,
					identifierCommand.dylib.name.offset);
				NSString *expectedInstallName = [@"@rpath/" stringByAppendingString:
					inspection.manifest.payload.path.lastPathComponent];
				if (![installName isEqualToString:expectedInstallName]) {
					BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"A raw .so must use its canonical @rpath install name.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				foundInstallName = YES;
				break;
			}
			case LC_RPATH: {
				if (command.cmdsize < sizeof(struct rpath_command)) {
					BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"An LC_RPATH command is truncated.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				struct rpath_command runpathCommand;
				memcpy(&runpathCommand, commandBytes, sizeof(runpathCommand));
				NSString *runpath = BTPluginLoadCommandString(commandBytes, command.cmdsize, runpathCommand.path.offset);
				if (!runpath || !BTPluginRunpathIsSafe(runpath) || [runpathSet containsObject:runpath]) {
					BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
						@"The Mach-O contains an unsafe or duplicate runpath.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				[runpathSet addObject:runpath];
				[runpaths addObject:runpath];
				break;
			}
			case LC_DYLD_ENVIRONMENT:
			case LC_LOAD_DYLINKER:
			case LC_ID_DYLINKER:
			case LC_MAIN:
			case LC_UNIXTHREAD:
				BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
					@"The loadable plug-in contains a load command reserved for executable processes or dyld configuration.",
					inspection.manifest.payload.executablePath, nil);
				return nil;
			case LC_SEGMENT_64: {
				if (command.cmdsize < sizeof(struct segment_command_64)) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"A 64-bit segment command is truncated.", inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				struct segment_command_64 segment;
				memcpy(&segment, commandBytes, sizeof(segment));
				uint64_t expectedSize = sizeof(segment) + (uint64_t)segment.nsects * sizeof(struct section_64);
				if (expectedSize != command.cmdsize || segment.filesize > segment.vmsize ||
					!BTPluginRangeIsValid(segment.fileoff, segment.filesize, sliceSize) ||
					(((segment.initprot | segment.maxprot) & VM_PROT_WRITE) != 0 &&
					 ((segment.initprot | segment.maxprot) & VM_PROT_EXECUTE) != 0)) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"A Mach-O segment is out of bounds or permits writable executable memory.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				if (segment.filesize > 0) {
					if (segment.fileoff == 0) {
						if (foundImageBase) {
							BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
								@"The Mach-O declares more than one file-backed image-base segment.",
								inspection.manifest.payload.executablePath, nil);
							return nil;
						}
						foundImageBase = YES;
						imageBaseAddress = segment.vmaddr;
					}
					for (NSValue *value in fileRanges) {
						NSRange priorRange = value.rangeValue;
						if (BTPluginRangesOverlap(segment.fileoff, segment.filesize,
							priorRange.location, priorRange.length)) {
							BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
								@"Mach-O file-backed segments overlap.", inspection.manifest.payload.executablePath, nil);
							return nil;
						}
					}
					if (segment.fileoff > NSUIntegerMax || segment.filesize > NSUIntegerMax - segment.fileoff) {
						BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
							@"A Mach-O segment range cannot be represented safely.", inspection.manifest.payload.executablePath, nil);
						return nil;
					}
					[fileRanges addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)segment.fileoff, (NSUInteger)segment.filesize)]];
				}
				for (uint32_t sectionIndex = 0; sectionIndex < segment.nsects; sectionIndex++) {
					struct section_64 section;
					memcpy(&section, commandBytes + sizeof(segment) +
						(uint64_t)sectionIndex * sizeof(section), sizeof(section));
					uint32_t sectionType = section.flags & SECTION_TYPE;
					globalSectionOrdinal++;
					if (globalSectionOrdinal > UINT8_MAX || section.addr < segment.vmaddr ||
						!BTPluginRangeIsValid(section.addr - segment.vmaddr, section.size, segment.vmsize)) {
						BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
							@"A Mach-O section is outside its segment or exceeds the section-ordinal limit.",
							inspection.manifest.payload.executablePath, nil);
						return nil;
					}
					BOOL zeroFill = sectionType == S_ZEROFILL || sectionType == S_GB_ZEROFILL ||
						sectionType == S_THREAD_LOCAL_ZEROFILL;
					if (!zeroFill && !BTPluginRangeIsValid(section.offset, section.size, sliceSize)) {
						BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
							@"A file-backed Mach-O section extends outside the slice.",
							inspection.manifest.payload.executablePath, nil);
						return nil;
					}
					if (sectionType == S_INTERPOSING || sectionType == S_MOD_TERM_FUNC_POINTERS) {
						BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
							@"Plug-ins cannot declare symbol interposition or termination-function sections.",
							inspection.manifest.payload.executablePath, nil);
						return nil;
					}
					if ((segment.initprot & VM_PROT_EXECUTE) != 0 &&
						(section.flags & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS)) != 0) {
						executableSectionRanges[@(globalSectionOrdinal)] =
							[NSValue valueWithRange:NSMakeRange((NSUInteger)section.addr, (NSUInteger)section.size)];
					}
				}
				break;
			}
			default:
				if ((command.cmd & LC_REQ_DYLD) != 0 && command.cmd != LC_DYLD_INFO_ONLY &&
					command.cmd != LC_DYLD_EXPORTS_TRIE && command.cmd != LC_DYLD_CHAINED_FIXUPS) {
					BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
						@"The Mach-O contains an unsupported required dyld load command.",
						inspection.manifest.payload.executablePath, nil);
					return nil;
				}
				break;
		}
		commandOffset += command.cmdsize;
	}
	if (commandOffset != header.sizeofcmds || !foundPlatformVersion || !foundSymbolTable ||
		!foundCodeSignature || !foundExportTrie || !foundImageBase ||
		!BTPluginRangeIsValid(exportTrieOffset, exportTrieSize, codeSignatureOffset)) {
		BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O is missing required platform, symbol, export-trie, image-base, or code-signature metadata.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	if ((header.flags & MH_TWOLEVEL) == 0) {
		BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
			@"Plug-ins must use the two-level namespace and cannot use flat symbol lookup.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	if ([inspection.manifest.payload.kind isEqualToString:@"so"] != foundInstallName) {
		BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The payload's dylib install-name role does not match its declared kind.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	uint32_t manifestMinimumVersion = 0;
	if (!BTPluginParseVersionString(inspection.manifest.payload.minimumIOSVersion, &manifestMinimumVersion) ||
		minimumVersion != manifestMinimumVersion || minimumVersion > BTPluginPackedOperatingSystemVersion(hostIOSVersion)) {
		BTPluginMachOFail(error, BTPluginPackageErrorInvalidMachO,
			@"The Mach-O iOS minimum version differs from the manifest or exceeds the current host.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	NSSet *declaredDependencies = [NSSet setWithArray:inspection.manifest.dependencies];
	if (declaredDependencies.count != inspection.manifest.dependencies.count ||
		![declaredDependencies isEqualToSet:[NSSet setWithArray:nonSystemDependencies]]) {
		BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
			@"The signed non-system dependency list does not exactly match Mach-O load commands.",
			inspection.manifest.payload.executablePath, nil);
		return nil;
	}
	for (NSString *dependency in nonSystemDependencies) {
		if ([dependency hasPrefix:@"@rpath/"] && runpaths.count == 0) {
			BTPluginMachOFail(error, BTPluginPackageErrorUnsafeDependency,
				@"An @rpath dependency has no safe LC_RPATH resolution root.", inspection.manifest.payload.executablePath, nil);
			return nil;
		}
	}
	uint64_t entryPointAddress = 0;
	if (!BTPluginVerifyEntryPoint(reader, sliceOffset, sliceSize, symbolTable,
		inspection.manifest.payload.entryPoint, dependencies.count, executableSectionRanges,
		&entryPointAddress, error) ||
		!BTPluginVerifyExportTrie(reader, sliceOffset, sliceSize, exportTrieOffset, exportTrieSize,
			inspection.manifest.payload.entryPoint, entryPointAddress, imageBaseAddress, error) ||
		!BTPluginVerifyCodeSignature(reader, sliceOffset, sliceSize, codeSignatureOffset, codeSignatureSize,
			inspection.manifest.pluginIdentifier, self.hostApplicationBundleIdentifier,
			inspection.isSealedAppBundleRepresentation && inspection.manifest.payload.codeIdentity != nil &&
				self.hostApplicationBundleIdentifier.length > 0,
			inspection.manifest.payload.codeIdentity != nil, error) ||
		![reader verifyUnchanged:error])
		return nil;

	BTPluginMachOInspection *result = [[BTPluginMachOInspection alloc] bt_init];
	result.executableURL = inspection.executableURL;
	result.sliceFileOffset = sliceOffset;
	result.sliceByteCount = sliceSize;
	result.machOFileType = header.filetype;
	result.minimumIOSVersion = BTPluginVersionString(minimumVersion);
	result.linkedDependencies = dependencies;
	result.nonSystemDependencies = nonSystemDependencies;
	result.runpaths = runpaths;
	result.codeSignatureOffsetInSlice = codeSignatureOffset;
	result.codeSignatureByteCount = codeSignatureSize;
	return result;
}

@end
