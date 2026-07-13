#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <sys/cdefs.h>

#define TI_DOD_SCALE 16384.0

__BEGIN_DECLS

double ti_dod_raw_to_percent(uint32_t raw_dod);
bool ti_dod_raw_is_valid(uint32_t raw_dod);
int fallback_design_cycle_count(const char *machine);
bool battery_tte_is_valid(int minutes);
double battery_ideal_tte_minutes(uint16_t remaining_capacity,
                                 int16_t average_current);

__END_DECLS
