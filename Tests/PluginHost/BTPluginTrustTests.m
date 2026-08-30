#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Security/BTPluginPackageStructuralVerifier.h"
#import "../../Battman/PluginHost/Security/BTPluginTrustEvaluator.h"
#import "../../Battman/PluginHost/Security/BTPluginTrustMetadataVerifier.h"

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

static NSData *BTPropertyListData(NSDictionary *dictionary) {
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictionary
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	BTAssert(data != nil, error.localizedDescription.UTF8String);
	return data;
}

static void BTWriteData(NSData *data, NSURL *url, NSNumber *permissions) {
	NSError *error = nil;
	BTAssert([data writeToURL:url options:NSDataWritingAtomic error:&error], error.localizedDescription.UTF8String);
	BTAssert([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: permissions }
		ofItemAtPath:url.path error:&error], error.localizedDescription.UTF8String);
}

static NSDictionary *BTManifestFile(NSString *path, NSData *data, NSString *mode) {
	return @{ @"path": path, @"size": @(data.length), @"mode": mode, @"sha256": BTHexDigest(data) };
}

static NSData *BTCreateSignature(SecKeyRef privateKey, NSData *manifestData) {
	CFErrorRef error = NULL;
	CFDataRef signature = SecKeyCreateSignature(privateKey,
		kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
		(__bridge CFDataRef)manifestData, &error);
	if (!signature) {
		NSError *underlying = CFBridgingRelease(error);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	return CFBridgingRelease(signature);
}

static void BTCreateEphemeralTestKey(SecKeyRef *privateKeyOutput,
										 NSData **publicKeyOutput,
										 NSString **keyIdentifierOutput) {
	NSDictionary *keyAttributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef keyError = NULL;
	SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)keyAttributes, &keyError);
	if (!privateKey) {
		NSError *underlying = CFBridgingRelease(keyError);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
	CFErrorRef exportError = NULL;
	CFDataRef publicKeyBytes = SecKeyCopyExternalRepresentation(publicKey, &exportError);
	CFRelease(publicKey);
	if (!publicKeyBytes) {
		NSError *underlying = CFBridgingRelease(exportError);
		CFRelease(privateKey);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	NSData *publicKeyData = CFBridgingRelease(publicKeyBytes);
	*privateKeyOutput = privateKey;
	*publicKeyOutput = publicKeyData;
	*keyIdentifierOutput = BTHexDigest(publicKeyData);
}

static NSURL *BTCreateSignedPackage(NSURL *parentURL,
										 SecKeyRef *privateKeyOutput,
										 NSData **publicKeyOutput,
										 NSString **keyIdentifierOutput) {
	SecKeyRef privateKey = NULL;
	NSData *publicKeyData = nil;
	NSString *keyIdentifier = nil;
	BTCreateEphemeralTestKey(&privateKey, &publicKeyData, &keyIdentifier);

	NSFileManager *manager = [NSFileManager defaultManager];
	NSError *error = nil;
	NSURL *packageURL = [parentURL URLByAppendingPathComponent:@"Signed.battman" isDirectory:YES];
	NSURL *payloadURL = [packageURL URLByAppendingPathComponent:@"Example.bundle" isDirectory:YES];
	NSURL *signatureDirectoryURL = [packageURL URLByAppendingPathComponent:@"Signatures" isDirectory:YES];
	NSURL *publisherDirectoryURL = [packageURL URLByAppendingPathComponent:@"PublisherKeys" isDirectory:YES];
	NSDictionary *directoryAttributes = @{ NSFilePosixPermissions: @0755 };
	BTAssert([manager createDirectoryAtURL:payloadURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);
	BTAssert([manager createDirectoryAtURL:signatureDirectoryURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);
	BTAssert([manager createDirectoryAtURL:publisherDirectoryURL withIntermediateDirectories:YES attributes:directoryAttributes error:&error],
		error.localizedDescription.UTF8String);

	NSData *executableData = [@"trust-fixture-never-executed" dataUsingEncoding:NSUTF8StringEncoding];
	NSData *payloadInfoData = BTPropertyListData(@{
		@"CFBundleExecutable": @"Example",
		@"CFBundleIdentifier": @"com.example.battman.analytics.signed",
		@"CFBundlePackageType": @"BNDL",
		@"CFBundleShortVersionString": @"1.0",
		@"CFBundleVersion": @"1",
	});
	NSData *outerInfoData = BTPropertyListData(@{
		@"CFBundleIdentifier": @"com.example.battman.analytics.signed",
		@"CFBundleDisplayName": @"Signed Fixture",
		@"CFBundleShortVersionString": @"1.0",
		@"CFBundleVersion": @"1",
		@"CFBundlePackageType": @"BTPG",
		@"BTPluginPackageFormatVersion": @1,
		@"BTPluginPublisherKeyIdentifier": keyIdentifier,
	});
	NSString *publisherKeyPath = [NSString stringWithFormat:@"PublisherKeys/%@.p256", keyIdentifier];
	BTWriteData(executableData, [payloadURL URLByAppendingPathComponent:@"Example"], @0755);
	BTWriteData(payloadInfoData, [payloadURL URLByAppendingPathComponent:@"Info.plist"], @0644);
	BTWriteData(outerInfoData, [packageURL URLByAppendingPathComponent:@"Info.plist"], @0644);
	BTWriteData(publicKeyData, [packageURL URLByAppendingPathComponent:publisherKeyPath], @0644);

	NSArray *files = @[
		BTManifestFile(@"Example.bundle/Example", executableData, @"executable"),
		BTManifestFile(@"Example.bundle/Info.plist", payloadInfoData, @"data"),
		BTManifestFile(@"Info.plist", outerInfoData, @"data"),
		BTManifestFile(publisherKeyPath, publicKeyData, @"data"),
	];
	NSDictionary *manifest = @{
		@"formatVersion": @1,
		@"schemaVersion": @1,
		@"pluginIdentifier": @"com.example.battman.analytics.signed",
		@"displayName": @"Signed Fixture",
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
	NSData *signatureData = BTCreateSignature(privateKey, manifestData);
	BTWriteData(signatureData,
		[signatureDirectoryURL URLByAppendingPathComponent:[keyIdentifier stringByAppendingPathExtension:@"sig"]], @0644);

	*privateKeyOutput = privateKey;
	*publicKeyOutput = publicKeyData;
	*keyIdentifierOutput = keyIdentifier;
	return packageURL;
}

@interface BTMemoryTrustStore : NSObject <BTPluginTrustStore>
@property (nonatomic, strong) NSMutableDictionary<NSString *, BTPluginPublisherApproval *> *publishers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BTPluginExactBuildApproval *> *builds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *releases;
@end

@implementation BTMemoryTrustStore

- (instancetype)init {
	self = [super init];
	if (self) {
		_publishers = [NSMutableDictionary dictionary];
		_builds = [NSMutableDictionary dictionary];
		_releases = [NSMutableDictionary dictionary];
	}
	return self;
}

- (NSString *)releaseKeyForPlugin:(NSString *)plugin key:(NSString *)key { return [NSString stringWithFormat:@"%@:%@", key, plugin]; }
- (BTPluginPublisherApproval *)publisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	(void)error;
	return self.publishers[keyIdentifier];
}
- (BTPluginExactBuildApproval *)exactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	(void)error;
	return self.builds[packageSHA256];
}
- (uint64_t)highestReleaseSequenceForPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)error;
	return [self.releases[[self releaseKeyForPlugin:pluginIdentifier key:publisherKeyIdentifier]][@"sequence"] unsignedLongLongValue];
}
- (NSString *)packageSHA256ForHighestReleaseOfPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)error;
	return self.releases[[self releaseKeyForPlugin:pluginIdentifier key:publisherKeyIdentifier]][@"digest"];
}
- (BOOL)storePublisherApproval:(BTPluginPublisherApproval *)approval error:(NSError **)error {
	(void)error;
	self.publishers[approval.keyIdentifier] = approval;
	return YES;
}
- (BOOL)storeExactBuildApproval:(BTPluginExactBuildApproval *)approval error:(NSError **)error {
	(void)error;
	self.builds[approval.packageSHA256] = approval;
	return YES;
}
- (BOOL)recordReleaseSequence:(uint64_t)releaseSequence packageSHA256:(NSString *)packageSHA256 forPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	NSString *key = [self releaseKeyForPlugin:pluginIdentifier key:publisherKeyIdentifier];
	NSDictionary *current = self.releases[key];
	uint64_t currentSequence = [current[@"sequence"] unsignedLongLongValue];
	if (currentSequence > releaseSequence || (currentSequence == releaseSequence && current && ![current[@"digest"] isEqualToString:packageSHA256])) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRollback, @"rollback", nil, nil);
		return NO;
	}
	self.releases[key] = @{ @"sequence": @(releaseSequence), @"digest": packageSHA256 };
	return YES;
}
- (BOOL)removePublisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	(void)error;
	[self.publishers removeObjectForKey:keyIdentifier];
	return YES;
}
- (BOOL)removeExactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	(void)error;
	[self.builds removeObjectForKey:packageSHA256];
	return YES;
}
@end

static BTPluginTrustPolicy *BTPolicy(NSDictionary *officialKeys, NSSet *revokedKeys) {
	NSError *error = nil;
	NSMutableDictionary *scopes = [NSMutableDictionary dictionary];
	for (NSString *keyIdentifier in officialKeys) {
		BTPluginTrustScope *scope = [[BTPluginTrustScope alloc]
			initWithPluginIdentifiers:[NSSet setWithObject:@"com.example.battman.analytics.signed"]
			extensionPointIdentifiers:[NSSet setWithObject:@"com.torrekie.battman.analytics.card.v1"]
			error:&error];
		BTAssert(scope != nil, error.localizedDescription.UTF8String);
		scopes[keyIdentifier] = scope;
	}
	BTPluginTrustPolicy *policy = [[BTPluginTrustPolicy alloc]
		initWithOfficialPublicKeysByIdentifier:officialKeys
		officialScopesByKeyIdentifier:scopes
		revokedKeyIdentifiers:revokedKeys
		metadataSequence:1
		metadataUpdatedAt:[NSDate dateWithTimeIntervalSince1970:1]
		error:&error];
	BTAssert(policy != nil, error.localizedDescription.UTF8String);
	return policy;
}

int main(void) {
	@autoreleasepool {
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-trust-tests-%@", NSUUID.UUID.UUIDString]]
			isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		SecKeyRef privateKey = NULL;
		NSData *publicKeyData = nil;
		NSString *keyIdentifier = nil;
		NSURL *packageURL = BTCreateSignedPackage(temporaryURL, &privateKey, &publicKeyData, &keyIdentifier);
		BTPluginPackageInspection *inspection = [[BTPluginPackageStructuralVerifier new] inspectPackageAtURL:packageURL error:&error];
		BTAssert(inspection != nil, error.localizedDescription.UTF8String);

		BTMemoryTrustStore *emptyStore = [BTMemoryTrustStore new];
		BTPluginTrustEvaluator *unknownEvaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:emptyStore];
		BTPluginTrustEvaluation *unknown = [unknownEvaluator evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(unknown != nil && unknown.disposition == BTPluginTrustDispositionRequiresApproval && !unknown.isApprovedForActivation,
			"unknown publisher was not quarantined for approval");
		error = nil;
		BTAssert(![unknownEvaluator recordActivatedInspection:inspection evaluation:unknown error:&error] &&
			error.code == BTPluginPackageErrorTrustStore, "unapproved package advanced rollback state");

		BTPluginTrustEvaluation *developer = [unknownEvaluator evaluateInspection:inspection developerMode:YES error:&error];
		BTAssert(developer.disposition == BTPluginTrustDispositionDeveloper && developer.isApprovedForActivation,
			"developer mode did not remain explicit");

		BTMemoryTrustStore *exactStore = [BTMemoryTrustStore new];
		BTPluginExactBuildApproval *exactApproval = [[BTPluginExactBuildApproval alloc]
			initWithPackageSHA256:inspection.packageSHA256
			pluginIdentifier:inspection.manifest.pluginIdentifier
			publisherKeyIdentifier:keyIdentifier approvedAt:[NSDate date] error:&error];
		BTAssert(exactApproval != nil && [exactStore storeExactBuildApproval:exactApproval error:&error], error.localizedDescription.UTF8String);
		BTPluginTrustEvaluator *exactEvaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:exactStore];
		BTPluginTrustEvaluation *exact = [exactEvaluator evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(exact.disposition == BTPluginTrustDispositionExactBuild, "exact-build approval was not honored");

		NSSet *plugins = [NSSet setWithObject:inspection.manifest.pluginIdentifier];
		NSSet *extensionPoints = [NSSet setWithObject:@"com.torrekie.battman.analytics.card.v1"];
		BTPluginPublisherApproval *publisherApproval = [[BTPluginPublisherApproval alloc]
			initWithKeyIdentifier:keyIdentifier publicKeyData:publicKeyData pluginIdentifiers:plugins
			extensionPointIdentifiers:extensionPoints approvedAt:[NSDate date] error:&error];
		BTAssert(publisherApproval != nil, error.localizedDescription.UTF8String);
		BTMemoryTrustStore *publisherStore = [BTMemoryTrustStore new];
		BTAssert([publisherStore storePublisherApproval:publisherApproval error:&error], error.localizedDescription.UTF8String);
		BTPluginTrustEvaluator *publisherEvaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:publisherStore];
		BTPluginTrustEvaluation *publisher = [publisherEvaluator evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(publisher.disposition == BTPluginTrustDispositionTrustedPublisher,
			"scoped publisher approval was not honored");
		BTAssert([publisherStore storeExactBuildApproval:exactApproval error:&error],
			error.localizedDescription.UTF8String);
		BTPluginTrustEvaluation *narrowerExact = [publisherEvaluator evaluateInspection:inspection
			developerMode:NO error:&error];
		BTAssert(narrowerExact.disposition == BTPluginTrustDispositionExactBuild,
			"broader publisher trust masked an explicit exact-build approval");

		BTPluginPublisherApproval *narrowApproval = [[BTPluginPublisherApproval alloc]
			initWithKeyIdentifier:keyIdentifier publicKeyData:publicKeyData pluginIdentifiers:plugins
			extensionPointIdentifiers:[NSSet setWithObject:@"com.example.unrelated.v1"] approvedAt:[NSDate date] error:&error];
		BTMemoryTrustStore *narrowStore = [BTMemoryTrustStore new];
		BTAssert([narrowStore storePublisherApproval:narrowApproval error:&error], error.localizedDescription.UTF8String);
		BTPluginTrustEvaluation *narrow = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:narrowStore]
			evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(narrow.disposition == BTPluginTrustDispositionRequiresApproval,
			"publisher approval escaped its extension-point scope");

		BTPluginTrustEvaluation *official = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{ keyIdentifier: publicKeyData }, [NSSet set]) trustStore:[BTMemoryTrustStore new]]
			evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(official.disposition == BTPluginTrustDispositionOfficial &&
			official.signatureResult.primaryKeyUsedExternalTrustMaterial, "official trust was not authenticated externally");

		SecKeyRef rootPrivateKey = NULL;
		NSData *rootPublicKeyData = nil;
		NSString *rootKeyIdentifier = nil;
		BTCreateEphemeralTestKey(&rootPrivateKey, &rootPublicKeyData, &rootKeyIdentifier);
		NSDictionary *trustMetadataObject = @{
			@"schemaVersion": @1,
			@"sequence": @5,
			@"generatedAtUnixSeconds": @1,
			@"officialPublishers": @[
				@{
					@"keyIdentifier": keyIdentifier,
					@"publicKeyX963Base64": [publicKeyData base64EncodedStringWithOptions:0],
					@"pluginIdentifiers": @[ inspection.manifest.pluginIdentifier ],
					@"extensionPointIdentifiers": @[ @"com.torrekie.battman.analytics.card.v1" ],
				},
			],
			@"revokedKeyIdentifiers": @[],
		};
		NSData *trustMetadataData = [NSJSONSerialization dataWithJSONObject:trustMetadataObject
			options:NSJSONWritingSortedKeys error:&error];
		BTAssert(trustMetadataData != nil, error.localizedDescription.UTF8String);
		NSData *rootSignature = BTCreateSignature(rootPrivateKey, trustMetadataData);
		BTPluginRootTrustPolicy *rootPolicy = [[BTPluginRootTrustPolicy alloc]
			initWithRootPublicKeysByIdentifier:@{ rootKeyIdentifier: rootPublicKeyData }
			signatureThreshold:1 error:&error];
		BTAssert(rootPolicy != nil, error.localizedDescription.UTF8String);
		BTPluginTrustMetadataVerifier *metadataVerifier = [[BTPluginTrustMetadataVerifier alloc]
			initWithRootPolicy:rootPolicy];
		BTPluginVerifiedTrustMetadata *verifiedMetadata = [metadataVerifier
			verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: rootSignature }
			previousSequence:0 previousMetadataSHA256:nil error:&error];
		BTAssert(verifiedMetadata != nil && verifiedMetadata.trustPolicy.metadataSequence == 5 &&
			[verifiedMetadata.verifiedRootKeyIdentifiers containsObject:rootKeyIdentifier],
			"root-signed trust metadata did not verify");
		BTPluginTrustEvaluation *metadataOfficial = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:verifiedMetadata.trustPolicy trustStore:[BTMemoryTrustStore new]]
			evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(metadataOfficial.disposition == BTPluginTrustDispositionOfficial,
			"verified trust metadata did not authorize its scoped official publisher");

		error = nil;
		BTAssert([metadataVerifier verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: rootSignature }
			previousSequence:6 previousMetadataSHA256:verifiedMetadata.metadataSHA256 error:&error] == nil &&
			error.code == BTPluginPackageErrorRollback, "older trust metadata was accepted");
		error = nil;
		NSString *wrongMetadataDigest = [@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
		BTAssert([metadataVerifier verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: rootSignature }
			previousSequence:5 previousMetadataSHA256:wrongMetadataDigest error:&error] == nil &&
			error.code == BTPluginPackageErrorRollback, "same-sequence trust-metadata equivocation was accepted");
		error = nil;
		BTAssert([metadataVerifier verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: rootSignature }
			previousSequence:5 previousMetadataSHA256:verifiedMetadata.metadataSHA256 error:&error] != nil,
			error.localizedDescription.UTF8String);

		NSData *duplicateMetadata = [@"{\"schemaVersion\":1,\"schemaVersion\":1}" dataUsingEncoding:NSUTF8StringEncoding];
		NSData *duplicateMetadataSignature = BTCreateSignature(rootPrivateKey, duplicateMetadata);
		error = nil;
		BTAssert([metadataVerifier verifyMetadataData:duplicateMetadata
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: duplicateMetadataSignature }
			previousSequence:0 previousMetadataSHA256:nil error:&error] == nil &&
			error.code == BTPluginPackageErrorInvalidJSON, "duplicate trust-metadata key was accepted");

		SecKeyRef secondRootPrivateKey = NULL;
		NSData *secondRootPublicKeyData = nil;
		NSString *secondRootKeyIdentifier = nil;
		BTCreateEphemeralTestKey(&secondRootPrivateKey, &secondRootPublicKeyData, &secondRootKeyIdentifier);
		NSData *secondRootSignature = BTCreateSignature(secondRootPrivateKey, trustMetadataData);
		BTPluginRootTrustPolicy *thresholdPolicy = [[BTPluginRootTrustPolicy alloc]
			initWithRootPublicKeysByIdentifier:@{
				rootKeyIdentifier: rootPublicKeyData,
				secondRootKeyIdentifier: secondRootPublicKeyData,
			} signatureThreshold:2 error:&error];
		BTPluginTrustMetadataVerifier *thresholdVerifier = [[BTPluginTrustMetadataVerifier alloc]
			initWithRootPolicy:thresholdPolicy];
		error = nil;
		BTAssert([thresholdVerifier verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{ rootKeyIdentifier: rootSignature }
			previousSequence:0 previousMetadataSHA256:nil error:&error] == nil &&
			error.code == BTPluginPackageErrorInvalidSignature, "root signature threshold was not enforced");
		error = nil;
		BTAssert(([thresholdVerifier verifyMetadataData:trustMetadataData
			signaturesByRootKeyIdentifier:@{
				rootKeyIdentifier: rootSignature,
				secondRootKeyIdentifier: secondRootSignature,
			} previousSequence:0 previousMetadataSHA256:nil error:&error] != nil),
			error.localizedDescription.UTF8String);
		CFRelease(secondRootPrivateKey);
		CFRelease(rootPrivateKey);

		error = nil;
		BTPluginTrustEvaluation *revoked = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet setWithObject:keyIdentifier]) trustStore:exactStore]
			evaluateInspection:inspection developerMode:NO error:&error];
		BTAssert(revoked == nil && error.code == BTPluginPackageErrorRevokedPublisher,
			"exact approval overrode a revoked publisher");

		BTMemoryTrustStore *rollbackStore = [BTMemoryTrustStore new];
		BTAssert([rollbackStore recordReleaseSequence:2 packageSHA256:inspection.packageSHA256
			forPluginIdentifier:inspection.manifest.pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error],
			error.localizedDescription.UTF8String);
		error = nil;
		BTPluginTrustEvaluation *rollback = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:rollbackStore]
			evaluateInspection:inspection developerMode:YES error:&error];
		BTAssert(rollback == nil && error.code == BTPluginPackageErrorRollback,
			"developer mode overrode rollback protection");

		BTMemoryTrustStore *equivocationStore = [BTMemoryTrustStore new];
		BTAssert([equivocationStore recordReleaseSequence:1 packageSHA256:inspection.packageSHA256
			forPluginIdentifier:inspection.manifest.pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error],
			error.localizedDescription.UTF8String);
		NSData *secondSignature = BTCreateSignature(privateKey, inspection.manifestData);
		NSURL *signatureURL = [packageURL URLByAppendingPathComponent:
			[NSString stringWithFormat:@"Signatures/%@.sig", keyIdentifier]];
		BTWriteData(secondSignature, signatureURL, @0644);
		BTPluginPackageInspection *equivocatingInspection = [[BTPluginPackageStructuralVerifier new]
			inspectPackageAtURL:packageURL error:&error];
		BTAssert(equivocatingInspection != nil, error.localizedDescription.UTF8String);
		BTAssert(![equivocatingInspection.packageSHA256 isEqualToString:inspection.packageSHA256],
			"test signer unexpectedly reproduced identical signature bytes");
		error = nil;
		BTPluginTrustEvaluation *equivocation = [[[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicy(@{}, [NSSet set]) trustStore:equivocationStore]
			evaluateInspection:equivocatingInspection developerMode:YES error:&error];
		BTAssert(equivocation == nil && error.code == BTPluginPackageErrorRollback,
			"same-sequence package equivocation was accepted");

		NSMutableData *badSignature = [secondSignature mutableCopy];
		uint8_t *signatureBytes = badSignature.mutableBytes;
		signatureBytes[badSignature.length - 1] ^= 1;
		BTWriteData(badSignature, signatureURL, @0644);
		BTPluginPackageInspection *badSignatureInspection = [[BTPluginPackageStructuralVerifier new]
			inspectPackageAtURL:packageURL error:&error];
		BTAssert(badSignatureInspection != nil, error.localizedDescription.UTF8String);
		error = nil;
		BTPluginTrustEvaluation *badSignatureResult = [unknownEvaluator evaluateInspection:badSignatureInspection
			developerMode:YES error:&error];
		BTAssert(badSignatureResult == nil && error.code == BTPluginPackageErrorInvalidSignature,
			"developer mode overrode a bad publisher signature");

		CFRelease(privateKey);
		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		printf("Offline plug-in signature, approval, revocation, and rollback tests passed.\n");
	}
	return 0;
}
