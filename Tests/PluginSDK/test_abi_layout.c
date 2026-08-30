#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "../../PluginSDK/include/BattmanPluginABI.h"

#if defined(__cplusplus)
#define BT_TEST_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define BT_TEST_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

BT_TEST_STATIC_ASSERT(offsetof(BTPluginErrorV1, structSize) == 0, "error structSize must be first");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginErrorV1, abiVersion) == 4, "error abiVersion must be second");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginExtensionRegistrationV1, structSize) == 0, "registration structSize must be first");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginExtensionRegistrationV1, abiVersion) == 4, "registration abiVersion must be second");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginHostV1, structSize) == 0, "host structSize must be first");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginHostV1, abiVersion) == 4, "host abiVersion must be second");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginDescriptorV1, structSize) == 0, "descriptor structSize must be first");
BT_TEST_STATIC_ASSERT(offsetof(BTPluginDescriptorV1, abiVersion) == 4, "descriptor abiVersion must be second");
BT_TEST_STATIC_ASSERT(BT_PLUGIN_ERROR_V1_MINIMUM_SIZE == 24, "unexpected error prefix size");
BT_TEST_STATIC_ASSERT(BT_PLUGIN_EXTENSION_REGISTRATION_V1_MINIMUM_SIZE == 40, "unexpected registration prefix size");
BT_TEST_STATIC_ASSERT(BT_PLUGIN_HOST_V1_MINIMUM_SIZE == 24, "unexpected required host prefix size");
BT_TEST_STATIC_ASSERT(BT_PLUGIN_DESCRIPTOR_V1_MINIMUM_SIZE == 40, "unexpected descriptor prefix size");

#if UINTPTR_MAX == UINT64_MAX
BT_TEST_STATIC_ASSERT(sizeof(BTPluginErrorV1) == 24, "unexpected 64-bit error layout");
BT_TEST_STATIC_ASSERT(sizeof(BTPluginExtensionRegistrationV1) == 40, "unexpected 64-bit registration layout");
BT_TEST_STATIC_ASSERT(sizeof(BTPluginHostV1) == 32, "unexpected 64-bit host layout");
BT_TEST_STATIC_ASSERT(sizeof(BTPluginDescriptorV1) == 40, "unexpected 64-bit descriptor layout");
BT_TEST_STATIC_ASSERT(sizeof(BTPluginHostV1) >= BT_PLUGIN_HOST_V1_MINIMUM_SIZE,
	"current host table must contain its frozen v1 prefix");
#endif

static const BTPluginDescriptorV1 *fixture_entry_point(void) {
	static const BTPluginDescriptorV1 descriptor = {
		sizeof(BTPluginDescriptorV1),
		BT_PLUGIN_ABI_VERSION_1,
		"com.example.fixture",
		"1.0.0",
		BT_PLUGIN_ABI_VERSION_1,
		BT_PLUGIN_ABI_VERSION_1,
		0,
	};
	return &descriptor;
}

int main(void) {
	const BTPluginDescriptorV1 *descriptor = fixture_entry_point();
	if (!descriptor || descriptor->structSize != sizeof(*descriptor))
		return 1;
	if (strcmp(BT_PLUGIN_ENTRY_POINT_SYMBOL_V1, "BattmanPluginEntryPointV1") != 0)
		return 2;
	if (strcmp(BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1, "com.torrekie.battman.analytics.card.v1") != 0)
		return 3;
	return 0;
}
