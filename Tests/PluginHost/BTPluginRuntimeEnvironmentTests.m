#import <Foundation/Foundation.h>

#import "../../Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static NSArray<NSURL *> *BTTestApplicationRoots;

// Exercise the production factory against real symlinks without modifying
// either system installation root on the test host.
@interface BTPluginTestRuntimeEnvironment : BTPluginRuntimeEnvironment
@end

@implementation BTPluginTestRuntimeEnvironment
+ (NSArray<NSURL *> *)bt_supportedJailbrokenApplicationRootURLs {
	return BTTestApplicationRoots;
}
@end

static void BTTestFactoryPaths(void) {
	NSFileManager *manager = NSFileManager.defaultManager;
	NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
		stringByAppendingPathComponent:[@"battman-runtime-environment-" stringByAppendingString:NSUUID.UUID.UUIDString]]
		isDirectory:YES];
	NSError *error = nil;
	NSURL *rootedRoot = [temporaryURL URLByAppendingPathComponent:@"Applications" isDirectory:YES];
	NSURL *rootedApp = [rootedRoot URLByAppendingPathComponent:@"Battman.app" isDirectory:YES];
	NSURL *physicalRoot = [temporaryURL URLByAppendingPathComponent:@"private/preboot/UUID/jb" isDirectory:YES];
	NSURL *physicalApp = [physicalRoot URLByAppendingPathComponent:@"Applications/Battman.app" isDirectory:YES];
	NSURL *rootlessAlias = [temporaryURL URLByAppendingPathComponent:@"var/jb" isDirectory:YES];
	NSURL *containerApp = [temporaryURL URLByAppendingPathComponent:@"var/containers/Bundle/Application/UUID/Battman.app"
		isDirectory:YES];
	NSURL *prefixSibling = [temporaryURL URLByAppendingPathComponent:@"Applications-other/Battman.app" isDirectory:YES];
	for (NSURL *directory in @[ rootedApp, physicalApp, rootlessAlias.URLByDeletingLastPathComponent,
		containerApp, prefixSibling ])
		BTAssert([manager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error],
			error.localizedDescription.UTF8String);
	BTAssert([manager createSymbolicLinkAtURL:rootlessAlias withDestinationURL:physicalRoot error:&error],
		error.localizedDescription.UTF8String);
	NSURL *rootlessRoot = [rootlessAlias URLByAppendingPathComponent:@"Applications" isDirectory:YES];
	NSURL *rootlessApp = [rootlessRoot URLByAppendingPathComponent:@"Battman.app" isDirectory:YES];
	BTTestApplicationRoots = @[ rootedRoot, rootlessRoot ];
	for (NSURL *bundle in @[ rootedApp, rootlessApp, physicalApp ]) {
		BTPluginRuntimeEnvironment *environment = [BTPluginTestRuntimeEnvironment
			currentEnvironmentForApplicationBundleURL:bundle];
		BTAssert(environment.installationKind == BTPluginRuntimeInstallationKindJailbrokenDirect &&
			environment.allowsApplicationDataNativeLoading && !environment.importedNativeCodeRequiresReplacementApp,
			"factory rejected a supported rooted/rootless app or its resolved alias");
	}
	NSURL *escapedApp = [rootedRoot URLByAppendingPathComponent:@"Escaped.app" isDirectory:YES];
	BTAssert([manager createSymbolicLinkAtURL:escapedApp withDestinationURL:containerApp error:&error],
		error.localizedDescription.UTF8String);
	for (NSURL *bundle in @[ containerApp, prefixSibling, escapedApp, rootedRoot ]) {
		BTPluginRuntimeEnvironment *environment = [BTPluginTestRuntimeEnvironment
			currentEnvironmentForApplicationBundleURL:bundle];
		BTAssert(environment.installationKind == BTPluginRuntimeInstallationKindTrollStoreReplacement &&
			!environment.allowsApplicationDataNativeLoading && environment.importedNativeCodeRequiresReplacementApp,
			"factory inferred direct loading from another install, a path prefix, or an escaping symlink");
	}
	BTTestApplicationRoots = nil;
	BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
}

int main(void) {
	@autoreleasepool {
		BTTestFactoryPaths();
		BTPluginRuntimeEnvironment *rooted = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:@"/Applications/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindJailbrokenDirect];
		BTPluginRuntimeEnvironment *rootless = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:@"/var/jb/Applications/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindJailbrokenDirect];
		BTPluginRuntimeEnvironment *trollStore = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:
				@"/var/containers/Bundle/Application/UUID/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindTrollStoreReplacement];
		BTAssert(rooted.allowsApplicationDataNativeLoading && rootless.allowsApplicationDataNativeLoading,
			"jailbroken app roots should permit verifier-gated app-data loading");
		BTAssert(!trollStore.allowsApplicationDataNativeLoading &&
			trollStore.importedNativeCodeRequiresReplacementApp,
			"container/TrollStore policy must require replacement-app activation");
		puts("Rooted/rootless direct-load and TrollStore replacement policy tests passed.");
	}
	return 0;
}
