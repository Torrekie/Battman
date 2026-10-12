//
//  BTPluginRuntimeLoader.h
//  Battman
//
//  Complete-verification-gated native activation. Import, discovery, approval,
//  and management code must not call a native image loader directly.
//

#import <Foundation/Foundation.h>

#import "../Discovery/BTPluginDiscovery.h"
#import "../Security/BTPluginPackageVerifier.h"
#import "BTPluginActivationStore.h"
#import "BTPluginRuntimeEnvironment.h"

@class BTPluginRegistry;

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginRuntimeLoadResult : NSObject
@property (nonatomic, strong, readonly) BTPluginDiscoveredPackage *discoveredPackage;
@property (nonatomic, strong, readonly) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, readonly, getter=isThirdParty) BOOL thirdParty;
- (instancetype)init NS_UNAVAILABLE;
@end

// Opaque, single-use capability for an entirely verified, privately pinned
// package. Only the loader that prepared it may activate it.
@interface BTPluginPreparedActivation : NSObject
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginRuntimeLoader : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
								 registry:(BTPluginRegistry *)registry
					 activationStore:(id<BTPluginActivationStore>)activationStore
							environment:(BTPluginRuntimeEnvironment *)environment NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginRuntimeLoadResult *)loadDiscoveredPackage:(BTPluginDiscoveredPackage *)discoveredPackage
											  activationRecord:(nullable BTPluginActivationRecord *)activationRecord
											 startupSnapshot:(BTPluginStartupSnapshot *)startupSnapshot
												 developerMode:(BOOL)developerMode
														 error:(NSError * _Nullable * _Nullable)error;

// Run preparation on the serial startup worker, then immediately activate on
// main before preparing the next package. Preparation performs all file I/O,
// verification, pinning and durable trust/recovery writes; it executes no
// package code. Never settle startup while a prepared activation is pending.
- (nullable BTPluginPreparedActivation *)prepareDiscoveredPackage:(BTPluginDiscoveredPackage *)discoveredPackage
	activationRecord:(nullable BTPluginActivationRecord *)activationRecord
	startupSnapshot:(BTPluginStartupSnapshot *)startupSnapshot
	developerMode:(BOOL)developerMode error:(NSError * _Nullable * _Nullable)error;
- (nullable BTPluginRuntimeLoadResult *)activatePreparedPackage:(BTPluginPreparedActivation *)prepared
	error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
