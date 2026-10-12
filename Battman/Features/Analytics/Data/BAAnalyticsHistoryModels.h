// Host-only normalized Powerlog data. Do not export through PluginSDK v1.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Units are part of these identifiers. Missing keys mean unavailable, never 0.
#define BAAnalyticsHistorySOCPercent @"soc.percent"
#define BAAnalyticsHistoryTemperatureCelsius @"temperature.celsius"
#define BAAnalyticsHistoryCurrentMilliamps @"current.milliamps"
#define BAAnalyticsHistoryVoltageMillivolts @"voltage.millivolts"
#define BAAnalyticsHistoryBatteryPowerWatts @"battery-power.watts"
#define BAAnalyticsHistoryRemainingCapacityMilliampHours @"remaining-capacity.milliamp-hours"
#define BAAnalyticsHistoryFullChargeCapacityMilliampHours @"full-charge-capacity.milliamp-hours"
#define BAAnalyticsHistoryDesignCapacityMilliampHours @"design-capacity.milliamp-hours"
#define BAAnalyticsHistoryCycleCount @"cycle-count"
#define BAAnalyticsHistoryExternalConnected @"external-connected"
#define BAAnalyticsHistoryIsCharging @"is-charging"
#define BAAnalyticsHistoryFullyCharged @"fully-charged"
#define BAAnalyticsHistoryNotChargingReasonCode @"not-charging-reason.code"
#define BAAnalyticsHistoryCellVoltage0Millivolts @"cell-voltage.0.millivolts"
#define BAAnalyticsHistoryCellVoltage1Millivolts @"cell-voltage.1.millivolts"
#define BAAnalyticsHistoryCellVoltage2Millivolts @"cell-voltage.2.millivolts"
#define BAAnalyticsHistoryInputCurrentMilliamps @"input-current.milliamps"
#define BAAnalyticsHistoryInputVoltageMillivolts @"input-voltage.millivolts"
#define BAAnalyticsHistoryInputPowerWatts @"input-power.watts"
#define BAAnalyticsHistoryPowerBudgetWatts @"power-budget.watts"
#define BAAnalyticsHistoryPowerTargetWatts @"power-target.watts"

// Additional cell indices use cell-voltage.<zero-based index>.millivolts.
// Current and battery power are signed: positive charge, negative discharge.
typedef NS_ENUM(NSInteger, BAAnalyticsObservedState) {
	BAAnalyticsObservedStateUnknown = 0,
	BAAnalyticsObservedStateUnplugged,
	BAAnalyticsObservedStateCharging,
	BAAnalyticsObservedStateConnectedNotCharging,
	BAAnalyticsObservedStateFull,
};

@interface BAAnalyticsFieldMetadata : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *sourceTable;
@property (nonatomic, copy, readonly) NSString *sourceColumn;
@property (nonatomic, copy, readonly) NSString *unit;
@property (nonatomic, copy, readonly) NSString *decoderIdentifier;
@property (nonatomic, readonly) BOOL unitValidated;
- (instancetype)initWithSourceTable:(NSString *)sourceTable
					 sourceColumn:(NSString *)sourceColumn
							 unit:(NSString *)unit
					decoderIdentifier:(NSString *)decoderIdentifier
						 unitValidated:(BOOL)unitValidated NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsObservation : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSDate *timestamp;
@property (nonatomic, readonly) double sourceTimestamp;
@property (nonatomic, readonly) BOOL timestampValidated;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *values;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *fieldMetadata;
- (instancetype)initWithIdentifier:(NSString *)identifier
						 timestamp:(NSDate *)timestamp
					 sourceTimestamp:(double)sourceTimestamp
					 timestampValidated:(BOOL)timestampValidated
							 values:(NSDictionary<NSString *, NSNumber *> *)values
						fieldMetadata:(NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *)fieldMetadata NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (nullable NSNumber *)valueForMetricIdentifier:(NSString *)metricIdentifier;
@end

// A bounded trusted pair, not an assertion that every metric exists throughout.
// coveredMetricIdentifiers names fields valid at both ends with a trusted cadence.
@interface BAAnalyticsHistoryInterval : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSDate *startDate;
@property (nonatomic, copy, readonly) NSDate *endDate;
@property (nonatomic, strong, readonly) BAAnalyticsObservation *startObservation;
@property (nonatomic, strong, readonly) BAAnalyticsObservation *endObservation;
@property (nonatomic, copy, readonly) NSSet<NSString *> *coveredMetricIdentifiers;
@property (nonatomic, readonly) BAAnalyticsObservedState state;
@property (nonatomic, readonly) NSTimeInterval duration;
- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
				 startObservation:(BAAnalyticsObservation *)startObservation
				   endObservation:(BAAnalyticsObservation *)endObservation
			coveredMetricIdentifiers:(NSSet<NSString *> *)coveredMetricIdentifiers
							 state:(BAAnalyticsObservedState)state NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsHistoryGap : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSDate *startDate;
@property (nonatomic, copy, readonly) NSDate *endDate;
@property (nonatomic, copy, readonly) NSString *reason;
- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
							 reason:(NSString *)reason NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

// Exact transition time is unknown between the two sampled boundaries.
@interface BAAnalyticsStateTransition : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSDate *earliestDate;
@property (nonatomic, copy, readonly) NSDate *latestDate;
@property (nonatomic, readonly) BAAnalyticsObservedState previousState;
@property (nonatomic, readonly) BAAnalyticsObservedState nextState;
@property (nonatomic, strong, readonly, nullable) NSNumber *reasonCode;
- (instancetype)initWithIdentifier:(NSString *)identifier
						 earliestDate:(NSDate *)earliestDate latestDate:(NSDate *)latestDate
						previousState:(BAAnalyticsObservedState)previousState
							 nextState:(BAAnalyticsObservedState)nextState
							 reasonCode:(nullable NSNumber *)reasonCode NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsHistorySession : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *kind; // "connected" or "unplugged"
@property (nonatomic, copy, readonly) NSDate *startDate;
@property (nonatomic, copy, readonly) NSDate *endDate;
@property (nonatomic, readonly) BOOL startBoundaryKnown;
@property (nonatomic, readonly) BOOL endBoundaryKnown;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsObservation *> *observations;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsHistoryInterval *> *intervals;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsHistoryGap *> *gaps;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsStateTransition *> *transitions;
- (instancetype)initWithIdentifier:(NSString *)identifier kind:(NSString *)kind
						 startDate:(NSDate *)startDate endDate:(NSDate *)endDate
					startBoundaryKnown:(BOOL)startBoundaryKnown endBoundaryKnown:(BOOL)endBoundaryKnown
						observations:(NSArray<BAAnalyticsObservation *> *)observations
							intervals:(NSArray<BAAnalyticsHistoryInterval *> *)intervals
								 gaps:(NSArray<BAAnalyticsHistoryGap *> *)gaps
							transitions:(NSArray<BAAnalyticsStateTransition *> *)transitions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
