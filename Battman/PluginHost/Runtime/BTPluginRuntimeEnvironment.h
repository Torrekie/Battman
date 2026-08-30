//
//  BTPluginRuntimeEnvironment.h
//  Battman
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginRuntimeInstallationKind) {
	BTPluginRuntimeInstallationKindJailbrokenDirect = 1,
	BTPluginRuntimeInstallationKindTrollStoreReplacement = 2,
	BTPluginRuntimeInstallationKindSimulatorDevelopment = 3,
};

@interface BTPluginRuntimeEnvironment : NSObject
@property (nonatomic, readonly) BTPluginRuntimeInstallationKind installationKind;
@property (nonatomic, readonly) BOOL allowsApplicationDataNativeLoading;
@property (nonatomic, readonly) BOOL importedNativeCodeRequiresReplacementApp;
@property (nonatomic, strong, readonly) NSURL *applicationBundleURL;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithApplicationBundleURL:(NSURL *)applicationBundleURL
								  installationKind:(BTPluginRuntimeInstallationKind)installationKind NS_DESIGNATED_INITIALIZER;
+ (instancetype)currentEnvironmentForApplicationBundleURL:(NSURL *)applicationBundleURL;
@end

NS_ASSUME_NONNULL_END
