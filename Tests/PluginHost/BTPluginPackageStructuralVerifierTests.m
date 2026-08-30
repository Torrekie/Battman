#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Model/BTPluginPackageManifest.h"
#import "../../Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.h"
#import "../../Battman/PluginHost/Security/BTPluginSealedPackageStructuralVerifier.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

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
	return @{
		@"path": path,
		@"size": @(data.length),
		@"mode": mode,
		@"sha256": BTHexDigest(data),
	};
}

static NSString *BTRepeatedString(NSString *value, NSUInteger count) {
	NSMutableString *result = [NSMutableString stringWithCapacity:value.length * count];
	for (NSUInteger index = 0; index < count; index++)
		[result appendString:value];
	return result;
}

static NSMutableDictionary *BTMutableManifestAtURL(NSURL *packageURL) {
	NSError *error = nil;
	id manifest = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:
		[packageURL URLByAppendingPathComponent:@"Manifest.json"]]
		options:NSJSONReadingMutableContainers error:&error];
	BTAssert([manifest isKindOfClass:[NSMutableDictionary class]], error.localizedDescription.UTF8String);
	return manifest;
}

static void BTWriteManifest(NSMutableDictionary *manifest, NSURL *packageURL) {
	NSError *error = nil;
	NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest
		options:NSJSONWritingSortedKeys error:&error];
	BTAssert(manifestData != nil, error.localizedDescription.UTF8String);
	BTWriteData(manifestData, [packageURL URLByAppendingPathComponent:@"Manifest.json"], @0644);
}

static void BTReplaceSignedFile(NSURL *packageURL, NSString *relativePath, NSData *data) {
	BTWriteData(data, [packageURL URLByAppendingPathComponent:relativePath], @0644);
	NSMutableDictionary *manifest = BTMutableManifestAtURL(packageURL);
	NSMutableArray *files = manifest[@"files"];
	NSUInteger index = [files indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger entryIndex, BOOL *stop) {
		(void)entryIndex;
		(void)stop;
		return [entry[@"path"] isEqualToString:relativePath];
	}];
	BTAssert(index != NSNotFound, "signed file fixture is absent from the manifest");
	files[index] = BTManifestFile(relativePath, data, @"data");
	BTWriteManifest(manifest, packageURL);
}

static void BTRemoveSignedFile(NSURL *packageURL, NSString *relativePath) {
	NSError *error = nil;
	BTAssert([[NSFileManager defaultManager] removeItemAtURL:
		[packageURL URLByAppendingPathComponent:relativePath] error:&error],
		error.localizedDescription.UTF8String);
	NSMutableDictionary *manifest = BTMutableManifestAtURL(packageURL);
	NSMutableArray *files = manifest[@"files"];
	NSIndexSet *indexes = [files indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry,
		NSUInteger entryIndex, BOOL *stop) {
		(void)entryIndex;
		(void)stop;
		return [entry[@"path"] isEqualToString:relativePath];
	}];
	BTAssert(indexes.count == 1, "signed file fixture inventory is not unique");
	[files removeObjectsAtIndexes:indexes];
	BTWriteManifest(manifest, packageURL);
}

static NSURL *BTCreateValidPackage(NSURL *parentURL, NSString *name, uint8_t signatureByte) {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSURL *packageURL = [parentURL URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"battman"] isDirectory:YES];
	NSURL *payloadURL = [packageURL URLByAppendingPathComponent:@"Example.bundle" isDirectory:YES];
	NSURL *signatureDirectoryURL = [packageURL URLByAppendingPathComponent:@"Signatures" isDirectory:YES];
	NSDictionary *directoryAttributes = @{ NSFilePosixPermissions: @0755 };
	BTAssert([manager createDirectoryAtURL:payloadURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);
	BTAssert([manager createDirectoryAtURL:signatureDirectoryURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);

	NSString *keyIdentifier = [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
	NSData *executableData = [@"non-executing-structural-fixture" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *payloadInfoData = BTPropertyListData(@{
		@"CFBundleExecutable": @"Example",
		@"CFBundleIdentifier": @"com.example.battman.analytics.fixture",
		@"CFBundlePackageType": @"BNDL",
		@"CFBundleShortVersionString": @"1.0",
		@"CFBundleVersion": @"1",
	});
	NSData *outerInfoData = BTPropertyListData(@{
		@"CFBundleIdentifier": @"com.example.battman.analytics.fixture",
		@"CFBundleDisplayName": @"Verifier Fixture",
		@"CFBundleShortVersionString": @"1.0",
		@"CFBundleVersion": @"1",
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPackageFormatVersion": @1,
		@"BTPluginPublisherKeyIdentifier": keyIdentifier,
	});
	BTWriteData(executableData, [payloadURL URLByAppendingPathComponent:@"Example"], @0755);
	BTWriteData(payloadInfoData, [payloadURL URLByAppendingPathComponent:@"Info.plist"], @0644);
	BTWriteData(outerInfoData, [packageURL URLByAppendingPathComponent:@"Info.plist"], @0644);

	NSArray *files = @[
		BTManifestFile(@"Example.bundle/Example", executableData, @"executable"),
		BTManifestFile(@"Example.bundle/Info.plist", payloadInfoData, @"data"),
		BTManifestFile(@"Info.plist", outerInfoData, @"data"),
	];
	NSDictionary *manifest = @{
		@"formatVersion": @1,
		@"schemaVersion": @1,
		@"pluginIdentifier": @"com.example.battman.analytics.fixture",
		@"displayName": @"Verifier Fixture",
		@"displayVersion": @"1.0",
		@"buildVersion": @"1",
		@"publisher": @{
			@"primaryKeyIdentifier": keyIdentifier,
			@"signatureKeyIdentifiers": @[ keyIdentifier ],
			@"algorithm": @"ecdsa-p256-sha256",
		},
		@"hostABI": @{ @"minimum": @1, @"maximum": @1 },
		@"payload": @{
			@"path": @"Example.bundle",
			@"kind": @"bundle",
			@"executablePath": @"Example.bundle/Example",
			@"architecture": @"arm64",
			@"minimumIOSVersion": @"12.0",
			@"entryPoint": @"BattmanPluginEntryPointV1",
		},
		@"extensionPoints": @[
			@{ @"identifier": @"com.torrekie.battman.analytics.card.v1", @"interfaceVersion": @1 },
		],
		@"files": files,
		@"dependencies": @[],
		@"releaseSequence": @1,
	};
	NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingSortedKeys error:&error];
	BTAssert(manifestData != nil, error.localizedDescription.UTF8String);
	BTWriteData(manifestData, [packageURL URLByAppendingPathComponent:@"Manifest.json"], @0644);
	NSData *signatureData = [NSData dataWithBytes:&signatureByte length:1];
	BTWriteData(signatureData, [signatureDirectoryURL URLByAppendingPathComponent:[keyIdentifier stringByAppendingPathExtension:@"sig"]], @0644);
	return packageURL;
}

static BTPluginPackageInspection *BTInspect(NSURL *packageURL, NSError **error) {
	return [[BTPluginPackageStructuralVerifier new] inspectPackageAtURL:packageURL error:error];
}

static NSDictionary<NSString *, NSURL *> *BTCreateSealedRepresentation(NSURL *parentURL,
	NSString *tag, NSURL *transportURL) {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSString *pluginIdentifier = @"com.example.battman.analytics.fixture";
	NSURL *appURL = [parentURL URLByAppendingPathComponent:tag isDirectory:YES];
	NSURL *payloadParentURL = [appURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
	NSURL *metadataParentURL = [appURL URLByAppendingPathComponent:@"PluginManifests" isDirectory:YES];
	NSURL *payloadURL = [payloadParentURL URLByAppendingPathComponent:
		[pluginIdentifier stringByAppendingPathExtension:@"bundle"] isDirectory:YES];
	NSURL *metadataURL = [metadataParentURL URLByAppendingPathComponent:pluginIdentifier isDirectory:YES];
	BTAssert([manager createDirectoryAtURL:payloadParentURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0755 } error:&error], error.localizedDescription.UTF8String);
	BTAssert([manager createDirectoryAtURL:metadataURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0755 } error:&error], error.localizedDescription.UTF8String);
	NSArray<NSURL *> *entries = [manager contentsOfDirectoryAtURL:transportURL
		includingPropertiesForKeys:nil options:0 error:&error];
	BTAssert(entries != nil, error.localizedDescription.UTF8String);
	for (NSURL *entryURL in entries) {
		NSURL *destinationURL = [entryURL.lastPathComponent isEqualToString:@"Example.bundle"] ?
			payloadURL : [metadataURL URLByAppendingPathComponent:entryURL.lastPathComponent
				isDirectory:[entryURL hasDirectoryPath]];
		BTAssert([manager moveItemAtURL:entryURL toURL:destinationURL error:&error],
			error.localizedDescription.UTF8String);
	}
	BTAssert([manager removeItemAtURL:transportURL error:&error], error.localizedDescription.UTF8String);
	return @{ @"metadata": metadataURL, @"payload": payloadURL };
}

static BTPluginPackageInspection *BTInspectSealed(NSDictionary<NSString *, NSURL *> *sealed,
	NSError **error) {
	return [[BTPluginSealedPackageStructuralVerifier new]
		inspectMetadataAtURL:sealed[@"metadata"] payloadURL:sealed[@"payload"] error:error];
}

int main(void) {
	@autoreleasepool {
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-structural-tests-%@", NSUUID.UUID.UUIDString]]
			isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);

		NSURL *validURL = BTCreateValidPackage(temporaryURL, @"Valid", 0x30);
		BTPluginPackageInspection *inspection = BTInspect(validURL, &error);
		BTAssert(inspection != nil, error.localizedDescription.UTF8String);
		BTAssert([inspection.manifest.pluginIdentifier isEqualToString:@"com.example.battman.analytics.fixture"], "identifier mismatch");
		BTAssert(inspection.manifest.author == nil, "legacy manifest unexpectedly acquired author metadata");
		BTAssert(inspection.filesByPath.count == 5, "unexpected inspected file count");
		BTAssert(inspection.signatureDataByKeyIdentifier.count == 1, "signature was not captured");
		BTAssert(inspection.packageSHA256.length == 64 && inspection.manifestSHA256.length == 64, "digest missing");

		NSArray<NSNumber *> *invalidPackageFormatVersions = @[
			@1.5,
			@1.0,
			[NSNumber numberWithBool:YES],
		];
		for (NSUInteger index = 0; index < invalidPackageFormatVersions.count; index++) {
			NSURL *formatURL = BTCreateValidPackage(temporaryURL,
				[NSString stringWithFormat:@"InvalidOuterFormat%lu", (unsigned long)index], 0x30);
			NSMutableDictionary *outerInfo = [[NSPropertyListSerialization propertyListWithData:
				[NSData dataWithContentsOfURL:[formatURL URLByAppendingPathComponent:@"Info.plist"]]
				options:NSPropertyListMutableContainers format:NULL error:&error] mutableCopy];
			outerInfo[@"BTPluginPackageFormatVersion"] = invalidPackageFormatVersions[index];
			BTReplaceSignedFile(formatURL, @"Info.plist", BTPropertyListData(outerInfo));
			error = nil;
			BTAssert(BTInspect(formatURL, &error) == nil && error.code == BTPluginPackageErrorInvalidInfoPlist,
				"a non-integer or boolean outer package format version was accepted");
		}

		NSArray<NSDictionary<NSString *, NSString *> *> *invalidBundleIdentities = @[
			@{ @"CFBundleExecutable": @"Wrong" },
			@{ @"CFBundleIdentifier": @"com.example.wrong" },
			@{ @"CFBundlePackageType": @"APPL" },
			@{ @"CFBundleShortVersionString": @"2.0" },
			@{ @"CFBundleVersion": @"2" },
		];
		for (NSUInteger index = 0; index < invalidBundleIdentities.count; index++) {
			NSURL *innerInfoURL = BTCreateValidPackage(temporaryURL,
				[NSString stringWithFormat:@"InvalidInnerInfo%lu", (unsigned long)index], 0x30);
			NSMutableDictionary *innerInfo = [[NSPropertyListSerialization propertyListWithData:
				[NSData dataWithContentsOfURL:[innerInfoURL URLByAppendingPathComponent:@"Example.bundle/Info.plist"]]
				options:NSPropertyListMutableContainers format:NULL error:&error] mutableCopy];
			[innerInfo addEntriesFromDictionary:invalidBundleIdentities[index]];
			BTReplaceSignedFile(innerInfoURL, @"Example.bundle/Info.plist", BTPropertyListData(innerInfo));
			error = nil;
			BTAssert(BTInspect(innerInfoURL, &error) == nil && error.code == BTPluginPackageErrorInvalidInfoPlist,
				"a signed bundle Info.plist identity mismatch was accepted");
		}

		NSURL *missingInnerInfoURL = BTCreateValidPackage(temporaryURL, @"MissingInnerInfo", 0x30);
		BTRemoveSignedFile(missingInnerInfoURL, @"Example.bundle/Info.plist");
		error = nil;
		BTAssert(BTInspect(missingInnerInfoURL, &error) == nil && error.code == BTPluginPackageErrorMissingFile,
			"a bundle payload without a signed inner Info.plist was accepted");

		NSURL *oversizedInnerInfoURL = BTCreateValidPackage(temporaryURL, @"OversizedInnerInfo", 0x30);
		NSMutableData *oversizedInnerInfo = [NSMutableData dataWithLength:64 * 1024 + 1];
		BTReplaceSignedFile(oversizedInnerInfoURL, @"Example.bundle/Info.plist", oversizedInnerInfo);
		error = nil;
		BTAssert(BTInspect(oversizedInnerInfoURL, &error) == nil && error.code == BTPluginPackageErrorLimitExceeded,
			"an oversized signed bundle Info.plist was accepted");

		NSData *duplicateJSON = [@"{\"formatVersion\":1,\"formatVersion\":1}" dataUsingEncoding:NSUTF8StringEncoding];
		error = nil;
		BTAssert([BTPluginPackageManifest manifestWithData:duplicateJSON error:&error] == nil, "duplicate JSON key accepted");
		BTAssert(error.code == BTPluginPackageErrorInvalidJSON, "duplicate key returned the wrong error");

		NSURL *validManifestURL = [validURL URLByAppendingPathComponent:@"Manifest.json"];
		NSMutableDictionary *authorManifestDictionary = [NSJSONSerialization JSONObjectWithData:
			[NSData dataWithContentsOfURL:validManifestURL] options:NSJSONReadingMutableContainers error:&error];
		BTAssert(authorManifestDictionary != nil, error.localizedDescription.UTF8String);
		authorManifestDictionary[@"author"] = [@{
			@"name": @"Example Developer",
			@"homepageURL": @"https://example.com/battman",
			@"supportEmail": @"support@example.com",
		} mutableCopy];
		NSData *authorManifestData = [NSJSONSerialization dataWithJSONObject:authorManifestDictionary
			options:NSJSONWritingSortedKeys error:&error];
		BTPluginPackageManifest *authorManifest = [BTPluginPackageManifest
			manifestWithData:authorManifestData error:&error];
		BTAssert(authorManifest != nil, error.localizedDescription.UTF8String);
		BTAssert([authorManifest.author.name isEqualToString:@"Example Developer"] &&
			[authorManifest.author.homepageURL isEqualToString:@"https://example.com/battman"] &&
			[authorManifest.author.supportEmail isEqualToString:@"support@example.com"],
			"signed author metadata did not round-trip");

		NSArray<NSDictionary *> *invalidAuthors = @[
			@{ @"name": @"Trailing Space " },
			@{ @"name": @"Example", @"homepageURL": @"http://example.com" },
			@{ @"name": @"Example", @"homepageURL": @"https://user@example.com" },
			@{ @"name": @"Example", @"supportEmail": @"support@localhost" },
			@{ @"name": @"Example", @"supportURL": @"https://example.com/support" },
		];
		for (NSDictionary *invalidAuthor in invalidAuthors) {
			authorManifestDictionary[@"author"] = invalidAuthor;
			NSData *invalidData = [NSJSONSerialization dataWithJSONObject:authorManifestDictionary
				options:NSJSONWritingSortedKeys error:&error];
			error = nil;
			BTAssert([BTPluginPackageManifest manifestWithData:invalidData error:&error] == nil &&
				error.code == BTPluginPackageErrorInvalidManifest,
				"unsafe or unknown author metadata was accepted");
		}

		NSMutableDictionary *displayManifestDictionary = [authorManifestDictionary mutableCopy];
		[displayManifestDictionary removeObjectForKey:@"author"];
		NSArray<NSString *> *invalidDisplayNames = @[
			@" Leading Space",
			@"Trailing Space ",
			@"Injected\nWarning",
			@"Injected\u2028Warning",
			@"Injected\u2029Warning",
			@"Reordered \u202eName",
			@"Cafe\u0301",
		];
		for (NSString *invalidDisplayName in invalidDisplayNames) {
			displayManifestDictionary[@"displayName"] = invalidDisplayName;
			NSData *invalidData = [NSJSONSerialization dataWithJSONObject:displayManifestDictionary
				options:NSJSONWritingSortedKeys error:&error];
			error = nil;
			BTAssert([BTPluginPackageManifest manifestWithData:invalidData error:&error] == nil &&
				error.code == BTPluginPackageErrorInvalidManifest,
				"unsafe displayName was accepted for host-owned consent UI");
		}

		NSString *astralCharacter = @"\U0001f680";
		NSString *displayNameAtScalarLimit = BTRepeatedString(astralCharacter, 256);
		displayManifestDictionary[@"displayName"] = displayNameAtScalarLimit;
		error = nil;
		NSData *displayNameAtScalarLimitData = [NSJSONSerialization
			dataWithJSONObject:displayManifestDictionary options:NSJSONWritingSortedKeys error:&error];
		BTPluginPackageManifest *displayNameAtScalarLimitManifest = [BTPluginPackageManifest
			manifestWithData:displayNameAtScalarLimitData error:&error];
		BTAssert(displayNameAtScalarLimitManifest != nil &&
			[displayNameAtScalarLimitManifest.displayName isEqualToString:displayNameAtScalarLimit],
			"a 256-scalar astral displayName was rejected");

		displayManifestDictionary[@"displayName"] = BTRepeatedString(astralCharacter, 257);
		error = nil;
		NSData *displayNameOverScalarLimitData = [NSJSONSerialization
			dataWithJSONObject:displayManifestDictionary options:NSJSONWritingSortedKeys error:&error];
		BTAssert([BTPluginPackageManifest manifestWithData:displayNameOverScalarLimitData error:&error] == nil &&
			error.code == BTPluginPackageErrorInvalidManifest,
			"a 257-scalar astral displayName was accepted");

		displayManifestDictionary[@"displayName"] = @"Verifier Fixture";
		NSString *authorNameAtScalarLimit = BTRepeatedString(astralCharacter, 128);
		displayManifestDictionary[@"author"] = @{ @"name": authorNameAtScalarLimit };
		error = nil;
		NSData *authorNameAtScalarLimitData = [NSJSONSerialization
			dataWithJSONObject:displayManifestDictionary options:NSJSONWritingSortedKeys error:&error];
		BTPluginPackageManifest *authorNameAtScalarLimitManifest = [BTPluginPackageManifest
			manifestWithData:authorNameAtScalarLimitData error:&error];
		BTAssert(authorNameAtScalarLimitManifest != nil &&
			[authorNameAtScalarLimitManifest.author.name isEqualToString:authorNameAtScalarLimit],
			"a 128-scalar astral author.name was rejected");

		displayManifestDictionary[@"author"] = @{
			@"name": BTRepeatedString(astralCharacter, 129),
		};
		error = nil;
		NSData *authorNameOverScalarLimitData = [NSJSONSerialization
			dataWithJSONObject:displayManifestDictionary options:NSJSONWritingSortedKeys error:&error];
		BTAssert([BTPluginPackageManifest manifestWithData:authorNameOverScalarLimitData error:&error] == nil &&
			error.code == BTPluginPackageErrorInvalidManifest,
			"a 129-scalar astral author.name was accepted");

		NSURL *unlistedURL = BTCreateValidPackage(temporaryURL, @"Unlisted", 0x30);
		BTWriteData([@"extra" dataUsingEncoding:NSUTF8StringEncoding], [unlistedURL URLByAppendingPathComponent:@"extra.txt"], @0644);
		error = nil;
		BTAssert(BTInspect(unlistedURL, &error) == nil && error.code == BTPluginPackageErrorUnexpectedFile,
			"unlisted file accepted");

		NSURL *hashURL = BTCreateValidPackage(temporaryURL, @"HashMismatch", 0x30);
		BTWriteData([@"changed" dataUsingEncoding:NSUTF8StringEncoding],
			[hashURL URLByAppendingPathComponent:@"Example.bundle/Info.plist"], @0644);
		error = nil;
		BTAssert(BTInspect(hashURL, &error) == nil && error.code == BTPluginPackageErrorHashMismatch,
			"hash mismatch accepted");

	NSURL *caseURL = BTCreateValidPackage(temporaryURL, @"CaseCollision", 0x30);
	BTWriteData([@"collision" dataUsingEncoding:NSUTF8StringEncoding],
		[caseURL URLByAppendingPathComponent:@"info.PLIST"], @0644);
	error = nil;
	/* Case-insensitive volumes may overwrite Info.plist instead of creating a
	 * second directory entry; either outcome must still fail closed. */
	BTAssert(BTInspect(caseURL, &error) == nil && error != nil,
		"case-colliding or overwritten path accepted");

		NSURL *symlinkURL = BTCreateValidPackage(temporaryURL, @"Symlink", 0x30);
		BTAssert([manager createSymbolicLinkAtURL:[symlinkURL URLByAppendingPathComponent:@"escape"]
			withDestinationURL:[NSURL fileURLWithPath:@"/etc/passwd"] error:&error], error.localizedDescription.UTF8String);
		error = nil;
		BTAssert(BTInspect(symlinkURL, &error) == nil && error.code == BTPluginPackageErrorUnsafePath,
			"symbolic link accepted");

		NSURL *hardLinkURL = BTCreateValidPackage(temporaryURL, @"HardLink", 0x30);
		NSString *sourcePath = [hardLinkURL URLByAppendingPathComponent:@"Info.plist"].path;
		NSString *linkPath = [hardLinkURL URLByAppendingPathComponent:@"hardlink"].path;
		BTAssert(link(sourcePath.fileSystemRepresentation, linkPath.fileSystemRepresentation) == 0, "unable to create hard-link fixture");
		error = nil;
		BTAssert(BTInspect(hardLinkURL, &error) == nil && error.code == BTPluginPackageErrorUnsafePath,
			"hard link accepted");

		NSURL *digestAURL = BTCreateValidPackage(temporaryURL, @"DigestA", 0x30);
		NSURL *digestBURL = BTCreateValidPackage(temporaryURL, @"DigestB", 0x31);
		error = nil;
		BTPluginPackageInspection *digestA = BTInspect(digestAURL, &error);
		BTAssert(digestA != nil, error.localizedDescription.UTF8String);
		BTPluginPackageInspection *digestB = BTInspect(digestBURL, &error);
		BTAssert(digestB != nil, error.localizedDescription.UTF8String);
		BTAssert(![digestA.packageSHA256 isEqualToString:digestB.packageSHA256],
			"package digest ignored signature bytes");

		NSURL *sealedTransportURL = BTCreateValidPackage(temporaryURL, @"SealedTransport", 0x30);
		BTPluginPackageInspection *transportInspection = BTInspect(sealedTransportURL, &error);
		BTAssert(transportInspection != nil, error.localizedDescription.UTF8String);
		NSDictionary<NSString *, NSURL *> *sealed = BTCreateSealedRepresentation(temporaryURL,
			@"SealedValid.app", sealedTransportURL);
		BTPluginPackageInspection *sealedInspection = BTInspectSealed(sealed, &error);
		BTAssert(sealedInspection != nil, error.localizedDescription.UTF8String);
		BTAssert([sealedInspection.packageSHA256 isEqualToString:transportInspection.packageSHA256] &&
			[sealedInspection.manifestSHA256 isEqualToString:transportInspection.manifestSHA256] &&
			[sealedInspection.manifest.pluginIdentifier isEqualToString:transportInspection.manifest.pluginIdentifier],
			"sealed installed representation changed the signed logical transport identity");
		BTAssert([sealedInspection.payloadURL.lastPathComponent isEqualToString:
			@"com.example.battman.analytics.fixture.bundle"] &&
			[sealedInspection.executableURL.lastPathComponent isEqualToString:@"Example"] &&
			[sealedInspection.executableURL.URLByDeletingLastPathComponent.lastPathComponent
				isEqualToString:@"com.example.battman.analytics.fixture.bundle"],
			"sealed installed representation did not resolve the physical payload path");

		NSURL *sealedInfoMismatchTransportURL = BTCreateValidPackage(temporaryURL,
			@"SealedInfoMismatchTransport", 0x30);
		NSMutableDictionary *sealedInnerInfo = [[NSPropertyListSerialization propertyListWithData:
			[NSData dataWithContentsOfURL:[sealedInfoMismatchTransportURL
				URLByAppendingPathComponent:@"Example.bundle/Info.plist"]]
			options:NSPropertyListMutableContainers format:NULL error:&error] mutableCopy];
		sealedInnerInfo[@"CFBundleIdentifier"] = @"com.example.wrong";
		BTReplaceSignedFile(sealedInfoMismatchTransportURL, @"Example.bundle/Info.plist",
			BTPropertyListData(sealedInnerInfo));
		NSDictionary<NSString *, NSURL *> *sealedInfoMismatch = BTCreateSealedRepresentation(temporaryURL,
			@"SealedInfoMismatch.app", sealedInfoMismatchTransportURL);
		error = nil;
		BTAssert(BTInspectSealed(sealedInfoMismatch, &error) == nil &&
			error.code == BTPluginPackageErrorInvalidInfoPlist,
			"a sealed signed bundle Info.plist identity mismatch was accepted");

		NSURL *sealedFormatTransportURL = BTCreateValidPackage(temporaryURL,
			@"SealedInvalidFormatTransport", 0x30);
		NSMutableDictionary *sealedOuterInfo = [[NSPropertyListSerialization propertyListWithData:
			[NSData dataWithContentsOfURL:[sealedFormatTransportURL URLByAppendingPathComponent:@"Info.plist"]]
			options:NSPropertyListMutableContainers format:NULL error:&error] mutableCopy];
		sealedOuterInfo[@"BTPluginPackageFormatVersion"] = @1.0;
		BTReplaceSignedFile(sealedFormatTransportURL, @"Info.plist", BTPropertyListData(sealedOuterInfo));
		NSDictionary<NSString *, NSURL *> *sealedInvalidFormat = BTCreateSealedRepresentation(temporaryURL,
			@"SealedInvalidFormat.app", sealedFormatTransportURL);
		error = nil;
		BTAssert(BTInspectSealed(sealedInvalidFormat, &error) == nil &&
			error.code == BTPluginPackageErrorInvalidInfoPlist,
			"a sealed float package format version was accepted");

		NSURL *tamperedTransportURL = BTCreateValidPackage(temporaryURL, @"SealedTamperedTransport", 0x30);
		NSDictionary<NSString *, NSURL *> *tampered = BTCreateSealedRepresentation(temporaryURL,
			@"SealedTampered.app", tamperedTransportURL);
		BTWriteData([@"changed" dataUsingEncoding:NSUTF8StringEncoding],
			[tampered[@"payload"] URLByAppendingPathComponent:@"Info.plist"], @0644);
		error = nil;
		BTAssert(BTInspectSealed(tampered, &error) == nil && error.code == BTPluginPackageErrorHashMismatch,
			"tampered sealed payload bytes were accepted");

		NSURL *linkedTransportURL = BTCreateValidPackage(temporaryURL, @"SealedLinkedTransport", 0x30);
		NSDictionary<NSString *, NSURL *> *linked = BTCreateSealedRepresentation(temporaryURL,
			@"SealedLinked.app", linkedTransportURL);
		BTAssert([manager createSymbolicLinkAtURL:[linked[@"payload"] URLByAppendingPathComponent:@"escape"]
			withDestinationURL:[NSURL fileURLWithPath:@"/etc/passwd"] error:&error],
			error.localizedDescription.UTF8String);
		error = nil;
		BTAssert(BTInspectSealed(linked, &error) == nil && error.code == BTPluginPackageErrorUnsafePath,
			"symbolic link in a sealed payload was accepted");

		NSURL *misnamedTransportURL = BTCreateValidPackage(temporaryURL, @"SealedMisnamedTransport", 0x30);
		NSDictionary<NSString *, NSURL *> *misnamed = BTCreateSealedRepresentation(temporaryURL,
			@"SealedMisnamed.app", misnamedTransportURL);
		NSURL *misnamedPayloadURL = [misnamed[@"payload"].URLByDeletingLastPathComponent
			URLByAppendingPathComponent:@"com.example.wrong.bundle" isDirectory:YES];
		BTAssert([manager moveItemAtURL:misnamed[@"payload"] toURL:misnamedPayloadURL error:&error],
			error.localizedDescription.UTF8String);
		error = nil;
		BTAssert([[BTPluginSealedPackageStructuralVerifier new]
			inspectMetadataAtURL:misnamed[@"metadata"] payloadURL:misnamedPayloadURL error:&error] == nil &&
			error.code == BTPluginPackageErrorSealedPackage,
			"misnamed sealed payload was accepted");

		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		printf("Transport and sealed installed structural verifier tests passed.\n");
	}
	return 0;
}
