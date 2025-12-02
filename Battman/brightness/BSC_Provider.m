//
//  BSC_Provider.m
//  Battman
//
//  Created by Torrekie on 2025/11/3.
//

#import "../ObjCExt/NSBundle+Auto.h"
#import "libbrightness.h"
#import "../common.h"

Class BrightnessSystemClient = nil;

id<BrightnessSystemClientProtocol> BrightnessSystemClient_sharedClient(void) {
	static dispatch_once_t once;
	static id<BrightnessSystemClientProtocol> BSC = nil;
	if (once != -1) {
		dispatch_once(&once, ^{
			NSBundle *cb = [NSBundle systemBundleWithName:@"corebrightness" fallbackExecutable:@"CoreBrightness"];
			NSError *err = nil;
			if (![cb loadAndReturnError:&err]) {
				DBGLOG(@"Failed to load CoreBrightness: %@", err.localizedDescription);
				return;
			}
			BrightnessSystemClient = [cb classNamed:@"BrightnessSystemClient"];
			BSC = [BrightnessSystemClient new];
		});
	}
	return BSC;
}
#define sharedClient BrightnessSystemClient_sharedClient()

bool als_supported(void) {
	return [sharedClient isAlsSupported];
}

bool blr_supported(void) {
	return MGGetBoolAnswerPtr(CFSTR("F1Xz9g1JORibBS9DYPUPrg"));
}

bool adaption_supported(void) {
	return [[sharedClient copyPropertyForKey:@"SupportedColorFX"][@"SupportsAmbientColorAdaptation"] boolValue];
}

#define DICTCPY(buf, dict, key, type) buf.key = [dict[@ #key] type ## Value]

VirtualBrightnessLimits brightness_limits(void) {
	VirtualBrightnessLimits buf = {0};
	NSDictionary *dict = [sharedClient copyPropertyForKey:@"VirtualBrightnessLimits"];
	if (dict) {
		DICTCPY(buf, dict, DigitalDimmingSupported, bool);
		DICTCPY(buf, dict, ExtrabrightEDRSupported, bool);
		DICTCPY(buf, dict, HardwareAccessibleMaxNits, int);
		DICTCPY(buf, dict, HardwareAccessibleMinNits, int);
		DICTCPY(buf, dict, MinNitsAccessibleWithDigitalDimming, int);
		DICTCPY(buf, dict, UserAccessibleMaxNits, int);
	}
	return buf;
}

DisplayBrightness display_brightness(void) {
	DisplayBrightness buf = {0};
	NSDictionary *dict = [sharedClient copyPropertyForKey:@"DisplayBrightness"];
	if (dict) {
		DICTCPY(buf, dict, Brightness, float);
		DICTCPY(buf, dict, Nits, float);
		DICTCPY(buf, dict, NitsPhysical, float);
	}
	return buf;
}

bool set_display_brightness(bool by_percentage, double value, bool commit) {
	CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	CFDictionaryAddValue(dict, by_percentage ? CFSTR("Brightness") : CFSTR("Nits"), (__bridge CFNumberRef)@(value));
	if (commit)
		CFDictionaryAddValue(dict, CFSTR("Commit"), kCFBooleanTrue);
	[sharedClient setProperty:(__bridge id)(dict) forKey:@"DisplayBrightness"];
	if (dict) {
		CFRelease(dict);
		return true;
	}
	return false;
}
