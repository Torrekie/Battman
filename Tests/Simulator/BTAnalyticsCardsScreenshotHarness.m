// Actual UIKit host + production V3 canvases. All measurements are synthetic.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "BAAnalyticsV3Fixtures.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#import "../../Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCards.h"
#import "../../Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInPlugin.h"
#import "../../Battman/Features/Analytics/BuiltIn/Canvas/BAAnalyticsCanvasCard.h"
#import "../../Battman/Features/Analytics/Host/AnalyticsViewController.h"
#import "../../Battman/Features/Analytics/Host/AnalyticsCardCell.h"
#import "../../Battman/Features/Analytics/Host/BAAnalyticsCardLayoutStore.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsSystemMetricSource.h"
#import "../../Battman/PluginHost/Application/BTPluginPlatform.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/ObjCExt/UIColor+compat.h"
#import "../../Battman/Features/Analytics/BuiltIn/Canvas/BAAnalyticsDetailViewController.h"
#import "../../Battman/Features/Analytics/BuiltIn/Live/BAAnalyticsLiveDrawing.h"
#import "../../Battman/Features/Analytics/BuiltIn/Statistics/BAStatisticsDrawing.h"
#import "../../Battman/Features/Analytics/BuiltIn/Process/BAAnalyticsProcessDrawing.h"
#import <objc/message.h>
#include <math.h>
static void DrainUI(void) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:.25]; while([end timeIntervalSinceNow]>0) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:end]; }
static void Require(BOOL condition,NSString *message) { if(!condition) @throw [NSException exceptionWithName:@"FixtureFailure" reason:message userInfo:nil]; }
static void WaitForFixture(BOOL (^ready)(void), NSTimeInterval seconds, NSString *message) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!ready() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    Require(ready(), message);
}
static void CollectCanvases(UIView *view, NSMutableArray<BAAnalyticsCanvasView *> *canvases) {
    if ([view isKindOfClass:BAAnalyticsCanvasView.class]) [canvases addObject:(id)view];
    for (UIView *child in view.subviews) CollectCanvases(child, canvases);
}
static void AwaitPreparedCanvases(UIView *view) {
    [view layoutIfNeeded];
    NSMutableArray<BAAnalyticsCanvasView *> *canvases = [NSMutableArray array];
    CollectCanvases(view, canvases);
    WaitForFixture(^BOOL {
        for (BAAnalyticsCanvasView *canvas in canvases) if (canvas.isPreparingHistory) return NO;
        return YES;
    }, 5, @"Canvas history preparation exceeded five seconds");
    // Drain a UI turn after the completion's invalidations before reading marks
    // or rasterizing. Do not impose a quarter-second delay on every matrix image.
    [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    [view layoutIfNeeded];
    for (BAAnalyticsCanvasView *canvas in canvases) { [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded]; }
}
static NSNumber *CapacitySummaryNumber(NSArray<NSDictionary *> *rows, NSUInteger index) {
    NSString *value = [rows[index][@"value"] stringByReplacingOccurrencesOfString:@" mAh" withString:@""];
    value = [value stringByReplacingOccurrencesOfString:@"%" withString:@""];
    NSNumberFormatter *formatter = [NSNumberFormatter new]; formatter.numberStyle = NSNumberFormatterDecimalStyle;
    return [formatter numberFromString:value];
}
static NSString *FixtureLanguage = @"en";
NSString *cond_localize(const char *v) {
    static NSDictionary *catalogs; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"fixture-catalogs" ofType:@"json"]];
        catalogs = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    });
    NSString *msgid = [NSString stringWithUTF8String:v];
    return catalogs[FixtureLanguage][msgid] ?: msgid;
}
const char *cond_localize_c(const char *v) { return v; }
id perform_selector(SEL s,id t,id v) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [t respondsToSelector:s]?[t performSelector:s withObject:v]:nil;
#pragma clang diagnostic pop
}
id perform_selector2(SEL s,id t,id a,id b) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    return [t respondsToSelector:s]?[t performSelector:s withObject:a withObject:b]:nil;
#pragma clang diagnostic pop
}
UIImage *imageForSFProGlyph(NSString *g,NSString *f,CGFloat s,UIColor *c) { (void)g;(void)f;(void)s;(void)c;return nil; }
// The injected initializer must never reach either physical acquisition boundary.
@implementation BAAnalyticsSystemMetricSource
- (NSDictionary *)readAnalyticsMetricValues { Require(NO,@"Physical metric source reached by fixture");return @{}; }
@end
@implementation BTPluginPlatform
+ (instancetype)sharedPlatform { Require(NO,@"Production composition reached by fixture");return nil; }
@end
static UIUserInterfaceStyle ForcedStyle=UIUserInterfaceStyleLight;
static UIContentSizeCategory ForcedCategory=nil;
static IMP OriginalTraitCategory=NULL,OriginalApplicationCategory=NULL;
static NSInteger TestStyle(id object,SEL command) { (void)object;(void)command;return ForcedStyle; }
static id TestTraitCategory(id object,SEL command) { return ForcedCategory?:((id(*)(id,SEL))OriginalTraitCategory)(object,command); }
static id TestApplicationCategory(id object,SEL command) { return ForcedCategory?:((id(*)(id,SEL))OriginalApplicationCategory)(object,command); }
static IMP OriginalScaledFont=NULL, OriginalCappedFont=NULL;
static UIFont *TestScaledFont(UIFontMetrics *metrics,SEL command,UIFont *font) {
    if (ForcedCategory) return [metrics scaledFontForFont:font compatibleWithTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:ForcedCategory]];
    return ((UIFont *(*)(id,SEL,UIFont *))OriginalScaledFont)(metrics,command,font);
}
static UIFont *TestCappedFont(UIFontMetrics *metrics,SEL command,UIFont *font,CGFloat maximum) {
    if (ForcedCategory) return [metrics scaledFontForFont:font maximumPointSize:maximum compatibleWithTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:ForcedCategory]];
    return ((UIFont *(*)(id,SEL,UIFont *,CGFloat))OriginalCappedFont)(metrics,command,font,maximum);
}
static void InstallPresentationOverrides(void) {
    OriginalScaledFont=method_setImplementation(class_getInstanceMethod(UIFontMetrics.class,@selector(scaledFontForFont:)),(IMP)TestScaledFont);
    OriginalCappedFont=method_setImplementation(class_getInstanceMethod(UIFontMetrics.class,@selector(scaledFontForFont:maximumPointSize:)),(IMP)TestCappedFont);
    // iOS 12 has no native Dark Mode. This only exercises the fallback palette.
    Method style=class_getInstanceMethod(UITraitCollection.class,@selector(userInterfaceStyle));
    if(style)method_setImplementation(style,(IMP)TestStyle);else class_addMethod(UITraitCollection.class,@selector(userInterfaceStyle),(IMP)TestStyle,"q@:");
    Method trait=class_getInstanceMethod(UITraitCollection.class,@selector(preferredContentSizeCategory));OriginalTraitCategory=method_setImplementation(trait,(IMP)TestTraitCategory);
    Method app=class_getInstanceMethod(UIApplication.class,@selector(preferredContentSizeCategory));OriginalApplicationCategory=method_setImplementation(app,(IMP)TestApplicationCategory);
}

// Large reports remain synthetic and unit-validated. Building the immutable
// windows is intentionally dispatched off main by the performance check.
static BAAnalyticsReport *PerformanceReport(NSUInteger count) {
    BAAnalyticsReport *base = BAFixtureReport(@"ready");
    NSDate *end = base.generatedAt;
    NSMutableArray *capacity = [NSMutableArray arrayWithCapacity:count], *cells = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray *capacityIntervals = [NSMutableArray array], *cellIntervals = [NSMutableArray array];
    NSMutableArray *capacityGaps = [NSMutableArray array], *cellGaps = [NSMutableArray array];
    NSString *fcc = BAAnalyticsHistoryFullChargeCapacityMilliampHours, *design = BAAnalyticsHistoryDesignCapacityMilliampHours;
    NSArray *metrics = @[fcc, design, BAAnalyticsHistoryCycleCount, BAAnalyticsHistorySOCPercent,
        BAAnalyticsHistoryTemperatureCelsius, BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging,
        BAAnalyticsHistoryFullyCharged, BAAnalyticsHistoryCellVoltage0Millivolts, BAAnalyticsHistoryCellVoltage1Millivolts,
        BAAnalyticsHistoryCellVoltage2Millivolts];
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    for (NSString *metric in metrics) {
        NSString *unit = [metric isEqual:fcc] || [metric isEqual:design] ? @"mAh" :
            [metric hasPrefix:@"cell-voltage."] ? @"mV" : [metric isEqual:BAAnalyticsHistorySOCPercent] ? @"%" :
            [metric isEqual:BAAnalyticsHistoryTemperatureCelsius] ? @"°C" : [metric isEqual:BAAnalyticsHistoryCycleCount] ? @"count" : @"boolean";
        metadata[metric] = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.performance" sourceColumn:metric
            unit:unit decoderIdentifier:@"fixture.performance.v1" unitValidated:YES];
    }
    NSDate *capacityStart = [end dateByAddingTimeInterval:-30 * 86400], *cellStart = [end dateByAddingTimeInterval:-6 * 3600];
    for (NSUInteger i = 0; i < count; i++) @autoreleasepool {
        double fraction = (double)i / (count - 1);
        double value = i == 1777 ? 2777 : i == 5333 ? 4999 : 3600 - 80 * fraction + 12 * sin(i * .07);
        NSDate *capacityDate = [capacityStart dateByAddingTimeInterval:30 * 86400 * fraction];
        NSDictionary *capacityValues = @{fcc:@(value), design:@(i < count / 2 ? 4000 : 4200), BAAnalyticsHistoryCycleCount:@(500 + i / 100)};
        BAAnalyticsObservation *point = [[BAAnalyticsObservation alloc] initWithIdentifier:[NSString stringWithFormat:@"performance.capacity.%lu",(unsigned long)i]
            timestamp:capacityDate sourceTimestamp:capacityDate.timeIntervalSince1970 timestampValidated:YES values:capacityValues fieldMetadata:metadata];
        BOOL connected = (i / 500) % 2 == 0;
        double cellValue = i == 1234 ? 3200 : i == 5678 ? 4450 : 3800 + 100 * sin(i * .015);
        NSDate *cellDate = [cellStart dateByAddingTimeInterval:6 * 3600 * fraction];
        NSDictionary *cellValues = @{BAAnalyticsHistorySOCPercent:@(20 + 70 * ((i % 1000) / 999.0)),
            BAAnalyticsHistoryTemperatureCelsius:@(30 + 4 * sin(i * .02)), BAAnalyticsHistoryExternalConnected:@(connected),
            BAAnalyticsHistoryIsCharging:@(connected), BAAnalyticsHistoryFullyCharged:@NO,
            BAAnalyticsHistoryCellVoltage0Millivolts:@(cellValue), BAAnalyticsHistoryCellVoltage1Millivolts:@(cellValue + 8),
            BAAnalyticsHistoryCellVoltage2Millivolts:@(cellValue + 13)};
        BAAnalyticsObservation *cell = [[BAAnalyticsObservation alloc] initWithIdentifier:[NSString stringWithFormat:@"performance.cells.%lu",(unsigned long)i]
            timestamp:cellDate sourceTimestamp:cellDate.timeIntervalSince1970 timestampValidated:YES values:cellValues fieldMetadata:metadata];
        if (i) {
            BAAnalyticsObservation *priorCapacity = capacity.lastObject, *priorCell = cells.lastObject;
            if (i % 257 == 0) {
                [capacityGaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:priorCapacity.timestamp endDate:point.timestamp reason:@"Synthetic missing pair"]];
                [cellGaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:priorCell.timestamp endDate:cell.timestamp reason:@"Synthetic missing pair"]];
            } else {
                [capacityIntervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:priorCapacity.timestamp endDate:point.timestamp
                    startObservation:priorCapacity endObservation:point coveredMetricIdentifiers:[NSSet setWithArray:capacityValues.allKeys] state:BAAnalyticsObservedStateUnknown]];
                NSMutableSet *covered = [NSMutableSet setWithArray:cellValues.allKeys];
                BOOL stableConnection = [priorCell.values[BAAnalyticsHistoryExternalConnected] boolValue] == connected;
                if (!stableConnection) { [covered removeObject:BAAnalyticsHistoryExternalConnected]; [covered removeObject:BAAnalyticsHistoryIsCharging]; }
                [cellIntervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:priorCell.timestamp endDate:cell.timestamp
                    startObservation:priorCell endObservation:cell coveredMetricIdentifiers:covered
                    state:stableConnection ? (connected ? BAAnalyticsObservedStateCharging : BAAnalyticsObservedStateUnplugged) : BAAnalyticsObservedStateUnknown]];
            }
        }
        [capacity addObject:point]; [cells addObject:cell];
    }
    BAAnalyticsHistoryWindow *capacityWindow = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:capacityStart endDate:end observations:capacity
        intervals:capacityIntervals gaps:capacityGaps coverageMetricIdentifiers:[NSSet setWithObject:fcc] coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
    BAAnalyticsHistoryWindow *cellWindow = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:cellStart endDate:end observations:cells
        intervals:cellIntervals gaps:cellGaps coverageMetricIdentifiers:[NSSet setWithObjects:BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected,nil]
        coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
    NSMutableDictionary *families = [base.familyReports mutableCopy];
    for (NSString *family in @[BAAnalyticsFamilyCapacity,BAAnalyticsFamilyCells,BAAnalyticsFamilyDwell,BAAnalyticsFamilyRhythm]) {
        BOOL isCapacity = [family isEqual:BAAnalyticsFamilyCapacity];
        families[family] = [[BAAnalyticsFamilyReport alloc] initWithFamily:family availability:BAAnalyticsReportAvailabilityPartial
            window:isCapacity ? capacityWindow : cellWindow payload:@{BAAnalyticsPayloadLatestObservation:isCapacity ? capacity.lastObject : cells.lastObject}
            limitations:@[@"Synthetic performance history; missing sampled pairs remain explicit"]];
    }
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:100 generatedAt:end sourceProfileIdentifier:@"synthetic.performance.v1"
        fieldMetadata:metadata familyReports:families error:nil];
}
static BAAnalyticsReport *PerformanceGeneration(BAAnalyticsReport *report, uint64_t sequence) {
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:sequence generatedAt:report.generatedAt sourceProfileIdentifier:report.sourceProfileIdentifier
        fieldMetadata:report.fieldMetadata familyReports:report.familyReports error:nil];
}

static BAAnalyticsReport *PerformanceEventsReport(NSUInteger count) {
    BAAnalyticsReport *base = BAFixtureReport(@"ready");
    NSDate *origin = [base.generatedAt dateByAddingTimeInterval:-10.0 * (NSTimeInterval)count];
    NSMutableArray *observations = [NSMutableArray array], *intervals = [NSMutableArray array];
    NSMutableArray *gaps = [NSMutableArray array], *transitions = [NSMutableArray array];
    NSArray *states = @[@(BAAnalyticsObservedStateCharging), @(BAAnalyticsObservedStateConnectedNotCharging),
        @(BAAnalyticsObservedStateFull), @(BAAnalyticsObservedStateUnplugged), @(BAAnalyticsObservedStateUnknown)];
    for (NSUInteger index = 0; index <= count; index++) @autoreleasepool {
        NSDate *time = [origin dateByAddingTimeInterval:10 * index];
        BAAnalyticsObservedState state = [states[(index / 320) % states.count] integerValue];
        double current = index % 17 == 0 ? 0 : (index % 450 < 225 ? 1600 : -650) + 300 * sin(index * .09);
        NSMutableDictionary *values = [@{BAAnalyticsHistoryCurrentMilliamps:@(current), BAAnalyticsHistorySOCPercent:@(50 + 20 * sin(index * .004)),
            BAAnalyticsHistoryTemperatureCelsius:@(30 + 3 * sin(index * .007))} mutableCopy];
        if (state != BAAnalyticsObservedStateUnknown) {
            values[BAAnalyticsHistoryExternalConnected] = @(state != BAAnalyticsObservedStateUnplugged);
            values[BAAnalyticsHistoryIsCharging] = @(state == BAAnalyticsObservedStateCharging);
            values[BAAnalyticsHistoryFullyCharged] = @(state == BAAnalyticsObservedStateFull);
        }
        BAAnalyticsObservation *observation = [[BAAnalyticsObservation alloc] initWithIdentifier:
            [NSString stringWithFormat:@"performance.events.%lu", (unsigned long)index] timestamp:time sourceTimestamp:time.timeIntervalSince1970
            timestampValidated:YES values:values fieldMetadata:base.fieldMetadata];
        if (observations.count) {
            BAAnalyticsObservation *previous = observations.lastObject;
            NSMutableSet *covered = [NSMutableSet setWithArray:values.allKeys]; [covered intersectSet:[NSSet setWithArray:previous.values.allKeys]];
            BAAnalyticsObservedState previousState = [states[((index - 1) / 320) % states.count] integerValue];
            [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:previous.timestamp endDate:time startObservation:previous
                endObservation:observation coveredMetricIdentifiers:covered state:previousState == state ? state : BAAnalyticsObservedStateUnknown]];
            if (index % 41 == 0) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:[time dateByAddingTimeInterval:-9.8]
                endDate:[time dateByAddingTimeInterval:-9.4] reason:@"Synthetic source discontinuity"]];
        }
        [observations addObject:observation];
        if (index < count && index % 7 == 0) [transitions addObject:[[BAAnalyticsStateTransition alloc] initWithIdentifier:
            [NSString stringWithFormat:@"performance.events.transition.%lu", (unsigned long)index] earliestDate:[time dateByAddingTimeInterval:1]
            latestDate:[time dateByAddingTimeInterval:26] previousState:BAAnalyticsObservedStateCharging
            nextState:BAAnalyticsObservedStateConnectedNotCharging reasonCode:nil]];
    }
    // Nested interval ends catch a sweep that incorrectly advances by end time.
    for (NSArray<NSNumber *> *bounds in @[@[@20,@35], @[@21,@23]]) {
        BAAnalyticsObservation *first = observations[[bounds[0] unsignedIntegerValue]], *last = observations[[bounds[1] unsignedIntegerValue]];
        [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:first.timestamp endDate:last.timestamp startObservation:first
            endObservation:last coveredMetricIdentifiers:[NSSet setWithArray:first.values.allKeys] state:BAAnalyticsObservedStateCharging]];
    }
    [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:[origin dateByAddingTimeInterval:400]
        endDate:[origin dateByAddingTimeInterval:430] reason:@"Synthetic closed gap bounds"]];
    [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:[origin dateByAddingTimeInterval:6500]
        endDate:[origin dateByAddingTimeInterval:6500] reason:@"Synthetic point discontinuity"]];
    for (NSArray *spec in @[@[@"left-touch",@395,@400], @[@"right-touch",@430,@435], @[@"gap-overlap",@402,@403],
            @[@"point-gap-start",@400,@400], @[@"point-gap-end",@430,@430], @[@"point-zero-gap",@6500,@6500],
            @[@"point-clear",@3002,@3002], @[@"nested-range",@215,@345]]) {
        [transitions addObject:[[BAAnalyticsStateTransition alloc] initWithIdentifier:[@"performance.events." stringByAppendingString:spec[0]]
            earliestDate:[origin dateByAddingTimeInterval:[spec[1] doubleValue]] latestDate:[origin dateByAddingTimeInterval:[spec[2] doubleValue]]
            previousState:BAAnalyticsObservedStateCharging nextState:BAAnalyticsObservedStateUnplugged reasonCode:nil]];
    }
    BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:origin endDate:base.generatedAt observations:observations
        intervals:intervals gaps:gaps coverageMetricIdentifiers:[NSSet setWithObject:BAAnalyticsHistoryExternalConnected]
        coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
    BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyEvents availability:BAAnalyticsReportAvailabilityPartial
        window:window payload:@{BAAnalyticsPayloadTransitions:transitions.reverseObjectEnumerator.allObjects}
        limitations:@[@"Synthetic dense sampled states, overlapping transitions and explicit source gaps"]];
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:401 generatedAt:base.generatedAt sourceProfileIdentifier:@"synthetic.performance.events.v1"
        fieldMetadata:base.fieldMetadata familyReports:@{BAAnalyticsFamilyEvents:family} error:nil];
}

// Independent legacy predicates are the oracle for the optimized sweep. They
// run once on the fixture worker, never in the production layout/drawing path.
static NSDictionary *PerformanceEventsReference(BAAnalyticsFamilyReport *family) {
    NSMutableArray *valid = [NSMutableArray array];
    for (BAAnalyticsStateTransition *transition in family.payload[BAAnalyticsPayloadTransitions]) {
        if ([transition.latestDate compare:transition.earliestDate] == NSOrderedAscending ||
            [transition.latestDate compare:family.window.startDate] == NSOrderedAscending ||
            [transition.earliestDate compare:family.window.endDate] == NSOrderedDescending || transition.previousState == transition.nextState) continue;
        BOOL intersects = NO;
        for (BAAnalyticsHistoryGap *gap in family.window.gaps) {
            BOOL strict = [transition.latestDate compare:gap.startDate] == NSOrderedDescending &&
                [transition.earliestDate compare:gap.endDate] == NSOrderedAscending;
            BOOL closedPoint = [transition.earliestDate isEqualToDate:transition.latestDate] &&
                [transition.earliestDate compare:gap.startDate] != NSOrderedAscending && [transition.latestDate compare:gap.endDate] != NSOrderedDescending;
            if (strict || closedPoint) { intersects = YES; break; }
        }
        if (!intersects) [valid addObject:transition];
    }
    [valid sortUsingComparator:^NSComparisonResult(BAAnalyticsStateTransition *a, BAAnalyticsStateTransition *b) { return [a.earliestDate compare:b.earliestDate]; }];
    NSMutableArray *states = [NSMutableArray array];
    NSDate *cursor = family.window.startDate;
    NSTimeInterval known = 0;
    for (BAAnalyticsHistoryInterval *interval in BAProcessOrderedIntervals(family.window.intervals)) {
        BAAnalyticsObservedState state = interval.state;
        for (BAAnalyticsStateTransition *transition in valid) {
            if ([interval.endDate compare:transition.earliestDate] == NSOrderedDescending &&
                [interval.startDate compare:transition.latestDate] == NSOrderedAscending) { state = BAAnalyticsObservedStateUnknown; break; }
        }
        [states addObject:@(state)];
        if (state == BAAnalyticsObservedStateUnknown || !BAProcessIntervalUsable(interval, @[], family.window.gaps)) continue;
        NSDate *first = [[interval.startDate laterDate:family.window.startDate] laterDate:cursor];
        NSDate *last = [interval.endDate earlierDate:family.window.endDate];
        if ([last compare:first] == NSOrderedDescending) known += [last timeIntervalSinceDate:first];
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
    }
    return @{@"transitions":valid.copy, @"states":states.copy, @"knownSeconds":@(known)};
}

// Independent complete sessions exercise drawing reduction without changing
// the sample population used for quantiles, counts or exact session details.
static BAAnalyticsReport *StartupRefreshReport(BAAnalyticsReport *base, uint64_t sequence) {
    const NSUInteger sessionCount = 80;
    NSMutableArray *sessions = [NSMutableArray array], *observations = [NSMutableArray array], *intervals = [NSMutableArray array];
    NSDate *origin = [base.generatedAt dateByAddingTimeInterval:-22 * 86400];
    NSArray *metrics = @[BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryTemperatureCelsius,
        BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging, BAAnalyticsHistoryFullyCharged];
    for (NSUInteger i = 0; i < sessionCount; i++) {
        NSDate *start = [origin dateByAddingTimeInterval:i * 6 * 3600];
        NSTimeInterval step = i == 53 ? 10 : i == 27 ? 600 : 45 + i * 3;
        NSMutableArray *records = [NSMutableArray array], *pairs = [NSMutableArray array];
        for (NSUInteger point = 0; point < 4; point++) {
            NSDate *time = [start dateByAddingTimeInterval:point * step];
            double temperature = i == 17 ? 56 : i == 41 ? 22 : 25 + i * .15;
            NSDictionary *values = @{BAAnalyticsHistorySOCPercent:@(10 + point * 80.0 / 3),
                BAAnalyticsHistoryTemperatureCelsius:@(temperature + (point == 2 ? 2 : 0)),
                BAAnalyticsHistoryExternalConnected:@YES, BAAnalyticsHistoryIsCharging:@YES, BAAnalyticsHistoryFullyCharged:@NO};
            BAAnalyticsObservation *record = [[BAAnalyticsObservation alloc] initWithIdentifier:
                [NSString stringWithFormat:@"startup.session.%lu.%lu", (unsigned long)i, (unsigned long)point]
                timestamp:time sourceTimestamp:time.timeIntervalSince1970 timestampValidated:YES values:values fieldMetadata:base.fieldMetadata];
            if (records.count) {
                BAAnalyticsObservation *previous = records.lastObject;
                [pairs addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:previous.timestamp endDate:time
                    startObservation:previous endObservation:record coveredMetricIdentifiers:[NSSet setWithArray:metrics]
                    state:BAAnalyticsObservedStateCharging]];
            }
            [records addObject:record];
        }
        BAAnalyticsHistorySession *session = [[BAAnalyticsHistorySession alloc] initWithIdentifier:
            [NSString stringWithFormat:@"startup.session.%lu", (unsigned long)i] kind:@"connected" startDate:start
            endDate:((BAAnalyticsObservation *)records.lastObject).timestamp startBoundaryKnown:YES endBoundaryKnown:YES
            observations:records intervals:pairs gaps:@[] transitions:@[]];
        [sessions addObject:session]; [observations addObjectsFromArray:records]; [intervals addObjectsFromArray:pairs];
    }
    BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:[base.generatedAt dateByAddingTimeInterval:-30 * 86400]
        endDate:base.generatedAt observations:observations intervals:intervals gaps:@[]
        coverageMetricIdentifiers:[NSSet setWithArray:metrics] coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
    NSMutableDictionary *families = [base.familyReports mutableCopy];
    families[BAAnalyticsFamilyCompare] = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCompare
        availability:BAAnalyticsReportAvailabilityReady window:window payload:@{BAAnalyticsPayloadSessions:sessions}
        limitations:@[@"Synthetic complete independent sessions"]];
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:sequence generatedAt:base.generatedAt
        sourceProfileIdentifier:base.sourceProfileIdentifier fieldMetadata:base.fieldMetadata familyReports:families error:nil];
}

static NSArray<NSDictionary *> *CanvasHitSignature(BAAnalyticsCanvasView *canvas) {
    NSMutableArray *signature = [NSMutableArray array];
    for (BAAnalyticsCanvasHitRegion *hit in canvas.hitRegions) {
        BAAnalyticsDetailSelection *selection = hit.selection;
        [signature addObject:@{@"rect":NSStringFromCGRect(hit.rect), @"kind":selection.kind ?: @"",
            @"records":selection.recordIdentifiers ?: @[], @"metrics":selection.metricIdentifiers ?: @[],
            @"start":selection.startDate ?: NSNull.null, @"end":selection.endDate ?: NSNull.null,
            @"sequence":selection.context[@"reportSequence"] ?: @0}];
    }
    return signature;
}

@interface BAPerformanceStatisticalCard : BASStatisticalCard
@property (atomic) NSUInteger derivationCount;
@property (atomic) BOOL derivedOnMainThread;
@property (atomic) BOOL workerStarted;
@property (atomic) BOOL holdNextDerivation;
@property (nonatomic, strong) dispatch_semaphore_t gate;
@end
@implementation BAPerformanceStatisticalCard
- (BAAnalyticsCanvasView *)makeCanvasView { return [BASStatisticalView new]; }
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family calendar:(NSCalendar *)calendar {
    self.derivationCount = self.derivationCount + 1;
    self.derivedOnMainThread = self.derivedOnMainThread || NSThread.isMainThread;
    BOOL hold = self.holdNextDerivation; self.holdNextDerivation = NO;
    self.workerStarted = YES;
    if (hold && self.gate) dispatch_semaphore_wait(self.gate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    return BAStatisticsDwell(family.window);
}
@end
@interface BAFixtureTouch : NSObject
@property (nonatomic) CGPoint point;
@end
@implementation BAFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view;return self.point; }
@end
@interface AnalyticsViewController (FixtureActions)
- (void)addCard:(id<BAAnalyticsCard>)card;
@end
@interface BAAnalyticsCanvasView (FixtureEventsEvidence)
- (NSArray<BAAnalyticsStateTransition *> *)transitionsForFamily:(BAAnalyticsFamilyReport *)family;
- (BAAnalyticsObservedState)stateForInterval:(BAAnalyticsHistoryInterval *)interval transitionCursor:(NSUInteger *)cursor;
- (NSTimeInterval)knownStateDuration:(BAAnalyticsFamilyReport *)family transitions:(NSArray *)transitions;
@end
@interface FixtureAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic,strong) UIWindow *window;
@property (nonatomic,strong) AnalyticsViewController *host;
@property (nonatomic,strong) UINavigationController *navigation;
@property (nonatomic,strong) BAFixtureHistoryService *history;
@property (nonatomic,strong) BAFixtureMetricService *metrics;
@property (nonatomic,strong) NSArray *cards;
@property (nonatomic,strong) NSUserDefaults *defaults;
@property (nonatomic,strong) NSMutableArray *manifest;
@property (nonatomic,copy) NSString *output;
@property (nonatomic,strong) NSMutableDictionary *performanceResults;
@end
@implementation FixtureAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;(void)options;
    InstallPresentationOverrides();[UIView setAnimationsEnabled:NO];
    self.output=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];self.manifest=[NSMutableArray array];
    Require([NSFileManager.defaultManager createDirectoryAtPath:self.output withIntermediateDirectories:YES attributes:nil error:NULL], @"Fixture could not create its output directory");
    self.history=[BAFixtureHistoryService new];self.history.fixtureReport=BAFixtureReport(@"ready");self.metrics=[BAFixtureMetricService new];self.metrics.fixtureSnapshot=BAFixtureSnapshot(NO);
    self.cards=BAAnalyticsCreateBuiltInCards();self.defaults=[[NSUserDefaults alloc] initWithSuiteName:@"com.torrekie.Battman.AnalyticsV3Fixture.layout"];
    [self.defaults removePersistentDomainForName:@"com.torrekie.Battman.AnalyticsV3Fixture.layout"];
    self.host=[[AnalyticsViewController alloc] initWithCards:self.cards metricService:self.metrics historyService:self.history userDefaults:self.defaults];
    self.host.navigationItem.prompt=@"Synthetic data · UI validation";
    self.navigation=[[UINavigationController alloc] initWithRootViewController:self.host];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=self.navigation;[self.window makeKeyAndVisible];
    // A run-loop timer permits the bounded nested waits below to receive
    // asynchronous history completions dispatched to the main queue.
    [self performSelector:@selector(runChecks) withObject:nil afterDelay:1]; return YES;
}
- (void)saveView:(UIView *)view name:(NSString *)name {
    [view setNeedsLayout]; AwaitPreparedCanvases(view);
    if ([NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_PERFORMANCE_ONLY"] isEqual:@"1"] && ![name hasPrefix:@"performance-"]) return;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size,NO,1);[view.layer renderInContext:UIGraphicsGetCurrentContext()];UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    Require(image!=nil,[NSString stringWithFormat:@"Missing rendered image %@",name]);
    Require([UIImagePNGRepresentation(image) writeToFile:[self.output stringByAppendingPathComponent:name] atomically:YES],@"Screenshot write failed");
}
- (void)renderCardsAtWidth:(CGFloat)width scenario:(NSString *)scenario allSizes:(BOOL)allSizes {
    self.history.fixtureReport=BAFixtureReport(scenario);[self.history publishFixture];
    BAAnalyticsMetricSnapshot *snapshot=BAFixtureSnapshot([scenario isEqualToString:@"unavailable"]);
    for(BAAnalyticsCanvasCard *card in self.cards) {
        card.historyService=self.history;
        NSArray *sizes=allSizes?BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes):@[@(card.defaultAnalyticsCardSize)];
        for(NSNumber *value in sizes) @autoreleasepool {
            BAAnalyticsCardSize size=value.integerValue;CGSize span=BAAnalyticsCardGridSpan(size);CGFloat unit=floor((width-44)/2);
            CGSize bounds=CGSizeMake(unit*span.width+12*(span.width-1),unit*span.height+12*(span.height-1));
            BAAnalyticsCardCell *cell=[[BAAnalyticsCardCell alloc] initWithFrame:(CGRect){CGPointZero,bounds}];
            [cell configureWithCard:card size:size editing:NO];[cell setAnalyticsCardDisplayed:YES];[cell applyMetricSnapshot:snapshot];
            [self.window addSubview:cell];[cell layoutIfNeeded];
            BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView;[canvas layoutIfNeeded];
            NSString *name=[NSString stringWithFormat:@"%@-%ld-%.0f-%@-%@%@.png",card.familyIdentifier,(long)size,width,[scenario stringByAppendingFormat:@"-%@",FixtureLanguage],ForcedStyle==UIUserInterfaceStyleDark?@"dark-fallback":@"light",ForcedCategory?@"-large":@""];
            [self saveView:cell name:name];
            Require(!CGRectIsEmpty(canvas.bounds),@"Zero-sized canvas");
            for(BAAnalyticsCanvasHitRegion *hit in canvas.hitRegions) {
                Require(isfinite(hit.rect.origin.x)&&isfinite(hit.rect.origin.y),@"Non-finite hit region");
                Require(hit.selection.familyIdentifier.length>0&&hit.accessibilityLabel.length>0,@"Unlabelled selection");
            }
            for(UIAccessibilityElement *element in canvas.accessibilityElements) {
                CGRect target=element.accessibilityFrameInContainerSpace;
                Require(target.size.width>=44&&target.size.height>=44,@"Accessibility target smaller than 44 points");
                Require(CGRectContainsRect(canvas.bounds,target),@"Accessibility target outside canvas");
            }
            if(canvas.hitRegions.count && card.supportsDetails) {
                BAAnalyticsDetailSelection *selection=canvas.hitRegions.firstObject.selection;
                UIAccessibilityElement *element=canvas.accessibilityElements[1];
                [canvas requestDetailForSelection:selection];Require(canvas.selectedDetail==selection,@"Selection did not retain exact context");
                [card analyticsCardContentView:canvas didChangeEditing:YES];[canvas requestDetailForSelection:nil];Require(canvas.selectedDetail==nil,@"Editing retained an active detail");
                Require(![element accessibilityActivate],@"Editing accepted the existing graph accessibility action");
                [card analyticsCardContentView:canvas didChangeEditing:NO];
            }
            [self.manifest addObject:@{ @"image":name,@"family":card.familyIdentifier,@"size":value,@"width":@(width),@"hitRegions":@(canvas.hitRegions.count),@"language":FixtureLanguage,@"accessibility":canvas.accessibilityLabel?:@"" }];
            [cell setAnalyticsCardDisplayed:NO];[cell removeFromSuperview];
        }
    }
}
- (void)testRegistrationAndMigration {
    BTPluginRegistry *registry=[BTPluginRegistry new];NSError *error=nil;
    NSString *point=BAAnalyticsCardExtensionPointIdentifier;
    Require([registry registerExtensionPointIdentifier:point interfaceVersion:BAAnalyticsCardExtensionPointVersion requiredProtocol:@protocol(BAAnalyticsCard) error:&error],error.description);
    Require(BTRegisterEmbeddedPluginDescriptor(BAAnalyticsBuiltInPluginDescriptor(),registry,[NSSet setWithObject:point],&error),error.description);
    Require([registry extensionObjectsForExtensionPointIdentifier:point].count==10,@"Registry did not publish all ten cards");
    [self.defaults setObject:@[@{@"id":@"battery.summary",@"size":@0},@{@"id":@"charge.history",@"size":@3}] forKey:BAAnalyticsLegacyCardLayoutDefaultsKey];
    NSArray *records=[BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:self.defaults];
    Require(records.count==2,@"Legacy migration lost records");
    Require([((BAAnalyticsCardLayoutRecord *)records[0]).cardIdentifier hasSuffix:@".live"],@"Legacy battery record not migrated");
    [self.defaults removeObjectForKey:BAAnalyticsLegacyCardLayoutDefaultsKey];
}
- (void)testHost {
    self.history.fixtureReport=BAFixtureReport(@"ready");[self.history publishFixture];self.metrics.fixtureSnapshot=BAFixtureSnapshot(NO);[self.metrics refreshNow];
    [self.host.view layoutIfNeeded];UICollectionView *collection=[self.host valueForKey:@"collectionView"];
    Require([collection numberOfItemsInSection:0]==10,@"Host did not display all ten cards");
    [self saveView:self.window name:@"host-top.png"];
    BAAnalyticsCardCell *cell=(id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    Require(cell!=nil,@"No first visible card");BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView;
    [canvas layoutIfNeeded];[self saveView:canvas name:@"host-first-canvas.png"];
    Require(canvas.hitRegions.count>0,@"Visible graph has no readable marks");
    Require(!canvas.detailEnabled && ![canvas accessibilityActivate],@"Self-contained live card unexpectedly navigates");
    cell=(id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];canvas=(id)cell.analyticsCardContentView;
    [canvas layoutIfNeeded]; Require(canvas.detailEnabled,@"Capacity drill-down is missing");
    BAAnalyticsCanvasHitRegion *region=canvas.hitRegions.firstObject;
    BAFixtureTouch *touch=[BAFixtureTouch new];touch.point=CGPointMake(CGRectGetMidX(region.rect),CGRectGetMidY(region.rect));
    Require([canvas beginTrackingWithTouch:(UITouch *)(id)touch withEvent:nil],@"Canvas did not accept touch tracking");
    [canvas endTrackingWithTouch:(UITouch *)(id)touch withEvent:nil];
    // A real collection touch can also deliver didSelect after the canvas's
    // own tracking action. Both routes must share one navigation transition.
    [collection.delegate collectionView:collection didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
    Require(self.navigation.viewControllers.count==2,@"Canvas selection did not navigate exactly once");DrainUI();
    UIViewController *detail=self.navigation.topViewController;[detail.view layoutIfNeeded];Require([detail isKindOfClass:UITableViewController.class],@"Shared evidence controller missing");
    Require(((UITableViewController *)detail).tableView.numberOfSections>0,@"Empty evidence detail");
    [self saveView:self.window name:@"detail-selected.png"];
    NSArray *sections=[detail valueForKey:@"sections"];
    BOOL disclosure=NO;
    for(NSUInteger section=0;section<sections.count;section++) {
        NSArray *rows=sections[section][@"rows"];
        for(NSUInteger row=0;row<rows.count;row++) if([rows[row][@"sources"] boolValue]) {
            UITableViewController *table=(id)detail;
            [table.tableView.delegate tableView:table.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
            disclosure=[[detail valueForKey:@"showsSourceDetails"] boolValue];break;
        }
        if(disclosure)break;
    }
    Require(disclosure,@"Source disclosure did not open");
    Require([detail valueForKey:@"snapshot"]==self.metrics.fixtureSnapshot,@"Detail did not freeze its acquisition snapshot");
    [self.navigation popViewControllerAnimated:NO];DrainUI();[self.host.view layoutIfNeeded];Require(self.navigation.viewControllers.count==1,@"Navigation pop failed");
    region=canvas.hitRegions.firstObject;
    UIAccessibilityElement *graphElement=canvas.accessibilityElements[1];
    Require([graphElement accessibilityActivate],@"Graph accessibility action failed");
    Require(canvas.selectedDetail==region.selection&&self.navigation.viewControllers.count==2,@"Accessibility did not open the same selected evidence");
    DrainUI();[self.navigation popViewControllerAnimated:NO];DrainUI();
    [self.host setEditing:YES animated:NO];[collection layoutIfNeeded];
    cell=(id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];canvas=(id)cell.analyticsCardContentView;
    Require(![canvas beginTrackingWithTouch:(UITouch *)(id)touch withEvent:nil],@"Editing accepted touch tracking");
    [canvas endTrackingWithTouch:(UITouch *)(id)touch withEvent:nil];Require(self.navigation.viewControllers.count==1,@"Detail opened during editing");
    Require(![canvas accessibilityActivate],@"Editing accepted an accessibility detail action");
    [graphElement accessibilityActivate];Require(self.navigation.viewControllers.count==1,@"A detached accessibility element opened detail while the host was editing");
    NSArray *states=[self.host valueForKey:@"cardStates"];NSInteger oldSize=[[states[0] valueForKey:@"size"] integerValue];
    [cell.resizeButton sendActionsForControlEvents:UIControlEventTouchUpInside];[collection layoutIfNeeded];
    Require([[states[0] valueForKey:@"size"] integerValue]!=oldSize,@"Resize did not change supported size");
    cell=(id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
    [cell.removeButton sendActionsForControlEvents:UIControlEventTouchUpInside];[collection layoutIfNeeded];DrainUI();Require([collection numberOfItemsInSection:0]==9,@"Remove did not update layout");
    [self.host addCard:self.cards[0]];[collection layoutIfNeeded];DrainUI();Require([collection numberOfItemsInSection:0]==10,@"Add did not restore card");
    id movedState=states[0];
    [collection.dataSource collectionView:collection moveItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0] toIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
    [collection reloadData];[collection layoutIfNeeded];
    Require(states[1]==movedState,@"Reorder did not retain card state");
    [self saveView:self.window name:@"host-edit.png"];
    [self.host setEditing:NO animated:NO];
    // Scroll each card into view: production reuse, visible subscriptions, and grid bounds.
    for(NSUInteger i=0;i<10;i++) {
        NSIndexPath *index=[NSIndexPath indexPathForItem:i inSection:0];[collection scrollToItemAtIndexPath:index atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];[collection layoutIfNeeded];
        UICollectionViewLayoutAttributes *a=[collection.collectionViewLayout layoutAttributesForItemAtIndexPath:index];
        Require(CGRectGetMinX(a.frame)>=0&&CGRectGetMaxX(a.frame)<=collection.bounds.size.width,@"Card outside grid");
        if(i==3||i==6||i==9)[self saveView:self.window name:[NSString stringWithFormat:@"host-scroll-%lu.png",(unsigned long)i]];
    }
    [self.host viewWillDisappear:NO];Require(self.history.subscriberCount==0&&self.metrics.subscriberCount==0,@"Offscreen host retained subscriptions");
    [self.host viewDidAppear:NO];[collection layoutIfNeeded];
    Require([BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:self.defaults].count==10,@"Edited layout not persisted");
    [collection setContentOffset:CGPointZero animated:NO];
}
- (void)testFamilyDetails {
    NSUInteger detailCount = 0;
    for (BAAnalyticsCanvasCard *card in self.cards) @autoreleasepool {
        BAAnalyticsCardCell *cell=[[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,346)];
        card.historyService=self.history;
        [cell configureWithCard:card size:card.defaultAnalyticsCardSize editing:NO];[cell setAnalyticsCardDisplayed:YES];
        [cell applyMetricSnapshot:self.metrics.fixtureSnapshot];[self.window addSubview:cell];[cell layoutIfNeeded];
        BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView; AwaitPreparedCanvases(canvas);
        BAAnalyticsDetailSelection *selection=canvas.hitRegions.firstObject.selection;
        [cell removeFromSuperview];
        UIViewController *detail=[card detailViewControllerForSelection:selection size:card.defaultAnalyticsCardSize];
        if (!card.supportsDetails) {
            Require(detail==nil && !canvas.detailEnabled,@"Unexpected universal detail controller");
            for (UIAccessibilityElement *element in canvas.accessibilityElements) Require(!(element.accessibilityTraits & UIAccessibilityTraitButton),@"Read-only mark announced as button");
            [cell setAnalyticsCardDisplayed:NO]; continue;
        }
        detailCount++;
        Require(selection!=nil,@"Detail card was not rendered before selection");
        [self.navigation pushViewController:detail animated:NO];DrainUI();[detail.view layoutIfNeeded];
        Require([detail isKindOfClass:BAAnalyticsDetailViewController.class]&&((UITableViewController *)detail).tableView.numberOfSections>0,@"Empty family detail");
        Require([detail valueForKey:@"selection"]==selection&&[detail valueForKey:@"report"]==canvas.latestReport&&[detail valueForKey:@"snapshot"]==canvas.latestSnapshot,@"Family detail changed its selected evidence");
        Require([detail valueForKey:@"visualization"]!=nil,@"Detail is missing its card-specific graphic");
        [self saveView:self.window name:[NSString stringWithFormat:@"detail-%@-%@.png",card.familyIdentifier,FixtureLanguage]];
        [self.navigation popViewControllerAnimated:NO];DrainUI();[cell setAnalyticsCardDisplayed:NO];
    }
    Require(detailCount==7,@"Optional card detail scope changed unexpectedly");
}
- (void)testCapacityCurrentDetail {
    BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCapacityCanvasCard();
    UIView *canvas = [card makeAnalyticsCardContentView];
    NSDate *now = [NSDate date];
    BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:17 timestamp:now
        values:@{BAAnalyticsMetricFullChargeCapacityMilliampHours:@5591, BAAnalyticsMetricDesignCapacityMilliampHours:@7596} histories:nil];
    [card analyticsCardContentView:canvas didReceiveMetricSnapshot:snapshot];
    NSArray *selections = @[NSNull.null,
        [BAAnalyticsDetailSelection selectionForFamily:BAAnalyticsFamilyCapacity kind:@"overview" context:@{@"source":@"metricSnapshot"}],
        [BAAnalyticsDetailSelection selectionForFamily:BAAnalyticsFamilyCapacity kind:@"capacity-ratio" context:@{@"source":@"metricSnapshot"}]];
    for (id candidate in selections) {
        BAAnalyticsDetailSelection *selection = candidate == NSNull.null ? nil : candidate;
        BAAnalyticsDetailViewController *detail = (id)[card detailViewControllerForSelection:selection size:BAAnalyticsCardSize1x1];
        NSArray *rows = [detail summaryRows];
        Require(CapacitySummaryNumber(rows,0).doubleValue == 5591 && CapacitySummaryNumber(rows,1).doubleValue == 7596 &&
            fabs(CapacitySummaryNumber(rows,2).doubleValue - 73.6) < .01,@"Capacity overview lost the live pair without historical records");
        Require(detail.snapshot == snapshot && [detail.selection.context[@"source"] isEqual:@"metricSnapshot"] &&
            [detail.selection.context[@"observationTimestamp"] doubleValue] == now.timeIntervalSince1970,@"Capacity live fallback lost its frozen source or acquisition time");
        if (!selection) {
            [self.navigation pushViewController:detail animated:NO]; DrainUI(); [detail.view layoutIfNeeded];
            [self saveView:self.window name:@"detail-capacity-live-no-history-en.png"];
            [self.navigation popViewControllerAnimated:NO]; DrainUI();
        }
    }
    // This historical point intentionally lacks a validated design capacity.
    // The live denominator must not turn it into an invented historical ratio.
    NSDate *pointTime = [now dateByAddingTimeInterval:-1200];
    NSString *metric = BAAnalyticsHistoryFullChargeCapacityMilliampHours;
    BAAnalyticsFieldMetadata *field = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.capacity" sourceColumn:@"FCC"
        unit:@"mAh" decoderIdentifier:@"fixture.capacity" unitValidated:YES];
    BAAnalyticsObservation *point = [[BAAnalyticsObservation alloc] initWithIdentifier:@"capacity.no-design" timestamp:pointTime
        sourceTimestamp:pointTime.timeIntervalSince1970 timestampValidated:YES values:@{metric:@3100} fieldMetadata:@{metric:field}];
    BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:[now dateByAddingTimeInterval:-3600] endDate:now
        observations:@[point] intervals:@[] gaps:@[] coverageMetricIdentifiers:NSSet.set coveredDuration:0 missingDuration:3600 coverageSecondsByMetric:@{}];
    BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCapacity availability:BAAnalyticsReportAvailabilityPartial
        window:window payload:@{} limitations:@[]];
    BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:18 generatedAt:now sourceProfileIdentifier:@"fixture.capacity"
        fieldMetadata:@{metric:field} familyReports:@{BAAnalyticsFamilyCapacity:family} error:nil];
    [card setValue:report forKey:@"latestReport"];
    BAAnalyticsDetailSelection *historical = [BAAnalyticsDetailSelection selectionForFamily:BAAnalyticsFamilyCapacity kind:@"capacity-point"
        recordIdentifiers:@[point.identifier] metricIdentifiers:@[metric] startDate:pointTime endDate:pointTime context:@{}];
    BAAnalyticsDetailViewController *detail = (id)[card detailViewControllerForSelection:historical size:BAAnalyticsCardSize1x1];
    NSArray *rows = [detail summaryRows];
    Require(CapacitySummaryNumber(rows,0).doubleValue == 3100 && [rows[1][@"value"] isEqual:cond_localize("Unavailable")] &&
        [rows[2][@"value"] isEqual:cond_localize("Unavailable")],@"Historical capacity borrowed a design value from a live snapshot");
    Require(detail.selection == historical && detail.selectedObservations.firstObject == point,@"Historical capacity changed its selected record or time");
    BAAnalyticsMetricSnapshot *designOnly = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:19 timestamp:now
        values:@{BAAnalyticsMetricDesignCapacityMilliampHours:@7596} histories:nil];
    [card analyticsCardContentView:canvas didReceiveMetricSnapshot:designOnly];
    detail = (id)[card detailViewControllerForSelection:nil size:BAAnalyticsCardSize1x1]; rows = [detail summaryRows];
    Require(CapacitySummaryNumber(rows,0).doubleValue == 3100 && [rows[1][@"value"] isEqual:cond_localize("Unavailable")] &&
        [rows[2][@"value"] isEqual:cond_localize("Unavailable")],@"A design-only live snapshot was paired with historical FCC");
}
- (void)testRealHistoryPublication {
    // Exercise the actual asynchronous service through the production cell
    // lifecycle. The other rendering fixtures publish synchronously.
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"battman-analytics-missing-%@/fixture.PLSQL", NSUUID.UUID.UUIDString]];
    BAAnalyticsHistoryService *history = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:[NSURL fileURLWithPath:path]];
    BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCapacityCanvasCard(); card.historyService = history;
    BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,170,170)];
    [cell configureWithCard:card size:BAAnalyticsCardSize1x1 editing:NO];
    [self.window addSubview:cell]; [cell layoutIfNeeded];
    @try {
        [cell setAnalyticsCardDisplayed:YES];
        Require(history.subscriberCount == 1 && history.polling,@"Visible production canvas did not start real history acquisition");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!history.latestReport && deadline.timeIntervalSinceNow > 0) {
            NSTimeInterval remaining = deadline.timeIntervalSinceNow;
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:
                [NSDate dateWithTimeIntervalSinceNow:MIN(.02,MAX(0,remaining))]];
        }
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        BAAnalyticsFamilyReport *family = [history.latestReport reportForFamily:BAAnalyticsFamilyCapacity];
        Require(history.latestReport != nil && family.availability == BAAnalyticsReportAvailabilityUnavailable,
            @"Missing fixture database stayed waiting instead of publishing unavailable history within three seconds");
        Require(card.latestReport == history.latestReport && canvas.latestReport == history.latestReport,
            @"Real history report did not reach the visible card and canvas");
        if ([NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_PERFORMANCE_ONLY"] isEqual:@"1"]) {
            BAAnalyticsReport *cached = history.latestReport;
            [cell setAnalyticsCardDisplayed:NO]; [cell setAnalyticsCardDisplayed:YES];
            Require(history.latestReport == cached && card.latestReport == cached && ![[history valueForKey:@"acquisitionPending"] boolValue],
                @"Fresh history cache reentry started another acquisition");
            DrainUI(); Require(history.latestReport == cached, @"Fresh cached report was replaced on visible reentry");
            [history refreshNow]; [history handleMemoryPressure];
            WaitForFixture(^BOOL { return ![[history valueForKey:@"acquisitionPending"] boolValue]; }, 3,
                @"Memory-pressure cancellation did not drain the history acquisition");
            Require(history.latestReport == nil && history.polling,
                @"Cancelled history immediately rebuilt its memory-pressure cache or lost its timer");
        }
    } @finally {
        [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview]; [history setApplicationActive:NO];
    }
    Require(history.subscriberCount == 0 && !history.polling,@"Hidden production canvas retained real history acquisition");
}
- (void)testRealHostHistoryActivation {
    Require(UIApplication.sharedApplication.applicationState == UIApplicationStateActive,@"History host activation fixture requires an active application");
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"battman-analytics-host-missing-%@/fixture.PLSQL", NSUUID.UUID.UUIDString]];
    BAAnalyticsHistoryService *history = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:[NSURL fileURLWithPath:path]];
    BAFixtureMetricService *metrics = [BAFixtureMetricService new]; metrics.fixtureSnapshot = BAFixtureSnapshot(NO);
    NSString *suite = [@"com.torrekie.Battman.AnalyticsV3Fixture.activation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    AnalyticsViewController *host = [[AnalyticsViewController alloc] initWithCards:BAAnalyticsCreateBuiltInCards()
        metricService:metrics historyService:history userDefaults:defaults];
    Require(host.viewIfLoaded == nil,@"Activation fixture loaded Analytics before simulating the missed notification");
    // Model construction while backgrounded, then a BecomeActive notification
    // missed before the lazy view registered its notification observers.
    [history setApplicationActive:NO];
    NSArray<UIViewController *> *previousStack = [self.navigation.viewControllers copy];
    @try {
        [self.navigation setViewControllers:@[host] animated:NO]; DrainUI(); [host.view layoutIfNeeded];
        UICollectionView *collection = [host valueForKey:@"collectionView"];
        Require(host.view.window == self.window && collection.visibleCells.count > 0,@"Activation fixture did not display the real Analytics host");
        Require(history.subscriberCount > 0 && history.polling,@"First visible Analytics host did not reactivate history after a missed BecomeActive notification");
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!history.latestReport && deadline.timeIntervalSinceNow > 0) {
            NSTimeInterval remaining = deadline.timeIntervalSinceNow;
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:
                [NSDate dateWithTimeIntervalSinceNow:MIN(.02,MAX(0,remaining))]];
        }
        Require(history.latestReport != nil,@"Activated real Analytics host stayed waiting for history beyond three seconds");
        NSUInteger visibleCanvases = 0;
        for (BAAnalyticsCardCell *cell in collection.visibleCells) {
            BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
            if (![canvas isKindOfClass:BAAnalyticsCanvasView.class]) continue;
            visibleCanvases++;
            BAAnalyticsFamilyReport *family = [canvas.latestReport reportForFamily:canvas.familyIdentifier];
            Require(canvas.latestReport == history.latestReport && family.availability == BAAnalyticsReportAvailabilityUnavailable,
                @"Real host did not publish missing-database history to every visible canvas");
        }
        Require(visibleCanvases > 0,@"Activation fixture had no visible production canvases");
    } @finally {
        [self.navigation setViewControllers:previousStack animated:NO]; DrainUI();
        [history setApplicationActive:NO]; [defaults removePersistentDomainForName:suite];
    }
    Require(history.subscriberCount == 0 && !history.polling,@"Restored navigation retained the activation fixture's history subscriptions");
}
- (void)testEditingAccessories {
    self.history.fixtureReport=BAFixtureReport(@"ready"); [self.history publishFixture];
    for (BAAnalyticsCanvasCard *card in self.cards) {
        card.historyService=self.history;
        for (NSNumber *size in BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes)) @autoreleasepool {
            CGSize span=BAAnalyticsCardGridSpan(size.integerValue);CGFloat unit=138;
            BAAnalyticsCardCell *cell=[[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,unit*span.width+12*(span.width-1),unit*span.height+12*(span.height-1))];
            [cell configureWithCard:card size:size.integerValue editing:YES];[cell setAnalyticsCardDisplayed:YES];[cell applyMetricSnapshot:BAFixtureSnapshot(NO)];
            [self.window addSubview:cell];[cell layoutIfNeeded];
            UIView *content=cell.analyticsCardContentView; UIView *container=cell.resizeButton.superview;
            Require(!content.userInteractionEnabled&&content.accessibilityElementsHidden,@"Editing left embedded card interactions enabled");
            CGRect contentFrame=[content convertRect:content.bounds toView:container];
            Require(CGRectEqualToRect(contentFrame,container.bounds),@"Editing compressed the card's drawing surface");
            Require(content.superview!=container&&cell.removeButton.superview==container,@"Resize accessory is inside the canvas hierarchy");
            // A canvas may reorder its own views/layers after mounting. The
            // host's sibling accessory must retain visual and touch priority.
            content.layer.zPosition=1000;
            [content.superview bringSubviewToFront:content];
            CGPoint center=CGPointMake(CGRectGetMidX(cell.resizeButton.frame),CGRectGetMidY(cell.resizeButton.frame));
            Require([container hitTest:center withEvent:nil]==cell.resizeButton,@"Card content intercepts resize button");
            CGPoint cellCenter=[container convertPoint:center toView:cell];
            Require([cell hitTest:cellCenter withEvent:nil]==cell.resizeButton,@"Cell routes resize touch into the canvas");
            Require(cell.resizeButton.bounds.size.width>=44,@"Resize target smaller than 44 pt");
            [self saveView:cell name:[NSString stringWithFormat:@"editing-%@-%ld-%@.png",card.familyIdentifier,(long)size.integerValue,FixtureLanguage]];
            content.layer.zPosition=0;
            [cell setAnalyticsCardDisplayed:NO];[cell removeFromSuperview];
        }
    }
}
- (void)testBatteryStates {
    BAAnalyticsCanvasCard *card=self.cards.firstObject;
    NSArray *cases=@[@[@73,@NO,@NO],@[@20,@NO,@NO],@[@19,@NO,@NO],@[@73,@YES,@NO],@[@19,@YES,@YES],@[@73,@NO,@YES]];
    for (NSArray *state in cases) {
        BAAnalyticsMetricSnapshot *original=BAFixtureSnapshot(NO);
        NSMutableDictionary *values=[original.values mutableCopy];
        values[BAAnalyticsMetricStateOfChargePercent]=state[0];values[BAAnalyticsMetricLowPowerMode]=state[1];values[BAAnalyticsMetricChargingState]=@([state[2] boolValue] ? BAAnalyticsChargingStateCharging : BAAnalyticsChargingStateNotCharging);
        BAAnalyticsMetricSnapshot *snapshot=[[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:2 timestamp:original.timestamp values:values histories:original.histories];
        BAAnalyticsCardCell *cell=[[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,358,173)];
        [cell configureWithCard:card size:BAAnalyticsCardSize2x1 editing:NO];[cell applyMetricSnapshot:snapshot];[self.window addSubview:cell];[cell layoutIfNeeded];
        BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView;
        CGRect temperature=[[canvas valueForKey:@"temperatureRect"] CGRectValue];
        for (id track in [canvas valueForKey:@"tracks"]) { CGRect plot=[[track valueForKey:@"rect"] CGRectValue];Require(CGRectIsEmpty(plot)||!CGRectIntersectsRect(temperature,plot),@"Temperature label overlaps a graph"); }
        // Test-only comparison with the local iOS 12 UIKit implementation.
        Class systemBattery=NSClassFromString(@"_UIBatteryView");Require(systemBattery!=Nil,@"System battery reference unavailable");
        id reference=[[systemBattery alloc] initWithFrame:CGRectZero];
        ((void (*)(id,SEL,double))objc_msgSend)(reference,NSSelectorFromString(@"setChargePercent:"),[state[0] doubleValue]/100);
        ((void (*)(id,SEL,BOOL))objc_msgSend)(reference,NSSelectorFromString(@"setSaverModeActive:"),[state[1] boolValue]);
        ((void (*)(id,SEL,NSInteger))objc_msgSend)(reference,NSSelectorFromString(@"setChargingState:"),[state[2] boolValue]?1:0);
        ((void (*)(id,SEL,id))objc_msgSend)(reference,NSSelectorFromString(@"setFillColor:"),UIColor.compatLabelColor);
        UIColor *expected=((id (*)(id,SEL))objc_msgSend)(reference,NSSelectorFromString(@"_batteryFillColor"));
        UIColor *actual=BALiveBatteryFillColor(state[0],[state[1] boolValue],[state[2] boolValue]);
        CGFloat er=0,eg=0,eb=0,ar=0,ag=0,ab=0;
        [expected getRed:&er green:&eg blue:&eb alpha:NULL];[actual getRed:&ar green:&ag blue:&ab alpha:NULL];
        Require(fabs(er-ar)+fabs(eg-ag)+fabs(eb-ab)<.02,@"Battery color disagrees with system reference");
        [self saveView:cell name:[NSString stringWithFormat:@"battery-%@-%@-%@-%@.png",state[0],state[1],state[2],ForcedStyle==UIUserInterfaceStyleDark?@"dark":@"light"]];
        [cell removeFromSuperview];
    }
}
- (void)capturePerformanceCard:(BAAnalyticsCanvasCard *)card size:(BAAnalyticsCardSize)size name:(NSString *)name {
    CGSize span = BAAnalyticsCardGridSpan(size);
    CGSize bounds = CGSizeMake(167 * span.width + 12 * (span.width - 1), 167 * span.height + 12 * (span.height - 1));
    BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:(CGRect){CGPointZero,bounds}];
    [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
    [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; [self.window addSubview:cell];
    BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
    AwaitPreparedCanvases(cell);
    Require(canvas.hitRegions.count <= 256 && canvas.accessibilityElements.count <= 257, @"Resized dense canvas exceeded its screen/VoiceOver bounds");
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    [canvas setNeedsLayout]; [canvas setNeedsDisplay]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    self.performanceResults[[name stringByAppendingString:@"LayoutDrawSeconds"]] = @(NSProcessInfo.processInfo.systemUptime - started);
    [self saveView:cell name:name];
    [self.manifest addObject:@{@"image":name,@"family":card.familyIdentifier,@"size":@(size),@"width":@(bounds.width),
        @"hitRegions":@(canvas.hitRegions.count),@"language":FixtureLanguage}];
    [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
}
- (void)testDenseEventsPresentation {
    __block BAAnalyticsReport *report = nil;
    __block NSDictionary *reference = nil;
    __block NSString *generationError = nil;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            @try {
                BAAnalyticsReport *generated = PerformanceEventsReport(2000);
                NSDictionary *expected = PerformanceEventsReference([generated reportForFamily:BAAnalyticsFamilyEvents]);
                dispatch_async(dispatch_get_main_queue(), ^{ report = generated; reference = expected; });
            } @catch (NSException *exception) {
                NSString *reason = exception.reason;
                dispatch_async(dispatch_get_main_queue(), ^{ generationError = reason; });
            }
        }
    });
    WaitForFixture(^BOOL { return (report && reference) || generationError; }, 5, @"Dense event source and independent oracle did not finish");
    Require(report && reference, generationError ?: @"Dense event source construction failed");
    BAAnalyticsFamilyReport *family = [report reportForFamily:BAAnalyticsFamilyEvents];
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = report;
    BAAnalyticsCanvasCard *events = nil;
    for (BAAnalyticsCanvasCard *card in BAAnalyticsCreateProcessCanvasCards()) if ([card.familyIdentifier isEqual:BAAnalyticsFamilyEvents]) events = card;
    Require(events != nil, @"Event canvas factory was absent"); events.historyService = history;
    BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0, 0, 167, 346)];
    [cell configureWithCard:events size:BAAnalyticsCardSize1x2 editing:NO]; [cell setAnalyticsCardDisplayed:YES];
    [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; [self.window addSubview:cell];
    BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
    @try {
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        AwaitPreparedCanvases(cell);
        self.performanceResults[@"denseEventsFirstLayoutDrawSeconds"] = @(NSProcessInfo.processInfo.systemUptime - started);
        NSArray<BAAnalyticsStateTransition *> *valid = [canvas transitionsForFamily:family];
        NSSet *identifiers = [NSSet setWithArray:[valid valueForKey:@"identifier"]];
        Require([identifiers isEqual:[NSSet setWithArray:[reference[@"transitions"] valueForKey:@"identifier"]]] && valid.count > 128,
            @"Indexed event filtering changed the full verified transition population");
        Require([identifiers containsObject:@"performance.events.left-touch"] && [identifiers containsObject:@"performance.events.right-touch"] &&
            [identifiers containsObject:@"performance.events.point-clear"] && ![identifiers containsObject:@"performance.events.gap-overlap"] &&
            ![identifiers containsObject:@"performance.events.point-gap-start"] && ![identifiers containsObject:@"performance.events.point-gap-end"] &&
            ![identifiers containsObject:@"performance.events.point-zero-gap"], @"Event filtering changed strict spans or closed point-gap endpoints");
        NSUInteger transitionCursor = 0, index = 0;
        for (BAAnalyticsHistoryInterval *interval in BAProcessOrderedIntervals(family.window.intervals)) {
            Require([canvas stateForInterval:interval transitionCursor:&transitionCursor] == [reference[@"states"][index++] integerValue],
                @"Event sweep disagreed with full transition overlap, including nested interval ends");
        }
        NSTimeInterval known = [canvas knownStateDuration:family transitions:valid];
        Require(index == 2002 && family.window.observations.count == 2001 && fabs(known - [reference[@"knownSeconds"] doubleValue]) < 1e-6,
            @"Dense event presentation truncated source records or changed known-state union duration");
        Require(canvas.hitRegions.count > 0 && canvas.hitRegions.count <= 198 && canvas.accessibilityElements.count <= 199,
            @"Dense events exceeded their three bounded time tracks plus legend/coverage actions");
        BOOL positive = NO, negative = NO, zero = NO;
        for (BAAnalyticsObservation *observation in family.window.observations) {
            NSNumber *value = BAProcessValue(observation, BAAnalyticsHistoryCurrentMilliamps);
            Require(value != nil, @"Dense event current lost a validated original sample");
            double current = value.doubleValue;
            positive |= current > 0; negative |= current < 0; zero |= current == 0;
        }
        Require(positive && negative && zero, @"Dense event current did not exercise both signs and a real zero");
        started = NSProcessInfo.processInfo.systemUptime;
        [canvas setNeedsLayout]; [canvas setNeedsDisplay]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
        Require([canvas transitionsForFamily:family] == valid, @"Repeated event layout rebuilt immutable transition evidence");
        self.performanceResults[@"denseEventsRepeatedLayoutDrawSeconds"] = @(NSProcessInfo.processInfo.systemUptime - started);
        self.performanceResults[@"denseEventsSourceIntervals"] = @(index);
        self.performanceResults[@"denseEventsVerifiedTransitions"] = @(valid.count);
        self.performanceResults[@"denseEventsKnownSeconds"] = @(known);
        self.performanceResults[@"denseEventsHitRegions"] = @(canvas.hitRegions.count);
        [self saveView:cell name:@"performance-events-dense-1x2.png"];
        [self.manifest addObject:@{@"image":@"performance-events-dense-1x2.png", @"family":BAAnalyticsFamilyEvents,
            @"size":@(BAAnalyticsCardSize1x2), @"width":@167, @"hitRegions":@(canvas.hitRegions.count), @"language":FixtureLanguage}];
        [events analyticsCardDidReceiveMemoryWarning];
        Require([canvas valueForKey:@"preparedTransitions"] == nil && [canvas valueForKey:@"preparedIntervals"] == nil &&
            [canvas valueForKey:@"transitionRanges"] == nil, @"Memory pressure retained dense event preparation");
    } @finally {
        [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
    }
}
- (void)testStartupRefreshPresentationWithReport:(BAAnalyticsReport *)base {
    BAAnalyticsReport *reportA = [StartupRefreshReport(base, 201) reportByMarkingCached];
    BAAnalyticsReport *reportB = PerformanceGeneration(reportA, 202);
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = reportA;
    NSArray<BAAnalyticsCanvasCard *> *cards = @[(id)BAAnalyticsCreateCapacityCanvasCard(), (id)BAAnalyticsCreateCellsCanvasCard(),
        (id)BAAnalyticsCreateDwellCanvasCard(), (id)BAAnalyticsCreateCompareCanvasCard(), (id)BAAnalyticsCreateRhythmCanvasCard()];
    NSMutableArray<BAAnalyticsCardCell *> *cells = [NSMutableArray array];
    NSMutableDictionary *analyses = [NSMutableDictionary dictionary], *hitSignatures = [NSMutableDictionary dictionary], *geometries = [NSMutableDictionary dictionary];
    NSMutableArray<BAAnalyticsDetailViewController *> *frozenDetails = [NSMutableArray array];
    dispatch_queue_t queue = BAAnalyticsCanvasPreparationQueue(); BOOL queueSuspended = NO;
    @try {
        for (BAAnalyticsCanvasCard *card in cards) {
            card.historyService = history;
            BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0, 0, 346, 346)];
            [cells addObject:cell];
            [cell configureWithCard:card size:BAAnalyticsCardSize2x2 editing:NO]; [cell setAnalyticsCardDisplayed:YES];
            [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; [self.window addSubview:cell];
            BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView; AwaitPreparedCanvases(cell);
            Require(canvas.latestReport == reportA && canvas.hitRegions.count > 0, @"Cached report did not produce paired startup geometry and actions");
            hitSignatures[card.familyIdentifier] = CanvasHitSignature(canvas);
            if ([card isKindOfClass:BASStatisticalCard.class]) analyses[card.familyIdentifier] = ((BASStatisticalCard *)card).analysis;
            else geometries[card.familyIdentifier] = [canvas valueForKey:@"displayIndices"];
        }
        dispatch_suspend(queue); queueSuspended = YES;
        history.fixtureReport = reportB; [history publishFixture];
        DrainUI();
        for (NSUInteger i = 0; i < cards.count; i++) {
            BAAnalyticsCanvasCard *card = cards[i]; BAAnalyticsCanvasView *canvas = (id)cells[i].analyticsCardContentView;
            [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
            Require(card.latestReport == reportB && canvas.latestReport == reportA,
                @"Pending refresh replaced the displayed report before its geometry was ready");
            Require([CanvasHitSignature(canvas) isEqual:hitSignatures[card.familyIdentifier]],
                @"Pending refresh changed old geometry, raw selections or report sequences");
            if ([card isKindOfClass:BASStatisticalCard.class]) {
                BASStatisticalCard *statistical = (id)card;
                Require(statistical.analysis == analyses[card.familyIdentifier] && statistical.derivedReport == reportA &&
                    ((BASStatisticalView *)canvas).familyReport == [reportA reportForFamily:card.familyIdentifier],
                    @"Pending statistics mixed displayed analysis with incoming evidence");
            } else {
                Require([canvas valueForKey:@"displayedReport"] == reportA &&
                    [[canvas valueForKey:@"displayIndices"] isEqual:geometries[card.familyIdentifier]],
                    @"Pending live-history preparation discarded its displayed geometry or field metadata");
            }
            BAAnalyticsDetailSelection *selection = ((BAAnalyticsCanvasHitRegion *)canvas.hitRegions.firstObject).selection;
            BAAnalyticsDetailViewController *detail = (id)[card detailViewControllerForSelection:selection size:BAAnalyticsCardSize2x2];
            Require(detail != nil && detail.report == reportA && [detail.selection.context[@"reportSequence"] unsignedLongLongValue] == reportA.sequenceNumber,
                @"Old graphical action opened a detail against the incoming report");
            if ([card isKindOfClass:BASStatisticalCard.class]) Require([detail valueForKey:@"frozenAnalysis"] == analyses[card.familyIdentifier],
                @"Old statistical action froze the wrong analysis generation");
            [frozenDetails addObject:detail];
        }
        dispatch_resume(queue); queueSuspended = NO;
        WaitForFixture(^BOOL {
            for (BAAnalyticsCardCell *cell in cells) {
                BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
                if (canvas.latestReport != reportB || canvas.isPreparingHistory) return NO;
            }
            return YES;
        }, 5, @"Prepared refresh did not replace every displayed card generation");
        for (NSUInteger i = 0; i < cards.count; i++) {
            BAAnalyticsCanvasCard *card = cards[i]; BAAnalyticsCanvasView *canvas = (id)cells[i].analyticsCardContentView;
            [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
            for (BAAnalyticsCanvasHitRegion *hit in canvas.hitRegions) Require([hit.selection.context[@"reportSequence"] unsignedLongLongValue] == reportB.sequenceNumber,
                @"Ready refresh retained old graphical action sequences");
            Require(frozenDetails[i].report == reportA, @"Refresh mutated an already frozen detail report");
            if ([card isKindOfClass:BASStatisticalCard.class]) {
                BASStatisticalCard *statistical = (id)card;
                Require(statistical.derivedReport == reportB && statistical.analysis != analyses[card.familyIdentifier],
                    @"Ready statistics did not publish a complete new analysis/report pair");
                Require([frozenDetails[i] valueForKey:@"frozenAnalysis"] == analyses[card.familyIdentifier],
                    @"Refresh mutated an already frozen detail analysis");
            }
        }
        BASStatisticalCard *compare = (id)cards[3]; BAAnalyticsCanvasView *compareCanvas = (id)cells[3].analyticsCardContentView;
        NSDictionary *comparison = compare.analysis;
        Require([comparison[@"samples"] count] == 80 && [comparison[@"n"] unsignedIntegerValue] == 80,
            @"Dense comparison presentation sampled the independent-session statistics");
        Require(fabs([comparison[@"minimum"] doubleValue] - .375) < 1e-6 && fabs([comparison[@"maximum"] doubleValue] - 22.5) < 1e-6,
            @"Dense comparison lost raw duration extrema");
        NSDictionary *temperatureDrawing = comparison[@"temperatureDrawing"];
        Require([temperatureDrawing[@"count"] unsignedIntegerValue] == 80 &&
            fabs([temperatureDrawing[@"minimum"] doubleValue] - 24) < 1e-6 && fabs([temperatureDrawing[@"maximum"] doubleValue] - 58) < 1e-6,
            @"Dense comparison used representative points to truncate temperature counts or scale extrema");
        Require([[comparison[@"durationDrawingSamples"] valueForKey:@"identifier"] containsObject:@"startup.session.53"] &&
            [[comparison[@"durationDrawingSamples"] valueForKey:@"identifier"] containsObject:@"startup.session.27"] &&
            [[temperatureDrawing[@"samples"] valueForKey:@"identifier"] containsObject:@"startup.session.17"] &&
            [[temperatureDrawing[@"samples"] valueForKey:@"identifier"] containsObject:@"startup.session.41"],
            @"Dense comparison drawing lost an independent duration or temperature extreme");
        Require([comparison[@"durationDrawingSamples"] count] <= 30 && [temperatureDrawing[@"samples"] count] <= 30 &&
            compareCanvas.hitRegions.count <= 64 && compareCanvas.accessibilityElements.count <= 65,
            @"Dense comparison exceeded its drawing, touch or VoiceOver budget");
        self.performanceResults[@"comparisonRawSessions"] = @80;
        self.performanceResults[@"comparisonHitRegions"] = @(compareCanvas.hitRegions.count);
        self.performanceResults[@"comparisonAXElements"] = @(compareCanvas.accessibilityElements.count);
        [self saveView:cells[3] name:@"performance-comparison-dense-2x2.png"];
        ForcedCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
        [compareCanvas setNeedsLayout]; [compareCanvas setNeedsDisplay]; [compareCanvas layoutIfNeeded]; [compareCanvas.layer displayIfNeeded];
        Require(((BASStatisticalView *)compareCanvas).largeTextRows.count <= 64,
            @"Dense comparison created an unbounded accessibility-size button list");
        [self saveView:cells[3] name:@"performance-comparison-large-type-2x2.png"];
        ForcedCategory = nil; [compareCanvas setNeedsLayout]; [compareCanvas setNeedsDisplay];
        [compareCanvas layoutIfNeeded]; [compareCanvas.layer displayIfNeeded];

        // Nil and memory pressure cancel queued generations. Drain their
        // completions before checking that no stale cache can reappear.
        dispatch_suspend(queue); queueSuspended = YES;
        history.fixtureReport = PerformanceGeneration(reportB, 203); [history publishFixture];
        history.fixtureReport = nil; [history publishFixture];
        for (NSUInteger i = 0; i < cards.count; i++) {
            BAAnalyticsCanvasView *canvas = (id)cells[i].analyticsCardContentView;
            Require(cards[i].latestReport == nil && canvas.latestReport == nil,
                @"Explicit nil evidence did not clear the displayed generation");
            [cards[i] analyticsCardDidReceiveMemoryWarning];
            Require(cards[i].latestReport == nil && canvas.latestReport == nil,
                @"Memory pressure retained the displayed evidence report");
            if ([cards[i] isKindOfClass:BASStatisticalCard.class]) Require(((BASStatisticalCard *)cards[i]).analysis == nil &&
                ((BASStatisticalView *)canvas).analysis == nil, @"Memory pressure retained statistical analysis");
            else Require([canvas valueForKey:@"preparedHistory"] == nil, @"Memory pressure retained live-history preparation");
        }
        dispatch_resume(queue); queueSuspended = NO;
        __block BOOL drained = NO;
        dispatch_async(queue, ^{ dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; }); });
        WaitForFixture(^BOOL { return drained; }, 5, @"Cancelled refresh preparations did not drain");
        for (NSUInteger i = 0; i < cards.count; i++) {
            BAAnalyticsCanvasView *canvas = (id)cells[i].analyticsCardContentView;
            Require(cards[i].latestReport == nil && canvas.latestReport == nil && !canvas.isPreparingHistory,
                @"Cancelled refresh resurrected a displayed report or remained permanently pending");
        }
        self.performanceResults[@"startupRefreshFamilies"] = @(cards.count);
        self.performanceResults[@"startupRefreshPairingAndCancellation"] = @YES;
    } @finally {
        if (queueSuspended) dispatch_resume(queue);
        ForcedCategory = nil;
        for (BAAnalyticsCardCell *cell in cells) { [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview]; }
        for (BAAnalyticsCanvasCard *card in cards) [card analyticsCardDidReceiveMemoryWarning];
    }

    // A cached instantaneous reading retains acquisition time. It may be
    // replaced by a fresh sample, but cannot impersonate a current reading.
    NSDate *oldTime = [NSDate dateWithTimeIntervalSinceNow:-600];
    BAAnalyticsMetricSnapshot *cachedSnapshot = [[[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:301 timestamp:oldTime
        values:BAFixtureSnapshot(NO).values histories:nil] snapshotByMarkingCached];
    BAAnalyticsCanvasCard *live = (id)BAAnalyticsCreateLiveCanvasCards().firstObject; live.historyService = history;
    BAAnalyticsCardCell *liveCell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,167)];
    @try {
        [liveCell configureWithCard:live size:BAAnalyticsCardSize2x1 editing:NO]; [liveCell setAnalyticsCardDisplayed:YES];
        [self.window addSubview:liveCell]; [liveCell applyMetricSnapshot:cachedSnapshot]; [liveCell layoutIfNeeded];
        BAAnalyticsCanvasView *canvas = (id)liveCell.analyticsCardContentView;
        Require(canvas.latestSnapshot.isCached && [canvas.latestSnapshot.timestamp isEqualToDate:oldTime] &&
            [canvas.accessibilityLabel containsString:BALiveAge(oldTime)], @"Cached metric was relabeled as a newly acquired reading");
        [self saveView:liveCell name:@"performance-current-battery-cached-2x1.png"];
        BAAnalyticsMetricSnapshot *fresh = BAFixtureSnapshot(NO); [liveCell applyMetricSnapshot:fresh]; [liveCell layoutIfNeeded];
        Require(canvas.latestSnapshot == fresh && !canvas.latestSnapshot.isCached && [canvas.latestSnapshot.timestamp compare:oldTime] == NSOrderedDescending,
            @"Fresh acquisition did not replace the cached metric timestamp");
        self.performanceResults[@"cachedMetricPreservesAcquisitionTime"] = @YES;
    } @finally {
        [liveCell setAnalyticsCardDisplayed:NO]; [liveCell removeFromSuperview]; [live analyticsCardDidReceiveMemoryWarning];
    }
}

- (void)testPerformanceHistory {
    const NSUInteger count = 8000;
    self.performanceResults = [NSMutableDictionary dictionaryWithObject:@(count) forKey:@"recordsPerDenseFamily"];
    __block BAAnalyticsReport *report = nil;
    __block NSString *generationError = nil;
    NSTimeInterval began = NSProcessInfo.processInfo.systemUptime;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            @try {
                BAAnalyticsReport *generated = PerformanceReport(count);
                NSTimeInterval encodeStart = NSProcessInfo.processInfo.systemUptime;
                NSData *cache = BAAnalyticsEncodeCachedReport(generated, NULL);
                NSTimeInterval encodeSeconds = NSProcessInfo.processInfo.systemUptime - encodeStart;
                Require(cache != nil, @"Dense completed history could not be cached within the graph budget");
                NSTimeInterval decodeStart = NSProcessInfo.processInfo.systemUptime;
                BAAnalyticsReport *restored = BAAnalyticsDecodeCachedReport(cache, generated.generatedAt, NULL);
                NSTimeInterval decodeSeconds = NSProcessInfo.processInfo.systemUptime - decodeStart;
                Require(restored.isCached && [restored.generatedAt isEqualToDate:generated.generatedAt] &&
                    [restored reportForFamily:BAAnalyticsFamilyCapacity].window.observations.count == count &&
                    [restored reportForFamily:BAAnalyticsFamilyCells].window.observations.count == count,
                    @"Dense cache changed timestamps or removed original evidence");
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.performanceResults[@"denseCacheBytes"] = @(cache.length);
                    self.performanceResults[@"denseCacheEncodeSeconds"] = @(encodeSeconds);
                    self.performanceResults[@"denseCacheDecodeSeconds"] = @(decodeSeconds);
                    report = generated;
                });
            } @catch (NSException *exception) {
                NSString *reason = exception.reason;
                dispatch_async(dispatch_get_main_queue(), ^{ generationError = reason; });
            }
        }
    });
    WaitForFixture(^BOOL { return report != nil || generationError != nil; }, 20, @"Synthetic report generation and cache preparation exceeded the bounded worker budget");
    Require(report != nil, generationError ?: @"Synthetic report generation failed");
    self.performanceResults[@"workerGenerationSeconds"] = @(NSProcessInfo.processInfo.systemUptime - began);
    BAAnalyticsFamilyReport *capacityFamily = [report reportForFamily:BAAnalyticsFamilyCapacity];
    BAAnalyticsFamilyReport *cellsFamily = [report reportForFamily:BAAnalyticsFamilyCells];
    Require(capacityFamily.window.observations.count == count && cellsFamily.window.observations.count == count,
        @"Dense immutable fixture lost source observations");
    Require(capacityFamily.window.gaps.count == (count - 1) / 257 && cellsFamily.window.gaps.count == (count - 1) / 257,
        @"Dense fixture did not retain explicit missing sampled pairs");
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = report;
    NSArray<BAAnalyticsCanvasCard *> *cards = @[(id)BAAnalyticsCreateCapacityCanvasCard(), (id)BAAnalyticsCreateCellsCanvasCard(),
        (id)BAAnalyticsCreateDwellCanvasCard(), (id)BAAnalyticsCreateCompareCanvasCard(), (id)BAAnalyticsCreateRhythmCanvasCard()];
    NSMutableArray<BAAnalyticsCardCell *> *mounted = [NSMutableArray array];
    for (BAAnalyticsCanvasCard *card in cards) {
        card.historyService = history;
        BAAnalyticsCardSize size = [card.familyIdentifier isEqual:BAAnalyticsFamilyCapacity] ? BAAnalyticsCardSize2x1 : BAAnalyticsCardSize2x2;
        BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,size == BAAnalyticsCardSize2x1 ? 167 : 346)];
        NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
        [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; [self.window addSubview:cell]; [cell layoutIfNeeded];
        self.performanceResults[[card.familyIdentifier stringByAppendingString:@"MountSeconds"]] = @(NSProcessInfo.processInfo.systemUptime - started);
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        if ([card isKindOfClass:BASStatisticalCard.class] && canvas.isPreparingHistory)
            Require([card detailViewControllerForSelection:nil size:size] == nil, @"Pending statistics froze an empty detail result");
        AwaitPreparedCanvases(canvas);
        Require(!canvas.isPreparingHistory && canvas.hitRegions.count > 0, @"Dense canvas did not produce prepared graphical evidence");
        Require(canvas.hitRegions.count <= 256 && canvas.accessibilityElements.count <= 257, @"Dense source records produced unbounded screen/VoiceOver marks");
        self.performanceResults[[card.familyIdentifier stringByAppendingString:@"HitRegions"]] = @(canvas.hitRegions.count);
        self.performanceResults[[card.familyIdentifier stringByAppendingString:@"AXElements"]] = @(canvas.accessibilityElements.count);
        for (UIAccessibilityElement *element in canvas.accessibilityElements)
            Require(CGRectContainsRect(canvas.bounds,element.accessibilityFrameInContainerSpace), @"Dense accessibility mark left the canvas");
        if ([card.familyIdentifier isEqual:BAAnalyticsFamilyCapacity]) {
            NSArray<BAAnalyticsObservation *> *raw = [canvas valueForKey:@"capacityObservations"];
            NSArray<NSNumber *> *indices = [canvas valueForKey:@"displayIndices"];
            Require(raw.count == count && indices.count < count / 4, @"Capacity display envelope truncated raw evidence or did not reduce dense drawing");
            self.performanceResults[@"capacityDisplayPoints"] = @(indices.count);
            Require([indices containsObject:@1777] && [indices containsObject:@5333], @"Capacity display envelope lost isolated minimum/maximum");
            Require([[canvas valueForKey:@"boundaryIndices"] count] > 0 && [[canvas valueForKey:@"displayGaps"] count] > 0,
                @"Capacity display lost configuration boundaries or missing spans");
            [self saveView:cell name:@"performance-capacity-2x1.png"];
            [self.manifest addObject:@{@"image":@"performance-capacity-2x1.png",@"family":card.familyIdentifier,@"size":@(size),@"width":@346,@"hitRegions":@(canvas.hitRegions.count),@"language":@"en"}];
        } else if ([card.familyIdentifier isEqual:BAAnalyticsFamilyCells]) {
            NSDictionary *rawChannels = [[canvas valueForKey:@"preparedHistory"] valueForKey:@"pointsByMetric"];
            for (NSString *metric in @[BAAnalyticsHistoryCellVoltage0Millivolts,BAAnalyticsHistoryCellVoltage1Millivolts,BAAnalyticsHistoryCellVoltage2Millivolts])
                Require([rawChannels[metric] count] == count, @"Cell preparation truncated a complete channel's original records");
            NSMutableSet *shown = [NSMutableSet set];
            NSDictionary *displayChannels = [canvas valueForKey:@"displayIndices"];
            NSMutableDictionary *displayCounts = [NSMutableDictionary dictionary];
            for (NSString *metric in displayChannels) {
                Require([displayChannels[metric] count] < count / 4, @"Cell display envelope did not reduce a dense channel");
                displayCounts[metric] = @([displayChannels[metric] count]);
            }
            self.performanceResults[@"cellsDisplayPointsPerMetric"] = displayCounts;
            for (NSString *metric in displayChannels) for (NSNumber *index in displayChannels[metric]) {
                BAAnalyticsObservation *observation = rawChannels[metric][index.unsignedIntegerValue];
                if (observation.identifier) [shown addObject:observation.identifier];
            }
            Require([shown containsObject:@"performance.cells.1234"] && [shown containsObject:@"performance.cells.5678"],
                @"Cell display envelope lost isolated voltage minimum/maximum");
            Require([[canvas valueForKey:@"untrustedRects"] count] > 0, @"Cell voltage display lost the missing sampled spans");
            Require([canvas.latestReport reportForFamily:BAAnalyticsFamilyCells].window.observations.count == count,
                @"Cell preparation replaced raw history with the display envelope");
            [self saveView:cell name:@"performance-cells-2x2.png"];
            [self.manifest addObject:@{@"image":@"performance-cells-2x2.png",@"family":card.familyIdentifier,@"size":@(size),@"width":@346,@"hitRegions":@(canvas.hitRegions.count),@"language":@"en"}];
        } else {
            BASStatisticalCard *statistical = (id)card;
            NSDictionary *cached = statistical.analysis;
            Require(cached != nil && statistical.derivedReport == report, @"Statistical view did not derive from the published dense report");
            for (NSUInteger i=0;i<8;i++) [cell applyMetricSnapshot:BAFixtureSnapshot(NO)];
            Require(statistical.analysis == cached && statistical.derivedReport == report && !canvas.isPreparingHistory,
                @"Pure history snapshot delivery invalidated prepared statistics");
        }
        [mounted addObject:cell];
    }
    for (BAAnalyticsCardCell *cell in mounted) { [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview]; }
    // Cover only the changed Capacity/Cells geometries, reusing this same
    // immutable report rather than expanding the full presentation matrix.
    for (NSUInteger index=0;index<2;index++) {
        BAAnalyticsCanvasCard *card=cards[index];
        for (NSNumber *number in BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes)) {
            BAAnalyticsCardSize size=number.integerValue;
            if ((index==0 && size==BAAnalyticsCardSize2x1) || (index==1 && size==BAAnalyticsCardSize2x2)) continue;
            [self capturePerformanceCard:card size:size name:[NSString stringWithFormat:@"performance-%@-size%ld-en.png",card.familyIdentifier,(long)size]];
        }
    }
    FixtureLanguage=@"zh_CN";
    BAAnalyticsCanvasCard *chinese=(id)BAAnalyticsCreateCapacityCanvasCard(); chinese.historyService=history;
    [self capturePerformanceCard:chinese size:chinese.defaultAnalyticsCardSize name:@"performance-capacity-default-zh_CN.png"];
    [chinese analyticsCardDidReceiveMemoryWarning]; FixtureLanguage=@"en";
    Require(self.manifest.count<=8,@"Focused performance mode expanded beyond eight screenshots");
    [self testStartupRefreshPresentationWithReport:report];
    BAFixtureHistoryService *processHistory = [BAFixtureHistoryService new]; processHistory.fixtureReport = BAFixtureReport(@"ready");
    for (BAAnalyticsCanvasCard *process in BAAnalyticsCreateProcessCanvasCards()) {
        process.historyService = processHistory;
        for (NSNumber *number in BAAnalyticsCardOrderedSizesForMask(process.supportedAnalyticsCardSizes)) {
            BAAnalyticsCardSize size = number.integerValue;
            if (size != BAAnalyticsCardSize2x1 && size != BAAnalyticsCardSize2x2) continue;
            [self capturePerformanceCard:process size:size name:[NSString stringWithFormat:@"performance-%@-size%ld-ready.png", process.familyIdentifier, (long)size]];
        }
        [process analyticsCardDidReceiveMemoryWarning];
    }
    [self testDenseEventsPresentation];

    // Hold one derivation in flight, then publish two generations. The main
    // heartbeat must run during the held work, and only the newest may survive.
    BAFixtureHistoryService *probeHistory = [BAFixtureHistoryService new]; probeHistory.fixtureReport = report;
    BAPerformanceStatisticalCard *probe = [[BAPerformanceStatisticalCard alloc] initWithIdentifier:@"fixture.performance.dwell"
        displayName:@"Synthetic dwell" familyIdentifier:BAAnalyticsFamilyDwell supportedSizes:BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x2];
    probe.historyService = probeHistory; probe.gate = dispatch_semaphore_create(0); probe.holdNextDerivation = YES;
    BAAnalyticsCardCell *probeCell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,346)];
    [probeCell configureWithCard:probe size:BAAnalyticsCardSize2x2 editing:NO]; [probeCell setAnalyticsCardDisplayed:YES];
    [self.window addSubview:probeCell]; [probeCell layoutIfNeeded];
    WaitForFixture(^BOOL { return probe.workerStarted; }, 3, @"Statistical worker did not start");
    __block BOOL heartbeat = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ heartbeat = YES; });
    WaitForFixture(^BOOL { return heartbeat; }, .5, @"Main queue stopped responding while statistics were prepared");
    Require(!probe.derivedOnMainThread && probe.analysis == nil, @"Statistics ran synchronously on main");
    probeHistory.fixtureReport = PerformanceGeneration(report,101); [probeHistory publishFixture];
    BAAnalyticsReport *newest = PerformanceGeneration(report,102);
    probeHistory.fixtureReport = newest; [probeHistory publishFixture];
    dispatch_semaphore_signal(probe.gate);
    WaitForFixture(^BOOL { return probe.derivedReport == newest && probe.analysis != nil; }, 5, @"Latest statistical generation did not replace discarded work");
    Require(probe.derivationCount == 2, @"Statistics retained or calculated a backlog of superseded generations");
    NSDictionary *cached = probe.analysis;
    for (NSUInteger i=0;i<8;i++) [probeCell applyMetricSnapshot:BAFixtureSnapshot(NO)];
    Require(probe.derivationCount == 2 && probe.analysis == cached, @"Live snapshots recalculated a pure history card");
    probe.workerStarted = NO; probe.gate = dispatch_semaphore_create(0); probe.holdNextDerivation = YES;
    probeHistory.fixtureReport = PerformanceGeneration(report,103); [probeHistory publishFixture];
    WaitForFixture(^BOOL { return probe.workerStarted; }, 3, @"Memory-pressure derivation did not start");
    [probe analyticsCardDidReceiveMemoryWarning];
    Require(probe.analysis == nil && probe.latestReport == nil && !((BAAnalyticsCanvasView *)probeCell.analyticsCardContentView).isPreparingHistory,
        @"Memory pressure retained statistical results or a permanent pending state");
    dispatch_semaphore_signal(probe.gate);
    __block BOOL memoryWorkerDrained = NO;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ memoryWorkerDrained = YES; });
    });
    WaitForFixture(^BOOL { return memoryWorkerDrained; }, 5, @"Cancelled statistics did not drain after memory pressure");
    Require(probe.analysis == nil && probe.latestReport == nil && probe.derivationCount == 3,
        @"Discarded work resurrected statistics after memory pressure");
    [probeCell setAnalyticsCardDisplayed:NO]; [probeCell removeFromSuperview];
    self.performanceResults[@"coalescedDerivations"] = @(probe.derivationCount);
    self.performanceResults[@"mainHeartbeatDuringPreparation"] = @(heartbeat);

    // Large exact evidence is selected on the same worker. The constructor and
    // main queue remain responsive while its complete raw record set is frozen.
    dispatch_semaphore_t evidenceGate = dispatch_semaphore_create(0);
    __block BOOL evidenceWorkerHeld = NO;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ evidenceWorkerHeld = YES; });
        dispatch_semaphore_wait(evidenceGate, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    });
    WaitForFixture(^BOOL { return evidenceWorkerHeld; }, 3, @"Evidence worker barrier did not start");
    NSTimeInterval detailStarted = NSProcessInfo.processInfo.systemUptime;
    BAAnalyticsDetailViewController *detail = [[BAAnalyticsDetailViewController alloc] initWithDisplayName:@"Synthetic exact capacity"
        familyIdentifier:BAAnalyticsFamilyCapacity report:report snapshot:nil selection:nil];
    self.performanceResults[@"detailConstructorSeconds"] = @(NSProcessInfo.processInfo.systemUptime - detailStarted);
    Require(NSProcessInfo.processInfo.systemUptime - detailStarted < .25 && detail.selectedObservations.count == 0,
        @"Large evidence selection blocked its detail constructor");
    [self.navigation pushViewController:detail animated:NO]; [detail.view layoutIfNeeded];
    Require([[detail valueForKey:@"selectingEvidence"] boolValue] && detail.tableView.numberOfSections > 0,
        @"Large evidence did not expose a bounded loading presentation");
    heartbeat = NO; dispatch_async(dispatch_get_main_queue(), ^{ heartbeat = YES; });
    WaitForFixture(^BOOL { return heartbeat; }, .5, @"Detail evidence selection froze the main queue");
    dispatch_semaphore_signal(evidenceGate);
    WaitForFixture(^BOOL { return detail.selectedObservations.count == count; }, 5, @"Exact detail evidence was truncated or did not finish");
    Require(detail.report == report && [detail.selectedObservations[1777].identifier isEqual:@"performance.capacity.1777"] &&
        [detail.selectedObservations[5333].identifier isEqual:@"performance.capacity.5333"], @"Exact evidence lost the frozen source or isolated extrema");
    [self.navigation popViewControllerAnimated:NO];
    for (BAAnalyticsCanvasCard *card in cards) [card analyticsCardDidReceiveMemoryWarning];
    self.performanceResults[@"exactDetailRecords"] = @(detail.selectedObservations.count);
    self.performanceResults[@"totalSeconds"] = @(NSProcessInfo.processInfo.systemUptime - began);
}
- (void)testGapIndexSemantics {
    NSDate *origin = [NSDate dateWithTimeIntervalSince1970:1700000000];
    BAAnalyticsHistoryGap *(^gap)(double,double,NSString *) = ^BAAnalyticsHistoryGap *(double a,double b,NSString *reason) {
        return [[BAAnalyticsHistoryGap alloc] initWithStartDate:[origin dateByAddingTimeInterval:a] endDate:[origin dateByAddingTimeInterval:b] reason:reason];
    };
    NSArray *gaps = @[gap(18,24,@"source"),gap(10,20,@"Required fields unavailable or sampling gap"),gap(5,7,@"source"),gap(12,13,@"source")];
    for (NSUInteger mode=0;mode<2;mode++) for (NSUInteger i=0;i<30;i++) {
        NSDate *start=[origin dateByAddingTimeInterval:i], *end=[origin dateByAddingTimeInterval:i+1];
        BOOL reference=NO;
        for (BAAnalyticsHistoryGap *item in gaps) {
            if (mode && [item.reason isEqual:@"Required fields unavailable or sampling gap"]) continue;
            reference |= [item.endDate compare:start]==NSOrderedDescending && [item.startDate compare:end]==NSOrderedAscending;
        }
        Require(BAAnalyticsHistoryHasGap(gaps,start,end,mode!=0)==reference, @"Indexed gap overlap disagreed with the original strict predicate");
    }
    Require(!BAAnalyticsHistoryHasGap(@[gap(10,20,@"source")],origin,[origin dateByAddingTimeInterval:10],NO) &&
        !BAAnalyticsHistoryHasGap(@[gap(10,20,@"source")],[origin dateByAddingTimeInterval:20],[origin dateByAddingTimeInterval:30],NO),
        @"A gap touching only a query endpoint changed strict overlap");
    Require(BAAnalyticsHistoryHasGap(@[gap(10,20,@"Required fields unavailable or sampling gap")],[origin dateByAddingTimeInterval:11],[origin dateByAddingTimeInterval:19],NO) &&
        !BAAnalyticsHistoryHasGap(@[gap(10,20,@"Required fields unavailable or sampling gap")],[origin dateByAddingTimeInterval:11],[origin dateByAddingTimeInterval:19],YES),
        @"Source-only gap indexing did not preserve coverage-gap exclusion");
    NSMutableArray *mutable=[gaps mutableCopy];
    NSDate *start=[origin dateByAddingTimeInterval:100], *end=[origin dateByAddingTimeInterval:110];
    Require(!BAAnalyticsHistoryHasGap(mutable,start,end,NO), @"Mutable gap fixture unexpectedly overlapped");
    [mutable addObject:gap(102,108,@"source")];
    Require(BAAnalyticsHistoryHasGap(mutable,start,end,NO), @"Mutable gap input reused a stale immutable index");
}
- (void)writeValidationWithChecks:(NSArray<NSString *> *)checks passed:(BOOL)passed {
    NSMutableDictionary *result=[@{@"synthetic":@YES,@"nativeDarkMode":@NO,@"renderings":self.manifest,
        @"checks":checks,@"passed":@(passed)} mutableCopy];
    if (self.performanceResults) result[@"performance"]=self.performanceResults;
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[self.output stringByAppendingPathComponent:@"validation.json"] atomically:YES];
}
- (void)runChecks {
    BOOL historyOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_HISTORY_ONLY"] isEqual:@"1"];
    BOOL performanceOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_PERFORMANCE_ONLY"] isEqual:@"1"];
    NSArray<NSString *> *checks = performanceOnly ? @[@"actual host lifecycle, editing, navigation and frozen optional details",
        @"8000-record Foundation-only history generated off main",@"bounded Capacity/Cells display and VoiceOver marks with raw extrema and gaps retained",
        @"asynchronous statistics, responsive main queue, generation coalescing and memory cleanup",@"pure history snapshots preserve derived results",
        @"cached startup preserves acquisition timestamps and refreshes paired geometry/report/details",@"dense independent comparison keeps full statistics with bounded drawing/actions",@"dense event sweep agrees with full overlap and gap-boundary predicates",@"asynchronous full exact evidence selection",@"strict gap indexing, mutable inputs and fresh service cache reentry",@"real history publication and lazy host activation"] : historyOnly ? @[@"real asynchronous history publication and visible canvas lifecycle",@"lazy host history activation after a missed BecomeActive notification"] :
        @[@"actual plugin registration",@"legacy layout migration",@"all supported sizes",@"320/390/430 container widths",@"fallback dark palette",@"accessibility text size",@"partial/unavailable data",
          @"selected evidence navigation",@"seven optional visual details and frozen evidence",@"gettext catalog translations in Chinese and German",@"system battery colors and 20-percent threshold",
          @"full canvas editing with sibling accessory stacking and hit routing",@"readings / plot annotation separation",@"44-point accessibility targets and equivalent activation",
          @"editing suppresses card touch, embedded gestures and accessibility actions",@"resize/remove/add/reorder/persistence",@"visible-only subscriptions",
          @"current capacity detail without history and no mixed-source capacity ratios",@"real asynchronous history publication and visible canvas lifecycle",@"lazy host history activation after a missed BecomeActive notification"];
    @try {
        if (performanceOnly) {
            [self testRegistrationAndMigration]; [self testHost]; [self testFamilyDetails]; [self testCapacityCurrentDetail];
            [self testPerformanceHistory]; [self testGapIndexSemantics];
        } else if (!historyOnly) {
        [self testRegistrationAndMigration];
        [self renderCardsAtWidth:390 scenario:@"ready" allSizes:YES];
        [self renderCardsAtWidth:320 scenario:@"ready" allSizes:YES];
        [self renderCardsAtWidth:430 scenario:@"ready" allSizes:YES];
        ForcedStyle=UIUserInterfaceStyleDark;[self renderCardsAtWidth:390 scenario:@"ready" allSizes:YES];ForcedStyle=UIUserInterfaceStyleLight;
        ForcedCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;Require([[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12]].pointSize>20,@"Accessibility font scaling inactive");[self renderCardsAtWidth:320 scenario:@"ready" allSizes:YES];ForcedCategory=nil;
        [self renderCardsAtWidth:390 scenario:@"partial" allSizes:NO];[self renderCardsAtWidth:390 scenario:@"unavailable" allSizes:NO];
        [self testBatteryStates]; ForcedStyle=UIUserInterfaceStyleDark;[self testBatteryStates];ForcedStyle=UIUserInterfaceStyleLight;
        [self testEditingAccessories];
        for (NSString *language in @[@"zh_CN",@"de"]) {
            FixtureLanguage=language;self.cards=BAAnalyticsCreateBuiltInCards();
            [self renderCardsAtWidth:320 scenario:@"ready" allSizes:YES];
            [self testEditingAccessories];
        }
        FixtureLanguage=@"en";self.cards=BAAnalyticsCreateBuiltInCards();
        [self testHost];
        [self testFamilyDetails];
        [self testCapacityCurrentDetail];
        }
        [self testRealHistoryPublication];
        [self testRealHostHistoryActivation];
        [self writeValidationWithChecks:checks passed:YES];
        [@"PASS" writeToFile:[self.output stringByAppendingPathComponent:@"analytics-v3.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch(NSException *exception) {
        [self writeValidationWithChecks:checks passed:NO];
        [[NSString stringWithFormat:@"FAIL: %@\n%@",exception.reason,exception.callStackSymbols] writeToFile:[self.output stringByAppendingPathComponent:@"analytics-v3.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(FixtureAppDelegate.class)); } }
