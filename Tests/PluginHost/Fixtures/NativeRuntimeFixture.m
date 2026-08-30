#import <Foundation/Foundation.h>

#import <fcntl.h>
#import <unistd.h>

#include "../../../PluginSDK/include/BattmanPluginABI.h"

static const char * const BTFixtureExtensionPoint = "com.example.battman.runtime.v1";

@interface BTNativeRuntimeFixtureObject : NSObject
@property (nonatomic, copy) NSString *fixtureValue;
@end

@implementation BTNativeRuntimeFixtureObject
@end

__attribute__((constructor)) static void BTNativeRuntimeFixtureConstructor(void) {
	const char *path = getenv("BT_PLUGIN_RUNTIME_CONSTRUCTOR_SENTINEL");
	if (!path || path[0] == '\0')
		return;
	const char byte = '1';
	int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (descriptor >= 0) {
		(void)write(descriptor, &byte, sizeof(byte));
		(void)close(descriptor);
	}
}

static BTPluginResultV1 BTNativeRuntimeFixtureRegister(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	(void)error;
	if (!host || host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		host->structSize < offsetof(BTPluginHostV1, registerExtension) + sizeof(host->registerExtension) ||
		!host->registerExtension)
		return BTPluginResultV1IncompatibleABI;
	BTNativeRuntimeFixtureObject *object = [BTNativeRuntimeFixtureObject new];
	object.fixtureValue = @"native-runtime-fixture";
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BTFixtureExtensionPoint,
		.extensionPointVersion = 1,
		.flags = 0,
		.extensionIdentifier = "com.example.battman.runtime.fixture",
		.extensionObject = (__bridge const void *)object,
	};
	return host->registerExtension(host->context, &registration, error);
}

BT_PLUGIN_EXPORT const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	static const BTPluginDescriptorV1 descriptor = {
		.structSize = sizeof(BTPluginDescriptorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.pluginIdentifier = "com.example.battman.runtime",
		.pluginVersion = "7",
		.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.registerPlugin = BTNativeRuntimeFixtureRegister,
	};
	return &descriptor;
}
