//
//  BTAnalyticsCardsScreenshotHarness.m
//  Battman deterministic Simulator screenshots
//
//  Renders the six embedded production Analytics cards through the production
//  host cell. Every metric below is a fixed synthetic fixture; this executable
//  never constructs a metric service or reads device battery state.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../../Battman/ChargingLimitViewController.h"
#import "../../Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCard.h"
#import "../../Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCards.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#import "../../Battman/Features/Analytics/Host/AnalyticsCardCell.h"

#define BTRequire(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "FAIL: %s\n", [(message) UTF8String]); \
		return 1; \
	} \
} while (0)

// Production localization resolves to the source strings in this standalone,
// locale-independent evidence process.
NSString *cond_localize(const char *value) {
	return [NSString stringWithUTF8String:value];
}

const char *cond_localize_c(const char *value) {
	return value;
}

id perform_selector(SEL selector, id target, id argument) {
	if (!target || ![target respondsToSelector:selector])
		return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [target performSelector:selector withObject:argument];
#pragma clang diagnostic pop
}

id perform_selector2(SEL selector, id target, id firstArgument, id secondArgument) {
	if (!target || ![target respondsToSelector:selector])
		return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [target performSelector:selector withObject:firstArgument withObject:secondArgument];
#pragma clang diagnostic pop
}

// Temperature preferences and locale state are deliberately outside this
// screenshot fixture. The production card still owns the value selection and
// presentation; this display-boundary shim fixes the unit and decimal format.
NSString *battman_temp_display_string(double celsius) {
	return [NSString stringWithFormat:@"%.1f \u00b0C", celsius];
}

// The Charging Limit card's navigation action is not exercised here. This
// inert implementation satisfies its production class reference without
// linking daemon-backed controller dependencies into the screenshot process.
@implementation ChargingLimitViewController
@end

@interface BAAnalyticsCardCell (BTDeterministicScreenshots)
- (void)setJiggling:(BOOL)jiggling;
@end

typedef UITraitCollection *(*BTScreenTraitCollectionImplementation)(id, SEL);

static BTScreenTraitCollectionImplementation BTOriginalScreenTraitCollection;
static UIUserInterfaceStyle BTForcedInterfaceStyle = UIUserInterfaceStyleLight;

static UITraitCollection *BTScreenTraitCollection(id screen, SEL command) {
	UITraitCollection *base = BTOriginalScreenTraitCollection ?
		BTOriginalScreenTraitCollection(screen, command) : [UITraitCollection new];
	if (@available(iOS 13.0, *)) {
		UITraitCollection *appearance = [UITraitCollection
			traitCollectionWithUserInterfaceStyle:BTForcedInterfaceStyle];
		return [UITraitCollection traitCollectionWithTraitsFromCollections:@[base, appearance]];
	}
	return base;
}

static BOOL BTInstallScreenTraitOverride(void) {
	Method method = class_getInstanceMethod([UIScreen class], @selector(traitCollection));
	if (!method)
		return NO;
	BTOriginalScreenTraitCollection = (BTScreenTraitCollectionImplementation)
		method_setImplementation(method, (IMP)BTScreenTraitCollection);
	return BTOriginalScreenTraitCollection != NULL;
}

static void BTRestoreScreenTraitOverride(void) {
	Method method = class_getInstanceMethod([UIScreen class], @selector(traitCollection));
	if (method && BTOriginalScreenTraitCollection)
		method_setImplementation(method, (IMP)BTOriginalScreenTraitCollection);
}

static NSArray<BAAnalyticsMetricPoint *> *BTSyntheticHistory(NSArray<NSNumber *> *values) {
	NSDate *baseDate = [NSDate dateWithTimeIntervalSince1970:1700000000.0];
	NSMutableArray<BAAnalyticsMetricPoint *> *points = [NSMutableArray arrayWithCapacity:values.count];
	for (NSUInteger index = 0; index < values.count; index++) {
		NSTimeInterval offset = -300.0 * (NSTimeInterval)(values.count - index - 1);
		[points addObject:[[BAAnalyticsMetricPoint alloc]
			initWithTimestamp:[baseDate dateByAddingTimeInterval:offset]
			value:values[index].doubleValue]];
	}
	return points;
}

static BAAnalyticsMetricSnapshot *BTSyntheticMetricSnapshot(void) {
	NSDictionary<NSString *, NSNumber *> *values = @{
		BAAnalyticsMetricStateOfChargePercent: @73,
		BAAnalyticsMetricBatteryHealthPercent: @91,
		BAAnalyticsMetricAverageTemperatureCelsius: @31.5,
		BAAnalyticsMetricAverageCurrentMilliamps: @(-420),
		BAAnalyticsMetricVoltageMillivolts: @3975,
		BAAnalyticsMetricAveragePowerWatts: @(-1.67),
		BAAnalyticsMetricCycleCount: @321,
		BAAnalyticsMetricDesignCycleCount: @1000,
		BAAnalyticsMetricRemainingCapacityMilliampHours: @2468,
		BAAnalyticsMetricFullChargeCapacityMilliampHours: @3610,
		BAAnalyticsMetricDesignCapacityMilliampHours: @3968,
		BAAnalyticsMetricChargingState: @(BAAnalyticsChargingStateCharging),
		BAAnalyticsMetricChargingLimitPercent: @80,
		BAAnalyticsMetricChargingLimitServiceActive: @YES,
		BAAnalyticsMetricChargingLimitReached: @NO,
	};
	NSDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *histories = @{
		BAAnalyticsMetricStateOfChargePercent:
			BTSyntheticHistory(@[@61, @64, @66, @69, @71, @73]),
		BAAnalyticsMetricRemainingCapacityMilliampHours:
			BTSyntheticHistory(@[@2120, @2210, @2260, @2340, @2410, @2468]),
	};
	return [[BAAnalyticsMetricSnapshot alloc]
		initWithSequenceNumber:424242
		timestamp:[NSDate dateWithTimeIntervalSince1970:1700000000.0]
		values:values
		histories:histories];
}

static NSArray<NSString *> *BTExpectedCardIdentifiers(void) {
	return @[
		BAAnalyticsBatterySummaryCardIdentifier,
		BAAnalyticsTemperatureAverageCardIdentifier,
		BAAnalyticsPowerAverageCardIdentifier,
		BAAnalyticsCycleSummaryCardIdentifier,
		BAAnalyticsRemainingCapacityCardIdentifier,
		BAAnalyticsChargingLimitCardIdentifier,
	];
}

static NSArray<id<BAAnalyticsCard>> *BTProductionCards(void) {
	NSArray<id<BAAnalyticsCard>> *cards = BAAnalyticsCreateBuiltInCards();
	if (cards.count != BTExpectedCardIdentifiers().count)
		return nil;
	NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:cards.count];
	for (id<BAAnalyticsCard> card in cards)
		[identifiers addObject:card.analyticsCardIdentifier ?: @""];
	return [identifiers isEqualToArray:BTExpectedCardIdentifiers()] ? cards : nil;
}

static BOOL BTValidatePresentation(id<BAAnalyticsCard> card,
	BAAnalyticsMetricSnapshot *snapshot, NSString *expectedValue,
	NSString *expectedCaption, NSArray<NSString *> *expectedDetails) {
	if (![card isKindOfClass:[BAAnalyticsBuiltInCard class]]) {
		fprintf(stderr, "FAIL: built-in provider is not a BAAnalyticsBuiltInCard: %s\n",
			[card.analyticsCardIdentifier UTF8String]);
		return NO;
	}
	BAAnalyticsCardPresentation *presentation =
		[(BAAnalyticsBuiltInCard *)card presentationForSnapshot:snapshot];
	BOOL matches = presentation != nil &&
		[presentation.value isEqualToString:expectedValue] &&
		[presentation.caption isEqualToString:expectedCaption] &&
		[presentation.detailLines isEqualToArray:expectedDetails];
	if (!matches) {
		NSString *actualValue = presentation.value ?: @"<nil>";
		NSString *actualCaption = presentation.caption ?: @"<nil>";
		NSArray<NSString *> *actualDetails = presentation.detailLines ?: @[];
		fprintf(stderr, "FAIL: unexpected presentation for %s: value=%s caption=%s details=%s\n",
			[card.analyticsCardIdentifier UTF8String],
			[actualValue UTF8String],
			[actualCaption UTF8String],
			[[actualDetails description] UTF8String]);
		return NO;
	}
	NSArray<NSString *> *strings = [@[presentation.value, presentation.caption]
		arrayByAddingObjectsFromArray:presentation.detailLines];
	for (NSString *string in strings) {
		if ([string containsString:@"--"]) {
			fprintf(stderr, "FAIL: placeholder escaped into %s presentation\n",
				[card.analyticsCardIdentifier UTF8String]);
			return NO;
		}
	}
	return YES;
}

static BAAnalyticsMetricSnapshot *BTSnapshotWithValues(
	NSDictionary<NSString *, NSNumber *> *values) {
	return [[BAAnalyticsMetricSnapshot alloc]
		initWithSequenceNumber:1
		timestamp:[NSDate dateWithTimeIntervalSince1970:1700000000.0]
		values:values
		histories:@{}];
}

static BOOL BTValidateProviderPresentations(void) {
	NSArray<id<BAAnalyticsCard>> *cards = BTProductionCards();
	if (!cards)
		return NO;

	BAAnalyticsMetricSnapshot *complete = BTSyntheticMetricSnapshot();
	NSArray<NSDictionary<NSString *, id> *> *completeExpectations = @[
		@{ @"value": @"73%", @"caption": @"Battery",
			@"details": @[@"Health: 91%", @"Status: Charging"] },
		@{ @"value": @"31.5 °C", @"caption": @"Avg. Temperature",
			@"details": @[@"Hardware Temperature: 31.5 °C"] },
		@{ @"value": @"-1.67 W", @"caption": @"Avg. Power",
			@"details": @[@"Avg. Current: -420 mA", @"Voltage: 3.98 V"] },
		@{ @"value": @"321", @"caption": @"Cycle Count",
			@"details": @[@"Designed Cycle Count: 1000"] },
		@{ @"value": @"2468 mAh", @"caption": @"Full Charge Capacity: 3610 mAh",
			@"details": @[@"Designed Capacity: 3968 mAh", @"Max Capacity: 91%"] },
		@{ @"value": @"80%", @"caption": @"Status",
			@"details": @[@"Status: Active", @"Limit charging at (%): 80%"] },
	];
	for (NSUInteger index = 0; index < cards.count; index++) {
		NSDictionary<NSString *, id> *expected = completeExpectations[index];
		if (!BTValidatePresentation(cards[index], complete, expected[@"value"],
			expected[@"caption"], expected[@"details"]))
			return NO;
	}

	BAAnalyticsMetricSnapshot *empty = BTSnapshotWithValues(@{});
	NSArray<NSString *> *emptyCaptions = @[
		@"Battery", @"Avg. Temperature", @"Avg. Power", @"Cycle Count",
		@"Full Charge Capacity: Unavailable", @"Status",
	];
	for (NSUInteger index = 0; index < cards.count; index++) {
		if (!BTValidatePresentation(cards[index], empty, @"Unavailable",
			emptyCaptions[index], @[]))
			return NO;
	}

	NSArray<NSDictionary<NSString *, NSNumber *> *> *primaryOnlyValues = @[
		@{ BAAnalyticsMetricStateOfChargePercent: @55 },
		@{ BAAnalyticsMetricAverageTemperatureCelsius: @12.5 },
		@{ BAAnalyticsMetricAveragePowerWatts: @2.5 },
		@{ BAAnalyticsMetricCycleCount: @44 },
		@{ BAAnalyticsMetricRemainingCapacityMilliampHours: @1234 },
	];
	NSArray<NSString *> *primaryOnlyResults = @[
		@"55%", @"12.5 °C", @"2.50 W", @"44", @"1234 mAh",
	];
	NSArray<NSString *> *primaryOnlyCaptions = @[
		@"Battery", @"Avg. Temperature", @"Avg. Power", @"Cycle Count",
		@"Full Charge Capacity: Unavailable",
	];
	NSArray<NSArray<NSString *> *> *primaryOnlyDetails = @[
		@[], @[@"Hardware Temperature: 12.5 °C"], @[], @[], @[],
	];
	for (NSUInteger index = 0; index < primaryOnlyValues.count; index++) {
		if (!BTValidatePresentation(cards[index],
			BTSnapshotWithValues(primaryOnlyValues[index]), primaryOnlyResults[index],
			primaryOnlyCaptions[index], primaryOnlyDetails[index]))
			return NO;
	}

	id<BAAnalyticsCard> chargingLimit = cards[5];
	if (!BTValidatePresentation(chargingLimit,
		BTSnapshotWithValues(@{ BAAnalyticsMetricChargingLimitServiceActive: @NO }),
		@"Inactive", @"Status", @[@"Status: Inactive"]))
		return NO;
	if (!BTValidatePresentation(chargingLimit,
		BTSnapshotWithValues(@{ BAAnalyticsMetricChargingLimitServiceActive: @YES }),
		@"Unavailable", @"Status", @[@"Status: Active"]))
		return NO;
	if (!BTValidatePresentation(chargingLimit,
		BTSnapshotWithValues(@{
			BAAnalyticsMetricChargingLimitServiceActive: @YES,
			BAAnalyticsMetricChargingLimitPercent: @85,
		}), @"85%", @"Status",
		@[@"Status: Active", @"Limit charging at (%): 85%"]))
		return NO;

	return YES;
}

static void BTAddFixtureHeading(UIView *canvas, NSString *scenario, BOOL dark) {
	UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 13.0,
		CGRectGetWidth(canvas.bounds) - 36.0, 22.0)];
	title.text = @"ANALYTICS CARDS - SYNTHETIC FIXTURE";
	title.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
	title.textColor = dark ? [UIColor whiteColor] : [UIColor blackColor];
	title.textAlignment = NSTextAlignmentNatural;
	[canvas addSubview:title];

	UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(18.0, 35.0,
		CGRectGetWidth(canvas.bounds) - 36.0, 18.0)];
	subtitle.text = [NSString stringWithFormat:@"NO DEVICE DATA - fixed test metrics - %@", scenario];
	subtitle.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
	subtitle.textColor = dark ? [UIColor colorWithWhite:0.72 alpha:1.0] :
		[UIColor colorWithWhite:0.34 alpha:1.0];
	subtitle.textAlignment = NSTextAlignmentNatural;
	[canvas addSubview:subtitle];
}

static BOOL BTAddCard(UIView *canvas, id<BAAnalyticsCard> card,
	BAAnalyticsMetricSnapshot *snapshot, CGRect frame, BAAnalyticsCardSize size,
	BOOL editing, BOOL rightToLeft) {
	if (!card || !BAAnalyticsCardSizeMaskContainsSize(card.supportedAnalyticsCardSizes, size))
		return NO;
	BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:frame];
	if (rightToLeft)
		cell.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
	[canvas addSubview:cell];
	[cell configureWithCard:card size:size editing:editing];
	[cell applyMetricSnapshot:snapshot];
	[cell setAnalyticsCardDisplayed:YES];
	if (editing)
		[cell setJiggling:NO];
	[cell setNeedsLayout];
	[cell layoutIfNeeded];
	return YES;
}

static NSData *BTRenderView(UIView *view) {
	[view setNeedsLayout];
	[view layoutIfNeeded];
	UIGraphicsBeginImageContextWithOptions(view.bounds.size, YES, 1.0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context) {
		UIGraphicsEndImageContext();
		return nil;
	}
	[view.layer renderInContext:context];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return UIImagePNGRepresentation(image);
}

static BOOL BTWriteView(UIView *view, NSString *outputDirectory, NSString *filename) {
	NSString *path = [outputDirectory stringByAppendingPathComponent:filename];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path])
		return NO;
	NSData *data = BTRenderView(view);
	return data.length > 0 && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static BOOL BTRenderPhoneScenario(NSString *outputDirectory, NSString *filename,
	UIUserInterfaceStyle style, NSString *scenario) {
	BTForcedInterfaceStyle = style;
	BOOL dark = style == UIUserInterfaceStyleDark;
	UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 390.0, 844.0)];
	if (@available(iOS 13.0, *))
		canvas.overrideUserInterfaceStyle = style;
	canvas.backgroundColor = dark ? [UIColor blackColor] :
		[UIColor colorWithRed:0.975 green:0.975 blue:0.985 alpha:1.0];
	BTAddFixtureHeading(canvas, scenario, dark);

	NSArray<id<BAAnalyticsCard>> *cards = BTProductionCards();
	BAAnalyticsMetricSnapshot *snapshot = BTSyntheticMetricSnapshot();
	if (!cards ||
		!BTAddCard(canvas, cards[0], snapshot, CGRectMake(19.0, 66.0, 170.0, 170.0), BAAnalyticsCardSize1x1, NO, NO) ||
		!BTAddCard(canvas, cards[1], snapshot, CGRectMake(201.0, 66.0, 170.0, 170.0), BAAnalyticsCardSize1x1, NO, NO) ||
		!BTAddCard(canvas, cards[2], snapshot, CGRectMake(19.0, 248.0, 170.0, 170.0), BAAnalyticsCardSize1x1, NO, NO) ||
		!BTAddCard(canvas, cards[3], snapshot, CGRectMake(201.0, 248.0, 170.0, 170.0), BAAnalyticsCardSize1x1, NO, NO) ||
		!BTAddCard(canvas, cards[4], snapshot, CGRectMake(19.0, 430.0, 352.0, 170.0), BAAnalyticsCardSize2x1, NO, NO) ||
		!BTAddCard(canvas, cards[5], snapshot, CGRectMake(19.0, 612.0, 352.0, 170.0), BAAnalyticsCardSize2x1, NO, NO))
		return NO;
	return BTWriteView(canvas, outputDirectory, filename);
}

static BOOL BTRenderWideRTLEditingScenario(NSString *outputDirectory, NSString *filename) {
	BTForcedInterfaceStyle = UIUserInterfaceStyleLight;
	UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1024.0, 660.0)];
	if (@available(iOS 13.0, *))
		canvas.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
	canvas.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
	canvas.backgroundColor = [UIColor colorWithRed:0.975 green:0.975 blue:0.985 alpha:1.0];
	BTAddFixtureHeading(canvas, @"wide RTL editing", NO);

	NSArray<id<BAAnalyticsCard>> *cards = BTProductionCards();
	BAAnalyticsMetricSnapshot *snapshot = BTSyntheticMetricSnapshot();
	if (!cards ||
		!BTAddCard(canvas, cards[0], snapshot, CGRectMake(134.0, 66.0, 372.0, 180.0), BAAnalyticsCardSize2x1, YES, YES) ||
		!BTAddCard(canvas, cards[3], snapshot, CGRectMake(518.0, 66.0, 372.0, 180.0), BAAnalyticsCardSize2x1, YES, YES) ||
		!BTAddCard(canvas, cards[1], snapshot, CGRectMake(134.0, 258.0, 180.0, 372.0), BAAnalyticsCardSize1x2, YES, YES) ||
		!BTAddCard(canvas, cards[2], snapshot, CGRectMake(326.0, 258.0, 180.0, 372.0), BAAnalyticsCardSize1x2, YES, YES) ||
		!BTAddCard(canvas, cards[4], snapshot, CGRectMake(518.0, 258.0, 372.0, 180.0), BAAnalyticsCardSize2x1, YES, YES) ||
		!BTAddCard(canvas, cards[5], snapshot, CGRectMake(518.0, 450.0, 372.0, 180.0), BAAnalyticsCardSize2x1, YES, YES))
		return NO;
	return BTWriteView(canvas, outputDirectory, filename);
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTRequire(argc == 2, @"provide one existing, fresh output directory");
		NSString *outputDirectory = [NSString stringWithUTF8String:argv[1]];
		BOOL directory = NO;
		BTRequire([[NSFileManager defaultManager] fileExistsAtPath:outputDirectory
			isDirectory:&directory] && directory, @"output directory is unavailable");
		BTRequire([NSThread isMainThread], @"UIKit screenshot harness must run on the main thread");
		BTRequire(BTValidateProviderPresentations(),
			@"built-in provider success and unavailable contracts failed");
		BTRequire(BTInstallScreenTraitOverride(), @"could not install deterministic appearance traits");

		BOOL rendered = BTRenderPhoneScenario(outputDirectory,
			@"analytics-cards-synthetic-iphone-light.png",
			UIUserInterfaceStyleLight, @"iPhone light") &&
			BTRenderPhoneScenario(outputDirectory,
			@"analytics-cards-synthetic-iphone-dark.png",
			UIUserInterfaceStyleDark, @"iPhone dark") &&
			BTRenderWideRTLEditingScenario(outputDirectory,
				@"analytics-cards-synthetic-wide-rtl-edit.png");
		BTRestoreScreenTraitOverride();
		BTRequire(rendered, @"could not render all Analytics card screenshots into fresh paths");
		printf("Rendered six production Analytics cards using only fixed synthetic metrics.\n");
	}
	return 0;
}
