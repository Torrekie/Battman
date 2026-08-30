//
//  BAAnalyticsTemperatureAverageCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"
#import "battery_utils/bin_display.h"

@interface BAAnalyticsTemperatureAverageCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsTemperatureAverageCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsTemperatureAverageCardIdentifier
							 displayName:_("Avg. Temperature")
							   cardTitle:nil
						 defaultCaption:_("Avg. Temperature")
							  symbolName:nil
						 fallbackGlyph:nil
							   tintColor:[UIColor compatOrangeColor]
						 supportedSizes:BAAnalyticsCardSizeMask1x1 | BAAnalyticsCardSizeMask1x2
							 defaultSize:BAAnalyticsCardSize1x1
							  showsGraph:NO];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *temperature = [snapshot valueForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius];
	NSString *value = temperature ? battman_temp_display_string(temperature.doubleValue) : _("Unavailable");
	NSArray<NSString *> *details = temperature ? @[BAAnalyticsLabeledValue(_("Hardware Temperature"), value)] : @[];
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:_("Avg. Temperature")
											   detailLines:details
											  historyPoints:[snapshot historyForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius]];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateTemperatureAverageCard(void) {
	return [BAAnalyticsTemperatureAverageCard new];
}
