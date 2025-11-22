//
//  backlight-control.c
//  Battman
//
//  Created by Torrekie on 2025/11/13.
//

#include "libbrightness.h"
#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../iokitextern.h"

static CFMutableDictionaryRef gBacklightProps = NULL;

static io_service_t _get_fresh_service(void) {
	io_service_t service = MACH_PORT_NULL;
	// Isn't these two same?
	if (dcp_backlight()) {
		service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching("AppleARMBacklight"));
	} else {
		CFStringRef cfstr = CFSTR("backlight-control");
		CFDictionaryRef backlightctrl = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&cfstr, (const void **)&kCFBooleanTrue, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		cfstr = CFSTR("IOPropertyMatch");
		CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, (const void **)&cfstr, (const void **)&backlightctrl, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		CFRelease(backlightctrl);

		service = IOServiceGetMatchingService(kIOMasterPortDefault, matching);
		CFRelease(matching);
	}
	return service;
}

static bool _is_service_valid(io_service_t service) {
	if (service == MACH_PORT_NULL)
		return false;

	CFMutableDictionaryRef props = NULL;
	kern_return_t kr = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, kNilOptions);
	if (kr == KERN_SUCCESS && props) {
		if (gBacklightProps) CFRelease(gBacklightProps);
		gBacklightProps = props;
		return true;
	}

	return false;
}

io_service_t backlight_service(void) {
	static io_service_t service = MACH_PORT_NULL;
	static dispatch_once_t onceToken;
	static dispatch_queue_t queue = NULL;
	
	dispatch_once(&onceToken, ^{
		queue = dispatch_queue_create("com.torrekie.Battman.backlight-service", DISPATCH_QUEUE_SERIAL);
		service = _get_fresh_service();
	});
	
	__block io_service_t result = MACH_PORT_NULL;
	dispatch_sync(queue, ^{
		if (!_is_service_valid(service)) {
			if (gBacklightProps) {
				CFRelease(gBacklightProps);
				gBacklightProps = NULL;
			}
			if (service != MACH_PORT_NULL) {
				IOObjectRelease(service);
			}
			service = _get_fresh_service();
		}
		result = service;
	});

	return result;
}

#define returnIfNoBacklight(x) { if (backlight_service() == MACH_PORT_NULL) return x; }

float backlight_percent(void) {
	float ret = -1.0f;

	returnIfNoBacklight(ret);

	if (!gBacklightProps)
		return ret;

	// Navigate: IODisplayParameters -> brightness -> value/max/min
	CFTypeRef displayParams = CFDictionaryGetValue(gBacklightProps, CFSTR("IODisplayParameters"));
	if (!displayParams || CFGetTypeID(displayParams) != CFDictionaryGetTypeID())
		return ret;

	// DCP writes MilliNits, DFR writes raw values
	CFTypeRef brightness = CFDictionaryGetValue((CFDictionaryRef)displayParams, dcp_backlight() ? CFSTR("BrightnessMilliNits") : CFSTR("brightness"));
	if (!brightness || CFGetTypeID(brightness) != CFDictionaryGetTypeID())
		return ret;

	CFDictionaryRef brightnessDict = (CFDictionaryRef)brightness;
	CFTypeRef valueRef = CFDictionaryGetValue(brightnessDict, CFSTR("value"));
	CFTypeRef maxRef = CFDictionaryGetValue(brightnessDict, CFSTR("max"));
	CFTypeRef minRef = CFDictionaryGetValue(brightnessDict, CFSTR("min"));

	if (!valueRef || !maxRef || !minRef || CFGetTypeID(valueRef) != CFNumberGetTypeID() || CFGetTypeID(maxRef) != CFNumberGetTypeID() || CFGetTypeID(minRef) != CFNumberGetTypeID())
		return ret;

	int64_t value = 0, max = 0, min = 0;
	if (!CFNumberGetValue((CFNumberRef)valueRef, kCFNumberSInt64Type, &value) || !CFNumberGetValue((CFNumberRef)maxRef, kCFNumberSInt64Type, &max) || !CFNumberGetValue((CFNumberRef)minRef, kCFNumberSInt64Type, &min))
		return ret;

	float value_f = (float)value * pow(2, -16);
	float max_f = (float)max * pow(2, -16);
	float min_f = (float)min * pow(2, -16);

	if (max_f == min_f)
		return -1.0f;

	ret = ((value_f - min_f) / (max_f - min_f));
	return ret;
}
