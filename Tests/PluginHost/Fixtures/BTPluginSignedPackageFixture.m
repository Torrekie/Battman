#import "BTPluginSignedPackageFixture.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

#import "../../../Battman/PluginHost/Security/BTPluginP256.h"

NSString * const BTPluginTestSignedPackageIdentifier = @"com.example.battman.analytics.fixture";
NSString * const BTPluginTestSignedPackageExtensionPoint = @"com.torrekie.battman.analytics.card.v1";

static void BTPluginTestFixtureFail(NSString *message) {
	fprintf(stderr, "Signed package fixture failed: %s\n", message.UTF8String ?: "unknown error");
	exit(1);
}

static NSString *BTPluginTestHexDigest(NSData *data) {
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

static void BTPluginTestWriteData(NSData *data, NSURL *url, NSNumber *permissions) {
	NSError *error = nil;
	if (![data writeToURL:url options:NSDataWritingAtomic error:&error] ||
		![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: permissions }
			ofItemAtPath:url.path error:&error])
		BTPluginTestFixtureFail(error.localizedDescription ?: @"could not write fixture data");
}

static NSData *BTPluginTestPropertyListData(NSDictionary *dictionary) {
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if (!data)
		BTPluginTestFixtureFail(error.localizedDescription ?: @"could not encode fixture property list");
	return data;
}

static NSDictionary *BTPluginTestManifestFile(NSString *path, NSData *data, NSString *mode) {
	return @{ @"path": path, @"size": @(data.length), @"mode": mode,
		@"sha256": BTPluginTestHexDigest(data) };
}

static NSArray<NSDictionary *> *BTPluginTestSortedManifestFiles(NSArray<NSDictionary *> *files) {
	return [files sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return [left[@"path"] compare:right[@"path"] options:NSLiteralSearch];
	}];
}

NSURL *BTPluginTestCreateSignedPackageVersioned(NSURL *parentURL, NSURL *executableSourceURL,
	NSString *packageFileName, NSString *displayVersion, NSString *buildVersion,
	uint64_t releaseSequence) {
	NSDictionary *keyAttributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef keyError = NULL;
	SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)keyAttributes, &keyError);
	if (!privateKey)
		BTPluginTestFixtureFail([(__bridge_transfer NSError *)keyError localizedDescription]);
	SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
	CFErrorRef exportError = NULL;
	CFDataRef exported = SecKeyCopyExternalRepresentation(publicKey, &exportError);
	CFRelease(publicKey);
	if (!exported) {
		CFRelease(privateKey);
		BTPluginTestFixtureFail([(__bridge_transfer NSError *)exportError localizedDescription]);
	}
	NSData *publicKeyData = CFBridgingRelease(exported);
	NSString *keyIdentifier = BTPluginP256KeyIdentifier(publicKeyData);

	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSURL *packageURL = [parentURL URLByAppendingPathComponent:packageFileName isDirectory:YES];
	NSURL *payloadURL = [packageURL URLByAppendingPathComponent:@"Example.bundle" isDirectory:YES];
	NSURL *signatureDirectoryURL = [packageURL URLByAppendingPathComponent:@"Signatures" isDirectory:YES];
	NSURL *publisherDirectoryURL = [packageURL URLByAppendingPathComponent:@"PublisherKeys" isDirectory:YES];
	NSDictionary *directoryAttributes = @{ NSFilePosixPermissions: @0755 };
	for (NSURL *directoryURL in @[ payloadURL, signatureDirectoryURL, publisherDirectoryURL ]) {
		if (![manager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES
			attributes:directoryAttributes error:&error]) {
			CFRelease(privateKey);
			BTPluginTestFixtureFail(error.localizedDescription ?: @"could not create fixture directory");
		}
	}

	NSData *executableData = [NSData dataWithContentsOfURL:executableSourceURL options:0 error:&error];
	if (!executableData) {
		CFRelease(privateKey);
		BTPluginTestFixtureFail(error.localizedDescription ?: @"could not read fixture executable");
	}
	NSData *payloadInfoData = BTPluginTestPropertyListData(@{
		@"CFBundleExecutable": @"Example",
		@"CFBundleIdentifier": BTPluginTestSignedPackageIdentifier,
		@"CFBundlePackageType": @"BNDL",
		@"CFBundleShortVersionString": displayVersion,
		@"CFBundleVersion": buildVersion,
	});
	NSData *outerInfoData = BTPluginTestPropertyListData(@{
		@"CFBundleIdentifier": BTPluginTestSignedPackageIdentifier,
		@"CFBundleDisplayName": @"Signed Native Fixture",
		@"CFBundleShortVersionString": displayVersion,
		@"CFBundleVersion": buildVersion,
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPackageFormatVersion": @1,
		@"BTPluginPublisherKeyIdentifier": keyIdentifier,
	});
	NSString *publisherKeyPath = [NSString stringWithFormat:@"PublisherKeys/%@.p256", keyIdentifier];
	BTPluginTestWriteData(executableData, [payloadURL URLByAppendingPathComponent:@"Example"], @0755);
	BTPluginTestWriteData(payloadInfoData, [payloadURL URLByAppendingPathComponent:@"Info.plist"], @0644);
	BTPluginTestWriteData(outerInfoData, [packageURL URLByAppendingPathComponent:@"Info.plist"], @0644);
	BTPluginTestWriteData(publicKeyData, [packageURL URLByAppendingPathComponent:publisherKeyPath], @0644);

	NSDictionary *manifest = @{
		@"formatVersion": @1,
		@"schemaVersion": @1,
		@"pluginIdentifier": BTPluginTestSignedPackageIdentifier,
		@"displayName": @"Signed Native Fixture",
		@"displayVersion": displayVersion,
		@"buildVersion": buildVersion,
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
			@{ @"identifier": BTPluginTestSignedPackageExtensionPoint, @"interfaceVersion": @1 },
		],
		@"files": BTPluginTestSortedManifestFiles(@[
			BTPluginTestManifestFile(@"Example.bundle/Example", executableData, @"executable"),
			BTPluginTestManifestFile(@"Example.bundle/Info.plist", payloadInfoData, @"data"),
			BTPluginTestManifestFile(@"Info.plist", outerInfoData, @"data"),
			BTPluginTestManifestFile(publisherKeyPath, publicKeyData, @"data"),
		]),
		@"dependencies": @[],
		@"releaseSequence": @(releaseSequence),
	};
	NSData *manifestData = [NSJSONSerialization dataWithJSONObject:manifest
		options:NSJSONWritingSortedKeys error:&error];
	if (!manifestData) {
		CFRelease(privateKey);
		BTPluginTestFixtureFail(error.localizedDescription ?: @"could not encode fixture manifest");
	}
	BTPluginTestWriteData(manifestData, [packageURL URLByAppendingPathComponent:@"Manifest.json"], @0644);
	CFErrorRef signatureError = NULL;
	CFDataRef createdSignature = SecKeyCreateSignature(privateKey,
		kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
		(__bridge CFDataRef)manifestData, &signatureError);
	CFRelease(privateKey);
	if (!createdSignature)
		BTPluginTestFixtureFail([(__bridge_transfer NSError *)signatureError localizedDescription]);
	NSData *signatureData = CFBridgingRelease(createdSignature);
	BTPluginTestWriteData(signatureData,
		[signatureDirectoryURL URLByAppendingPathComponent:[keyIdentifier stringByAppendingPathExtension:@"sig"]],
		@0644);
	return packageURL;
}

NSURL *BTPluginTestCreateSignedPackage(NSURL *parentURL, NSURL *executableSourceURL,
	NSString *packageFileName) {
	return BTPluginTestCreateSignedPackageVersioned(parentURL, executableSourceURL, packageFileName,
		@"1.0", @"1", 1);
}
