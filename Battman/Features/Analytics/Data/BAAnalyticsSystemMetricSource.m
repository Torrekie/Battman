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
#include <signal.h>
#include <unistd.h>

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
		int descriptor = open(path, O_RDONLY);
		if (descriptor >= 0) {
			int processIdentifier = 0;
			ssize_t readLength = read(descriptor, &processIdentifier, sizeof(processIdentifier));
			close(descriptor);
			if (readLength == (ssize_t)sizeof(processIdentifier) && processIdentifier > 1) {
				errno = 0;
				serviceActive = kill(processIdentifier, 0) == 0 || errno == EPERM;
			}
		}
	}
	values[BAAnalyticsMetricChargingLimitServiceActive] = @(serviceActive);

	length = snprintf(path, sizeof(path), "%s/daemon_settings", configDirectory);
	if (length <= 0 || (size_t)length >= sizeof(path))
		return;
	int descriptor = open(path, O_RDONLY);
	if (descriptor < 0)
		return;
	uint8_t settings[3] = { 0 };
	ssize_t readLength = read(descriptor, settings, sizeof(settings));
	close(descriptor);
	if (readLength != (ssize_t)sizeof(settings))
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
		if (get_capacity(&remainingCapacity, &fullChargeCapacity, &designCapacity)) {
			values[BAAnalyticsMetricRemainingCapacityMilliampHours] = @(remainingCapacity);
			values[BAAnalyticsMetricFullChargeCapacityMilliampHours] = @(fullChargeCapacity);
			values[BAAnalyticsMetricDesignCapacityMilliampHours] = @(designCapacity);
			if (designCapacity > 0)
				values[BAAnalyticsMetricBatteryHealthPercent] = @(100.0 * (double)fullChargeCapacity / (double)designCapacity);
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
