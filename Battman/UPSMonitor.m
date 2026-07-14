//
//  UPSMonitor.m
//  Battman
//
//  Created by Torrekie on 2025/6/3.
//  This is exactly what ioupsd does, but ported to work with iOS App
//

#import "common.h"
#import "UPSMonitor.h"

#include <pthread/pthread.h>
#include <syslog.h>
#import <UIKit/UIKit.h>

#if !USE_NEW_UPSMONITOR

static bool UPSWatching = false;
static CFRunLoopRef   gBackgroundRunLoop = NULL;

static pthread_t gUPSWatchThread = NULL;
static bool gTerminationInProgress = false;

void suspendPowerEventMonitoring(void);
void resumePowerEventMonitoring(void);
void cleanupPowerEventMonitoring(void);

@implementation UPSMonitor

static IONotificationPortRef    gNotifyPort     = NULL;
static io_iterator_t            gAddedIter      = MACH_PORT_NULL;

UPSDeviceSet *gAllUPSDevices = NULL;

#pragma mark gAllUPSDevices

// Create an empty set
static UPSDeviceSet *UPSDeviceSetCreate(void) {
	UPSDeviceSet *set = calloc(1, sizeof(*set));
	if (!set) return NULL;
	set->capacity = 1;
	set->items    = calloc(set->capacity, sizeof(UPSDataRef));
	return set;
}

// Free the set itself (not the UPSDataRefs; you should free those separately)
static void UPSDeviceSetDestroy(UPSDeviceSet *set) {
	if (!set) return;
	free(set->items);
	free(set);
}

// Returns true if already present
static bool UPSDeviceSetContains(UPSDeviceSet *set, UPSDataRef ptr) {
	for (size_t i = 0; i < set->count; i++) {
		if (set->items[i]->regID == ptr->regID) return true;
	}
	return false;
}

// Add ptr if not already in the set
static bool UPSDeviceSetAdd(UPSDeviceSet *set, UPSDataRef ptr) {
	if (UPSDeviceSetContains(set, ptr)) return false;
	if (set->count == set->capacity) {
		size_t newCap = set->capacity * 2;
		UPSDataRef *newArr = realloc(set->items, newCap * sizeof(UPSDataRef));
		if (!newArr) return false;
		set->items    = newArr;
		set->capacity = newCap;
	}
	set->items[set->count++] = ptr;
	return true;
}

// Remove ptr if present; shifts tail elements down
static bool UPSDeviceSetRemove(UPSDeviceSet *set, UPSDataRef ptr) {
	for (size_t i = 0; i < set->count; i++) {
		if (set->items[i]->regID == ptr->regID) {
			memmove(&set->items[i],
					&set->items[i+1],
					(set->count - i - 1) * sizeof(UPSDataRef));
			set->count--;
			return true;
		}
	}
	return false;
}

// Number of items
static size_t UPSDeviceSetCount(UPSDeviceSet *set) {
	return set ? set->count : 0;
}

// Copy all items into user-supplied buffer (must be at least count() in size)
static void UPSDeviceSetGetAll(UPSDeviceSet *set, UPSDataRef *outBuffer) {
	if (!set || !outBuffer) return;
	memcpy(outBuffer, set->items, set->count * sizeof(UPSDataRef));
}

static void
FreeUPSData(UPSDataRef upsDataRef)
{
	if (upsDataRef == NULL) return;

	if (upsDataRef->upsEventSource) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), upsDataRef->upsEventSource, kCFRunLoopDefaultMode);
		CFRelease(upsDataRef->upsEventSource);
		upsDataRef->upsEventSource = NULL;
	}
	if (upsDataRef->upsEventTimer) {
		CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), upsDataRef->upsEventTimer, kCFRunLoopDefaultMode);
		CFRelease(upsDataRef->upsEventTimer);
		upsDataRef->upsEventTimer = NULL;
	}

	if (upsDataRef->upsPlugInInterface) {
		(*upsDataRef->upsPlugInInterface)->Release(upsDataRef->upsPlugInInterface);
		upsDataRef->upsPlugInInterface = NULL;
	}

	if (upsDataRef->notification != MACH_PORT_NULL) {
		IOObjectRelease(upsDataRef->notification);
		upsDataRef->notification = MACH_PORT_NULL;
	}

	free(upsDataRef);
}

void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument ) {
	UPSDataRef upsData = (UPSDataRef)refCon;
	if (upsData == NULL) {
		return;
	}
	
	if (messageType == kIOMessageServiceIsTerminated) {
		UPSDeviceSetRemove(gAllUPSDevices, upsData);
		FreeUPSData(upsData);
	}
}

static void
ProcessUPSEventSource(CFTypeRef typeRef, CFRunLoopTimerRef * pTimer, CFRunLoopSourceRef * pSource)
{
	if ( CFGetTypeID(typeRef) == CFRunLoopTimerGetTypeID() ) {
		*pTimer = (CFRunLoopTimerRef)typeRef;
	}
	else if ( CFGetTypeID(typeRef) == CFRunLoopSourceGetTypeID() ) {
		*pSource = (CFRunLoopSourceRef)typeRef;
	}
}

static void
UPSDeviceAdded(void *refCon, io_iterator_t iterator)
{
	io_object_t             upsDevice           = MACH_PORT_NULL;
	
	while ( (upsDevice = IOIteratorNext(iterator)) ) {
		DBGLOG(@"[UPSMonitor] UPSDevice Got");
		IOCFPlugInInterface **    plugInInterface = NULL;
		IOUPSPlugInInterface_v140 **   upsPlugInInterface  = NULL;
		SInt32                    score           = 0;
		IOReturn                  kr;
		HRESULT                   result;
		CFTypeRef typeRef = NULL;

		UPSDataRef upsDataRef = calloc(1, sizeof(UPSData));
		if (!upsDataRef) {
			IOObjectRelease(upsDevice);
			continue;
		}

		uint64_t entryID = 0;
		IORegistryEntryGetRegistryEntryID(upsDevice, &entryID);
		upsDataRef->regID              = entryID;
		upsDataRef->notification       = MACH_PORT_NULL;
		upsDataRef->upsPlugInInterface = NULL;
		upsDataRef->upsProperties      = NULL;
		upsDataRef->upsCapabilities    = NULL;
		upsDataRef->upsEvent           = NULL;
		upsDataRef->upsEventSource     = NULL;
		upsDataRef->upsEventTimer      = NULL;

		// Create the CF plugin for this device
		kr = IOCreatePlugInInterfaceForService(upsDevice, kIOUPSPlugInTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
		
		if (kr != kIOReturnSuccess)
			goto CLEANUP_PARTIAL;
		
		// Grab the new v140 interface
		result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUPSPlugInInterfaceID_v140), (LPVOID)&upsPlugInInterface);
		
		if ( ( result == S_OK ) && upsPlugInInterface ) {
			kr = (*upsPlugInInterface)->createAsyncEventSource(upsPlugInInterface, &typeRef);
			
			if ((kr != kIOReturnSuccess) || !typeRef)
				goto CLEANUP_PARTIAL;
			
			if (CFGetTypeID(typeRef) == CFArrayGetTypeID()) {
				CFArrayRef arrayRef = (CFArrayRef)typeRef;
				CFIndex     count   = CFArrayGetCount(arrayRef);
				
				for (CFIndex i = 0; i < count; i++) {
					CFTypeRef element = CFArrayGetValueAtIndex(arrayRef, i);
					ProcessUPSEventSource(element, &upsDataRef->upsEventTimer, &upsDataRef->upsEventSource);
				}
			}
			else {
				ProcessUPSEventSource(typeRef, &upsDataRef->upsEventTimer, &upsDataRef->upsEventSource);
			}
			
			if (upsDataRef->upsEventSource) {
				CFRunLoopAddSource(CFRunLoopGetCurrent(), upsDataRef->upsEventSource, kCFRunLoopDefaultMode);
			}
			if (upsDataRef->upsEventTimer) {
				CFRunLoopAddTimer(CFRunLoopGetCurrent(), upsDataRef->upsEventTimer, kCFRunLoopDefaultMode);
			}
			
			if ( typeRef )
				CFRelease(typeRef);
		}
		// Couldn't grab the new interface.  Fallback on the old.
		else
		{
			result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUPSPlugInInterfaceID), (LPVOID)&upsPlugInInterface);
		}
		
		// Got the interface
		if ( ( result == S_OK ) && upsPlugInInterface )
		{
			upsDataRef->upsPlugInInterface = (IOUPSPlugInInterface **)upsPlugInInterface;

			(*plugInInterface)->Release(plugInInterface);
			plugInInterface = NULL;

			kr = (*upsPlugInInterface)->getProperties(upsPlugInInterface, &upsDataRef->upsProperties);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsProperties)) {
				goto CLEANUP_PARTIAL;
			}
			
			kr = (*upsPlugInInterface)->getCapabilities(upsPlugInInterface, &upsDataRef->upsCapabilities);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsCapabilities)) {
				goto CLEANUP_PARTIAL;
			}
			
			kr = (*upsPlugInInterface)->getEvent(upsPlugInInterface, &upsDataRef->upsEvent);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsEvent)) {
				goto CLEANUP_PARTIAL;
			}

			kr = IOServiceAddInterestNotification(gNotifyPort, upsDevice, "IOGeneralInterest", DeviceNotification, upsDataRef, &(upsDataRef->notification));
			if (kr != kIOReturnSuccess)
				goto CLEANUP_PARTIAL;
			
			if (!gAllUPSDevices) {
				gAllUPSDevices = UPSDeviceSetCreate();
			}
			UPSDeviceSetAdd(gAllUPSDevices, upsDataRef);
#ifdef DEBUG
			PrintAllUPSDevices();
#endif
			IOObjectRelease(upsDevice);
			continue;
		}
		
	CLEANUP_PARTIAL:
		// (same cleanup logic as before)
		if (upsDataRef) {
			DBGLOG(@"[UPSMonitor] cleanup");
			if (upsDataRef->notification != MACH_PORT_NULL) {
				IOObjectRelease(upsDataRef->notification);
			}
			if (upsDataRef->upsPlugInInterface) {
				(*upsDataRef->upsPlugInInterface)->Release(upsDataRef->upsPlugInInterface);
			}
			if (upsDataRef->upsProperties)     CFRelease(upsDataRef->upsProperties);
			if (upsDataRef->upsCapabilities)   CFRelease(upsDataRef->upsCapabilities);
			if (upsDataRef->upsEvent)          CFRelease(upsDataRef->upsEvent);
			if (upsDataRef->upsEventSource) {
				CFRunLoopRemoveSource(CFRunLoopGetCurrent(), upsDataRef->upsEventSource, kCFRunLoopDefaultMode);
				CFRelease(upsDataRef->upsEventSource);
			}
			if (upsDataRef->upsEventTimer) {
				CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), upsDataRef->upsEventTimer, kCFRunLoopDefaultMode);
				CFRelease(upsDataRef->upsEventTimer);
			}
			free(upsDataRef);
			upsDataRef = NULL;
		}
		if (plugInInterface) {
			(*plugInInterface)->Release(plugInInterface);
		}
		IOObjectRelease(upsDevice);
	}
}

static void
threadMain(void)
{
	@autoreleasepool {
		gNotifyPort = IONotificationPortCreate(kIOMasterPortDefault);
		if (!gNotifyPort) {
			NSLog(@"[UPSMonitor] ERROR: failed to create IONotificationPort");
			return;
		}

		CFRunLoopSourceRef rlSrc = IONotificationPortGetRunLoopSource(gNotifyPort);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), rlSrc, kCFRunLoopDefaultMode);
		gBackgroundRunLoop = CFRunLoopGetCurrent();
		CFRetain(gBackgroundRunLoop);

		CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOHIDDeviceKey);
		if (!matchingDict) {
			NSLog(@"[UPSMonitor] ERROR: IOServiceMatching returned NULL");
			goto CLEANUP_ALL;
		}
		
		// Build the usage‐pairs array:
		CFMutableArrayRef devicePairs = CFArrayCreateMutable(kCFAllocatorDefault, 4, &kCFTypeArrayCallBacks);
		if (!devicePairs) {
			CFRelease(matchingDict);
			goto CLEANUP_ALL;
		}

		int usagePages[] = {
			kHIDPage_PowerDevice,
			kHIDPage_BatterySystem,
			kHIDPage_AppleVendor,
			kHIDPage_PowerDevice
		};
		int usages[] = {
			0,
			0,
			kHIDUsage_AppleVendor_AccessoryBattery,
			kHIDUsage_PD_PeripheralDevice
		};
		size_t count = sizeof(usagePages) / sizeof(usagePages[0]);
		for (size_t i = 0; i < count; i++) {
			CFMutableDictionaryRef pair = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			if (!pair) {
				CFRelease(devicePairs);
				CFRelease(matchingDict);
				goto CLEANUP_ALL;
			}
			CFNumberRef numPage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePages[i]);
			if (!numPage) {
				CFRelease(pair);
				CFRelease(devicePairs);
				CFRelease(matchingDict);
				goto CLEANUP_ALL;
			}
			CFDictionarySetValue(pair, CFSTR(kIOHIDDeviceUsagePageKey), numPage);
			CFRelease(numPage);
			
			// add Usage if non‐zero (some entries are zero meaning “don’t filter on usage”)
			if (usages[i] != 0) {
				CFNumberRef numUsage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usages[i]);
				if (!numUsage) {
					CFRelease(pair);
					CFRelease(devicePairs);
					CFRelease(matchingDict);
					goto CLEANUP_ALL;
				}
				CFDictionarySetValue(pair, CFSTR(kIOHIDDeviceUsageKey), numUsage);
				CFRelease(numUsage);
			}
			
			CFArrayAppendValue(devicePairs, pair);
			CFRelease(pair);
		}
		
		CFDictionarySetValue(matchingDict, CFSTR(kIOHIDDeviceUsagePairsKey), devicePairs);
		CFRelease(devicePairs);
		devicePairs = NULL;
		
		// Now set up the “first match” notification so UPSDeviceAdded() is called whenever a device arrives.
		kern_return_t kr = IOServiceAddMatchingNotification(gNotifyPort, kIOFirstMatchNotification, matchingDict, UPSDeviceAdded, NULL, &gAddedIter);
		// matchingDict is retained by IOKit (no need to CFRelease here; IOKit takes ownership)
		matchingDict = NULL;
		
		if (kr != kIOReturnSuccess) {
			NSLog(@"[UPSMonitor] ERROR: IOServiceAddMatchingNotification failed: 0x%08x", kr);
			goto CLEANUP_ALL;
		}
		DBGLOG(@"[UPSMonitor] thread setup");
		// Drain any already‐present devices so they don’t get missed
		UPSDeviceAdded(NULL, gAddedIter);

		CFRunLoopRun();
		
	CLEANUP_ALL:
		if (gBackgroundRunLoop) {
			CFRelease(gBackgroundRunLoop);
			gBackgroundRunLoop = NULL;
		}

		if (gAddedIter != MACH_PORT_NULL) {
			IOObjectRelease(gAddedIter);
			gAddedIter = MACH_PORT_NULL;
		}

		if (gAllUPSDevices) {
			size_t n = UPSDeviceSetCount(gAllUPSDevices);
			UPSDataRef *buffer = calloc(n, sizeof(UPSDataRef));
			UPSDeviceSetGetAll(gAllUPSDevices, buffer);
			for (size_t i = 0; i < n; i++) {
				FreeUPSData(buffer[i]);
			}
			free(buffer);
			UPSDeviceSetDestroy(gAllUPSDevices);
			gAllUPSDevices = NULL;
		}


		if (gNotifyPort) {
			IONotificationPortDestroy(gNotifyPort);
			gNotifyPort = NULL;
		}
	}
}

void SignalHandler(int sigraised) {
	syslog(LOG_INFO, "Battman: received signal %d, exiting gracefully\n", sigraised);
	[UPSMonitor cleanupAllResources];
	// app_exit();
}

// Update the CleanupAndExit function
void CleanupAndExit(void) {
	[UPSMonitor cleanupAllResources];
	CFRunLoopStop(CFRunLoopGetCurrent());
}

static bool gNotificationsPaused = false;

+ (void)cleanupAllResources
{
	if (gTerminationInProgress) {
		return; // Prevent double cleanup
	}
	gTerminationInProgress = true;
	
	NSLog(@"[UPSMonitor] Starting graceful shutdown...");
	
	// Stop power event monitoring first
	cleanupPowerEventMonitoring();
	
	// Stop the UPS monitoring run loop if it's running
	if (gBackgroundRunLoop) {
		CFRunLoopPerformBlock(gBackgroundRunLoop, kCFRunLoopDefaultMode, ^{
			CFRunLoopStop(CFRunLoopGetCurrent());
		});
		CFRunLoopWakeUp(gBackgroundRunLoop);
		
		// Give the run loop time to stop gracefully
		dispatch_semaphore_t stopSemaphore = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			// Wait a bit for the run loop to stop
			usleep(100000); // 100ms
			dispatch_semaphore_signal(stopSemaphore);
		});
		
		// Wait up to 1 second for graceful shutdown
		dispatch_semaphore_wait(stopSemaphore, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
	}
	
	// Clean up all UPS devices
	if (gAllUPSDevices) {
		NSLog(@"[UPSMonitor] Cleaning up %zu UPS devices", UPSDeviceSetCount(gAllUPSDevices));
		size_t n = UPSDeviceSetCount(gAllUPSDevices);
		if (n > 0) {
			UPSDataRef *buffer = calloc(n, sizeof(UPSDataRef));
			if (buffer) {
				UPSDeviceSetGetAll(gAllUPSDevices, buffer);
				for (size_t i = 0; i < n; i++) {
					FreeUPSData(buffer[i]);
				}
				free(buffer);
			}
		}
		UPSDeviceSetDestroy(gAllUPSDevices);
		gAllUPSDevices = NULL;
	}
	
	// Clean up IOKit resources
	if (gAddedIter != MACH_PORT_NULL) {
		IOObjectRelease(gAddedIter);
		gAddedIter = MACH_PORT_NULL;
	}
	
	if (gNotifyPort) {
		IONotificationPortDestroy(gNotifyPort);
		gNotifyPort = NULL;
	}
	
	// Clean up run loop reference
	if (gBackgroundRunLoop) {
		CFRelease(gBackgroundRunLoop);
		gBackgroundRunLoop = NULL;
	}
	
	// Reset state
	UPSWatching = false;
	gNotificationsPaused = false;
	
	NSLog(@"[UPSMonitor] Graceful shutdown completed");
}

+ (void)appWillTerminate:(NSNotification *)note
{
	NSLog(@"[UPSMonitor] App will terminate - beginning cleanup");
	[self cleanupAllResources];
}

+ (void)appDidEnterBackground:(NSNotification *)note
{
	if (gTerminationInProgress) return;

	extern dispatch_queue_t _powerQueue;

	suspendPowerEventMonitoring();
	
	if (gBackgroundRunLoop == NULL || gNotifyPort == NULL || gNotificationsPaused)
		return;
	
	CFRunLoopSourceRef src = IONotificationPortGetRunLoopSource(gNotifyPort);
	if (!src) return;
	
	// Remove the UPS monitoring run loop source
	CFRunLoopPerformBlock(gBackgroundRunLoop, kCFRunLoopDefaultMode, ^{
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
	});
	CFRunLoopWakeUp(gBackgroundRunLoop);
	
	gNotificationsPaused = true;
	NSLog(@"[UPSMonitor] Suspended monitoring - app entered background");
}

+ (void)appWillEnterForeground:(NSNotification *)note
{
	if (gTerminationInProgress) return;

	extern dispatch_queue_t _powerQueue;

	resumePowerEventMonitoring();
	
	if (gBackgroundRunLoop == NULL || gNotifyPort == NULL || !gNotificationsPaused)
		return;
	
	CFRunLoopSourceRef src = IONotificationPortGetRunLoopSource(gNotifyPort);
	if (!src) return;
	
	// Add back the UPS monitoring run loop source
	CFRunLoopPerformBlock(gBackgroundRunLoop, kCFRunLoopDefaultMode, ^{
		CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
	});
	CFRunLoopWakeUp(gBackgroundRunLoop);
	
	gNotificationsPaused = false;
	NSLog(@"[UPSMonitor] Resumed monitoring - app will enter foreground");
}


+ (void)startWatchingUPS
{
	DBGLOG(@"[UPSMonitor] called");
	if (UPSWatching) {
		return;
	}

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[nc addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
	[nc addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];

	// Install a signal handler so if someone ^C’s, we clean up
	signal(SIGINT, SignalHandler);
	signal(SIGTERM, SignalHandler);
	
	// Spawn a detached pthread that we do not affect the UIKit
	pthread_t thread;
	pthread_attr_t attrs;
	pthread_attr_init(&attrs);
	pthread_attr_setdetachstate(&attrs, PTHREAD_CREATE_DETACHED);
	
	int err = pthread_create(&thread, &attrs, (void *(*)(void *))threadMain, NULL);
	pthread_attr_destroy(&attrs);
	
	if (err) {
		NSLog(@"[UPSMonitor] Failed to create UPS‐watch thread: %d", err);
	} else {
		gUPSWatchThread = thread;
		NSLog(@"[UPSMonitor] UPS‐watch thread launched.");
		UPSWatching = true;
	}
}

// manually stop monitoring (useful for testing ig)
+ (void)stopWatchingUPS
{
	NSLog(@"[UPSMonitor] Manually stopping UPS monitoring");
	[self cleanupAllResources];
	
	// Remove notification observers
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
	[nc removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
	[nc removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
}

@end

bool UPSCopyBatterySnapshot(int vid, int pid, UPSBatterySnapshot *snapshot) {
	if (!snapshot) return false;
	memset(snapshot, 0, sizeof(*snapshot));
	if (!gAllUPSDevices || vid == 0 || pid == 0) return false;

	for (size_t i = 0; i < gAllUPSDevices->count; i++) {
		UPSDataRef device = gAllUPSDevices->items[i];
		if (!device->upsProperties ||
		    CFGetTypeID(device->upsProperties) != CFDictionaryGetTypeID()) continue;
		SInt32 vendor = 0;
		SInt32 product = 0;
		CFNumberRef number = CFDictionaryGetValue(device->upsProperties, CFSTR("Vendor ID"));
		if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
		    !CFNumberGetValue(number, kCFNumberSInt32Type, &vendor)) continue;
		number = CFDictionaryGetValue(device->upsProperties, CFSTR("Product ID"));
		if (!number || CFGetTypeID(number) != CFNumberGetTypeID() ||
		    !CFNumberGetValue(number, kCFNumberSInt32Type, &product)) continue;
		if (vendor != vid || product != pid) continue;

		snapshot->battery = ups_battery_info(device);
		if (device->upsCapabilities &&
		    CFGetTypeID(device->upsCapabilities) == CFSetGetTypeID()) {
			CFIndex count = CFSetGetCount(device->upsCapabilities);
			for (CFIndex cell = 0; cell < count; cell++) {
				CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
				    CFSTR("Cell %ld Voltage"), cell);
				if (!key) break;
				bool present = CFSetContainsValue(device->upsCapabilities, key);
				CFRelease(key);
				if (!present) break;
				snapshot->cell_count++;
			}
		}
		return true;
	}
	return false;
}

#endif

#pragma mark -- Misc

// Call this right after you do your UPSDeviceSetAdd, or whenever you want to dump the contents:
#if DEBUG
void PrintAllUPSDevices(void) {
	if (!gAllUPSDevices || gAllUPSDevices->count == 0) {
		NSLog(@"[UPSMonitor] no UPS devices in set");
		return;
	}
	
	NSLog(@"[UPSMonitor] gAllUPSDevices contains %zu entries:", gAllUPSDevices->count);
	for (size_t i = 0; i < gAllUPSDevices->count; i++) {
		UPSDataRef d = gAllUPSDevices->items[i];
		
		NSLog(@"  [%zu] UPSDataRef %p entryID %llu", i, d, d->regID);
		CFShow(d->upsProperties);
		CFShow(d->upsCapabilities);
		CFShow(d->upsEvent);
	}
}
#endif

#define GetIntForKey(x, y, z) do { \
	(z) = 0; \
	if ((x) && CFGetTypeID(x) == CFDictionaryGetTypeID()) { \
		number = CFDictionaryGetValue((x), CFSTR(y)); \
		if (!number || CFGetTypeID(number) != CFNumberGetTypeID() || \
		    !CFNumberGetValue(number, kCFNumberIntType, &(z))) (z) = 0; \
	} \
} while (0)

ups_batt_t ups_battery_info(UPSDataRef device) {
	ups_batt_t info = {0};

	if (!device || !device->upsEvent ||
	    CFGetTypeID(device->upsEvent) != CFDictionaryGetTypeID()) return info;

	CFNumberRef number;
	/* Do not show Nominal Capacity, to avoid confusions */
	GetIntForKey(device->upsEvent, "AppleRawCurrentCapacity", info.current_capacity);
	GetIntForKey(device->upsEvent, "Max Capacity", info.max_capacity);
	GetIntForKey(device->upsEvent, "Battery Case Charging Voltage", info.batt_charging_voltage);
	GetIntForKey(device->upsEvent, "Current", info.current);
	GetIntForKey(device->upsEvent, "Voltage", info.voltage);
	GetIntForKey(device->upsEvent, "CycleCount", info.cycle_count);
	GetIntForKey(device->upsEvent, "Device Color", info.device_color);
	GetIntForKey(device->upsEvent, "Incoming Current", info.incoming_current);
	GetIntForKey(device->upsEvent, "Incoming Voltage", info.incoming_voltage);
	GetIntForKey(device->upsEvent, "Is Charging", info.charging);
	GetIntForKey(device->upsEvent, "Temperature", info.temperature);
	GetIntForKey(device->upsEvent, "Time to Empty", info.time_to_empty);
	GetIntForKey(device->upsEvent, "Time to Full", info.time_to_full);

	CFDictionaryRef debug_info = CFDictionaryGetValue(device->upsEvent, CFSTR("Debug Information"));
	GetIntForKey(debug_info, "Battery Case Average Charging Current", info.batt_charging_current);

	return info;
}
