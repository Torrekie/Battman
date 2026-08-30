//
//  BTPluginRuntimeLoaderInternal.h
//  Battman
//
//  Host-internal dependency seam for testing the complete verifier-gated
//  runtime composition without mapping an iOS image into a macOS test process.
//  This is not part of PluginSDK or the public native plug-in ABI.
//

#import "BTPluginRuntimeLoader.h"

@class BTPluginNativeImageLoader;

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginRuntimeLoader (BTPluginRuntimeLoaderInternal)

- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
								 registry:(BTPluginRegistry *)registry
						 activationStore:(id<BTPluginActivationStore>)activationStore
							 environment:(BTPluginRuntimeEnvironment *)environment
			 nativeImageLoaderForTesting:(BTPluginNativeImageLoader *)nativeImageLoader;

@end

NS_ASSUME_NONNULL_END
