//
//  BAAnalyticsSystemMetricSource.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsSystemMetricSource.h"
#import "BAAnalyticsMetricSnapshotInternal.h"

#import "battery_utils/libsmc.h"
#import "iokitextern.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <string.h>
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

// smc_read_n intentionally accepts size mismatches for legacy callers. A
// measurement here requires the exact known encoding, so a missing key or a
// changed firmware profile cannot turn a zero-filled buffer into a reading.
static BOOL BAAnalyticsReadSMC(uint32_t key, uint32_t type, void *bytes, uint32_t size, uint8_t *attributes) {
	SMCParamStruct input = {0};
	SMCParamStruct output = {0};
	input.key = key;
	input.param.data8 = kSMCGetKeyInfo;
	if (smc_call(kSMCHandleYPCEvent, &input, &output) != 0 || output.param.result != 0 ||
		output.param.keyInfo.dataSize != size || output.param.keyInfo.dataType != type ||
		size > sizeof(output.param.bytes))
		return NO;
	input.param.keyInfo = output.param.keyInfo;
	input.param.data8 = kSMCReadKey;
	memset(&output, 0, sizeof(output));
	if (smc_call(kSMCHandleYPCEvent, &input, &output) != 0 || output.param.result != 0)
		return NO;
	memcpy(bytes, output.param.bytes, size);
	if (attributes)
		*attributes = input.param.keyInfo.dataAttributes;
	return YES;
}

static BOOL BAAnalyticsReadUInt16(uint32_t key, uint16_t *value) {
	uint16_t result = 0;
	if (!BAAnalyticsReadSMC(key, 'ui16', &result, sizeof(result), NULL) || result == UINT16_MAX)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static BOOL BAAnalyticsReadInt16(uint32_t key, int16_t *value) {
	int16_t result = 0;
	if (!BAAnalyticsReadSMC(key, 'si16', &result, sizeof(result), NULL) || result == INT16_MIN || result == INT16_MAX)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static BOOL BAAnalyticsReadUInt64(uint32_t key, uint64_t *value) {
	uint64_t result = 0;
	if ((!BAAnalyticsReadSMC(key, 'ui64', &result, sizeof(result), NULL) &&
		 !BAAnalyticsReadSMC(key, 'hex_', &result, sizeof(result), NULL)) || result == UINT64_MAX)
		return NO;
	if (value)
		*value = result;
	return YES;
}

static NSNumber *BAAnalyticsReadAveragePowerWatts(void) {
	// The existing gas-gauge backend identifies B0AP as measured average mW;
	// some profiles expose si32 rather than si16. Keep that SDK metric distinct
	// from the derived battery-side current × voltage measurement below.
	int16_t narrowValue = 0;
	if (BAAnalyticsReadSMC('B0AP', 'si16', &narrowValue, sizeof(narrowValue), NULL) &&
		narrowValue != INT16_MIN && narrowValue != INT16_MAX)
		return @((double)narrowValue / 1000.0);
	int32_t wideValue = 0;
	if (BAAnalyticsReadSMC('B0AP', 'si32', &wideValue, sizeof(wideValue), NULL) &&
		wideValue != INT32_MIN && wideValue != INT32_MAX)
		return @((double)wideValue / 1000.0);
	return nil;
}

static NSNumber *BAAnalyticsCopyPowerSourceBoolean(io_service_t service, CFStringRef key) {
	CFTypeRef property = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
	if (!property)
		return nil;
	NSNumber *value = nil;
	if (CFGetTypeID(property) == CFBooleanGetTypeID()) {
		value = @(CFBooleanGetValue(property));
	} else if (CFGetTypeID(property) == CFNumberGetTypeID()) {
		double number = NAN;
		if (CFNumberGetValue(property, kCFNumberDoubleType, &number) && (number == 0.0 || number == 1.0))
			value = @(number == 1.0);
	}
	CFRelease(property);
	return value;
}

static NSArray<NSNumber *> *BAAnalyticsCopyPrimaryCellVoltages(void) {
	// AppleSmartBattery is the built-in battery, unlike accessory power-source
	// entries. Adopt its CellVoltage array only when the same dictionary's
	// established mV pack voltage verifies the channel units and topology.
	io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSmartBattery"));
	if (!service) return nil;
	CFTypeRef property = IORegistryEntryCreateCFProperty(service, CFSTR("BatteryData"), kCFAllocatorDefault, 0);
	IOObjectRelease(service);
	NSMutableArray<NSNumber *> *result = nil;
	if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
		CFTypeRef cells = CFDictionaryGetValue((CFDictionaryRef)property, CFSTR("CellVoltage"));
		if (cells && CFGetTypeID(cells) == CFArrayGetTypeID()) {
			CFIndex count = CFArrayGetCount((CFArrayRef)cells);
			if (count > 0 && count <= 10) {
				result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
				for (CFIndex index = 0; index < count; index++) {
					CFTypeRef cell = CFArrayGetValueAtIndex((CFArrayRef)cells, index);
					double voltage = NAN;
					if (!cell || CFGetTypeID(cell) != CFNumberGetTypeID() ||
						!CFNumberGetValue((CFNumberRef)cell, kCFNumberDoubleType, &voltage) ||
						!isfinite(voltage) || voltage <= 0 || voltage >= UINT16_MAX || floor(voltage) != voltage) {
						result = nil; break;
					}
					[result addObject:@(voltage)];
				}
			}
		}
		// The primary pack Voltage is established in mV. Require the same
		// dictionary's series-cell sum to agree before adopting an unfamiliar
		// registry profile; never rescale values or infer accessory units. The
		// small tolerance accommodates rounded/non-atomic gauge readings and
		// is a unit consistency check, not an imbalance/fault threshold.
		CFTypeRef pack = CFDictionaryGetValue((CFDictionaryRef)property, CFSTR("Voltage"));
		double packVoltage = NAN, sum = 0;
		for (NSNumber *voltage in result) sum += voltage.doubleValue;
		if (!pack || CFGetTypeID(pack) != CFNumberGetTypeID() ||
			!CFNumberGetValue((CFNumberRef)pack, kCFNumberDoubleType, &packVoltage) ||
			!isfinite(packVoltage) || packVoltage <= 0 || packVoltage >= UINT16_MAX ||
			floor(packVoltage) != packVoltage || fabs(sum - packVoltage) > MAX(10.0, packVoltage * .02))
			result = nil;
	}
	if (property) CFRelease(property);
	return [result copy];
}

static void BAAnalyticsReadObservedChargingMetrics(NSMutableDictionary<NSString *, NSNumber *> *values,
													NSNumber *SMCConnected) {
	NSNumber *connected = nil;
	NSNumber *charging = nil;
	NSNumber *fullyCharged = nil;
	// Read only the three battery state properties, not adapter identity or
	// unrelated registry/activity payloads. Each absent property stays absent.
	io_service_t service = IOServiceGetMatchingService(0, IOServiceMatching("IOPMPowerSource"));
	if (service) {
		connected = BAAnalyticsCopyPowerSourceBoolean(service, CFSTR("ExternalConnected"));
		if (!connected)
			connected = BAAnalyticsCopyPowerSourceBoolean(service, CFSTR("AppleRawExternalConnected"));
		charging = BAAnalyticsCopyPowerSourceBoolean(service, CFSTR("IsCharging"));
		fullyCharged = BAAnalyticsCopyPowerSourceBoolean(service, CFSTR("FullyCharged"));
		IOObjectRelease(service);
	}
	BAAnalyticsRecordObservedChargingMetrics(values, connected ?: SMCConnected, charging, fullyCharged);
}

static BOOL BAAnalyticsReadInputMeasurement(uint32_t key, double maximum, double *value) {
	uint64_t raw = 0;
	if (!BAAnalyticsReadSMC(key, 'ioft', &raw, sizeof(raw), NULL) || raw == UINT64_MAX)
		return NO;
	// Existing IBUS/VBUS backend establishes unsigned 16-fraction-bit ioft,
	// with current in A and voltage in V. These are measured input quantities.
	double decoded = (double)raw / 65536.0;
	if (!isfinite(decoded) || decoded < 0 || decoded > maximum)
		return NO;
	*value = decoded;
	return YES;
}

static void BAAnalyticsReadChargingLimitMetrics(NSMutableDictionary<NSString *, NSNumber *> *values) {
	const char *configDirectory = battman_config_dir();
	if (!configDirectory || configDirectory[0] == '\0')
		return;

	char path[PATH_MAX];
	int length = snprintf(path, sizeof(path), "%s/daemon.run", configDirectory);
	NSNumber *serviceActive = nil;
	if (length > 0 && (size_t)length < sizeof(path)) {
		pid_t processIdentifier = 0;
		serviceActive = @(BAAnalyticsReadDaemonPID(path, &processIdentifier));
	}
	if (serviceActive)
		values[BAAnalyticsMetricChargingLimitServiceActive] = serviceActive;

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
	if (stateOfCharge && serviceActive.boolValue)
		values[BAAnalyticsMetricChargingLimitReached] = @(stateOfCharge.doubleValue >= (double)limitPercent);
}

@implementation BAAnalyticsSystemMetricSource

- (NSDictionary<NSString *, NSNumber *> *)readAnalyticsMetricValues {
	NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];
	values[BAAnalyticsMetricLowPowerMode] = @([NSProcessInfo processInfo].lowPowerModeEnabled);

	// This source owns a single serial service queue. The synchronized section
	// additionally prevents concurrent reads if another service instance is
	// created; legacy callers elsewhere in Battman retain their existing policy.
	@synchronized([BAAnalyticsSystemMetricSource class]) {
		// get_temperature initializes the shared backend only when necessary;
		// calling smc_open every poll would open another legacy connection.
		BOOL SMCReady = hasSMC;
		if (SMCReady)
			(void)get_temperature();
		int8_t port = -2;
		NSNumber *SMCConnected = nil;
		BOOL portValidated = SMCReady && BAAnalyticsReadSMC('AC-W', 'si8 ', &port, sizeof(port), NULL);
		if (portValidated && port >= -1 && port <= 9)
			SMCConnected = @(port > 0);
		BAAnalyticsReadObservedChargingMetrics(values, SMCConnected);
		if (SMCReady) {

			uint16_t temperature = 0;
			if (BAAnalyticsReadUInt16('B0AT', &temperature))
				BAAnalyticsRecordTemperatureMetric(values, (float)temperature / 100.0f);

			int8_t cellCount = -1;
			BOOL cellCountValidated = BAAnalyticsReadSMC('BNCB', 'si8 ', &cellCount, sizeof(cellCount), NULL) && cellCount > 0 && cellCount <= 10;
			if (cellCountValidated) {
				values[BAAnalyticsMetricCellCount] = @(cellCount);
				for (NSUInteger index = 0; index < (NSUInteger)cellCount; index++) {
					uint16_t voltage = 0;
					uint32_t key = 'BC\0V' | ((uint32_t)('0' + index) << 8);
					if (BAAnalyticsReadUInt16(key, &voltage) && voltage > 0)
						values[BAAnalyticsCellVoltageMetricIdentifier(index)] = @(voltage);
				}
			}

			uint16_t remainingCapacity = 0;
			uint16_t fullChargeCapacity = 0;
			uint16_t designCapacity = 0;
			uint8_t remainingAttributes = 0;
			// The established SMC capacity keys are per-cell mAh. Do not substitute
			// PowerSource CurrentCapacity/MaxCapacity percentages or guess cell count.
			if (cellCountValidated) {
				if (BAAnalyticsReadSMC('B0RM', 'ui16', &remainingCapacity, sizeof(remainingCapacity), &remainingAttributes) && remainingCapacity != UINT16_MAX) {
					if (remainingAttributes & 0x10)
						remainingCapacity = (uint16_t)((remainingCapacity << 8) | (remainingCapacity >> 8));
					values[BAAnalyticsMetricRemainingCapacityMilliampHours] = @((NSUInteger)remainingCapacity * (NSUInteger)cellCount);
				}
				if (BAAnalyticsReadUInt16('B0FC', &fullChargeCapacity) && fullChargeCapacity > 0)
					values[BAAnalyticsMetricFullChargeCapacityMilliampHours] = @((NSUInteger)fullChargeCapacity * (NSUInteger)cellCount);
				if (BAAnalyticsReadUInt16('B0DC', &designCapacity) && designCapacity > 0)
					values[BAAnalyticsMetricDesignCapacityMilliampHours] = @((NSUInteger)designCapacity * (NSUInteger)cellCount);
				if (values[BAAnalyticsMetricFullChargeCapacityMilliampHours] && values[BAAnalyticsMetricDesignCapacityMilliampHours]) {
					double health = 100.0 * (double)fullChargeCapacity / (double)designCapacity;
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
			NSNumber *current = values[BAAnalyticsMetricAverageCurrentMilliamps];
			NSNumber *voltage = values[BAAnalyticsMetricVoltageMillivolts];
			if (current && voltage)
				values[BAAnalyticsMetricBatteryNetPowerWatts] = @(current.doubleValue * voltage.doubleValue / 1000000.0);
			NSNumber *averagePower = BAAnalyticsReadAveragePowerWatts();
			if (averagePower)
				values[BAAnalyticsMetricAveragePowerWatts] = averagePower;
			if (BAAnalyticsReadUInt16('B0CT', &unsignedValue))
				values[BAAnalyticsMetricCycleCount] = @(unsignedValue);
			if (BAAnalyticsReadUInt16('B0CU', &unsignedValue) && unsignedValue > 0)
				values[BAAnalyticsMetricDesignCycleCount] = @(unsignedValue);
			if (BAAnalyticsReadUInt64('BUPT', &unsignedWideValue) && unsignedWideValue > 0)
				values[BAAnalyticsMetricBatteryUptimeSeconds] = @(unsignedWideValue);

			// Do not use is_charging(): its AC-W path proves connection only.
			// Input is available independently at each measured point; no adapter
			// rating, rectifier unit guess, or budget is presented as a measurement.
			if (portValidated && port > 0 && port <= 9 && values[BAAnalyticsMetricExternalConnected].boolValue) {
				double inputCurrent = 0;
				double inputVoltage = 0;
				if (BAAnalyticsReadInputMeasurement('IQ0u', 100.0, &inputCurrent))
					values[BAAnalyticsMetricInputCurrentMilliamps] = @(inputCurrent * 1000.0);
				uint32_t voltageKey = 'VQ\0u' | ((uint32_t)('0' + port - 1) << 8);
				if (BAAnalyticsReadInputMeasurement(voltageKey, 500.0, &inputVoltage) && inputVoltage > 0)
					values[BAAnalyticsMetricInputVoltageMillivolts] = @(inputVoltage * 1000.0);
				if (values[BAAnalyticsMetricInputCurrentMilliamps] && values[BAAnalyticsMetricInputVoltageMillivolts])
					values[BAAnalyticsMetricInputPowerWatts] = @(inputCurrent * inputVoltage);
			}
		}
		NSUInteger observedCells = 0;
		for (NSUInteger index = 0; index < 10; index++)
			if (values[BAAnalyticsCellVoltageMetricIdentifier(index)]) observedCells++;
		NSNumber *count = values[BAAnalyticsMetricCellCount];
		if (!count || observedCells != count.unsignedIntegerValue) {
			NSArray<NSNumber *> *primaryCells = BAAnalyticsCopyPrimaryCellVoltages();
			if (primaryCells.count) {
				// Replace the complete set, never combine an SMC partial reading with
				// a registry reading acquired later or from a different channel set.
				for (NSUInteger index = 0; index < 10; index++)
					[values removeObjectForKey:BAAnalyticsCellVoltageMetricIdentifier(index)];
				values[BAAnalyticsMetricCellCount] = @(primaryCells.count);
				for (NSUInteger index = 0; index < primaryCells.count; index++)
					values[BAAnalyticsCellVoltageMetricIdentifier(index)] = primaryCells[index];
			}
		}
	}

	BAAnalyticsReadChargingLimitMetrics(values);
	return [values copy];
}

@end
