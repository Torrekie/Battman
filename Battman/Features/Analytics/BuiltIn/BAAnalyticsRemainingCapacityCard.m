//
//  BAAnalyticsRemainingCapacityCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"

static NSString *BAAnalyticsCapacityString(NSNumber *capacity) {
	return capacity ? [NSString stringWithFormat:@"%.0f mAh", capacity.doubleValue] : _("Unavailable");
}

@interface BAAnalyticsRemainingCapacityCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsRemainingCapacityCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsRemainingCapacityCardIdentifier
							 displayName:_("Remaining Capacity")
							   cardTitle:_("Remaining Capacity")
						 defaultCaption:_("Full Charge Capacity")
							  symbolName:@"chart.bar.doc.horizontal"
						 fallbackGlyph:@"C"
							   tintColor:[UIColor compatBlueColor]
						 supportedSizes:BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2
							 defaultSize:BAAnalyticsCardSize2x1
							  showsGraph:YES];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *remaining = [snapshot valueForMetricIdentifier:BAAnalyticsMetricRemainingCapacityMilliampHours];
	NSNumber *full = [snapshot valueForMetricIdentifier:BAAnalyticsMetricFullChargeCapacityMilliampHours];
	NSNumber *design = [snapshot valueForMetricIdentifier:BAAnalyticsMetricDesignCapacityMilliampHours];
	NSNumber *health = [snapshot valueForMetricIdentifier:BAAnalyticsMetricBatteryHealthPercent];
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	if (design)
		[details addObject:BAAnalyticsLabeledValue(_("Designed Capacity"), BAAnalyticsCapacityString(design))];
	if (health) {
		[details addObject:BAAnalyticsLabeledValue(_("Max Capacity"), [NSString stringWithFormat:@"%.0f%%", health.doubleValue])];
		[details addObject:_("Health is calculated from Full Charge Capacity and Designed Capacity; it is not a runtime estimate.")];
	} else {
		[details addObject:_("Health is unavailable until both capacity readings are valid.")];
	}
	return [BAAnalyticsCardPresentation presentationWithValue:BAAnalyticsCapacityString(remaining)
														 caption:BAAnalyticsLabeledValue(_("Full Charge Capacity"), BAAnalyticsCapacityString(full))
														 detailLines:details
														 historyPoints:remaining ? [snapshot historyForMetricIdentifier:BAAnalyticsMetricRemainingCapacityMilliampHours] : @[]];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateRemainingCapacityCard(void) {
	return [BAAnalyticsRemainingCapacityCard new];
}
