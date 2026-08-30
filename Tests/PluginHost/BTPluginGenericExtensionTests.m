#import <Foundation/Foundation.h>
#include "../../PluginSDK/include/BattmanPluginABI.h"
#import "../../PluginSDK/TestSupport/include/BTMockStatusExtension.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/Runtime/BTPluginNativeImageLoaderPrivate.h"

#define BTAssert(condition, message) do { if (!(condition)) { \
	fprintf(stderr, "Assertion failed: %s\n", (message)); exit(1); } } while (0)

@interface BTEmbeddedMockStatusProvider : NSObject <BTMockStatusProvider>
@end
@implementation BTEmbeddedMockStatusProvider
- (NSString *)mockStatusIdentifier { return @"com.example.battman.future.fixture"; }
- (NSDictionary<NSString *,NSString *> *)currentMockStatus { return @{ @"state": @"future" }; }
@end

static BTPluginResultV1 BTRegisterMockAtPointAndVersion(const BTPluginHostV1 *host,
	const char *point, uint32_t version, BTPluginErrorV1 *error) {
	BTEmbeddedMockStatusProvider *provider = [BTEmbeddedMockStatusProvider new];
	BTPluginExtensionRegistrationV1 registration = {
		sizeof(BTPluginExtensionRegistrationV1), BT_PLUGIN_ABI_VERSION_1,
		point, version, 0, "com.example.battman.future.fixture",
		(__bridge const void *)provider,
	};
	return host->registerExtension(host->context, &registration, error);
}

static BTPluginResultV1 BTRegisterFutureVersion(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	return BTRegisterMockAtPointAndVersion(host, BT_PLUGIN_EXTENSION_POINT_MOCK_STATUS_V1, 2, error);
}
static BTPluginResultV1 BTRegisterUnknownPoint(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	return BTRegisterMockAtPointAndVersion(host,
		"com.torrekie.battman.tests.status-provider.v2", 1, error);
}

static const BTPluginDescriptorV1 BTFutureVersionPlugin = {
	sizeof(BTPluginDescriptorV1), BT_PLUGIN_ABI_VERSION_1,
	"com.example.battman.future", "1",
	BT_PLUGIN_ABI_VERSION_1, BT_PLUGIN_ABI_VERSION_1, BTRegisterFutureVersion,
};
static const BTPluginDescriptorV1 BTUnknownPointPlugin = {
	sizeof(BTPluginDescriptorV1), BT_PLUGIN_ABI_VERSION_1,
	"com.example.battman.unknown-point", "1",
	BT_PLUGIN_ABI_VERSION_1, BT_PLUGIN_ABI_VERSION_1, BTRegisterUnknownPoint,
};

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTAssert(argc == 3, "expected current and frozen-v1 mock-status bundle paths");
		BTPluginRegistry *registry = [BTPluginRegistry new];
		NSError *error = nil;
		BTAssert([registry registerExtensionPointIdentifier:BTMockStatusExtensionPointIdentifier
			interfaceVersion:BTMockStatusExtensionPointVersion
			requiredProtocol:@protocol(BTMockStatusProvider) error:&error],
			error.localizedDescription.UTF8String);
		NSSet *declared = [NSSet setWithObject:BTMockStatusExtensionPointIdentifier];
		BTPluginNativeImageLoader *loader = [BTPluginNativeImageLoader new];
		BTAssert([loader loadImageAtURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
			expectedPluginIdentifier:@"com.example.battman.mock-status"
			expectedPluginVersion:@"1" declaredExtensionPoints:declared registry:registry error:&error],
			error.localizedDescription.UTF8String);
		NSArray *providers = [registry extensionObjectsForExtensionPointIdentifier:BTMockStatusExtensionPointIdentifier];
		BTAssert(providers.count == 1, "native non-Analytics provider count changed");
		id<BTMockStatusProvider> provider = providers.firstObject;
		BTAssert([provider.mockStatusIdentifier isEqualToString:@"com.example.battman.mock-status.fixture"],
			"mock provider identity changed");
		NSDictionary *expectedStatus = @{ @"state": @"ready",
			@"source": @"native-test-bundle" };
		BTAssert([[provider currentMockStatus] isEqual:expectedStatus],
			"mock provider behavior changed");

		error = nil;
		BTAssert([loader loadImageAtURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]
			expectedPluginIdentifier:@"com.example.battman.older-v1"
			expectedPluginVersion:@"1" declaredExtensionPoints:declared registry:registry error:&error],
			error.localizedDescription.UTF8String);
		providers = [registry extensionObjectsForExtensionPointIdentifier:BTMockStatusExtensionPointIdentifier];
		BTAssert(providers.count == 2, "frozen older-v1 native provider was not committed");
		id<BTMockStatusProvider> olderProvider = providers.lastObject;
		BTAssert([olderProvider.mockStatusIdentifier isEqualToString:@"com.example.battman.older-v1.fixture"],
			"frozen older-v1 provider identity changed");
		BTAssert([[[olderProvider currentMockStatus] objectForKey:@"source"] isEqualToString:@"frozen-abi-v1"],
			"frozen older-v1 provider did not execute through the current host table");

		error = nil;
		BTAssert(!BTRegisterEmbeddedPluginDescriptor(&BTFutureVersionPlugin, registry, declared, &error) &&
			error.code == BTPluginRegistryErrorIncompatibleExtensionPointVersion,
			"future interface version was not rejected cleanly");
		BTAssert([registry extensionObjectsForExtensionPointIdentifier:BTMockStatusExtensionPointIdentifier].count == 2,
			"future-version rejection committed partial state");
		error = nil;
		BTAssert(!BTRegisterEmbeddedPluginDescriptor(&BTUnknownPointPlugin, registry,
			[NSSet setWithObject:@"com.torrekie.battman.tests.status-provider.v2"], &error) &&
			error.code == BTPluginRegistryErrorUnknownExtensionPoint,
			"unknown future extension point was not rejected cleanly");
		puts("Generic non-Analytics, frozen ABI-v1, and future-version rejection tests passed.");
	}
	return 0;
}
