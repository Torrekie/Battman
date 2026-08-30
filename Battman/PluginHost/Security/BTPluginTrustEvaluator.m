//
//  BTPluginTrustEvaluator.m
//  Battman
//

#import "BTPluginTrustEvaluator.h"

#import "../../../PluginSDK/include/BattmanPluginABI.h"
#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"
#import "BTPluginP256.h"

static BOOL BTPluginTrustFail(NSError **error, BTPluginPackageErrorCode code, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, nil, nil);
	return NO;
}

static BOOL BTPluginTrustScopeSetIsValid(NSSet<NSString *> *values) {
	if (![values isKindOfClass:[NSSet class]] || values.count == 0 || values.count > 64)
		return NO;
	for (id value in values) {
		if (![value isKindOfClass:[NSString class]] || !BTPluginIdentifierIsValid(value))
			return NO;
	}
	return YES;
}

@interface BTPluginTrustScope ()
@property (nonatomic, copy, readwrite) NSSet<NSString *> *pluginIdentifiers;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *extensionPointIdentifiers;
@end

@implementation BTPluginTrustScope

- (instancetype)initWithPluginIdentifiers:(NSSet<NSString *> *)pluginIdentifiers
				 extensionPointIdentifiers:(NSSet<NSString *> *)extensionPointIdentifiers
										  error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (!BTPluginTrustScopeSetIsValid(pluginIdentifiers) || !BTPluginTrustScopeSetIsValid(extensionPointIdentifiers)) {
		BTPluginTrustFail(error, BTPluginPackageErrorInvalidSignature, @"An official publisher scope is malformed.");
		return nil;
	}
	_pluginIdentifiers = [pluginIdentifiers copy];
	_extensionPointIdentifiers = [extensionPointIdentifiers copy];
	return self;
}

@end

@interface BTPluginTrustPolicy ()
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSData *> *officialPublicKeysByIdentifier;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, BTPluginTrustScope *> *officialScopesByKeyIdentifier;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *revokedKeyIdentifiers;
@property (nonatomic, readwrite) uint64_t metadataSequence;
@property (nonatomic, copy, readwrite) NSDate *metadataUpdatedAt;
@end

@implementation BTPluginTrustPolicy

- (instancetype)initWithOfficialPublicKeysByIdentifier:(NSDictionary<NSString *,NSData *> *)officialPublicKeysByIdentifier
								 officialScopesByKeyIdentifier:(NSDictionary<NSString *,BTPluginTrustScope *> *)officialScopesByKeyIdentifier
										revokedKeyIdentifiers:(NSSet<NSString *> *)revokedKeyIdentifiers
												metadataSequence:(uint64_t)metadataSequence
											   metadataUpdatedAt:(NSDate *)metadataUpdatedAt
															error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (![officialPublicKeysByIdentifier isKindOfClass:[NSDictionary class]] || officialPublicKeysByIdentifier.count > 16 ||
		![officialScopesByKeyIdentifier isKindOfClass:[NSDictionary class]] ||
		![[NSSet setWithArray:officialPublicKeysByIdentifier.allKeys] isEqualToSet:[NSSet setWithArray:officialScopesByKeyIdentifier.allKeys]] ||
		![revokedKeyIdentifiers isKindOfClass:[NSSet class]] || revokedKeyIdentifiers.count > 64 ||
		metadataSequence == 0 || ![metadataUpdatedAt isKindOfClass:[NSDate class]]) {
		BTPluginTrustFail(error, BTPluginPackageErrorInvalidSignature, @"The offline trust policy is malformed.");
		return nil;
	}
	for (NSString *keyIdentifier in officialPublicKeysByIdentifier) {
		NSData *publicKeyData = officialPublicKeysByIdentifier[keyIdentifier];
		BTPluginTrustScope *scope = officialScopesByKeyIdentifier[keyIdentifier];
		if (!BTPluginP256PublicKeyMatchesIdentifier(publicKeyData, keyIdentifier) ||
			![scope isKindOfClass:[BTPluginTrustScope class]]) {
			BTPluginTrustFail(error, BTPluginPackageErrorInvalidSignature, @"An official trust-policy key has an invalid fingerprint or encoding.");
			return nil;
		}
	}
	for (id keyIdentifier in revokedKeyIdentifiers) {
		if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier)) {
			BTPluginTrustFail(error, BTPluginPackageErrorInvalidSignature, @"The offline trust policy contains an invalid revoked key identifier.");
			return nil;
		}
	}
	_officialPublicKeysByIdentifier = [officialPublicKeysByIdentifier copy];
	_officialScopesByKeyIdentifier = [officialScopesByKeyIdentifier copy];
	_revokedKeyIdentifiers = [revokedKeyIdentifiers copy];
	_metadataSequence = metadataSequence;
	_metadataUpdatedAt = [metadataUpdatedAt copy];
	return self;
}

@end

@interface BTPluginTrustEvaluation ()
@property (nonatomic, readwrite) BTPluginTrustDisposition disposition;
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite) NSString *publisherKeyIdentifier;
@property (nonatomic, copy, readwrite) NSString *packageSHA256;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *requestedExtensionPointIdentifiers;
@property (nonatomic, strong, readwrite) BTPluginSignatureVerificationResult *signatureResult;
@property (nonatomic, copy, readwrite) NSDate *trustMetadataUpdatedAt;
@property (nonatomic, readwrite) uint64_t trustMetadataSequence;
- (instancetype)bt_init;
@end

@implementation BTPluginTrustEvaluation
- (instancetype)bt_init { return [super init]; }
- (BOOL)isApprovedForActivation { return self.disposition != BTPluginTrustDispositionRequiresApproval; }
@end

@interface BTPluginTrustEvaluator ()
@property (nonatomic, strong) BTPluginTrustPolicy *policy;
@property (nonatomic, strong) id<BTPluginTrustStore> trustStore;
@property (nonatomic, strong) BTPluginSignatureVerifier *signatureVerifier;
@end

@implementation BTPluginTrustEvaluator

- (instancetype)initWithPolicy:(BTPluginTrustPolicy *)policy trustStore:(id<BTPluginTrustStore>)trustStore {
	self = [super init];
	if (self) {
		_policy = policy;
		_trustStore = trustStore;
		_signatureVerifier = [BTPluginSignatureVerifier new];
	}
	return self;
}

- (BTPluginTrustEvaluation *)evaluateInspection:(BTPluginPackageInspection *)inspection
										 developerMode:(BOOL)developerMode
												  error:(NSError **)error {
	if (![inspection isKindOfClass:[BTPluginPackageInspection class]] || !self.policy || !self.trustStore) {
		BTPluginTrustFail(error, BTPluginPackageErrorInvalidPackage, @"Trust evaluation received invalid input.");
		return nil;
	}
	BTPluginPackageManifest *manifest = inspection.manifest;
	if (!(manifest.minimumHostABI <= BT_PLUGIN_ABI_VERSION_1 && manifest.maximumHostABI >= BT_PLUGIN_ABI_VERSION_1)) {
		BTPluginTrustFail(error, BTPluginPackageErrorIncompatibleABI,
			@"The plug-in package does not support this Battman host ABI.");
		return nil;
	}

	NSString *primaryKeyIdentifier = manifest.publisher.primaryKeyIdentifier;
	NSError *storeError = nil;
	BTPluginPublisherApproval *publisherApproval = [self.trustStore publisherApprovalForKeyIdentifier:primaryKeyIdentifier
		error:&storeError];
	if (storeError) {
		if (error)
			*error = storeError;
		return nil;
	}
	BTPluginExactBuildApproval *buildApproval = [self.trustStore exactBuildApprovalForPackageSHA256:inspection.packageSHA256
		error:&storeError];
	if (storeError) {
		if (error)
			*error = storeError;
		return nil;
	}

	NSMutableDictionary<NSString *, NSData *> *externalKeys = [self.policy.officialPublicKeysByIdentifier mutableCopy];
	if (publisherApproval)
		externalKeys[publisherApproval.keyIdentifier] = publisherApproval.publicKeyData;
	BTPluginSignatureVerificationResult *signatureResult = [self.signatureVerifier verifyInspection:inspection
		publicKeysByIdentifier:externalKeys error:error];
	if (!signatureResult)
		return nil;

	NSMutableSet *revokedSigners = [signatureResult.verifiedKeyIdentifiers mutableCopy];
	[revokedSigners intersectSet:self.policy.revokedKeyIdentifiers];
	if (revokedSigners.count > 0) {
		BTPluginTrustFail(error, BTPluginPackageErrorRevokedPublisher,
			@"The package is signed by a publisher key in the local revocation set.");
		return nil;
	}

	uint64_t highestSequence = [self.trustStore highestReleaseSequenceForPluginIdentifier:manifest.pluginIdentifier
		publisherKeyIdentifier:primaryKeyIdentifier error:&storeError];
	if (storeError) {
		if (error)
			*error = storeError;
		return nil;
	}
	NSString *highestDigest = nil;
	if (highestSequence > 0) {
		highestDigest = [self.trustStore packageSHA256ForHighestReleaseOfPluginIdentifier:manifest.pluginIdentifier
			publisherKeyIdentifier:primaryKeyIdentifier error:&storeError];
		if (storeError || !highestDigest) {
			if (error)
				*error = storeError ?: BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
					@"The recorded rollback state is incomplete.", nil, nil);
			return nil;
		}
	}
	if (manifest.releaseSequence < highestSequence ||
		(manifest.releaseSequence == highestSequence && highestDigest && ![highestDigest isEqualToString:inspection.packageSHA256])) {
		BTPluginTrustFail(error, BTPluginPackageErrorRollback,
			@"The package is older than, or conflicts with, the locally recorded publisher release.");
		return nil;
	}

	NSMutableSet<NSString *> *requestedExtensionPoints = [NSMutableSet set];
	for (BTPluginManifestExtensionPoint *extensionPoint in manifest.extensionPoints)
		[requestedExtensionPoints addObject:extensionPoint.identifier];

	BTPluginTrustDisposition disposition = BTPluginTrustDispositionRequiresApproval;
	BTPluginTrustScope *officialScope = self.policy.officialScopesByKeyIdentifier[primaryKeyIdentifier];
	if (self.policy.officialPublicKeysByIdentifier[primaryKeyIdentifier] && officialScope &&
		[signatureResult.externallyProvidedKeyIdentifiers containsObject:primaryKeyIdentifier] &&
		[officialScope.pluginIdentifiers containsObject:manifest.pluginIdentifier] &&
		[requestedExtensionPoints isSubsetOfSet:officialScope.extensionPointIdentifiers]) {
		disposition = BTPluginTrustDispositionOfficial;
	} else if (buildApproval && [buildApproval.pluginIdentifier isEqualToString:manifest.pluginIdentifier] &&
		[buildApproval.publisherKeyIdentifier isEqualToString:primaryKeyIdentifier]) {
		// Prefer the narrower authorization when both an exact build and its
		// publisher are approved.  This preserves the user's explicit one-build
		// escape hatch across ABI-v1 publisher-key changes.
		disposition = BTPluginTrustDispositionExactBuild;
	} else if (publisherApproval && [publisherApproval.pluginIdentifiers containsObject:manifest.pluginIdentifier] &&
		[requestedExtensionPoints isSubsetOfSet:publisherApproval.extensionPointIdentifiers]) {
		disposition = BTPluginTrustDispositionTrustedPublisher;
	} else if (developerMode) {
		disposition = BTPluginTrustDispositionDeveloper;
	}

	BTPluginTrustEvaluation *evaluation = [[BTPluginTrustEvaluation alloc] bt_init];
	evaluation.disposition = disposition;
	evaluation.pluginIdentifier = manifest.pluginIdentifier;
	evaluation.publisherKeyIdentifier = primaryKeyIdentifier;
	evaluation.packageSHA256 = inspection.packageSHA256;
	evaluation.requestedExtensionPointIdentifiers = requestedExtensionPoints;
	evaluation.signatureResult = signatureResult;
	evaluation.trustMetadataUpdatedAt = self.policy.metadataUpdatedAt;
	evaluation.trustMetadataSequence = self.policy.metadataSequence;
	return evaluation;
}

- (BOOL)recordActivatedInspection:(BTPluginPackageInspection *)inspection
						 evaluation:(BTPluginTrustEvaluation *)evaluation
								 error:(NSError **)error {
	if (![inspection isKindOfClass:[BTPluginPackageInspection class]] ||
		![evaluation isKindOfClass:[BTPluginTrustEvaluation class]] || !evaluation.isApprovedForActivation ||
		![evaluation.pluginIdentifier isEqualToString:inspection.manifest.pluginIdentifier] ||
		![evaluation.publisherKeyIdentifier isEqualToString:inspection.manifest.publisher.primaryKeyIdentifier] ||
		![evaluation.packageSHA256 isEqualToString:inspection.packageSHA256])
		return BTPluginTrustFail(error, BTPluginPackageErrorTrustStore,
			@"Only the matching approved inspection can advance plug-in rollback state.");
	return [self.trustStore recordReleaseSequence:inspection.manifest.releaseSequence
		packageSHA256:inspection.packageSHA256
		forPluginIdentifier:inspection.manifest.pluginIdentifier
		publisherKeyIdentifier:inspection.manifest.publisher.primaryKeyIdentifier
		error:error];
}

@end
