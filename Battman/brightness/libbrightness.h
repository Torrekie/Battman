//
//  libbrightness.h
//  Battman
//
//  Created by Torrekie on 2025/11/3.
//

#include <stdbool.h>
#include <objc/message.h>
#include <CoreFoundation/CoreFoundation.h>
#include "../iokitextern.h"

#ifdef __OBJC__
#import <Foundation/Foundation.h>

@protocol BrightnessSystemClientProtocol <NSObject>
- (id)copyPropertyForKey:(NSString *)key;
- (BOOL)isAlsSupported;
- (void)setProperty:(id)property forKey:(NSString *)key;
@end

#else

__BEGIN_DECLS

extern Class BrightnessSystemClient;

__END_DECLS
#endif

typedef struct VirtualBrightnessLimits {
	bool DigitalDimmingSupported;
	bool ExtrabrightEDRSupported;
	int HardwareAccessibleMaxNits;
	int HardwareAccessibleMinNits;
	int MinNitsAccessibleWithDigitalDimming;
	int UserAccessibleMaxNits;
} VirtualBrightnessLimits;

typedef struct DisplayBrightness {
	float Brightness;
	float Nits;
	float NitsPhysical;
} DisplayBrightness;

__BEGIN_DECLS

// ALS: Ambient Light Sensor
bool als_supported(void);

// BLR: Blue Light Reduction (Night Shift)
bool blr_supported(void);

// Adaption: Ambient Color Adaption (True Tone)
bool adaption_supported(void);

// If current device using DCP brightness control (What is DCP?)
bool dcp_backlight(void);


VirtualBrightnessLimits brightness_limits(void);

// User-Level brightness info
DisplayBrightness display_brightness(void);

// User-Level set brightness, value is nits or percentage
bool set_display_brightness(bool by_percentage, double value, bool commit);

io_service_t backlight_service(void);

// Get current backlight brightness as a percentage (0.0-1.0)
// Returns -1.0 on error
float backlight_percent(void);

__END_DECLS
