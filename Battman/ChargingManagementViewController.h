#pragma once
#import <UIKit/UIKit.h>
#import "BatterySubscriberViewControllerBase.h"

@interface ChargingManagementViewController : BatterySubscriberViewControllerBase
{
	UIDatePicker *fromPicker;
	UIDatePicker *untilPicker;

	NSUserDefaults *batterysaver;
	NSUserDefaults *springboard;

	const char *batterysaver_notif;
	NSString *batterysaver_state;
	const char *system_lpm_notif;

	bool lpm_supported;
	bool lpm_on;
	float lpm_thr;

	int daemon_pid;
}
@end

@interface PowerUI_someinterface : NSObject
- (BOOL)setState:(NSUInteger)state error:(NSError **)err;
- (id)initWithClientName:(NSString *)name;
- (void)engageFrom:(NSDate *)f until:(NSDate*)u repeatUntil:(NSDate *)ru overrideAllSignals:(BOOL)oas;
@end

@interface CoreDuet_someinterface : NSObject
+ (id)batterySaver;
- (int)setMode:(int)mode;
- (BOOL)setPowerMode:(int)mode error:(NSError **)error;
- (long long)getPowerMode;
@end

// The LowPowerMode.framework is open source at PowerManagement
// CoreDuet _CDBatterySaver -> LowPowerMode _PMLowPowerMode
// coreduetd -> powerd
#if __has_include(<LowPowerMode/_PMLowPowerMode.h>)
#import <LowPowerMode/_PMLowPowerMode.h>
#else
typedef NS_ENUM(NSInteger, PMPowerMode) {
    PMNormalPowerMode = 0,
    PMLowPowerMode = 1
};

typedef void (^PMSetPowerModeCompletionHandler)(BOOL success, NSError *error);

@protocol _PMLowPowerModeProtocol

- (void)setPowerMode:(PMPowerMode)mode
          fromSource:(NSString *)source
      withCompletion:(PMSetPowerModeCompletionHandler)handler;

@end

@interface _PMLowPowerMode : NSObject <_PMLowPowerModeProtocol>

+ (instancetype)sharedInstance;

// Synchronous flavor. The one from Protocol is async.
- (BOOL)setPowerMode:(PMPowerMode)mode fromSource:(NSString *)source;
- (PMPowerMode)getPowerMode;

@end
#endif
