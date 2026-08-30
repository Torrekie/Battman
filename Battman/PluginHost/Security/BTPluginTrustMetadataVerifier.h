//
//  BTPluginTrustMetadataVerifier.h
//  Battman
//
//  Threshold verification for offline official-key delegation and revocation
//  metadata. Root private keys are never part of this API or repository.
//

#import <Foundation/Foundation.h>

#import "BTPluginTrustEvaluator.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginRootTrustPolicy : NSObject
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSData *> *rootPublicKeysByIdentifier;
@property (nonatomic, readonly) NSUInteger signatureThreshold;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithRootPublicKeysByIdentifier:(NSDictionary<NSString *, NSData *> *)rootPublicKeysByIdentifier
												 signatureThreshold:(NSUInteger)signatureThreshold
																error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginVerifiedTrustMetadata : NSObject
@property (nonatomic, strong, readonly) BTPluginTrustPolicy *trustPolicy;
@property (nonatomic, copy, readonly) NSData *metadataData;
@property (nonatomic, copy, readonly) NSString *metadataSHA256;
@property (nonatomic, copy, readonly) NSSet<NSString *> *verifiedRootKeyIdentifiers;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginTrustMetadataVerifier : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithRootPolicy:(BTPluginRootTrustPolicy *)rootPolicy NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginVerifiedTrustMetadata *)verifyMetadataData:(NSData *)metadataData
									 signaturesByRootKeyIdentifier:(NSDictionary<NSString *, NSData *> *)signaturesByRootKeyIdentifier
												 previousSequence:(uint64_t)previousSequence
									 previousMetadataSHA256:(nullable NSString *)previousMetadataSHA256
														 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
