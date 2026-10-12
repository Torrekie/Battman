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
#import "../../Battman/Features/Analytics/Host/BAAnalyticsUnavailableCard.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsSystemMetricSource.h"
#import "../../Battman/PluginHost/Application/BTPluginPlatform.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/ObjCExt/UIColor+compat.h"
#import "../../Battman/Features/Analytics/BuiltIn/Canvas/BAAnalyticsDetailViewController.h"
#import "../../Battman/Features/Analytics/BuiltIn/Live/BAAnalyticsLiveDrawing.h"
#import "../../Battman/Features/Analytics/BuiltIn/Statistics/BAStatisticsDrawing.h"
#import "../../Battman/Features/Analytics/BuiltIn/Process/BAAnalyticsProcessDrawing.h"
#import "../../Battman/Features/Analytics/BuiltIn/Process/BAAnalyticsSessionCanvasCard.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryReader.h"
#import <objc/message.h>
#include <math.h>
#include <sqlite3.h>
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
static void CheckEmbeddedScrollInsets(UIView *view) {
    if ([view isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (id)view;
        Require(UIEdgeInsetsEqualToEdgeInsets(scroll.adjustedContentInset, UIEdgeInsetsZero),
            @"Embedded card scrolling inherited navigation/safe-area insets");
    }
    for (UIView *child in view.subviews) CheckEmbeddedScrollInsets(child);
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
// Fixture services inject their storage; never resolve production user data.
const char *battman_config_dir(void) { return NULL; }
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
NSNotificationName const BTPluginPlatformDidFinishStartupNotification = @"BTPluginPlatformDidFinishStartupNotification";
static BTPluginPlatform *FixtureExternalPlatform;
static BTPluginRegistry *FixtureExternalRegistry;
@implementation BTPluginPlatform
+ (instancetype)sharedPlatform {
    Require(FixtureExternalPlatform != nil, @"Production composition reached outside the external-card fixture");
    return FixtureExternalPlatform;
}
- (BTPluginRegistry *)registry {
    Require(self == FixtureExternalPlatform && FixtureExternalRegistry != nil, @"Unexpected external registry access");
    return FixtureExternalRegistry;
}
@end
static UIUserInterfaceStyle ForcedStyle=UIUserInterfaceStyleLight;
static BOOL FixtureNativeDarkMode=NO;
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
    if (@available(iOS 13.0, *)) {
        FixtureNativeDarkMode=YES;
    } else {
        // Legacy systems exercise Battman's fallback palette. Modern UIKit
        // must use actual window traits to resolve dynamic system colors.
        Method style=class_getInstanceMethod(UITraitCollection.class,@selector(userInterfaceStyle));
        if(style)method_setImplementation(style,(IMP)TestStyle);else class_addMethod(UITraitCollection.class,@selector(userInterfaceStyle),(IMP)TestStyle,"q@:");
    }
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

static BAAnalyticsReport *ReaderCableEventReport(NSURL *file) {
    NSDate *end = [NSDate dateWithTimeIntervalSince1970:floor(NSDate.date.timeIntervalSince1970)];
    NSTimeInterval start = end.timeIntervalSince1970 - 1800;
    sqlite3 *database = NULL;
    Require(sqlite3_open(file.path.fileSystemRepresentation, &database) == SQLITE_OK, @"Could not create isolated cable-event database");
    @try {
        NSString *schema = [NSString stringWithFormat:
            @"CREATE TABLE PLStorageOperator_EventForward_TimeOffset (ID INTEGER PRIMARY KEY,timestamp REAL,system REAL);"
            "INSERT INTO PLStorageOperator_EventForward_TimeOffset VALUES (1,%.6f,0);"
            "CREATE TABLE PLBatteryAgent_EventBackward_Battery (ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,InstantAmperage INTEGER,"
            "ExternalConnected INTEGER,IsCharging INTEGER,FullyCharged INTEGER,Voltage INTEGER DEFAULT 4000,CellVoltage0 INTEGER DEFAULT 4000,CellVoltage1 INTEGER DEFAULT 4001);"
            "CREATE TABLE PLBatteryAgent_EventBackward_BatteryUI (ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,IsCharging INTEGER);"
            "INSERT INTO PLBatteryAgent_EventBackward_BatteryUI VALUES (1,%.6f,50,0),(2,%.6f,50,0);", start - 3600, start, start + 1200];
        Require(sqlite3_exec(database, schema.UTF8String, NULL, NULL, NULL) == SQLITE_OK, @"Could not populate cable-event schema");
        for (NSUInteger index = 0; index <= 21; index++) {
            NSTimeInterval time = start + (index == 21 ? 1800 : index * 60);
            BOOL charging = index == 2 || index == 3 || index == 21;
            NSString *row = [NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventBackward_Battery (ID,timestamp,Level,InstantAmperage,ExternalConnected,IsCharging,FullyCharged) VALUES (%lu,%.6f,50,%d,%d,%d,0)",
                (unsigned long)index + 1, time, charging ? 100 : -100, charging, charging];
            Require(sqlite3_exec(database, row.UTF8String, NULL, NULL, NULL) == SQLITE_OK, @"Could not populate cable-event samples");
        }
    } @finally { sqlite3_close(database); }
    return BAAnalyticsReadHistoryReport(file, end, 710, ^BOOL { return NO; });
}

static BAAnalyticsReport *PerformanceFragmentedReport(BAAnalyticsReport *base) {
    NSMutableDictionary *families = [NSMutableDictionary dictionary];
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    for (NSUInteger index=0;index<8000;index+=20) [indices addIndex:index];
    for (NSNumber *index in @[@1777,@5333,@1234,@5678,@7999]) [indices addIndex:index.unsignedIntegerValue];
    for (NSString *name in @[BAAnalyticsFamilyCapacity,BAAnalyticsFamilyCells]) {
        BAAnalyticsFamilyReport *original = [base reportForFamily:name];
        NSArray *points = [original.window.observations objectsAtIndexes:indices];
        NSMutableArray *intervals = [NSMutableArray array], *gaps = [NSMutableArray array];
        for (NSUInteger index=1;index<points.count;index++) {
            BAAnalyticsObservation *a=points[index-1], *b=points[index];
            [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:a.timestamp endDate:b.timestamp
                startObservation:a endObservation:b coveredMetricIdentifiers:[NSSet setWithArray:b.values.allKeys] state:BAAnalyticsObservedStateUnknown]];
            // Explicit gaps override apparently valid pairs and create many
            // more original runs than a widget's display budget can retain.
            if (index%2) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:a.timestamp endDate:b.timestamp reason:@"Synthetic missing pair"]];
        }
        BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:original.window.startDate endDate:original.window.endDate
            observations:points intervals:intervals gaps:gaps coverageMetricIdentifiers:original.window.coverageMetricIdentifiers
            coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
        families[name] = [[BAAnalyticsFamilyReport alloc] initWithFamily:name availability:BAAnalyticsReportAvailabilityPartial
            window:window payload:@{BAAnalyticsPayloadLatestObservation:points.lastObject} limitations:@[@"Synthetic fragmented source"]];
    }
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:601 generatedAt:base.generatedAt sourceProfileIdentifier:@"synthetic.fragmented.v1"
        fieldMetadata:base.fieldMetadata familyReports:families error:nil];
}

static double FixtureMissingFraction(BAAnalyticsFamilyReport *family) {
    NSTimeInterval missing=0, duration=[family.window.endDate timeIntervalSinceDate:family.window.startDate];
    for (BAAnalyticsHistoryGap *gap in family.window.gaps) {
        NSDate *start=[gap.startDate laterDate:family.window.startDate],*end=[gap.endDate earlierDate:family.window.endDate];
        missing+=MAX(0,[end timeIntervalSinceDate:start]);
    }
    return duration>0?missing/duration:0;
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
@interface BAFixtureReadingTap : UITapGestureRecognizer
@property (nonatomic) CGPoint fixturePoint;
@end
@implementation BAFixtureReadingTap
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateEnded; }
- (CGPoint)locationInView:(UIView *)view { return self.fixturePoint; }
@end
@interface BAFixtureCardLongPress : UILongPressGestureRecognizer
@property (nonatomic) UIGestureRecognizerState fixtureState;
@property (nonatomic) CGPoint fixturePoint;
@end
@implementation BAFixtureCardLongPress
- (UIGestureRecognizerState)state { return self.fixtureState; }
- (CGPoint)locationInView:(UIView *)view { return self.fixturePoint; }
@end
// A small external provider exercises the actual host/registry/restoration
// boundary without starting sensor acquisition or deriving another canvas.
@interface BAFixtureExternalCard : NSObject <BAAnalyticsCard>
@property (nonatomic, copy) NSString *analyticsCardIdentifier;
@property (nonatomic, copy) NSDictionary *restoredState;
@property (nonatomic) NSUInteger restorationCount;
@end
@implementation BAFixtureExternalCard
- (BAAnalyticsCardSizeMask)supportedAnalyticsCardSizes { return BAAnalyticsCardSizeMaskAll; }
- (BAAnalyticsCardSize)defaultAnalyticsCardSize { return BAAnalyticsCardSize1x1; }
- (NSString *)analyticsCardDisplayName { return self.analyticsCardIdentifier.lastPathComponent; }
- (UIView *)makeAnalyticsCardContentView { return [UIView new]; }
- (void)configureAnalyticsCardContentView:(UIView *)view forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
    view.accessibilityIdentifier = self.analyticsCardIdentifier;
}
- (NSUInteger)analyticsCardRestorationSchemaVersion { return 1; }
- (NSDictionary *)analyticsCardRestorationState { return self.restoredState ?: @{}; }
- (void)analyticsCardRestoreState:(NSDictionary *)state { self.restoredState = state; ++self.restorationCount; }
@end
@interface BAAnalyticsCanvasView (FixtureCapacityBrowsing)
- (void)selectHistoryReading:(UITapGestureRecognizer *)recognizer;
@end
@interface AnalyticsViewController (FixtureActions)
- (void)addCard:(id<BAAnalyticsCard>)card;
- (void)externalCardsDidLoad:(NSNotification *)notification;
- (void)handleCardLongPress:(UILongPressGestureRecognizer *)recognizer;
- (void)saveCardLayout;
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
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle=ForcedStyle;
    [view setNeedsLayout]; AwaitPreparedCanvases(view);
    if ([NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_PERFORMANCE_ONLY"] isEqual:@"1"] && ![name hasPrefix:@"performance-"]) return;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size,NO,1);[view.layer renderInContext:UIGraphicsGetCurrentContext()];UIImage *image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
    Require(image!=nil,[NSString stringWithFormat:@"Missing rendered image %@",name]);
    Require([UIImagePNGRepresentation(image) writeToFile:[self.output stringByAppendingPathComponent:name] atomically:YES],@"Screenshot write failed");
}
- (void)renderCardsAtWidth:(CGFloat)width scenario:(NSString *)scenario allSizes:(BOOL)allSizes {
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle=ForcedStyle;
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
            NSString *name=[NSString stringWithFormat:@"%@-%ld-%.0f-%@-%@%@.png",card.familyIdentifier,(long)size,width,[scenario stringByAppendingFormat:@"-%@",FixtureLanguage],ForcedStyle==UIUserInterfaceStyleDark?(FixtureNativeDarkMode?@"dark":@"dark-fallback"):@"light",ForcedCategory?@"-large":@""];
            [self saveView:cell name:name];
            Require(!CGRectIsEmpty(canvas.bounds),@"Zero-sized canvas");
            if (ForcedCategory) CheckEmbeddedScrollInsets(canvas);
            if (@available(iOS 13.0, *)) Require(canvas.traitCollection.userInterfaceStyle==ForcedStyle,@"Canvas did not receive native appearance traits");
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
- (void)testDelayedExternalCards {
    UIViewController *originalRoot = self.window.rootViewController;
    NSString *suite = @"com.torrekie.Battman.AnalyticsV3Fixture.external-startup";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    AnalyticsViewController *host = nil;
    @try {
        // Separate launches cover normal edit completion and Done being tapped
        // while a dragged card is still waiting for its finish callback.
        for (NSUInteger dragging = 0; dragging < 2; dragging++) {
            [defaults removePersistentDomainForName:suite];
            NSMutableArray<BAFixtureExternalCard *> *cards = [NSMutableArray array];
            NSMutableArray *records = [NSMutableArray array];
            NSDictionary *savedState = @{@"range":@"week", @"selectedSeries":@2};
            for (NSString *suffix in @[@"alpha", @"beta", @"gamma", @"hidden"]) {
                BAFixtureExternalCard *card = [BAFixtureExternalCard new];
                card.analyticsCardIdentifier = [@"com.example.fixture.async." stringByAppendingString:suffix];
                [cards addObject:card];
                if (cards.count <= 3) [records addObject:[[BAAnalyticsCardLayoutRecord alloc]
                    initWithCardIdentifier:card.analyticsCardIdentifier displayName:suffix sizeValue:BAAnalyticsCardSize1x1
                    restorationSchemaVersion:1 restorationState:savedState]];
            }
            [BAAnalyticsCardLayoutStore saveRecords:records toUserDefaults:defaults];
            FixtureExternalPlatform = [BTPluginPlatform new];
            FixtureExternalRegistry = [BTPluginRegistry new];
            NSError *error = nil;
            Require([FixtureExternalRegistry registerExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
                interfaceVersion:BAAnalyticsCardExtensionPointVersion requiredProtocol:@protocol(BAAnalyticsCard) error:&error], error.description);
            host = [[AnalyticsViewController alloc] initWithCards:@[cards[0]] metricService:[BAFixtureMetricService new]
                historyService:[BAFixtureHistoryService new] userDefaults:defaults];
            // The injected initializer intentionally omits application composition.
            // Wire its production notification selector to this isolated platform.
            [NSNotificationCenter.defaultCenter addObserver:host selector:@selector(externalCardsDidLoad:)
                name:BTPluginPlatformDidFinishStartupNotification object:FixtureExternalPlatform];
            self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:host];
            [self.window layoutIfNeeded]; [host.view layoutIfNeeded]; DrainUI();
            UICollectionView *collection = [host valueForKey:@"collectionView"];
            NSMutableArray *states = [host valueForKey:@"cardStates"];
            Require(states.count == 3 && [[states[1] valueForKey:@"card"] isKindOfClass:BAAnalyticsUnavailableCard.class],
                @"Pending external provider did not retain its saved placeholder");

            [host setEditing:YES animated:NO]; [collection layoutIfNeeded];
            [collection.dataSource collectionView:collection moveItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]
                toIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            [collection reloadData]; [collection layoutIfNeeded];
            BAAnalyticsCardCell *cell = (id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            Require(cell != nil && !cell.resizeButton.hidden, @"Pending provider could not be resized");
            [cell.resizeButton sendActionsForControlEvents:UIControlEventTouchUpInside]; [collection layoutIfNeeded];
            NSInteger editedSize = [[states[0] valueForKey:@"size"] integerValue];
            Require(editedSize != BAAnalyticsCardSize1x1, @"Fixture resize did not reach the production host");
            NSIndexPath *removedPath = [NSIndexPath indexPathForItem:2 inSection:0];
            [collection scrollToItemAtIndexPath:removedPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
            [collection layoutIfNeeded];
            cell = (id)[collection cellForItemAtIndexPath:removedPath];
            Require(cell != nil, @"Pending provider to remove was not visible");
            [cell.removeButton sendActionsForControlEvents:UIControlEventTouchUpInside]; [collection layoutIfNeeded]; DrainUI();
            [collection setContentOffset:CGPointZero animated:NO]; [collection layoutIfNeeded];
            NSArray *editedStates = [states copy];
            NSArray *editedOrder = @[cards[1].analyticsCardIdentifier, cards[0].analyticsCardIdentifier];
            Require([[states valueForKeyPath:@"card.analyticsCardIdentifier"] isEqual:editedOrder], @"Fixture edit did not preserve its intended order");
            id placeholder = [states[0] valueForKey:@"card"];

            BAFixtureCardLongPress *gesture = nil;
            if (dragging) {
                cell = (id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
                gesture = [BAFixtureCardLongPress new]; gesture.fixtureState = UIGestureRecognizerStateBegan;
                gesture.fixturePoint = CGPointMake(CGRectGetMidX(cell.frame), CGRectGetMidY(cell.frame));
                [host handleCardLongPress:gesture];
                Require([[host valueForKey:@"movingCard"] boolValue], @"Production long press did not start a drag");
            }
            BTPluginRegistrationTransaction *transaction = [FixtureExternalRegistry beginTransactionForPluginIdentifier:@"com.example.fixture.async"
                pluginVersion:@"1.0" declaredExtensionPoints:[NSSet setWithObject:BAAnalyticsCardExtensionPointIdentifier] error:&error];
            Require(transaction != nil, error.description);
            for (BAFixtureExternalCard *card in cards)
                Require([transaction registerExtensionObject:card extensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
                    extensionPointVersion:BAAnalyticsCardExtensionPointVersion extensionIdentifier:card.analyticsCardIdentifier error:&error], error.description);
            Require([transaction commit:&error], error.description);
            [NSNotificationCenter.defaultCenter postNotificationName:BTPluginPlatformDidFinishStartupNotification object:FixtureExternalPlatform];
            Require([[host valueForKey:@"pendingExternalCards"] boolValue] && [states[0] valueForKey:@"card"] == placeholder,
                @"External completion changed a card during editing or dragging");
            [host setEditing:NO animated:NO];
            if (dragging) {
                Require([[host valueForKey:@"pendingExternalCards"] boolValue] && [states[0] valueForKey:@"card"] == placeholder,
                    @"Done replaced the provider before the dragged card finished");
                gesture.fixtureState = UIGestureRecognizerStateEnded;
                [host handleCardLongPress:gesture];
            }
            WaitForFixture(^BOOL { return ![[host valueForKey:@"pendingExternalCards"] boolValue] && ![[host valueForKey:@"movingCard"] boolValue]; },
                1, @"Deferred external completion was not applied after editing/dragging ended");
            [collection layoutIfNeeded];
            Require([states isEqualToArray:editedStates] && [[states valueForKeyPath:@"card.analyticsCardIdentifier"] isEqual:editedOrder] &&
                [[states[0] valueForKey:@"size"] integerValue] == editedSize, @"External startup reconstructed or overwrote the edited layout");
            Require([states[0] valueForKey:@"card"] == cards[1] && cards[1].restorationCount == 1 && [cards[1].restoredState isEqual:savedState],
                @"The matching external provider did not restore the placeholder's exact saved state");
            Require([[host valueForKey:@"availableCards"] count] == 4 && states.count == 2 && cards[2].restorationCount == 0,
                @"External startup re-added a removed/hidden provider to a saved layout");
            cell = (id)[collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]];
            Require([cell.analyticsCardContentView.accessibilityIdentifier isEqual:cards[1].analyticsCardIdentifier],
                @"Resolved provider did not replace the visible unavailable content");
            [host saveCardLayout];
            NSArray<BAAnalyticsCardLayoutRecord *> *saved = [BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:defaults];
            Require(saved.count == 2 && [saved[0].cardIdentifier isEqual:cards[1].analyticsCardIdentifier] &&
                saved[0].sizeValue == editedSize && [saved[0].restorationState isEqual:savedState],
                @"Resolved external provider did not preserve edited layout persistence");
            [NSNotificationCenter.defaultCenter removeObserver:host name:BTPluginPlatformDidFinishStartupNotification object:FixtureExternalPlatform];
        }
    } @finally {
        if (host) [NSNotificationCenter.defaultCenter removeObserver:host name:BTPluginPlatformDidFinishStartupNotification object:FixtureExternalPlatform];
        self.window.rootViewController = originalRoot;
        [self.window layoutIfNeeded];
        FixtureExternalRegistry = nil; FixtureExternalPlatform = nil;
        [defaults removePersistentDomainForName:suite];
    }
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
- (void)testScrollRecyclingWithReport:(BAAnalyticsReport *)report {
    BAAnalyticsReport *original = self.history.fixtureReport;
    self.history.fixtureReport = report; [self.history publishFixture];
    UICollectionView *collection = [self.host valueForKey:@"collectionView"];
    NSArray *states = [self.host valueForKey:@"cardStates"];
    NSMutableDictionary *canvases = [NSMutableDictionary dictionary];
    NSMutableArray *durations = [NSMutableArray array];
    for (NSUInteger pass = 0; pass < 2; pass++) {
        for (NSUInteger index = 0; index < states.count; index++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:0];
            NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
            [collection scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
            [collection layoutIfNeeded];
            BAAnalyticsCardCell *cell = (id)[collection cellForItemAtIndexPath:path];
            BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
            Require(canvas != nil, @"Scroll did not display the requested card");
            if (pass == 0) {
                AwaitPreparedCanvases(cell);
                canvases[cell.mountedCardIdentifier] = canvas;
            } else {
                Require(canvases[cell.mountedCardIdentifier] == canvas, @"Scroll round trip recreated a prepared canvas");
                [canvas.layer displayIfNeeded];
                [durations addObject:@(NSProcessInfo.processInfo.systemUptime - start)];
            }
        }
    }
    self.performanceResults[@"scrollRetainedCanvasCount"] = @(canvases.count);
    self.performanceResults[@"scrollWarmVisitSeconds"] = durations;
    NSUInteger capacityIndex = [states indexOfObjectPassingTest:^BOOL(id state, NSUInteger index, BOOL *stop) {
        return [[(BAAnalyticsCanvasCard *)[state valueForKey:@"card"] familyIdentifier] isEqual:BAAnalyticsFamilyCapacity];
    }];
    NSIndexPath *path = [NSIndexPath indexPathForItem:capacityIndex inSection:0];
    [collection scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    [collection layoutIfNeeded];
    BAAnalyticsCardCell *cell = (id)[collection cellForItemAtIndexPath:path];
    BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
    AwaitPreparedCanvases(cell);
    Require([collection touchesShouldCancelInContentView:canvas], @"Card control captured a scrolling touch");
    Require(![collection touchesShouldCancelInContentView:cell.resizeButton], @"Scroll policy unexpectedly changed resize button tracking");
    BAAnalyticsReport *displayed = canvas.latestReport;
    BAAnalyticsMetricSnapshot *snapshot = canvas.latestSnapshot;
    [collection.delegate scrollViewWillBeginDragging:collection];
    BAAnalyticsReport *last = nil;
    for (NSUInteger sequence = 0; sequence < 2; sequence++) {
        last = [[BAAnalyticsReport alloc] initWithSequenceNumber:9000 + sequence generatedAt:report.generatedAt
            sourceProfileIdentifier:report.sourceProfileIdentifier fieldMetadata:report.fieldMetadata
            familyReports:report.familyReports error:nil];
        self.history.fixtureReport = last; [self.history publishFixture];
        self.metrics.fixtureSnapshot = BAFixtureSnapshot(NO); [self.metrics refreshNow];
    }
    Require(canvas.latestReport == displayed && canvas.latestSnapshot == snapshot,
        @"History/live refresh replaced the canvas during finger tracking");
    [collection.delegate scrollViewDidEndDragging:collection willDecelerate:YES];
    Require(canvas.latestReport == displayed, @"Refresh interrupted inertial scrolling");
    [collection.delegate scrollViewDidEndDecelerating:collection];
    AwaitPreparedCanvases(cell);
    Require(canvas.latestReport == last && canvas.latestSnapshot == self.metrics.fixtureSnapshot,
        @"Scroll completion failed to adopt the newest coalesced evidence");
    // Release cached offscreen views while preserving the mounted visible view.
    [cell releaseOffscreenCardContent];
    Require(cell.analyticsCardContentView == canvas, @"Memory reclamation detached a visible canvas");
    BAAnalyticsCardCell *cached = [[BAAnalyticsCardCell alloc] initWithFrame:cell.frame];
    cached.preservesBuiltInCanvasForReuse = YES;
    BAAnalyticsCanvasCard *card = [states[capacityIndex] valueForKey:@"card"];
    [cached configureWithCard:card size:card.defaultAnalyticsCardSize editing:NO];
    UIView *retained = cached.analyticsCardContentView;
    [cached prepareForReuse];
    Require(cached.analyticsCardContentView == retained, @"Built-in prepareForReuse discarded its canvas");
    [cached releaseOffscreenCardContent];
    Require(cached.analyticsCardContentView == nil, @"Memory reclamation retained an offscreen canvas");
    [cached configureWithCard:card size:card.defaultAnalyticsCardSize editing:NO];
    BAAnalyticsCanvasCard *replacement = (id)BAAnalyticsCreateCapacityCanvasCard();
    retained = cached.analyticsCardContentView;
    [cached configureWithCard:replacement size:replacement.defaultAnalyticsCardSize editing:NO];
    Require(cached.analyticsCardContentView != retained, @"Replacing a card object reused the old object's canvas");
    self.history.fixtureReport = original; [self.history publishFixture];
    [collection setContentOffset:CGPointZero animated:NO]; [collection layoutIfNeeded];
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
- (void)testSessionSingletonFallback {
    BAAnalyticsReport *base = BAFixtureReport(@"ready");
    BAAnalyticsFamilyReport *original = base.familyReports[BAAnalyticsFamilySession];
    BAAnalyticsHistorySession *previous = original.payload[BAAnalyticsPayloadSelectedSession];
    NSDate *date = [previous.endDate dateByAddingTimeInterval:60];
    BAAnalyticsObservation *point = [[BAAnalyticsObservation alloc] initWithIdentifier:@"synthetic.latest.single"
        timestamp:date sourceTimestamp:date.timeIntervalSince1970 timestampValidated:YES
        values:previous.observations.lastObject.values fieldMetadata:previous.observations.lastObject.fieldMetadata];
    BAAnalyticsHistorySession *latest = [[BAAnalyticsHistorySession alloc] initWithIdentifier:@"synthetic.latest.connection"
        kind:@"connected" startDate:date endDate:date startBoundaryKnown:NO endBoundaryKnown:NO
        observations:@[point] intervals:@[] gaps:@[] transitions:@[]];
    BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilySession
        availability:BAAnalyticsReportAvailabilityPartial window:original.window
        payload:@{BAAnalyticsPayloadSessions:@[previous,latest],BAAnalyticsPayloadSelectedSession:latest}
        limitations:@[@"Synthetic newest connection contains one observation"]];
    NSMutableDictionary *families = [base.familyReports mutableCopy]; families[BAAnalyticsFamilySession] = family;
    BAFixtureHistoryService *history = [BAFixtureHistoryService new];
    history.fixtureReport = [[BAAnalyticsReport alloc] initWithSequenceNumber:2 generatedAt:date
        sourceProfileIdentifier:base.sourceProfileIdentifier fieldMetadata:base.fieldMetadata familyReports:families error:nil];
    BAAnalyticsCanvasCard *card = [BAAnalyticsSessionCanvasCard new]; card.historyService = history;
    for (NSString *language in @[@"en",@"zh_CN",@"de"]) {
        FixtureLanguage = language;
        for (NSNumber *sizeNumber in BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes)) @autoreleasepool {
            BAAnalyticsCardSize size = sizeNumber.integerValue; CGSize span = BAAnalyticsCardGridSpan(size);
            BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,138*span.width+12*(span.width-1),138*span.height+12*(span.height-1))];
            [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
            [cell applyMetricSnapshot:self.metrics.fixtureSnapshot]; [self.window addSubview:cell]; AwaitPreparedCanvases(cell);
            BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
            BAAnalyticsDetailSelection *selection = canvas.hitRegions.firstObject.selection;
            Require([selection.context[@"sessionIdentifier"] isEqual:previous.identifier] &&
                [selection.context[@"showingPreviousSession"] boolValue] && [selection.startDate isEqual:previous.startDate],
                @"Newest singleton hid the drawable session or changed its selected evidence");
            Require([canvas.accessibilityLabel containsString:cond_localize("Newest connection has one reading; showing previous session")],
                @"Previous-session presentation omitted its provenance");
            NSString *name = [NSString stringWithFormat:@"session-previous-%ld-%@.png",(long)size,language];
            [self saveView:cell name:name]; [self.manifest addObject:@{@"image":name,@"family":BAAnalyticsFamilySession,@"size":@(size),@"language":language}];
            [cell configureWithCard:card size:size editing:YES]; [cell layoutIfNeeded];
            Require(![canvas accessibilityActivate],@"Fallback session opened details during editing");
            [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
        }
    }
    FixtureLanguage = @"en";
    BAAnalyticsFamilyReport *compare = base.familyReports[BAAnalyticsFamilyCompare];
    BAAnalyticsFamilyReport *one = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCompare
        availability:BAAnalyticsReportAvailabilityReady window:compare.window
        payload:@{BAAnalyticsPayloadSessions:@[[compare.payload[BAAnalyticsPayloadSessions] firstObject]]} limitations:compare.limitations];
    families[BAAnalyticsFamilyCompare] = one;
    history.fixtureReport = [[BAAnalyticsReport alloc] initWithSequenceNumber:3 generatedAt:date
        sourceProfileIdentifier:base.sourceProfileIdentifier fieldMetadata:base.fieldMetadata familyReports:families error:nil];
    card = (id)BAAnalyticsCreateCompareCanvasCard(); card.historyService = history;
    for (NSNumber *sizeNumber in BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes)) @autoreleasepool {
        BAAnalyticsCardSize size = sizeNumber.integerValue; CGSize span = BAAnalyticsCardGridSpan(size);
        BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,138*span.width+12*(span.width-1),138*span.height+12*(span.height-1))];
        [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
        [cell applyMetricSnapshot:self.metrics.fixtureSnapshot]; [self.window addSubview:cell]; AwaitPreparedCanvases(cell);
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        Require([[[canvas valueForKey:@"analysis"] objectForKey:@"samples"] count] == 1 &&
            ![[[canvas valueForKey:@"analysis"] objectForKey:@"hasBox"] boolValue],@"Single complete session did not retain its individual estimate");
        NSString *name = [NSString stringWithFormat:@"compare-single-%ld-en.png",(long)size];
        [self saveView:cell name:name]; [self.manifest addObject:@{@"image":name,@"family":BAAnalyticsFamilyCompare,@"size":@(size)}];
        [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
    }
}
- (void)testCellsCurrentFallback {
    NSDate *now = [NSDate date], *cachedTime = [now dateByAddingTimeInterval:-3600];
    NSDictionary *single = @{BAAnalyticsMetricCellCount:@1, BAAnalyticsCellVoltageMetricIdentifier(0):@3952};
    NSDictionary *multiple = @{BAAnalyticsMetricCellCount:@3, BAAnalyticsCellVoltageMetricIdentifier(0):@3940,
        BAAnalyticsCellVoltageMetricIdentifier(1):@3952, BAAnalyticsCellVoltageMetricIdentifier(2):@3965};
    NSArray *scenarios = @[@"single",@"multiple",@"cached",@"missing",@"history"];
    for (NSString *scenario in scenarios) {
        BAFixtureHistoryService *history = [BAFixtureHistoryService new];
        history.fixtureReport = BAFixtureReport([scenario isEqual:@"history"] ? @"ready" : @"unavailable");
        BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCellsCanvasCard(); card.historyService = history;
        for (NSNumber *sizeNumber in BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes)) @autoreleasepool {
            BAAnalyticsCardSize size = sizeNumber.integerValue; CGSize span = BAAnalyticsCardGridSpan(size);
            CGFloat unit = 138; CGSize bounds = CGSizeMake(unit * span.width + 12 * (span.width - 1), unit * span.height + 12 * (span.height - 1));
            BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:(CGRect){CGPointZero,bounds}];
            [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
            NSDictionary *values = [scenario isEqual:@"multiple"] ? multiple : [scenario isEqual:@"missing"] ? @{} : single;
            BOOL cached = [scenario isEqual:@"cached"];
            BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:41
                timestamp:cached ? cachedTime : now values:values histories:@{BAAnalyticsCellVoltageMetricIdentifier(0):
                    @[[[BAAnalyticsMetricPoint alloc] initWithTimestamp:[now dateByAddingTimeInterval:-300] value:3200]]}];
            if (cached) snapshot = [snapshot snapshotByMarkingCached];
            [cell applyMetricSnapshot:snapshot]; [self.window addSubview:cell]; AwaitPreparedCanvases(cell);
            BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
            BOOL hasHistory = [scenario isEqual:@"history"];
            Require([[canvas valueForKey:@"displayingCurrentCells"] boolValue] != hasHistory, @"Cell fallback replaced existing history or failed to adopt a current reading");
            NSDictionary *shown = [canvas valueForKey:@"latestValues"];
            if (hasHistory) {
                Require(canvas.detailEnabled && canvas.hitRegions.count > 0 && shown.count == 3,
                    @"Historical cell chart or optional details were discarded by the single-cell live snapshot");
                Require(![[canvas valueForKey:@"latestCellObservation"] isEqual:snapshot], @"Current cells were inserted into historical evidence");
            } else {
                Require(!canvas.detailEnabled && canvas.hitRegions.count == 0 && ![canvas accessibilityActivate] &&
                    [card detailViewControllerForSelection:nil size:size] == nil, @"Current cell reading opened an unsupported historical detail");
                Require(shown.count == values.count - (values.count ? 1 : 0), @"Current cell snapshot lost or borrowed a channel");
                NSNumber *delta = [canvas valueForKey:@"observedDelta"];
                Require([scenario isEqual:@"multiple"] ? delta.doubleValue == 25 : delta == nil,
                    @"Cell delta was fabricated for a single/absent channel or mixed sample times");
                BAAnalyticsMetricSnapshot *current = [canvas valueForKey:@"currentCellSnapshot"];
                Require(!values.count || (current == snapshot && [current.timestamp isEqual:cached ? cachedTime : now]),
                    @"Current cell fallback changed the acquisition timestamp");
                Require([[canvas valueForKey:@"windowText"] isEqual:values.count ?
                    cond_localize(cached ? "Cached current reading" : "Current reading") : cond_localize("No cell readings")],
                    @"Current/cached/missing cells claim a historical window");
            }
            if (![[canvas valueForKey:@"largeType"] boolValue]) {
                CGRect plot = [[canvas valueForKey:@"plotRect"] CGRectValue];
                for (NSString *key in @[@"summaryRect",@"unitRect",@"countRect",@"timestampRect",@"windowRect"]) {
                    CGRect annotation = [[canvas valueForKey:key] CGRectValue];
                    Require(CGRectIsEmpty(annotation) || CGRectContainsRect(canvas.bounds,annotation), @"Cells annotation lies outside its canvas");
                    Require(CGRectIsEmpty(CGRectIntersection(plot,annotation)), @"Cell reading annotations overlap the visualization");
                }
            }
            NSString *name = [NSString stringWithFormat:@"cells-fallback-%@-%ld-en.png",scenario,(long)size];
            [self saveView:cell name:name];
            [self.manifest addObject:@{@"image":name,@"family":BAAnalyticsFamilyCells,@"size":@(size),@"scenario":scenario}];
            if (cached) {
                BAAnalyticsMetricSnapshot *fresh = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:42 timestamp:now values:multiple histories:nil];
                [cell applyMetricSnapshot:fresh]; [cell layoutIfNeeded];
                Require([canvas valueForKey:@"currentCellSnapshot"] == fresh && [[canvas valueForKey:@"observedDelta"] doubleValue] == 25 &&
                    [[canvas valueForKey:@"windowText"] isEqual:cond_localize("Current reading")], @"Fresh cells did not replace cached values and provenance together");
            }
            [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
        }
    }
    // Cover long localized provenance and the existing scrollable accessibility
    // summary without rendering the unrelated card matrix again.
    NSArray *presentations = @[@{@"language":@"de",@"cached":@YES}, @{@"language":@"zh_CN"},
        @{@"language":@"en",@"dark":@YES}, @{@"language":@"en",@"large":@YES}];
    for (NSDictionary *presentation in presentations) {
        FixtureLanguage = presentation[@"language"];
        ForcedStyle = [presentation[@"dark"] boolValue] ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        ForcedCategory = [presentation[@"large"] boolValue] ? UIContentSizeCategoryAccessibilityExtraExtraExtraLarge : nil;
        BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = BAFixtureReport(@"unavailable");
        BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCellsCanvasCard(); card.historyService = history;
        NSArray *sizes = [presentation[@"cached"] boolValue] ? BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes) : @[@(BAAnalyticsCardSize1x1)];
        for (NSNumber *sizeNumber in sizes) @autoreleasepool {
            BAAnalyticsCardSize size = sizeNumber.integerValue; CGSize span = BAAnalyticsCardGridSpan(size);
            BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,138*span.width+12*(span.width-1),138*span.height+12*(span.height-1))];
            [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
            BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:43 timestamp:now values:multiple histories:nil];
            if ([presentation[@"cached"] boolValue]) snapshot = [snapshot snapshotByMarkingCached];
            [cell applyMetricSnapshot:snapshot]; [self.window addSubview:cell]; AwaitPreparedCanvases(cell);
            NSString *name = [NSString stringWithFormat:@"cells-fallback-localized-%@-%ld%@%@.png",FixtureLanguage,(long)size,
                ForcedStyle==UIUserInterfaceStyleDark ? @"-dark" : @"", ForcedCategory ? @"-large" : @""];
            [self saveView:cell name:name];
            [self.manifest addObject:@{@"image":name,@"family":BAAnalyticsFamilyCells,@"size":@(size),@"language":FixtureLanguage}];
            [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
        }
    }
    FixtureLanguage = @"en"; ForcedStyle = UIUserInterfaceStyleLight; ForcedCategory = nil;
    BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCellsCanvasCard();
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = BAFixtureReport(@"unavailable"); card.historyService = history;
    BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,138,138)];
    [cell configureWithCard:card size:BAAnalyticsCardSize1x1 editing:NO]; [cell setAnalyticsCardDisplayed:YES];
    BAAnalyticsMetricSnapshot *invalid = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:44 timestamp:now
        values:@{BAAnalyticsMetricCellCount:@3, BAAnalyticsCellVoltageMetricIdentifier(0):@YES,
            BAAnalyticsCellVoltageMetricIdentifier(1):@3952.25,BAAnalyticsCellVoltageMetricIdentifier(2):@3952} histories:nil];
    [cell applyMetricSnapshot:invalid]; [cell layoutIfNeeded]; BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
    Require([[canvas valueForKey:@"latestValues"] count] == 1 && [canvas valueForKey:@"observedDelta"] == nil,
        @"Boolean/fractional cells were treated as valid mV readings");
    Require(![[canvas valueForKey:@"summaryText"] isEqual:cond_localize("Single cell")],
        @"One valid reading in a multi-cell pack claimed single-cell hardware");
    Require([[[canvas valueForKey:@"visibleMetrics"] firstObject] isEqual:BAAnalyticsHistoryCellVoltage2Millivolts],
        @"Missing earlier channels displaced the only valid current reading");
    NSMutableDictionary *dense = [NSMutableDictionary dictionaryWithObject:@10 forKey:BAAnalyticsMetricCellCount];
    for (NSUInteger index=0;index<10;index++) dense[BAAnalyticsCellVoltageMetricIdentifier(index)] = @(3950+index);
    [cell applyMetricSnapshot:[[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:45 timestamp:now values:dense histories:nil]]; [cell layoutIfNeeded];
    Require([[canvas valueForKey:@"latestValues"] count] == 10 && [[canvas valueForKey:@"visibleMetrics"] count] <= 10 && canvas.hitRegions.count == 0,
        @"Dense current cells lost exact accessible readings or created per-record actions");
    [cell setAnalyticsCardDisplayed:NO];
}
- (void)testCapacityCurrentDetail {
    // A translucent missing-data fill must blend over an opaque light canvas.
    uint8_t pixels[12 * 12 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels, 12, 12, 8, 12 * 4, space,
        kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    Require(bitmap != NULL, @"Missing-data blend fixture has no graphics context");
    CGContextSetRGBFillColor(bitmap, 1, 1, 1, 1); CGContextFillRect(bitmap, CGRectMake(0, 0, 12, 12));
    UIGraphicsPushContext(bitmap); BALiveHatch(CGRectMake(0, 0, 12, 12)); UIGraphicsPopContext();
    CGContextRelease(bitmap);
    Require(pixels[(6 * 12 + 6) * 4] > 128, @"Missing-data fill replaced the light canvas with an opaque dark block");
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

    // Real capacity windows also contain newer rows from unrelated tables.
    // A selected historical range must use its own FCC evidence, rather than
    // the family's last row or a denominator from the current acquisition.
    NSMutableArray<BAAnalyticsObservation *> *historyPoints = [NSMutableArray array];
    NSDate *origin = [now dateByAddingTimeInterval:-3600];
    for (NSUInteger index = 0; index < 260; index++) {
        NSDate *time = [origin dateByAddingTimeInterval:10.0 * index];
        [historyPoints addObject:[[BAAnalyticsObservation alloc] initWithIdentifier:[NSString stringWithFormat:@"capacity.range.%lu", (unsigned long)index]
            timestamp:time sourceTimestamp:time.timeIntervalSince1970 timestampValidated:YES values:@{metric:@(3100 + index)} fieldMetadata:@{metric:field}]];
    }
    BAAnalyticsObservation *lastFCC = historyPoints.lastObject;
    NSDate *unrelatedTime = [now dateByAddingTimeInterval:-900];
    [historyPoints addObject:[[BAAnalyticsObservation alloc] initWithIdentifier:@"capacity.unrelated.latest" timestamp:unrelatedTime
        sourceTimestamp:unrelatedTime.timeIntervalSince1970 timestampValidated:YES values:@{} fieldMetadata:@{}]];
    BAAnalyticsHistoryWindow *denseWindow = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:origin endDate:now
        observations:historyPoints intervals:@[] gaps:@[] coverageMetricIdentifiers:NSSet.set coveredDuration:0 missingDuration:3600 coverageSecondsByMetric:@{}];
    BAAnalyticsFamilyReport *denseFamily = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCapacity availability:BAAnalyticsReportAvailabilityPartial
        window:denseWindow payload:@{BAAnalyticsPayloadLatestObservation:lastFCC} limitations:@[]];
    BAAnalyticsReport *denseReport = [[BAAnalyticsReport alloc] initWithSequenceNumber:24 generatedAt:now sourceProfileIdentifier:@"fixture.capacity.range"
        fieldMetadata:@{metric:field} familyReports:@{BAAnalyticsFamilyCapacity:denseFamily} error:nil];
    BAAnalyticsCanvasCard *denseCard = (id)BAAnalyticsCreateCapacityCanvasCard(); [denseCard setValue:denseReport forKey:@"latestReport"];
    BAAnalyticsCanvasView *denseCanvas = (id)[denseCard makeAnalyticsCardContentView];
    denseCanvas.frame = CGRectMake(0, 0, 173, 173);
    [denseCard analyticsCardContentView:denseCanvas didReceiveMetricSnapshot:snapshot];
    [denseCard configureAnalyticsCardContentView:denseCanvas forSize:BAAnalyticsCardSize1x1 editing:NO]; AwaitPreparedCanvases(denseCanvas);
    BAAnalyticsCanvasHitRegion *overviewHit = nil;
    for (BAAnalyticsCanvasHitRegion *hit in denseCanvas.hitRegions) if ([hit.selection.kind isEqual:@"overview"]) overviewHit = hit;
    Require(overviewHit != nil, @"Dense compact capacity trend has no overview affordance");
    BAFixtureTouch *centerTouch = [BAFixtureTouch new]; centerTouch.point = CGPointMake(CGRectGetMidX(overviewHit.rect), CGRectGetMidY(overviewHit.rect));
    [denseCanvas endTrackingWithTouch:(UITouch *)(id)centerTouch withEvent:nil];
    Require([denseCanvas.selectedDetail.kind isEqual:@"overview"], @"Compact capacity canvas selected an arbitrary historical slice");
    denseCanvas.frame = CGRectMake(0, 0, 358, 358);
    [denseCard configureAnalyticsCardContentView:denseCanvas forSize:BAAnalyticsCardSize2x2 editing:NO]; AwaitPreparedCanvases(denseCanvas);
    NSUInteger sliceHits = 0;
    for (BAAnalyticsCanvasHitRegion *hit in denseCanvas.hitRegions) {
        if (![hit.selection.kind isEqual:@"capacity-observations"] ||
            [hit.selection.endDate timeIntervalSinceDate:hit.selection.startDate] >= [lastFCC.timestamp timeIntervalSinceDate:origin]) continue;
        Require(CGRectGetWidth(hit.rect) >= 44 && CGRectGetHeight(hit.rect) >= 44, @"Large capacity trend has overlapping narrow slice targets");
        sliceHits++;
    }
    Require(sliceHits > 1, @"Large capacity trend lost its historical slice interactions");
    BAAnalyticsDetailSelection *range = [BAAnalyticsDetailSelection selectionForFamily:BAAnalyticsFamilyCapacity kind:@"capacity-observations"
        recordIdentifiers:nil metricIdentifiers:@[metric, BAAnalyticsHistoryDesignCapacityMilliampHours]
        startDate:historyPoints[100].timestamp endDate:historyPoints[120].timestamp
        context:@{@"validatedMetricIdentifiers":@[metric], @"reportSequence":@24}];
    detail = (id)[denseCard detailViewControllerForSelection:range size:BAAnalyticsCardSize2x2];
    WaitForFixture(^BOOL { return detail.selectedObservations.count == 21; }, 5, @"Capacity historical slice did not select its original records");
    rows = [detail summaryRows];
    Require(CapacitySummaryNumber(rows,0).doubleValue == 3220 && [rows[1][@"value"] isEqual:cond_localize("Unavailable")] &&
        [rows[2][@"value"] isEqual:cond_localize("Unavailable")], @"Historical capacity range used an unrelated row or borrowed the live denominator");
    [self.navigation pushViewController:detail animated:NO]; [detail.view layoutIfNeeded]; AwaitPreparedCanvases(detail.view);
    BAAnalyticsCanvasView *detailCanvas = [detail valueForKey:@"visualization"];
    NSArray *visiblePoints = [detailCanvas valueForKey:@"capacityObservations"];
    Require(visiblePoints.count == detail.selectedObservations.count && visiblePoints.firstObject == historyPoints[100] &&
        visiblePoints.lastObject == historyPoints[120], @"Capacity detail chart did not match its selected evidence window");
    Require(detailCanvas.latestSnapshot == nil && [[detailCanvas valueForKey:@"fullCharge"] doubleValue] == 3220 &&
        [detailCanvas valueForKey:@"designCapacity"] == nil, @"Historical capacity detail graphic adopted current acquisition values");
    [self saveView:self.window name:@"detail-capacity-historical-slice-en.png"];
    [self.navigation popViewControllerAnimated:NO]; DrainUI();

    BAAnalyticsMetricSnapshot *newer = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:25 timestamp:[now dateByAddingTimeInterval:1]
        values:@{BAAnalyticsMetricFullChargeCapacityMilliampHours:@6100, BAAnalyticsMetricDesignCapacityMilliampHours:@8000} histories:nil];
    [denseCard analyticsCardContentView:denseCanvas didReceiveMetricSnapshot:newer];
    BAAnalyticsDetailSelection *frozen = [BAAnalyticsDetailSelection selectionForFamily:BAAnalyticsFamilyCapacity kind:@"overview"
        recordIdentifiers:nil metricIdentifiers:@[metric] startDate:origin endDate:lastFCC.timestamp context:@{@"source":@"metricSnapshot",
            @"fullChargeMilliampHours":@5591, @"designCapacityMilliampHours":@7596, @"observationTimestamp":@(now.timeIntervalSince1970), @"reportSequence":@24}];
    BAAnalyticsDetailViewController *frozenDetail = (id)[denseCard detailViewControllerForSelection:frozen size:BAAnalyticsCardSize2x2];
    BAAnalyticsCanvasView *frozenCanvas = (id)[frozenDetail makeVisualizationView]; frozenCanvas.frame = CGRectMake(0, 0, 358, 330); AwaitPreparedCanvases(frozenCanvas);
    Require([[frozenCanvas valueForKey:@"fullCharge"] doubleValue] == 5591 && [[frozenCanvas valueForKey:@"designCapacity"] doubleValue] == 7596,
        @"Capacity detail graphic replaced its frozen current pair with a newer snapshot");
    // The selection carries Unix seconds, rather than NSDate's reference epoch.
    // Compare that stored representation without another epoch round trip.
    Require([[frozenCanvas valueForKey:@"capacityTimestamp"] timeIntervalSince1970] == [frozen.context[@"observationTimestamp"] doubleValue],
        @"Capacity detail graphic replaced its frozen acquisition timestamp");
    [denseCard analyticsCardContentView:denseCanvas didReceiveMetricSnapshot:designOnly];
    BAAnalyticsDetailViewController *historyOverview = (id)[denseCard detailViewControllerForSelection:nil size:BAAnalyticsCardSize2x2];
    WaitForFixture(^BOOL { return historyOverview.selectedObservations.count == historyPoints.count; }, 5, @"Capacity overview evidence did not finish");
    rows = [historyOverview summaryRows];
    Require(CapacitySummaryNumber(rows,0).doubleValue == 3359 && [rows[1][@"value"] isEqual:cond_localize("Unavailable")],
        @"Capacity overview used the family's unrelated final row or a live design-only denominator");
}
- (void)testCapacityHistoryBrowsing {
    NSString *metric = BAAnalyticsHistoryFullChargeCapacityMilliampHours;
    BAAnalyticsFieldMetadata *field = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.capacity"
        sourceColumn:@"FCC" unit:@"mAh" decoderIdentifier:@"fixture.capacity.browsing" unitValidated:YES];
    NSDate *origin = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSMutableArray<BAAnalyticsObservation *> *points = [NSMutableArray array];
    NSMutableArray *intervals = [NSMutableArray array], *gaps = [NSMutableArray array];
    for (NSUInteger index = 0; index <= 1000; index++) {
        NSDate *time = [origin dateByAddingTimeInterval:index * 3600.0];
        BAAnalyticsObservation *point = [[BAAnalyticsObservation alloc] initWithIdentifier:[NSString stringWithFormat:@"capacity.browse.%lu", (unsigned long)index]
            timestamp:time sourceTimestamp:time.timeIntervalSince1970 timestampValidated:YES
            values:@{metric:@(3500 - index * .15 + 12 * sin(index * .09) + (index == 910 ? 80 : 0))} fieldMetadata:@{metric:field}];
        if (points.count) {
            BAAnalyticsObservation *previous = points.lastObject;
            if (index >= 900 && index <= 903)
                [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:previous.timestamp endDate:time reason:@"Synthetic missing interval"]];
            else [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:previous.timestamp endDate:time
                startObservation:previous endObservation:point coveredMetricIdentifiers:[NSSet setWithObject:metric] state:BAAnalyticsObservedStateUnplugged]];
        }
        [points addObject:point];
    }
    BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:origin endDate:points.lastObject.timestamp
        observations:points intervals:intervals gaps:gaps coverageMetricIdentifiers:[NSSet setWithObject:metric]
        coveredDuration:996 * 3600 missingDuration:4 * 3600 coverageSecondsByMetric:@{metric:@(996 * 3600)}];
    BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCapacity
        availability:BAAnalyticsReportAvailabilityPartial window:window payload:@{} limitations:@[]];
    BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:51 generatedAt:points.lastObject.timestamp
        sourceProfileIdentifier:@"fixture.capacity.browsing" fieldMetadata:@{metric:field}
        familyReports:@{BAAnalyticsFamilyCapacity:family} error:nil];
    BAAnalyticsCanvasCard *card = (id)BAAnalyticsCreateCapacityCanvasCard(); [card setValue:report forKey:@"latestReport"];
    BAAnalyticsDetailViewController *detail = (id)[card detailViewControllerForSelection:nil size:BAAnalyticsCardSize2x2];
    [self.navigation pushViewController:detail animated:NO]; [detail.view layoutIfNeeded]; AwaitPreparedCanvases(detail.view);
    BAAnalyticsCanvasView *canvas = [detail valueForKey:@"visualization"];
    UIScrollView *scroll = [canvas valueForKey:@"historyScrollView"];
    UISegmentedControl *range = [canvas valueForKey:@"historyRangeControl"];
    id prepared = [canvas valueForKey:@"preparedHistory"];
    Require(canvas.userInteractionEnabled && [[canvas valueForKey:@"detailBrowsingEnabled"] boolValue], @"Capacity detail did not enable its optional interaction");
    Require([[canvas valueForKey:@"capacityObservations"] count] == points.count &&
        [[canvas valueForKey:@"historyWindowDuration"] doubleValue] == 7 * 86400 &&
        fabs([[canvas valueForKey:@"historyWindowStart"] doubleValue] - (points.lastObject.timestamp.timeIntervalSince1970 - 7 * 86400)) < .01,
        @"Capacity history did not retain the full population and initially show its latest week");
    Require(scroll.contentSize.width > scroll.bounds.size.width && canvas.bounds.size.width <= detail.tableView.bounds.size.width &&
        CGRectContainsRect(canvas.bounds, scroll.frame) && CGRectIsEmpty(CGRectIntersection(scroll.frame, range.frame)),
        @"Capacity viewport allocated a wide drawing surface or overlapped its range control");
    Require([[canvas valueForKey:@"displayIndices"] count] <= 128 && [[canvas valueForKey:@"displayMarkerIndices"] count] <= 12 &&
        [[canvas valueForKey:@"displayGaps"] count] > 0, @"Capacity viewport exceeded drawing budgets or lost its visible gap");
    [self saveView:self.window name:@"detail-capacity-history-latest-en.png"];
    [scroll setContentOffset:CGPointZero animated:NO]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    Require(fabs([[canvas valueForKey:@"historyWindowStart"] doubleValue] - origin.timeIntervalSince1970) < .01 &&
        [canvas valueForKey:@"preparedHistory"] == prepared && [[[canvas valueForKey:@"displayIndices"] firstObject] unsignedIntegerValue] == 0,
        @"Horizontal browsing changed source preparation or failed to show the earliest records");
    CGRect plot = [[canvas valueForKey:@"historyPlotRect"] CGRectValue];
    BAFixtureReadingTap *tap = [BAFixtureReadingTap new];
    tap.fixturePoint = CGPointMake(plot.origin.x + plot.size.width * .4, CGRectGetMidY(plot));
    [canvas selectHistoryReading:tap]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    Require([[canvas valueForKey:@"selectedHistoryIndex"] unsignedIntegerValue] == 67,
        @"Tapping the capacity trend did not select the nearest original reading");
    Require([scroll.accessibilityValue containsString:@"mAh"], @"Selected capacity reading is not available to VoiceOver");
    [self saveView:self.window name:@"detail-capacity-history-selected-en.png"];
    CGRect originalFrame = canvas.frame;
    canvas.frame = CGRectMake(originalFrame.origin.x, originalFrame.origin.y, 288, originalFrame.size.height);
    [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    Require(fabs([[canvas valueForKey:@"historyWindowStart"] doubleValue] - origin.timeIntervalSince1970) < .01 &&
        [[canvas valueForKey:@"selectedHistoryIndex"] unsignedIntegerValue] == 67 && CGRectContainsRect(canvas.bounds, scroll.frame),
        @"Resizing the capacity viewport moved its time window, selection or gesture region");
    canvas.frame = originalFrame;
    range.selectedSegmentIndex = 0; [range sendActionsForControlEvents:UIControlEventValueChanged];
    [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    Require([[canvas valueForKey:@"historyWindowDuration"] doubleValue] == 86400 &&
        [[canvas valueForKey:@"displayIndices"] count] <= 128, @"Day range failed to update the bounded viewport");
    range.selectedSegmentIndex = 2; [range sendActionsForControlEvents:UIControlEventValueChanged];
    [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
    Require(fabs(scroll.contentSize.width - scroll.bounds.size.width) < .01 &&
        [[canvas valueForKey:@"capacityObservations"] count] == points.count && [[canvas valueForKey:@"displayIndices"] count] <= 128,
        @"All-history view truncated evidence or kept a scrollable oversized drawing");
    [self.navigation popViewControllerAnimated:NO]; DrainUI();
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
- (void)testReaderCableEventsAndIndependentGaps {
    NSURL *file = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"battman-cable-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    __block BAAnalyticsReport *report = nil; __block NSString *error = nil;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            @try {
                BAAnalyticsReport *generated = ReaderCableEventReport(file);
                dispatch_async(dispatch_get_main_queue(), ^{ report = generated; });
            } @catch (NSException *exception) {
                NSString *reason = exception.reason;
                dispatch_async(dispatch_get_main_queue(), ^{ error = reason; });
            }
        }
    });
    BAAnalyticsCardCell *cell = nil;
    @try {
        WaitForFixture(^BOOL { return report || error; }, 5, @"Production reader did not finish the cable-event fixture");
        Require(report && !report.error, error ?: @"Production reader rejected the cable-event fixture");
        BAAnalyticsFamilyReport *family = [report reportForFamily:BAAnalyticsFamilyEvents];
        NSArray<BAAnalyticsStateTransition *> *raw = family.payload[BAAnalyticsPayloadTransitions];
        Require(raw.count == 2, @"Reader failed to distinguish insertion/removal from a change across a long gap");
        for (BAAnalyticsStateTransition *transition in raw) {
            Require(BAAnalyticsHistoryHasGap(family.window.gaps, transition.earliestDate, transition.latestDate, NO) &&
                !BAAnalyticsHistoryHasGap(family.window.gaps, transition.earliestDate, transition.latestDate, YES),
                @"Cable boundary fixture did not exercise joint-coverage complement without a real source gap");
        }
        BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = report;
        BAAnalyticsCanvasCard *events = nil;
        for (BAAnalyticsCanvasCard *card in BAAnalyticsCreateProcessCanvasCards())
            if ([card.familyIdentifier isEqual:BAAnalyticsFamilyEvents]) events = card;
        events.historyService = history;
        cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0, 0, 346, 346)];
        [cell configureWithCard:events size:BAAnalyticsCardSize2x2 editing:NO];
        [cell setAnalyticsCardDisplayed:YES]; [self.window addSubview:cell]; AwaitPreparedCanvases(cell);
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        NSArray<BAAnalyticsStateTransition *> *visible = [canvas transitionsForFamily:family];
        Require(visible.count == 2 && [visible[0].identifier isEqual:raw[0].identifier] && [visible[1].identifier isEqual:raw[1].identifier],
            @"Events canvas erased a real reader cable transition because its state coverage changes");
        Require(visible[0].previousState == BAAnalyticsObservedStateUnplugged && visible[1].nextState == BAAnalyticsObservedStateUnplugged,
            @"Insertion and removal lost their distinct observed directions");
        BAAnalyticsHistoryWindow *path = [report reportForFamily:BAAnalyticsFamilyPath].window;
        NSUInteger usable = 0;
        for (BAAnalyticsHistoryInterval *interval in path.intervals)
            if (BAProcessIntervalUsable(interval, @[BAAnalyticsHistoryBatteryPowerWatts], path.gaps)) usable++;
        Require(usable == 20, @"Independent sparse BatteryUI masked trusted primary Battery power pairs");
        if (!self.performanceResults) self.performanceResults = [NSMutableDictionary dictionary];
        self.performanceResults[@"readerCableEventsAndIndependentSourceGaps"] = @YES;
    } @finally {
        [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview];
        [NSFileManager.defaultManager removeItemAtURL:file error:NULL];
    }
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
    if (@available(iOS 13.0, *)) self.window.overrideUserInterfaceStyle=ForcedStyle;
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
- (void)testProcessRenderingCaches {
    FixtureLanguage = @"en"; ForcedCategory = nil;
    NSDate *origin = [NSDate dateWithTimeIntervalSince1970:1700000000];
    NSArray *metrics = @[BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryTemperatureCelsius,
        BAAnalyticsHistoryCurrentMilliamps, BAAnalyticsHistoryBatteryPowerWatts,
        BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging, BAAnalyticsHistoryFullyCharged];
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    for (NSString *metric in metrics) {
        NSString *unit = [metric isEqual:BAAnalyticsHistorySOCPercent] ? @"%" :
            [metric isEqual:BAAnalyticsHistoryTemperatureCelsius] ? @"°C" :
            [metric isEqual:BAAnalyticsHistoryCurrentMilliamps] ? @"mA" :
            [metric isEqual:BAAnalyticsHistoryBatteryPowerWatts] ? @"W" : @"boolean";
        metadata[metric] = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.primary"
            sourceColumn:metric unit:unit decoderIdentifier:@"synthetic.process.v1" unitValidated:YES];
    }
    NSSet *covered = [NSSet setWithArray:metrics];
    BAAnalyticsObservation *(^point)(NSString *, NSUInteger, NSDictionary *) =
        ^BAAnalyticsObservation *(NSString *identifier, NSUInteger index, NSDictionary *values) {
            NSDate *date = [origin dateByAddingTimeInterval:10 * index];
            return [[BAAnalyticsObservation alloc] initWithIdentifier:identifier timestamp:date
                sourceTimestamp:date.timeIntervalSince1970 timestampValidated:YES values:values fieldMetadata:metadata];
        };
    BAAnalyticsHistoryInterval *(^pair)(BAAnalyticsObservation *, BAAnalyticsObservation *, BAAnalyticsObservedState) =
        ^BAAnalyticsHistoryInterval *(BAAnalyticsObservation *a, BAAnalyticsObservation *b, BAAnalyticsObservedState state) {
            return [[BAAnalyticsHistoryInterval alloc] initWithStartDate:a.timestamp endDate:b.timestamp
                startObservation:a endObservation:b coveredMetricIdentifiers:covered state:state];
        };
    NSDictionary *smallValues = @{BAAnalyticsHistorySOCPercent:@50, BAAnalyticsHistoryTemperatureCelsius:@32,
        BAAnalyticsHistoryCurrentMilliamps:@1000, BAAnalyticsHistoryBatteryPowerWatts:@4,
        BAAnalyticsHistoryExternalConnected:@YES, BAAnalyticsHistoryIsCharging:@YES, BAAnalyticsHistoryFullyCharged:@NO};
    NSMutableArray<BAAnalyticsObservation *> *small = [NSMutableArray array];
    for (NSUInteger index=0;index<7;index++)
        [small addObject:point([NSString stringWithFormat:@"synthetic.process.small.%lu",(unsigned long)index],index,smallValues)];
    BAAnalyticsCanvasView *probe = [BAAnalyticsCanvasView new];
    NSArray *noGaps = @[];
    NSArray *chain = @[pair(small[0],small[1],BAAnalyticsObservedStateCharging),
        pair(small[1],small[2],BAAnalyticsObservedStateCharging)];
    NSArray<BAProcessStateRun *> *runs = BAProcessStateRuns(probe,chain,noGaps,[small[0] timestamp],[small[2] timestamp]);
    Require(runs.count==1 && [runs.firstObject.startDate isEqual:[small[0] timestamp]] &&
        [runs.firstObject.endDate isEqual:[small[2] timestamp]] && runs.firstObject.state==BAAnalyticsObservedStateCharging,
        @"Shared-endpoint state pairs failed to collapse into one exact continuous display band");
    Require(BAProcessStateRuns(probe,chain,noGaps,[small[0] timestamp],[small[2] timestamp])==runs,
        @"Unchanged immutable state evidence rebuilt its presentation cache");

    NSArray *broken = @[pair(small[0],small[1],BAAnalyticsObservedStateCharging),
        pair(small[1],small[2],BAAnalyticsObservedStateCharging),
        pair(small[2],small[3],BAAnalyticsObservedStateCharging),
        pair(small[3],small[4],BAAnalyticsObservedStateUnknown),
        pair(small[4],small[5],BAAnalyticsObservedStateConnectedNotCharging),
        pair(small[5],small[6],BAAnalyticsObservedStateCharging)];
    NSArray *gaps = @[[[BAAnalyticsHistoryGap alloc] initWithStartDate:[small[1] timestamp]
        endDate:[small[2] timestamp] reason:@"Synthetic source discontinuity"]];
    runs = BAProcessStateRuns(probe,broken,gaps,[small[0] timestamp],[small[6] timestamp]);
    Require(runs.count==4 && [runs[0].endDate isEqual:[small[1] timestamp]] &&
        [runs[1].startDate isEqual:[small[2] timestamp]] && [runs[1].endDate isEqual:[small[3] timestamp]] &&
        [runs[2].startDate isEqual:[small[4] timestamp]] && runs[2].state==BAAnalyticsObservedStateConnectedNotCharging &&
        [runs[3].startDate isEqual:[small[5] timestamp]] && runs[3].state==BAAnalyticsObservedStateCharging,
        @"State display merged across a source gap, Unknown interval or actual state change");

    BAAnalyticsObservation *replacement = point(@"synthetic.process.other-source",1,smallValues);
    NSArray *mismatched = @[pair(small[0],small[1],BAAnalyticsObservedStateCharging),
        pair(replacement,small[2],BAAnalyticsObservedStateCharging)];
    runs = BAProcessStateRuns(probe,mismatched,noGaps,[small[0] timestamp],[small[2] timestamp]);
    Require(runs.count==2 && BAProcessStateRuns(probe,mismatched,noGaps,[small[0] timestamp],[small[2] timestamp])==runs,
        @"State display bridged distinct source endpoint IDs or failed immutable cache reuse");
    BAProcessClearDisplayCaches(probe);
    Require(BAProcessStateRuns(probe,mismatched,noGaps,[small[0] timestamp],[small[2] timestamp])!=runs,
        @"Explicit Process cache invalidation retained its previous display array");
    BAProcessClearDisplayCaches(probe);

    NSMutableDictionary *families = [NSMutableDictionary dictionary];
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary];
    const NSUInteger count = 500;
    for (NSNumber *flag in @[@NO,@YES]) {
        BOOL unplugged = flag.boolValue;
        NSString *family = unplugged ? BAAnalyticsFamilyDischarge : BAAnalyticsFamilySession;
        NSMutableArray<BAAnalyticsObservation *> *observations = [NSMutableArray array];
        NSMutableArray<BAAnalyticsHistoryInterval *> *intervals = [NSMutableArray array];
        for (NSUInteger index=0;index<count;index++) {
            double fraction = (double)index/(count-1);
            double power = unplugged ? (index==123 ? -12.75 : index==234 ? 4.25 : index==345 ? 0 : -3-1.5*sin(index*.07)) : 8-4*fraction;
            NSDictionary *values = @{BAAnalyticsHistorySOCPercent:@(unplugged ? 88-42*fraction : 18+66*fraction),
                BAAnalyticsHistoryTemperatureCelsius:@(index==177 ? 39.5 : 30+4*sin(M_PI*fraction)),
                BAAnalyticsHistoryCurrentMilliamps:@(power*250), BAAnalyticsHistoryBatteryPowerWatts:@(power),
                BAAnalyticsHistoryExternalConnected:@(!unplugged), BAAnalyticsHistoryIsCharging:@(!unplugged),
                BAAnalyticsHistoryFullyCharged:@NO};
            BAAnalyticsObservation *observation = point([NSString stringWithFormat:@"synthetic.process.%@.%lu",family,(unsigned long)index],index,values);
            if (observations.count) [intervals addObject:pair(observations.lastObject,observation,
                unplugged ? BAAnalyticsObservedStateUnplugged : BAAnalyticsObservedStateCharging)];
            [observations addObject:observation];
        }
        NSDate *end = [observations.lastObject timestamp];
        NSTimeInterval duration = [end timeIntervalSinceDate:origin];
        NSMutableDictionary *coverage = [NSMutableDictionary dictionary];
        for (NSString *metric in metrics) coverage[metric]=@(duration);
        BAAnalyticsHistorySession *session = [[BAAnalyticsHistorySession alloc] initWithIdentifier:
            [@"synthetic.process.session." stringByAppendingString:family] kind:unplugged?@"unplugged":@"connected"
            startDate:origin endDate:end startBoundaryKnown:YES endBoundaryKnown:YES observations:observations
            intervals:intervals gaps:noGaps transitions:@[]];
        BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:origin endDate:end
            observations:observations intervals:intervals gaps:noGaps coverageMetricIdentifiers:covered
            coveredDuration:duration missingDuration:0 coverageSecondsByMetric:coverage];
        families[family] = [[BAAnalyticsFamilyReport alloc] initWithFamily:family availability:BAAnalyticsReportAvailabilityReady
            window:window payload:@{BAAnalyticsPayloadSelectedSession:session,BAAnalyticsPayloadSessions:@[session]}
            limitations:@[@"Synthetic primary observations"]];
        sessions[family]=session;
    }
    BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:701
        generatedAt:[origin dateByAddingTimeInterval:10*(count-1)] sourceProfileIdentifier:@"synthetic.process.v1"
        fieldMetadata:metadata familyReports:families error:nil];
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport=report;
    for (BAAnalyticsCanvasCard *card in BAAnalyticsCreateProcessCanvasCards()) {
        BOOL isSession = [card.familyIdentifier isEqual:BAAnalyticsFamilySession];
        if (!isSession && ![card.familyIdentifier isEqual:BAAnalyticsFamilyDischarge]) continue;
        card.historyService=history;
        BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,346)];
        [cell configureWithCard:card size:BAAnalyticsCardSize2x2 editing:NO]; [cell setAnalyticsCardDisplayed:YES];
        [self.window addSubview:cell]; [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; AwaitPreparedCanvases(cell);
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        BAAnalyticsHistorySession *session = sessions[card.familyIdentifier];
        @try {
            Require([canvas valueForKey:@"preparedSession"]==session && session.observations.count==count && session.intervals.count==count-1,
                @"Dense Process presentation dropped raw observations or prepared a different session");
            NSArray *stateRuns = BAProcessStateRuns(canvas,session.intervals,session.gaps,session.startDate,session.endDate);
            Require(stateRuns.count==1,@"A stable dense Process session still produced one state band per sample pair");
            if (isSession) {
                NSArray *soc=[canvas valueForKey:@"preparedSOC"], *temperature=[canvas valueForKey:@"preparedTemperature"], *current=[canvas valueForKey:@"preparedCurrent"];
                NSNumber *coverage=[canvas valueForKey:@"preparedSOCCoverage"];
                Require(soc.count==count && temperature.count==count && current.count==count &&
                    fabs(coverage.doubleValue-10*(count-1))<1e-6 &&
                    fabs([[canvas valueForKey:@"preparedTemperatureCoverage"] doubleValue]-coverage.doubleValue)<1e-6 &&
                    fabs([[canvas valueForKey:@"preparedCurrentCoverage"] doubleValue]-coverage.doubleValue)<1e-6,
                    @"Session display reduction changed metric coverage or the exact observation population");
                [canvas setNeedsLayout]; [canvas setNeedsDisplay]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
                Require([canvas valueForKey:@"preparedSOC"]==soc && [canvas valueForKey:@"preparedTemperature"]==temperature &&
                    [canvas valueForKey:@"preparedCurrent"]==current && [[canvas valueForKey:@"preparedSOCCoverage"] isEqual:coverage] &&
                    BAProcessStateRuns(canvas,session.intervals,session.gaps,session.startDate,session.endDate)==stateRuns,
                    @"Unchanged Session drawing rebuilt immutable arrays, coverage or state bands");
                CGRect tracePlot = CGRectMake(24, 30, 300, 80);
                NSArray *(^collect)(void) = ^NSArray * {
                    return BAProcessTrace(canvas, soc, session.intervals, session.gaps,
                        BAAnalyticsHistorySOCPercent, @"%", session.startDate, session.endDate,
                        tracePlot, 0, 100, 1, UIColor.greenColor, NO, session.identifier);
                };
                NSArray *firstRegions = collect();
                Require(firstRegions.count > 0 && firstRegions.count <= 12 && collect() == firstRegions,
                    @"Dense layout recreated time-slice selections or exceeded screen-sized targets");
                for (BAAnalyticsCanvasHitRegion *hit in firstRegions)
                    Require([hit.selection.context[@"validatedMetricIdentifiers"] containsObject:BAAnalyticsHistorySOCPercent],
                        @"Dense metric detail lost its verified-unit restriction");
                NSTimeInterval selectionStart = NSProcessInfo.processInfo.systemUptime;
                for (NSUInteger repeat = 0; repeat < 100; repeat++) Require(collect() == firstRegions, @"Dense hit cache was unstable");
                self.performanceResults[@"sessionCached100CollectionsSeconds"] = @(NSProcessInfo.processInfo.systemUptime - selectionStart);
                self.performanceResults[@"sessionRawObservations"]=@(count);
                self.performanceResults[@"sessionDisplayStateRuns"]=@(stateRuns.count);
            } else {
                NSIndexSet *indices=[canvas valueForKey:@"preparedPowerIndices"];
                NSArray *intervals=[canvas valueForKey:@"preparedIntervals"];
                NSData *missing=[canvas valueForKey:@"preparedPowerMissingRanges"];
                Require(indices.count>0 && indices.count<=194 && [indices containsIndex:0] && [indices containsIndex:123] &&
                    [indices containsIndex:234] && [indices containsIndex:345] && [indices containsIndex:count-1],
                    @"Discharge power drawing exceeded its budget or lost negative/positive extrema, zero or endpoints");
                Require(intervals.count==count-1 && missing.length==0,
                    @"Dense unplugged display changed trusted power coverage or fabricated a missing span");
                [canvas setNeedsLayout]; [canvas setNeedsDisplay]; [canvas layoutIfNeeded]; [canvas.layer displayIfNeeded];
                Require([canvas valueForKey:@"preparedPowerIndices"]==indices && [canvas valueForKey:@"preparedIntervals"]==intervals &&
                    [canvas valueForKey:@"preparedPowerMissingRanges"]==missing,
                    @"Unchanged Discharge drawing rebuilt power indices, original intervals or missing ranges");
                self.performanceResults[@"dischargeRawObservations"]=@(count);
                self.performanceResults[@"dischargeDisplayPowerPoints"]=@(indices.count);
            }
            NSString *image = isSession ? @"performance-session-trend-2x2.png" : @"performance-discharge-trend-2x2.png";
            [self saveView:cell name:image];
            [self.manifest addObject:@{@"image":image,@"family":card.familyIdentifier,@"size":@(BAAnalyticsCardSize2x2),
                @"width":@346,@"hitRegions":@(canvas.hitRegions.count),@"language":@"en"}];
            [card analyticsCardDidReceiveMemoryWarning];
            Require(card.latestReport==nil && canvas.latestReport==nil && [canvas valueForKey:@"preparedSession"]==nil,
                @"Process memory pressure retained the report or selected-session cache");
            Require(BAProcessStateRuns(canvas,session.intervals,session.gaps,session.startDate,session.endDate)!=stateRuns,
                @"Process memory pressure failed to invalidate the associated state-run buffer");
            BAProcessClearDisplayCaches(canvas);
            if (isSession) Require([canvas valueForKey:@"preparedSOC"]==nil && [canvas valueForKey:@"preparedTemperature"]==nil &&
                [canvas valueForKey:@"preparedCurrent"]==nil && [canvas valueForKey:@"preparedPeak"]==nil &&
                [[canvas valueForKey:@"preparedSOCCoverage"] doubleValue]==0,
                @"Session memory pressure retained source arrays, the peak or coverage cache");
            else Require([canvas valueForKey:@"preparedIntervals"]==nil && [canvas valueForKey:@"preparedContext"]==nil &&
                [canvas valueForKey:@"preparedPowerIndices"]==nil && [canvas valueForKey:@"preparedPowerMissingRanges"]==nil &&
                [canvas valueForKey:@"preparedFirstSOC"]==nil && [canvas valueForKey:@"preparedLastSOC"]==nil,
                @"Discharge memory pressure retained source intervals, power buffers or endpoint rows");
        } @finally {
            [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview]; [card analyticsCardDidReceiveMemoryWarning];
        }
    }
    self.performanceResults[@"processStateBoundariesAndCacheLifecycle"]=@YES;
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
        @try {
            WaitForFixture(^BOOL {
                for (BAAnalyticsCardCell *cell in cells) {
                    BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
                    if (canvas.latestReport != reportB || canvas.isPreparingHistory) return NO;
                }
                return YES;
            }, 5, @"Prepared refresh did not replace every displayed card generation");
        } @catch (NSException *exception) {
            NSMutableArray *pending=[NSMutableArray array];
            for (BAAnalyticsCardCell *cell in cells) {
                BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView;
                if (canvas.latestReport!=reportB || canvas.isPreparingHistory)
                    [pending addObject:[NSString stringWithFormat:@"%@: displayed=%llu, preparing=%d",canvas.familyIdentifier,(unsigned long long)canvas.latestReport.sequenceNumber,canvas.isPreparingHistory]];
            }
            @throw [NSException exceptionWithName:exception.name reason:[NSString stringWithFormat:@"%@ (%@)",exception.reason,[pending componentsJoinedByString:@"; "]] userInfo:nil];
        }
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

- (void)testDrawingBudgetsWithReport:(BAAnalyticsReport *)base {
    BAAnalyticsReport *fragmented = PerformanceFragmentedReport(base);
    BAFixtureHistoryService *history = [BAFixtureHistoryService new]; history.fixtureReport = fragmented;
    for (BAAnalyticsCanvasCard *card in @[(id)BAAnalyticsCreateCapacityCanvasCard(),(id)BAAnalyticsCreateCellsCanvasCard()]) {
        card.historyService = history;
        BOOL capacity = [card.familyIdentifier isEqual:BAAnalyticsFamilyCapacity];
        BAAnalyticsCardSize size = capacity ? BAAnalyticsCardSize2x1 : BAAnalyticsCardSize2x2;
        BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,capacity?167:346)];
        [cell configureWithCard:card size:size editing:NO]; [cell setAnalyticsCardDisplayed:YES];
        [self.window addSubview:cell]; [cell applyMetricSnapshot:BAFixtureSnapshot(NO)]; AwaitPreparedCanvases(cell);
        BAAnalyticsCanvasView *canvas = (id)cell.analyticsCardContentView;
        BAAnalyticsFamilyReport *family = [fragmented reportForFamily:card.familyIdentifier];
        Require(family.window.gaps.count > 192 && [canvas.latestReport reportForFamily:card.familyIdentifier].window.observations.count == family.window.observations.count,
            @"Fragmented display lost original observations or source gaps");
        if (capacity) {
            NSArray *raw = [canvas valueForKey:@"capacityObservations"], *indices=[canvas valueForKey:@"displayIndices"], *markers=[canvas valueForKey:@"displayMarkerIndices"];
            Require(indices.count<=128 && markers.count<=12 && [[canvas valueForKey:@"displayGaps"] count]>0,@"Fragmented capacity exceeded budgets or hid missing time");
            NSMutableSet *ids=[NSMutableSet set];for (NSNumber *index in markers) [ids addObject:[raw[index.unsignedIntegerValue] identifier]];
            Require([ids containsObject:@"performance.capacity.1777"] && [ids containsObject:@"performance.capacity.5333"],@"Fragmented capacity hid real extrema");
            double missing=0;for(NSValue *value in [canvas valueForKey:@"displayGaps"])missing+=value.CGRectValue.size.width;
            Require(fabs(missing-FixtureMissingFraction(family))<1e-6,@"Capacity gap grouping exaggerated fragmented missing-time coverage");
        } else {
            NSDictionary *indices=[canvas valueForKey:@"displayIndices"];
            NSUInteger total=0;for (NSArray *channel in indices.allValues) total+=channel.count;
            Require(total<=192 && [[canvas valueForKey:@"marks"] count]<=12 && [[canvas valueForKey:@"untrustedRects"] count]>0,@"Fragmented cell history exceeded budgets or hid missing time");
            double missing=0;for(NSValue *value in [canvas valueForKey:@"untrustedRects"])missing+=value.CGRectValue.size.width;
            CGRect plot=[[canvas valueForKey:@"plotRect"] CGRectValue];
            Require(fabs(missing/plot.size.width-FixtureMissingFraction(family))<1e-6,@"Cell gap grouping exaggerated fragmented missing-time coverage");
        }
        [self capturePerformanceCard:card size:size name:capacity?@"performance-capacity-fragmented.png":@"performance-cells-fragmented.png"];
        [cell setAnalyticsCardDisplayed:NO]; [cell removeFromSuperview]; [card analyticsCardDidReceiveMemoryWarning];
    }
    // A clipped original endpoint must not displace the real in-window
    // minimum in a reduced edge bucket.
    NSString *metric=BAAnalyticsHistoryCellVoltage0Millivolts;
    NSDictionary *metadata=@{metric:[[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.clipped" sourceColumn:@"CellVoltage0" unit:@"mV" decoderIdentifier:@"synthetic.mV" unitValidated:YES]};
    NSMutableArray *points=[NSMutableArray array],*intervals=[NSMutableArray array];
    NSMutableArray *specs=[@[@[@(-3605),@3000],@[@(-3598),@3800],@[@(-3597),@3200],@[@(-3596),@4200],@[@(-3595),@3900]] mutableCopy];
    for (NSUInteger index=0;index<200;index++) [specs addObject:@[@(-3580+17*(NSInteger)index),@(3900+100*sin(index))]];
    [specs addObject:@[@0,@3900]];
    for (NSArray *spec in specs) {
        NSDate *date=[base.generatedAt dateByAddingTimeInterval:[spec[0] doubleValue]];
        BAAnalyticsObservation *point=[[BAAnalyticsObservation alloc] initWithIdentifier:[NSString stringWithFormat:@"clipped.%lu",(unsigned long)points.count]
            timestamp:date sourceTimestamp:date.timeIntervalSince1970 timestampValidated:YES values:@{metric:spec[1]} fieldMetadata:metadata];
        if (points.count) {
            BAAnalyticsObservation *prior=points.lastObject;
            [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:prior.timestamp endDate:date startObservation:prior endObservation:point coveredMetricIdentifiers:[NSSet setWithObject:metric] state:BAAnalyticsObservedStateUnknown]];
        }
        [points addObject:point];
    }
    BAAnalyticsHistoryWindow *window=[[BAAnalyticsHistoryWindow alloc] initWithStartDate:[base.generatedAt dateByAddingTimeInterval:-3600]
        endDate:base.generatedAt observations:[points subarrayWithRange:NSMakeRange(1,points.count-1)] intervals:intervals gaps:@[] coverageMetricIdentifiers:[NSSet setWithObject:metric] coveredDuration:3600 missingDuration:0 coverageSecondsByMetric:@{metric:@3600}];
    BAAnalyticsFamilyReport *family=[[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCells availability:BAAnalyticsReportAvailabilityReady
        window:window payload:@{BAAnalyticsPayloadLatestObservation:points.lastObject} limitations:@[@"Synthetic clipped interval"]];
    history.fixtureReport=[[BAAnalyticsReport alloc] initWithSequenceNumber:602 generatedAt:base.generatedAt sourceProfileIdentifier:@"synthetic.clipped.v1"
        fieldMetadata:metadata familyReports:@{BAAnalyticsFamilyCells:family} error:nil];
    BAAnalyticsCanvasCard *cells=(id)BAAnalyticsCreateCellsCanvasCard();cells.historyService=history;
    BAAnalyticsCardCell *cell=[[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,346)];
    [cell configureWithCard:cells size:BAAnalyticsCardSize2x2 editing:NO];[cell setAnalyticsCardDisplayed:YES];[self.window addSubview:cell];
    AwaitPreparedCanvases(cell);BAAnalyticsCanvasView *canvas=(id)cell.analyticsCardContentView;
    NSArray *kept=[[canvas valueForKey:@"displayIndices"] objectForKey:metric];
    Require(kept.count<=192 && [kept containsObject:@1] && [kept containsObject:@2] && [kept containsObject:@3] && [kept containsObject:@(points.count-1)],@"Clipped endpoint displaced actual first/last/min/max in-window readings");
    [cell setAnalyticsCardDisplayed:NO];[cell removeFromSuperview];[cells analyticsCardDidReceiveMemoryWarning];
    BAAnalyticsCanvasCard *live=(id)BAAnalyticsCreateLiveCanvasCards().firstObject;live.historyService=history;
    cell=[[BAAnalyticsCardCell alloc] initWithFrame:CGRectMake(0,0,346,346)];
    [cell configureWithCard:live size:BAAnalyticsCardSize2x2 editing:NO];[cell setAnalyticsCardDisplayed:YES];[self.window addSubview:cell];
    [cell applyMetricSnapshot:BAFixtureSnapshot(NO)];AwaitPreparedCanvases(cell);canvas=(id)cell.analyticsCardContentView;
    Require(!canvas.detailEnabled && canvas.hitRegions.count<=52,@"Read-only live canvas produced unbounded/unused actions");
    for (id track in [canvas valueForKey:@"tracks"]) {
        NSArray<BAAnalyticsMetricPoint *> *raw=[track valueForKey:@"points"];NSIndexSet *markers=[track valueForKey:@"markerIndices"],*accessible=[track valueForKey:@"accessibleIndices"];
        Require(raw.count==61 && markers.count<=4 && accessible.count<=16,@"Live trend reduction altered raw counts or exceeded marker/VoiceOver budget");
        NSUInteger lo=0,hi=0;for (NSUInteger index=1;index<raw.count;index++) {
            if ([raw[index] value]<[raw[lo] value]) lo=index;if ([raw[index] value]>[raw[hi] value]) hi=index;
        }
        Require([markers containsIndex:0]&&[markers containsIndex:raw.count-1]&&[markers containsIndex:lo]&&[markers containsIndex:hi],@"Live trend lost observed endpoints or extrema");
    }
    [self capturePerformanceCard:live size:BAAnalyticsCardSize2x2 name:@"performance-current-battery-trend.png"];
    [cell setAnalyticsCardDisplayed:NO];[cell removeFromSuperview];[live analyticsCardDidReceiveMemoryWarning];
    self.performanceResults[@"fragmentedAndLiveDrawingBudgets"] = @YES;
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
    [self testScrollRecyclingWithReport:report];
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
            Require(raw.count == count && indices.count <= 128, @"Capacity display envelope truncated raw evidence or exceeded its vertex budget");
            NSArray *markers = [canvas valueForKey:@"displayMarkerIndices"];
            Require(markers.count <= 12 && [markers containsObject:@0] && [markers containsObject:@(count-1)] &&
                [markers containsObject:@1777] && [markers containsObject:@5333],@"Capacity circles lost endpoints/extrema or exceeded their budget");
            self.performanceResults[@"capacityMarkerCount"] = @(markers.count);
            self.performanceResults[@"capacityDisplayPoints"] = @(indices.count);
            Require([indices containsObject:@1777] && [indices containsObject:@5333], @"Capacity display envelope lost isolated minimum/maximum");
            Require([[canvas valueForKey:@"boundaryIndices"] count] > 0 && [[canvas valueForKey:@"displayGaps"] count] > 0,
                @"Capacity display lost configuration boundaries or missing spans");
            double missing=0;for(NSValue *value in [canvas valueForKey:@"displayGaps"])missing+=value.CGRectValue.size.width;
            Require(fabs(missing-FixtureMissingFraction(capacityFamily))<1e-6,@"Short capacity source gaps expanded into unobserved multi-day spans");
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
            NSUInteger totalDisplay = 0;
            for (NSNumber *value in displayCounts.allValues) totalDisplay += value.unsignedIntegerValue;
            Require(totalDisplay <= 192 && [[canvas valueForKey:@"marks"] count] <= 4*[[canvas valueForKey:@"visibleMetrics"] count],
                @"Dense cell channels exceeded the shared line/marker budget");
            for (NSString *metric in displayChannels) for (NSNumber *index in displayChannels[metric]) {
                BAAnalyticsObservation *observation = rawChannels[metric][index.unsignedIntegerValue];
                if (observation.identifier) [shown addObject:observation.identifier];
            }
            Require([shown containsObject:@"performance.cells.1234"] && [shown containsObject:@"performance.cells.5678"],
                @"Cell display envelope lost isolated voltage minimum/maximum");
            Require([[canvas valueForKey:@"untrustedRects"] count] > 0, @"Cell voltage display lost the missing sampled spans");
            double missing=0;for(NSValue *value in [canvas valueForKey:@"untrustedRects"])missing+=value.CGRectValue.size.width;
            CGRect plot=[[canvas valueForKey:@"plotRect"] CGRectValue];
            Require(fabs(missing/plot.size.width-FixtureMissingFraction(cellsFamily))<1e-6,@"Short cell source gaps expanded into unobserved multi-hour spans");
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
            [canvas.layer displayIfNeeded];
            NSArray *before = canvas.hitRegions;
            [card configureAnalyticsCardContentView:canvas forSize:size editing:NO];
            Require(!canvas.layer.needsDisplay && canvas.hitRegions == before,@"Unchanged host configuration forced a statistical repaint");
            [canvas setNeedsDisplay]; [canvas.layer displayIfNeeded];
            Require(before.count == canvas.hitRegions.count,@"Statistical repaint changed the evidence population");
            for (NSUInteger index=0;index<before.count;index++)
                Require([before[index] selection] == canvas.hitRegions[index].selection,@"Statistical repaint serialized the same immutable evidence again");
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
    [self testDrawingBudgetsWithReport:report];
    [self testProcessRenderingCaches];
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
    NSMutableDictionary *result=[@{@"synthetic":@YES,@"nativeDarkMode":@(FixtureNativeDarkMode),@"renderings":self.manifest,
        @"checks":checks,@"passed":@(passed)} mutableCopy];
    if (self.performanceResults) result[@"performance"]=self.performanceResults;
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[self.output stringByAppendingPathComponent:@"validation.json"] atomically:YES];
}
- (void)runChecks {
    BOOL cellsOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_CELLS_ONLY"] isEqual:@"1"];
    BOOL capacityOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_CAPACITY_ONLY"] isEqual:@"1"];
    BOOL historyOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_HISTORY_ONLY"] isEqual:@"1"];
    BOOL performanceOnly = [NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_PERFORMANCE_ONLY"] isEqual:@"1"];
    NSArray<NSString *> *checks = performanceOnly ? @[@"actual host lifecycle, editing, navigation and frozen optional details",
        @"scroll round-trip canvas retention, touch cancellation and deferred latest-only refresh",
        @"8000-record Foundation-only history generated off main",@"bounded Capacity/Cells display and VoiceOver marks with raw extrema and gaps retained",
        @"asynchronous statistics, responsive main queue, generation coalescing and memory cleanup",@"pure history snapshots preserve derived results",
        @"cached startup preserves acquisition timestamps and refreshes paired geometry/report/details",@"dense independent comparison keeps full statistics with bounded drawing/actions",@"dense event sweep agrees with full overlap and gap-boundary predicates",@"asynchronous full exact evidence selection",@"strict gap indexing, mutable inputs and fresh service cache reentry",@"real history publication and lazy host activation"] : historyOnly ? @[@"real asynchronous history publication and visible canvas lifecycle",@"lazy host history activation after a missed BecomeActive notification"] :
        @[@"actual plugin registration",@"legacy layout migration",@"all supported sizes",@"320/390/430 container widths",@"native or fallback dark palette",@"accessibility text size",@"partial/unavailable data",
          @"selected evidence navigation",@"seven optional visual details and frozen evidence",@"gettext catalog translations in Chinese and German",@"system battery colors and 20-percent threshold",
          @"full canvas editing with sibling accessory stacking and hit routing",@"readings / plot annotation separation",@"44-point accessibility targets and equivalent activation",
          @"editing suppresses card touch, embedded gestures and accessibility actions",@"resize/remove/add/reorder/persistence",@"visible-only subscriptions",
          @"current capacity detail without history and no mixed-source capacity ratios",@"bounded capacity history browsing, exact reading selection and resize consistency",@"real asynchronous history publication and visible canvas lifecycle",@"lazy host history activation after a missed BecomeActive notification"];
    checks = [checks arrayByAddingObject:@"production reader cable transitions and independent source gaps survive canvas filtering"];
    checks = [checks arrayByAddingObject:@"delayed external completion preserves edited layout and restores placeholders after editing/dragging"];
    @try {
        NSString *focusedFamilies = NSProcessInfo.processInfo.environment[@"BATTMAN_ANALYTICS_VISUAL_FAMILIES"];
        if (focusedFamilies.length) {
            NSSet *families = [NSSet setWithArray:[focusedFamilies componentsSeparatedByString:@","]];
            self.cards = [self.cards filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(BAAnalyticsCanvasCard *card, NSDictionary *bindings) {
                return [families containsObject:card.familyIdentifier];
            }]];
            Require(self.cards.count == families.count, @"Unknown family requested for focused presentation check");
            for (NSString *language in @[@"en", @"zh_CN", @"de"]) {
                FixtureLanguage = language;
                [self renderCardsAtWidth:320 scenario:@"ready" allSizes:YES];
            }
            FixtureLanguage = @"en";
            [self renderCardsAtWidth:430 scenario:@"ready" allSizes:YES];
            ForcedStyle = UIUserInterfaceStyleDark;
            [self renderCardsAtWidth:390 scenario:@"ready" allSizes:YES];
            ForcedStyle = UIUserInterfaceStyleLight;
            ForcedCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
            [self renderCardsAtWidth:320 scenario:@"ready" allSizes:YES];
            ForcedCategory = nil;
            [self writeValidationWithChecks:@[@"focused family supported sizes and localized presentation", @"native appearance traits and embedded large-text scroll insets"] passed:YES];
            [@"PASS" writeToFile:[self.output stringByAppendingPathComponent:@"analytics-v3.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        if (cellsOnly) {
            [self testCellsCurrentFallback];
            [self testSessionSingletonFallback];
            [self writeValidationWithChecks:@[@"same-acquisition single/multiple/cached/missing current cells",@"historical cell chart and details preserved",@"supported sizes, annotation separation, localized provenance and accessible summary",@"newest singleton retains previous drawable session and accurate frozen selection",@"editing suppresses fallback session actions",@"one complete comparison session renders an estimate without a statistical box"] passed:YES];
            [@"PASS" writeToFile:[self.output stringByAppendingPathComponent:@"analytics-v3.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        if (capacityOnly) {
            [self testCapacityCurrentDetail]; [self testCapacityHistoryBrowsing];
            [self writeValidationWithChecks:@[@"capacity overview and historical selection keep chart, readings and exact evidence consistent"] passed:YES];
            [@"PASS" writeToFile:[self.output stringByAppendingPathComponent:@"analytics-v3.status"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        [self testDelayedExternalCards];
        if (performanceOnly) {
            [self testRegistrationAndMigration]; [self testHost]; [self testFamilyDetails]; [self testCapacityCurrentDetail]; [self testCapacityHistoryBrowsing];
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
        [self testCapacityCurrentDetail]; [self testCapacityHistoryBrowsing];
        }
        [self testReaderCableEventsAndIndependentGaps];
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
