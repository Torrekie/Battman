#pragma once
#include "./cobjc.h"

typedef NSObject NSTimer;

DefineClassMethod(NSTimer, NSTimer *, NSTimerScheduledTimerWithTimeInterval, scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:, NSTimeInterval, id, SEL, id, BOOL);
DefineObjcMethod(void, NSTimerInvalidate, invalidate);
DefineObjcMethod(BOOL, NSTimerIsValid, isValid);
