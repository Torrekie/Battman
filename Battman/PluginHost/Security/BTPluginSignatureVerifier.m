//
//  BTPluginSignatureVerifier.m
//  Battman
//

#import "BTPluginSignatureVerifier.h"

#import "../Model/BTPluginPackageErrors.h"
#import "BTPluginP256.h"

static BOOL BTPluginSignatureFail(NSError **error, NSString *description, NSString *relativePath, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
			description, relativePath, underlyingError);
	return NO;
}

@interface BTPluginSignatureVerificationResult ()
@property (nonatomic, copy, readwrite) NSSet<NSString *> *verifiedKeyIdentifiers;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *externallyProvidedKeyIdentifiers;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *packageProvidedKeyIdentifiers;
@property (nonatomic, readwrite) BOOL primaryKeyUsedExternalTrustMaterial;
- (instancetype)bt_init;
@end

@implementation BTPluginSignatureVerificationResult
- (instancetype)bt_init { return [super init]; }
@end

@implementation BTPluginSignatureVerifier

- (BTPluginSignatureVerificationResult *)verifyInspection:(BTPluginPackageInspection *)inspection
								 publicKeysByIdentifier:(NSDictionary<NSString *,NSData *> *)publicKeysByIdentifier
													  error:(NSError **)error {
	if (![inspection isKindOfClass:[BTPluginPackageInspection class]] ||
		![publicKeysByIdentifier isKindOfClass:[NSDictionary class]]) {
		BTPluginSignatureFail(error, @"Signature verification received invalid input.", nil, nil);
		return nil;
	}
	NSMutableSet *verified = [NSMutableSet set];
	NSMutableSet *external = [NSMutableSet set];
	NSMutableSet *packageProvided = [NSMutableSet set];

	for (NSString *keyIdentifier in inspection.manifest.publisher.signatureKeyIdentifiers) {
		NSData *publicKeyData = publicKeysByIdentifier[keyIdentifier];
		BOOL usedExternal = publicKeyData != nil;
		if (!publicKeyData)
			publicKeyData = inspection.includedPublisherKeysByIdentifier[keyIdentifier];
		NSString *signaturePath = [NSString stringWithFormat:@"Signatures/%@.sig", keyIdentifier];
		NSData *signatureData = inspection.signatureDataByKeyIdentifier[keyIdentifier];
		if (!BTPluginP256PublicKeyMatchesIdentifier(publicKeyData, keyIdentifier)) {
			BTPluginSignatureFail(error,
				@"A declared signature has no valid P-256 public key with the expected fingerprint.", signaturePath, nil);
			return nil;
		}
		if (!BTPluginP256SignatureIsCanonicalDER(signatureData)) {
			BTPluginSignatureFail(error, @"A publisher signature is not canonical DER-encoded ECDSA.", signaturePath, nil);
			return nil;
		}

		if (!BTPluginP256VerifyMessage(inspection.manifestData, signatureData, publicKeyData, signaturePath, error))
			return nil;
		[verified addObject:keyIdentifier];
		if (usedExternal)
			[external addObject:keyIdentifier];
		else
			[packageProvided addObject:keyIdentifier];
	}

	BTPluginSignatureVerificationResult *result = [[BTPluginSignatureVerificationResult alloc] bt_init];
	result.verifiedKeyIdentifiers = verified;
	result.externallyProvidedKeyIdentifiers = external;
	result.packageProvidedKeyIdentifiers = packageProvided;
	result.primaryKeyUsedExternalTrustMaterial = [external containsObject:inspection.manifest.publisher.primaryKeyIdentifier];
	return result;
}

@end
