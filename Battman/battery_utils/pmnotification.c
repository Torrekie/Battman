#include "../common.h"
#include "../iokitextern.h"
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFNotificationCenter.h>
#include <stdint.h>
#include <stdlib.h>

#if __has_include(<IOKit/IOKitKeys.h>)
#include <IOKit/IOKitKeys.h>
#else
#define kIOFirstMatchNotification "IOServiceFirstMatch"
#define kIOGeneralInterest "IOGeneralInterest"
#endif

#if __has_include(<dispatch/dispatch.h>)
#include <dispatch/dispatch.h>
#else
extern void *dispatch_get_global_queue(int, int);
#endif

/* The queue and context have process lifetime. IOKit retains refCon after
 * registration returns; neither callback may point into a caller's stack. */
dispatch_queue_t _powerQueue = NULL;
static char powerQueueKey;
typedef void (*PowerEventCallback)(int, io_registry_entry_t, int32_t);
typedef struct PowerInterest {
	uint64_t registryID;
	io_object_t notification;
	struct PowerInterest *next;
} PowerInterest;
static struct {
	IONotificationPortRef port;
	io_iterator_t iterator;
	PowerEventCallback callback;
	PowerInterest *interests;
	uintptr_t generation;
	bool initialized;
	bool suspended;
} powerMonitor;

static void onPowerQueue(dispatch_block_t block) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		_powerQueue = dispatch_queue_create("com.torrekie.Battman.pmEvents", DISPATCH_QUEUE_SERIAL);
		dispatch_queue_set_specific(_powerQueue, &powerQueueKey, &powerQueueKey, NULL);
	});
	if (dispatch_get_specific(&powerQueueKey))
		block();
	else
		dispatch_sync(_powerQueue, block);
}

static void powerInterestChanged(void *refCon, io_service_t service,
                                 uint32_t messageType, void *messageArgument) {
	(void)messageArgument;
	/* A late delivery from a destroyed port cannot enter a newer subscription. */
	if (!powerMonitor.initialized || powerMonitor.suspended ||
	    (uintptr_t)refCon != powerMonitor.generation)
		return;
	PowerEventCallback callback = powerMonitor.callback;
	if (callback)
		callback(0, service, (int32_t)messageType);
}

static void stpe_cb(void *refCon, io_iterator_t iterator) {
	if (refCon != &powerMonitor || !powerMonitor.initialized ||
	    iterator != powerMonitor.iterator)
		return;
	io_object_t service;
	while ((service = IOIteratorNext(iterator))) {
		uint64_t registryID = 0;
		bool duplicate = false;
		if (IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS) {
			for (PowerInterest *item = powerMonitor.interests; item; item = item->next)
				if (item->registryID == registryID) { duplicate = true; break; }
		} else {
			IOObjectRelease(service);
			continue;
		}
		PowerInterest *interest = duplicate ? NULL : calloc(1, sizeof(*interest));
		if (interest) {
			kern_return_t error = IOServiceAddInterestNotification(powerMonitor.port,
			    service, kIOGeneralInterest, powerInterestChanged,
			    (void *)powerMonitor.generation, &interest->notification);
			if (error == KERN_SUCCESS) {
				interest->registryID = registryID;
				interest->next = powerMonitor.interests;
				powerMonitor.interests = interest;
			} else {
				if (interest->notification) IOObjectRelease(interest->notification);
				free(interest);
				os_log_error(gLog, "[pmnotification] Failed to register interest: %d", error);
			}
		}
		IOObjectRelease(service);
	}
}

static void cleanupPowerMonitoringOnQueue(void) {
	powerMonitor.initialized = false;
	powerMonitor.suspended = false;
	powerMonitor.callback = NULL;
	++powerMonitor.generation;
	if (powerMonitor.port)
		IONotificationPortSetDispatchQueue(powerMonitor.port, NULL);
	while (powerMonitor.interests) {
		PowerInterest *interest = powerMonitor.interests;
		powerMonitor.interests = interest->next;
		IOObjectRelease(interest->notification);
		free(interest);
	}
	if (powerMonitor.iterator) {
		IOObjectRelease(powerMonitor.iterator);
		powerMonitor.iterator = MACH_PORT_NULL;
	}
	if (powerMonitor.port) {
		IONotificationPortDestroy(powerMonitor.port);
		powerMonitor.port = NULL;
	}
}

void suspendPowerEventMonitoring(void) {
	onPowerQueue(^{
		if (!powerMonitor.initialized || powerMonitor.suspended) return;
		powerMonitor.suspended = true;
		IONotificationPortSetDispatchQueue(powerMonitor.port, NULL);
	});
}

void resumePowerEventMonitoring(void) {
	onPowerQueue(^{
		if (!powerMonitor.initialized || !powerMonitor.suspended) return;
		powerMonitor.suspended = false;
		IONotificationPortSetDispatchQueue(powerMonitor.port, _powerQueue);
		stpe_cb(&powerMonitor, powerMonitor.iterator);
	});
}

void cleanupPowerEventMonitoring(void) {
	/* Never suspend the serial queue: teardown can drain every earlier callback
	 * before releasing its IOKit objects, including while the app is backgrounded. */
	onPowerQueue(^{ cleanupPowerMonitoringOnQueue(); });
}

void subscribeToPowerEvents(PowerEventCallback callback) {
	if (!callback) return;
	onPowerQueue(^{
		/* The constructor subscribes before daemon_main replaces the callback.
		 * Reuse that registration instead of leaking a second port and notifier. */
		if (powerMonitor.initialized) {
			powerMonitor.callback = callback;
			return;
		}
		powerMonitor.port = IONotificationPortCreate(kIOMasterPortDefault);
		if (!powerMonitor.port) {
			os_log_error(gLog, "[pmnotification] Failed to create IONotificationPort");
			return;
		}
		powerMonitor.callback = callback;
		++powerMonitor.generation;
		powerMonitor.initialized = true;
		IONotificationPortSetDispatchQueue(powerMonitor.port, _powerQueue);
		kern_return_t error = IOServiceAddMatchingNotification(powerMonitor.port,
		    kIOFirstMatchNotification, IOServiceMatching("IOPMPowerSource"),
		    stpe_cb, &powerMonitor, &powerMonitor.iterator);
		if (error != KERN_SUCCESS) {
			os_log_error(gLog, "[pmnotification] Failed to register matching notification: %d", error);
			cleanupPowerMonitoringOnQueue();
			return;
		}
		stpe_cb(&powerMonitor, powerMonitor.iterator);
	});
}

void pmncb(int a, io_registry_entry_t b, int32_t c) {
	// Check if we're in the middle of shutdown
	if (!powerMonitor.initialized || powerMonitor.suspended) {
		return;
	}

	if (c != -536723200)
		return;
	CFMutableDictionaryRef props;
	int ret = IORegistryEntryCreateCFProperties(b, &props, 0, 0);
	if (ret != 0) {
		os_log_error(gLog, "[pmnotification] Failed to get CFProperties from notification");
		return;
	}
	//CFStringRef desc=CFCopyDescription(props);
	//CFRelease(props);
	//NSLog(CFSTR("Power Update: %@"),desc);
	//show_alert("Power",CFStringGetCStringPtr(desc,0x08000100),"ok");
	//CFRelease(desc);
	CFNotificationCenterPostNotification(CFNotificationCenterGetLocalCenter(), CFSTR("SMC60000"), NULL, props, 1);
	CFRelease(props);
}

__attribute__((constructor)) static void startpmn() { subscribeToPowerEvents(pmncb); }
__attribute__((destructor)) static void stoppmn() { cleanupPowerEventMonitoring(); }
