#pragma once

#include <Availability.h>

/*
If building with Theos iOS 9.3 sdk, please remove liblaunch.dylib from libSystem.B.tbd
Tested:
- iPhoneOS9.3.sdk
- iPhoneOS10.3.sdk
- iPhoneOS11.4.sdk
- iPhoneOS12.4.sdk
- iPhoneOS13.7.sdk
- iPhoneOS14.5.sdk

This project targets iOS 14.*, building with newer sdks is not recommended.

TODO: Test on such iOS versions
*/

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 100000
#define TARGET_OS_OSX 0
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 140000
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 120000
#undef __OSX_AVAILABLE_STARTING
#define __OSX_AVAILABLE_STARTING(a,b) 
#else
#undef API_UNAVAILABLE
#define API_UNAVAILABLE(...)
#endif
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 130000
#ifdef __OBJC__

#import <UIKit/UIKit.h>

// Keep the iOS 13 enum value when building with an older SDK. All uses are
// runtime guarded; aliasing to Grouped would defeat the iOS 13+ layout choice.
#define UITableViewStyleInsetGrouped ((UITableViewStyle)2)

@interface UIColor ()
+ (instancetype)secondaryLabelColor;
+ (instancetype)systemRedColor;
+ (instancetype)systemYellowColor;
// systemRedColor is only defined after iOS 13.0, although Apple documentation
// 	suggests that it is available since iOS 7.0.
+ (instancetype)linkColor;
+ (instancetype)systemBackgroundColor;
+ (instancetype)systemBlueColor;
+ (instancetype)secondarySystemFillColor;
+ (instancetype)colorWithDynamicProvider:(id)dp;
+ (instancetype)labelColor;
+ (instancetype)tertiarySystemFillColor;
@end

@interface UIImage ()
+ (instancetype)systemImageNamed:(NSString *)name;
@end

@interface NSDate ()
+ (instancetype)now;
@end

@interface UIView ()
#if __ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ < 110000
@property (nonatomic, strong, readonly) UILayoutGuide *safeAreaLayoutGuide;
#endif
@end

// Marked unavailable below iOS 13
//#define CGColorCreateGenericRGB ((CGColorRef(*)(CGFloat,CGFloat,CGFloat,CGFloat))dlsym(NULL,"_CGColorCreateGenericRGB"))

@interface TraitCollection__define : NSObject
- (NSInteger)userInterfaceStyle;
@end
#define UIUserInterfaceStyleDark 2

#if __ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ < 100000
typedef id NSKeyValueChangeKey;
#endif

#endif
#endif
