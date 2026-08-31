#import <Foundation/Foundation.h>

#if __has_include(<IOKit/hid/IOHIDDeviceKeys.h>)
#include <IOKit/hid/IOHIDDeviceKeys.h>
#else
#define kIOHIDProductKey "Product"
#define kIOHIDLocationIDKey "LocationID"
#define kIOHIDPrimaryUsagePageKey "PrimaryUsagePage"
#define kIOHIDPrimaryUsageKey "PrimaryUsage"
#endif

#if __has_include(<IOKit/hid/IOHIDUsageTables.h>)
#include <IOKit/hid/IOHIDUsageTables.h>
#else
#define kHIDPage_Sensor 0x20
#define kHIDUsage_Snsr_Environmental_AtmosphericPressure 0x31
#endif

#if __has_include(<IOKit/hid/AppleHIDUsageTables.h>)
#include <IOKit/hid/AppleHIDUsageTables.h>
#else
#define kHIDPage_AppleVendor 0xFF00
#define kHIDUsage_AppleVendor_TemperatureSensor 0x0005
#define kHIDUsage_AppleVendor_Accelerometer 0x03
#define kHIDUsage_AppleVendor_Gyro 0x09
#define kHIDUsage_AppleVendor_Compass 0x0A
#define kHIDUsage_AppleVendor_Jarvis 0x3E
#endif

#if __has_include(<IOKit/hid/IOHIDEventTypes.h>)
#include <IOKit/hid/IOHIDEventTypes.h>
#else
#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperatureLevel (kIOHIDEventTypeTemperature << 16)
#endif

#if __has_include(<IOKit/hid/IOHIDEvent.h>)
#include <IOKit/hid/IOHIDEvent.h>
#else
CF_IMPLICIT_BRIDGING_ENABLED
#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif
typedef struct __IOHIDEvent * IOHIDEventRef;
typedef uint32_t IOHIDEventField;

extern IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef, IOHIDEventField);
CF_IMPLICIT_BRIDGING_DISABLED
#endif

#if __has_include(<IOKit/hidsystem/IOHIDEventSystemClient.h>)
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#else
CF_IMPLICIT_BRIDGING_ENABLED
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient * IOHIDEventSystemClientRef;

extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
CF_IMPLICIT_BRIDGING_DISABLED
#endif

// Sadly these are SPI
#if __has_include(<IOKit/hid/IOHIDEventSystemClient.h>) && 0
#include <IOKit/hid/IOHIDEventSystemClient.h>
#else
CF_IMPLICIT_BRIDGING_ENABLED
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, uint32_t client_type, CFDictionaryRef attrs);
CF_IMPLICIT_BRIDGING_DISABLED
#endif

#if __has_include(<IOKit/hidsystem/IOHIDServiceClient.h>)
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#else
CF_IMPLICIT_BRIDGING_ENABLED
typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient * IOHIDServiceClientRef;

extern CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
CF_IMPLICIT_BRIDGING_DISABLED
#endif
// Should be in IOHIDServiceClient.h but nope
CF_IMPLICIT_BRIDGING_ENABLED
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
CF_IMPLICIT_BRIDGING_DISABLED

BOOL NSStringEquals4CC(uint32_t fourcc, NSString *string) {
	if ([string length] != 4) {
		return NO;
	}
	
	// Convert fourcc to 4-character C string
	char fourccStr[5] = {
		(char)((fourcc >> 24) & 0xFF),
		(char)((fourcc >> 16) & 0xFF),
		(char)((fourcc >> 8) & 0xFF),
		(char)(fourcc & 0xFF),
		'\0'
	};
	
	return [string isEqualToString:[NSString stringWithCString:fourccStr encoding:NSUTF8StringEncoding]];
}

// XXX: Consider migrate to pure C
NSDictionary *getTemperatureHIDData(void) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
	if (!client)
		return nil;

    NSDictionary *matching = @{
        @kIOHIDPrimaryUsagePageKey: @(kHIDPage_AppleVendor),
        @kIOHIDPrimaryUsageKey: @(kHIDUsage_AppleVendor_TemperatureSensor),
    };
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);

	NSArray *ret = CFBridgingRelease(IOHIDEventSystemClientCopyServices(client));
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	for (id serviceClient in ret) {
		NSString *prod = CFBridgingRelease(IOHIDServiceClientCopyProperty((IOHIDServiceClientRef)serviceClient, CFSTR(kIOHIDProductKey)));
		if (!prod)
			continue;
	    IOHIDEventRef event = IOHIDServiceClientCopyEvent((IOHIDServiceClientRef)serviceClient, kIOHIDEventTypeTemperature, 0, 0);
		if (!event)
			continue;
		dict[prod] = [NSNumber numberWithDouble:IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)];
		CFRelease((CFTypeRef)event);
	}
	CFRelease(client);
	return dict;
}

float getTemperatureHIDAt(NSString *locID) {
	IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
	if (!client)
		return -1;
	
	NSDictionary *matching = @{
		@kIOHIDPrimaryUsagePageKey: @(kHIDPage_AppleVendor),
		@kIOHIDPrimaryUsageKey: @(kHIDUsage_AppleVendor_TemperatureSensor),
	};
	IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);

	float temp = -1;
	NSArray *ret = CFBridgingRelease(IOHIDEventSystemClientCopyServices(client));
	for (id serviceClient in ret) {
		NSNumber *location = CFBridgingRelease(IOHIDServiceClientCopyProperty((IOHIDServiceClientRef)serviceClient, CFSTR(kIOHIDLocationIDKey)));
		if (!location || !NSStringEquals4CC([location unsignedIntValue], locID))
			continue;
		IOHIDEventRef event = IOHIDServiceClientCopyEvent((IOHIDServiceClientRef)serviceClient, kIOHIDEventTypeTemperature, 0, 0);
		if (!event)
			continue;
		
		temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel);
		CFRelease((CFTypeRef)event);
	}
	CFRelease(client);
	return temp;
}

/* This has to be polished
uint32_t getMajorSkinTemperatureLocationOf(NSString *name) {
	// A13, iPhone 12, iPhone 12 Pro, iPhone 12 Pro Max
	NSArray *TSRM = @[@"t8030", @"D53", @"D54"];
	for (int i = 0; i < TSRM.count; i++) {
		if ([name rangeOfString:TSRM[i] options:NSCaseInsensitiveSearch].location != NSNotFound)
			return 'TSRM';
	}

	// iPad8,9
	// iPad8,10
	// iPad8,11
	// iPad8,12
	// iPad13,1
	// iPad13,2
	// iPad13,18
	// iPad13,19
	NSArray *TSBM = @[@"J417", @"J418", @"J420", @"J421", @"J307", @"J308", @"J271", @"J272"];
	for (int i = 0; i < TSBM.count; i++) {
		if ([name rangeOfString:TSBM[i] options:NSCaseInsensitiveSearch].location != NSNotFound)
			return 'TSBM';
	}

	// iPad12,1
	// iPad12,2
	// and bunch of apple watches
	NSArray *TSBH = @[@"J181", @"J182", @"N157s", @"N157b", @"N158s", @"N158b", @"N187s", @"N187b", @"N188s", @"N188b", @"N143s", @"N143b", @"N197s", @"N197b", @"N198s", @"N198b", @"N199"];
	for (int i = 0; i < TSBH.count; i++) {
		if ([name rangeOfString:TSBH[i] options:NSCaseInsensitiveSearch].location != NSNotFound)
			return 'TSBH';
	}

	// ACSK Products has no skin sensor
	NSArray *acsk_prods = @[@"D16", @"D17", @"D27", @"D28", @"D49", @"D63", @"D64", @"D73", @"D74", @"J310", @"J311", @"J407", @"J408", @"J517", @"J518", @"J522", @"J523"];
	for (int i = 0; i < acsk_prods.count; i++) {
		if ([name rangeOfString:acsk_prods[i] options:NSCaseInsensitiveSearch].location != NSNotFound)
			return 0;
	}

	// iPhone 12 mini and t8015 and forward
	return 'TSBE';
}
*/

NSArray *getHIDSkinModelsOf(NSString *product) {
	/* Keep the dispatch_once result in function-static storage.  A block-local
	 * variable would be nil on every call after the first one because the
	 * once-token skips the initializer, making repeated UI refreshes lose the
	 * Device Avg. sensor row. */
	static NSDictionary *skinModelsByProduct = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		// define each value array once
		NSArray *TSLE   = @[@"TSLE"];
		NSArray *TSBH   = @[@"TSBH"];
		NSArray *BH_BR  = @[@"TSBH", @"TSBR"];
		NSArray *BH_FD  = @[@"TSBH", @"TSFD"];
		NSArray *BH_FD_BR = @[@"TSBH", @"TSFD", @"TSBR"];
		NSArray *BM_FD_FL_BQ_FG = @[@"TSBM", @"TSFD", @"TSFL", @"TSBQ", @"TSFG"];
		NSArray *BM_FD_FL_BQ_FG_BR = @[@"TSBM", @"TSFD", @"TSFL", @"TSBQ", @"TSFG", @"TSBR"];
		NSArray *BM_FD_FL_BQ = @[@"TSBM", @"TSFD", @"TSFL", @"TSBQ"];
		NSArray *BH_cH_dH_FD = @[@"TSBH", @"TScH", @"TSdH", @"TSFD"];
		NSArray *FH_FL_FD_BH_BE_BR_FC = @[@"TSFH", @"TSFL", @"TSFD", @"TSBH", @"TSBE", @"TSBR", @"TSFC"];
		NSArray *FH_FL_FD_BH_BL_BR_FC = @[@"TSFH", @"TSFL", @"TSFD", @"TSBH", @"TSBL", @"TSBR", @"TSFC"];
		NSArray *BR_BH_FC_FD = @[@"TSBR", @"TSBH", @"TSFC", @"TSFD"];
		NSArray *FP     = @[@"TSFP"];
		NSArray *FP_BM  = @[@"TSFP", @"TSBM"];
		NSArray *Wu     = @[@"TSWu"];
		NSArray *BE_RM_RR_FC_Ba_FL_BQ = @[@"TSBE", @"TSRM", @"TSRR", @"TSFC", @"TSBa", @"TSFL", @"TSBQ"];
		NSArray *BE_RM_RR_FC_Ba_FL_RQ = @[@"TSBE", @"TSRM", @"TSRR", @"TSFC", @"TSBa", @"TSFL", @"TSRQ"];
		NSArray *BE_RM_RR_FC_FD_Ba_FL_RQ = @[@"TSBE", @"TSRM", @"TSRR", @"TSFC", @"TSFD", @"TSBa", @"TSFL", @"TSRQ"];
		NSArray *BE_RM_RR_FC_FD_Ba_FL_BR = @[@"TSBE", @"TSRM", @"TSRR", @"TSFC", @"TSFD", @"TSBa", @"TSFL", @"TSBR"];
		NSArray *BE_BQ_RM_RR_FC_FL_Ba = @[@"TSBE", @"TSBQ", @"TSRM", @"TSRR", @"TSFC", @"TSFL", @"TSBa"];
		NSArray *BE_BQ_RM_RR_FR_LR_FC_FL_FD_Ba = @[@"TSBE", @"TSBQ", @"TSRM", @"TSRR", @"TSFR", @"TSLR", @"TSFC", @"TSFL", @"TSFD", @"TSBa"];
		NSArray *BE_BQ_RM_RR_BR_FR_LR_FC_FL_FD_Ba = @[@"TSBE", @"TSBQ", @"TSRM", @"TSRR", @"TSBR", @"TSFR", @"TSLR", @"TSFC", @"TSFL", @"TSFD", @"TSBa"];
		
		// helper to add many keys for one value
		NSMutableDictionary *dict = [NSMutableDictionary new];
		void (^add)(NSArray *, NSArray *) = ^(NSArray *keys, NSArray *val){
			for (NSString *k in keys) dict[k] = val;
		};
		
		add(@[@"J42d",@"J105a",@"J305"],           TSLE);
		add(@[@"J81",@"J96",@"J98a"],               TSBH);
		add(@[@"J82",@"J97",@"J99a"],               BH_BR);
		add(@[@"J127",@"J207",@"J120",@"J71s",@"J71t",@"J71b",@"J171",@"J171a",@"J181"], BH_FD);
		add(@[@"J128",@"J208",@"J121",@"J72s",@"J72t",@"J72b",@"J172",@"J172a",@"J182"], BH_FD_BR);
		add(@[@"J307",@"J317",@"J317x",@"J320",@"J320x",@"J417",@"J420"], BM_FD_FL_BQ_FG);
		add(@[@"J308",@"J318",@"J318x",@"J321",@"J321x",@"J418",@"J421"], BM_FD_FL_BQ_FG_BR);
		add(@[@"J210",@"J217",@"J271"],             BM_FD_FL_BQ);
		add(@[@"J211",@"J218",@"J272"],             [BM_FD_FL_BQ arrayByAddingObject:@"TSBR"]);
		add(@[@"N27d",@"N28d",@"N74",@"N75"],        BH_cH_dH_FD);
		add(@[@"N111s",@"N111b",@"N121s",@"N121b",@"N131s",@"N131b",@"N141s",@"N141b",@"N144s",@"N144b",
			  @"N146s",@"N146b",@"N157s",@"N157b",@"N158s",@"N158b",@"N187s",@"N187b",@"N188s",@"N188b",
			  @"N143s",@"N143b",@"N197s",@"N197b",@"N198s",@"N198b",@"N199"], BH_FD);
		add(@[@"N112"],                            FH_FL_FD_BH_BE_BR_FC);
		add(@[@"N66",@"N66m",@"N71",@"N71m"],       FH_FL_FD_BH_BL_BR_FC);
		add(@[@"N69",@"N69u"],                      BR_BH_FC_FD);
		add(@[@"D10",@"D101",@"D11",@"D111"],       FH_FL_FD_BH_BE_BR_FC);
		add(@[@"B238",@"B238a"],                    FP);
		add(@[@"B520"],                             FP_BM);
		add(@[@"B620"],                             Wu);
		add(@[@"D20",@"D201",@"D21",@"D211"],       BE_RM_RR_FC_Ba_FL_BQ);
		add(@[@"D22",@"D221"],                      BE_RM_RR_FC_Ba_FL_RQ);
		add(@[@"D331",@"D331p"],                    BE_RM_RR_FC_FD_Ba_FL_RQ);
		add(@[@"D321",@"N841"],                     BE_RM_RR_FC_FD_Ba_FL_BR);
		add(@[@"D79"],                              BE_BQ_RM_RR_FC_FL_Ba);
		add(@[@"D421",@"D431",@"N104"],             BE_BQ_RM_RR_FR_LR_FC_FL_FD_Ba);
		add(@[@"D52g",@"D53g",@"D53p",@"D54p"],     BE_BQ_RM_RR_BR_FR_LR_FC_FL_FD_Ba);
		
		skinModelsByProduct = dict.copy;
	});
	
	NSArray *models = skinModelsByProduct[product];
	return models ?: @[];
}

static int GetTemperatureFromDict(CFDictionaryRef dict) {
	if (dict == NULL) {
		return -1;
	}

	// kAppleTemperatureDictionaryKey normally only one member
	CFIndex count = CFDictionaryGetCount(dict);
	if (count != 1) {
		return -1;
	}

	const void *keys[1];
	const void *values[1];
	CFDictionaryGetKeysAndValues(dict, keys, values);
	
	CFNumberRef num = (CFNumberRef)values[0];
	if (num == NULL || CFGetTypeID(num) != CFNumberGetTypeID()) {
		return -1;
	}
	
	int result = 0;
	if (!CFNumberGetValue(num, kCFNumberIntType, &result)) {
		return -1;
	}
	
	return result;
}

float getSensorTemperature(int page, int usage) {
	// kIOHIDEventSystemClientTypeMonitor
	IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 1, NULL);
	if (!client) return -1;

	float ret = -1;
	void *keys[2], *values[2];
	CFNumberRef cfPage, cfUsage;
	CFArrayRef services = NULL;
	keys[0] = (void *)CFSTR(kIOHIDPrimaryUsagePageKey);
	keys[1] = (void *)CFSTR(kIOHIDPrimaryUsageKey);\
	
	cfPage = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page);
	cfUsage = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage);
	values[0] = (void *)cfPage;
	values[1] = (void *)cfUsage;
	
	CFDictionaryRef matchingDict = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if (matchingDict) {
		IOHIDEventSystemClientSetMatching(client, matchingDict);
		CFRelease(matchingDict);

		services = IOHIDEventSystemClientCopyServices(client);
		CFIndex count;
		if (services && ((void)(count = CFArrayGetCount(services)), count > 0)) {
			int i = 0;
			ret = 0;
			// Even we do a loop here, the count should always be one
			while (i < count) {
				IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
				// kAppleTemperatureDictionaryKey
				CFDictionaryRef dict = IOHIDServiceClientCopyProperty(service, CFSTR("AppleVoltageDictionary"));
				if (dict) {
					int num = GetTemperatureFromDict(dict);
					if (num != -1) {
						ret += (float)num / 100.0f;
					}
					CFRelease(dict);
				}
				i++;
			}
			ret /= count;
			CFRelease(services);
		}
	}

	CFRelease(cfPage);
	CFRelease(cfUsage);
	CFRelease(client);

	return ret;
}

static int sensorUsages[] = {
	kHIDUsage_AppleVendor_Accelerometer,
	kHIDUsage_AppleVendor_Gyro,
	kHIDUsage_AppleVendor_Compass,
	/* kHIDUsage_AppleVendor_ProximitySensor some device seems having temp on this sensor */
	/* kHIDUsage_AppleVendor_Jarvis seems the legacy compass sensor */
	kHIDUsage_Snsr_Environmental_AtmosphericPressure,
	/* kHIDUsage_Snsr_Environmental_Humidity seems only on HomePods, we can enable this once Battman running on HomePods */
};
#ifdef _C
#undef _C
#endif
#define _C(x) x
static char *sensorNames[] = {
	_C("Accelerometer"),
	_C("Gyroscope"),
	_C("Compass"),
	/* "Proximity Sensor" */
	/* "Compass (Jarvis)" */
	_C("Atmos Pressure Sensor"),
	/* "Humidity Sensor" */
};

NSDictionary *getSensorTemperatures(void) {
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	
	@autoreleasepool {
		for (size_t i = 0; i < (sizeof(sensorUsages) / sizeof(sensorUsages[0])); i++) {
			int page = kHIDPage_AppleVendor;
			if (i > 2)
				page = kHIDPage_Sensor;
			
			float temp = getSensorTemperature(page, sensorUsages[i]);
			if (temp && temp != -1) {
				NSString *name = [NSString stringWithCString:sensorNames[i] encoding:NSUTF8StringEncoding];
				[dict setValue:[NSNumber numberWithDouble:temp] forKey:name];
			}
		}
	}
	
	return dict;
}

float getSensorAvgTemperature(void) {
	// These are all known sensors with temperatures on iOS devices (except kHIDUsage_AppleVendor_TemperatureSensor)
	// FIXME: use getSensorTemperatures
	float ret = 0;
	int cnt = 0;
	for (size_t i = 0; i < (sizeof(sensorUsages) / sizeof(sensorUsages[0])); i++) {
		int page = kHIDPage_AppleVendor;
		if (i > 2)
			page = kHIDPage_Sensor;

		float temp = getSensorTemperature(page, sensorUsages[i]);
		if (temp && temp != -1) {
			ret += temp;
			cnt++;
		}
	}
	if (cnt)
		return (ret /= cnt);

	return -1;
}
