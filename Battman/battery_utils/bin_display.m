//
//  bin_display.m
//  Battman
//
//  Display-side formatting for battery_info values and temperatures.
//

#import <Foundation/Foundation.h>
#include <string.h>

#include "bin_display.h"
#include "battery_info.h"
#include "../BattmanPrefs.h"
#include "../common.h"

static int gLocaleFahrenheit = -1; /* -1 = unresolved */

static void locale_changed_cb(CFNotificationCenterRef center, void *observer,
    CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	gLocaleFahrenheit = -1;
}

bool battman_temp_system_fahrenheit(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
		    NULL, locale_changed_cb, kCFLocaleCurrentLocaleDidChangeNotification,
		    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	});
	if (gLocaleFahrenheit < 0) {
		/* CLDR unitPreferenceData: regions preferring Fahrenheit, plus US
		 * territories. NSLocaleTemperatureUnit needs iOS 16, and
		 * NSLocaleUsesMetricSystem misclassifies both ways (LR/MM are
		 * non-metric Celsius; BS/BZ/KY/PW are metric Fahrenheit). */
		static const char *f_regions[] = {"US", "BS", "BZ", "KY", "PW", "PR",
		                                  "AS", "GU", "MP", "UM", "VI", NULL};
		char cc[3] = {0};
		CFLocaleRef locale = CFLocaleCopyCurrent();
		CFStringRef country = CFLocaleGetValue(locale, kCFLocaleCountryCode);
		if (country)
			CFStringGetCString(country, cc, sizeof(cc), kCFStringEncodingASCII);
		CFRelease(locale);
		gLocaleFahrenheit = 0;
		for (const char **r = f_regions; *r; r++) {
			if (strcmp(cc, *r) == 0) {
				gLocaleFahrenheit = 1;
				break;
			}
		}
	}
	return gLocaleFahrenheit;
}

bool battman_temp_display_fahrenheit(void) {
	switch ((BattmanTempUnitPref)BattmanPrefsGetInt(kBattmanPrefs_TEMPERATURE_UNIT)) {
		case BattmanTempUnitCelsius:
			return false;
		case BattmanTempUnitFahrenheit:
			return true;
		case BattmanTempUnitSystem:
		default:
			return battman_temp_system_fahrenheit();
	}
}

double battman_temp_display_value(double celsius) {
	return battman_temp_display_fahrenheit() ? celsius * 9.0 / 5.0 + 32.0 : celsius;
}

NSString *battman_temp_display_string(double celsius) {
	bool fahrenheit = battman_temp_display_fahrenheit();
	return [NSString stringWithFormat:@"%.4g %@",
	        fahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius,
	        fahrenheit ? _("°F") : _("℃")];
}

typedef NSString *(*bin_unit_formatter_t)(uint32_t content, double value);

static NSString *bin_fmt_temperature(uint32_t content, double value) {
	(void)content;
	return battman_temp_display_string(value);
}

static NSString *bin_fmt_minutes(uint32_t content, double value) {
	(void)content;
	return [NSString stringWithUTF8String:second_to_datefmt((uint64_t)(value * 60))];
}

/* Units needing more than the default number + bin_unit_strings[] suffix */
static const bin_unit_formatter_t bin_unit_formatters[BIN_UNIT_COUNT] = {
	[BIN_UNIT_INDEX(BIN_UNIT_DEGREE_C)] = bin_fmt_temperature,
	[BIN_UNIT_INDEX(BIN_UNIT_MIN)]      = bin_fmt_minutes,
};

static float bin_content_load_float(uint32_t content) {
	struct battery_info_node node = {0};
	node.content = content;
	return bi_node_load_float(&node);
}

NSString *bin_format_special(uint32_t content) {
	if ((content & BIN_IS_BOOLEAN) == BIN_IS_BOOLEAN)
		return ((int16_t)(content >> 16)) ? _("True") : _("False");

	bool   is_float = (content & BIN_IS_FLOAT) == BIN_IS_FLOAT;
	double value    = is_float ? (double)bin_content_load_float(content)
	                           : (double)(int16_t)(content >> 16);

	if (content & BIN_HAS_UNIT) {
		bin_unit_formatter_t fmt = bin_unit_formatters[BIN_UNIT_INDEX(content)];
		if (fmt)
			return fmt(content, value);
		return [NSString stringWithFormat:is_float ? @"%.4g %@" : @"%.0f %@",
		        value, _(bin_unit_strings[BIN_UNIT_INDEX(content)])];
	}
	return [NSString stringWithFormat:is_float ? @"%.4g" : @"%.0f", value];
}
