//
//  BAAnalyticsBuiltInCards.m
//  Battman
//


#import "BAAnalyticsBuiltInCards.h"

NSString *const BAAnalyticsBatterySummaryCardIdentifier = @"com.torrekie.battman.analytics.battery.summary";
NSString *const BAAnalyticsTemperatureAverageCardIdentifier = @"com.torrekie.battman.analytics.temperature.average";
NSString *const BAAnalyticsPowerAverageCardIdentifier = @"com.torrekie.battman.analytics.power.average";
NSString *const BAAnalyticsCycleSummaryCardIdentifier = @"com.torrekie.battman.analytics.cycle.summary";
NSString *const BAAnalyticsRemainingCapacityCardIdentifier = @"com.torrekie.battman.analytics.capacity.remaining";
NSString *const BAAnalyticsChargingLimitCardIdentifier = @"com.torrekie.battman.analytics.charging-limit";

NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateBuiltInCards(void) {
	return @[
		BAAnalyticsCreateBatterySummaryCard(),
		BAAnalyticsCreateTemperatureAverageCard(),
		BAAnalyticsCreatePowerAverageCard(),
		BAAnalyticsCreateCycleSummaryCard(),
		BAAnalyticsCreateRemainingCapacityCard(),
		BAAnalyticsCreateChargingLimitCard(),
	];
}
