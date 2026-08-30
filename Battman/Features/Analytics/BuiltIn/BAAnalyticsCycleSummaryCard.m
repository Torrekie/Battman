//
//  BAAnalyticsCycleSummaryCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"

static NSString *BAAnalyticsUptimeString(NSTimeInterval seconds) {
	NSDateComponentsFormatter *formatter = [NSDateComponentsFormatter new];
	formatter.allowedUnits = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
	formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
	formatter.maximumUnitCount = 2;
	formatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
	return [formatter stringFromTimeInterval:MAX(0.0, seconds)] ?: [NSString stringWithFormat:@"%.0f s", seconds];
}

@interface BAAnalyticsCycleSummaryCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsCycleSummaryCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsCycleSummaryCardIdentifier
							 displayName:_("Cycle Count")
							   cardTitle:nil
						 defaultCaption:_("Cycle Count")
							  symbolName:nil
						 fallbackGlyph:nil
							   tintColor:[UIColor compatGrayColor]
						 supportedSizes:BAAnalyticsCardSizeMaskAll
							 defaultSize:BAAnalyticsCardSize1x1
							  showsGraph:NO];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *cycleCount = [snapshot valueForMetricIdentifier:BAAnalyticsMetricCycleCount];
	NSString *value = cycleCount ? [NSString stringWithFormat:@"%llu", cycleCount.unsignedLongLongValue] : _("Unavailable");
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	NSNumber *designCycleCount = [snapshot valueForMetricIdentifier:BAAnalyticsMetricDesignCycleCount];
	if (designCycleCount)
		[details addObject:BAAnalyticsLabeledValue(_("Designed Cycle Count"), [NSString stringWithFormat:@"%llu", designCycleCount.unsignedLongLongValue])];
	NSNumber *uptime = [snapshot valueForMetricIdentifier:BAAnalyticsMetricBatteryUptimeSeconds];
	if (uptime)
		[details addObject:BAAnalyticsLabeledValue(_("Battery Uptime"), BAAnalyticsUptimeString(uptime.doubleValue))];
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:_("Cycle Count")
											   detailLines:details
											  historyPoints:nil];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateCycleSummaryCard(void) {
	return [BAAnalyticsCycleSummaryCard new];
}
