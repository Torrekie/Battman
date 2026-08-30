//
//  BTPluginOfficialTrustLoader.h
//  Battman
//
//  Bounded, offline loading of the app-bundled root policy and its
//  threshold-signed official publisher metadata.
//


#import <Foundation/Foundation.h>

#import "BTPluginTrustEvaluator.h"

NS_ASSUME_NONNULL_BEGIN

@protocol BTPluginTrustMetadataStateStore <NSObject>

// No prior record is represented by sequence zero and a nil digest.
- (BOOL)readPreviousSequence:(uint64_t *)sequence
					 metadataSHA256:(NSString * _Nullable * _Nonnull)metadataSHA256
								 error:(NSError * _Nullable * _Nullable)error;

// Updates are monotonic and idempotent. A lower sequence or same-sequence
// digest conflict must fail with BTPluginPackageErrorRollback.
- (BOOL)recordSequence:(uint64_t)sequence
			 metadataSHA256:(NSString *)metadataSHA256
						 error:(NSError * _Nullable * _Nullable)error;

@end

@interface BTPluginKeychainTrustMetadataStateStore : NSObject <BTPluginTrustMetadataStateStore>
- (instancetype)init;
- (instancetype)initWithServiceName:(NSString *)serviceName NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginOfficialTrustLoadResult : NSObject
@property (nonatomic, strong, readonly) BTPluginTrustPolicy *trustPolicy;
@property (nonatomic, readonly, getter=isSignedMetadataLoaded) BOOL signedMetadataLoaded;
@property (nonatomic, copy, readonly, nullable) NSString *metadataSHA256;
@property (nonatomic, copy, readonly) NSSet<NSString *> *verifiedRootKeyIdentifiers;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginOfficialTrustLoader : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStateStore:(id<BTPluginTrustMetadataStateStore>)stateStore
	NS_DESIGNATED_INITIALIZER;

// PluginTrust is optional for engineering builds. If it is absent, the result
// contains an empty official policy and signedMetadataLoaded is NO. If it is
// present, every resource, signature, and rollback-state update must verify or
// this method returns nil.
- (nullable BTPluginOfficialTrustLoadResult *)loadFromApplicationBundleURL:(NSURL *)applicationBundleURL
																 error:(NSError * _Nullable * _Nullable)error;

+ (BTPluginTrustPolicy *)emptyTrustPolicy;

@end

NS_ASSUME_NONNULL_END
