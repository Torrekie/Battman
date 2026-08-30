#include <BattmanPluginABI.h>

_Static_assert(BT_PLUGIN_ABI_VERSION_1 == 1u, "ABI version drifted");
_Static_assert(sizeof(BTPluginDescriptorV1) >= 32u, "descriptor unexpectedly shrank");

int battman_sdk_c_consumer(void) {
	return BT_PLUGIN_ENTRY_POINT_SYMBOL_V1[0] == 'B' ? 0 : 1;
}
