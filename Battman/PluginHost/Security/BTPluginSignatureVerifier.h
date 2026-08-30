//
//  BTPluginSignatureVerifier.h
//  Battman
//
//  Offline publisher-signature verification over the exact Manifest.json
//  bytes. Platform code signatures are a separate validation.
//

#import <Foundation/Foundation.h>

#import "BTPluginPackageStructuralVerifier.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginSignatureVerificationResult : NSObject
@property (nonatomic, copy, readonly) NSSet<NSString *> *verifiedKeyIdentifiers;
@property (nonatomic, copy, readonly) NSSet<NSString *> *externallyProvidedKeyIdentifiers;
@property (nonatomic, copy, readonly) NSSet<NSString *> *packageProvidedKeyIdentifiers;
@property (nonatomic, readonly) BOOL primaryKeyUsedExternalTrustMaterial;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginSignatureVerifier : NSObject

- (nullable BTPluginSignatureVerificationResult *)verifyInspection:(BTPluginPackageInspection *)inspection
									  publicKeysByIdentifier:(NSDictionary<NSString *, NSData *> *)publicKeysByIdentifier
														 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
