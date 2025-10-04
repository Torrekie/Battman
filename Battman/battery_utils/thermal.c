//
//  thermal.c
//  Battman
//
//  Created by Torrekie on 2025/7/11.
//

#include "thermal.h"
#include "../common.h"
#include <Availability.h>
#include <dlfcn.h>
#include <notify.h>
#include <sys/types.h>
// Avoid libkern/OSThermalNotification.h here
__OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_7_0)
extern const char *const kOSThermalNotificationPressureLevelName;

#define kOSThermalNotificationName GET_SECT_SYMBOL(const char *, kOSThermalNotificationName)

#define _OSThermalNotificationLevelForBehavior(x) DL_CALL(_OSThermalNotificationLevelForBehavior, int, (int), (x))
#define _OSThermalNotificationSetLevelForBehavior(x) DL_CALL(_OSThermalNotificationSetLevelForBehavior, void, (int), (x));
#define OSThermalNotificationCurrentLevel() DL_CALL(OSThermalNotificationCurrentLevel, int, (void), ());

#ifdef _C
#undef _C
#endif
// Gettext
#define _C(x) x
static const char *thermal_pressure_string[] = {
	_C("Nominal"),
	_C("Light"),
	_C("Moderate"),
	_C("Heavy"),
	_C("Trapping"),
	_C("Sleeping")
};
static const char *thermal_notif_level_string[] = {
	_C("Normal"),
	_C("70% Torch"),
	_C("70% Backlight"),
	_C("50% Torch"),
	_C("50% Backlight"),
	_C("Torch Disabled"),
	_C("25% Backlight"),
	_C("Maps halo Disabled"),
	_C("App Terminated"),
	_C("Device Restart"),
	_C("Ready")
};
#undef _C
#define _C(x) cond_localize_c(x)

const char *get_thermal_pressure_string(thermal_pressure_t pressure) {
	if (pressure < kBattmanThermalPressureLevelNominal)
		return L_ERR;

	if (pressure < kBattmanThermalPressureLevelUnknown)
		return _C(thermal_pressure_string[pressure]);

	static char numstr[32];
	sprintf(numstr, "%s (%d)", _C("Unknown"), pressure);
	return numstr;
}

const char *get_thermal_notif_level_string(thermal_notif_level_t level) {
	static char numstr[32];
	// Knowing a special value 8: thermtune controlled
	int realval = OSThermalNotificationCurrentLevel();

	if (level <= kBattmanThermalNotificationLevelAny)
		return L_NONE;

	if (level > kBattmanThermalNotificationLevelAny && level < kBattmanThermalNotificationLevelUnknown) {
		sprintf(numstr, "%s (%d)", _C(thermal_notif_level_string[level]), realval);
	} else {
		sprintf(numstr, "%s (%d)", _C("Unknown"), realval);
	}

	return numstr;
}

thermal_pressure_t thermal_pressure(void) {
	int      token;
	uint64_t level;

	if (notify_register_check(kOSThermalNotificationPressureLevelName, &token)) {
		return kBattmanThermalPressureLevelError;
	}
	if (notify_get_state(token, &level)) {
		return kBattmanThermalPressureLevelError;
	}
	if (notify_cancel(token)) {
		return kBattmanThermalPressureLevelError;
	}

	/* OSThermalPressureLevel, but compat both platforms */
	if (level == 0)
		return kBattmanThermalPressureLevelNominal;

	if (level < 10) {
		switch (level) {
		case 1:
			return kBattmanThermalPressureLevelModerate;
		case 2:
			return kBattmanThermalPressureLevelHeavy;
		case 3:
			return kBattmanThermalPressureLevelTrapping;
		case 4:
			return kBattmanThermalPressureLevelSleeping;
		default:
			return kBattmanThermalPressureLevelUnknown;
		}
	} else {
		switch (level) {
		case 10:
			return kBattmanThermalPressureLevelLight;
		case 20:
			return kBattmanThermalPressureLevelModerate;
		case 30:
			return kBattmanThermalPressureLevelHeavy;
		case 40:
			return kBattmanThermalPressureLevelTrapping;
		case 50:
			return kBattmanThermalPressureLevelSleeping;
		default:
			return kBattmanThermalPressureLevelUnknown;
		}
	}

	return kBattmanThermalPressureLevelError;
}

thermal_notif_level_t thermal_notif_level(void) {
	static bool got_levels = false;
	static int  levels[11] = { 0 };

	// macOS has no such thing
	if (kOSThermalNotificationName == NULL)
		return kBattmanThermalNotificationLevelAny;

	/* The level can be any number since there has _OSThermalNotificationSetLevelForBehavior */
	if (!got_levels)
		for (int i = 0; i < kBattmanThermalNotificationLevelUnknown; i++)
			levels[i] = _OSThermalNotificationLevelForBehavior(i);

	/* is there a condition that current level is not any of those levels? */
	int raw_level = OSThermalNotificationCurrentLevel();
	for (int i = 0; i < kBattmanThermalNotificationLevelUnknown; i++)
		if (levels[i] == raw_level)
			return (thermal_notif_level_t)i;

	return kBattmanThermalNotificationLevelUnknown;
}

float thermal_max_trigger_temperature(void) {
	int      token;
	uint64_t level;

	// This is set by thermalmonitord
	if (notify_register_check("com.apple.system.maxthermalsensorvalue", &token)) {
		return -1;
	}
	if (notify_get_state(token, &level)) {
		return -1;
	}
	if (notify_cancel(token)) {
		return -1;
	}

	// degC
	return (float)level / 100.0f;
}

int thermal_solar_state(void) {
	int      token;
	uint64_t level;
	
	// This is set by thermalmonitord
	if (notify_register_check("com.apple.system.thermalsunlightstate", &token)) {
		return 0;
	}
	if (notify_get_state(token, &level)) {
		return 0;
	}
	if (notify_cancel(token)) {
		return 0;
	}

	return (int)level;
}
