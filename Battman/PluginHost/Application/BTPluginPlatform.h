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

// Posted on main once every external candidate has either registered or been
// rejected. Observers may safely refresh registry-derived UI at this point.
FOUNDATION_EXPORT NSNotificationName const BTPluginPlatformDidFinishStartupNotification;

@interface BTPluginPlatformDiagnostic : NSObject
@property (nonatomic, copy, readonly) NSString *stage;
@property (nonatomic, copy, readonly, nullable) NSString *pluginIdentifier;
@property (nonatomic, strong, readonly) NSError *error;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPlatform : NSObject

@property (nonatomic, strong, readonly) BTPluginRegistry *registry;
@property (atomic, strong, readonly, nullable) BTPluginStartupSnapshot *startupSnapshot;
@property (atomic, strong, readonly, nullable) BTPluginDiscoveryResult *discoveryResult;
@property (atomic, copy, readonly) NSArray<BTPluginRuntimeLoadResult *> *loadedPlugins;
@property (atomic, copy, readonly) NSArray<BTPluginPlatformDiagnostic *> *diagnostics;
@property (atomic, strong, readonly, nullable) BTPluginManagementService *managementService;
@property (atomic, readonly, getter=isPreparedForApplicationLaunch) BOOL preparedForApplicationLaunch;
@property (atomic, readonly, getter=isExternalStartupComplete) BOOL externalStartupComplete;

+ (instancetype)sharedPlatform;

// Call once on the main thread after battman_bootstrap creates its delegate
// classes and before UIApplicationMain. Built-in descriptors are immediately
// available; external verification runs asynchronously, with main-thread
// activation. YES means scheduled, not finished. Repeated calls are idempotent.
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
