//
//  bin_display.h
//  Battman
//
//  Display-side formatting for battery_info values and temperatures.
//

#ifndef bin_display_h
#define bin_display_h

#include <stdbool.h>
#include <stdint.h>
#include <sys/cdefs.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

__BEGIN_DECLS

/* Display-only helpers: preferences, sensor plumbing and any math
 * (thermometer ranges, arc percentages, gradients) stay in Celsius.
 * Convert at the label, never before. */
bool   battman_temp_display_fahrenheit(void);
/* Resolved system-locale default, ignoring the user override.
 * Exposed for labeling the "System" choice in preferences. */
bool   battman_temp_system_fahrenheit(void);
double battman_temp_display_value(double celsius);

#ifdef __OBJC__
/* "36.5 ℃" / "97.7 °F" per the resolved display unit */
NSString *battman_temp_display_string(double celsius);
/* Formatted value (+ unit) for any BIN_IS_SPECIAL battery_info content */
NSString *bin_format_special(uint32_t content);
#endif

__END_DECLS

#endif /* bin_display_h */
