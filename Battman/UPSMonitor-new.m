//
//  UPSMonitor-new.m
//  Battman
//
//  Created by Torrekie on 2025/9/6.
//

#import "common.h"
#import "UPSMonitor.h"

#include <pthread/pthread.h>
#include <unistd.h>
#import <UIKit/UIKit.h>

UPSDeviceSet *gAllUPSDevices = NULL;

// ---------------------------------------------------------------------------
// Globals (internal)
// ---------------------------------------------------------------------------

static bool UPSWatching = false;
static pthread_t gUPSWatchThread = 0;         // watch thread (joinable)
static bool gWatchThreadExited = false;
static bool gWatchThreadStarting = false;
static bool gWatchThreadReady = false;
static CFRunLoopRef gBackgroundRunLoop = NULL;
static IONotificationPortRef gNotifyPort = NULL;
static io_iterator_t gAddedIter = MACH_PORT_NULL;

static bool gTerminationInProgress = false;
static bool gNotificationsPaused = false;

// (Full file content, with modifications and added helper functions)

// --- additions at top of file (new global lock & helper prototypes) ---
static pthread_mutex_t gAllUPSDevicesLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gWatchLifecycleLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t gWatchStateCondition = PTHREAD_COND_INITIALIZER;

static bool AllUPSDevicesContainsByID(uint64_t regID);
static void SetupPluginAndEventSourceForDevice(UPSDataRef upsDataRef, io_service_t upsDevice);
static void TeardownDeviceRuntime(UPSDataRef upsDataRef); // remove sources/timers/notification/plugin but keep CF properties
static void RecreateMonitoringForExistingDevices(void); // run on background runloop to reattach existing devices

void suspendPowerEventMonitoring(void);
void resumePowerEventMonitoring(void);
void cleanupPowerEventMonitoring(void);

// ---------------------------------------------------------------------
// Existing code continues, with edits below
// ---------------------------------------------------------------------
@implementation UPSMonitor

// Create an empty set
static UPSDeviceSet *UPSDeviceSetCreate(void) {
	UPSDeviceSet *set = calloc(1, sizeof(*set));
	if (!set) return NULL;
	set->capacity = 1;
	set->items    = calloc(set->capacity, sizeof(UPSDataRef));
	if (!set->items) {
		free(set);
		return NULL;
	}
	return set;
}

// Free the set itself (not the UPSDataRefs; you should free those separately)
static void UPSDeviceSetDestroy(UPSDeviceSet *set) {
	if (!set) return;
	free(set->items);
	free(set);
}
static UPSDataRef UPSDataRetain(UPSDataRef upsDataRef) {
	if (upsDataRef) {
		__atomic_add_fetch(&upsDataRef->retainCount, 1, __ATOMIC_RELAXED);
	}
	return upsDataRef;
}

static void UPSDataRelease(UPSDataRef upsDataRef);

typedef struct UPSRuntimeResources {
	IOUPSPlugInInterface **plugin;
	io_object_t notification;
	UPSDataRef notificationOwner;
	CFRunLoopSourceRef eventSource;
	CFRunLoopTimerRef eventTimer;
} UPSRuntimeResources;

static UPSRuntimeResources UPSDetachRuntimeLocked(UPSDataRef upsDataRef) {
	UPSRuntimeResources runtime = {
		.plugin = upsDataRef->upsPlugInInterface,
		.notification = upsDataRef->notification,
		.notificationOwner = upsDataRef->notification != MACH_PORT_NULL ? upsDataRef : NULL,
		.eventSource = upsDataRef->upsEventSource,
		.eventTimer = upsDataRef->upsEventTimer,
	};
	upsDataRef->upsPlugInInterface = NULL;
	upsDataRef->notification = MACH_PORT_NULL;
	upsDataRef->upsEventSource = NULL;
	upsDataRef->upsEventTimer = NULL;
	return runtime;
}

static void UPSReleaseRuntime(UPSRuntimeResources runtime) {
	if (runtime.notification != MACH_PORT_NULL) {
		IOObjectRelease(runtime.notification);
	}
	if (runtime.eventSource) {
		CFRunLoopSourceInvalidate(runtime.eventSource);
		CFRelease(runtime.eventSource);
	}
	if (runtime.eventTimer) {
		CFRunLoopTimerInvalidate(runtime.eventTimer);
		CFRelease(runtime.eventTimer);
	}
	if (runtime.plugin) {
		(*runtime.plugin)->Release(runtime.plugin);
	}
	if (runtime.notificationOwner) {
		UPSDataRelease(runtime.notificationOwner);
	}
}

static void UPSDataDestroy(UPSDataRef upsDataRef) {
	TeardownDeviceRuntime(upsDataRef);
	if (upsDataRef->upsProperties) CFRelease(upsDataRef->upsProperties);
	if (upsDataRef->upsCapabilities) CFRelease(upsDataRef->upsCapabilities);
	if (upsDataRef->upsEvent) CFRelease(upsDataRef->upsEvent);
	free(upsDataRef);
}

static void UPSDataRelease(UPSDataRef upsDataRef) {
	if (upsDataRef &&
	    __atomic_sub_fetch(&upsDataRef->retainCount, 1, __ATOMIC_ACQ_REL) == 0) {
		UPSDataDestroy(upsDataRef);
	}
}

static bool AllUPSDevicesContainsByID(uint64_t regID) {
	bool contains = false;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gAllUPSDevices) {
		for (size_t i = 0; i < gAllUPSDevices->count; i++) {
			if (gAllUPSDevices->items[i]->regID == regID) {
				contains = true;
				break;
			}
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return contains;
}

// Transfers the caller's initial reference to the global set on success.
static bool AllUPSDevicesAdd(UPSDataRef upsDataRef) {
	bool added = false;
	if (!upsDataRef) return false;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (!gTerminationInProgress) {
		if (!gAllUPSDevices) gAllUPSDevices = UPSDeviceSetCreate();
		if (gAllUPSDevices) {
			bool duplicate = false;
			for (size_t i = 0; i < gAllUPSDevices->count; i++) {
				if (gAllUPSDevices->items[i]->regID == upsDataRef->regID) {
					duplicate = true;
					break;
				}
			}
			if (!duplicate) {
				if (gAllUPSDevices->count < gAllUPSDevices->capacity) {
					added = true;
				} else {
					size_t newCapacity = gAllUPSDevices->capacity
					    ? gAllUPSDevices->capacity * 2 : 1;
					UPSDataRef *items = realloc(gAllUPSDevices->items,
					    newCapacity * sizeof(*items));
					if (items) {
						gAllUPSDevices->items = items;
						gAllUPSDevices->capacity = newCapacity;
						added = true;
					}
				}
				if (added) gAllUPSDevices->items[gAllUPSDevices->count++] = upsDataRef;
			}
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return added;
}

// Transfers the set's reference to the caller on success.
static bool AllUPSDevicesRemove(UPSDataRef upsDataRef) {
	bool removed = false;
	if (!upsDataRef) return false;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gAllUPSDevices) {
		for (size_t i = 0; i < gAllUPSDevices->count; i++) {
			if (gAllUPSDevices->items[i] == upsDataRef) {
				memmove(&gAllUPSDevices->items[i], &gAllUPSDevices->items[i + 1],
				    (gAllUPSDevices->count - i - 1) * sizeof(UPSDataRef));
				gAllUPSDevices->count--;
				removed = true;
				break;
			}
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return removed;
}

// Returns retained device references from one lock-protected snapshot.
static UPSDataRef *AllUPSDevicesCopy(size_t *outCount) {
	UPSDataRef *items = NULL;
	*outCount = 0;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gAllUPSDevices && gAllUPSDevices->count) {
		items = calloc(gAllUPSDevices->count, sizeof(*items));
		if (items) {
			*outCount = gAllUPSDevices->count;
			for (size_t i = 0; i < *outCount; i++) {
				items[i] = UPSDataRetain(gAllUPSDevices->items[i]);
			}
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return items;
}

// Detaches the set atomically so only one shutdown path owns its references.
static UPSDeviceSet *AllUPSDevicesTake(void) {
	pthread_mutex_lock(&gAllUPSDevicesLock);
	UPSDeviceSet *set = gAllUPSDevices;
	gAllUPSDevices = NULL;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return set;
}

bool UPSCopyBatterySnapshot(int vid, int pid, UPSBatterySnapshot *snapshot) {
	if (!snapshot) return false;
	memset(snapshot, 0, sizeof(*snapshot));
	if (vid == 0 || pid == 0) return false;

	bool found = false;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gAllUPSDevices) {
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
			found = true;
			break;
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	return found;
}

static void TeardownDeviceRuntime(UPSDataRef upsDataRef) {
	if (!upsDataRef) return;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	UPSRuntimeResources runtime = UPSDetachRuntimeLocked(upsDataRef);
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	UPSReleaseRuntime(runtime);
}

static void FreeUPSData(UPSDataRef upsDataRef) {
	if (!upsDataRef) return;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	upsDataRef->removed = true;
	UPSRuntimeResources runtime = UPSDetachRuntimeLocked(upsDataRef);
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	UPSDataRelease(upsDataRef);
	UPSReleaseRuntime(runtime);
}

static void AllUPSDevicesRemoveMissing(CFSetRef presentRegistryIDs) {
	if (!presentRegistryIDs) return;
	UPSDataRef *removed = NULL;
	size_t removedCount = 0;

	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gAllUPSDevices && gAllUPSDevices->count) {
		removed = calloc(gAllUPSDevices->count, sizeof(*removed));
		if (removed) {
			for (size_t i = 0; i < gAllUPSDevices->count;) {
				uint64_t regID = gAllUPSDevices->items[i]->regID;
				CFNumberRef number = CFNumberCreate(kCFAllocatorDefault,
				    kCFNumberSInt64Type, &regID);
				bool present = !number || CFSetContainsValue(presentRegistryIDs, number);
				if (number) CFRelease(number);
				if (present) {
					i++;
					continue;
				}
				removed[removedCount++] = gAllUPSDevices->items[i];
				memmove(&gAllUPSDevices->items[i], &gAllUPSDevices->items[i + 1],
				    (gAllUPSDevices->count - i - 1) * sizeof(UPSDataRef));
				gAllUPSDevices->count--;
			}
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);

	for (size_t i = 0; i < removedCount; i++) FreeUPSData(removed[i]);
	free(removed);
}

// Device interest notifications come here (called by IOKit)
void DeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument ) {
	UPSDataRef upsData = (UPSDataRef)refCon;
	if (upsData == NULL) {
		return;
	}
	
	if (messageType == kIOMessageServiceIsTerminated) {
		// The set reference belongs to whichever removal path wins.
		if (AllUPSDevicesRemove(upsData)) FreeUPSData(upsData);
	}
}

// Helper: classify typeRef and populate either timer or source pointer
static void
ProcessUPSEventSource(CFTypeRef typeRef, CFRunLoopTimerRef * pTimer, CFRunLoopSourceRef * pSource)
{
	if (!typeRef) return;
	if ( CFGetTypeID(typeRef) == CFRunLoopTimerGetTypeID() ) {
		*pTimer = (CFRunLoopTimerRef)typeRef;
		CFRetain(*pTimer);
	}
	else if ( CFGetTypeID(typeRef) == CFRunLoopSourceGetTypeID() ) {
		*pSource = (CFRunLoopSourceRef)typeRef;
		CFRetain(*pSource);
	}
}

// New helper: attempt to set up plugin and async event source for an existing upsDataRef and upsDevice
static void SetupPluginAndEventSourceForDevice(UPSDataRef upsDataRef, io_service_t upsDevice) {
	if (!upsDataRef || upsDevice == MACH_PORT_NULL) return;
	
	IOCFPlugInInterface **    plugInInterface = NULL;
	IOUPSPlugInInterface_v140 **   upsPlugInInterface  = NULL;
	SInt32                    score           = 0;
	IOReturn                  kr;
	HRESULT                   result          = E_NOINTERFACE;
	CFTypeRef typeRef = NULL;
	CFRunLoopSourceRef newSource = NULL;
	CFRunLoopTimerRef newTimer = NULL;
	CFDictionaryRef newProps = NULL;
	CFSetRef newCaps = NULL;
	CFDictionaryRef newEvent = NULL;
	io_object_t newNotification = MACH_PORT_NULL;
	
	kr = IOCreatePlugInInterfaceForService(upsDevice, kIOUPSPlugInTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
	if (kr != kIOReturnSuccess || !plugInInterface) {
		DBGLOG(@"[UPSMonitor] IOCreatePlugInInterfaceForService failed: 0x%08x", kr);
		if (plugInInterface) (*plugInInterface)->Release(plugInInterface);
		return;
	}
	
	// Try the v140 interface first
	result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUPSPlugInInterfaceID_v140), (LPVOID)&upsPlugInInterface);
	if ( ( result == S_OK ) && upsPlugInInterface ) {
		kr = (*upsPlugInInterface)->createAsyncEventSource(upsPlugInInterface, &typeRef);
		if ((kr != kIOReturnSuccess) || !typeRef) {
			// fallthrough to cleanup below (we may still try fallback below)
		}
	} else {
		// fallback to older interface
		result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUPSPlugInInterfaceID), (LPVOID)&upsPlugInInterface);
		if ( ( result == S_OK ) && upsPlugInInterface ) {
			kr = (*upsPlugInInterface)->createAsyncEventSource(upsPlugInInterface, &typeRef);
			if ((kr != kIOReturnSuccess) || !typeRef) {
				// fallthrough
			}
		}
	}
	
	// Build runtime state in locals so teardown never races partially initialized fields.
	if (typeRef) {
		if (CFGetTypeID(typeRef) == CFArrayGetTypeID()) {
			CFArrayRef sources = (CFArrayRef)typeRef;
			for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
				ProcessUPSEventSource(CFArrayGetValueAtIndex(sources, i),
				    &newTimer, &newSource);
			}
		} else {
			ProcessUPSEventSource(typeRef, &newTimer, &newSource);
		}
		
		CFRunLoopRef runLoop = gBackgroundRunLoop ?: CFRunLoopGetCurrent();
		if (newSource) {
			CFRunLoopAddSource(runLoop, newSource, kCFRunLoopDefaultMode);
		}
		if (newTimer) {
			CFRunLoopAddTimer(runLoop, newTimer, kCFRunLoopDefaultMode);
		}
		CFRelease(typeRef);
		typeRef = NULL;
	}
	
	if ((result == S_OK) && upsPlugInInterface) {
		kr = (*upsPlugInInterface)->getProperties(upsPlugInInterface, &newProps);
		if ((kr != kIOReturnSuccess) || !newProps) {
			if (newProps) CFRelease(newProps);
			newProps = NULL;
		}
		kr = (*upsPlugInInterface)->getCapabilities(upsPlugInInterface, &newCaps);
		if ((kr != kIOReturnSuccess) || !newCaps) {
			if (newCaps) CFRelease(newCaps);
			newCaps = NULL;
		}
		kr = (*upsPlugInInterface)->getEvent(upsPlugInInterface, &newEvent);
		if ((kr != kIOReturnSuccess) || !newEvent) {
			if (newEvent) CFRelease(newEvent);
			newEvent = NULL;
		}
		(*upsPlugInInterface)->Release(upsPlugInInterface);
		upsPlugInInterface = NULL;
	}

	if (gNotifyPort) {
		kr = IOServiceAddInterestNotification(gNotifyPort, upsDevice, "IOGeneralInterest",
		    DeviceNotification, upsDataRef, &newNotification);
		if (kr == kIOReturnSuccess) {
			UPSDataRetain(upsDataRef);
		} else {
			if (newNotification != MACH_PORT_NULL) IOObjectRelease(newNotification);
			newNotification = MACH_PORT_NULL;
		}
	}

	UPSRuntimeResources oldRuntime = {0};
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (!upsDataRef->removed) {
		oldRuntime = UPSDetachRuntimeLocked(upsDataRef);
		upsDataRef->upsEventSource = newSource;
		upsDataRef->upsEventTimer = newTimer;
		upsDataRef->notification = newNotification;
		newSource = NULL;
		newTimer = NULL;
		newNotification = MACH_PORT_NULL;

		if (newProps) {
			if (upsDataRef->upsProperties) CFRelease(upsDataRef->upsProperties);
			upsDataRef->upsProperties = newProps;
			newProps = NULL;
		}
		if (newCaps) {
			if (upsDataRef->upsCapabilities) CFRelease(upsDataRef->upsCapabilities);
			upsDataRef->upsCapabilities = newCaps;
			newCaps = NULL;
		}
		if (newEvent) {
			if (upsDataRef->upsEvent) CFRelease(upsDataRef->upsEvent);
			upsDataRef->upsEvent = newEvent;
			newEvent = NULL;
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);

	UPSReleaseRuntime(oldRuntime);
	UPSRuntimeResources unusedRuntime = {
		.notification = newNotification,
		.notificationOwner = newNotification != MACH_PORT_NULL ? upsDataRef : NULL,
		.eventSource = newSource,
		.eventTimer = newTimer,
	};
	UPSReleaseRuntime(unusedRuntime);
	if (newProps) CFRelease(newProps);
	if (newCaps) CFRelease(newCaps);
	if (newEvent) CFRelease(newEvent);
	if (typeRef) CFRelease(typeRef);
	if (upsPlugInInterface) {
		(*upsPlugInInterface)->Release(upsPlugInInterface);
		upsPlugInInterface = NULL;
	}
	if (plugInInterface) {
		(*plugInInterface)->Release(plugInInterface);
		plugInInterface = NULL;
	}
}

// Recreate monitoring for devices that are currently present. Runs on background runloop.
static void RecreateMonitoringForExistingDevices(void) {
	pthread_mutex_lock(&gAllUPSDevicesLock);
	bool terminating = gTerminationInProgress;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (terminating) return;

	// Build a matching dictionary similar to threadMain
	CFMutableDictionaryRef matchingDict = IOServiceMatching(kIOHIDDeviceKey);
	if (!matchingDict) {
		DBGLOG(@"[UPSMonitor] ERROR: IOServiceMatching returned NULL in RecreateMonitoringForExistingDevices");
		return;
	}
	
	// Build usage-pairs array same as threadMain
	CFMutableArrayRef devicePairs = CFArrayCreateMutable(kCFAllocatorDefault, 4, &kCFTypeArrayCallBacks);
	if (!devicePairs) {
		CFRelease(matchingDict);
		return;
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
			return;
		}
		CFNumberRef numPage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePages[i]);
		CFDictionarySetValue(pair, CFSTR(kIOHIDDeviceUsagePageKey), numPage);
		CFRelease(numPage);
		if (usages[i] != 0) {
			CFNumberRef numUsage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usages[i]);
			CFDictionarySetValue(pair, CFSTR(kIOHIDDeviceUsageKey), numUsage);
			CFRelease(numUsage);
		}
		CFArrayAppendValue(devicePairs, pair);
		CFRelease(pair);
	}
	CFDictionarySetValue(matchingDict, CFSTR(kIOHIDDeviceUsagePairsKey), devicePairs);
	CFRelease(devicePairs);
	
	// Get iterator for currently present devices
	io_iterator_t iter = MACH_PORT_NULL;
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iter);
	// matchingDict is consumed by IOServiceGetMatchingServices
	matchingDict = NULL;
	if (kr != kIOReturnSuccess || iter == MACH_PORT_NULL) {
		DBGLOG(@"[UPSMonitor] IOServiceGetMatchingServices failed during recreate: 0x%08x", kr);
		if (iter != MACH_PORT_NULL) IOObjectRelease(iter);
		return;
	}
	CFMutableSetRef presentRegistryIDs = CFSetCreateMutable(kCFAllocatorDefault,
	    0, &kCFTypeSetCallBacks);
	bool canReconcile = presentRegistryIDs != NULL;
	
	// Iterate present devices; for each, try to match by registry entry ID to an existing element in gAllUPSDevices
	io_service_t service;
	while ((service = IOIteratorNext(iter))) {
		uint64_t entryID = 0;
		kr = IORegistryEntryGetRegistryEntryID(service, &entryID);
		if (kr != kIOReturnSuccess) {
			canReconcile = false;
			IOObjectRelease(service);
			continue;
		}
		if (canReconcile) {
			CFNumberRef registryID = CFNumberCreate(kCFAllocatorDefault,
			    kCFNumberSInt64Type, &entryID);
			if (registryID) {
				CFSetAddValue(presentRegistryIDs, registryID);
				CFRelease(registryID);
			} else {
				canReconcile = false;
			}
		}
		
		// find an upsDataRef with same regID
		pthread_mutex_lock(&gAllUPSDevicesLock);
		UPSDataRef matched = NULL;
		if (gAllUPSDevices) {
			for (size_t i = 0; i < gAllUPSDevices->count; i++) {
				if (gAllUPSDevices->items[i]->regID == entryID) {
					matched = UPSDataRetain(gAllUPSDevices->items[i]);
					break;
				}
			}
		}
		pthread_mutex_unlock(&gAllUPSDevicesLock);
		
		if (matched) {
			// set up plugin and event source for the existing upsDataRef
			SetupPluginAndEventSourceForDevice(matched, service);
			UPSDataRelease(matched);
		} else {
			// no existing device with that regID — normal: let UPSDeviceAdded handle it (it will be called via first-match notifications)
		}
		
		IOObjectRelease(service);
	}
	IOObjectRelease(iter);
	if (canReconcile) AllUPSDevicesRemoveMissing(presentRegistryIDs);
	if (presentRegistryIDs) CFRelease(presentRegistryIDs);
}

// Called by the IOKit matching notification when devices are added
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
		upsDataRef->retainCount        = 1;
		upsDataRef->regID              = entryID;
		upsDataRef->notification       = MACH_PORT_NULL;
		upsDataRef->upsPlugInInterface = NULL;
		upsDataRef->upsProperties      = NULL;
		upsDataRef->upsCapabilities    = NULL;
		upsDataRef->upsEvent           = NULL;
		upsDataRef->upsEventSource     = NULL;
		upsDataRef->upsEventTimer      = NULL;
		
		// If we already have a device with this registry ID, avoid creating a duplicate. Free the temp and continue.
		if (AllUPSDevicesContainsByID(entryID)) {
			DBGLOG(@"[UPSMonitor] device with regID %llu already present - skipping", entryID);
			UPSDataRelease(upsDataRef);
			IOObjectRelease(upsDevice);
			continue;
		}
		
		// Create the CF plugin for this device (we only use it to create async event source & read properties)
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
			
			// Attach source/timer to the background runloop (we're in the background thread's runloop context)
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
			// Fetch properties, capabilities and events and store them in the upsDataRef (kept across backgrounding)
			upsDataRef->upsPlugInInterface = (IOUPSPlugInInterface **)upsPlugInInterface; // temporarily store pointer
			kr = (*upsPlugInInterface)->getProperties(upsPlugInInterface, &upsDataRef->upsProperties);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsProperties)) {
				// proceed, we might still have event source
			}
			
			kr = (*upsPlugInInterface)->getCapabilities(upsPlugInInterface, &upsDataRef->upsCapabilities);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsCapabilities)) {
				// proceed
			}
			
			kr = (*upsPlugInInterface)->getEvent(upsPlugInInterface, &upsDataRef->upsEvent);
			if ((kr != kIOReturnSuccess) || (!upsDataRef->upsEvent)) {
				// proceed
			}
			
			// Per requirement: release the plugin interface immediately after we got what we needed.
			if (upsDataRef->upsPlugInInterface) {
				(*upsDataRef->upsPlugInInterface)->Release(upsDataRef->upsPlugInInterface);
				upsDataRef->upsPlugInInterface = NULL;
			}
			
			// Create interest notification and add to set
			kr = IOServiceAddInterestNotification(gNotifyPort, upsDevice, "IOGeneralInterest", DeviceNotification, upsDataRef, &(upsDataRef->notification));
			if (kr == kIOReturnSuccess) {
				UPSDataRetain(upsDataRef);
			} else {
				if (upsDataRef->notification != MACH_PORT_NULL) {
					IOObjectRelease(upsDataRef->notification);
				}
				upsDataRef->notification = MACH_PORT_NULL;
			}
			
			if (plugInInterface) {
				(*plugInInterface)->Release(plugInInterface);
				plugInInterface = NULL;
			}
			if (!AllUPSDevicesAdd(upsDataRef)) {
				// If we failed to add (race or duplicate), cleanup upsDataRef to avoid leak
				DBGLOG(@"[UPSMonitor] Failed to add upsDataRef to global set - cleaning up");
				FreeUPSData(upsDataRef);
				upsDataRef = NULL;
				IOObjectRelease(upsDevice);
				continue;
			}
			
#ifdef DEBUG
			PrintAllUPSDevices();
#endif
			IOObjectRelease(upsDevice);
			continue;
		}
		
	CLEANUP_PARTIAL:
		if (upsDataRef) {
			DBGLOG(@"[UPSMonitor] cleanup");
			FreeUPSData(upsDataRef);
			upsDataRef = NULL;
		}
		if (typeRef) {
			CFRelease(typeRef);
			typeRef = NULL;
		}
		if (upsPlugInInterface) {
			(*upsPlugInInterface)->Release(upsPlugInInterface);
			upsPlugInInterface = NULL;
		}
		if (plugInInterface) {
			(*plugInInterface)->Release(plugInInterface);
			plugInInterface = NULL;
		}
		IOObjectRelease(upsDevice);
	}
}

static void UPSKeepAlivePerform(void *info) {}

static void *
threadMain(void *context)
{
	@autoreleasepool {
		IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
		CFRunLoopSourceRef keepAliveSource = NULL;
		CFRunLoopRef runLoopToRelease = NULL;
		if (!notifyPort) {
			NSLog(@"[UPSMonitor] ERROR: failed to create IONotificationPort");
			goto CLEANUP_ALL;
		}
		
		CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
		CFRunLoopSourceRef notificationSource = IONotificationPortGetRunLoopSource(notifyPort);
		CFRunLoopSourceContext keepAliveContext = {
			.version = 0,
			.perform = UPSKeepAlivePerform,
		};
		keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &keepAliveContext);
		if (!notificationSource || !keepAliveSource) {
			NSLog(@"[UPSMonitor] ERROR: failed to create run loop sources");
			goto CLEANUP_ALL;
		}
		CFRunLoopAddSource(currentRunLoop, notificationSource, kCFRunLoopDefaultMode);
		CFRunLoopAddSource(currentRunLoop, keepAliveSource, kCFRunLoopDefaultMode);

		pthread_mutex_lock(&gAllUPSDevicesLock);
		bool shouldTerminate = gTerminationInProgress;
		if (!shouldTerminate) {
			gNotifyPort = notifyPort;
			gBackgroundRunLoop = currentRunLoop;
			CFRetain(gBackgroundRunLoop);
		}
		pthread_mutex_unlock(&gAllUPSDevicesLock);
		if (shouldTerminate) goto CLEANUP_ALL;
		
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
		kern_return_t kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchingDict, UPSDeviceAdded, NULL, &gAddedIter);
		// matchingDict is retained by IOKit (no need to CFRelease here; IOKit takes ownership)
		matchingDict = NULL;
		
		if (kr != kIOReturnSuccess) {
			NSLog(@"[UPSMonitor] ERROR: IOServiceAddMatchingNotification failed: 0x%08x", kr);
			goto CLEANUP_ALL;
		}
		DBGLOG(@"[UPSMonitor] thread setup");
		// Drain any already‐present devices so they don’t get missed
		UPSDeviceAdded(NULL, gAddedIter);
		pthread_mutex_lock(&gAllUPSDevicesLock);
		gWatchThreadReady = true;
		pthread_cond_broadcast(&gWatchStateCondition);
		pthread_mutex_unlock(&gAllUPSDevicesLock);

		CFRunLoopRun();
		
	CLEANUP_ALL:
		pthread_mutex_lock(&gAllUPSDevicesLock);
		if (gNotifyPort == notifyPort) gNotifyPort = NULL;
		runLoopToRelease = gBackgroundRunLoop;
		gBackgroundRunLoop = NULL;
		gWatchThreadReady = false;
		UPSWatching = false;
		gWatchThreadExited = true;
		gNotificationsPaused = false;
		pthread_cond_broadcast(&gWatchStateCondition);
		pthread_mutex_unlock(&gAllUPSDevicesLock);

		if (gAddedIter != MACH_PORT_NULL) {
			IOObjectRelease(gAddedIter);
			gAddedIter = MACH_PORT_NULL;
		}
		
		UPSDeviceSet *set = AllUPSDevicesTake();
		if (set) {
			for (size_t i = 0; i < set->count; i++) FreeUPSData(set->items[i]);
			UPSDeviceSetDestroy(set);
		}
		
		if (keepAliveSource) {
			CFRunLoopSourceInvalidate(keepAliveSource);
			CFRelease(keepAliveSource);
		}
		if (notifyPort) IONotificationPortDestroy(notifyPort);
		if (runLoopToRelease) CFRelease(runLoopToRelease);
	}
	return NULL;
}

void SignalHandler(int sigraised) {
	// Process teardown is not async-signal-safe; the OS reclaims these resources.
	_exit(128 + sigraised);
}

// Update the CleanupAndExit function
void CleanupAndExit(void) {
	[UPSMonitor cleanupAllResources];
	CFRunLoopStop(CFRunLoopGetCurrent());
}

+ (void)_cleanupAllResourcesLocked
{
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gTerminationInProgress) {
		pthread_mutex_unlock(&gAllUPSDevicesLock);
		return;
	}
	gTerminationInProgress = true;
	gNotificationsPaused = false;
	CFRunLoopRef runLoop = gBackgroundRunLoop;
	if (runLoop) CFRetain(runLoop);
	pthread_t watchThread = gUPSWatchThread;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	
	NSLog(@"[UPSMonitor] Starting graceful shutdown...");
	cleanupPowerEventMonitoring();

	if (runLoop) {
		CFRunLoopPerformBlock(runLoop, kCFRunLoopDefaultMode, ^{
			CFRunLoopStop(CFRunLoopGetCurrent());
		});
		CFRunLoopWakeUp(runLoop);
		CFRelease(runLoop);
	}
	if (watchThread && !pthread_equal(watchThread, pthread_self())) {
		pthread_join(watchThread, NULL);
		pthread_mutex_lock(&gAllUPSDevicesLock);
		if (pthread_equal(gUPSWatchThread, watchThread)) gUPSWatchThread = 0;
		UPSWatching = false;
		gWatchThreadExited = false;
		pthread_mutex_unlock(&gAllUPSDevicesLock);
	} else if (!watchThread) {
		UPSDeviceSet *set = AllUPSDevicesTake();
		if (set) {
			for (size_t i = 0; i < set->count; i++) FreeUPSData(set->items[i]);
			UPSDeviceSetDestroy(set);
		}
		pthread_mutex_lock(&gAllUPSDevicesLock);
		UPSWatching = false;
		gWatchThreadExited = false;
		pthread_mutex_unlock(&gAllUPSDevicesLock);
	}

	NSLog(@"[UPSMonitor] Graceful shutdown completed");
}

+ (void)cleanupAllResources
{
	pthread_mutex_lock(&gWatchLifecycleLock);
	[self _cleanupAllResourcesLocked];
	pthread_mutex_unlock(&gWatchLifecycleLock);
}

// app background/foreground handling — updated to teardown/recreate runtime parts (but keep CF properties)
+ (void)appWillTerminate:(NSNotification *)note
{
	NSLog(@"[UPSMonitor] App will terminate - beginning cleanup");
	[self cleanupAllResources];
}

+ (void)appDidEnterBackground:(NSNotification *)note
{
	pthread_mutex_lock(&gWatchLifecycleLock);
	pthread_mutex_lock(&gAllUPSDevicesLock);
	bool terminating = gTerminationInProgress;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (terminating) {
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}

	suspendPowerEventMonitoring();

	CFRunLoopRef runLoop = NULL;
	CFRunLoopSourceRef notificationSource = NULL;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (!gTerminationInProgress && !gNotificationsPaused &&
	    gBackgroundRunLoop && gNotifyPort) {
		notificationSource = IONotificationPortGetRunLoopSource(gNotifyPort);
		if (notificationSource) {
			CFRetain(notificationSource);
			runLoop = gBackgroundRunLoop;
			CFRetain(runLoop);
			gNotificationsPaused = true;
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (!runLoop || !notificationSource) {
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}

	CFRunLoopRemoveSource(runLoop, notificationSource, kCFRunLoopDefaultMode);
	CFRelease(notificationSource);
	CFRunLoopPerformBlock(runLoop, kCFRunLoopDefaultMode, ^{
		size_t count = 0;
		UPSDataRef *devices = AllUPSDevicesCopy(&count);
		for (size_t i = 0; i < count; i++) {
			TeardownDeviceRuntime(devices[i]);
			UPSDataRelease(devices[i]);
		}
		free(devices);
	});
	CFRunLoopWakeUp(runLoop);
	CFRelease(runLoop);

	NSLog(@"[UPSMonitor] Suspended monitoring - app entered background (plugin/interfaces released, CF props retained)");
	pthread_mutex_unlock(&gWatchLifecycleLock);
}

+ (void)appWillEnterForeground:(NSNotification *)note
{
	pthread_mutex_lock(&gWatchLifecycleLock);
	pthread_mutex_lock(&gAllUPSDevicesLock);
	bool terminating = gTerminationInProgress;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (terminating) {
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}

	resumePowerEventMonitoring();

	CFRunLoopRef runLoop = NULL;
	CFRunLoopSourceRef notificationSource = NULL;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (!gTerminationInProgress && gNotificationsPaused &&
	    gBackgroundRunLoop && gNotifyPort) {
		notificationSource = IONotificationPortGetRunLoopSource(gNotifyPort);
		if (notificationSource) {
			CFRetain(notificationSource);
			runLoop = gBackgroundRunLoop;
			CFRetain(runLoop);
			gNotificationsPaused = false;
		}
	}
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (!runLoop || !notificationSource) {
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}

	CFRunLoopAddSource(runLoop, notificationSource, kCFRunLoopDefaultMode);
	CFRelease(notificationSource);
	CFRunLoopPerformBlock(runLoop, kCFRunLoopDefaultMode, ^{
		RecreateMonitoringForExistingDevices();
	});
	CFRunLoopWakeUp(runLoop);
	CFRelease(runLoop);

	NSLog(@"[UPSMonitor] Resumed monitoring - app will enter foreground");
	pthread_mutex_unlock(&gWatchLifecycleLock);
}


+ (void)startWatchingUPS
{
	DBGLOG(@"[UPSMonitor] called");
	pthread_mutex_lock(&gWatchLifecycleLock);
	pthread_t exitedThread = 0;
	pthread_mutex_lock(&gAllUPSDevicesLock);
	if (gUPSWatchThread && gWatchThreadExited && !UPSWatching) {
		exitedThread = gUPSWatchThread;
		gUPSWatchThread = 0;
		gWatchThreadExited = false;
	} else if (UPSWatching || gUPSWatchThread || gWatchThreadStarting) {
		pthread_mutex_unlock(&gAllUPSDevicesLock);
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}
	gWatchThreadStarting = true;
	gWatchThreadReady = false;
	gTerminationInProgress = false;
	gNotificationsPaused = false;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	if (exitedThread) pthread_join(exitedThread, NULL);
	
	// Keep the watch thread joinable so cleanup can synchronize ownership.
	pthread_t thread = 0;
	pthread_attr_t attrs;
	pthread_attr_init(&attrs);
	
	pthread_mutex_lock(&gAllUPSDevicesLock);
	bool cancelled = gTerminationInProgress;
	int err = cancelled ? 0 : pthread_create(&thread, &attrs, threadMain, NULL);
	if (!cancelled && !err) {
		gUPSWatchThread = thread;
		UPSWatching = true;
		gWatchThreadExited = false;
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		[nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
		[nc removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
		[nc removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
		[nc addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
		[nc addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
		[nc addObserver:self selector:@selector(appWillTerminate:) name:UIApplicationWillTerminateNotification object:nil];
		signal(SIGINT, SignalHandler);
		signal(SIGTERM, SignalHandler);
	}
	gWatchThreadStarting = false;
	pthread_mutex_unlock(&gAllUPSDevicesLock);
	pthread_attr_destroy(&attrs);
	if (cancelled) {
		pthread_mutex_unlock(&gWatchLifecycleLock);
		return;
	}
	
	if (err) {
		NSLog(@"[UPSMonitor] Failed to create UPS‐watch thread: %d", err);
	} else {
		pthread_mutex_lock(&gAllUPSDevicesLock);
		while (!gWatchThreadReady && !gWatchThreadExited) {
			pthread_cond_wait(&gWatchStateCondition, &gAllUPSDevicesLock);
		}
		bool ready = gWatchThreadReady;
		pthread_mutex_unlock(&gAllUPSDevicesLock);
		if (ready) {
			NSLog(@"[UPSMonitor] UPS‐watch thread launched.");
		} else {
			pthread_join(thread, NULL);
			pthread_mutex_lock(&gAllUPSDevicesLock);
			if (pthread_equal(gUPSWatchThread, thread)) gUPSWatchThread = 0;
			UPSWatching = false;
			gWatchThreadExited = false;
			pthread_mutex_unlock(&gAllUPSDevicesLock);
			NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
			[nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
			[nc removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
			[nc removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
			NSLog(@"[UPSMonitor] UPS‐watch thread failed during initialization.");
		}
	}
	pthread_mutex_unlock(&gWatchLifecycleLock);
}

// manually stop monitoring (useful for testing ig)
+ (void)stopWatchingUPS
{
	NSLog(@"[UPSMonitor] Manually stopping UPS monitoring");
	pthread_mutex_lock(&gWatchLifecycleLock);
	[self _cleanupAllResourcesLocked];
	
	// Remove notification observers
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
	[nc removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
	[nc removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
	pthread_mutex_unlock(&gWatchLifecycleLock);
}

@end
