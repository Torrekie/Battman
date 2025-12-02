#include "battery_info.h"
#include "iokit_connection.h"
#include "../common.h"
#include "accessory.h"
#include "libsmc.h"
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFBase.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>

#include "../UPSMonitor.h"

#ifdef _C
#undef _C
#endif
// Stub _C definition for gettext, locales are caller processed
#define _C(x) x
const char *bin_unit_strings[] = {
	_C("℃"), _C("%"), _C("mA"), _C("mAh"), _C("mV"), _C("mW"), _C("min"),
	_C("Hr") // Do not modify, thats how Texas Instruments documented
};

struct battery_info_node main_battery_template[] = {
	{ _C("Gas Gauge (Basic)"), _C("All Gas Gauge metrics are dynamically retrieved from the onboard sensor array in real time. Should anomalies be detected in specific readings, this may indicate the presence of unauthorized components or require diagnostics through Apple Authorised Service Provider."), DEFINE_SECTION(10000) },
	{ _C("Device Name"), _C("This indicates the name of the current Gas Gauge IC used by the installed battery."), 0 },
	{ _C("Health"), NULL, BIN_IS_BACKGROUND | BIN_UNIT_PERCENT },
	{ _C("SoC"), NULL, BIN_IS_FLOAT | BIN_UNIT_PERCENT },
	{ _C("Avg. Temperature"), NULL, BIN_IS_FLOAT | BIN_UNIT_DEGREE_C | BIN_DETAILS_SHARED },
	{ _C("Charging"), NULL, BIN_IS_BOOLEAN },
	{ "ASoC(Hidden)", NULL, BIN_IS_FOREGROUND | BIN_IS_HIDDEN },
	{ _C("Full Charge Capacity"), NULL, BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("Designed Capacity"), NULL, BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("Remaining Capacity"), NULL, BIN_UNIT_MAH | BIN_IN_DETAILS },
	/* FIXME: bmsUptime uses at least 4 bytes (8 bytes in total), current structure only allow 2 */
	{ _C("Battery Uptime"), _C("The length of time the Battery Management System (BMS) has been up."), /* BIN_UNIT_MIN | BIN_IN_DETAILS */ 0 },
	{ _C("Qmax"), NULL, BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("Depth of Discharge"), _C("Current chemical depth of discharge (DOD₀). The gas gauge updates information on the DOD₀ based on open-circuit voltage (OCV) readings when in a relaxed state."), BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("Passed Charge"), _C("The cumulative capacity of the current charging or discharging cycle. It is reset to zero with each DOD₀ update."), BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("Voltage"), NULL, BIN_UNIT_MVOLT | BIN_IN_DETAILS },
	{ _C("Avg. Current"), NULL, BIN_UNIT_MAMP | BIN_IN_DETAILS },
	{ _C("Avg. Power"), NULL, BIN_UNIT_MWATT | BIN_IN_DETAILS },
	{ _C("Cell Count"), NULL, BIN_IN_DETAILS },
	/* TODO: TimeToFull */
	{ _C("Time to Empty"), NULL, BIN_UNIT_MIN | BIN_IN_DETAILS },
	{ _C("Cycle Count"), NULL, BIN_IN_DETAILS },
	{ _C("Designed Cycle Count"), NULL, BIN_IN_DETAILS },
	{ _C("State of Charge"), NULL, BIN_UNIT_PERCENT | BIN_IN_DETAILS },
	{ _C("State of Charge (UI)"), _C("The \"Battery Percentage\" displayed exactly on your status bar. This is the SoC that Apple wants to tell you."), BIN_UNIT_PERCENT | BIN_IN_DETAILS },
	{ _C("Resistance Scale"), NULL, BIN_IN_DETAILS },
	{ _C("Battery Serial No."), NULL, 0 },
	{ _C("Chemistry ID"), _C("Chemistry unique identifier (ChemID) assigned to each battery in Texas Instruments' database. It ensures accurate calculations and predictions."), 0 },
	{ _C("Flags"), NULL, 0 },
	{ _C("True Remaining Capacity"), NULL, BIN_UNIT_MAH | BIN_IN_DETAILS },
	{ _C("OCV Current"), NULL, BIN_UNIT_MAMP | BIN_IN_DETAILS },
	{ _C("OCV Voltage"), NULL, BIN_UNIT_MVOLT | BIN_IN_DETAILS },
	{ _C("Max Load Current"), NULL, BIN_UNIT_MAMP | BIN_IN_DETAILS },
	{ _C("Max Load Current 2"), NULL, BIN_UNIT_MAMP | BIN_IN_DETAILS },
	/* TODO: Parse ITMiscStatus
	 * Known components: DOD0Update, FastQmaxUpdate, ITSimulation, QmaxAtEOC, QmaxDisqualified, QmaxDOD0, QmaxUpdate, RaUpdate */
	{ _C("IT Misc Status"), _C("This field refers to the miscellaneous data returned by battery Impedance Track™ Gas Gauge IC."), 0 },
	{ _C("Simulation Rate"), _C("This field refers to the rate of Gas Gauge performing Impedance Track™ simulations."), BIN_UNIT_HOUR | BIN_IN_DETAILS },
	{ _C("Daily Max SoC"), NULL, BIN_UNIT_PERCENT | BIN_IN_DETAILS },
	{ _C("Daily Min SoC"), NULL, BIN_UNIT_PERCENT | BIN_IN_DETAILS },

	{ _C("Adapter Details"), _C("All adapter information is dynamically retrieved from the hardware of the currently connected adapter (or cable if you are using Lightning ports). If any of the data is missing, it may indicate that the power source is not providing the relevant information, or there may be a hardware issue with the power source."), DEFINE_SECTION(9000) },
	{ _C("Port"), _C("Port of currently connected adapter. On macOS, this is the USB port that the adapter currently attached."), BIN_IN_DETAILS },
	{ _C("Adapter Type"), NULL, 0 },
	{ _C("Compatibility"), NULL, 0 },
	{ _C("Type"), _C("This field refers to the Family Code (kIOPSPowerAdapterFamilyKey) of currently connected power adapter."), 0 },
	{ _C("Status"), NULL, 0 },
	{ _C("Reason"), _C("If this field appears in the list, it indicates that an issue has occurred or that a condition was met, causing charging to stop."), 0 },
	{ _C("Current Rating"), _C("Current rating of connected power source, this does not indicates the real-time passing current."), BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Voltage Rating"), _C("Voltage rating of connected power source, this does not indicates the real-time passing voltage."), BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Input Current"), _C("Real-time input current (IBUS) from the connected power source."), BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Input Voltage"), _C("Real-time input voltage (VBUS) from the connected power source."), BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Charging Current"), _C("The real-time passing current to internal battery."), BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Charging Voltage"), _C("The real-time passing voltage to internal battery."), BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Charger IC ID"), NULL, 0 },
	{ _C("Model Name"), NULL, 0 },
	{ _C("Manufacturer"), NULL, 0 },
	{ _C("Model"), NULL, 0 },
	{ _C("Firmware Version"), NULL, 0 },
	{ _C("Hardware Version"), NULL, 0 },
	{ _C("Description"), _C("Short description provided by Apple PMU on current power adapter Family Code. Sometimes may not set."), 0 },
	{ _C("Serial No."), NULL, 0 },
	{ _C("PMU Configuration"), _C("The Configuration values is the max allowed Charging Current configurations."), 0 },
	{ _C("Charger Configuration"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("HVC Mode"), _C("High Voltage Charging (HVC) Mode may accquired by your power adapter or system, all supported modes will be listed below."), BIN_IN_DETAILS },

	{ _C("Inductive Port"), NULL, DEFINE_SECTION(8500) },
	{ _C("Acc. ID"), NULL, 0 },
	{ _C("Port Type"), NULL, 0 },
	{ _C("Allowed Features"), _C("Accessory Feature Flags, I don't know how to parse it yet."), 0 },
	{ _C("Serial No."), NULL, 0 },
	{ _C("Manufacturer"), NULL, 0 },
	{ _C("Product ID"), NULL, 0 },
	{ _C("Vendor ID"), NULL, 0 },
	{ _C("Model"), NULL, 0 },
	{ _C("Name"), NULL, 0 },
	{ _C("PPID"), NULL, 0 },
	{ _C("Firmware Version"), NULL, 0 },
	{ _C("Hardware Version"), NULL, 0 },
	{ _C("Battery Pack"), _C("This indicates if an accessory is now working as a Battery Pack."), 0 },
	{ _C("Providing Power"), _C("This indicates if an accessory is now providing power."), BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Status"), 0 },
	/* Accessory UPS Start */
	{ _C("Max Capacity"), _C("The accessory battery's Full Charge Capacity."), BIN_IN_DETAILS | BIN_UNIT_MAH },
	{ _C("Current Capacity"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAH },
	{ _C("Avg. Charging Current"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Charging Voltage Rating"), NULL, BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Cell Count"), NULL, BIN_IN_DETAILS },
	{ _C("Cycle Count"), NULL, BIN_IN_DETAILS },
	{ _C("Current"), _C("Real-time output current by attached accessory."), BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Voltage"), _C("Real-time output voltage by attached accessory."), BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Incoming Current"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Incoming Voltage"), NULL, BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Accepting Charge"), _C("This indicates if accessory is accepting charge."), BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Temperature"), NULL, BIN_IN_DETAILS | BIN_UNIT_DEGREE_C },
	{ _C("Acc. Time to Empty"), NULL, BIN_IN_DETAILS | BIN_UNIT_MIN },
	{ _C("Acc. Time to Full"), NULL, BIN_IN_DETAILS | BIN_UNIT_MIN },
	/* Accessory UPS End */
	{ _C("State of Charge"), _C("The accessory battery percentage reported by AppleSMC."), 0 },
	{ _C("Accepting Charge"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Power Mode"), NULL, 0 },
	{ _C("Sleep Power"), NULL, 0 },
	{ _C("Supervised Acc. Attached"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Supervised Transports Restricted"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Inductive FW Mode"), NULL, 0 },
	{ _C("Inductive Region Code"), _C("This indicates if current inductive accesory is following specific region configuration."), 0 },
	{ _C("Inductive Auth Timeout"), 0, BIN_IN_DETAILS | BIN_IS_BOOLEAN },

	{ _C("Serial Port"), NULL, DEFINE_SECTION(8000) },
	{ _C("Acc. ID"), NULL, 0 },
	{ _C("Digital ID"), _C("The \"Chip ID\" of attached accessory."), 0 },
	{ _C("ID Serial No."), _C("Interface Device Serial Number (ID-SN)."), 0 },
	{ _C("IM Serial No."), _C("Interface Module Serial Number (MSN)."), 0 },
	{ _C("Port Type"), NULL, 0 },
	{ _C("Allowed Features"), _C("Accessory Feature Flags, I don't know how to parse it yet."), 0 },
	{ _C("Serial No."), _C("Accessory Serial Number (ASN)."), 0 },
	{ _C("Manufacturer"), NULL, 0 },
	{ _C("Product ID"), NULL, 0 },
	{ _C("Vendor ID"), NULL, 0 },
	{ _C("Model"), NULL, 0 },
	{ _C("Name"), NULL, 0 },
	{ _C("PPID"), NULL, 0 },
	{ _C("Firmware Version"), NULL, 0 },
	{ _C("Hardware Version"), NULL, 0 },
	{ _C("Battery Pack"), _C("This indicates if an accessory is now working as a Battery Pack."), 0 },
	{ _C("Providing Power"), _C("This indicates if an accessory is now providing power."), BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	/* Accessory UPS Start */
	{ _C("Max Capacity"), _C("The accessory battery's Full Charge Capacity."), BIN_IN_DETAILS | BIN_UNIT_MAH },
	{ _C("Current Capacity"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAH },
	{ _C("Charging Voltage Rating"), NULL, BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Avg. Charging Current"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Cell Count"), NULL, 0 },
	{ _C("Cycle Count"), NULL, BIN_IN_DETAILS },
	{ _C("Current"), _C("Real-time output current by attached accessory."), BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Voltage"), _C("Real-time output voltage by attached accessory."), BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Incoming Current"), NULL, BIN_IN_DETAILS | BIN_UNIT_MAMP },
	{ _C("Incoming Voltage"), NULL, BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("Accepting Charge"), _C("This indicates if accessory is accepting charge."), BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Temperature"), NULL, BIN_IN_DETAILS | BIN_UNIT_DEGREE_C },
	{ _C("Acc. Time to Empty"), NULL, BIN_IN_DETAILS | BIN_UNIT_MIN },
	{ _C("Acc. Time to Full"), NULL, BIN_IN_DETAILS | BIN_UNIT_MIN },
	/* Accessory UPS End */
	// FIXME: We need a Smart Battery Case to test
	// { _C("Status"), 0 },
	// { _C("State of Charge"), _C("The accessory battery percentage reported by AppleSMC."), 0 },
	// { _C("Accepting Charge"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("USB Connect State"), NULL, 0 },
	{ _C("USB Charging Volt."), NULL, BIN_IN_DETAILS | BIN_UNIT_MVOLT },
	{ _C("USB Current Config"), NULL, 0 },
	{ _C("Power Mode"), NULL, 0 },
	{ _C("Sleep Power"), NULL, 0 },
	{ _C("Supervised Acc. Attached"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	{ _C("Supervised Transports Restricted"), NULL, BIN_IN_DETAILS | BIN_IS_BOOLEAN },
	// TODO: Scorpius (I don't have Apple Pencil to test)
	{ NULL }  // DO NOT DELETE
};

struct iopm_property {
	const char   *name;
	CFStringRef **candidates;
	int           property_type; // 0 = don't care : default s_int32
	int           in_detail;
	double        multiplier; // when multiplier==0, no multiplier is applied
	                          // which means, multiplier 0 is equivalent to 1
};

// Special types:
// 0 - signed int32 - equivalent to kCFNumberSInt32Type
// 500 - bool
// 501 - CFStringRef
// 502 - bool (set hidden)
// 502 - bool (set hidden - inverted)
// (CFStringRef) 1 - first item in array (fail if not an array, will not crash)

#define IPCandidateGroup(...) \
	(CFStringRef *[]) { __VA_ARGS__, NULL }
#define IPCandidate(...) \
	(CFStringRef[]) { __VA_ARGS__, NULL }
#define IPSingleCandidate(...) \
	(CFStringRef *[]) { (CFStringRef[]) { __VA_ARGS__, NULL }, NULL }

struct iopm_property iopm_items[] = {
	{ _C("Avg. Temperature"), IPSingleCandidate(CFSTR("Temperature")), kCFNumberSInt16Type, 0, 1.0 / 100.0 },
	{ _C("Charging"), IPSingleCandidate(CFSTR("AppleRawExternalConnected")), 500, 0, 0 },
	{ _C("Full Charge Capacity"), IPSingleCandidate(CFSTR("AppleRawMaxCapacity")), kCFNumberSInt16Type, 1, 0 },
	{ _C("Designed Capacity"), IPSingleCandidate(CFSTR("DesignCapacity")), kCFNumberSInt16Type, 1, 0 },
	{ _C("Remaining Capacity"), IPSingleCandidate(CFSTR("AppleRawCurrentCapacity")), kCFNumberSInt16Type, 1, 0 },
	{ _C("Battery Uptime"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("LifetimeData"), CFSTR("TotalOperatingTime")), 0, 1, 1.0 / 60.0 },
	{ _C("Qmax"), IPCandidateGroup(IPCandidate(CFSTR("BatteryData"), CFSTR("Qmax"), (CFStringRef)1), IPCandidate(CFSTR("BatteryData"), CFSTR("QmaxCell0"))), 0, 1, 0 },
	{ _C("Depth of Discharge"), IPCandidateGroup(IPCandidate(CFSTR("BatteryData"), CFSTR("DOD0"), (CFStringRef)1), IPCandidate(CFSTR("BatteryFCCData"), CFSTR("DOD0"))), 0, 1, 0 },
	{ _C("Passed Charge"), IPCandidateGroup(IPCandidate(CFSTR("BatteryData"), CFSTR("PassedCharge")), IPCandidate(CFSTR("BatteryFCCData"), CFSTR("PassedCharge"))), 0, 1, 0 },
	{ _C("Voltage"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("Voltage")), 0, 1, 0 },
	{ _C("Avg. Current"), IPSingleCandidate(CFSTR("InstantAmperage")), 0, 1, 0 },
	{ _C("Cycle Count"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("CycleCount")), 0, 1, 0 },
	{ _C("State of Charge"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("StateOfCharge")), 0, 1, 0 },
	{ _C("State of Charge (UI)"), IPSingleCandidate(CFSTR("CurrentCapacity")), 0, 1, 0 },
	{ _C("Resistance Scale"), IPSingleCandidate(CFSTR("BatteryFCCData"), CFSTR("ResScale")), 0, 1, 0 },
	{ _C("Battery Serial No."), IPSingleCandidate(CFSTR("Serial")), 501, 1, 0 },
 // Chemistry ID: To be done programmatically
  // Flags: TBD Prg/ly
	{ _C("True Remaining Capacity"), IPSingleCandidate(CFSTR("AbsoluteCapacity")), 0, 1, 0 },
 //{_C("IT Misc Status"),IPSingleCandidate(CFSTR("BatteryData"),CFSTR("ITMiscStatus")),0,1,0},
	{ _C("Simulation Rate"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("SimRate")), 0, 1, 0 },
	{ _C("Daily Max SoC"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("DailyMaxSoc")), 0, 1, 0 },
	{ _C("Daily Min SoC"), IPSingleCandidate(CFSTR("BatteryData"), CFSTR("DailyMinSoc")), 0, 1, 0 },
	{ _C("Adapter Details"), IPSingleCandidate(CFSTR("AppleRawExternalConnected")), 503, 1, 0 },
 // Port???
  // Port Type???
  // Type TBD programmatically
  // Status???
	{ _C("Current Rating"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("Current")), 0, 1, 0 },
	{ _C("Voltage Rating"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("Voltage")), 0, 1, 0 },
 // Charger ID prog
	{ _C("Description"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("Description")), 501, 1, 0 },
	{ _C("PMU Configuration"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("PMUConfiguration")), 0, 1, 0 },
	{ _C("Model Name"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("Name")), 501, 1, 0 },
 // Model p
	{ _C("Manufacturer"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("Manufacturer")), 501, 1, 0 },
	{ _C("Firmware Version"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("FwVersion")), 501, 1, 0 },
	{ _C("Hardware Version"), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("HwVersion")), 501, 1, 0 },
	{ _C("Serial No."), IPSingleCandidate(CFSTR("AdapterDetails"), CFSTR("SerialString")), 501, 1, 0 },
	{ NULL }
};

struct battery_info_section *bi_make_section(const char *name, uint64_t context_size) {
	size_t                    size          = 0;
	struct battery_info_node *section_begin = NULL;
	for (struct battery_info_node *i = main_battery_template; i->name; i++) {
		if ((i->content & BIN_SECTION) == BIN_SECTION) {
			if (section_begin)
				break;
			if (i->name == name)
				section_begin = i;
		}
		if (section_begin)
			size += sizeof(struct battery_info_node);
	}
	if (!section_begin)
		return NULL;
	struct battery_info_section *section = malloc(size + 32 + context_size);
	section->next                        = NULL;
	section->self_ref                    = NULL;
	memcpy(&section->data, section_begin, size);
	*(char **)((uint64_t)section + size + 24) = NULL;
	section->context                          = (struct battery_info_section_context *)((uint64_t)section + size + 32);
	// Initialize context fields
	memset(section->context, 0, context_size);
	return section;
}

void bi_destroy_section(struct battery_info_section *sect) {
	if (!sect || !sect->context)
		return;
	
	// Mark section as being destroyed
	sect->context->destroying = true;
	
	if (sect->self_ref)
		battery_info_remove_section(sect);
	sect->data[0].name = NULL;   // This is to tell update() that the section is being destroyed
	sect->context->update(sect); // update() will have to release resources
	free(sect);
}

void bi_node_change_content_value(struct battery_info_node *node,
    int identifier, unsigned short value) {
	node += identifier;
	uint16_t *sects = (uint16_t *)&node->content;
	sects[1]        = value;
}

void bi_node_change_content_value_float(struct battery_info_node *node,
    int identifier, float value) {
	node += identifier;
	assert((node->content & BIN_IS_FLOAT) == BIN_IS_FLOAT);
	uint32_t *vptr = (uint32_t *)&value;
	uint32_t  vr   = *vptr;
	// TODO: No magic numbers!
	node->content =
	    ((vr & ((uint64_t)0b11 << 30)) | (vr & (((1 << 4) - 1) << 23)) << 3 |
	        (vr & (((1 << 10) - 1) << 13)) << 3) |
	    (node->content & ((1 << 16) - 1));
	// overwrite higher bits;
}

float bi_node_load_float(struct battery_info_node *node) {
	float     ret;
	uint32_t *vptr = (uint32_t *)&ret;
	uint32_t  vr   = node->content;
	*vptr =
	    ((vr & ((uint64_t)0b11 << 30)) | (vr & (((1 << 4) - 1) << 26)) >> 3 |
	        (vr & (((1 << 10) - 1) << 16)) >> 3);
	return ret;
}

void bi_node_set_hidden(struct battery_info_node *node, int identifier,
    bool hidden) {
	node += identifier;
	// assert((node->content & BIN_IN_DETAILS) == BIN_IN_DETAILS);
	if (!node->content)
		return;
	if (hidden) {
		node->content |= (1 << 5);
	} else {
		node->content &= ~(1L << 5);
	}
}

#include <mach/mach.h>

char *bi_node_ensure_string(struct battery_info_node *node, int identifier,
    uint64_t length) {
	node += identifier;
	assert(!(node->content & BIN_IS_SPECIAL));

	if (!node->content) {
		void *allocen = (void *)0x10000000;
		// ^ Preferred addr
		// Use vm_allocate to prevent possible unexpected heap allocation (it
		// crashes in current data structure)
		// TODO: get rid of hardcoded length
		int   result  = vm_allocate(mach_task_self(), (vm_address_t *)&allocen, 256, VM_FLAGS_ANYWHERE);
		if (result != KERN_SUCCESS) {
			// Fallback to malloc
			// allocen = malloc(length);
			allocen = nil;
		}
		node->content = (uint32_t)(((uint64_t)allocen) >> 3);
	}
	return bi_node_get_string(node);
}

char *bi_node_get_string(struct battery_info_node *node) {
	return (char *)(((uint64_t)node->content) << 3);
}

void bi_node_free_string(struct battery_info_node *node) {
	if (!node->content)
		return;
	vm_deallocate(mach_task_self(), (vm_address_t)bi_node_get_string(node), 256);
	node->content = 0;
}

static int _impl_set_item_find_item(struct battery_info_node **head, const char *desc) {
	if (!desc)
		return 0;
	for (struct battery_info_node *i = *head; i->name; i++) {
		if (i->name == desc) {
			*head = i;
			return 1;
		}
	}
	for (struct battery_info_node *i = (*head) - 1; i != head[1] - 1; i--) {
		if (i->name == desc) {
			*head = i;
			return 1;
		}
	}
	return 0;
}

static char *_impl_set_item(struct battery_info_node **head, const char *desc,
    uint64_t value, float valueAsFloat, int options) {
	if (!_impl_set_item_find_item(head, desc)) {
		return NULL;
	}
	struct battery_info_node *i = *head;
	if (options == 2 || (i->content & BIN_IS_SPECIAL) == 0) {
		if (options == 1) {
			if (value && i->content) {
				bi_node_free_string(i);
			}
			return NULL;
		}
		return bi_node_ensure_string(i, 0, 256);
	} else if (options == 1) {
		bi_node_set_hidden(i, 0, (bool)value);
	} else if ((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT) {
		bi_node_change_content_value_float(i, 0, valueAsFloat);
		return NULL;
	} else {
		bi_node_change_content_value(i, 0, (uint16_t)value);
	}
	return NULL;
}

#define BI_SET_ITEM(name, value) \
	_impl_set_item(head_arr, name, (uint64_t)(value), (float)(value), 0)

#define BI_ENSURE_STR(name) _impl_set_item(head_arr, name, 0, 0, 2)

#define BI_FORMAT_ITEM(name, ...) \
	sprintf(_impl_set_item(head_arr, name, 0, 0, 2), __VA_ARGS__)

#define BI_SET_ITEM_IF(cond, name, value)        \
	if (cond) {                                  \
		BI_SET_ITEM(name, value);                \
		_impl_set_item(head_arr, name, 0, 0, 1); \
	} else {                                     \
		_impl_set_item(head_arr, name, 1, 0, 1); \
	}

#define BI_FORMAT_ITEM_IF(cond, name, ...)       \
	if (cond) {                                  \
		BI_FORMAT_ITEM(name, __VA_ARGS__);       \
	} else {                                     \
		_impl_set_item(head_arr, name, 1, 0, 1); \
	}

#define BI_SET_HIDDEN(name, value) _impl_set_item(head_arr, name, value, 0, 1)

#include "../iokitextern.h"

void battery_info_init(struct battery_info_section **ptr) {
	*ptr = NULL;
	battery_info_update(ptr);
}

// ptr=&head;
void battery_info_insert_section(struct battery_info_section *sect, struct battery_info_section **ptr) {
	if (!ptr)
		return;
	if (!*ptr) {
		*ptr           = sect;
		sect->next     = NULL;
		sect->self_ref = ptr;
		return;
	}
	if (SECTION_PRIORITY(sect) <= SECTION_PRIORITY(*ptr)) {
		for (;; ptr = &(*ptr)->next) {
			if (!*ptr || SECTION_PRIORITY(sect) > SECTION_PRIORITY(*ptr)) {
				sect->next     = *ptr;
				if(*ptr)
					sect->next->self_ref=&sect->next;
				*ptr           = sect;
				sect->self_ref = ptr;
				return;
			}
		}
	} else {
		sect->next     = *ptr;
		if(*ptr)
			sect->next->self_ref=&sect->next;
		*ptr           = sect;
		sect->self_ref = ptr;
	}
}

void battery_info_remove_section(struct battery_info_section *sect) {
	if (sect->self_ref) {
		*(sect->self_ref) = sect->next;
		if (sect->next) {
			sect->next->self_ref = sect->self_ref;
		}
		sect->self_ref    = NULL;
	}
	sect->next        = NULL;
}

static int battery_info_has(struct battery_info_section *head, uint64_t identifier) {
	for (struct battery_info_section *i = head; i; i = i->next) {
		if (i->context->custom_identifier == identifier)
			return 1;
	}
	return 0;
}

void adapter_info_update_smc(struct battery_info_section *section);
void battery_info_update_smc(struct battery_info_section *section);
void accessory_info_update(struct battery_info_section *section);

void battery_info_poll(struct battery_info_section **head) {
	if (hasSMC) {
		if (!battery_info_has(*head, BI_GAS_GAUGE_SECTION_ID)) {
			struct battery_info_section *smcSect = bi_make_section(_C("Gas Gauge (Basic)"), sizeof(struct battery_info_section_context));
			smcSect->context->custom_identifier  = BI_GAS_GAUGE_SECTION_ID;
			smcSect->context->update             = battery_info_update_smc;
			battery_info_insert_section(smcSect, head);
		}
		charging_state_t charging_stat = is_charging(NULL, NULL);
		if (charging_stat > 0 && !battery_info_has(*head, BI_ADAPTER_SECTION_ID)) {
			struct battery_info_section *smcAdpSect = bi_make_section(_C("Adapter Details"), sizeof(struct battery_info_section_context));
			smcAdpSect->context->custom_identifier  = BI_ADAPTER_SECTION_ID;
			smcAdpSect->context->update             = adapter_info_update_smc;
			battery_info_insert_section(smcAdpSect, head);
		}
	}

	const char *acc_names[]={_C("Inductive Port"),_C("Serial Port"),NULL};
	const int acc_ports[]={kIOAccessoryPortID0Pin,kIOAccessoryPortIDSerial};
	for(int i=0;acc_names[i];i++) {
		io_service_t cur_connect=acc_open_with_port(acc_ports[i]);
		if(cur_connect!=IO_OBJECT_NULL) {
			if(!battery_info_has(*head, 420+i)) {
				struct battery_info_section *curSect=bi_make_section(acc_names[i],sizeof(struct accessory_info_section_context));
				struct accessory_info_section_context *context=(void*)curSect->context;
				context->identifier=420+i;
				context->update=accessory_info_update;
				context->primary_port=acc_ports[i];
				context->connect=cur_connect;
				battery_info_insert_section(curSect,head);
			}
		}
	}
}

// Non-recursive update to avoid use-after-free when sections are destroyed during update
static void _battery_info_update(struct battery_info_section *head) {
	struct battery_info_section *current = head;
	
	// First pass: collect all sections to update
	struct battery_info_section *sections_to_update[32]; // Reasonable limit
	int section_count = 0;
	
	while (current && section_count < 32) {
		sections_to_update[section_count++] = current;
		current = current->next;
	}
	
	// Second pass: update sections in reverse order (as the original recursive version did)
	for (int i = section_count - 1; i >= 0; i--) {
		struct battery_info_section *sect = sections_to_update[i];
		// Check if section is still valid (not destroyed or being destroyed)
		if (sect->context && sect->context->update && sect->data[0].name && !sect->context->destroying) {
			sect->context->update(sect);
		}
	}
}

void battery_info_update(struct battery_info_section **head) {
	battery_info_poll(head);
	if (*head)
		_battery_info_update(*head);
}

struct battery_info_section *battery_info_get_section(struct battery_info_section *head, long n) {
	for (long i = 0; i < n; i++)
		head = head->next;
	return head;
}

int battery_info_get_section_count(struct battery_info_section *head) {
	int ret = 0;
	for (struct battery_info_section *i = head; i; i = i->next)
		ret++;
	return ret;
}

// TODO: Re-implement
#if 0
void battery_info_update_iokit_with_data(struct battery_info_node *head, const void *info, bool inDetail) {
	struct battery_info_node *head_arr[2] = {head, head};
	uint16_t remain_cap,full_cap,design_cap;
	uint16_t temperature;
	CFNumberRef designCapacityNum=CFDictionaryGetValue(info, CFSTR("DesignCapacity"));
	CFNumberRef fullCapacityNum=CFDictionaryGetValue(info, CFSTR("AppleRawMaxCapacity"));
	CFNumberRef remainingCapacityNum=CFDictionaryGetValue(info, CFSTR("AppleRawCurrentCapacity"));
	if(!designCapacityNum||!fullCapacityNum||!remainingCapacityNum) {
		// Basic info required
		fprintf(stderr, "battery_info_update_iokit: Basic info required not present\n");
		CFRelease(info);
		return;
	}
	CFNumberGetValue(designCapacityNum, kCFNumberSInt16Type, (void *)&design_cap);
	CFNumberGetValue(fullCapacityNum, kCFNumberSInt16Type, (void *)&full_cap);
	CFNumberGetValue(remainingCapacityNum, kCFNumberSInt16Type, (void *)&remain_cap);
	BI_SET_ITEM_IF(1,_C("Health"), 100.0f * (float)full_cap / (float)design_cap);
	BI_SET_ITEM_IF(1,_C("SoC"), 100.0f * (float)remain_cap / (float)full_cap);
	BI_SET_ITEM("ASoC(Hidden)", 100.0f * (float)remain_cap / (float)design_cap);
	if (inDetail) {
		CFDictionaryRef batteryData = CFDictionaryGetValue(info, CFSTR("BatteryData"));
		if (batteryData) {
			int val = 0;
			CFNumberRef ChemIDNum = CFDictionaryGetValue(batteryData, CFSTR("ChemID"));
			if (ChemIDNum)
				CFNumberGetValue(ChemIDNum, kCFNumberSInt32Type, (void *)&val);
			BI_FORMAT_ITEM_IF(ChemIDNum, _C("Chemistry ID"), "0x%.8X", val);
			CFNumberRef FlagsNum = CFDictionaryGetValue(batteryData, CFSTR("Flags"));
			if (FlagsNum)
				CFNumberGetValue(FlagsNum, kCFNumberSInt32Type, (void *)&val);
			BI_FORMAT_ITEM_IF(FlagsNum, _C("Flags"), "0x%.4X", val);
			CFNumberRef ITMiscNum = CFDictionaryGetValue(batteryData, CFSTR("ITMiscStatus"));
			if (ITMiscNum)
				CFNumberGetValue(ITMiscNum, kCFNumberSInt32Type,(void *)&val);
			BI_FORMAT_ITEM_IF(ITMiscNum, _C("IT Misc Status"), "0x%.4X", val);
		}
	}
	CFTypeRef lastItem;
	for(struct iopm_property *i=iopm_items;i->name;i++) {
		int succ=0;
		for(CFStringRef **ppath=i->candidates;*ppath;ppath++) {
			lastItem=info;
			for(CFStringRef *elem=*ppath;*elem;elem++) {
				if(*elem==(CFStringRef)1) {
					if(CFGetTypeID(lastItem)!=CFArrayGetTypeID()) {
						lastItem=NULL;
						break;
					}
					lastItem=CFArrayGetValueAtIndex(lastItem,0);
				}else{
					if(CFGetTypeID(lastItem)!=CFDictionaryGetTypeID()) {
						lastItem=NULL;
						break;
					}
					lastItem=CFDictionaryGetValue(lastItem,*elem);
				}
				if(!lastItem)
					break;
			}
			if(!lastItem)
				continue;
			int val=0;
			if(i->property_type==500) {
				if(CFGetTypeID(lastItem)!=CFBooleanGetTypeID())
					continue;
				val=CFBooleanGetValue(lastItem);
			}else if(i->property_type==501) {
				if(CFGetTypeID(lastItem)!=CFStringGetTypeID())
					continue;
				CFStringGetCString(lastItem,BI_ENSURE_STR(i->name),256,kCFStringEncodingUTF8);
				succ=1;
				break;
			}else if(i->property_type==502) {
				if(CFGetTypeID(lastItem)!=CFBooleanGetTypeID())
					continue;
				succ=!CFBooleanGetValue(lastItem);
				BI_SET_HIDDEN(i->name,!succ);
				break;
			}else if(i->property_type==503) {
				if(CFGetTypeID(lastItem)!=CFBooleanGetTypeID())
					continue;
				succ=CFBooleanGetValue(lastItem);
				BI_SET_HIDDEN(i->name,!succ);
				break;
			}else{
				if(CFGetTypeID(lastItem)!=CFNumberGetTypeID())
					continue;
				CFNumberGetValue(lastItem,i->property_type?i->property_type:kCFNumberSInt32Type,(void*)&val);
				if(i->property_type==kCFNumberSInt16Type)
					val=(int)(short)val;
			}
			if(i->multiplier) {
				BI_SET_ITEM(i->name,(double)val * i->multiplier);
			}else{
				BI_SET_ITEM(i->name,val);
			}
			succ=1;
			break;
		}
		if(succ)
			BI_SET_HIDDEN(i->name,0);
	}
}

void battery_info_update_iokit(struct battery_info_node *head, bool inDetail) {
	io_service_t service = IOServiceGetMatchingService(0,IOServiceMatching("IOPMPowerSource"));
	CFMutableDictionaryRef info;
	int ret = IORegistryEntryCreateCFProperties(service, &info, 0, 0);
	if (ret != 0) {
		fprintf(stderr, "battery_info_update_iokit: Failed to get info from IOPMPowerSource\n");
		return;
	}
	battery_info_update_iokit_with_data(head, info, inDetail);
	CFRelease(info);
}
#endif

extern const char *cond_localize_c(const char *);

void adapter_info_update_smc(struct battery_info_section *section) {
    if (!section->data[0].name)
        return; // no data need to be freed
    struct battery_info_node *head        = section->data;
    struct battery_info_node *head_arr[2] = { head, head };
    mach_port_t               adapter_family;
    device_info_t             adapter_info;
    charging_state_t          charging_stat = is_charging(&adapter_family, &adapter_info);
    if (charging_stat <= 0) {
        bi_destroy_section(section);
        return;
    }
    charger_data_t adapter_data;
    get_charger_data(&adapter_data);
    // BI_SET_HIDDEN(_C("Adapter Details"), 0);
    BI_SET_ITEM(_C("Port"), adapter_info.port);
    /* FIXME: no direct use of cond_localize_c(), do locales like names */
    BI_FORMAT_ITEM(_C("Compatibility"), "%s: %s\n%s: %s", cond_localize_c("External Connected"), (adapter_data.ChargerExist != 0) ? L_TRUE : L_FALSE, cond_localize_c("Charger Capable"), (adapter_data.ChargerCapable != 0) ? L_TRUE : L_FALSE);
    BI_FORMAT_ITEM(_C("Type"), "%s (%.8X)", cond_localize_c(get_adapter_family_desc(adapter_family)), adapter_family);
    BI_FORMAT_ITEM(_C("Status"), "%s", (charging_stat == kIsPausing || adapter_data.NotChargingReason != 0) ? cond_localize_c("Not Charging") : cond_localize_c("Charging"));

	/* Adapter -> VBUS -> Battery */
	/* XXX: Consider make a better UI for them */
    BI_SET_ITEM(_C("Current Rating"), adapter_info.current);
    BI_SET_ITEM(_C("Voltage Rating"), adapter_info.voltage);
	/* IBUS gives A */
	BI_SET_ITEM(_C("Input Current"), adapter_info.input_current * 1000.0f);
	/* VBUS gives V */
	BI_SET_ITEM(_C("Input Voltage"), adapter_info.input_voltage * 1000.0f);
    BI_SET_ITEM(_C("Charging Current"), adapter_data.ChargingCurrent);
    BI_SET_ITEM(_C("Charging Voltage"), adapter_data.ChargingVoltage);
    BI_FORMAT_ITEM(_C("Charger IC ID"), "0x%.4X", adapter_data.ChargerId);
    BI_FORMAT_ITEM_IF(*adapter_info.name, _C("Model Name"), "%s", adapter_info.name);
    BI_FORMAT_ITEM_IF(*adapter_info.vendor, _C("Manufacturer"), "%s", adapter_info.vendor);
    BI_FORMAT_ITEM_IF(*adapter_info.adapter, _C("Model"), "%s", adapter_info.adapter);
    BI_FORMAT_ITEM_IF(*adapter_info.firmware, _C("Firmware Version"), "%s", adapter_info.firmware);
    BI_FORMAT_ITEM_IF(*adapter_info.hardware, _C("Hardware Version"), "%s", adapter_info.hardware);
    BI_FORMAT_ITEM_IF(*adapter_info.description, _C("Description"), "%s", adapter_info.description);
    BI_FORMAT_ITEM_IF(*adapter_info.serial, _C("Serial No."), "%s", adapter_info.serial);

	BI_FORMAT_ITEM_IF((int32_t)adapter_info.PMUConfiguration != -1, _C("PMU Configuration"), "%d %s", adapter_info.PMUConfiguration, L_MA);
	BI_FORMAT_ITEM_IF((int32_t)adapter_info.PMUConfiguration == -1, _C("PMU Configuration"), "%s", cond_localize_c("Unspecified"));
    BI_SET_ITEM(_C("Charger Configuration"), adapter_data.ChargerConfiguration);
    BI_FORMAT_ITEM_IF(adapter_data.NotChargingReason != 0, _C("Reason"), "%s", not_charging_reason_str(adapter_data.NotChargingReason));
    BI_FORMAT_ITEM_IF(adapter_info.adap_type != 0, _C("Adapter Type"), "%d", adapter_info.adap_type);
}

void battery_info_update_smc(struct battery_info_section *section) {
	if (!hasSMC) {
		abort(); // this section should not have been added
		/*for(struct battery_info_node *i=head+1;i->name;i++) {
		    bi_node_set_hidden(i,0,1);
		}
		battery_info_update_iokit(head,inDetail);*/
		return;
	}
	if (!section->data[0].name)
		return; // no data need to be freed
	struct battery_info_node *head = section->data;
	uint16_t                  remain_cap = 0, full_cap = 0, design_cap = 0;
	get_capacity(&remain_cap, &full_cap, &design_cap);

	struct battery_info_node *head_arr[2] = { head, head };
	/* Health = 100.0f * FullChargeCapacity (mAh) / DesignCapacity (mAh) */
	BI_SET_ITEM(_C("Health"), 100.0f * (float)full_cap / (float)design_cap);
	/* SoC = 100.0f * RemainCapacity (mAh) / FullChargeCapacity (mAh) */
	if (remain_cap && full_cap)
		BI_SET_ITEM(_C("SoC"), 100.0f * (float)remain_cap / (float)full_cap);
	else {
		uint8_t uisoc = 0;
		smc_read_n('BUIC', &uisoc, 1);
		DBGLOG(CFSTR("remain_cap=0, Use UISoC (%d) as SoC instead"), (int)uisoc);
		BI_SET_ITEM(_C("SoC"), uisoc);
	}
	// No Imperial units here
	BI_SET_ITEM(_C("Avg. Temperature"), get_temperature());
	// // TODO: Charging Type Display {"Battery Power", "AC Power", "UPS Power"}
	charging_state_t charging_stat = is_charging(NULL, NULL);
	BI_SET_ITEM(_C("Charging"), (charging_stat == kIsCharging));
	/* ASoC = 100.0f * RemainCapacity (mAh) / DesignCapacity (mAh) */
	BI_SET_ITEM("ASoC(Hidden)", 100.0f * remain_cap / design_cap);
	// if (inDetail) {
	get_gas_gauge(&gGauge);
	BI_FORMAT_ITEM_IF(strlen(gGauge.DeviceName), _C("Device Name"), "%s", gGauge.DeviceName);
	BI_SET_ITEM(_C("Full Charge Capacity"), full_cap);
	BI_SET_ITEM(_C("Designed Capacity"), design_cap);
	BI_SET_ITEM(_C("Remaining Capacity"), remain_cap);
	/* FIXME: bmsUptime uses at least 4 bytes (8 bytes in total), current structure only allow 2 */
	// second_to_datefmt is a workaround, the "Battery Uptime" should be numeric type
	BI_FORMAT_ITEM(_C("Battery Uptime"), "%s", second_to_datefmt(gGauge.bmsUpTime));
	BI_SET_ITEM(_C("Qmax"), gGauge.Qmax * batt_cell_num());
	BI_SET_ITEM(_C("Depth of Discharge"), gGauge.DOD0);
	BI_SET_ITEM(_C("Passed Charge"), gGauge.PassedCharge);
	BI_SET_ITEM(_C("Voltage"), gGauge.Voltage);
	BI_SET_ITEM(_C("Avg. Current"), gGauge.AverageCurrent);
	BI_SET_ITEM(_C("Avg. Power"), gGauge.AveragePower);
	BI_SET_ITEM(_C("Cell Count"), batt_cell_num());
	/* FIXME: TTE still displays when -1, WHY?? */
	int timeToEmpty = get_time_to_empty();
	BI_SET_ITEM_IF(timeToEmpty > 0, _C("Time to Empty"), timeToEmpty);
	BI_SET_ITEM(_C("Cycle Count"), gGauge.CycleCount);
	BI_SET_ITEM_IF(gGauge.DesignCycleCount, _C("Designed Cycle Count"), gGauge.DesignCycleCount)
	BI_SET_ITEM(_C("State of Charge"), gGauge.StateOfCharge);
	BI_SET_ITEM(_C("State of Charge (UI)"), gGauge.UISoC);
	BI_SET_ITEM_IF(gGauge.ResScale, _C("Resistance Scale"), gGauge.ResScale);
	if (!battery_serial(BI_ENSURE_STR(_C("Battery Serial No.")))) {
		BI_FORMAT_ITEM(_C("Battery Serial No."), "%s", L_NONE);
	}
	BI_FORMAT_ITEM("Chemistry ID", "0x%.8X", gGauge.ChemID);

	/* For Flags, I need at least DeviceName to confirm its format */
	/* TODO: bq40z651 */
	/* Confirmed Flags format */
	/* bq20z45*: Battery Status (0x16):
	 * https://www.ti.com/lit/er/sluu313a/sluu313a.pdf */
	BI_FORMAT_ITEM(_C("Flags"), "0x%.4X", gGauge.Flags);
	BI_SET_ITEM_IF(gGauge.TrueRemainingCapacity,
	    _C("True Remaining Capacity"),
	    gGauge.TrueRemainingCapacity);
	BI_SET_ITEM_IF(gGauge.OCV_Current, _C("OCV Current"), gGauge.OCV_Current);
	BI_SET_ITEM_IF(gGauge.OCV_Voltage, _C("OCV Voltage"), gGauge.OCV_Voltage);
	BI_SET_ITEM_IF(gGauge.IMAX, _C("Max Load Current"), gGauge.IMAX);
	BI_SET_ITEM_IF(gGauge.IMAX2, _C("Max Load Current 2"), gGauge.IMAX2);
	BI_FORMAT_ITEM_IF(gGauge.ITMiscStatus, _C("IT Misc Status"), "0x%.4X", gGauge.ITMiscStatus);
	BI_SET_ITEM_IF(gGauge.SimRate, _C("Simulation Rate"), gGauge.SimRate);
	BI_SET_ITEM_IF(gGauge.DailyMaxSoc, _C("Daily Max SoC"), gGauge.DailyMaxSoc);
	BI_SET_ITEM_IF(gGauge.DailyMinSoc, _C("Daily Min SoC"), gGauge.DailyMinSoc);
}

void accessory_info_update(struct battery_info_section *section) {
	struct accessory_info_section_context *context=(void*)section->context;
	if (!section->data[0].name) {
		IOObjectRelease(context->connect);
		return;
	}

	struct battery_info_node *head        = section->data;
	struct battery_info_node *head_arr[2] = { head, head };
	io_connect_t connect                  = context->connect;

	SInt32 acc_id                         = get_accid(connect);
	SInt32 port_type                      = get_acc_port_type(connect);
	SInt32 features                       = get_acc_allowed_features(connect);
	accessory_info_t accinfo              = get_acc_info(connect);
	accessory_powermode_t mode            = get_acc_powermode(connect);
	accessory_sleeppower_t sleep          = get_acc_sleeppower(connect);
	iktara_accessory_array_t array;
	accessory_usb_connstat_t connstat;
	accessory_usb_ilim_t ilim;
	int inductive_fw_mode                 = get_acc_inductive_fw_mode(connect);
	int inductive_region                  = get_acc_inductive_region_code(connect);
	bool inductive_timeout                = get_acc_inductive_timeout(connect);
	uint32_t vid = 0, pid = 0;

	// TODO: Consider display info when -1, this typically happens when USB-C
	// 100: Not connected, -1: Unrecognized
	if (connect == IO_OBJECT_NULL || acc_id == 100 || acc_id == -1)  {
		bi_destroy_section(section);
		return;
	}
	
	// This is temporary, subcells will be implemented to replace this terrible impl.
	char str_buf[512];
	char *bufptr=str_buf;

	/* IOAM Part */
	const char *idstr = acc_id_string(acc_id);
	BI_FORMAT_ITEM(_C("Acc. ID"), "%d\n%s", acc_id,idstr);
	BI_FORMAT_ITEM_IF(features != -1, _C("Allowed Features"), "0x%.8X", features);
	BI_FORMAT_ITEM_IF(port_type != -1, _C("Port Type"), "%s", acc_port_type_string(port_type));
	BI_FORMAT_ITEM_IF(*accinfo.serial, _C("Serial No."), "%s", accinfo.serial);
	// Consider add a warnaccessory if vendor name appears a fake "Apple Inc."
	BI_FORMAT_ITEM_IF(*accinfo.vendor, _C("Manufacturer"), "%s", accinfo.vendor);
	BI_FORMAT_ITEM_IF(*accinfo.model, _C("Model"), "%s", accinfo.model);
	BI_FORMAT_ITEM_IF(*accinfo.name, _C("Name"), "%s", accinfo.name);
	BI_FORMAT_ITEM_IF(*accinfo.PPID, _C("PPID"), "%s", accinfo.PPID);
	BI_FORMAT_ITEM_IF(*accinfo.fwVer, _C("Firmware Version"), "%s", accinfo.fwVer);
	BI_FORMAT_ITEM_IF(*accinfo.hwVer, _C("Hardware Version"), "%s", accinfo.hwVer);
	BI_FORMAT_ITEM(_C("Battery Pack"), "%s", get_acc_battery_pack_mode(connect) ? L_TRUE : L_FALSE);
	
	bufptr+=sprintf(bufptr,"%s: ",cond_localize_c("Configured Mode"));
	acc_powermode_string(mode.mode,&bufptr);
	*(bufptr++)='\n';
	bufptr+=sprintf(bufptr,"%s: ",cond_localize_c("Active Mode"));
	acc_powermode_string(mode.active,&bufptr);
	*(bufptr++)='\n';
	acc_powermode_string_supported(mode,&bufptr);
	BI_FORMAT_ITEM(_C("Power Mode"), "%s", str_buf);
	if (sleep.supported) {
		BI_FORMAT_ITEM(_C("Sleep Power"), "%s\n%s: %d", sleep.enabled ? cond_localize_c("Enabled") : cond_localize_c("Disabled"), cond_localize_c("Limit"), sleep.limit);
	} else {
		BI_FORMAT_ITEM(_C("Sleep Power"), "%s", cond_localize_c("Unsupported"));
	}
	// Only show these when true
	BI_SET_ITEM_IF(get_acc_supervised(connect), _C("Supervised Acc. Attached"), true);
	BI_SET_ITEM_IF(get_acc_supervised_transport_restricted(connect), _C("Supervised Transports Restricted"), true);

	/* AppleSMC Part */
	bool smc_vendor = false;
	if (hasSMC && accessory_available() && context->primary_port == kIOAccessoryPortID0Pin) {
		BI_SET_ITEM(_C("Providing Power"), vbus_port() == 2);
		if (get_iktara_accessory_array(&array) && array.present == 1) {
			/* TODO: Search VID/PID online */
			const char *vendor_name = manf_id_string((SInt32)array.VID);
			if (vendor_name) {
				BI_FORMAT_ITEM_IF(vendor_name, _C("Vendor ID"), "0x%0.4X\n(%s)", array.VID, vendor_name);
			} else {
				BI_FORMAT_ITEM_IF(array.VID, _C("Vendor ID"), "0x%0.4X", array.VID);
			}
			if (array.VID == VID_APPLE) {
				const char *product_name = apple_prod_id_string(array.PID);
				if (product_name) {
					BI_FORMAT_ITEM_IF(product_name, _C("Product ID"), "0x%0.4X\n(%s)", array.PID, product_name);
				} else {
					BI_FORMAT_ITEM_IF(array.PID, _C("Product ID"), "0x%0.4X", array.PID);
				}
			} else {
				BI_FORMAT_ITEM_IF(array.PID, _C("Product ID"), "0x%0.4X", array.PID);
			}
			if (array.VID && array.PID) {
				smc_vendor = true;
				vid = array.VID;
				pid = array.PID;
			}

			BI_FORMAT_ITEM_IF(array.capacity != -1, _C("State of Charge"), "%d%%", array.capacity);
			BI_SET_ITEM_IF(array.charging != -1, _C("Accepting Charge"), array.charging);
			BI_FORMAT_ITEM_IF(array.status, _C("Status"), "0x%.8X", array.status);
		}
		/* TODO: Iktara Fw/Drv stat */
	} else {
		// For now, I only have one MagSafe Battery Pack to test, so disable those values for other ports before someone donate some Smart Battery Cases
		// FIXME: this is a workaround for init cells, try fix bi_make_section
		BI_SET_ITEM_IF(array.charging != -1, _C("Accepting Charge"), array.charging);
	}

	/* Inductive Port: kHIDPage_AppleVendor:70 */
	bool hid_vendor = false;
	if (!smc_vendor && context->primary_port == kIOAccessoryPortID0Pin) {
		vid = pid = 0;
		// Normally, only one device will be at 0xFF00:70
		if (first_vendor_at_usagepagepairs(&vid, &pid, 0xFF00, 70)) {
			const char *vendor_name = manf_id_string((SInt32)vid);
			if (vendor_name) {
				BI_FORMAT_ITEM_IF(vendor_name, _C("Vendor ID"), "0x%0.4X\n(%s)", vid, vendor_name);
			} else {
				BI_FORMAT_ITEM_IF(vid, _C("Vendor ID"), "0x%0.4X", vid);
			}
			if (vid == VID_APPLE) {
				const char *product_name = apple_prod_id_string(pid);
				if (product_name) {
					BI_FORMAT_ITEM_IF(product_name, _C("Product ID"), "0x%0.4X\n(%s)", pid, product_name);
				} else {
					BI_FORMAT_ITEM_IF(pid, _C("Product ID"), "0x%0.4X", pid);
				}
			} else {
				BI_FORMAT_ITEM_IF(pid, _C("Product ID"), "0x%0.4X", pid);
			}
		}
		if (vid && pid)
			hid_vendor = true;
	} else if (context->primary_port == kIOAccessoryPortIDSerial) {
		BI_SET_ITEM(_C("Providing Power"), vbus_port() == 1);

		if (acc_id == 91) {
			UInt8 digitalID[6];
			SInt64 idsn;
			char msn[32];
			// Digital ID
			BI_FORMAT_ITEM_IF(get_acc_digitalid(connect, &digitalID) == kIOReturnSuccess, _C("Digital ID"), "%02x %02x %02x %02x %02x %02x", digitalID[0], digitalID[1], digitalID[2], digitalID[3], digitalID[4], digitalID[5]);
			BI_FORMAT_ITEM_IF(get_acc_idsn(connect, &idsn) == kIOReturnSuccess, _C("ID Serial No."), "%llX", idsn);
			BI_FORMAT_ITEM_IF(get_acc_msn(connect, &msn) == kIOReturnSuccess, _C("IM Serial No."), "%s", msn);
			// TODO: Digital Info
		}
		BI_FORMAT_ITEM_IF(get_acc_usb_connstat(connect, &connstat) == kIOReturnSuccess, _C("USB Connect State"), "%s\n%s: %s, %s: %s", connstat.active ? cond_localize_c("Active") : cond_localize_c("Inactive"), cond_localize_c("Type"), acc_usb_connstat_string(connstat.type), cond_localize_c("Published Type"), acc_usb_connstat_string(connstat.published_type));

		SInt32 voltage = 0;
		BI_SET_ITEM_IF((get_acc_usb_voltage(connect, &voltage) != kIOReturnNotAttached), _C("USB Charging Volt."), voltage);
		// XXX: Consider use custom UI for this
		if(get_acc_usb_ilim(connect, &ilim) != kIOReturnNotAttached) {
			acc_usb_ilim_string_multiline(ilim,str_buf);
			BI_FORMAT_ITEM(_C("USB Current Config"), "%s", str_buf);
		}
		/* TODO: Transport types */

		/* How do we actually get VID/PID if wired? MFA Cables does not seems having them */
	} else if (context->primary_port == 256) {
		/* TODO: SmartConnector */
	} else if (context->primary_port == 257) {
		/* TODO: Scorpius */
	}
	acc_inductive_mode_string(inductive_fw_mode,str_buf);
	BI_FORMAT_ITEM_IF(inductive_fw_mode != -1, _C("Inductive FW Mode"), "%s", str_buf);
	BI_FORMAT_ITEM_IF(inductive_region != -1, _C("Inductive Region Code"), "0x%04x (%c%c)", (uint16_t)inductive_region, (inductive_region & 0xFF00) >> 8, inductive_region & 0xFF);
	BI_SET_ITEM_IF(inductive_timeout, _C("Inductive Auth Timeout"), inductive_timeout);
	/* MagSafe Charger: kHIDPage_AppleVendor:17 */
	/* MagSafe Battery: kHIDPage_AppleVendor:11 */
	// By verifying 0xFF00:(17/11), we can know which type of device actually attached

	/* Accessory Battery: kHIDPage_PowerDevice:kHIDUsage_PD_PeripheralDevice */
	/* Battery Case: kHIDPage_BatterySystem:kHIDUsage_BS_PrimaryBattery */
	/* The Battery Case / Battery Pack details are stored in kHIDPage_BatterySystem normally */
	// check UPSMonitor.m
	// FIXME: kIOAccessoryPortIDSerial added as a workaround of cell init, try fix bi_make_section
	if (smc_vendor || hid_vendor || context->primary_port == kIOAccessoryPortIDSerial) {
		UPSDataRef device = UPSDeviceMatchingVendorProduct(vid, pid);
		ups_batt_t info = {0};

		int cell_count = 0;
		if (device != NULL) {
			info = ups_battery_info(device);

			CFIndex caps_count = CFSetGetCount(device->upsCapabilities);
			for (CFIndex i = 0; i < caps_count; i++) {
				CFStringRef val = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("Cell %ld Voltage"), i);
				if (val && CFSetContainsValue(device->upsCapabilities, val)) {
					cell_count++;
					CFRelease(val);
					continue;
				} else {
					if (val) CFRelease(val);
					break;
				}
			}
		}
		/* We are not ready to display Cell specs for any batteries (But defined in headers) */
		BI_SET_ITEM_IF(cell_count != 0, ("Cell Count"), cell_count);
		/* Sadly, UPS does not got reports on Designed Capacity */
		BI_SET_ITEM_IF(info.current_capacity != 0, _C("Current Capacity"), info.current_capacity);
		BI_SET_ITEM_IF(info.max_capacity != 0, _C("Max Capacity"), info.max_capacity);
		BI_SET_ITEM_IF(info.cycle_count != 0, _C("Cycle Count"), info.cycle_count);
		/* XXX: Device Color */
		BI_SET_ITEM_IF(info.batt_charging_voltage != 0, _C("Charging Voltage Rating"), info.batt_charging_voltage);
		BI_SET_ITEM_IF(info.batt_charging_voltage != 0, _C("Avg. Charging Current"), info.batt_charging_current);
		BI_SET_ITEM_IF(info.current != 0, _C("Current"), info.current);
		BI_SET_ITEM_IF(info.current != 0, _C("Voltage"), info.voltage);
		BI_SET_ITEM_IF(info.incoming_current != 0, _C("Incoming Current"), info.incoming_current);
		BI_SET_ITEM_IF(info.incoming_voltage != 0, _C("Incoming Voltage"), info.incoming_voltage);
		BI_SET_ITEM_IF(info.charging != 0, _C("Accepting Charge"), info.charging);
		BI_SET_ITEM_IF(info.temperature != 0, _C("Temperature"), info.temperature);
		BI_SET_ITEM_IF(info.time_to_empty != 0, _C("Acc. Time to Empty"), info.time_to_empty);
		BI_SET_ITEM_IF(info.time_to_full != 0, _C("Acc. Time to Full"), info.time_to_full);
		
		/* We are not ready to display Lifetime data for any batteries (But defined in headers) */

		/*
		 MagSafe Battery Pack Events:
		 {
			AppleRawCurrentCapacity = 815;
			"Battery Case Charging Voltage" = 0;
			"Cell 0 Voltage" = 3786;
			"Cell 1 Voltage" = 3762;
			Current = "-991";
			"Current Capacity" = 851;
			CycleCount = 279;
			"Debug Information" =     {
				"Attach Count 10.5W Adapter" = 1931312116;
				"Attach Count 12W Adapter" = 4152232521;
				"Attach Count 15W Adapter" = 3089525786;
				"Attach Count 18 - 20W Adapter" = 968817642;
				"Attach Count 5W Adapter" = 2124225740;
				"Attach Count 7.5W Adapter" = 4021667898;
				"Attach Count Device Type 0" = 1213098256;
				"Attach Count Device Type 1" = 3198192647;
				"Attach Count Less Than 5W Adapter" = 380749299;
				"Attach Count Other" = 2519347824;
				"Attach Count Over 20W Adapter" = 904112396;
				"Battery Case Average Charging Current" = 0;
				ChargingStatus = 364;
				"Host Available Power dW" = 106;
				InductiveStatus = 2147745799;
				"Kiosk Mode Count" = 0;
				"Lifetime Cell0 Max Q" = 1460;
				"Lifetime Cell0 Max Voltage" = 4354;
				"Lifetime Cell0 Min Voltage" = 2823;
				"Lifetime Cell1 Max Q" = 1462;
				"Lifetime Cell1 Max Voltage" = 4351;
				"Lifetime Cell1 Min Voltage" = 2777;
				"Lifetime Firmware Runtime" = 112347250;
				"Lifetime Max Charge Current" = 2048;
				"Lifetime Max Discharge Current" = "-2122";
				"Lifetime Max Temperature" = 49;
				"Lifetime Min Temperature" = 0;
				"Lifetime Time Above High Temperature" = 52078;
				"Lifetime Time Above Low Temperature" = 6215247;
				"Lifetime Time Above Mid Temperature" = 698591;
				"Lifetime Time Below Low Temperature" = 60438707;
				PowerStatus = 39;
				"Rx Power Limit" = 3;
			};
			"Device Color" = 0;
			"Incoming Current" = 271;
			"Incoming Voltage" = 92;
			"Is Charging" = 0;
			"Max Capacity" = 1281;
			"Nominal Capacity" = 1273;
			"Power Source State" = "Battery Power";
			Temperature = 35;
			"Time to Empty" = 77;
			Voltage = 7548;
		 }
		*/
	}
	
	/* TODO: CoreAccessory Part */
}
