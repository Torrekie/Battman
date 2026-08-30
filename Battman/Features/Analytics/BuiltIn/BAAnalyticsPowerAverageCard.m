//
//  BAAnalyticsPowerAverageCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"

@interface BAAnalyticsPowerAverageCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsPowerAverageCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsPowerAverageCardIdentifier
							 displayName:_("Avg. Power")
							   cardTitle:nil
						 defaultCaption:_("Avg. Power")
							  symbolName:nil
						 fallbackGlyph:nil
							   tintColor:[UIColor compatRedColor]
						 supportedSizes:BAAnalyticsCardSizeMask1x1 | BAAnalyticsCardSizeMask1x2
							 defaultSize:BAAnalyticsCardSize1x1
							  showsGraph:NO];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *power = [snapshot valueForMetricIdentifier:BAAnalyticsMetricAveragePowerWatts];
	NSString *value = power ? [NSString stringWithFormat:@"%.2f W", power.doubleValue] : _("Unavailable");
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	NSNumber *current = [snapshot valueForMetricIdentifier:BAAnalyticsMetricAverageCurrentMilliamps];
	if (current)
		[details addObject:BAAnalyticsLabeledValue(_("Avg. Current"), [NSString stringWithFormat:@"%.0f mA", current.doubleValue])];
	NSNumber *voltage = [snapshot valueForMetricIdentifier:BAAnalyticsMetricVoltageMillivolts];
	if (voltage)
		[details addObject:BAAnalyticsLabeledValue(_("Voltage"), [NSString stringWithFormat:@"%.2f V", voltage.doubleValue / 1000.0])];
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:_("Avg. Power")
											   detailLines:details
											  historyPoints:[snapshot historyForMetricIdentifier:BAAnalyticsMetricAveragePowerWatts]];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreatePowerAverageCard(void) {
	return [BAAnalyticsPowerAverageCard new];
}
