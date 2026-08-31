//
//  BAAnalyticsBatterySummaryCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"

@interface BAAnalyticsBatterySummaryCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsBatterySummaryCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsBatterySummaryCardIdentifier
							 displayName:_("Battery")
							   cardTitle:nil
						 defaultCaption:_("Battery")
							  symbolName:nil
						 fallbackGlyph:nil
							   tintColor:[UIColor compatGreenColor]
						 supportedSizes:BAAnalyticsCardSizeMaskAll
							 defaultSize:BAAnalyticsCardSize1x1
							  showsGraph:NO];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *stateOfCharge = [snapshot valueForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent];
	NSString *value = stateOfCharge ? [NSString stringWithFormat:@"%.0f%%", stateOfCharge.doubleValue] : _("Unavailable");
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	NSNumber *health = [snapshot valueForMetricIdentifier:BAAnalyticsMetricBatteryHealthPercent];
	if (health) {
		[details addObject:BAAnalyticsLabeledValue(_("Health"), [NSString stringWithFormat:@"%.0f%%", health.doubleValue])];
		[details addObject:_("Health is calculated from Full Charge Capacity and Designed Capacity; it is not a runtime estimate.")];
	} else {
		[details addObject:_("Health is unavailable until both capacity readings are valid.")];
	}
	NSNumber *rawChargingState = [snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingState];
	if (rawChargingState) {
		NSString *chargingDescription = _("Not Charging");
		if (rawChargingState.integerValue == BAAnalyticsChargingStateCharging)
			chargingDescription = _("Charging");
		else if (rawChargingState.integerValue == BAAnalyticsChargingStatePaused && [[snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingLimitReached] boolValue])
			chargingDescription = _("Charging Limit Reached");
		[details addObject:BAAnalyticsLabeledValue(_("Status"), chargingDescription)];
	}
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:_("Battery")
											   detailLines:details
											  historyPoints:[snapshot historyForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent]];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateBatterySummaryCard(void) {
	return [BAAnalyticsBatterySummaryCard new];
}
