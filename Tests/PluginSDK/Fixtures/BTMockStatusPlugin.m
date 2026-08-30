#import <Foundation/Foundation.h>
#include <BattmanPluginABI.h>
#import <BTMockStatusExtension.h>

@interface BTMockStatusProviderFixture : NSObject <BTMockStatusProvider>
@end

@implementation BTMockStatusProviderFixture
- (NSString *)mockStatusIdentifier { return @"com.example.battman.mock-status.fixture"; }
- (NSDictionary<NSString *,NSString *> *)currentMockStatus {
	return @{ @"state": @"ready", @"source": @"native-test-bundle" };
}
@end

static BTPluginResultV1 BTMockStatusRegister(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	if (!host || host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		host->structSize < BT_PLUGIN_HOST_V1_MINIMUM_SIZE ||
		!host->registerExtension)
		return BTPluginResultV1IncompatibleABI;
	BTMockStatusProviderFixture *provider = [BTMockStatusProviderFixture new];
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BT_PLUGIN_EXTENSION_POINT_MOCK_STATUS_V1,
		.extensionPointVersion = BTMockStatusExtensionPointVersion,
		.flags = 0,
		.extensionIdentifier = "com.example.battman.mock-status.fixture",
		.extensionObject = (__bridge const void *)provider,
	};
	return host->registerExtension(host->context, &registration, error);
}

BT_PLUGIN_EXPORT const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	static const BTPluginDescriptorV1 descriptor = {
		sizeof(BTPluginDescriptorV1), BT_PLUGIN_ABI_VERSION_1,
		"com.example.battman.mock-status", "1",
		BT_PLUGIN_ABI_VERSION_1, BT_PLUGIN_ABI_VERSION_1, BTMockStatusRegister,
	};
	return &descriptor;
}
