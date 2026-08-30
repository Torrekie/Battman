//
//  BTChargeGaugePlugin.h
//  Battman official Charge Gauge plug-in
//

#include <BattmanPluginABI.h>

#ifdef __cplusplus
extern "C" {
#endif

// The embedded form exists for parity testing. Production 1.1.0 ships this
// source only as a separately signed native bundle.
const BTPluginDescriptorV1 *BTChargeGaugePluginDescriptor(void);

#ifdef __cplusplus
}
#endif
