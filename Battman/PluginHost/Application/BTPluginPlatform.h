//
//  BTPluginPlatform.h
//  Battman
//
//  Process-wide application composition root for typed extension registration,
//  bounded startup discovery, verifier-gated loading, and recovery state.
//

#import <Foundation/Foundation.h>
#import "../Runtime/BTPluginSafeModeRequest.h"

@class BTPluginDiscoveryResult;
@class BTPluginImportCoordinator;
@class BTPluginManagementService;
@class BTPluginManagementSnapshot;
@class BTPluginRegistry;
@class BTPluginRuntimeLoadResult;
@class BTPluginStartupSnapshot;

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginPlatformDiagnostic : NSObject
@property (nonatomic, copy, readonly) NSString *stage;
@property (nonatomic, copy, readonly, nullable) NSString *pluginIdentifier;
@property (nonatomic, strong, readonly) NSError *error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPlatform : NSObject

@property (nonatomic, strong, readonly) BTPluginRegistry *registry;
@property (nonatomic, strong, readonly, nullable) BTPluginStartupSnapshot *startupSnapshot;
@property (nonatomic, strong, readonly, nullable) BTPluginDiscoveryResult *discoveryResult;
@property (nonatomic, copy, readonly) NSArray<BTPluginRuntimeLoadResult *> *loadedPlugins;
@property (nonatomic, copy, readonly) NSArray<BTPluginPlatformDiagnostic *> *diagnostics;
@property (nonatomic, strong, readonly, nullable) BTPluginManagementService *managementService;
@property (nonatomic, readonly, getter=isPreparedForApplicationLaunch) BOOL preparedForApplicationLaunch;

+ (instancetype)sharedPlatform;

// Call once on the main thread after battman_bootstrap creates its delegate
// classes and before UIApplicationMain. Repeated calls are idempotent.
- (BOOL)prepareForApplicationLaunchWithError:(NSError * _Nullable * _Nullable)error;

// Called by application integration after the first stable active interval.
- (BOOL)markStartupSettledWithError:(NSError * _Nullable * _Nullable)error;

// Accepts document-open URLs for non-executing verification and quarantine.
// A YES result means accepted for asynchronous inspection, not approved or
// activated. Completion is published by BTPluginImportCoordinator.
- (BOOL)handleOpenPackageURL:(NSURL *)packageURL;
- (nullable BTPluginManagementSnapshot *)currentManagementSnapshotWithError:
	(NSError * _Nullable * _Nullable)error;
- (BOOL)requestSafeModeForNextLaunchWithError:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
