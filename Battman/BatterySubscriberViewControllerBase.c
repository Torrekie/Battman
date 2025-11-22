#include "cobjc/cobjc.h"
#include "common.h"
#include "BattmanPrefs.h"
#include <string.h>

// Extern UIApplication notification names as CFStringRef
extern CFStringRef const UIApplicationDidEnterBackgroundNotification;
extern CFStringRef const UIApplicationWillEnterForegroundNotification;

// Static variable to track if notifications are paused
static BOOL gNotificationsPaused = NO;

// Timer management structure for each view controller instance
typedef struct {
	NSTimer *refreshTimer;
	float currentInterval;
	BOOL isAutoMode;
	BOOL isNeverMode;
	BOOL isInitialized;
} BSVCTimerContext;

// Helper function to get timer context from view controller
static BSVCTimerContext *BSVCGetTimerContext(id self) {
	if (!self) return NULL;
	
	// Verify this is actually a BatterySubscriberViewControllerBase instance
	if (!NSObjectIsKindOfClass(self, BatterySubscriberViewControllerBase)) {
		return NULL;
	}
	
	BSVCTimerContext *context = (BSVCTimerContext *)COBJC_STRUCT(BatterySubscriberViewControllerBase, self);
	if (!context)
		return NULL;
	
	// Lazily initialize the context to ensure safe defaults before first use
	if (!context->isInitialized) {
		memset(context, 0, sizeof(BSVCTimerContext));
		context->refreshTimer   = NULL;
		context->currentInterval = 0.0f;
		context->isAutoMode     = YES;
		context->isNeverMode    = NO;
		context->isInitialized  = YES;
	}
	
	return context;
}

// Timer callback function
void BSVCTimerFired(id self, void *unused, NSTimer *timer) {
	if (!self) return;
	
	// Additional safety check - verify the context is still valid
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	if (!context || !context->refreshTimer || context->refreshTimer != timer) {
		// Timer is stale or context is invalid, invalidate it
		if (timer && NSTimerIsValid(timer)) {
			NSTimerInvalidate(timer);
		}
		return;
	}
	
	// Only call updateTableView if we're still in timer mode
	if (!context->isAutoMode && !context->isNeverMode && context->currentInterval > 0.0f) {
		if (ocall(self, respondsToSelector:, oselector(updateTableView)))
			ocall(self, updateTableView);
	}
}

// Update refresh mode based on preferences
static void BSVCUpdateRefreshMode(id self) {
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	if (!context) return;
	
	float interval = BattmanPrefsGetFloat(kBattmanPrefs_BI_INTERVAL);
	
	// Stop existing timer if any
	if (context->refreshTimer && NSTimerIsValid(context->refreshTimer)) {
		NSTimerInvalidate(context->refreshTimer);
		NSObjectRelease(context->refreshTimer);
		context->refreshTimer = NULL;
	}
	
	context->currentInterval = interval;
	context->isAutoMode = (interval == 0.0f);
	context->isNeverMode = (interval == -1.0f);
	
	// Start new timer if interval > 0
	if (interval > 0.0f) {
		context->refreshTimer = NSTimerScheduledTimerWithTimeInterval(
			interval, self, oselector(BSVCTimerFired:), NULL, YES);
		NSObjectRetain(context->refreshTimer);
	}
}

void BSVCBatteryStatusDidUpdateWithInfo(id self, void *emptyRef, CFDictionaryRef info) {
	if (!self) return;
	
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	// Only respond to IOKit events in auto mode (interval == 0.0f)
	if (context && context->isAutoMode && !context->isNeverMode) {
		ocall(self, batteryStatusDidUpdate);
	}
}

static void BSVCBatteryStatusCallback1(void **userInfo) {
	if (!userInfo || !userInfo[0]) return;
	
	id self = userInfo[0];
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	// Only respond to IOKit events in auto mode (interval == 0.0f)
	if (context && context->isAutoMode && !context->isNeverMode) {
		ocall(userInfo[0], batteryStatusDidUpdate:, userInfo[1]);
	}
}

static void BSVCBatteryStatusCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	if (gNotificationsPaused) {
		return;
	}

	void *observerAndUserInfo[2] = {
		observer,
		(void *)userInfo
	};
	dispatch_sync_f(dispatch_get_main_queue(), observerAndUserInfo, (void (*)(void *))BSVCBatteryStatusCallback1);
	// stack variable is ok bc it waits until execution finishes
}

// CFNotificationCenter callback for app lifecycle events
static void BSVCAppLifecycleCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	if (CFStringCompare(name, UIApplicationDidEnterBackgroundNotification, 0) == kCFCompareEqualTo) {
		gNotificationsPaused = YES;
		DBGLOG(CFSTR("BSVC PAUSE"));
		// Pause timer when going to background
		BSVCTimerContext *context = BSVCGetTimerContext(observer);
		if (context && context->refreshTimer && NSTimerIsValid(context->refreshTimer)) {
			NSTimerInvalidate(context->refreshTimer);
		}
	} else if (CFStringCompare(name, UIApplicationWillEnterForegroundNotification, 0) == kCFCompareEqualTo) {
		gNotificationsPaused = NO;
		DBGLOG(CFSTR("BSVC RESUME"));
		// Resume timer and update refresh mode when coming to foreground
		BSVCUpdateRefreshMode(observer);
		dispatch_async(dispatch_get_main_queue(), ^{
			BSVCTimerContext *context = BSVCGetTimerContext(observer);
			// Only trigger update in auto mode when coming to foreground
			if (context && context->isAutoMode && !context->isNeverMode) {
				ocall(observer, batteryStatusDidUpdate);
			}
		});
	}
}

void BSVCBatteryStatusDidUpdate(id self) {
	if (!self) return;
	
	DBGLOG(CFSTR("BSVC: didUpdate: %@"), self);
	
	// Check refresh mode - only update in auto mode
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	if (context && context->isAutoMode && !context->isNeverMode) {
		//UITableViewReloadData(UITableViewControllerGetTableView(self));
		// Call either [BatteryInfoViewController updateTableView] or [BatteryDetailsViewController updateTableView]
		// instead of UITableViewReloadData(UITableViewControllerGetTableView(self));
		if (ocall(self, respondsToSelector:, oselector(updateTableView)))
			ocall(self, updateTableView);
	}
}

void BSVCViewDidDisappear(id self, void *er, BOOL animated) {
	osupercall(BatterySubscriberViewControllerBase, self, viewDidDisappear:, animated);
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), self, CFSTR("SMC60000"), NULL);

	CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), self, UIApplicationDidEnterBackgroundNotification, NULL);
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(), self, UIApplicationWillEnterForegroundNotification, NULL);
	
	// Clean up timer
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	if (context && context->refreshTimer) {
		if (NSTimerIsValid(context->refreshTimer)) {
			NSTimerInvalidate(context->refreshTimer);
		}
		NSObjectRelease(context->refreshTimer);
		context->refreshTimer = NULL;
	}
}

void BSVCViewDidAppear(id self, void *er, BOOL animated) {
	osupercall(BatterySubscriberViewControllerBase, self, viewDidAppear:, animated);
	CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), self, BSVCBatteryStatusCallback, CFSTR("SMC60000"), NULL, CFNotificationSuspensionBehaviorDrop);

	CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), self, BSVCAppLifecycleCallback, UIApplicationDidEnterBackgroundNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), self, BSVCAppLifecycleCallback, UIApplicationWillEnterForegroundNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	
	// Initialize timer context and set up refresh mode
	BSVCTimerContext *context = BSVCGetTimerContext(self);
	if (context) {
		// Zero out the entire context for safety
		memset(context, 0, sizeof(BSVCTimerContext));
		
		// Initialize context with default values
		context->refreshTimer = NULL;
		context->currentInterval = 0.0f;
		context->isAutoMode = YES;
		context->isNeverMode = NO;
		
		// Set up refresh mode based on preferences
		BSVCUpdateRefreshMode(self);
	}
}

// Public function to update refresh mode (can be called from Objective-C)
void BSVCRefreshModeDidUpdate(id self) {
	BSVCUpdateRefreshMode(self);
}

MAKE_CLASS(BatterySubscriberViewControllerBase, UITableViewController, 32,
    ,
    BSVCBatteryStatusDidUpdateWithInfo, batteryStatusDidUpdate:,
    BSVCBatteryStatusDidUpdate, batteryStatusDidUpdate,
    BSVCViewDidDisappear, viewDidDisappear:,
    BSVCViewDidAppear, viewDidAppear:,
    BSVCTimerFired, BSVCTimerFired:
)
