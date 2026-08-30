//
//  BTPluginDiscovery.h
//  Battman
//
//  Deterministic, non-recursive discovery from explicit roots. Discovery is
//  inventory only: it never verifies trust, changes activation state, or loads.
//

#import <Foundation/Foundation.h>

#import "../Model/BTPluginSource.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginInstalledRepresentation) {
	BTPluginInstalledRepresentationTransportPackage = 1,
	BTPluginInstalledRepresentationSealedAppBundle = 2,
};

@interface BTPluginDiscoveryRoot : NSObject
@property (nonatomic, strong, readonly) NSURL *rootURL;
@property (nonatomic, strong, readonly, nullable) NSURL *metadataRootURL;
@property (nonatomic, readonly) BTPluginSource source;
@property (nonatomic, readonly) BTPluginInstalledRepresentation representation;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)transportPackageRootURL:(NSURL *)rootURL source:(BTPluginSource)source;
+ (instancetype)sealedAppBundleRootURL:(NSURL *)rootURL metadataRootURL:(NSURL *)metadataRootURL;
@end

@interface BTPluginDiscoveredPackage : NSObject
@property (nonatomic, copy, readonly) NSString *claimedPluginIdentifier;
@property (nonatomic, strong, readonly) NSURL *packageURL;
@property (nonatomic, strong, readonly, nullable) NSURL *payloadURL;
@property (nonatomic, strong, readonly, nullable) NSURL *metadataURL;
@property (nonatomic, readonly) BTPluginSource source;
@property (nonatomic, readonly) BTPluginInstalledRepresentation representation;
@property (nonatomic, copy, readonly) NSString *stableLocationKey;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginDiscoveryDiagnostic : NSObject
@property (nonatomic, strong, readonly) NSURL *url;
@property (nonatomic, readonly) BTPluginSource source;
@property (nonatomic, strong, readonly) NSError *error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginDiscoveryResult : NSObject
@property (nonatomic, copy, readonly) NSArray<BTPluginDiscoveredPackage *> *packages;
@property (nonatomic, copy, readonly) NSArray<BTPluginDiscoveryDiagnostic *> *diagnostics;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginDiscovery : NSObject

+ (NSArray<BTPluginDiscoveryRoot *> *)defaultRootsForApplicationSupportURL:(NSURL *)applicationSupportURL
																 mainBundleURL:(NSURL *)mainBundleURL;

- (BTPluginDiscoveryResult *)discoverRoots:(NSArray<BTPluginDiscoveryRoot *> *)roots;

@end

NS_ASSUME_NONNULL_END
