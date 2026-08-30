//
//  BTPluginP256.h
//  Battman
//
//  One canonical implementation for package and trust-metadata P-256 keys and
//  signatures.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *BTPluginP256KeyIdentifier(NSData *publicKeyData);
FOUNDATION_EXPORT BOOL BTPluginP256PublicKeyMatchesIdentifier(NSData *publicKeyData,
	NSString *keyIdentifier);
FOUNDATION_EXPORT BOOL BTPluginP256SignatureIsCanonicalDER(NSData *signatureData);
FOUNDATION_EXPORT BOOL BTPluginP256VerifyMessage(NSData *messageData,
	NSData *signatureData,
	NSData *publicKeyData,
	NSString *relativePath,
	NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
