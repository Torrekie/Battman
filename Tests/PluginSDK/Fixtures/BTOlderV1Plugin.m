#import <Foundation/Foundation.h>
#include <BattmanPluginABI.h>
#import <BTMockStatusExtension.h>

/* Compiled only against TestSupport/ABI/v1-initial, never the live ABI header. */
_Static_assert(sizeof(BTPluginHostV1) == 24, "initial LP64 host table changed");

@interface BTOlderV1StatusProviderFixture : NSObject <BTMockStatusProvider>
@end

@implementation BTOlderV1StatusProviderFixture
- (NSString *)mockStatusIdentifier { return @"com.example.battman.older-v1.fixture"; }
- (NSDictionary<NSString *,NSString *> *)currentMockStatus {
	return @{ @"state": @"ready", @"source": @"frozen-abi-v1" };
}
@end


static BTPluginResultV1 BTOlderV1Register(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	if (!host || host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		host->structSize < BT_PLUGIN_HOST_V1_MINIMUM_SIZE || !host->registerExtension)
		return BTPluginResultV1IncompatibleABI;
	BTOlderV1StatusProviderFixture *provider = [BTOlderV1StatusProviderFixture new];
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BT_PLUGIN_EXTENSION_POINT_MOCK_STATUS_V1,
		.extensionPointVersion = BTMockStatusExtensionPointVersion,
		.flags = 0,
		.extensionIdentifier = "com.example.battman.older-v1.fixture",
		.extensionObject = (__bridge const void *)provider,
	};
	return host->registerExtension(host->context, &registration, error);
}

BT_PLUGIN_EXPORT const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	static const BTPluginDescriptorV1 descriptor = {
		sizeof(BTPluginDescriptorV1), BT_PLUGIN_ABI_VERSION_1,
		"com.example.battman.older-v1", "1",
		BT_PLUGIN_ABI_VERSION_1, BT_PLUGIN_ABI_VERSION_1, BTOlderV1Register,
	};
	return &descriptor;
}
