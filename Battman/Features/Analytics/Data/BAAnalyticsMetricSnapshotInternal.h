// Host/test-only construction surface. Plug-ins receive immutable instances.
#import "../Public/BAAnalyticsMetricSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

// Host-only literals until the integration task adds any compatible SDK
// declarations. Presence is independent for each observed state/measurement.
#define BAAnalyticsMetricLowPowerMode @"system.low-power-mode"
#define BAAnalyticsMetricExternalConnected @"battery.external-connected"
#define BAAnalyticsMetricIsCharging @"battery.is-charging"
#define BAAnalyticsMetricFullyCharged @"battery.fully-charged"
#define BAAnalyticsMetricCellCount @"battery.cells.count"
#define BAAnalyticsMetricBatteryNetPowerWatts @"battery.power.net.watts"
#define BAAnalyticsMetricInputCurrentMilliamps @"power-source.input-current.milliamps"
#define BAAnalyticsMetricInputVoltageMillivolts @"power-source.input-voltage.millivolts"
#define BAAnalyticsMetricInputPowerWatts @"power-source.input-power.watts"

static inline NSString *BAAnalyticsCellVoltageMetricIdentifier(NSUInteger index) {
	return [NSString stringWithFormat:@"battery.cell-voltage.%lu.millivolts", (unsigned long)index];
}

static inline NSNumber * _Nullable BAAnalyticsValidatedBooleanMetric(NSNumber * _Nullable value) {
	if (![value isKindOfClass:[NSNumber class]])
		return nil;
	double number = value.doubleValue;
	return number == 0.0 || number == 1.0 ? @(number == 1.0) : nil;
}

// A connection is not evidence that charge is entering the battery. SDK v1
// has no full-charge enum; the independent fully-charged value retains that
// distinction while its legacy state accurately reports not charging.
static inline void BAAnalyticsRecordObservedChargingMetrics(NSMutableDictionary<NSString *, NSNumber *> *values,
															NSNumber * _Nullable connected,
															NSNumber * _Nullable charging,
															NSNumber * _Nullable fullyCharged) {
	connected = BAAnalyticsValidatedBooleanMetric(connected);
	charging = BAAnalyticsValidatedBooleanMetric(charging);
	fullyCharged = BAAnalyticsValidatedBooleanMetric(fullyCharged);
	[values removeObjectsForKeys:@[BAAnalyticsMetricExternalConnected, BAAnalyticsMetricIsCharging,
		BAAnalyticsMetricFullyCharged, BAAnalyticsMetricChargingState]];
	if (connected)
		values[BAAnalyticsMetricExternalConnected] = connected;
	if (charging)
		values[BAAnalyticsMetricIsCharging] = charging;
	if (fullyCharged)
		values[BAAnalyticsMetricFullyCharged] = fullyCharged;

	if (charging.boolValue && ((connected && !connected.boolValue) || fullyCharged.boolValue))
		return; // Conflicting observations cannot establish a combined state.
	if (charging.boolValue)
		values[BAAnalyticsMetricChargingState] = @(BAAnalyticsChargingStateCharging);
	else if (connected.boolValue && charging && !charging.boolValue && fullyCharged && !fullyCharged.boolValue)
		values[BAAnalyticsMetricChargingState] = @(BAAnalyticsChargingStatePaused);
	else if ((connected && !connected.boolValue) || (charging && !charging.boolValue) || fullyCharged.boolValue)
		values[BAAnalyticsMetricChargingState] = @(BAAnalyticsChargingStateNotCharging);
}

@interface BAAnalyticsMetricPoint (BAAnalyticsHostConstruction)
- (instancetype)initWithTimestamp:(NSDate *)timestamp value:(double)value;
@end

@interface BAAnalyticsMetricSnapshot (BAAnalyticsHostConstruction)
@property (nonatomic, readonly, getter=isCached) BOOL cached;
- (BAAnalyticsMetricSnapshot *)snapshotByMarkingCached;
// Missing/non-finite values are discarded while the host builds a snapshot.
- (instancetype)initWithSequenceNumber:(uint64_t)sequenceNumber
						  timestamp:(NSDate *)timestamp
							 values:(nullable NSDictionary<NSString *, NSNumber *> *)values
						  histories:(nullable NSDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *)histories;
@end
NS_ASSUME_NONNULL_END
