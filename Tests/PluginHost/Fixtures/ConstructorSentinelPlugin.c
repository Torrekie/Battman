/*
 * Adversarial native fixture for the Phase 3 non-executing verifier. If any
 * inspection path maps this image, the constructor creates the path supplied
 * in BT_PLUGIN_CONSTRUCTOR_SENTINEL. Verification must leave it absent.
 */

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

#include "../../../PluginSDK/include/BattmanPluginABI.h"

__attribute__((constructor))
static void BTPluginConstructorSentinel(void) {
	const char *path = getenv("BT_PLUGIN_CONSTRUCTOR_SENTINEL");
	if (!path || !path[0])
		return;
	int descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
	if (descriptor >= 0) {
		static const char marker[] = "constructor executed\n";
		(void)write(descriptor, marker, sizeof(marker) - 1);
		(void)close(descriptor);
	}
}

static BTPluginResultV1 BTPluginFixtureRegister(const BTPluginHostV1 *host,
													 BTPluginErrorV1 *error) {
	(void)host;
	(void)error;
	return BTPluginResultV1Success;
}

static const BTPluginDescriptorV1 BTPluginFixtureDescriptor = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.battman.analytics.fixture",
	.pluginVersion = "1.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTPluginFixtureRegister,
};

BT_PLUGIN_EXPORT
const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	return &BTPluginFixtureDescriptor;
}

#if defined(BT_PLUGIN_ADVERSARIAL_EXTRA_EXPORT)
BT_PLUGIN_EXPORT
int BattmanPluginUnexpectedExport(void) {
	return 1;
}
#endif
