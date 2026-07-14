#include "accessory.h"
#include "../common.h"
//#include "intlextern.h"
#include <mach/mach.h>

io_iterator_t gAccessories;
io_service_t gAccPrimary;
static bool use_libioam = false;

const char *acc_id_0_f[] = {
	"3K: Simple dock (beep on insert)",
	"10K: FireWire card reader",
	"18K: (Reserved/unused)",
	"28K: USB device accessory",
	"39K: (Reserved/unused)",
	"52K: (Reserved/unused)",
	"68K: Line out on/speaker off (MFP-compat, A63)",
	"88K: Diagnostics dock",
	"113K: (Reserved/unused)",
	"147K: (Reserved/unused)",
	"191K: USB iAP HID alternate config",
	"255K: Battery pack (no iPod charge)",
	"360K: Line out off, echo cancel on (MFP-compat, A63)",
	"549K: 30 pin connector serial device",
	"1000K: Car charger (pause on detach)",
	"3010K: Acc detect grounded but no resistor ID)",
};

const char *acc_id_50_5e[] = {
	"USBC: USB Host only",
	"USBC: USB Device only",
	"USBC: USB Host + DP display",
	"USBC: USB Device + DP display",
	"USBC: DP display only",
	"USBC: Snk current only",
	"USBC: Src current only",
	"USBC: Debug only",
	"USBC: Plugged other",
	NULL,
	"Digital ID: not found",
	"Digital ID", // This will need IOAccessoryManagerGetDigitalID()
	"Digital ID: unsupported",
	"Digital ID: unreliable",
	"Digital ID: reversed orientation",
};

/* Sadly I didn't got the full list of accids, but we can guess */
const char *acc_id_string(int accid) {
	if (accid >= 0 && accid < 16) {
		return acc_id_0_f[accid];
	} else if (accid > 79 && accid < 95 && accid != 89) {
		int idx = accid - 80;
		return acc_id_50_5e[idx];
	} else if (accid == 70) {
		return "(Scorpius: unknown)";
	} else if (accid == 71) {
		return "(Scorpius: pencil)";
	}
	
	return "";
}


#ifdef _C
#undef _C
#endif
#define _C(x) x
static const char *acc_powermodes[] = {
	_C("Off"),
	_C("Low"),
	_C("On"),
	_C("High Current"),
	_C("High Current (BM3)"),
	_C("Low Voltage"),
};
static const char *acc_usb_connstats[] = {
	_C("None"),
	_C("Charger"),
	_C("Host"),
	_C("Host (alternate config)"), // HostAltConfig
	_C("Device"),
	_C("Device (Auth required)"),  // DeviceAuthRequired
};
static const char *acc_port_types[] = {
	_C("Unknown"),
	_C("Virtual"),
	_C("USB-C"),
	_C("USB-A"),
	_C("Mini DP"),
	_C("FireWire 800"),
	_C("HDMI"),
	_C("Audio Jack (Mini)"),
	_C("Ethernet"),
	_C("MagSafe"),			// This is typically old MagSafe charger port on old MacBooks
	_C("MagSafe 2"),
	_C("SD Card"),
	_C("Lightning"),
	_C("30-Pin"),			// Wow, who still using this
	_C("Inductive"),		// iPhone wireless charging / Apple Pencil magnetically connect
	_C("Smart Connector"),
	_C("Display Port"),
	_C("MagSafe 3"),		// 2021 introduced MagSafe 3 for MacBooks
	// We need help on testing 'Inductive', 'Contactless' and 'Wireless'
	_C("Contactless"),
	_C("Wireless")
};
static const char *acc_inductive_modes[] = {
	_C("RX"),
	_C("TX"),
	_C("TEST"),
	_C("INVALID"),
};
#undef _C
extern const char *cond_localize_c(const char *);
#define _C(x) cond_localize_c(x)

void acc_powermode_string(AccessoryPowermode powermode, char **pbuf) {
	// IOAM modes are starting form 1
	if (powermode >= kIOAMPowermodeOff && powermode <= kIOAMPowermodeCount) {
		*pbuf=stpcpy(*pbuf,_C(acc_powermodes[powermode - 1]));
		return;
	}

	(*pbuf) +=sprintf(*pbuf, "<%d>", powermode);
}
const char *acc_usb_connstat_string(int usb_connstat) {
	if (usb_connstat > 5) return _C("Unknown");
	
	return _C(acc_usb_connstats[usb_connstat]);
}

void acc_powermode_string_supported(accessory_powermode_t mode, char **pbuf) {
	if (mode.supported_cnt == 0) {
		**pbuf=0;
		return;
	}

	(*pbuf)+=sprintf(*pbuf, "%s: ", _C("Supported List"));
	for (size_t i = 0; i < mode.supported_cnt; i++) {
		(*pbuf)+=sprintf(*pbuf, "%s", (i == 0) ? "" : "\n");
		acc_powermode_string(mode.supported[i],pbuf);
		(*pbuf)+=sprintf(*pbuf, "<%lu %s>", mode.supported_lim[i], L_MA);
	}
}

void acc_usb_ilim_string_multiline(accessory_usb_ilim_t ilim, char *pbuf) {
	if (ilim.limit == 0) {
		strcpy(pbuf,_C("Detached"));
		return;
	}

	// XXX: This is terrible, consider migrate to a better UI
	pbuf+=sprintf(pbuf, "%s: %lu %s", _C("Limit"), (unsigned long)ilim.limit, L_MA);
	if (ilim.base || ilim.offset || ilim.max) {
		pbuf=stpcpy(pbuf, "\n(");
		if (ilim.base)
			pbuf+=sprintf(pbuf, "%s: %lu", _C("Base"), (unsigned long)ilim.base);
		if (ilim.offset)
			pbuf+=sprintf(pbuf, "%s%s: %lu", (ilim.base) ? " " : "", _C("Offset"), (unsigned long)ilim.offset);
		if (ilim.max)
			pbuf+=sprintf(pbuf, "%s%s: %lu", (ilim.base || ilim.offset) ? " " : "", _C("Max"), (unsigned long)ilim.max);
		
		*(pbuf++)=')';
		*(pbuf++)=0;
	}
}

const char *acc_port_type_string(int pt) {
	if (pt > 19) {
		return _C("Undefined");
	}
	return _C(acc_port_types[pt]);
}

void acc_inductive_mode_string(int mode, char *pbuf) {
	if (mode >= 0 && mode < 4) {
		strcpy(pbuf,_C(acc_inductive_modes[mode]));
		return;
	}
	
	sprintf(pbuf, "<%d>", mode);
}

const char *manf_id_string(int manf) {
	switch (manf) {
		// retrieve from online db? or just common vids?
		case VID_APPLE: return "Apple Inc.";
		case VID_UGREEN: return "Ugreen Group Limited";
		default: break;
	}
	return NULL;
}

const char *ugreen_prod_id_string(int prod) {
	switch (prod) {
		case 0xC5DC: return "MagSafe Charger (MFi Module)";	// 219693601610 A2463
		default:
			break;
	}
	return NULL;
}

const char *apple_prod_id_string(int prod) {
	switch (prod) {
		case 0x0500: return "MagSafe Charger";					// A2140
		case 0x0501: return "MagSafe Charger (MFi Module)";		// A2463
		case 0x0502: return "MagSafe Duo Charger";				// A2458
		case 0x0503: return "WatchPuck";						// A2515
		case 0x0504: return "WatchPuck (MFi Module)";			// A2755
		case 0x0505: return "WatchPuck (MFi Module)";			// A2675
		case 0x0506: return "MagSafe Charger";					// A2580

		case 0x1395: return "Smart Battery Case [iPhone 6]";
		case 0x1398: return "Smart Battery Case";
		case 0x1399: return "MagSafe Battery Pack";				// A2384
		case 0x139B: return "MagSafe Charger (MFi Module)";		// A2728

		case 0x7002:											// A2166
		case 0x7016:											// A2518
		case 0x7019:											// A2452
		case 0x701A:											// A2571
		case 0x701B: return "Power Adapter";					// A2676

		case 0x7800: return "MagSafe Cable";					// A2363
		case 0x7803: return "MagSafe Charger";					// A2781
		default: break;
	}
	return NULL;
}

/* Private func of IOAM */
static IOReturn checkIDBusAvailable(io_registry_entry_t entry, bool accessory_mode) {
	IOReturn result = kIOReturnSuccess;
	UInt8 bytes[6];
	
	memset(bytes, 0xAA, 6);

	result = get_acc_digitalid(entry, bytes);
	if (result == kIOReturnSuccess) {
		result = kIOReturnNotReadable;
		if (bytes[0] <= 0x3F) {
			if (accessory_mode && (bytes[1] & 3) == 0)
				return kIOReturnUnsupportedMode;
			else
				return kIOReturnNotFound;
		}
	}
	return result;
}

/* Make sure logics are not directly called in the UI */
#pragma mark - IOAccessoryMananger

io_iterator_t IOAccessoryManagerGetServices(void) {
	io_iterator_t services = MACH_PORT_NULL;
	IOReturn kr = kIOReturnSuccess;

	kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOAccessoryManager"), &services);
	if (kr != kIOReturnSuccess) {
		DBGLOG(CFSTR("Cannot open IOAccessoryManager (0x%X)"), kr);
	}

	return services;
}

/* Different from AppleSMC calls, we are going to get services quite often */
__attribute__((constructor))
void check_ioam_existance(void) {
	void *lib = dlopen("/usr/lib/libIOAccessoryManager.dylib", RTLD_LAZY);
	if (lib) {
		use_libioam = true;
	}
}

io_service_t acc_open_with_port(int port) {
	if (use_libioam)
		return IOAccessoryManagerGetServiceWithPrimaryPort(port);

	CFMutableDictionaryRef service;
	CFDictionaryRef matching;
	void *values;
	void *keys;
	int valuePtr;
	
	valuePtr = port;
	service = IOServiceMatching("IOAccessoryManager");
	keys = (void *)CFSTR("IOAccessoryPrimaryDevicePort");
	values = (void *)CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &valuePtr);
	matching = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&keys, (const void **)&values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionarySetValue(service, CFSTR("IOPropertyMatch"), matching);
	CFRelease(matching);
	CFRelease(keys);
	CFRelease(values);
	return IOServiceGetMatchingService(kIOMasterPortDefault, service);
}

static IOReturn copyDeviceInfo(io_connect_t connect, AccessoryInfo infoID, CFTypeRef *buf) {
	IOReturn kr = kIOReturnSuccess;
	if (use_libioam) {
		kr = IOAccessoryManagerCopyDeviceInfo(connect, infoID, buf);
	} else {
		bool accessory_mode = true;
		CFStringRef key = NULL;
		switch (infoID) {
			case kIOAMInterfaceDeviceSerialNumber:
				accessory_mode = false;
				key = CFSTR("IOAccessoryInterfaceDeviceSerialNumber");
				break;
			case kIOAMInterfaceModuleSerialNumber:
				accessory_mode = false;
				key = CFSTR("IOAccessoryInterfaceModuleSerialNumber");
				break;
			case kIOAMAccessorySerialNumber:    key = CFSTR("IOAccessoryAccessorySerialNumber"); break;
			case kIOAMAccessoryManufacturer:    key = CFSTR("IOAccessoryAccessoryManufacturer"); break;
			case kIOAMAccessoryName:            key = CFSTR("IOAccessoryAccessoryName"); break;
			case kIOAMAccessoryModelNumber:     key = CFSTR("IOAccessoryAccessoryModelNumber"); break;
			case kIOAMAccessoryFirmwareVersion: key = CFSTR("IOAccessoryAccessoryFirmwareVersion"); break;
			case kIOAMAccessoryHardwareVersion: key = CFSTR("IOAccessoryAccessoryHardwareVersion"); break;
			case kIOAMAccessoryPPID:            key = CFSTR("IOAccessoryAccessoryPPID"); break;
			default: kr = kIOReturnBadArgument;
		}
		if (kr == kIOReturnSuccess) {
			*buf = IORegistryEntryCreateCFProperty(connect, key, kCFAllocatorDefault, kNilOptions);
			if (buf) {
				kr = kIOReturnSuccess;
			} else {
				kr = checkIDBusAvailable(connect, accessory_mode);
			}
		}
	}
	return kr;
}

int get_accid(io_connect_t connect) {
	int accid = -1;
	if (use_libioam) {
		accid = IOAccessoryManagerGetAccessoryID(connect);
	} else {
		CFNumberRef number;
		number = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryID"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &accid)) {
			accid = -1;
		}
		if (number) CFRelease(number);
	}
	return accid;
}

bool get_acc_battery_pack_mode(io_connect_t connect) {
	if (use_libioam)
		return IOAccessoryManagerGetBatteryPackMode(connect);

	CFBooleanRef boolean = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryBatteryPack"), kCFAllocatorDefault, kNilOptions);

	bool result = (boolean == kCFBooleanTrue);
	if (boolean) CFRelease(boolean);

	return result;
}

int get_acc_allowed_features(io_connect_t connect) {
	int buffer = -1;
	CFNumberRef AllowedFeatures;

	AllowedFeatures = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerAllowedFeatures"), kCFAllocatorDefault, kNilOptions);
	if (AllowedFeatures) {
		if (!CFNumberGetValue(AllowedFeatures, kCFNumberSInt32Type, &buffer)) {
			DBGLOG(CFSTR("get_acc_allowed_features: Invalid"));
		}
	} else {
		DBGLOG(CFSTR("get_acc_allowed_features: None"));
	}
	if (AllowedFeatures) CFRelease(AllowedFeatures);

	return buffer;
}

int get_acc_port_type(io_connect_t connect) {
	int buffer = -1;
	CFNumberRef PortType;
	
	PortType = IORegistryEntryCreateCFProperty(connect, CFSTR("PortType"), kCFAllocatorDefault, kNilOptions);
	if (PortType) {
		if (!CFNumberGetValue(PortType, kCFNumberSInt32Type, &buffer)) {
			DBGLOG(CFSTR("get_acc_port_type: Invalid"));
		}
	} else {
		DBGLOG(CFSTR("get_acc_port_type: None"));
	}
	if (PortType) CFRelease(PortType);
	
	return buffer;
}

typedef struct {
	AccessoryInfo   key;
	void           *dest;
	size_t          len;
	
} AccQuery;
accessory_info_t get_acc_info(io_connect_t connect) {
	IOReturn     kr = kIOReturnSuccess;
	CFTypeRef    buffer = NULL;
	accessory_info_t info;
	
	memset(&info, 0, sizeof(info));

	AccQuery queries[] = {
		{kIOAMAccessorySerialNumber,    info.serial, sizeof(info.serial)},
		{kIOAMAccessoryManufacturer,    info.vendor, sizeof(info.vendor)},
		{kIOAMAccessoryName,            info.name,   sizeof(info.name)},
		{kIOAMAccessoryModelNumber,     info.model,  sizeof(info.model)},
		{kIOAMAccessoryFirmwareVersion, info.fwVer,  sizeof(info.fwVer)},
		{kIOAMAccessoryHardwareVersion, info.hwVer,  sizeof(info.hwVer)},
		{kIOAMAccessoryPPID,            info.PPID,   sizeof(info.PPID)},
	};
	
	for (size_t i = 0; i < sizeof(queries) / sizeof(queries[0]); i++) {
		kr = copyDeviceInfo(connect, queries[i].key, &buffer);
		if (kr != kIOReturnSuccess) {
			NSLog(CFSTR("get_acc_info(%d): %s"), queries[i].key, mach_error_string(kr));
			continue;
		}

		memset(queries[i].dest, 0, queries[i].len);

		/* We only handle Accessories, so they are all strings */
		if (buffer) {
			if (!CFStringGetCString((CFStringRef)buffer, queries[i].dest, queries[i].len, kCFStringEncodingUTF8)) {
				NSLog(CFSTR("get_acc_info(%d): CF Error"), queries[i].key);
				continue;
			}
			DBGLOG(CFSTR("get_acc_info(%d): got %s"), queries[i].key, (char *)queries[i].dest);
			CFRelease(buffer);
		}
	}

	return info;
}

accessory_powermode_t get_acc_powermode(io_connect_t connect) {
	accessory_powermode_t mode;

	memset(&mode, 0, sizeof(mode));

	if (use_libioam) {
		mode.mode = IOAccessoryManagerGetPowerMode(connect);
		mode.active = IOAccessoryManagerGetActivePowerMode(connect);
	} else {
		CFTypeRef property = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryPowerMode"), kCFAllocatorDefault, kNilOptions);
		SInt32 powerMode;
		if (!property || CFGetTypeID(property) != CFNumberGetTypeID() ||
		    !CFNumberGetValue((CFNumberRef)property, kCFNumberSInt32Type, &powerMode)) {
			mode.mode = 0;
		} else {
			mode.mode = powerMode;
		}
		if (property) CFRelease(property);

		property = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryActivePowerMode"), kCFAllocatorDefault, kNilOptions);
		if (!property || CFGetTypeID(property) != CFNumberGetTypeID() ||
		    !CFNumberGetValue((CFNumberRef)property, kCFNumberSInt32Type, &powerMode)) {
			mode.active = 0;
		} else {
			mode.active = powerMode;
		}
		if (property) CFRelease(property);
	}

	CFTypeRef supportedProperty = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessorySupportedPowerModes"), kCFAllocatorDefault, kNilOptions);
	if (supportedProperty && CFGetTypeID(supportedProperty) == CFArrayGetTypeID()) {
		CFArrayRef supported = (CFArrayRef)supportedProperty;
#if DEBUG
		printf("Powermodes: ");
		CFShow(supported);
#endif
		CFTypeRef limitsProperty = NULL;
		CFArrayRef limits = NULL;
		if (!use_libioam) {
			limitsProperty = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryPowerCurrentLimits"), kCFAllocatorDefault, kNilOptions);
			if (limitsProperty && CFGetTypeID(limitsProperty) == CFArrayGetTypeID()) {
				limits = (CFArrayRef)limitsProperty;
			}
		}

		const size_t supportedCapacity = sizeof(mode.supported) / sizeof(mode.supported[0]);
		CFIndex reportedCount = CFArrayGetCount(supported);
		for (CFIndex i = 0; i < reportedCount && mode.supported_cnt < supportedCapacity; i++) {
			CFTypeRef value = CFArrayGetValueAtIndex(supported, i);
			SInt32 powerMode;
			if (!value || CFGetTypeID(value) != CFNumberGetTypeID() ||
			    !CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &powerMode)) {
				continue;
			}

			size_t destinationIndex = mode.supported_cnt++;
			mode.supported[destinationIndex] = powerMode;
			if (powerMode >= kIOAMPowermodeOff && powerMode <= kIOAMPowermodeCount) {
				if (use_libioam) {
					mode.supported_lim[destinationIndex] = IOAccessoryManagerPowerModeCurrentLimit(connect, powerMode);
				} else if (limits) {
					CFIndex limitIndex = (CFIndex)powerMode - kIOAMPowermodeOff;
					if (limitIndex < CFArrayGetCount(limits)) {
						CFTypeRef limitValue = CFArrayGetValueAtIndex(limits, limitIndex);
						SInt32 currentLimit;
						if (limitValue && CFGetTypeID(limitValue) == CFNumberGetTypeID() &&
						    CFNumberGetValue((CFNumberRef)limitValue, kCFNumberSInt32Type, &currentLimit) &&
						    currentLimit >= 0) {
							mode.supported_lim[destinationIndex] = currentLimit;
						}
					}
				}
			}
		}
		if (limitsProperty) CFRelease(limitsProperty);
	}
	if (supportedProperty) CFRelease(supportedProperty);

	return mode;
}

accessory_sleeppower_t get_acc_sleeppower(io_connect_t connect) {
	accessory_sleeppower_t sleep;

	memset(&sleep, 0, sizeof(sleep));

	if (use_libioam) {
		sleep.supported = IOAccessoryManagerPowerDuringSleepIsSupported(connect);
		sleep.enabled = IOAccessoryManagerGetPowerDuringSleep(connect);
		sleep.limit = IOAccessoryManagerGetSleepPowerCurrentLimit(connect);
	} else {
		CFBooleanRef result;
		result = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerSleepPower"), kCFAllocatorDefault, kNilOptions);
		sleep.supported = (result != NULL);
		sleep.enabled = (result == kCFBooleanTrue);
		if (result) CFRelease(result);

		CFNumberRef number;
		number = (CFNumberRef)IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessorySleepPowerCurrentLimit"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &sleep.limit)) {
			sleep.limit = 0;
		}
		if (number) CFRelease(number);
	}

	return sleep;
}

bool get_acc_supervised(io_connect_t connect) {
	CFBooleanRef supervised;

	supervised = IORegistryEntryCreateCFProperty(connect, CFSTR("SupervisedAccessoryAttached"), kCFAllocatorDefault, kNilOptions);

	bool ret = (supervised == kCFBooleanTrue);
	if (supervised) CFRelease(supervised);

	return ret;
}

bool get_acc_supervised_transport_restricted(io_connect_t connect) {
	CFBooleanRef restricted;
	
	restricted = IORegistryEntryCreateCFProperty(connect, CFSTR("SupervisedTransportsRestricted"), kCFAllocatorDefault, kNilOptions);
	
	bool ret = (restricted == kCFBooleanTrue);
	if (restricted) CFRelease(restricted);
	
	return ret;
}

int32_t get_acc_type(io_connect_t connect) {
	if (use_libioam)
		return IOAccessoryManagerGetType(connect);

	CFNumberRef number;
	int32_t type = 0;
	number = (CFNumberRef)IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerType"), kCFAllocatorDefault, kNilOptions);
	if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &type)) {
		 type = 0;
	}
	if (number) CFRelease(number);

	return type;
}

IOReturn get_acc_digitalid(io_connect_t connect, void *digitalID) {
	IOReturn kr = kIOReturnSuccess;
	if (use_libioam)
		return IOAccessoryManagerGetDigitalID(connect, digitalID);
		
	CFDataRef data = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryDigitalID"), kCFAllocatorDefault, kNilOptions);

	if (data) {
		CFDataGetBytes(data, CFRangeMake(0, 6), digitalID);
		CFRelease(data);
		return kIOReturnSuccess;
	} else {
		kr = kIOReturnUnsupported;
		if ((get_acc_type(connect) & 0xF) != 0 ) {
			CFBooleanRef detect = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryDetect"), kCFAllocatorDefault, kNilOptions);
			kr = (detect == kCFBooleanTrue) ? kIOReturnNotReady : kIOReturnNotAttached;

			if (detect) CFRelease(detect);
		}
	}
	return kr;
}

IOReturn get_acc_usb_connstat(io_connect_t connect, accessory_usb_connstat_t *connstat) {
	IOReturn kr = kIOReturnSuccess;
	memset(connstat, 0, sizeof(accessory_usb_connstat_t));

	if (use_libioam) {
		int32_t buf;
		bool active;
		kr = IOAccessoryManagerGetUSBConnectType(connect, &buf, &active);
		if (kr == kIOReturnSuccess) {
			connstat->active = active;
			connstat->type = buf;
		}

		kr = IOAccessoryManagerGetUSBConnectTypePublished(connect, &buf, &active);
		if (kr == kIOReturnSuccess) {
			connstat->active = active;
			connstat->published_type = buf;
		}
	} else {
		CFMutableDictionaryRef properties;
		kr = IORegistryEntryCreateCFProperties(connect, &properties, kCFAllocatorDefault, kNilOptions);
		if (kr == kIOReturnSuccess) {
			CFNumberRef number = CFDictionaryGetValue(properties, CFSTR("IOAccessoryUSBConnectType"));
			if (number) {
				if (!CFNumberGetValue(number, kCFNumberSInt32Type, &(connstat->type)))
					connstat->type = -1;
			}
			number = CFDictionaryGetValue(properties, CFSTR("IOAccessoryUSBConnectTypePublished"));
			if (number) {
				if (!CFNumberGetValue(number, kCFNumberSInt32Type, &(connstat->published_type)))
					connstat->published_type = -1;
			}
			connstat->active = (CFDictionaryGetValue(properties, CFSTR("IOAccessoryUSBActive")) == kCFBooleanTrue);

			CFRelease(properties);
		}
	}
	return kr;
}

IOReturn get_acc_usb_voltage(io_connect_t connect, int32_t *voltage) {
	IOReturn kr = kIOReturnSuccess;
	if (use_libioam)
		return IOAccessoryManagerGetUSBChargingVoltage(connect, voltage);
	
	CFNumberRef number;
	number = (CFNumberRef)IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryUSBChargingVoltage"), kCFAllocatorDefault, kNilOptions);
	if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, voltage)) {
		*voltage = 0;
		kr = kIOReturnNotAttached;
	}
	if (number) CFRelease(number);
	
	return kr;
}

IOReturn get_acc_usb_ilim(io_connect_t connect, accessory_usb_ilim_t *ilim) {
	IOReturn kr = kIOReturnSuccess;
	IOReturn lim = 0, base = 0, offset = 0, max = 0;

	memset(ilim, 0, sizeof(accessory_usb_ilim_t));
	if (use_libioam) {
		lim = IOAccessoryManagerGetUSBCurrentLimit(connect, &(ilim->limit));
		base = IOAccessoryManagerGetUSBCurrentLimitBase(connect, &(ilim->base));
		offset = IOAccessoryManagerGetUSBCurrentLimitOffset(connect, &(ilim->offset));
		max = IOAccessoryManagerGetUSBCurrentLimitMaximum(connect, &(ilim->max));
	} else {
		CFNumberRef number;

		number = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryUSBCurrentLimit"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &(ilim->limit))) {
			lim = kIOReturnNotAttached;
		}
		if (number) CFRelease(number);

		number = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryUSBCurrentLimitBase"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &(ilim->base))) {
			base = kIOReturnNotAttached;
		}
		if (number) CFRelease(number);

		number = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryUSBCurrentLimitOffset"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &(ilim->offset))) {
			offset = kIOReturnNotFound;
		}
		if (number) CFRelease(number);

		number = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryUSBCurrentLimitMaximum"), kCFAllocatorDefault, kNilOptions);
		if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &(ilim->max))) {
			offset = kIOReturnNotFound;
		}
		if (number) CFRelease(number);
	}

	if ((lim == kIOReturnNotAttached) && (base == kIOReturnNotAttached) && (offset == kIOReturnNotFound) && (max == kIOReturnNotFound)) {
		kr = kIOReturnNotAttached;
	}
	
	return kr;
}

IOReturn get_acc_idsn(io_connect_t connect, long long *buf) {
	IOReturn kr;
	CFTypeRef number;
	kr = copyDeviceInfo(connect, kIOAMInterfaceDeviceSerialNumber, &number);
	if (kr == kIOReturnSuccess) {
		if (!CFNumberGetValue((CFNumberRef)number, kCFNumberSInt64Type, buf)) {
			kr = kIOReturnError;
		}
		CFRelease(number);
	}
	return kr;
}

IOReturn get_acc_msn(io_connect_t connect, void *buf) {
	IOReturn kr;
	CFTypeRef sn;
	kr = copyDeviceInfo(connect, kIOAMInterfaceModuleSerialNumber, &sn);
	if (kr == kIOReturnSuccess) {
		if (!CFStringGetCString(sn, buf, 32, kCFStringEncodingUTF8)) {
			kr = kIOReturnError;
		}
		CFRelease(sn);
	}
	return kr;
}

int get_acc_inductive_fw_mode(io_connect_t connect) {
	IOReturn kr = kIOReturnSuccess;
	int mode = -1;
	
	CFNumberRef number;
	number = (CFNumberRef)IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerInductiveFwMode"), kCFAllocatorDefault, kNilOptions);
	if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &mode)) {
		kr = kIOReturnNotAttached;
	}
	if (number) CFRelease(number);

	return mode;
}

int get_acc_inductive_region_code(io_connect_t connect) {
	IOReturn kr = kIOReturnSuccess;
	int code = -1;
	
	CFNumberRef number;
	number = (CFNumberRef)IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerInductiveRegionCodeData"), kCFAllocatorDefault, kNilOptions);
	if (!number || !CFNumberGetValue(number, kCFNumberSInt32Type, &code)) {
		kr = kIOReturnNotAttached;
	}
	if (number) CFRelease(number);
	
	return code;
}

bool get_acc_inductive_timeout(io_connect_t connect) {
	CFBooleanRef timeout;
	
	timeout = IORegistryEntryCreateCFProperty(connect, CFSTR("IOAccessoryManagerInductiveAuthTimedOut"), kCFAllocatorDefault, kNilOptions);
	
	bool ret = (timeout == kCFBooleanTrue);
	if (timeout) CFRelease(timeout);
	
	return ret;
}
