#include "battery_diagnostics.h"

#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

double ti_dod_raw_to_percent(uint32_t raw_dod) {
	return ((double)raw_dod * 100.0) / TI_DOD_SCALE;
}

bool ti_dod_raw_is_valid(uint32_t raw_dod) {
	return raw_dod <= (uint32_t)TI_DOD_SCALE;
}

static bool parse_model_suffix(const char *suffix, bool allow_subfamily,
    int *major, int *minor) {
	if (!suffix || !major || !minor)
		return false;

	if (allow_subfamily) {
		while ((*suffix >= 'A' && *suffix <= 'Z') ||
		    (*suffix >= 'a' && *suffix <= 'z'))
			suffix++;
	}

	char *end = NULL;
	long parsed_major = strtol(suffix, &end, 10);
	if (end == suffix || *end != ',' || parsed_major <= 0 || parsed_major > INT_MAX)
		return false;

	const char *minor_start = end + 1;
	long parsed_minor = strtol(minor_start, &end, 10);
	if (end == minor_start || *end != '\0' || parsed_minor < 0 || parsed_minor > INT_MAX)
		return false;

	*major = (int)parsed_major;
	*minor = (int)parsed_minor;
	return true;
}

int fallback_design_cycle_count(const char *machine) {
	if (!machine)
		return 0;

	int major = 0;
	int minor = 0;
	if (strncmp(machine, "iPhone", 6) == 0 &&
	    parse_model_suffix(machine + 6, false, &major, &minor)) {
		return (major < 15 || (major == 15 && minor < 4)) ? 500 : 1000;
	}
	if (strncmp(machine, "iPad", 4) == 0 &&
	    parse_model_suffix(machine + 4, false, &major, &minor))
		return 1000;
	if (strncmp(machine, "Watch", 5) == 0 &&
	    parse_model_suffix(machine + 5, false, &major, &minor))
		return 1000;
	if (strncmp(machine, "MacBook", 7) == 0 &&
	    parse_model_suffix(machine + 7, true, &major, &minor))
		return 1000;
	if (strncmp(machine, "iPod", 4) == 0 &&
	    parse_model_suffix(machine + 4, false, &major, &minor))
		return 400;
	return 0;
}

bool battery_tte_is_valid(int minutes) {
	return minutes > 0 && minutes <= INT16_MAX;
}

double battery_ideal_tte_minutes(uint16_t remaining_capacity,
    int16_t average_current) {
	if (average_current == 0)
		return 0.0;
	return ((double)remaining_capacity * 60.0) / fabs((double)average_current);
}
