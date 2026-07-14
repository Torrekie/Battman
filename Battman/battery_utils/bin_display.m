//
//  bin_display.m
//  Battman
//
//  Display-side formatting for battery_info values and temperatures.
//

#import <Foundation/Foundation.h>

#include "bin_display.h"
#include "battery_info.h"
#include "../BattmanPrefs.h"
#include "../common.h"

static int gSystemFahrenheit = -1; /* -1 = unresolved */

static void locale_changed_cb(CFNotificationCenterRef center, void *observer,
    CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
	gSystemFahrenheit = -1;
}

static BattmanTempUnitPref battman_temp_display_pref(void) {
	NSInteger pref = BattmanPrefsGetInt(kBattmanPrefs_TEMPERATURE_UNIT);
	if (pref < BattmanTempUnitSystem || pref > BattmanTempUnitFahrenheit)
		return BattmanTempUnitSystem;
	return (BattmanTempUnitPref)pref;
}

static NSMeasurement *battman_temp_measurement(double celsius) {
	return [[NSMeasurement alloc] initWithDoubleValue:celsius unit:[NSUnitTemperature celsius]];
}

static NSUnitTemperature *battman_temp_unit_for_pref(BattmanTempUnitPref pref) {
	switch (pref) {
		case BattmanTempUnitCelsius:
			return [NSUnitTemperature celsius];
		case BattmanTempUnitFahrenheit:
			return [NSUnitTemperature fahrenheit];
		case BattmanTempUnitSystem:
		default:
			return nil;
	}
}

static NSMeasurementFormatter *battman_temp_formatter(NSMeasurementFormatterUnitOptions unitOptions) {
	NSNumberFormatter *numberFormatter = [NSNumberFormatter new];
	numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
	numberFormatter.usesSignificantDigits = YES;
	numberFormatter.maximumSignificantDigits = 4;

	NSMeasurementFormatter *formatter = [NSMeasurementFormatter new];
	formatter.locale = [NSLocale autoupdatingCurrentLocale];
	formatter.numberFormatter = numberFormatter;
	formatter.unitOptions = unitOptions;
	formatter.unitStyle = NSFormattingUnitStyleShort;
	return formatter;
}

static NSString *battman_temp_display_string_for_pref(double celsius, BattmanTempUnitPref pref) {
	NSMeasurement *measurement = battman_temp_measurement(celsius);
	NSUnitTemperature *unit = battman_temp_unit_for_pref(pref);
	NSMeasurementFormatterUnitOptions unitOptions = NSMeasurementFormatterUnitOptionsNaturalScale;
	if (unit) {
		measurement = [measurement measurementByConvertingToUnit:unit];
		unitOptions = NSMeasurementFormatterUnitOptionsProvidedUnit;
	}

	return [battman_temp_formatter(unitOptions) stringFromMeasurement:measurement];
}

static bool battman_temp_string_mentions_fahrenheit(NSString *string) {
	return [string rangeOfString:@"F" options:NSCaseInsensitiveSearch].location != NSNotFound ||
	       [string rangeOfString:@"℉"].location != NSNotFound;
}

static bool battman_temp_resolve_system_fahrenheit(void) {
	NSString *system = battman_temp_display_string_for_pref(0.0, BattmanTempUnitSystem);
	NSString *fahrenheit = battman_temp_display_string_for_pref(0.0, BattmanTempUnitFahrenheit);
	NSString *celsius = battman_temp_display_string_for_pref(0.0, BattmanTempUnitCelsius);

	if ([system isEqualToString:fahrenheit])
		return true;
	if ([system isEqualToString:celsius])
		return false;

	return battman_temp_string_mentions_fahrenheit(system);
}

bool battman_temp_system_fahrenheit(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
		    NULL, locale_changed_cb, kCFLocaleCurrentLocaleDidChangeNotification,
		    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	});
	if (gSystemFahrenheit < 0)
		gSystemFahrenheit = battman_temp_resolve_system_fahrenheit() ? 1 : 0;
	return gSystemFahrenheit;
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
	NSUnitTemperature *unit = battman_temp_display_fahrenheit() ? [NSUnitTemperature fahrenheit]
	                                                            : [NSUnitTemperature celsius];
	return [[battman_temp_measurement(celsius) measurementByConvertingToUnit:unit] doubleValue];
}

NSString *battman_temp_display_string(double celsius) {
	return battman_temp_display_string_for_pref(celsius, battman_temp_display_pref());
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
	NSString *number_format = is_float
	    ? ((content & BIN_FORMAT_FIXED_2) ? @"%.2f" : @"%.4g")
	    : @"%.0f";

	if (content & BIN_HAS_UNIT) {
		uint32_t unit_index = BIN_UNIT_INDEX(content);
		if (unit_index >= BIN_UNIT_COUNT)
			return [NSString stringWithFormat:number_format, value];

		bin_unit_formatter_t fmt = bin_unit_formatters[unit_index];
		if (fmt)
			return fmt(content, value);
		return [NSString stringWithFormat:[number_format stringByAppendingString:@" %@"],
		        value, _(bin_unit_strings[unit_index])];
	}
	return [NSString stringWithFormat:number_format, value];
}
