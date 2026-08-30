//
//  BAAnalyticsBuiltInCards.h
//  Battman
//


#import <Foundation/Foundation.h>

#import "../Public/BAAnalyticsCard.h"

FOUNDATION_EXPORT NSString *const BAAnalyticsBatterySummaryCardIdentifier;
FOUNDATION_EXPORT NSString *const BAAnalyticsTemperatureAverageCardIdentifier;
FOUNDATION_EXPORT NSString *const BAAnalyticsPowerAverageCardIdentifier;
FOUNDATION_EXPORT NSString *const BAAnalyticsCycleSummaryCardIdentifier;
FOUNDATION_EXPORT NSString *const BAAnalyticsRemainingCapacityCardIdentifier;
FOUNDATION_EXPORT NSString *const BAAnalyticsChargingLimitCardIdentifier;

NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateBuiltInCards(void);

id<BAAnalyticsCard> BAAnalyticsCreateBatterySummaryCard(void);
id<BAAnalyticsCard> BAAnalyticsCreateTemperatureAverageCard(void);
id<BAAnalyticsCard> BAAnalyticsCreatePowerAverageCard(void);
id<BAAnalyticsCard> BAAnalyticsCreateCycleSummaryCard(void);
id<BAAnalyticsCard> BAAnalyticsCreateRemainingCapacityCard(void);
id<BAAnalyticsCard> BAAnalyticsCreateChargingLimitCard(void);
