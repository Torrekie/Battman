#import <Foundation/Foundation.h>

#import "../../Battman/PluginHost/Runtime/BTPluginRuntimeEnvironment.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

int main(void) {
	@autoreleasepool {
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
