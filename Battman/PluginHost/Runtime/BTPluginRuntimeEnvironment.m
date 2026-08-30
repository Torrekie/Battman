//
//  BTPluginRuntimeEnvironment.m
//  Battman
//

#import "BTPluginRuntimeEnvironment.h"

#import <TargetConditionals.h>

@implementation BTPluginRuntimeEnvironment

- (instancetype)initWithApplicationBundleURL:(NSURL *)applicationBundleURL
								 installationKind:(BTPluginRuntimeInstallationKind)installationKind {
	self = [super init];
	if (!self)
		return nil;
	_applicationBundleURL = [applicationBundleURL copy];
	_installationKind = installationKind;
	return self;
}

+ (instancetype)currentEnvironmentForApplicationBundleURL:(NSURL *)applicationBundleURL {
	BTPluginRuntimeInstallationKind kind = BTPluginRuntimeInstallationKindTrollStoreReplacement;
#if TARGET_OS_SIMULATOR
	kind = BTPluginRuntimeInstallationKindSimulatorDevelopment;
#else
	NSString *path = applicationBundleURL.URLByStandardizingPath.path;
	if ([path hasPrefix:@"/Applications/"] || [path hasPrefix:@"/var/jb/Applications/"])
		kind = BTPluginRuntimeInstallationKindJailbrokenDirect;
#endif
	return [[self alloc] initWithApplicationBundleURL:applicationBundleURL installationKind:kind];
}

- (BOOL)allowsApplicationDataNativeLoading {
	return self.installationKind == BTPluginRuntimeInstallationKindJailbrokenDirect ||
		self.installationKind == BTPluginRuntimeInstallationKindSimulatorDevelopment;
}

- (BOOL)importedNativeCodeRequiresReplacementApp {
	return !self.allowsApplicationDataNativeLoading;
}

@end
