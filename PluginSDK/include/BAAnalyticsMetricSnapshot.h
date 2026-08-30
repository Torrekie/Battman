//
//  BAAnalyticsMetricSnapshot.h
//  Battman Plugin SDK
//
//  Immutable, UIKit-free metric values delivered to Analytics cards.
//  Plug-ins receive these objects from the host; they do not instantiate host
//  implementation classes or link against Battman symbols.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// String literals keep the metric namespace ABI independent from symbols in
// the Battman executable. A native bundle links only documented system
// frameworks and communicates with snapshot objects through Objective-C.
#define BAAnalyticsMetricStateOfChargePercent @"battery.state-of-charge.percent"
#define BAAnalyticsMetricBatteryHealthPercent @"battery.health.percent"
#define BAAnalyticsMetricAverageTemperatureCelsius @"battery.temperature.average.celsius"
#define BAAnalyticsMetricAverageCurrentMilliamps @"battery.current.average.milliamps"
#define BAAnalyticsMetricVoltageMillivolts @"battery.voltage.millivolts"
#define BAAnalyticsMetricAveragePowerWatts @"battery.power.average.watts"
#define BAAnalyticsMetricCycleCount @"battery.cycles.current"
#define BAAnalyticsMetricDesignCycleCount @"battery.cycles.design"
#define BAAnalyticsMetricBatteryUptimeSeconds @"battery.uptime.seconds"
#define BAAnalyticsMetricRemainingCapacityMilliampHours @"battery.capacity.remaining.milliamp-hours"
#define BAAnalyticsMetricFullChargeCapacityMilliampHours @"battery.capacity.full-charge.milliamp-hours"
#define BAAnalyticsMetricDesignCapacityMilliampHours @"battery.capacity.design.milliamp-hours"
#define BAAnalyticsMetricChargingState @"battery.charging.state"
#define BAAnalyticsMetricChargingLimitPercent @"charging-limit.percent"
#define BAAnalyticsMetricChargingLimitServiceActive @"charging-limit.service-active"
#define BAAnalyticsMetricChargingLimitReached @"charging-limit.reached"

typedef NS_ENUM(NSInteger, BAAnalyticsChargingState) {
	BAAnalyticsChargingStateUnavailable = -1,
	BAAnalyticsChargingStateNotCharging = 0,
	BAAnalyticsChargingStateCharging = 1,
	BAAnalyticsChargingStatePaused = 2,
};

@interface BAAnalyticsMetricPoint : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSDate *timestamp;
@property (nonatomic, readonly) double value;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsMetricSnapshot : NSObject <NSCopying>
@property (nonatomic, readonly) uint64_t sequenceNumber;
@property (nonatomic, copy, readonly) NSDate *timestamp;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *values;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *histories;

- (instancetype)init NS_UNAVAILABLE;

- (nullable NSNumber *)valueForMetricIdentifier:(NSString *)metricIdentifier;
- (NSArray<BAAnalyticsMetricPoint *> *)historyForMetricIdentifier:(NSString *)metricIdentifier;
@end

NS_ASSUME_NONNULL_END
