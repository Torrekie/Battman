//
//  NSObject+UPSMonitor.h
//  Battman
//
//  Created by Torrekie on 2025/6/3.
//

#import "iokitextern.h"
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#if __has_include(<IOKit/hid/AppleHIDUsageTables.h>)
#include <IOKit/hid/AppleHIDUsageTables.h>
#else
#define kHIDPage_AppleVendor 0xFF00
#define kHIDUsage_AppleVendor_AccessoryBattery 0x0014
#endif
#if __has_include(<IOKit/hid/IOHIDUsageTables.h>)
#include <IOKit/hid/IOHIDUsageTables.h>
#else
#define kHIDPage_PowerDevice 0x0084
#define kHIDPage_BatterySystem 0x0085
#define kHIDUsage_PD_PeripheralDevice 0x0006
#define kHIDUsage_BS_PrimaryBattery 0x002E
#endif
#if __has_include(<IOKit/hid/IOHIDKeys.h>)
#include <IOKit/hid/IOHIDKeys.h>
#else
#define kIOFirstMatchNotification "IOServiceFirstMatch"
#define kIOHIDDeviceKey "IOHIDDevice"
#define kIOHIDDeviceUsagePageKey "DeviceUsagePage"
#define kIOHIDDeviceUsageKey "DeviceUsage"
#define kIOHIDDeviceUsagePairsKey "DeviceUsagePairs"
#endif
#if __has_include(<IOKit/ps/IOUPSPlugIn.h>)
#include <IOKit/ps/IOUPSPlugIn.h>
#else

#define kIOMessageServiceIsTerminated 0xe0000010
#define kIOCFPlugInInterfaceID CFUUIDGetConstantUUIDWithBytes(NULL,	\
0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,			\
0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
#define kIOUPSPlugInTypeID CFUUIDGetConstantUUIDWithBytes(NULL, 	\
0x40, 0xa5, 0x7a, 0x4e, 0x26, 0xa0, 0x11, 0xd8,			\
0x92, 0x95, 0x00, 0x0a, 0x95, 0x8a, 0x2c, 0x78)
#define kIOUPSPlugInInterfaceID_v140 CFUUIDGetConstantUUIDWithBytes(NULL, 	\
0xe6, 0xe, 0x7, 0x99, 0x9a, 0xa6, 0x49, 0xdf,               \
0xb5, 0x5b, 0xa5, 0xc9, 0x4b, 0xa0, 0x7a, 0x4a)
#define kIOUPSPlugInInterfaceID CFUUIDGetConstantUUIDWithBytes(NULL, 	\
0x63, 0xf8, 0xbf, 0xc4, 0x26, 0xa0, 0x11, 0xd8, 			\
0x88, 0xb4, 0x0, 0xa, 0x95, 0x8a, 0x2c, 0x78)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

typedef void (*IOUPSEventCallbackFunction)
(void *	 		target,
 IOReturn 		result,
 void * 			refcon,
 void * 			sender,
 CFDictionaryRef  event);

#pragma clang diagnostic pop

#define IOUPSPLUGINBASE							\
IOReturn (*getProperties)(	void * thisPointer, 			\
CFDictionaryRef * properties);		\
IOReturn (*getCapabilities)(void * thisPointer, 			\
CFSetRef * capabilities);		\
IOReturn (*getEvent)(	void * thisPointer, 			\
CFDictionaryRef * event);		\
IOReturn (*setEventCallback)(void * thisPointer, 			\
IOUPSEventCallbackFunction callback,	\
void * callbackTarget,  		\
void * callbackRefcon);			\
IOReturn (*sendCommand)(	void * thisPointer, 			\
CFDictionaryRef command)

#define IOUPSPLUGIN_V140							\
IOReturn (*createAsyncEventSource)(void * thisPointer,      \
CFTypeRef * source)


typedef struct IOUPSPlugInInterface {
	IUNKNOWN_C_GUTS;
	IOUPSPLUGINBASE;
} IOUPSPlugInInterface;

typedef struct IOUPSPlugInInterface_v140 {
	IUNKNOWN_C_GUTS;
	IOUPSPLUGINBASE;
	IOUPSPLUGIN_V140;
} IOUPSPlugInInterface_v140;
#endif

#ifndef USE_NEW_UPSMONITOR
#define USE_NEW_UPSMONITOR 1
#endif

__BEGIN_DECLS

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
typedef struct UPSData {
	uint64_t                    regID;
	io_object_t                 notification;          // returned by IOServiceAddInterestNotification
	IOUPSPlugInInterface **     upsPlugInInterface;    // the v140 or old plugin Interface
	CFDictionaryRef             upsProperties;         // retained via getProperties
	CFDictionaryRef             upsEvent;              // retained via getEvent
	CFSetRef                    upsCapabilities;       // retained via getCapabilities
	CFRunLoopSourceRef          upsEventSource;        // from createAsyncEventSource
	CFRunLoopTimerRef           upsEventTimer;         // from createAsyncEventSource
} UPSData;

typedef UPSData * UPSDataRef;

typedef struct {
	UPSDataRef  *items;
	size_t      count;
	size_t      capacity;
} UPSDeviceSet;

typedef struct ups_batt {
	int current_capacity;
	int max_capacity;
	int batt_charging_current;
	int batt_charging_voltage;
	int current;
	int voltage;
	int cycle_count;
	int device_color;
	int incoming_current;
	int incoming_voltage;
	int charging;
	int temperature;
	int time_to_empty;
	int time_to_full;
} ups_batt_t;

extern UPSDeviceSet *gAllUPSDevices;

void PrintAllUPSDevices(void);
UPSDataRef UPSDeviceMatchingVendorProduct(int vid, int pid);
ups_batt_t ups_battery_info(UPSDataRef device);

#pragma clang diagnostic pop

__END_DECLS

#ifdef __OBJC__
NS_ASSUME_NONNULL_BEGIN

@interface UPSMonitor : NSObject
+ (void)startWatchingUPS;
+ (void)stopWatchingUPS;
+ (void)appDidEnterBackground:(NSNotification *)note;
+ (void)appWillEnterForeground:(NSNotification *)note;
+ (void)cleanupAllResources;
@end

NS_ASSUME_NONNULL_END
#endif
