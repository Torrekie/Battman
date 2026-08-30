//
//  BTPluginApplicationIntegration.h
//  Battman
//
//  File-open integration for Battman's runtime-created UIKit delegates.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Call after battman_bootstrap() registers the delegate classes and before
// UIApplicationMain(). Existing delegate behavior is preserved.
FOUNDATION_EXPORT BOOL BTPluginInstallApplicationIntegration(
	NSString *applicationDelegateClassName,
	NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
