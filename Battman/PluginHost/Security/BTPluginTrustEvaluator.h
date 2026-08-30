//
//  BTPluginTrustEvaluator.h
//  Battman
//
//  Offline trust classification after structural and publisher-signature
//  verification. Requires-approval is a safe state, not a verifier failure.
//

#import <Foundation/Foundation.h>

#import "BTPluginSignatureVerifier.h"
#import "BTPluginTrustStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginTrustDisposition) {
	BTPluginTrustDispositionOfficial = 1,
	BTPluginTrustDispositionTrustedPublisher = 2,
	BTPluginTrustDispositionExactBuild = 3,
	BTPluginTrustDispositionDeveloper = 4,
	BTPluginTrustDispositionRequiresApproval = 5,
};

@interface BTPluginTrustScope : NSObject
@property (nonatomic, copy, readonly) NSSet<NSString *> *pluginIdentifiers;
@property (nonatomic, copy, readonly) NSSet<NSString *> *extensionPointIdentifiers;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPluginIdentifiers:(NSSet<NSString *> *)pluginIdentifiers
						 extensionPointIdentifiers:(NSSet<NSString *> *)extensionPointIdentifiers
													 error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginTrustPolicy : NSObject
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSData *> *officialPublicKeysByIdentifier;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BTPluginTrustScope *> *officialScopesByKeyIdentifier;
@property (nonatomic, copy, readonly) NSSet<NSString *> *revokedKeyIdentifiers;
@property (nonatomic, readonly) uint64_t metadataSequence;
@property (nonatomic, copy, readonly) NSDate *metadataUpdatedAt;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithOfficialPublicKeysByIdentifier:(NSDictionary<NSString *, NSData *> *)officialPublicKeysByIdentifier
										 officialScopesByKeyIdentifier:(NSDictionary<NSString *, BTPluginTrustScope *> *)officialScopesByKeyIdentifier
											 revokedKeyIdentifiers:(NSSet<NSString *> *)revokedKeyIdentifiers
													 metadataSequence:(uint64_t)metadataSequence
													metadataUpdatedAt:(NSDate *)metadataUpdatedAt
																 error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginTrustEvaluation : NSObject
@property (nonatomic, readonly) BTPluginTrustDisposition disposition;
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *publisherKeyIdentifier;
@property (nonatomic, copy, readonly) NSString *packageSHA256;
@property (nonatomic, copy, readonly) NSSet<NSString *> *requestedExtensionPointIdentifiers;
@property (nonatomic, strong, readonly) BTPluginSignatureVerificationResult *signatureResult;
@property (nonatomic, copy, readonly) NSDate *trustMetadataUpdatedAt;
@property (nonatomic, readonly) uint64_t trustMetadataSequence;
@property (nonatomic, readonly, getter=isApprovedForActivation) BOOL approvedForActivation;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginTrustEvaluator : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPolicy:(BTPluginTrustPolicy *)policy
							 trustStore:(id<BTPluginTrustStore>)trustStore NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginTrustEvaluation *)evaluateInspection:(BTPluginPackageInspection *)inspection
													 developerMode:(BOOL)developerMode
																 error:(NSError * _Nullable * _Nullable)error;

// Call only after a package classified as approved actually reaches its
// activation commit. Verification and user approval alone do not advance the
// monotonic release state.
- (BOOL)recordActivatedInspection:(BTPluginPackageInspection *)inspection
							 evaluation:(BTPluginTrustEvaluation *)evaluation
									 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
