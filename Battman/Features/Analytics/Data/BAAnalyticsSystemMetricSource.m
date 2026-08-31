//
//  BAAnalyticsSystemMetricSource.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsSystemMetricSource.h"

#import "battery_utils/libsmc.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static BOOL BAAnalyticsReadDaemonPID(const char *path, pid_t *pid_out) {
	if (!path || !pid_out)
		return NO;
	int descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
	if (descriptor < 0)
		return NO;
	struct stat st;
	BOOL safe = fstat(descriptor, &st) == 0 && S_ISREG(st.st_mode) &&
	            st.st_size == (off_t)sizeof(pid_t) && (st.st_mode & 022) == 0 &&
	            (st.st_uid == 0 || st.st_uid == getuid());
	pid_t processIdentifier = 0;
	ssize_t readLength = safe ? pread(descriptor, &processIdentifier,
	                                  sizeof(processIdentifier), 0) : -1;
	close(descriptor);
	if (readLength != (ssize_t)sizeof(processIdentifier) || processIdentifier <= 1)
		return NO;
	errno = 0;
	if (kill(processIdentifier, 0) != 0 && errno != EPERM)
		return NO;
	*pid_out = processIdentifier;
	return YES;
}

static BOOL BAAnalyticsReadDaemonSettings(const char *path, uint8_t settings[BATTMAN_DAEMON_SETTINGS_SIZE]) {
	if (!path || !settings)
		return NO;
	int descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
	if (descriptor < 0)
		return NO;
	struct stat st;
	BOOL safe = fstat(descriptor, &st) == 0 && S_ISREG(st.st_mode) &&
	            st.st_size == (off_t)BATTMAN_DAEMON_SETTINGS_SIZE &&
	            (st.st_mode & 022) == 0 && (st.st_uid == 0 || st.st_uid == getuid());
	ssize_t readLength = safe ? pread(descriptor, settings,
	                                  BATTMAN_DAEMON_SETTINGS_SIZE, 0) : -1;
	close(descriptor);
	if (readLength != (ssize_t)BATTMAN_DAEMON_SETTINGS_SIZE)
		return NO;
	if ((settings[0] != UINT8_MAX && settings[0] > 100) ||
	    (settings[1] != UINT8_MAX && settings[1] > 100) ||
	    (settings[0] != UINT8_MAX && settings[1] == UINT8_MAX) ||
	    (settings[0] != UINT8_MAX && settings[1] != UINT8_MAX && settings[0] >= settings[1]))
		return NO;
	return YES;
}

static BOOL BAAnalyticsReadUInt16(uint32_t key, uint16_t *value) {
	uint16_t result = 0;
	if (smc_read_n(key, &result, (int32_t)sizeof(result)) != 0)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static BOOL BAAnalyticsReadInt16(uint32_t key, int16_t *value) {
	int16_t result = 0;
	if (smc_read_n(key, &result, (int32_t)sizeof(result)) != 0)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static BOOL BAAnalyticsReadUInt64(uint32_t key, uint64_t *value) {
	uint64_t result = 0;
	if (smc_read_n(key, &result, (int32_t)sizeof(result)) != 0)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static void BAAnalyticsReadChargingLimitMetrics(NSMutableDictionary<NSString *, NSNumber *> *values) {
	const char *configDirectory = battman_config_dir();
	if (!configDirectory || configDirectory[0] == '\0')
		return;

	char path[PATH_MAX];
	int length = snprintf(path, sizeof(path), "%s/daemon.run", configDirectory);
	BOOL serviceActive = NO;
	if (length > 0 && (size_t)length < sizeof(path)) {
		pid_t processIdentifier = 0;
		serviceActive = BAAnalyticsReadDaemonPID(path, &processIdentifier);
	}
	values[BAAnalyticsMetricChargingLimitServiceActive] = @(serviceActive);

	length = snprintf(path, sizeof(path), "%s/daemon_settings", configDirectory);
	if (length <= 0 || (size_t)length >= sizeof(path))
		return;
	uint8_t settings[BATTMAN_DAEMON_SETTINGS_SIZE] = { 0 };
	if (!BAAnalyticsReadDaemonSettings(path, settings))
		return;

	NSUInteger limitPercent = settings[1] == UINT8_MAX ? 100 : settings[1];
	if (limitPercent > 100)
		return;
	values[BAAnalyticsMetricChargingLimitPercent] = @(limitPercent);
	NSNumber *stateOfCharge = values[BAAnalyticsMetricStateOfChargePercent];
	if (stateOfCharge && serviceActive)
		values[BAAnalyticsMetricChargingLimitReached] = @(stateOfCharge.doubleValue >= (double)limitPercent);
}

@implementation BAAnalyticsSystemMetricSource

- (NSDictionary<NSString *, NSNumber *> *)readAnalyticsMetricValues {
	NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];

	// This source owns a single serial service queue. The synchronized section
	// additionally prevents concurrent reads if another service instance is
	// created; legacy callers elsewhere in Battman retain their existing policy.
	@synchronized([BAAnalyticsSystemMetricSource class]) {
		BAAnalyticsRecordTemperatureMetric(values, get_temperature());

		uint16_t remainingCapacity = 0;
		uint16_t fullChargeCapacity = 0;
		uint16_t designCapacity = 0;
		if (get_capacity(&remainingCapacity, &fullChargeCapacity, &designCapacity) &&
		    fullChargeCapacity > 0 && designCapacity > 0) {
			values[BAAnalyticsMetricRemainingCapacityMilliampHours] = @(remainingCapacity);
			values[BAAnalyticsMetricFullChargeCapacityMilliampHours] = @(fullChargeCapacity);
			values[BAAnalyticsMetricDesignCapacityMilliampHours] = @(designCapacity);
			if (designCapacity > 0 && fullChargeCapacity > 0) {
				double health = 100.0 * (double)fullChargeCapacity / (double)designCapacity;
				/* Capacity calibration can legitimately put the estimate a
				 * little above 100%, but an unbounded/negative value is a
				 * failed reading, not a meaningful health score. */
				if (isfinite(health) && health >= 0.0 && health <= 200.0)
					values[BAAnalyticsMetricBatteryHealthPercent] = @(health);
			}
		}

		uint16_t unsignedValue = 0;
		int16_t signedValue = 0;
		uint64_t unsignedWideValue = 0;
		if (BAAnalyticsReadUInt16('BRSC', &unsignedValue) && unsignedValue <= 100)
			values[BAAnalyticsMetricStateOfChargePercent] = @(unsignedValue);
		if (BAAnalyticsReadUInt16('B0AV', &unsignedValue) && unsignedValue > 0)
			values[BAAnalyticsMetricVoltageMillivolts] = @(unsignedValue);
		if (BAAnalyticsReadInt16('B0AC', &signedValue))
			values[BAAnalyticsMetricAverageCurrentMilliamps] = @(signedValue);
		if (BAAnalyticsReadInt16('B0AP', &signedValue))
			values[BAAnalyticsMetricAveragePowerWatts] = @((double)signedValue / 1000.0);
		if (BAAnalyticsReadUInt16('B0CT', &unsignedValue))
			values[BAAnalyticsMetricCycleCount] = @(unsignedValue);
		if (BAAnalyticsReadUInt16('B0CU', &unsignedValue) && unsignedValue > 0)
			values[BAAnalyticsMetricDesignCycleCount] = @(unsignedValue);
		if (BAAnalyticsReadUInt64('BUPT', &unsignedWideValue) && unsignedWideValue > 0)
			values[BAAnalyticsMetricBatteryUptimeSeconds] = @(unsignedWideValue);

		charging_state_t chargingState = is_charging(NULL, NULL);
		if (chargingState >= kIsNotCharging && chargingState <= kIsPausing)
			values[BAAnalyticsMetricChargingState] = @((NSInteger)chargingState);
	}

	BAAnalyticsReadChargingLimitMetrics(values);
	return [values copy];
}

@end
