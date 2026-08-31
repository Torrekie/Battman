//
//  BAAnalyticsTemperatureAverageCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ObjCExt/UIColor+compat.h"
#import "battery_utils/bin_display.h"

#include <math.h>

@interface BAAnalyticsTemperatureAverageCard : BAAnalyticsBuiltInCard
@end

static BOOL BAAnalyticsTemperatureHistoryMayBeStale(NSArray<BAAnalyticsMetricPoint *> *points) {
	/* A stable room/device temperature is normal. Only flag a value after a
	 * long, contiguous run of identical samples, and keep the reading visible
	 * so the user can compare it with another sensor. */
	if (points.count < 6)
		return NO;
	BAAnalyticsMetricPoint *last = points.lastObject;
	NSUInteger startIndex = points.count - 1;
	while (startIndex > 0) {
		BAAnalyticsMetricPoint *previous = points[startIndex - 1];
		NSTimeInterval gap = [points[startIndex].timestamp timeIntervalSinceDate:previous.timestamp];
		if (!isfinite(gap) || gap < 0.0 || gap > 90.0)
			break;
		startIndex--;
		/* Include the sample that reaches the stale horizon. Checking after
		 * decrementing avoids stopping one point short of 240 seconds. */
		NSTimeInterval span = [last.timestamp timeIntervalSinceDate:points[startIndex].timestamp];
		if (!isfinite(span))
			return NO;
		if (span >= 240.0)
			break;
	}
	BAAnalyticsMetricPoint *first = points[startIndex];
	NSTimeInterval span = [last.timestamp timeIntervalSinceDate:first.timestamp];
	if (!isfinite(span) || span < 240.0)
		return NO;
	double reference = last.value;
	for (NSUInteger index = startIndex; index < points.count; index++) {
		BAAnalyticsMetricPoint *point = points[index];
		NSDate *previousTimestamp = index == startIndex ? first.timestamp : points[index - 1].timestamp;
		NSTimeInterval gap = [point.timestamp timeIntervalSinceDate:previousTimestamp];
		if (!isfinite(gap) || gap < 0.0 || gap > 90.0 || fabs(point.value - reference) > 0.001)
			return NO;
	}
	return YES;
}

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
	BOOL mayBeStale = temperature && BAAnalyticsTemperatureHistoryMayBeStale([snapshot historyForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius]);
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	if (temperature) {
		[details addObject:BAAnalyticsLabeledValue(_("Hardware Temperature"), value)];
		if (mayBeStale)
			[details addObject:_("No change detected for several minutes; verify this reading with another sensor if it looks wrong.")];
	} else {
		[details addObject:_("Temperature is unavailable because no valid hardware reading was returned.")];
	}
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:mayBeStale ? _("Potentially Stale") : _("Avg. Temperature")
											   detailLines:details
											  historyPoints:[snapshot historyForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius]];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateTemperatureAverageCard(void) {
	return [BAAnalyticsTemperatureAverageCard new];
}
