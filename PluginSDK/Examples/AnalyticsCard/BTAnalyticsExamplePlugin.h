//
//  BTAnalyticsExamplePlugin.h
//  Battman Plugin SDK example
//

#include <BattmanPluginABI.h>

#ifdef __cplusplus
extern "C" {
#endif

// The embedded build uses a unique symbol so several statically linked
// plug-ins can coexist. The native build exports BattmanPluginEntryPointV1.
const BTPluginDescriptorV1 *BTAnalyticsExamplePluginDescriptor(void);

#ifdef __cplusplus
}
#endif
