#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Security/BTPluginOfficialTrustLoader.h"
#import "../../Battman/PluginHost/Security/BTPluginP256.h"

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

static void BTCreateEphemeralKey(SecKeyRef *privateKeyOutput,
	NSData **publicKeyOutput,
	NSString **keyIdentifierOutput) {
	NSDictionary *attributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef createError = NULL;
	SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &createError);
	if (!privateKey) {
		NSError *underlying = CFBridgingRelease(createError);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
	CFErrorRef exportError = NULL;
	CFDataRef publicBytes = SecKeyCopyExternalRepresentation(publicKey, &exportError);
	CFRelease(publicKey);
	if (!publicBytes) {
		NSError *underlying = CFBridgingRelease(exportError);
		CFRelease(privateKey);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	NSData *publicData = CFBridgingRelease(publicBytes);
	*privateKeyOutput = privateKey;
	*publicKeyOutput = publicData;
	*keyIdentifierOutput = BTHexDigest(publicData);
}

static NSData *BTSign(SecKeyRef privateKey, NSData *data) {
	CFErrorRef signatureError = NULL;
	CFDataRef signature = SecKeyCreateSignature(privateKey,
		kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
		(__bridge CFDataRef)data, &signatureError);
	if (!signature) {
		NSError *underlying = CFBridgingRelease(signatureError);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	return CFBridgingRelease(signature);
}

static void BTWriteData(NSData *data, NSURL *url) {
	NSError *error = nil;
	BTAssert([data writeToURL:url options:NSDataWritingAtomic error:&error],
		error.localizedDescription.UTF8String);
	BTAssert([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0644 }
		ofItemAtPath:url.path error:&error], error.localizedDescription.UTF8String);
}

static NSURL *BTCreateApplicationBundle(NSURL *parent,
	SecKeyRef rootPrivateKey,
	NSData *rootPublicKey,
	NSString *rootIdentifier,
	NSData *publisherPublicKey,
	NSString *publisherIdentifier,
	uint64_t sequence) {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSURL *bundleURL = [parent URLByAppendingPathComponent:
		[NSString stringWithFormat:@"%@.app", NSUUID.UUID.UUIDString] isDirectory:YES];
	NSURL *trustURL = [bundleURL URLByAppendingPathComponent:@"PluginTrust" isDirectory:YES];
	NSURL *signaturesURL = [trustURL URLByAppendingPathComponent:@"TrustMetadata.signatures" isDirectory:YES];
	BTAssert([manager createDirectoryAtURL:signaturesURL withIntermediateDirectories:YES
		attributes:@{ NSFilePosixPermissions: @0755 } error:&error],
		error.localizedDescription.UTF8String);
	NSDictionary *rootPolicy = @{
		@"schemaVersion": @1,
		@"signatureThreshold": @1,
		@"rootPublicKeys": @[
			@{
				@"keyIdentifier": rootIdentifier,
				@"publicKeyX963Base64": [rootPublicKey base64EncodedStringWithOptions:0],
			},
		],
	};
	NSData *rootPolicyData = [NSPropertyListSerialization dataWithPropertyList:rootPolicy
		format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
	BTAssert(rootPolicyData != nil, error.localizedDescription.UTF8String);
	NSDictionary *metadata = @{
		@"schemaVersion": @1,
		@"sequence": @(sequence),
		@"generatedAtUnixSeconds": @123,
		@"officialPublishers": @[
			@{
				@"keyIdentifier": publisherIdentifier,
				@"publicKeyX963Base64": [publisherPublicKey base64EncodedStringWithOptions:0],
				@"pluginIdentifiers": @[ @"com.example.battman.official" ],
				@"extensionPointIdentifiers": @[ @"com.torrekie.battman.analytics.card.v1" ],
			},
		],
		@"revokedKeyIdentifiers": @[],
	};
	NSData *metadataData = [NSJSONSerialization dataWithJSONObject:metadata
		options:NSJSONWritingSortedKeys error:&error];
	BTAssert(metadataData != nil, error.localizedDescription.UTF8String);
	BTWriteData(rootPolicyData, [trustURL URLByAppendingPathComponent:@"RootPolicy.plist"]);
	BTWriteData(metadataData, [trustURL URLByAppendingPathComponent:@"TrustMetadata.json"]);
	BTWriteData(BTSign(rootPrivateKey, metadataData), [signaturesURL URLByAppendingPathComponent:
		[rootIdentifier stringByAppendingPathExtension:@"sig"]]);
	return bundleURL;
}

static void BTCleanupKeychainService(NSString *serviceName) {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
	BTAssert(status == errSecSuccess || status == errSecItemNotFound,
		"isolated trust-metadata Keychain records could not be deleted");
}

int main(void) {
	@autoreleasepool {
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-official-trust-%@",
				NSUUID.UUID.UUIDString]] isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error],
			error.localizedDescription.UTF8String);

		SecKeyRef rootPrivateKey = NULL;
		NSData *rootPublicKey = nil;
		NSString *rootIdentifier = nil;
		BTCreateEphemeralKey(&rootPrivateKey, &rootPublicKey, &rootIdentifier);
		SecKeyRef publisherPrivateKey = NULL;
		NSData *publisherPublicKey = nil;
		NSString *publisherIdentifier = nil;
		BTCreateEphemeralKey(&publisherPrivateKey, &publisherPublicKey, &publisherIdentifier);

		NSString *serviceName = [@"com.torrekie.Battman.PluginTrustMetadata.tests."
			stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
		BTCleanupKeychainService(serviceName);
		BTPluginKeychainTrustMetadataStateStore *store =
			[[BTPluginKeychainTrustMetadataStateStore alloc] initWithServiceName:serviceName];
		BTPluginOfficialTrustLoader *loader = [[BTPluginOfficialTrustLoader alloc]
			initWithStateStore:store];

		NSURL *emptyBundle = [temporaryURL URLByAppendingPathComponent:@"Empty.app" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:emptyBundle withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0755 } error:&error],
			error.localizedDescription.UTF8String);
		BTPluginOfficialTrustLoadResult *empty = [loader loadFromApplicationBundleURL:emptyBundle error:&error];
		BTAssert(empty != nil && !empty.isSignedMetadataLoaded &&
			empty.trustPolicy.officialPublicKeysByIdentifier.count == 0,
			"an absent engineering trust resource did not produce an empty policy");

		NSURL *validBundle = BTCreateApplicationBundle(temporaryURL, rootPrivateKey, rootPublicKey,
			rootIdentifier, publisherPublicKey, publisherIdentifier, 7);
		BTPluginOfficialTrustLoadResult *loaded = [loader loadFromApplicationBundleURL:validBundle error:&error];
		BTAssert(loaded != nil && loaded.isSignedMetadataLoaded &&
			loaded.trustPolicy.metadataSequence == 7 &&
			[loaded.trustPolicy.officialPublicKeysByIdentifier[publisherIdentifier]
				isEqualToData:publisherPublicKey] &&
			[loaded.verifiedRootKeyIdentifiers containsObject:rootIdentifier],
			"a valid app-bundled official trust snapshot did not load");
		NSString *expectedDigest = loaded.metadataSHA256;
		BTAssert([loader loadFromApplicationBundleURL:validBundle error:&error] != nil,
			"an idempotent official trust reload failed");

		error = nil;
		BTAssert([loader loadFromApplicationBundleURL:emptyBundle error:&error] == nil &&
			error.code == BTPluginPackageErrorRollback,
			"removing official metadata after recording it did not fail closed");

		NSURL *olderBundle = BTCreateApplicationBundle(temporaryURL, rootPrivateKey, rootPublicKey,
			rootIdentifier, publisherPublicKey, publisherIdentifier, 6);
		error = nil;
		BTAssert([loader loadFromApplicationBundleURL:olderBundle error:&error] == nil &&
			error.code == BTPluginPackageErrorRollback,
			"an older official trust snapshot was accepted");

		NSURL *conflictingBundle = BTCreateApplicationBundle(temporaryURL, rootPrivateKey, rootPublicKey,
			rootIdentifier, publisherPublicKey, publisherIdentifier, 7);
		NSURL *conflictingMetadataURL = [[conflictingBundle URLByAppendingPathComponent:@"PluginTrust"]
			URLByAppendingPathComponent:@"TrustMetadata.json"];
		NSMutableDictionary *conflictingMetadata = [[NSJSONSerialization JSONObjectWithData:
			[NSData dataWithContentsOfURL:conflictingMetadataURL] options:0 error:&error] mutableCopy];
		conflictingMetadata[@"generatedAtUnixSeconds"] = @124;
		NSData *conflictingData = [NSJSONSerialization dataWithJSONObject:conflictingMetadata
			options:NSJSONWritingSortedKeys error:&error];
		BTWriteData(conflictingData, conflictingMetadataURL);
		NSURL *conflictingSignatureURL = [[[conflictingBundle URLByAppendingPathComponent:@"PluginTrust"]
			URLByAppendingPathComponent:@"TrustMetadata.signatures"] URLByAppendingPathComponent:
			[rootIdentifier stringByAppendingPathExtension:@"sig"]];
		BTWriteData(BTSign(rootPrivateKey, conflictingData), conflictingSignatureURL);
		error = nil;
		BTAssert([loader loadFromApplicationBundleURL:conflictingBundle error:&error] == nil &&
			error.code == BTPluginPackageErrorRollback &&
			![BTHexDigest(conflictingData) isEqualToString:expectedDigest],
			"same-sequence official trust equivocation was accepted");

		NSString *freshServiceName = [@"com.torrekie.Battman.PluginTrustMetadata.tests."
			stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
		BTCleanupKeychainService(freshServiceName);
		BTPluginOfficialTrustLoader *freshLoader = [[BTPluginOfficialTrustLoader alloc]
			initWithStateStore:[[BTPluginKeychainTrustMetadataStateStore alloc]
				initWithServiceName:freshServiceName]];
		NSURL *partialBundle = [temporaryURL URLByAppendingPathComponent:@"Partial.app" isDirectory:YES];
		NSURL *partialTrust = [partialBundle URLByAppendingPathComponent:@"PluginTrust" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:partialTrust withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0755 } error:&error],
			error.localizedDescription.UTF8String);
		BTWriteData([@"partial" dataUsingEncoding:NSUTF8StringEncoding],
			[partialTrust URLByAppendingPathComponent:@"RootPolicy.plist"]);
		error = nil;
		BTAssert([freshLoader loadFromApplicationBundleURL:partialBundle error:&error] == nil && error != nil,
			"a partial official trust resource did not fail closed");

		NSURL *tamperedBundle = BTCreateApplicationBundle(temporaryURL, rootPrivateKey, rootPublicKey,
			rootIdentifier, publisherPublicKey, publisherIdentifier, 8);
		NSURL *tamperedSignatureURL = [[[tamperedBundle URLByAppendingPathComponent:@"PluginTrust"]
			URLByAppendingPathComponent:@"TrustMetadata.signatures"] URLByAppendingPathComponent:
			[rootIdentifier stringByAppendingPathExtension:@"sig"]];
		NSMutableData *tamperedSignature = [[NSData dataWithContentsOfURL:tamperedSignatureURL] mutableCopy];
		BTAssert(tamperedSignature.length > 0, "the signature fixture was empty");
		uint8_t *tamperedBytes = tamperedSignature.mutableBytes;
		tamperedBytes[tamperedSignature.length - 1] ^= 0x01;
		BTWriteData(tamperedSignature, tamperedSignatureURL);
		error = nil;
		BTAssert([freshLoader loadFromApplicationBundleURL:tamperedBundle error:&error] == nil && error != nil,
			"tampered official trust metadata signature was accepted");

		NSURL *symlinkBundle = [temporaryURL URLByAppendingPathComponent:@"Symlink.app" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:symlinkBundle withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0755 } error:&error],
			error.localizedDescription.UTF8String);
		BTAssert([manager createSymbolicLinkAtURL:[symlinkBundle URLByAppendingPathComponent:@"PluginTrust"]
			withDestinationURL:[validBundle URLByAppendingPathComponent:@"PluginTrust"] error:&error],
			error.localizedDescription.UTF8String);
		error = nil;
		BTAssert([freshLoader loadFromApplicationBundleURL:symlinkBundle error:&error] == nil && error != nil,
			"a symlinked official trust resource was accepted");

		BTCleanupKeychainService(serviceName);
		BTCleanupKeychainService(freshServiceName);
		CFRelease(publisherPrivateKey);
		CFRelease(rootPrivateKey);
		BTAssert([manager removeItemAtURL:temporaryURL error:&error],
			error.localizedDescription.UTF8String);
		printf("App-bundled official trust loading and rollback tests passed.\n");
	}
	return 0;
}
