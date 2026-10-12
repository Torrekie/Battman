#import "main.h"
#import "BAAnalyticsPathCanvasCard.h"
#import "BAAnalyticsProcessDrawing.h"
#include <math.h>

@interface BAAnalyticsPathCanvasView : BAAnalyticsCanvasView
@property (nonatomic, weak) BAAnalyticsFamilyReport *preparedFamily;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *preparedLatest;
@property (nonatomic) BOOL preparedTraceRange;
@property (nonatomic) double preparedTraceMinimum;
@property (nonatomic) double preparedTraceMaximum;
@end

@implementation BAAnalyticsPathCanvasView

- (void)setLatestReport:(BAAnalyticsReport *)latestReport {
    if (!latestReport || latestReport != self.latestReport) {
        self.preparedFamily = nil; self.preparedLatest = nil;
        self.preparedTraceRange = NO; self.preparedTraceMinimum = 0; self.preparedTraceMaximum = 0;
        BAProcessClearDisplayCaches(self);
    }
    [super setLatestReport:latestReport];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

// Every point is selected independently from normalized rows. This never
// pretends that input and battery readings occurred at the same timestamp.
- (BAAnalyticsObservation *)latestObservationForMetric:(NSString *)metric report:(BAAnalyticsFamilyReport *)family {
    if (self.preparedFamily != family || !self.preparedLatest) {
        self.preparedFamily = family;
        self.preparedLatest = [NSMutableDictionary dictionary];
        self.preparedTraceRange = NO;
    }
    id cached = self.preparedLatest[metric];
    if (cached) return cached == NSNull.null ? nil : cached;
    BAAnalyticsObservation *latest = nil;
    id payload = family.payload[BAAnalyticsPayloadLatestObservation];
    if ([payload isKindOfClass:[BAAnalyticsObservation class]] && BAProcessValue(payload, metric)) latest = payload;
    for (BAAnalyticsObservation *observation in family.window.observations) {
        if (!BAProcessValue(observation, metric)) continue;
        if (!latest || [observation.timestamp compare:latest.timestamp] == NSOrderedDescending) latest = observation;
    }
    if (latest && ([latest.timestamp compare:family.window.startDate] == NSOrderedAscending || [latest.timestamp compare:family.window.endDate] == NSOrderedDescending)) latest = nil;
    self.preparedLatest[metric] = latest ?: (id)NSNull.null;
    return latest;
}

- (BAAnalyticsDetailSelection *)selectionForMetric:(NSString *)metric observation:(BAAnalyticsObservation *)observation family:(BAAnalyticsFamilyReport *)family {
    NSArray *metrics;
    if ([metric isEqualToString:BAAnalyticsHistoryInputPowerWatts]) {
        metrics = @[metric, BAAnalyticsHistoryInputCurrentMilliamps, BAAnalyticsHistoryInputVoltageMillivolts];
    } else if ([metric isEqualToString:BAAnalyticsHistoryBatteryPowerWatts]) {
        metrics = @[metric, BAAnalyticsHistoryCurrentMilliamps, BAAnalyticsHistoryVoltageMillivolts];
    } else {
        metrics = @[metric];
    }
    return BAProcessSelection(self, observation ? @"record" : @"metric", observation ? @[observation.identifier] : @[], metrics,
        observation ? observation.timestamp : family.window.startDate,
        observation ? observation.timestamp : family.window.endDate,
        @{@"measurementPoint":metric, @"signedPower":@YES, @"independentTimestamps":@YES});
}

- (void)drawColumn:(CGRect)column metric:(NSString *)metric label:(NSString *)label
       observation:(BAAnalyticsObservation *)observation family:(BAAnalyticsFamilyReport *)family
           minimum:(double)minimum maximum:(double)maximum color:(UIColor *)color
            regions:(NSMutableArray<BAAnalyticsCanvasHitRegion *> *)regions compact:(BOOL)compact {
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSNumber *value = BAProcessValue(observation, metric);
    CGFloat zeroY = CGRectGetMaxY(column) - (0 - minimum) / (maximum - minimum) * CGRectGetHeight(column);
    CGFloat center = CGRectGetMidX(column);
    CGRect bar = CGRectMake(center - 17, CGRectGetMinY(column), 34, CGRectGetHeight(column));
    if (value) {
        CGFloat valueY = CGRectGetMaxY(column) - (value.doubleValue - minimum) / (maximum - minimum) * CGRectGetHeight(column);
        bar = CGRectMake(center - 17, MIN(zeroY, valueY), 34, MAX(2, fabs(zeroY - valueY)));
        if (context) {
            CGContextSetFillColorWithColor(context, [color colorWithAlphaComponent:0.72].CGColor);
            CGContextFillRect(context, bar);
        }
        NSString *reading = [NSString stringWithFormat:[metric isEqualToString:BAAnalyticsHistoryBatteryPowerWatts] ? _("%+.2f W") : _("%.2f W"), value.doubleValue];
        UIFont *readingFont = BAProcessFont(UIFontTextStyleHeadline, compact ? 15 : 18, UIFontWeightSemibold);
        BAProcessText(reading, CGRectMake(CGRectGetMinX(column) - 6, CGRectGetMinY(column) - readingFont.lineHeight - 2,
            CGRectGetWidth(column) + 12, readingFont.lineHeight + 2), readingFont, color, NSTextAlignmentCenter);
    } else {
        BAProcessHatch(bar, UIColor.compatSecondaryLabelColor);
        BAProcessText(_("Unavailable"), CGRectMake(CGRectGetMinX(column) - 6, CGRectGetMinY(column) - 23, CGRectGetWidth(column) + 12, 28),
            BAProcessFont(UIFontTextStyleCaption1, 11, UIFontWeightRegular), UIColor.compatSecondaryLabelColor, NSTextAlignmentCenter);
    }
    if (context) {
        CGContextSetStrokeColorWithColor(context, UIColor.compatSeparatorColor.CGColor);
        CGContextSetLineWidth(context, 1);
        CGContextMoveToPoint(context, CGRectGetMinX(column), zeroY);
        CGContextAddLineToPoint(context, CGRectGetMaxX(column), zeroY);
        CGContextStrokePath(context);
    }
    CGRect nameRect = CGRectMake(CGRectGetMinX(column) - 6, CGRectGetMaxY(column) + 5, CGRectGetWidth(column) + 12, compact ? 45 : 32);
    BAProcessText(label, nameRect, BAProcessFont(UIFontTextStyleCaption1, 11, UIFontWeightMedium), color, NSTextAlignmentCenter);
    CGRect hit = CGRectUnion(bar, nameRect);
    NSString *accessibility = [NSString stringWithFormat:_("%@, %@%@"), label,
        value ? [NSString stringWithFormat:_("%+.3f watts"), value.doubleValue] : _("unavailable"),
        observation ? [NSString stringWithFormat:_(", observed %@"), BAProcessWindow(observation.timestamp, observation.timestamp)] : @""];
    [regions addObject:BAProcessRegion(hit, [self selectionForMetric:metric observation:observation family:family], accessibility)];
}

- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderCanvas {
    NSMutableArray *regions = [NSMutableArray array];
    BAAnalyticsFamilyReport *family = BAProcessFamily(self);
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    if (width < 60 || height < 60) return regions;
    BOOL large = BAProcessLargeText(self);
    BOOL tall = self.cardSize == BAAnalyticsCardSize2x2;
    UIFont *caption = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
        scaledFontForFont:[UIFont systemFontOfSize:11] maximumPointSize:large ? 16 : 19];
    UIColor *muted = UIColor.compatSecondaryLabelColor;
    if (!family || family.availability == BAAnalyticsReportAvailabilityLoading || family.availability == BAAnalyticsReportAvailabilityUnavailable) {
        BAProcessText(_("Measurement points · W"), CGRectMake(14, 12, width - 28, 50), BAProcessFont(UIFontTextStyleHeadline, 16, UIFontWeightMedium), UIColor.compatLabelColor, NSTextAlignmentLeft);
        BAProcessHatch(CGRectMake(20, 66, width - 40, MAX(10, height - 110)), muted);
        BAProcessText(BAProcessAvailability(family), CGRectMake(14, height - 42, width - 28, 40), caption, muted, NSTextAlignmentLeft);
        self.accessibilityLabel = [NSString stringWithFormat:_("Measurement points in watts, %@"), BAProcessAvailability(family)];
        return regions;
    }
    BAAnalyticsObservation *input = [self latestObservationForMetric:BAAnalyticsHistoryInputPowerWatts report:family];
    BAAnalyticsObservation *battery = [self latestObservationForMetric:BAAnalyticsHistoryBatteryPowerWatts report:family];
    BAAnalyticsObservation *budget = [self latestObservationForMetric:BAAnalyticsHistoryPowerBudgetWatts report:family];
    BAAnalyticsObservation *target = [self latestObservationForMetric:BAAnalyticsHistoryPowerTargetWatts report:family];
    BOOL partial = !input || !battery || family.availability == BAAnalyticsReportAvailabilityPartial;
    NSString *status = [NSString stringWithFormat:@"%@%@", BAProcessWindow(family.window.startDate, family.window.endDate), partial ? _(" · partial") : @""];
    CGFloat headerHeight = large ? 34 : 18;
    BAProcessText(status, CGRectMake(12, 8, width - 24, headerHeight), caption, muted, NSTextAlignmentLeft);
    // Large text gets two reading panels with less chart decoration. Values
    // retain their units; exact times and every target remain accessible.
    if (large) {
        CGFloat rowHeight = MAX(26, (height - headerHeight - 32) / 2.0);
        NSArray *records = @[input ?: (id)NSNull.null, battery ?: (id)NSNull.null];
        NSArray *metrics = @[BAAnalyticsHistoryInputPowerWatts, BAAnalyticsHistoryBatteryPowerWatts];
        NSArray *labels = @[_("Input"), _("Net")];
        UIFont *readingFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:14 weight:UIFontWeightMedium] maximumPointSize:24];
        for (NSUInteger i = 0; i < 2; i++) {
            id record = records[i];
            BAAnalyticsObservation *observation = record == NSNull.null ? nil : record;
            NSNumber *value = BAProcessValue(observation, metrics[i]);
            CGRect row = CGRectMake(14, headerHeight + 10 + i * rowHeight, width - 28, rowHeight);
            NSString *reading = value ? [NSString stringWithFormat:_("%@  %+.3g W"), labels[i], value.doubleValue] : [NSString stringWithFormat:_("%@  — W"), labels[i]];
            if (!value) BAProcessHatch(row, muted);
            BAProcessText(reading, row, readingFont, i == 0 ? UIColor.compatBlueColor : UIColor.compatGreenColor, NSTextAlignmentLeft);
            [regions addObject:BAProcessRegion(row, [self selectionForMetric:metrics[i] observation:observation family:family],
                [NSString stringWithFormat:_("%@, %@"), i == 0 ? _("Input") : _("Battery net"), value ? reading : _("unavailable")] )];
        }
        if (budget || target) {
            CGRect targets = CGRectMake(14, height - 22, width - 28, 20);
            CGContextRef context = UIGraphicsGetCurrentContext();
            if (context) {
                CGContextSaveGState(context);
                CGFloat dash[] = {4, 3};
                CGContextSetLineDash(context, 0, dash, 2);
                CGContextSetStrokeColorWithColor(context, UIColor.compatBlueColor.CGColor);
                CGContextMoveToPoint(context, CGRectGetMinX(targets), CGRectGetMidY(targets));
                CGContextAddLineToPoint(context, CGRectGetMinX(targets) + 20, CGRectGetMidY(targets));
                CGContextStrokePath(context);
                CGContextRestoreGState(context);
            }
            BAProcessText(_("Targets"), CGRectMake(40, height - 23, width - 54, 22), caption, UIColor.compatBlueColor, NSTextAlignmentLeft);
            NSMutableArray *targetIDs = [NSMutableArray array], *targetMetrics = [NSMutableArray array];
            if (budget) { [targetIDs addObject:budget.identifier]; [targetMetrics addObject:BAAnalyticsHistoryPowerBudgetWatts]; }
            if (target) { [targetIDs addObject:target.identifier]; [targetMetrics addObject:BAAnalyticsHistoryPowerTargetWatts]; }
            [regions addObject:BAProcessRegion(targets, BAProcessSelection(self, @"record", targetIDs, targetMetrics,
                family.window.startDate, family.window.endDate, @{@"targetOnly":@YES}), _("Dashed lines show budget and power targets"))];
        }
        self.accessibilityLabel = [NSString stringWithFormat:_("Measurement points, %@. Each point has its own observation time. Targets use dashed lines."), status];
        return regions;
    }
    double minimum = 0, maximum = 0;
    NSArray *records = @[input ?: (id)NSNull.null, battery ?: (id)NSNull.null, budget ?: (id)NSNull.null, target ?: (id)NSNull.null];
    NSArray *metrics = @[BAAnalyticsHistoryInputPowerWatts, BAAnalyticsHistoryBatteryPowerWatts, BAAnalyticsHistoryPowerBudgetWatts, BAAnalyticsHistoryPowerTargetWatts];
    for (NSUInteger i = 0; i < records.count; i++) {
        if (records[i] == NSNull.null) continue;
        double value = BAProcessValue(records[i], metrics[i]).doubleValue;
        minimum = MIN(minimum, value); maximum = MAX(maximum, value);
    }
    double range = maximum - minimum;
    if (!(range > 0)) { minimum = -1; maximum = 1; }
    else { if (minimum < 0) minimum -= range * 0.1; maximum += range * 0.25; }
    CGFloat top = headerHeight + 39;
    CGFloat chartBottom = tall ? MIN(height * 0.52, height - 140) : height - 47;
    chartBottom = MAX(top + 24, chartBottom);
    CGRect inputColumn = CGRectMake(26, top, width * 0.43 - 26, chartBottom - top);
    CGRect batteryColumn = CGRectMake(width * 0.57, top, width * 0.43 - 26, chartBottom - top);
    [self drawColumn:inputColumn metric:BAAnalyticsHistoryInputPowerWatts label:_("Input") observation:input family:family minimum:minimum maximum:maximum color:UIColor.compatBlueColor regions:regions compact:NO];
    [self drawColumn:batteryColumn metric:BAAnalyticsHistoryBatteryPowerWatts label:_("Battery net") observation:battery family:family minimum:minimum maximum:maximum color:UIColor.compatGreenColor regions:regions compact:NO];
    CGContextRef context = UIGraphicsGetCurrentContext();
    // Budget and target each retain their own source row/time and are dashed.
    for (NSUInteger i = 0; i < 2; i++) {
        BAAnalyticsObservation *observation = i == 0 ? budget : target;
        NSString *metric = i == 0 ? BAAnalyticsHistoryPowerBudgetWatts : BAAnalyticsHistoryPowerTargetWatts;
        NSNumber *value = BAProcessValue(observation, metric);
        if (!value) continue;
        CGFloat y = chartBottom - (value.doubleValue - minimum) / (maximum - minimum) * (chartBottom - top);
        CGRect mark = CGRectMake(CGRectGetMinX(inputColumn), y - 1, CGRectGetWidth(inputColumn), 2);
        if (context) {
            CGContextSaveGState(context);
            CGFloat dash[] = {i == 0 ? 5 : 2, 3};
            CGContextSetLineDash(context, 0, dash, 2);
            CGContextSetLineWidth(context, 1.5);
            CGContextSetStrokeColorWithColor(context, (i == 0 ? UIColor.compatBlueColor : UIColor.compatLabelColor).CGColor);
            CGContextMoveToPoint(context, CGRectGetMinX(mark), y);
            CGContextAddLineToPoint(context, CGRectGetMaxX(mark), y);
            CGContextStrokePath(context);
            CGContextRestoreGState(context);
        }
        [regions addObject:BAProcessRegion(mark, [self selectionForMetric:metric observation:observation family:family],
            [NSString stringWithFormat:_("%@ target, %.3f W, observed %@"), i == 0 ? _("Budget") : _("Power"), value.doubleValue, BAProcessClock(observation.timestamp)])];
    }
    if (!tall) {
        // Independent exact acquisition times are retained in each selectable mark.
        NSMutableArray *targets = [NSMutableArray array];
        if (budget) [targets addObject:[NSString stringWithFormat:_("Budget %.3g W"), BAProcessValue(budget, BAAnalyticsHistoryPowerBudgetWatts).doubleValue]];
        if (target) [targets addObject:[NSString stringWithFormat:_("Target %.3g W"), BAProcessValue(target, BAAnalyticsHistoryPowerTargetWatts).doubleValue]];
        BAProcessText([targets componentsJoinedByString:_(" · ")], CGRectMake(12, height - 24, width - 24, 20), caption, muted, NSTextAlignmentLeft);
    } else {
        NSMutableArray *targets = [NSMutableArray array];
        if (budget) [targets addObject:[NSString stringWithFormat:_("Budget %.3g W"), BAProcessValue(budget, BAAnalyticsHistoryPowerBudgetWatts).doubleValue]];
        if (target) [targets addObject:[NSString stringWithFormat:_("Target %.3g W"), BAProcessValue(target, BAAnalyticsHistoryPowerTargetWatts).doubleValue]];
        BAProcessText([targets componentsJoinedByString:_(" · ")], CGRectMake(12, chartBottom + 25, width - 24, 20), caption, muted, NSTextAlignmentLeft);
        CGFloat traceTop = chartBottom + 53;
        CGRect plot = CGRectMake(30, traceTop, width - 44, MAX(16, height - traceTop - 30));
        BAProcessText(@"W", CGRectMake(12, traceTop, 24, 20), caption, muted, NSTextAlignmentLeft);
        if (!self.preparedTraceRange) {
            self.preparedTraceMinimum = 0; self.preparedTraceMaximum = 0;
            NSArray *traceMetrics = @[BAAnalyticsHistoryInputPowerWatts, BAAnalyticsHistoryBatteryPowerWatts];
            for (BAAnalyticsObservation *observation in family.window.observations) {
                for (NSString *metric in traceMetrics) {
                    NSNumber *value = BAProcessValue(observation, metric);
                    if (value) {
                        self.preparedTraceMinimum = MIN(self.preparedTraceMinimum, value.doubleValue);
                        self.preparedTraceMaximum = MAX(self.preparedTraceMaximum, value.doubleValue);
                    }
                }
            }
            self.preparedTraceRange = YES;
        }
        double traceMin = MIN(minimum, self.preparedTraceMinimum), traceMax = MAX(maximum, self.preparedTraceMaximum);
        [regions addObjectsFromArray:BAProcessTrace(self, family.window.observations, family.window.intervals, family.window.gaps,
            BAAnalyticsHistoryInputPowerWatts, _("input W"), family.window.startDate, family.window.endDate, plot, traceMin, traceMax, 1, UIColor.compatBlueColor, YES, nil)];
        [regions addObjectsFromArray:BAProcessTrace(self, family.window.observations, family.window.intervals, family.window.gaps,
            BAAnalyticsHistoryBatteryPowerWatts, _("battery net W"), family.window.startDate, family.window.endDate, plot, traceMin, traceMax, 1, UIColor.compatGreenColor, NO, nil)];
        BAProcessText(BAProcessClock(family.window.startDate), CGRectMake(12, height - 24, width / 2 - 12, 20), caption, muted, NSTextAlignmentLeft);
        BAProcessText(BAProcessClock(family.window.endDate), CGRectMake(width / 2, height - 24, width / 2 - 12, 20), caption, muted, NSTextAlignmentRight);
    }
    self.accessibilityLabel = [NSString stringWithFormat:_("Measurement points, %@. Input and battery net are independent measured points. Dashed lines are budget and power targets. Hatched regions are unavailable."), status];
    return regions;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.hitRegions = [self renderCanvas];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect { (void)[self renderCanvas]; }
@end

@implementation BAAnalyticsPathCanvasCard
- (instancetype)init {
    return [super initWithIdentifier:@"com.torrekie.battman.analytics.path" displayName:_("Measurement points")
        familyIdentifier:BAAnalyticsFamilyPath supportedSizes:BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x1];
}
- (BAAnalyticsCanvasView *)makeCanvasView { return [BAAnalyticsPathCanvasView new]; }
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view { [view setNeedsLayout]; [view setNeedsDisplay]; }
@end
