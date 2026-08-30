#include <BattmanPluginABI.h>

#include <type_traits>

static_assert(std::is_standard_layout<BTPluginHostV1>::value, "host table must be standard-layout");

int battman_sdk_cxx_consumer() {
	return BT_PLUGIN_FORMAT_VERSION_1 == 1u ? 0 : 1;
}
