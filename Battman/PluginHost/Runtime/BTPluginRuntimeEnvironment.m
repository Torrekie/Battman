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

+ (NSArray<NSURL *> *)bt_supportedJailbrokenApplicationRootURLs {
	return @[
		[NSURL fileURLWithPath:@"/Applications" isDirectory:YES],
		[NSURL fileURLWithPath:@"/var/jb/Applications" isDirectory:YES],
	];
}

+ (instancetype)currentEnvironmentForApplicationBundleURL:(NSURL *)applicationBundleURL {
	BTPluginRuntimeInstallationKind kind = BTPluginRuntimeInstallationKindTrollStoreReplacement;
#if TARGET_OS_SIMULATOR
	kind = BTPluginRuntimeInstallationKindSimulatorDevelopment;
#else
	// NSBundle may return the physical preboot path behind /var/jb. Resolve
	// both sides instead of depending on the spelling of the current app URL.
	// Another installation's presence never changes this app's policy.
	if (applicationBundleURL.isFileURL) {
		NSString *path = applicationBundleURL.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
		for (NSURL *rootURL in [self bt_supportedJailbrokenApplicationRootURLs]) {
			NSString *rootPath = rootURL.URLByResolvingSymlinksInPath.URLByStandardizingPath.path;
			if ([path hasPrefix:[rootPath stringByAppendingString:@"/"]]) {
				kind = BTPluginRuntimeInstallationKindJailbrokenDirect;
				break;
			}
		}
	}
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
