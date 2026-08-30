#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <stdlib.h>
#import <unistd.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Security/BTPluginMachOInspector.h"
#import "../../Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.h"
#import "../../Battman/PluginHost/Security/BTPluginPlatformLoadabilityVerifier.h"
#import "../../Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

typedef void (^BTMutateExecutable)(NSMutableData *data);

static NSString *BTHexDigest(NSData *data) {
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	static const char digits[] = "0123456789abcdef";
	char output[CC_SHA256_DIGEST_LENGTH * 2 + 1];
	for (NSUInteger index = 0; index < sizeof(digest); index++) {
		output[index * 2] = digits[digest[index] >> 4];
		output[index * 2 + 1] = digits[digest[index] & 0x0f];
	}
	output[sizeof(digest) * 2] = '\0';
	return [NSString stringWithUTF8String:output];
}

static void BTWriteData(NSData *data, NSURL *url, NSNumber *permissions) {
	NSError *error = nil;
	BTAssert([data writeToURL:url options:NSDataWritingAtomic error:&error], error.localizedDescription.UTF8String);
	if (permissions) {
		BTAssert([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: permissions }
			ofItemAtPath:url.path error:&error], error.localizedDescription.UTF8String);
	}
}

static NSData *BTPropertyListData(NSDictionary *dictionary) {
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	BTAssert(data != nil, error.localizedDescription.UTF8String);
	return data;
}

static NSDictionary *BTManifestFile(NSString *path, NSData *data, NSString *mode) {
	return @{ @"path": path, @"size": @(data.length), @"mode": mode, @"sha256": BTHexDigest(data) };
}

static NSArray<NSDictionary *> *BTSortedManifestFiles(NSArray<NSDictionary *> *files) {
	return [files sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return [left[@"path"] compare:right[@"path"] options:NSLiteralSearch];
	}];
}

static NSURL *BTCreatePackageWithKindInternal(NSURL *parentURL,
											NSString *name,
											NSURL *executableSourceURL,
											NSString *payloadKind,
											NSString *minimumIOSVersion,
											NSArray<NSString *> *dependencies,
											BOOL includeAdditionalMachO,
											BTMutateExecutable mutation,
											BOOL includeCodeIdentity) {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	BOOL isBundle = [payloadKind isEqualToString:@"bundle"];
	BOOL isSO = [payloadKind isEqualToString:@"so"];
	BTAssert(isBundle || isSO, "unsupported fixture payload kind");
	BTAssert(!includeAdditionalMachO || isBundle, "additional Mach-O fixture requires a bundle payload");
	NSString *payloadPath = isBundle ? @"Example.bundle" : @"Example.so";
	NSString *executablePath = isBundle ? @"Example.bundle/Example" : payloadPath;
	NSURL *packageURL = [parentURL URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"battman"] isDirectory:YES];
	NSURL *payloadURL = [packageURL URLByAppendingPathComponent:payloadPath isDirectory:isBundle];
	NSURL *executableURL = isBundle ? [payloadURL URLByAppendingPathComponent:@"Example"] : payloadURL;
	NSURL *signatureDirectoryURL = [packageURL URLByAppendingPathComponent:@"Signatures" isDirectory:YES];
	NSDictionary *directoryAttributes = @{ NSFilePosixPermissions: @0755 };
	BTAssert([manager createDirectoryAtURL:packageURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);
	if (isBundle) {
		BTAssert([manager createDirectoryAtURL:payloadURL withIntermediateDirectories:NO attributes:directoryAttributes error:&error],
			error.localizedDescription.UTF8String);
	}
	BTAssert([manager createDirectoryAtURL:signatureDirectoryURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);

	NSString *keyIdentifier = [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
	NSMutableData *executableData = [NSMutableData dataWithContentsOfURL:executableSourceURL options:0 error:&error];
	BTAssert(executableData != nil, error.localizedDescription.UTF8String);
	if (mutation)
		mutation(executableData);
	NSData *outerInfoData = BTPropertyListData(@{
		@"CFBundleIdentifier": @"com.example.battman.analytics.fixture",
		@"CFBundleDisplayName": @"Mach-O Verifier Fixture",
		@"CFBundleShortVersionString": @"1.0",
		@"CFBundleVersion": @"1",
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPackageFormatVersion": @1,
		@"BTPluginPublisherKeyIdentifier": keyIdentifier,
	});
	BTWriteData(executableData, executableURL, @0755);
	BTWriteData(outerInfoData, [packageURL URLByAppendingPathComponent:@"Info.plist"], @0644);

	NSMutableArray<NSDictionary *> *files = [NSMutableArray arrayWithArray:@[
		BTManifestFile(executablePath, executableData, @"executable"),
		BTManifestFile(@"Info.plist", outerInfoData, @"data"),
	]];
	if (isBundle) {
		NSData *payloadInfoData = BTPropertyListData(@{
			@"CFBundleExecutable": @"Example",
			@"CFBundleIdentifier": @"com.example.battman.analytics.fixture",
			@"CFBundlePackageType": @"BNDL",
			@"CFBundleShortVersionString": @"1.0",
			@"CFBundleVersion": @"1",
		});
		BTWriteData(payloadInfoData, [payloadURL URLByAppendingPathComponent:@"Info.plist"], @0644);
		[files addObject:BTManifestFile(@"Example.bundle/Info.plist", payloadInfoData, @"data")];
	}
	if (includeAdditionalMachO) {
		BTWriteData(executableData, [payloadURL URLByAppendingPathComponent:@"Resource.bin"], @0644);
		[files addObject:BTManifestFile(@"Example.bundle/Resource.bin", executableData, @"data")];
	}
	NSMutableDictionary *payloadManifest = [@{
		@"path": payloadPath,
		@"kind": payloadKind,
		@"executablePath": executablePath,
		@"architecture": @"arm64",
		@"minimumIOSVersion": minimumIOSVersion,
		@"entryPoint": @"BattmanPluginEntryPointV1",
	} mutableCopy];
	if (includeCodeIdentity) {
		uint64_t unsignedByteCount = 0;
		NSString *codeSHA256 = nil;
		BTAssert(BTPluginComputeMachOCodeIdentityAtURL(executableURL, executablePath,
			&unsignedByteCount, &codeSHA256, &error), error.localizedDescription.UTF8String);
		payloadManifest[@"codeIdentity"] = @{
			@"algorithm": BTPluginMachOCodeIdentityAlgorithm,
			@"unsignedByteCount": @(unsignedByteCount),
			@"sha256": codeSHA256,
		};
	}
	NSDictionary *manifest = @{
		@"formatVersion": @1,
		@"schemaVersion": @1,
		@"pluginIdentifier": @"com.example.battman.analytics.fixture",
		@"displayName": @"Mach-O Verifier Fixture",
		@"displayVersion": @"1.0",
		@"buildVersion": @"1",
		@"publisher": @{
			@"primaryKeyIdentifier": keyIdentifier,
			@"signatureKeyIdentifiers": @[ keyIdentifier ],
			@"algorithm": @"ecdsa-p256-sha256",
		},
		@"hostABI": @{ @"minimum": @1, @"maximum": @1 },
		@"payload": payloadManifest,
		@"extensionPoints": @[
			@{ @"identifier": @"com.torrekie.battman.analytics.card.v1", @"interfaceVersion": @1 },
		],
		@"files": BTSortedManifestFiles(files),
		@"dependencies": dependencies,
		@"releaseSequence": @1,
	};
	NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingSortedKeys error:&error];
	BTAssert(manifestData != nil, error.localizedDescription.UTF8String);
	BTWriteData(manifestData, [packageURL URLByAppendingPathComponent:@"Manifest.json"], @0644);
	uint8_t signatureByte = 0x30;
	BTWriteData([NSData dataWithBytes:&signatureByte length:1],
		[signatureDirectoryURL URLByAppendingPathComponent:[keyIdentifier stringByAppendingPathExtension:@"sig"]], @0644);
	return packageURL;
}

static NSURL *BTCreatePackageWithKind(NSURL *parentURL,
	NSString *name, NSURL *executableSourceURL, NSString *payloadKind,
	NSString *minimumIOSVersion, NSArray<NSString *> *dependencies,
	BOOL includeAdditionalMachO, BTMutateExecutable mutation) {
	return BTCreatePackageWithKindInternal(parentURL, name, executableSourceURL, payloadKind,
		minimumIOSVersion, dependencies, includeAdditionalMachO, mutation, NO);
}

static NSURL *BTCreatePackage(NSURL *parentURL,
								NSString *name,
								NSURL *executableSourceURL,
								NSString *minimumIOSVersion,
								NSArray<NSString *> *dependencies,
								BOOL includeAdditionalMachO,
								BTMutateExecutable mutation) {
	return BTCreatePackageWithKind(parentURL, name, executableSourceURL, @"bundle",
		minimumIOSVersion, dependencies, includeAdditionalMachO, mutation);
}

static BTPluginPackageInspection *BTStructuralInspect(NSURL *packageURL, NSError **error) {
	return [[BTPluginPackageStructuralVerifier new] inspectPackageAtURL:packageURL error:error];
}

static NSDictionary<NSString *, NSURL *> *BTCreateSealedRepresentation(NSURL *parentURL,
	NSURL *transportURL, NSURL *resignedExecutableURL) {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSURL *appURL = [parentURL URLByAppendingPathComponent:@"Resigned.app" isDirectory:YES];
	NSURL *payloadParentURL = [appURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
	NSURL *metadataParentURL = [appURL URLByAppendingPathComponent:@"PluginManifests" isDirectory:YES];
	NSURL *payloadURL = [payloadParentURL
		URLByAppendingPathComponent:@"com.example.battman.analytics.fixture.bundle" isDirectory:YES];
	NSURL *metadataURL = [metadataParentURL
		URLByAppendingPathComponent:@"com.example.battman.analytics.fixture" isDirectory:YES];
	BTAssert([manager createDirectoryAtURL:payloadParentURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0755 } error:&error], error.localizedDescription.UTF8String);
	BTAssert([manager createDirectoryAtURL:metadataParentURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0755 } error:&error], error.localizedDescription.UTF8String);
	BTAssert([manager copyItemAtURL:transportURL toURL:metadataURL error:&error], error.localizedDescription.UTF8String);
	NSURL *logicalPayloadURL = [metadataURL URLByAppendingPathComponent:@"Example.bundle" isDirectory:YES];
	BTAssert([manager copyItemAtURL:logicalPayloadURL toURL:payloadURL error:&error], error.localizedDescription.UTF8String);
	BTAssert([manager removeItemAtURL:logicalPayloadURL error:&error], error.localizedDescription.UTF8String);
	NSURL *installedExecutableURL = [payloadURL URLByAppendingPathComponent:@"Example" isDirectory:NO];
	BTAssert([manager removeItemAtURL:installedExecutableURL error:&error], error.localizedDescription.UTF8String);
	BTAssert([manager copyItemAtURL:resignedExecutableURL toURL:installedExecutableURL error:&error],
		error.localizedDescription.UTF8String);
	BTAssert([manager setAttributes:@{ NSFilePosixPermissions: @0755 }
		ofItemAtPath:installedExecutableURL.path error:&error], error.localizedDescription.UTF8String);
	return @{ @"metadata": metadataURL, @"payload": payloadURL };
}

static uint32_t BTTestReadBig32(const uint8_t *bytes) {
	uint32_t value = 0;
	memcpy(&value, bytes, sizeof(value));
	return CFSwapInt32BigToHost(value);
}

static void BTTestWriteBig32(uint8_t *bytes, uint32_t value) {
	uint32_t bigEndian = CFSwapInt32HostToBig(value);
	memcpy(bytes, &bigEndian, sizeof(bigEndian));
}

static NSURL *BTCreateTrollStoreEnvelopeExecutable(NSURL *parentURL,
	NSURL *sourceURL, NSString *hostIdentifier) {
	NSError *error = nil;
	NSMutableData *data = [NSMutableData dataWithContentsOfURL:sourceURL options:0 error:&error];
	BTAssert(data != nil, error.localizedDescription.UTF8String);
	BTAssert(data.length >= sizeof(struct mach_header_64), "TrollStore fixture source is truncated");
	struct mach_header_64 *header = data.mutableBytes;
	BTAssert(header->magic == MH_MAGIC_64 && header->sizeofcmds <= data.length - sizeof(*header),
		"TrollStore fixture source is not a bounded thin Mach-O");

	NSUInteger signatureCommandOffset = NSNotFound;
	NSUInteger linkeditCommandOffset = NSNotFound;
	uint8_t *commands = (uint8_t *)data.mutableBytes + sizeof(*header);
	NSUInteger commandOffset = 0;
	for (uint32_t index = 0; index < header->ncmds; index++) {
		BTAssert(commandOffset + sizeof(struct load_command) <= header->sizeofcmds,
			"TrollStore fixture load commands are truncated");
		struct load_command *command = (struct load_command *)(commands + commandOffset);
		BTAssert(command->cmdsize >= sizeof(*command) && commandOffset + command->cmdsize <= header->sizeofcmds,
			"TrollStore fixture load command is malformed");
		if (command->cmd == LC_CODE_SIGNATURE) {
			BTAssert(signatureCommandOffset == NSNotFound && command->cmdsize == sizeof(struct linkedit_data_command),
				"TrollStore fixture has an invalid code-signature command");
			signatureCommandOffset = sizeof(*header) + commandOffset;
		} else if (command->cmd == LC_SEGMENT_64) {
			struct segment_command_64 *segment = (struct segment_command_64 *)command;
			if (strncmp(segment->segname, SEG_LINKEDIT, sizeof(segment->segname)) == 0) {
				BTAssert(linkeditCommandOffset == NSNotFound, "TrollStore fixture has duplicate __LINKEDIT segments");
				linkeditCommandOffset = sizeof(*header) + commandOffset;
			}
		}
		commandOffset += command->cmdsize;
	}
	BTAssert(signatureCommandOffset != NSNotFound && linkeditCommandOffset != NSNotFound,
		"TrollStore fixture is missing signing load commands");
	struct linkedit_data_command *signatureCommand =
		(struct linkedit_data_command *)((uint8_t *)data.mutableBytes + signatureCommandOffset);
	uint32_t signatureOffset = signatureCommand->dataoff;
	uint32_t signatureSize = signatureCommand->datasize;
	BTAssert(signatureSize >= 12 && signatureOffset <= data.length && signatureSize <= data.length - signatureOffset,
		"TrollStore fixture signature is out of bounds");

	const uint8_t *oldSignature = (const uint8_t *)data.bytes + signatureOffset;
	uint32_t oldLength = BTTestReadBig32(oldSignature + 4);
	uint32_t oldCount = BTTestReadBig32(oldSignature + 8);
	BTAssert(BTTestReadBig32(oldSignature) == 0xfade0cc0 && oldLength <= signatureSize &&
		oldCount > 0 && 12 + (uint64_t)oldCount * 8 <= oldLength,
		"TrollStore fixture source has an invalid SuperBlob");

	NSMutableArray<NSNumber *> *slots = [NSMutableArray array];
	NSMutableArray<NSMutableData *> *blobs = [NSMutableArray array];
	NSMutableData *alternateCodeDirectory = nil;
	for (uint32_t index = 0; index < oldCount; index++) {
		uint32_t slot = BTTestReadBig32(oldSignature + 12 + (uint64_t)index * 8);
		uint32_t blobOffset = BTTestReadBig32(oldSignature + 16 + (uint64_t)index * 8);
		BTAssert(blobOffset <= oldLength - 8, "TrollStore fixture blob offset is out of bounds");
		uint32_t blobLength = BTTestReadBig32(oldSignature + blobOffset + 4);
		BTAssert(blobLength >= 8 && blobLength <= oldLength - blobOffset,
			"TrollStore fixture blob is out of bounds");
		NSMutableData *blob = [NSMutableData dataWithBytes:oldSignature + blobOffset length:blobLength];
		if (slot != 0) {
			[slots addObject:@(slot)];
			[blobs addObject:blob];
			continue;
		}
		BTAssert(blobLength >= 44 && BTTestReadBig32(blob.bytes) == 0xfade0c02 &&
			((const uint8_t *)blob.bytes)[37] == 2 && ((const uint8_t *)blob.bytes)[36] == CC_SHA256_DIGEST_LENGTH,
			"TrollStore fixture source lacks a primary SHA-256 CodeDirectory");
		NSMutableData *compatibilityCodeDirectory = [blob mutableCopy];
		((uint8_t *)compatibilityCodeDirectory.mutableBytes)[36] = CC_SHA1_DIGEST_LENGTH;
		((uint8_t *)compatibilityCodeDirectory.mutableBytes)[37] = 1;
		[slots addObject:@0];
		[blobs addObject:compatibilityCodeDirectory];

		alternateCodeDirectory = [blob mutableCopy];
		uint32_t identifierOffset = BTTestReadBig32((const uint8_t *)alternateCodeDirectory.bytes + 20);
		BTAssert(identifierOffset < alternateCodeDirectory.length, "TrollStore fixture identifier is out of bounds");
		uint8_t *identifierBytes = (uint8_t *)alternateCodeDirectory.mutableBytes + identifierOffset;
		NSUInteger identifierCapacity = alternateCodeDirectory.length - identifierOffset;
		uint8_t *terminator = memchr(identifierBytes, 0, identifierCapacity);
		NSData *hostIdentifierData = [hostIdentifier dataUsingEncoding:NSUTF8StringEncoding];
		BTAssert(terminator && hostIdentifierData.length <= (NSUInteger)(terminator - identifierBytes),
			"TrollStore fixture host identifier does not fit its CodeDirectory");
		memset(identifierBytes, 0, (NSUInteger)(terminator - identifierBytes) + 1);
		memcpy(identifierBytes, hostIdentifierData.bytes, hostIdentifierData.length);
		[slots addObject:@0x1000];
		[blobs addObject:alternateCodeDirectory];
	}
	BTAssert(alternateCodeDirectory != nil, "TrollStore fixture did not find its primary CodeDirectory");

	uint64_t newLength64 = 12 + (uint64_t)slots.count * 8;
	for (NSData *blob in blobs)
		newLength64 += blob.length;
	BTAssert(newLength64 <= UINT32_MAX, "TrollStore fixture SuperBlob is too large");
	uint32_t newLength = (uint32_t)newLength64;
	uint32_t newSignatureSize = (newLength + 15) & ~15U;
	[data setLength:(NSUInteger)signatureOffset + newSignatureSize];
	signatureCommand = (struct linkedit_data_command *)((uint8_t *)data.mutableBytes + signatureCommandOffset);
	struct segment_command_64 *linkedit =
		(struct segment_command_64 *)((uint8_t *)data.mutableBytes + linkeditCommandOffset);
	signatureCommand->datasize = newSignatureSize;
	linkedit->filesize = data.length - linkedit->fileoff;
	linkedit->vmsize = (linkedit->filesize + 0x3fff) & ~UINT64_C(0x3fff);

	uint8_t *alternateBytes = alternateCodeDirectory.mutableBytes;
	uint32_t hashOffset = BTTestReadBig32(alternateBytes + 16);
	uint32_t codeSlotCount = BTTestReadBig32(alternateBytes + 28);
	uint32_t codeLimit = BTTestReadBig32(alternateBytes + 32);
	uint8_t hashSize = alternateBytes[36];
	uint8_t pageSizeShift = alternateBytes[39];
	BTAssert(codeLimit == signatureOffset && hashSize == CC_SHA256_DIGEST_LENGTH &&
		(pageSizeShift == 12 || pageSizeShift == 14) &&
		hashOffset <= alternateCodeDirectory.length &&
		(uint64_t)codeSlotCount * hashSize <= alternateCodeDirectory.length - hashOffset,
		"TrollStore fixture alternate CodeDirectory is malformed");
	uint64_t pageSize = UINT64_C(1) << pageSizeShift;
	BTAssert(codeSlotCount == (codeLimit + pageSize - 1) / pageSize,
		"TrollStore fixture alternate CodeDirectory has the wrong page count");
	for (uint32_t slot = 0; slot < codeSlotCount; slot++) {
		uint64_t pageOffset = (uint64_t)slot * pageSize;
		NSUInteger byteCount = (NSUInteger)MIN(pageSize, codeLimit - pageOffset);
		CC_SHA256((const uint8_t *)data.bytes + pageOffset, (CC_LONG)byteCount,
			alternateBytes + hashOffset + (uint64_t)slot * hashSize);
	}

	uint8_t *newSignature = (uint8_t *)data.mutableBytes + signatureOffset;
	memset(newSignature, 0, newSignatureSize);
	BTTestWriteBig32(newSignature, 0xfade0cc0);
	BTTestWriteBig32(newSignature + 4, newLength);
	BTTestWriteBig32(newSignature + 8, (uint32_t)slots.count);
	uint32_t outputOffset = 12 + (uint32_t)slots.count * 8;
	for (NSUInteger index = 0; index < slots.count; index++) {
		BTTestWriteBig32(newSignature + 12 + index * 8, slots[index].unsignedIntValue);
		BTTestWriteBig32(newSignature + 16 + index * 8, outputOffset);
		NSData *blob = blobs[index];
		memcpy(newSignature + outputOffset, blob.bytes, blob.length);
		outputOffset += (uint32_t)blob.length;
	}
	BTAssert(outputOffset == newLength, "TrollStore fixture SuperBlob length drifted");

	NSURL *outputURL = [parentURL URLByAppendingPathComponent:@"trollstore-envelope.bundle" isDirectory:NO];
	BTWriteData(data, outputURL, @0755);
	return outputURL;
}

static BTPluginMachOInspection *BTMachOInspect(BTPluginPackageInspection *inspection,
														NSOperatingSystemVersion hostVersion,
														NSError **error) {
	return [[BTPluginMachOInspector new] inspectPackageInspection:inspection hostIOSVersion:hostVersion error:error];
}

static NSArray<NSValue *> *BTFindAllBytes(NSMutableData *data, const char *needle) {
	NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
	NSData *needleData = [NSData dataWithBytes:needle length:strlen(needle)];
	NSRange searchRange = NSMakeRange(0, data.length);
	while (searchRange.length > 0) {
		NSRange range = [data rangeOfData:needleData options:0 range:searchRange];
		if (range.location == NSNotFound)
			break;
		[ranges addObject:[NSValue valueWithRange:range]];
		NSUInteger next = NSMaxRange(range);
		searchRange = NSMakeRange(next, data.length - next);
	}
	return ranges;
}

static BOOL BTClearExternalDefinitionForSymbol(NSMutableData *data, const char *symbolName) {
	if (data.length < sizeof(struct mach_header_64))
		return NO;
	struct mach_header_64 *header = data.mutableBytes;
	if (header->magic != MH_MAGIC_64 || header->ncmds == 0 ||
		header->sizeofcmds < sizeof(struct load_command) ||
		header->sizeofcmds > data.length - sizeof(struct mach_header_64))
		return NO;
	uint8_t *commands = (uint8_t *)data.mutableBytes + sizeof(struct mach_header_64);
	uint64_t commandOffset = 0;
	struct symtab_command symtab = {0};
	BOOL foundSymtab = NO;
	for (uint32_t index = 0; index < header->ncmds; index++) {
		if (commandOffset > header->sizeofcmds - sizeof(struct load_command))
			return NO;
		struct load_command *command = (struct load_command *)(commands + commandOffset);
		if (command->cmdsize < sizeof(*command) || command->cmdsize > header->sizeofcmds - commandOffset)
			return NO;
		if (command->cmd == LC_SYMTAB) {
			if (foundSymtab || command->cmdsize != sizeof(symtab))
				return NO;
			memcpy(&symtab, command, sizeof(symtab));
			foundSymtab = YES;
		}
		commandOffset += command->cmdsize;
	}
	uint64_t symbolBytes = (uint64_t)symtab.nsyms * sizeof(struct nlist_64);
	if (!foundSymtab || symtab.symoff > data.length || symbolBytes > data.length - symtab.symoff ||
		symtab.stroff > data.length || symtab.strsize > data.length - symtab.stroff)
		return NO;
	struct nlist_64 *symbols = (struct nlist_64 *)((uint8_t *)data.mutableBytes + symtab.symoff);
	const uint8_t *strings = (const uint8_t *)data.bytes + symtab.stroff;
	NSUInteger expectedLength = strlen(symbolName);
	for (uint32_t index = 0; index < symtab.nsyms; index++) {
		struct nlist_64 *symbol = &symbols[index];
		if ((symbol->n_type & N_EXT) == 0 || (symbol->n_type & N_TYPE) == N_UNDF ||
			symbol->n_un.n_strx == 0 || symbol->n_un.n_strx >= symtab.strsize)
			continue;
		NSUInteger maximum = symtab.strsize - symbol->n_un.n_strx;
		const uint8_t *name = strings + symbol->n_un.n_strx;
		const uint8_t *terminator = memchr(name, 0, maximum);
		if (terminator && (NSUInteger)(terminator - name) == expectedLength &&
			memcmp(name, symbolName, expectedLength) == 0) {
			symbol->n_type &= (uint8_t)~N_EXT;
			return YES;
		}
	}
	return NO;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTAssert(argc == 11, "expected valid C, Objective-C, and chained-fixup bundles, valid .so, unsafe-install-name .so, unsafe-rpath, unsafe-dependency, dynamic-lookup, extra-export, and resigned fixture paths");
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-macho-tests-%@", NSUUID.UUID.UUIDString]]
			isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *validExecutableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		NSURL *validObjectiveCExecutableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
		NSURL *validChainedExecutableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[3]]];
		NSURL *validSOURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[4]]];
		NSURL *unsafeInstallNameSOURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[5]]];
		NSURL *unsafeRpathURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[6]]];
		NSURL *unsafeDependencyURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[7]]];
		NSURL *dynamicLookupURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[8]]];
		NSURL *extraExportURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[9]]];
		NSURL *resignedExecutableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[10]]];
		NSOperatingSystemVersion iOS17 = { .majorVersion = 17, .minorVersion = 2, .patchVersion = 0 };

		NSString *sentinelPath = [temporaryURL.path stringByAppendingPathComponent:@"constructor-ran"];
		BTAssert(setenv("BT_PLUGIN_CONSTRUCTOR_SENTINEL", sentinelPath.fileSystemRepresentation, 1) == 0, "setenv failed");
		NSURL *validPackageURL = BTCreatePackage(temporaryURL, @"Valid", validExecutableURL, @"12.0", @[], NO, nil);
		BTPluginPackageInspection *validStructural = BTStructuralInspect(validPackageURL, &error);
		BTAssert(validStructural != nil, error.localizedDescription.UTF8String);
		BTPluginMachOInspection *validMachO = BTMachOInspect(validStructural, iOS17, &error);
		BTAssert(validMachO != nil, error.localizedDescription.UTF8String);
		BTAssert(validMachO.machOFileType == MH_BUNDLE, "valid fixture has wrong file type");
		BTAssert([validMachO.minimumIOSVersion isEqualToString:@"12.0.0"], "minimum iOS mismatch");
		BTAssert(validMachO.codeSignatureByteCount > 0, "code signature was not inspected");
		BTAssert([[BTPluginPlatformLoadabilityVerifier new] verifyPackageInspection:validStructural
			machOInspection:validMachO error:&error], error.localizedDescription.UTF8String);
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during inspection");

		error = nil;
		NSURL *validObjectiveCPackageURL = BTCreatePackage(temporaryURL, @"ValidObjectiveC",
			validObjectiveCExecutableURL, @"12.0", @[], NO, nil);
		BTPluginPackageInspection *validObjectiveCStructural = BTStructuralInspect(validObjectiveCPackageURL, &error);
		BTAssert(validObjectiveCStructural != nil, error.localizedDescription.UTF8String);
		BTPluginMachOInspection *validObjectiveCMachO = BTMachOInspect(validObjectiveCStructural, iOS17, &error);
		BTAssert(validObjectiveCMachO != nil, error.localizedDescription.UTF8String);
		BTAssert(validObjectiveCMachO.machOFileType == MH_BUNDLE,
			"valid Objective-C fixture has wrong file type");

		error = nil;
		NSURL *validChainedPackageURL = BTCreatePackage(temporaryURL, @"ValidChained",
			validChainedExecutableURL, @"15.0", @[], NO, nil);
		BTPluginPackageInspection *validChainedStructural = BTStructuralInspect(validChainedPackageURL, &error);
		BTAssert(validChainedStructural != nil, error.localizedDescription.UTF8String);
		BTPluginMachOInspection *validChainedMachO = BTMachOInspect(validChainedStructural, iOS17, &error);
		BTAssert(validChainedMachO != nil, error.localizedDescription.UTF8String);
		BTAssert([validChainedMachO.minimumIOSVersion isEqualToString:@"15.0.0"],
			"chained-fixup fixture minimum iOS mismatch");

		uint64_t originalUnsignedByteCount = 0;
		uint64_t resignedUnsignedByteCount = 0;
		NSString *originalCodeSHA256 = nil;
		NSString *resignedCodeSHA256 = nil;
		BTAssert(BTPluginComputeMachOCodeIdentityAtURL(validExecutableURL, @"Example.bundle/Example",
			&originalUnsignedByteCount, &originalCodeSHA256, &error), error.localizedDescription.UTF8String);
		error = nil;
		BTAssert(BTPluginComputeMachOCodeIdentityAtURL(resignedExecutableURL, @"Example.bundle/Example",
			&resignedUnsignedByteCount, &resignedCodeSHA256, &error), error.localizedDescription.UTF8String);
		BTAssert(originalUnsignedByteCount == resignedUnsignedByteCount &&
			[originalCodeSHA256 isEqualToString:resignedCodeSHA256],
			"bounded code-signature replacement changed the canonical Mach-O identity");
		BTAssert(![[NSData dataWithContentsOfURL:validExecutableURL]
			isEqualToData:[NSData dataWithContentsOfURL:resignedExecutableURL]],
			"resigned fixture did not change raw executable bytes");
		NSURL *identityTransportURL = BTCreatePackageWithKindInternal(temporaryURL, @"IdentityTransport",
			validExecutableURL, @"bundle", @"12.0", @[], NO, nil, YES);
		error = nil;
		BTPluginPackageInspection *identityTransport = BTStructuralInspect(identityTransportURL, &error);
		BTAssert(identityTransport != nil, error.localizedDescription.UTF8String);
		NSDictionary<NSString *, NSURL *> *sealed = BTCreateSealedRepresentation(temporaryURL,
			identityTransportURL, resignedExecutableURL);
		error = nil;
		BTPluginPackageInspection *sealedInspection = [[BTPluginSealedPackageStructuralVerifier new]
			inspectMetadataAtURL:sealed[@"metadata"] payloadURL:sealed[@"payload"] error:&error];
		BTAssert(sealedInspection != nil, error.localizedDescription.UTF8String);
		BTAssert([sealedInspection.packageSHA256 isEqualToString:identityTransport.packageSHA256],
			"resigned sealed representation changed the signed logical package identity");
		BTPluginMachOInspection *resignedMachO = BTMachOInspect(sealedInspection, iOS17, &error);
		BTAssert(resignedMachO != nil, error.localizedDescription.UTF8String);
		BTAssert(resignedMachO.codeSignatureByteCount > 0,
			"resigned sealed payload did not pass bounded CodeDirectory inspection");

		NSString *hostApplicationIdentifier = @"com.example.battman.host";
		NSURL *trollStoreExecutableURL = BTCreateTrollStoreEnvelopeExecutable(temporaryURL,
			validExecutableURL, hostApplicationIdentifier);
		uint64_t trollStoreUnsignedByteCount = 0;
		NSString *trollStoreCodeSHA256 = nil;
		error = nil;
		BTAssert(BTPluginComputeMachOCodeIdentityAtURL(trollStoreExecutableURL, @"Example.bundle/Example",
			&trollStoreUnsignedByteCount, &trollStoreCodeSHA256, &error), error.localizedDescription.UTF8String);
		BTAssert(originalUnsignedByteCount == trollStoreUnsignedByteCount &&
			[originalCodeSHA256 isEqualToString:trollStoreCodeSHA256],
			"TrollStore envelope fixture changed the canonical Mach-O identity");

		NSURL *trollStoreTransportURL = BTCreatePackageWithKindInternal(temporaryURL, @"TrollStoreTransport",
			trollStoreExecutableURL, @"bundle", @"12.0", @[], NO, nil, YES);
		error = nil;
		BTPluginPackageInspection *trollStoreTransport = BTStructuralInspect(trollStoreTransportURL, &error);
		BTAssert(trollStoreTransport != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(trollStoreTransport, iOS17, &error) == nil &&
			error.code == BTPluginPackageErrorPlatformSignature,
			"TrollStore alternate CodeDirectory was accepted outside a sealed app representation");

		NSURL *trollStoreParentURL = [temporaryURL URLByAppendingPathComponent:@"TrollStoreSealed" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:trollStoreParentURL withIntermediateDirectories:NO
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *trollStoreIdentityTransportURL = BTCreatePackageWithKindInternal(temporaryURL,
			@"TrollStoreIdentityTransport", validExecutableURL, @"bundle", @"12.0", @[], NO, nil, YES);
		NSDictionary<NSString *, NSURL *> *trollStoreSealed = BTCreateSealedRepresentation(trollStoreParentURL,
			trollStoreIdentityTransportURL, trollStoreExecutableURL);
		error = nil;
		BTPluginPackageInspection *trollStoreSealedInspection = [[BTPluginSealedPackageStructuralVerifier new]
			inspectMetadataAtURL:trollStoreSealed[@"metadata"] payloadURL:trollStoreSealed[@"payload"] error:&error];
		BTAssert(trollStoreSealedInspection != nil, error.localizedDescription.UTF8String);
		BTPluginMachOInspector *hostBoundInspector = [[BTPluginMachOInspector alloc]
			initWithHostApplicationBundleIdentifier:hostApplicationIdentifier];
		BTAssert([hostBoundInspector inspectPackageInspection:trollStoreSealedInspection
			hostIOSVersion:iOS17 error:&error] != nil, error.localizedDescription.UTF8String);
		error = nil;
		BTPluginMachOInspector *wrongHostInspector = [[BTPluginMachOInspector alloc]
			initWithHostApplicationBundleIdentifier:@"com.example.wrong-host"];
		BTAssert([wrongHostInspector inspectPackageInspection:trollStoreSealedInspection
			hostIOSVersion:iOS17 error:&error] == nil && error.code == BTPluginPackageErrorPlatformSignature,
			"TrollStore alternate CodeDirectory was not bound to the containing host identifier");

		error = nil;
		NSURL *validSOPackageURL = BTCreatePackageWithKind(temporaryURL, @"ValidSO", validSOURL,
			@"so", @"12.0", @[], NO, nil);
		BTPluginPackageInspection *validSOStructural = BTStructuralInspect(validSOPackageURL, &error);
		BTAssert(validSOStructural != nil, error.localizedDescription.UTF8String);
		BTPluginMachOInspection *validSOMachO = BTMachOInspect(validSOStructural, iOS17, &error);
		BTAssert(validSOMachO != nil, error.localizedDescription.UTF8String);
		BTAssert(validSOMachO.machOFileType == MH_DYLIB, "valid raw .so fixture has wrong file type");
		BTAssert([validSOMachO.minimumIOSVersion isEqualToString:@"12.0.0"], "raw .so minimum iOS mismatch");
		BTAssert(validSOMachO.codeSignatureByteCount > 0, "raw .so code signature was not inspected");
		BTAssert([[BTPluginPlatformLoadabilityVerifier new] verifyPackageInspection:validSOStructural
			machOInspection:validSOMachO error:&error], error.localizedDescription.UTF8String);
		BTAssert(![manager fileExistsAtPath:sentinelPath], "raw .so constructor executed during inspection");

		error = nil;
		NSURL *unsafeInstallNamePackageURL = BTCreatePackageWithKind(temporaryURL, @"UnsafeInstallName",
			unsafeInstallNameSOURL, @"so", @"12.0", @[], NO, nil);
		BTPluginPackageInspection *unsafeInstallNameStructural = BTStructuralInspect(unsafeInstallNamePackageURL, &error);
		BTAssert(unsafeInstallNameStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(unsafeInstallNameStructural, iOS17, &error) == nil &&
			error.code == BTPluginPackageErrorUnsafeDependency, "non-canonical raw .so install name accepted");

		NSURL *wrongTypeURL = BTCreatePackage(temporaryURL, @"WrongType", validExecutableURL, @"12.0", @[], NO,
			^(NSMutableData *data) {
				struct mach_header_64 *header = data.mutableBytes;
				header->filetype = MH_DYLIB;
			});
		error = nil;
		BTPluginPackageInspection *wrongTypeStructural = BTStructuralInspect(wrongTypeURL, &error);
		BTAssert(wrongTypeStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(wrongTypeStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorInvalidMachO,
			"wrong Mach-O type accepted");

		NSURL *wrongArchitectureURL = BTCreatePackage(temporaryURL, @"WrongArchitecture", validExecutableURL, @"12.0", @[], NO,
			^(NSMutableData *data) {
				struct mach_header_64 *header = data.mutableBytes;
				header->cputype = CPU_TYPE_X86_64;
			});
		error = nil;
		BTPluginPackageInspection *wrongArchitectureStructural = BTStructuralInspect(wrongArchitectureURL, &error);
		BTAssert(wrongArchitectureStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(wrongArchitectureStructural, iOS17, &error) == nil &&
			error.code == BTPluginPackageErrorUnsupportedArchitecture, "wrong architecture accepted");

		NSURL *missingEntryURL = BTCreatePackage(temporaryURL, @"MissingEntry", validExecutableURL, @"12.0", @[], NO,
			^(NSMutableData *data) {
				NSArray<NSValue *> *ranges = BTFindAllBytes(data, "_BattmanPluginEntryPointV1");
				BTAssert(ranges.count > 0, "entry-point string not found in fixture");
				for (NSValue *value in ranges)
					((uint8_t *)data.mutableBytes)[value.rangeValue.location + 1] = 'X';
			});
		error = nil;
		BTPluginPackageInspection *missingEntryStructural = BTStructuralInspect(missingEntryURL, &error);
		BTAssert(missingEntryStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(missingEntryStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorInvalidMachO,
			"missing entry point accepted");

		NSURL *extraExportPackageURL = BTCreatePackage(temporaryURL, @"ExtraExport", extraExportURL,
			@"12.0", @[], NO, nil);
		error = nil;
		BTPluginPackageInspection *extraExportStructural = BTStructuralInspect(extraExportPackageURL, &error);
		BTAssert(extraExportStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(extraExportStructural, iOS17, &error) == nil &&
			error.code == BTPluginPackageErrorInvalidMachO,
			"additional externally defined symbol accepted");

		NSURL *trieOnlyExportPackageURL = BTCreatePackage(temporaryURL, @"TrieOnlyExport", extraExportURL,
			@"12.0", @[], NO, ^(NSMutableData *data) {
				BTAssert(BTClearExternalDefinitionForSymbol(data, "_BattmanPluginUnexpectedExport"),
					"unexpected export was not found in the adversarial symbol table");
			});
		error = nil;
		BTPluginPackageInspection *trieOnlyExportStructural = BTStructuralInspect(trieOnlyExportPackageURL, &error);
		BTAssert(trieOnlyExportStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(trieOnlyExportStructural, iOS17, &error) == nil &&
			error.code == BTPluginPackageErrorInvalidMachO,
			"dyld-trie-only additional export accepted");

		uint32_t signatureOffset = validMachO.codeSignatureOffsetInSlice;
		NSURL *tamperedPageURL = BTCreatePackage(temporaryURL, @"TamperedPage", validExecutableURL, @"12.0", @[], NO,
			^(NSMutableData *data) {
				BTAssert(signatureOffset > 1024, "fixture signature offset too small");
				((uint8_t *)data.mutableBytes)[signatureOffset / 2] ^= 0x01;
			});
		error = nil;
		BTPluginPackageInspection *tamperedPageStructural = BTStructuralInspect(tamperedPageURL, &error);
		BTAssert(tamperedPageStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(tamperedPageStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorPlatformSignature,
			"tampered signed page accepted");

		NSURL *manifestVersionURL = BTCreatePackage(temporaryURL, @"VersionMismatch", validExecutableURL, @"13.0", @[], NO, nil);
		error = nil;
		BTPluginPackageInspection *manifestVersionStructural = BTStructuralInspect(manifestVersionURL, &error);
		BTAssert(manifestVersionStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(manifestVersionStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorInvalidMachO,
			"manifest/Mach-O version mismatch accepted");

		NSOperatingSystemVersion iOS11 = { .majorVersion = 11, .minorVersion = 4, .patchVersion = 0 };
		error = nil;
		BTAssert(BTMachOInspect(validStructural, iOS11, &error) == nil && error.code == BTPluginPackageErrorInvalidMachO,
			"payload newer than host accepted");

		NSURL *unsafeRpathPackageURL = BTCreatePackage(temporaryURL, @"UnsafeRpath", unsafeRpathURL, @"12.0", @[], NO, nil);
		error = nil;
		BTPluginPackageInspection *unsafeRpathStructural = BTStructuralInspect(unsafeRpathPackageURL, &error);
		BTAssert(unsafeRpathStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(unsafeRpathStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorUnsafeDependency,
			"unsafe runpath accepted");

		NSURL *unsafeDependencyPackageURL = BTCreatePackage(temporaryURL, @"UnsafeDependency", unsafeDependencyURL, @"12.0", @[], NO, nil);
		error = nil;
		BTPluginPackageInspection *unsafeDependencyStructural = BTStructuralInspect(unsafeDependencyPackageURL, &error);
		BTAssert(unsafeDependencyStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(unsafeDependencyStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorUnsafeDependency,
			"unapproved system dependency accepted");

		NSURL *dynamicLookupPackageURL = BTCreatePackage(temporaryURL, @"DynamicLookup", dynamicLookupURL, @"12.0", @[], NO, nil);
		error = nil;
		BTPluginPackageInspection *dynamicLookupStructural = BTStructuralInspect(dynamicLookupPackageURL, &error);
		BTAssert(dynamicLookupStructural != nil, error.localizedDescription.UTF8String);
		BTAssert(BTMachOInspect(dynamicLookupStructural, iOS17, &error) == nil && error.code == BTPluginPackageErrorUnsafeDependency,
			"dynamic host-symbol lookup accepted");

		NSURL *additionalMachOURL = BTCreatePackage(temporaryURL, @"AdditionalMachO", validExecutableURL, @"12.0", @[], YES, nil);
		error = nil;
		BTAssert(BTStructuralInspect(additionalMachOURL, &error) == nil && error.code == BTPluginPackageErrorInvalidMachO,
			"additional Mach-O marked as data accepted");

		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during a rejection path");
		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		printf("Non-executing bundle/.so, dependency, one-symbol export-trie, and CodeDirectory tests passed.\n");
	}
	return 0;
}
