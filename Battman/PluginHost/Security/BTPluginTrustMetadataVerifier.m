//
//  BTPluginTrustMetadataVerifier.m
//  Battman
//

#import "BTPluginTrustMetadataVerifier.h"

#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"
#import "../Model/BTPluginStrictJSON.h"
#import "BTPluginP256.h"

static const NSUInteger BTPluginTrustMetadataMaximumByteCount = 256 * 1024;

static BOOL BTPluginMetadataFail(NSError **error, BTPluginPackageErrorCode code, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, @"TrustMetadata.json", nil);
	return NO;
}

static NSString *BTPluginMetadataSHA256(NSData *data) {
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

static BOOL BTPluginMetadataHasExactKeys(NSDictionary *dictionary,
														 NSArray<NSString *> *keys,
														 NSError **error) {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
		![[NSSet setWithArray:dictionary.allKeys] isEqualToSet:[NSSet setWithArray:keys]])
		return BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata has missing or unknown object keys.");
	return YES;
}

static BOOL BTPluginMetadataInteger(NSDictionary *dictionary,
										 NSString *key,
										 uint64_t minimum,
										 uint64_t *output,
										 NSError **error) {
	id value = dictionary[key];
	if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
		return BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata contains a non-integer sequence or timestamp.");
	double number = [value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < (double)minimum || number > 9007199254740991.0)
		return BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata contains an out-of-range integer.");
	uint64_t integer = [value unsignedLongLongValue];
	if ((double)integer != number)
		return BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata contains an inexact integer.");
	*output = integer;
	return YES;
}

static NSSet<NSString *> *BTPluginMetadataIdentifierSet(id value,
															NSUInteger maximumCount,
															BOOL requireNonempty,
															NSError **error) {
	if (![value isKindOfClass:[NSArray class]] || [value count] > maximumCount || (requireNonempty && [value count] == 0)) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata has an invalid identifier list size.");
		return nil;
	}
	NSMutableSet *result = [NSMutableSet set];
	for (id identifier in value) {
		if (![identifier isKindOfClass:[NSString class]] || !BTPluginIdentifierIsValid(identifier) ||
			[result containsObject:identifier]) {
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
				@"Trust metadata contains an invalid or duplicate scoped identifier.");
			return nil;
		}
		[result addObject:identifier];
	}
	return result;
}

@interface BTPluginRootTrustPolicy ()
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSData *> *rootPublicKeysByIdentifier;
@property (nonatomic, readwrite) NSUInteger signatureThreshold;
@end

@implementation BTPluginRootTrustPolicy

- (instancetype)initWithRootPublicKeysByIdentifier:(NSDictionary<NSString *,NSData *> *)rootPublicKeysByIdentifier
									 signatureThreshold:(NSUInteger)signatureThreshold
														  error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (![rootPublicKeysByIdentifier isKindOfClass:[NSDictionary class]] || rootPublicKeysByIdentifier.count == 0 ||
		rootPublicKeysByIdentifier.count > 8 || signatureThreshold == 0 || signatureThreshold > rootPublicKeysByIdentifier.count) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
			@"The built-in root trust policy has an invalid key count or threshold.");
		return nil;
	}
	for (NSString *keyIdentifier in rootPublicKeysByIdentifier) {
		if (!BTPluginP256PublicKeyMatchesIdentifier(rootPublicKeysByIdentifier[keyIdentifier], keyIdentifier)) {
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
				@"A built-in root public key has an invalid fingerprint or encoding.");
			return nil;
		}
	}
	_rootPublicKeysByIdentifier = [rootPublicKeysByIdentifier copy];
	_signatureThreshold = signatureThreshold;
	return self;
}

@end

@interface BTPluginVerifiedTrustMetadata ()
@property (nonatomic, strong, readwrite) BTPluginTrustPolicy *trustPolicy;
@property (nonatomic, copy, readwrite) NSData *metadataData;
@property (nonatomic, copy, readwrite) NSString *metadataSHA256;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *verifiedRootKeyIdentifiers;
- (instancetype)bt_init;
@end

@implementation BTPluginVerifiedTrustMetadata
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginTrustMetadataVerifier ()
@property (nonatomic, strong) BTPluginRootTrustPolicy *rootPolicy;
@end

@implementation BTPluginTrustMetadataVerifier

- (instancetype)initWithRootPolicy:(BTPluginRootTrustPolicy *)rootPolicy {
	self = [super init];
	if (self)
		_rootPolicy = rootPolicy;
	return self;
}

- (BTPluginVerifiedTrustMetadata *)verifyMetadataData:(NSData *)metadataData
							  signaturesByRootKeyIdentifier:(NSDictionary<NSString *,NSData *> *)signaturesByRootKeyIdentifier
												previousSequence:(uint64_t)previousSequence
							 previousMetadataSHA256:(NSString *)previousMetadataSHA256
															error:(NSError **)error {
	if (!self.rootPolicy || ![signaturesByRootKeyIdentifier isKindOfClass:[NSDictionary class]] ||
		![metadataData isKindOfClass:[NSData class]] || metadataData.length == 0 ||
		metadataData.length > BTPluginTrustMetadataMaximumByteCount ||
		signaturesByRootKeyIdentifier.count < self.rootPolicy.signatureThreshold ||
		signaturesByRootKeyIdentifier.count > self.rootPolicy.rootPublicKeysByIdentifier.count) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
			@"Trust metadata does not provide the required root-signature threshold.");
		return nil;
	}
	NSMutableSet *verifiedRoots = [NSMutableSet set];
	for (NSString *keyIdentifier in signaturesByRootKeyIdentifier) {
		NSData *rootKey = self.rootPolicy.rootPublicKeysByIdentifier[keyIdentifier];
		NSData *signature = signaturesByRootKeyIdentifier[keyIdentifier];
		NSString *signaturePath = [NSString stringWithFormat:@"TrustMetadata.signatures/%@.sig", keyIdentifier];
		if (!rootKey || !BTPluginP256VerifyMessage(metadataData, signature, rootKey, signaturePath, error))
			return nil;
		[verifiedRoots addObject:keyIdentifier];
	}
	if (verifiedRoots.count < self.rootPolicy.signatureThreshold) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
			@"Trust metadata did not meet its root-signature threshold.");
		return nil;
	}

	NSString *metadataSHA256 = BTPluginMetadataSHA256(metadataData);
	if (previousSequence > 0 && !BTPluginPackageLowercaseSHA256IsValid(previousMetadataSHA256)) {
		BTPluginMetadataFail(error, BTPluginPackageErrorTrustStore,
			@"The locally recorded trust-metadata state is incomplete.");
		return nil;
	}
	id object = BTPluginStrictJSONObjectWithData(metadataData, BTPluginTrustMetadataMaximumByteCount,
		@"TrustMetadata.json", error);
	if (![object isKindOfClass:[NSDictionary class]]) {
		if (object)
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
				@"TrustMetadata.json must contain one object.");
		return nil;
	}
	NSDictionary *dictionary = object;
	NSArray *rootKeys = @[
		@"schemaVersion", @"sequence", @"generatedAtUnixSeconds",
		@"officialPublishers", @"revokedKeyIdentifiers"
	];
	if (!BTPluginMetadataHasExactKeys(dictionary, rootKeys, error))
		return nil;
	uint64_t schemaVersion = 0;
	uint64_t sequence = 0;
	uint64_t generatedAt = 0;
	if (!BTPluginMetadataInteger(dictionary, @"schemaVersion", 1, &schemaVersion, error) || schemaVersion != 1 ||
		!BTPluginMetadataInteger(dictionary, @"sequence", 1, &sequence, error) ||
		!BTPluginMetadataInteger(dictionary, @"generatedAtUnixSeconds", 0, &generatedAt, error)) {
		if (schemaVersion != 1 && error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidJSON,
				@"The trust-metadata schema version is unsupported.", @"TrustMetadata.json", nil);
		return nil;
	}
	if (sequence < previousSequence ||
		(sequence == previousSequence && previousSequence > 0 && ![metadataSHA256 isEqualToString:previousMetadataSHA256])) {
		BTPluginMetadataFail(error, BTPluginPackageErrorRollback,
			@"Trust metadata is older than, or conflicts with, the locally recorded sequence.");
		return nil;
	}

	id officialValue = dictionary[@"officialPublishers"];
	if (![officialValue isKindOfClass:[NSArray class]] || [officialValue count] > 16) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata contains too many official publisher records.");
		return nil;
	}
	NSMutableDictionary<NSString *, NSData *> *officialKeys = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, BTPluginTrustScope *> *officialScopes = [NSMutableDictionary dictionary];
	for (id value in officialValue) {
		NSArray *publisherKeys = @[
			@"keyIdentifier", @"publicKeyX963Base64", @"pluginIdentifiers", @"extensionPointIdentifiers"
		];
		if (!BTPluginMetadataHasExactKeys(value, publisherKeys, error))
			return nil;
		NSString *keyIdentifier = value[@"keyIdentifier"];
		NSString *base64 = value[@"publicKeyX963Base64"];
		if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) || ![base64 isKindOfClass:[NSString class]] ||
			base64.length != 88 || officialKeys[keyIdentifier]) {
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
				@"An official publisher key record is malformed or duplicated.");
			return nil;
		}
		NSData *publicKey = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
		if (!BTPluginP256PublicKeyMatchesIdentifier(publicKey, keyIdentifier) ||
			![[publicKey base64EncodedStringWithOptions:0] isEqualToString:base64]) {
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
				@"An official publisher public key has an invalid encoding or fingerprint.");
			return nil;
		}
		NSSet *plugins = BTPluginMetadataIdentifierSet(value[@"pluginIdentifiers"], 64, YES, error);
		NSSet *extensionPoints = BTPluginMetadataIdentifierSet(value[@"extensionPointIdentifiers"], 64, YES, error);
		if (!plugins || !extensionPoints)
			return nil;
		BTPluginTrustScope *scope = [[BTPluginTrustScope alloc]
			initWithPluginIdentifiers:plugins extensionPointIdentifiers:extensionPoints error:error];
		if (!scope)
			return nil;
		officialKeys[keyIdentifier] = publicKey;
		officialScopes[keyIdentifier] = scope;
	}

	id revokedValue = dictionary[@"revokedKeyIdentifiers"];
	if (![revokedValue isKindOfClass:[NSArray class]] || [revokedValue count] > 64) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
			@"Trust metadata contains an invalid revocation list.");
		return nil;
	}
	NSMutableSet *revoked = [NSMutableSet set];
	for (id keyIdentifier in revokedValue) {
		if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) || [revoked containsObject:keyIdentifier]) {
			BTPluginMetadataFail(error, BTPluginPackageErrorInvalidJSON,
				@"Trust metadata contains an invalid or duplicate revoked key.");
			return nil;
		}
		[revoked addObject:keyIdentifier];
	}
	NSMutableSet *activeRevoked = [NSMutableSet setWithArray:officialKeys.allKeys];
	[activeRevoked intersectSet:revoked];
	if (activeRevoked.count > 0) {
		BTPluginMetadataFail(error, BTPluginPackageErrorInvalidSignature,
			@"Trust metadata cannot delegate and revoke the same publisher key.");
		return nil;
	}

	NSDate *generatedDate = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)generatedAt];
	BTPluginTrustPolicy *policy = [[BTPluginTrustPolicy alloc]
		initWithOfficialPublicKeysByIdentifier:officialKeys
		officialScopesByKeyIdentifier:officialScopes
		revokedKeyIdentifiers:revoked
		metadataSequence:sequence
		metadataUpdatedAt:generatedDate
		error:error];
	if (!policy)
		return nil;
	BTPluginVerifiedTrustMetadata *verified = [[BTPluginVerifiedTrustMetadata alloc] bt_init];
	verified.trustPolicy = policy;
	verified.metadataData = metadataData;
	verified.metadataSHA256 = metadataSHA256;
	verified.verifiedRootKeyIdentifiers = verifiedRoots;
	return verified;
}

@end
