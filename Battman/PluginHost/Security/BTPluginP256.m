//
//  BTPluginP256.m
//  Battman
//

#import "BTPluginP256.h"

#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"

NSString *BTPluginP256KeyIdentifier(NSData *publicKeyData) {
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(publicKeyData.bytes, (CC_LONG)publicKeyData.length, digest);
	static const char digits[] = "0123456789abcdef";
	char output[CC_SHA256_DIGEST_LENGTH * 2 + 1];
	for (NSUInteger index = 0; index < sizeof(digest); index++) {
		output[index * 2] = digits[digest[index] >> 4];
		output[index * 2 + 1] = digits[digest[index] & 0x0f];
	}
	output[sizeof(digest) * 2] = '\0';
	return [NSString stringWithUTF8String:output];
}

BOOL BTPluginP256PublicKeyMatchesIdentifier(NSData *publicKeyData, NSString *keyIdentifier) {
	if (![publicKeyData isKindOfClass:[NSData class]] || publicKeyData.length != 65 ||
		((const uint8_t *)publicKeyData.bytes)[0] != 0x04 ||
		!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) ||
		![BTPluginP256KeyIdentifier(publicKeyData) isEqualToString:keyIdentifier])
		return NO;
	NSDictionary *attributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef keyError = NULL;
	SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
		(__bridge CFDictionaryRef)attributes, &keyError);
	if (key)
		CFRelease(key);
	if (keyError)
		CFRelease(keyError);
	return key != NULL;
}

static BOOL BTPluginP256IntegerIsCanonical(const uint8_t *bytes, NSUInteger length) {
	if (length == 0 || length > 33 || (bytes[0] & 0x80) != 0)
		return NO;
	if (length > 1 && bytes[0] == 0 && (bytes[1] & 0x80) == 0)
		return NO;
	BOOL nonzero = NO;
	for (NSUInteger index = 0; index < length; index++)
		nonzero |= bytes[index] != 0;
	return nonzero;
}

BOOL BTPluginP256SignatureIsCanonicalDER(NSData *signatureData) {
	if (![signatureData isKindOfClass:[NSData class]])
		return NO;
	const uint8_t *bytes = signatureData.bytes;
	NSUInteger length = signatureData.length;
	if (length < 8 || length > 72 || bytes[0] != 0x30 || bytes[1] != length - 2 || (bytes[1] & 0x80) != 0)
		return NO;
	NSUInteger index = 2;
	if (index + 2 > length || bytes[index++] != 0x02)
		return NO;
	NSUInteger rLength = bytes[index++];
	if (index + rLength + 2 > length || !BTPluginP256IntegerIsCanonical(bytes + index, rLength))
		return NO;
	index += rLength;
	if (bytes[index++] != 0x02)
		return NO;
	NSUInteger sLength = bytes[index++];
	return index + sLength == length && BTPluginP256IntegerIsCanonical(bytes + index, sLength);
}

BOOL BTPluginP256VerifyMessage(NSData *messageData,
								NSData *signatureData,
								NSData *publicKeyData,
								NSString *relativePath,
								NSError **error) {
	if (!BTPluginP256SignatureIsCanonicalDER(signatureData) || publicKeyData.length != 65 ||
		((const uint8_t *)publicKeyData.bytes)[0] != 0x04) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
				@"A P-256 public key or ECDSA signature has an invalid encoding.", relativePath, nil);
		return NO;
	}
	NSDictionary *attributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef keyError = NULL;
	SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)publicKeyData,
		(__bridge CFDictionaryRef)attributes, &keyError);
	if (!key) {
		NSError *underlying = CFBridgingRelease(keyError);
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
				@"A P-256 public key could not be decoded.", relativePath, underlying);
		return NO;
	}
	SecKeyAlgorithm algorithm = kSecKeyAlgorithmECDSASignatureMessageX962SHA256;
	if (!SecKeyIsAlgorithmSupported(key, kSecKeyOperationTypeVerify, algorithm)) {
		CFRelease(key);
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
				@"This platform cannot verify ECDSA P-256 with SHA-256.", relativePath, nil);
		return NO;
	}
	CFErrorRef verificationError = NULL;
	BOOL valid = SecKeyVerifySignature(key, algorithm,
		(__bridge CFDataRef)messageData, (__bridge CFDataRef)signatureData, &verificationError);
	CFRelease(key);
	if (!valid) {
		NSError *underlying = CFBridgingRelease(verificationError);
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
				@"An ECDSA signature does not match the exact signed bytes.", relativePath, underlying);
		return NO;
	}
	if (verificationError)
		CFRelease(verificationError);
	return YES;
}
