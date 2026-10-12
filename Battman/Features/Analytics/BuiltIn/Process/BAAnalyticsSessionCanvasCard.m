#import "../Canvas/BAAnalyticsDetailViewController.h"
#import "main.h"
#import "BAAnalyticsSessionCanvasCard.h"
#import "BAAnalyticsProcessDrawing.h"
#include <math.h>

// These summaries use the session's normalized evidence only. In particular,
// observation counts do not substitute for elapsed per-metric coverage.
static NSTimeInterval BASessionCoverage(BAAnalyticsHistorySession *session, NSString *metric) {
    NSArray<BAAnalyticsHistoryInterval *> *ordered = BAProcessOrderedIntervals(session.intervals);
    NSDate *unionStart = nil;
    NSDate *unionEnd = nil;
    NSTimeInterval covered = 0;
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[metric], session.gaps)) continue;
        NSDate *start = [interval.startDate compare:session.startDate] == NSOrderedAscending ? session.startDate : interval.startDate;
        NSDate *end = [interval.endDate compare:session.endDate] == NSOrderedDescending ? session.endDate : interval.endDate;
        if ([end compare:start] != NSOrderedDescending) continue;
        if (!unionStart) {
            unionStart = start;
            unionEnd = end;
        } else if ([start compare:unionEnd] != NSOrderedDescending) {
            if ([end compare:unionEnd] == NSOrderedDescending) unionEnd = end;
        } else {
            covered += [unionEnd timeIntervalSinceDate:unionStart];
            unionStart = start;
            unionEnd = end;
        }
    }
    if (unionStart) covered += [unionEnd timeIntervalSinceDate:unionStart];
    return covered;
}

static NSArray<BAAnalyticsObservation *> *BASessionMetricObservations(BAAnalyticsHistorySession *session, NSString *metric) {
    NSMutableArray *observations = [NSMutableArray array];
    for (BAAnalyticsObservation *observation in session.observations) {
        if (!BAProcessValue(observation, metric) ||
            [observation.timestamp compare:session.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:session.endDate] == NSOrderedDescending) continue;
        [observations addObject:observation];
    }
    for (NSUInteger i = 1; i < observations.count; i++) {
        BAAnalyticsObservation *left = observations[i - 1], *right = observations[i];
        if ([left.timestamp compare:right.timestamp] == NSOrderedDescending)
            return [observations sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
                return [a.timestamp compare:b.timestamp];
            }];
    }
    return observations;
}

static void BASessionRange(NSArray<BAAnalyticsObservation *> *observations, NSString *metric,
        double divisor, BOOL includeZero, double *minimum, double *maximum) {
    double low = INFINITY, high = -INFINITY;
    for (BAAnalyticsObservation *observation in observations) {
        double value = BAProcessValue(observation, metric).doubleValue / divisor;
        low = MIN(low, value);
        high = MAX(high, value);
    }
    if (!isfinite(low) || !isfinite(high)) { *minimum = 0; *maximum = 1; return; }
    if (includeZero) { low = MIN(0, low); high = MAX(0, high); }
    // Padding is a drawing scale, never a substitute measurement.
    double padding = MAX((high - low) * 0.15, includeZero ? 0.05 : 0.5);
    *minimum = low - padding;
    *maximum = high + padding;
}

static BAAnalyticsObservation *BASessionPeak(NSArray<BAAnalyticsObservation *> *observations, NSString *metric) {
    BAAnalyticsObservation *peak = nil;
    for (BAAnalyticsObservation *observation in observations) {
        if (!peak || BAProcessValue(observation, metric).doubleValue > BAProcessValue(peak, metric).doubleValue) peak = observation;
    }
    return peak;
}



@interface BASessionCanvasView : BAAnalyticsCanvasView
- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderCanvasWithAccessibilityValue:(NSString * _Nullable * _Nullable)value;
@end

@implementation BASessionCanvasView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.accessibilityLabel = _("Connected session");
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSString *summary = nil;
    NSArray *regions = [self renderCanvasWithAccessibilityValue:&summary];
    self.accessibilityLabel = [NSString stringWithFormat:_("Connected session. %@"), summary ?: _("Waiting for layout")];
    self.hitRegions = regions;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [self renderCanvasWithAccessibilityValue:NULL];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderCanvasWithAccessibilityValue:(NSString **)accessibilityValue {
    NSMutableArray<BAAnalyticsCanvasHitRegion *> *regions = [NSMutableArray array];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    if (width < 40 || height < 40) return regions;
    BAAnalyticsFamilyReport *family = BAProcessFamily(self);
    BAAnalyticsHistorySession *session = BAProcessSession(family, @"connected");
    UIFont *caption = BAProcessFont(UIFontTextStyleCaption1, 11, UIFontWeightRegular);
    UIFont *mark = BAProcessFont(UIFontTextStyleCaption1, 12, UIFontWeightSemibold);
    UIColor *muted = UIColor.compatSecondaryLabelColor;
    NSArray<NSString *> *metrics = @[BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryTemperatureCelsius, BAAnalyticsHistoryCurrentMilliamps];
    if (!session || [session.endDate compare:session.startDate] != NSOrderedDescending) {
        NSString *status = BAProcessAvailability(family);
        if (session) status = _("No valid session time range");
        NSString *window = family ? BAProcessWindow(family.window.startDate, family.window.endDate) : _("History time range unavailable");
        BAProcessText(window, CGRectMake(12, 10, width - 24, caption.lineHeight * 2), caption, muted, NSTextAlignmentLeft);
        CGRect empty = CGRectMake(48, caption.lineHeight * 2 + 18, width - 60, MAX(20, height - caption.lineHeight * 4 - 30));
        BAProcessHatch(empty, muted);
        BAProcessText(_("SOC %\n°C\nA ±"), CGRectMake(12, CGRectGetMinY(empty), 36, CGRectGetHeight(empty)), caption, muted, NSTextAlignmentLeft);
        BAProcessText(status, CGRectInset(empty, 6, 6), mark, muted, NSTextAlignmentCenter);
        BAAnalyticsDetailSelection *selection = BAProcessSelection(self, _("unavailable"), @[], metrics,
            family.window.startDate, family.window.endDate, @{@"availability": status});
        [regions addObject:BAProcessRegion(self.bounds, selection, [NSString stringWithFormat:_("%@. %@"), status, window])];
        if (accessibilityValue) *accessibilityValue = [NSString stringWithFormat:_("%@. %@. No verified readings."), status, window];
        return regions;
    }

    NSArray<BAAnalyticsObservation *> *soc = BASessionMetricObservations(session, BAAnalyticsHistorySOCPercent);
    NSArray<BAAnalyticsObservation *> *temperature = BASessionMetricObservations(session, BAAnalyticsHistoryTemperatureCelsius);
    NSArray<BAAnalyticsObservation *> *current = BASessionMetricObservations(session, BAAnalyticsHistoryCurrentMilliamps);
    BAAnalyticsObservation *peak = BASessionPeak(temperature, BAAnalyticsHistoryTemperatureCelsius);
    NSTimeInterval duration = [session.endDate timeIntervalSinceDate:session.startDate];
    NSTimeInterval socCoverage = BASessionCoverage(session, BAAnalyticsHistorySOCPercent);
    NSTimeInterval temperatureCoverage = BASessionCoverage(session, BAAnalyticsHistoryTemperatureCelsius);
    NSTimeInterval currentCoverage = BASessionCoverage(session, BAAnalyticsHistoryCurrentMilliamps);
    BOOL partial = !session.startBoundaryKnown || !session.endBoundaryKnown || session.gaps.count > 0 ||
        socCoverage + 0.001 < duration || temperatureCoverage + 0.001 < duration || currentCoverage + 0.001 < duration;
    NSString *window = BAProcessWindow(session.startDate, session.endDate);
    NSString *boundary = session.startBoundaryKnown && session.endBoundaryKnown ? _("sampled boundaries") : _("partial boundaries");
    NSString *coverage = [NSString stringWithFormat:_("Covered SOC %@; °C %@; A %@ / %@"),
        BAProcessDuration(socCoverage), BAProcessDuration(temperatureCoverage), BAProcessDuration(currentCoverage), BAProcessDuration(duration)];
    NSString *socSummary = soc.count ? [NSString stringWithFormat:_("SOC %.0f → %.0f%%"), BAProcessValue(soc.firstObject, BAAnalyticsHistorySOCPercent).doubleValue,
        BAProcessValue(soc.lastObject, BAAnalyticsHistorySOCPercent).doubleValue] : _("SOC unavailable");
    NSString *temperatureSummary = peak ? [NSString stringWithFormat:_("Observed peak %.1f °C"), BAProcessValue(peak, BAAnalyticsHistoryTemperatureCelsius).doubleValue] : _("Temperature unavailable");
    NSString *currentSummary = current.count ? [NSString stringWithFormat:_("Last %+.2f A"), BAProcessValue(current.lastObject, BAAnalyticsHistoryCurrentMilliamps).doubleValue / 1000.0] : _("Current unavailable");
    NSDictionary *sessionContext = @{@"sessionIdentifier": session.identifier, @"boundaryEstimate": @YES,
        @"startBoundaryKnown": @(session.startBoundaryKnown), @"endBoundaryKnown": @(session.endBoundaryKnown)};
    BAAnalyticsDetailSelection *sessionSelection = BAProcessSelection(self, @"session", @[], metrics, session.startDate, session.endDate, sessionContext);
    if (accessibilityValue) *accessibilityValue = [NSString stringWithFormat:
        _("%@. Approximately %@, %@, %@. %@. %@. %@. %@. %lu source records. Positive current charges the battery; negative current discharges it. State changes are sampled bounds; hatching means missing observations."),
        window, BAProcessDuration(duration), boundary, partial ? _("partial observations") : _("covered observations"), socSummary, temperatureSummary,
        currentSummary, coverage, (unsigned long)session.observations.count];

    // Larger text keeps directly selectable evidence instead of shrinking every
    // track label to fit the same small plot. Normal text retains all three
    // tracks; the square canvas provides more room for axis and peak labels.
    BOOL largeText = BAProcessLargeText(self);
    BOOL tall = self.cardSize == BAAnalyticsCardSize2x2;
    CGFloat headerHeight = caption.lineHeight + 8;
    BAProcessText(window, CGRectMake(12, 8, width - 24, caption.lineHeight + 2), caption, muted, NSTextAlignmentLeft);
    [regions addObject:BAProcessRegion(CGRectMake(12, 4, width - 24, headerHeight), sessionSelection,
        [NSString stringWithFormat:_("Connected session, %@, %@"), window, boundary])];

    if (largeText && !tall) {
        NSArray *labels = @[
            soc.count ? [NSString stringWithFormat:_("SOC %.0f → %.0f%%"), BAProcessValue(soc.firstObject, BAAnalyticsHistorySOCPercent).doubleValue,
                BAProcessValue(soc.lastObject, BAAnalyticsHistorySOCPercent).doubleValue] : _("SOC — %"),
            peak ? [NSString stringWithFormat:_("obs. %.1f °C"), BAProcessValue(peak, BAAnalyticsHistoryTemperatureCelsius).doubleValue] : _("— °C"),
            current.count ? [NSString stringWithFormat:_("%+.3g A"), BAProcessValue(current.lastObject, BAAnalyticsHistoryCurrentMilliamps).doubleValue / 1000] : _("— A")];
        NSArray *colors = @[UIColor.compatGreenColor, UIColor.compatOrangeColor, UIColor.compatBlueColor];
        NSArray *selectedRecords = @[
            soc.count ? @[soc.firstObject.identifier, soc.lastObject.identifier] : @[],
            peak ? @[peak.identifier] : @[],
            current.count ? @[current.lastObject.identifier] : @[]];
        CGFloat rowHeight = mark.lineHeight + 3;
        CGFloat y = headerHeight + 6;
        for (NSUInteger index = 0; index < labels.count; index++) {
            CGRect row = index == 0 ? CGRectMake(12, y, width - 24, rowHeight) :
                CGRectMake(index == 1 ? 12 : width / 2, y + rowHeight, width / 2 - 12, rowHeight);
            BAProcessText(labels[index], row, mark, colors[index], NSTextAlignmentLeft);
            BAAnalyticsDetailSelection *selection = BAProcessSelection(self, index == 0 || [selectedRecords[index] count] == 0 ? @"metric" : @"record", selectedRecords[index], @[metrics[index]],
                index == 0 ? session.startDate : (index == 1 ? peak.timestamp : current.lastObject.timestamp),
                index == 0 ? session.endDate : (index == 1 ? peak.timestamp : current.lastObject.timestamp), sessionContext);
            [regions addObject:BAProcessRegion(row, selection, labels[index])];
        }
        y += rowHeight * 2;
        CGFloat stateLeft = 12;
        CGRect stateRect = CGRectMake(stateLeft, y + 2, width - stateLeft - 12, 12);
        BAProcessStateStrip(self, session.intervals, session.gaps, session.startDate, session.endDate, stateRect, session.identifier, regions);
        y = CGRectGetMaxY(stateRect) + 2;
        NSString *shortCoverage = [NSString stringWithFormat:_("Coverage SOC %.0f%% T %.0f%% A %.0f%%"),
            socCoverage / duration * 100, temperatureCoverage / duration * 100, currentCoverage / duration * 100];
        UIFont *coverageFont = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
            scaledFontForFont:[UIFont systemFontOfSize:11] maximumPointSize:14];
        BAProcessText(shortCoverage, CGRectMake(12, y + 2, width - 24, MAX(coverageFont.lineHeight, height - y - 4)), coverageFont, muted, NSTextAlignmentLeft);
        [regions addObject:BAProcessRegion(CGRectMake(12, y, width - 24, MAX(1, height - y)), sessionSelection, coverage)];
        return regions;
    }

    CGFloat footerHeight = caption.lineHeight * (largeText ? 3 : 2) + (tall ? 6 : 2);
    CGFloat stateHeight = tall ? MAX(12, MIN(22, caption.lineHeight + 2)) : 10;
    CGFloat gap = tall ? 14 : 3;
    CGFloat temperatureGap = tall ? MAX(gap, ceil(caption.lineHeight) + 4) : gap;
    // Keep observed endpoint values in their own row. A high SOC must not
    // clamp its annotation into the trace, nor obscure nearby observations.
    CGFloat endpointHeight = soc.count ? ceil(mark.lineHeight) + 4 : 0;
    CGFloat available = MAX(30, height - headerHeight - endpointHeight - footerHeight - stateHeight - 3 * gap - temperatureGap - (tall ? 9 : 4));
    CGFloat left = MAX(40, MIN(65, caption.pointSize * 3.4));
    CGFloat plotWidth = MAX(1, width - left - 13);
    CGFloat endpointY = headerHeight + gap;
    CGFloat y = endpointY + endpointHeight;
    CGRect socPlot = CGRectMake(left, y, plotWidth, available * 0.46);
    y = CGRectGetMaxY(socPlot) + temperatureGap;
    CGRect temperaturePlot = CGRectMake(left, y, plotWidth, available * 0.25);
    y = CGRectGetMaxY(temperaturePlot) + gap;
    CGRect currentPlot = CGRectMake(left, y, plotWidth, available * 0.29);
    CGRect statePlot = CGRectMake(left, CGRectGetMaxY(currentPlot) + gap, plotWidth, stateHeight);
    NSArray *plots = @[[NSValue valueWithCGRect:socPlot], [NSValue valueWithCGRect:temperaturePlot], [NSValue valueWithCGRect:currentPlot]];
    NSArray *units = @[_("SOC %"), @"°C", _("A ±")];
    NSArray *colors = @[UIColor.compatGreenColor, UIColor.compatOrangeColor, UIColor.compatBlueColor];
    NSArray *observed = @[soc, temperature, current];
    double temperatureMinimum, temperatureMaximum, currentMinimum, currentMaximum;
    BASessionRange(temperature, BAAnalyticsHistoryTemperatureCelsius, 1, NO, &temperatureMinimum, &temperatureMaximum);
    BASessionRange(current, BAAnalyticsHistoryCurrentMilliamps, 1000, YES, &currentMinimum, &currentMaximum);
    double minima[] = {0, temperatureMinimum, currentMinimum};
    double maxima[] = {100, temperatureMaximum, currentMaximum};
    double divisors[] = {1, 1, 1000};
    CGContextRef context = UIGraphicsGetCurrentContext();
    for (NSUInteger index = 0; index < plots.count; index++) {
        CGRect plot = [plots[index] CGRectValue];
        BAProcessText(units[index], CGRectMake(10, CGRectGetMinY(plot), left - 13, caption.lineHeight + 2), caption, colors[index], NSTextAlignmentLeft);
        if (context) {
            CGContextSaveGState(context);
            CGContextSetStrokeColorWithColor(context, [UIColor.compatSeparatorColor colorWithAlphaComponent:0.6].CGColor);
            CGContextSetLineWidth(context, 0.6);
            CGContextMoveToPoint(context, CGRectGetMinX(plot), CGRectGetMinY(plot));
            CGContextAddLineToPoint(context, CGRectGetMinX(plot), CGRectGetMaxY(plot));
            CGContextAddLineToPoint(context, CGRectGetMaxX(plot), CGRectGetMaxY(plot));
            CGContextStrokePath(context);
            // The same wall-clock positions extend through all three tracks.
            CGFloat midpoint = BAProcessTimeX([session.startDate dateByAddingTimeInterval:duration * 0.5], session.startDate, session.endDate, plot);
            CGFloat dash[] = {2, 3};
            CGContextSetLineDash(context, 0, dash, 2);
            CGContextMoveToPoint(context, midpoint, CGRectGetMinY(plot));
            CGContextAddLineToPoint(context, midpoint, CGRectGetMaxY(plot));
            CGContextStrokePath(context);
            if (index == 2) {
                CGFloat zeroY = CGRectGetMaxY(plot) - (0 - currentMinimum) / (currentMaximum - currentMinimum) * CGRectGetHeight(plot);
                CGContextMoveToPoint(context, CGRectGetMinX(plot), zeroY);
                CGContextAddLineToPoint(context, CGRectGetMaxX(plot), zeroY);
                CGContextStrokePath(context);
            }
            CGContextRestoreGState(context);
        }
        [regions addObjectsFromArray:BAProcessTrace(self, session.observations, session.intervals, session.gaps, metrics[index],
            index == 0 ? @"%" : index == 1 ? @"°C" : @"A", session.startDate, session.endDate, plot,
            minima[index], maxima[index], divisors[index], colors[index], NO, session.identifier)];
        BAAnalyticsDetailSelection *trackSelection = BAProcessSelection(self, @"metric", @[], @[metrics[index]], session.startDate, session.endDate, sessionContext);
        [regions addObject:BAProcessRegion(CGRectMake(10, CGRectGetMinY(plot), left - 13, CGRectGetHeight(plot)), trackSelection,
            [NSString stringWithFormat:_("%@ track, %@"), units[index], [@[socSummary, temperatureSummary, currentSummary] objectAtIndex:index]])];
        if ([observed[index] count] == 0) {
            BAProcessText(_("Unavailable"), CGRectInset(plot, 5, 1), caption, muted, NSTextAlignmentCenter);
        } else if (tall && CGRectGetHeight(plot) > caption.lineHeight * 2.5) {
            NSString *axisFormat = index == 0 ? @"%.0f" : (index == 2 ? @"%+.2g" : @"%.1f");
            BAProcessText([NSString stringWithFormat:axisFormat, maxima[index]],
                CGRectMake(8, CGRectGetMinY(plot) + caption.lineHeight, left - 15, caption.lineHeight), caption, muted, NSTextAlignmentRight);
            BAProcessText([NSString stringWithFormat:axisFormat, minima[index]],
                CGRectMake(8, CGRectGetMaxY(plot) - caption.lineHeight, left - 15, caption.lineHeight), caption, muted, NSTextAlignmentRight);
        }
    }

    // Endpoint labels belong to actual observed rows, even if a session edge
    // has no observation. They must not imply the boundary SOC is known.
    if (soc.count) {
        BAAnalyticsObservation *first = soc.firstObject, *last = soc.lastObject;
        CGFloat labelWidth = MIN(plotWidth * 0.45, mark.pointSize * 5);
        CGRect firstLabel = CGRectMake(CGRectGetMinX(socPlot), endpointY, labelWidth, mark.lineHeight + 2);
        CGRect lastLabel = CGRectMake(CGRectGetMaxX(socPlot) - labelWidth, endpointY, labelWidth, mark.lineHeight + 2);
        BAProcessText([NSString stringWithFormat:@"%.0f%%", BAProcessValue(first, BAAnalyticsHistorySOCPercent).doubleValue], firstLabel, mark, UIColor.compatGreenColor, NSTextAlignmentLeft);
        BAProcessText([NSString stringWithFormat:@"%.0f%%", BAProcessValue(last, BAAnalyticsHistorySOCPercent).doubleValue], lastLabel, mark, UIColor.compatGreenColor, NSTextAlignmentRight);
        [regions addObject:BAProcessRegion(firstLabel, BAProcessSelection(self, @"record", @[first.identifier], @[BAAnalyticsHistorySOCPercent], first.timestamp, first.timestamp, sessionContext),
            [NSString stringWithFormat:_("First observed SOC %.0f percent, %@"), BAProcessValue(first, BAAnalyticsHistorySOCPercent).doubleValue, BAProcessClock(first.timestamp)])];
        [regions addObject:BAProcessRegion(lastLabel, BAProcessSelection(self, @"record", @[last.identifier], @[BAAnalyticsHistorySOCPercent], last.timestamp, last.timestamp, sessionContext),
            [NSString stringWithFormat:_("Last observed SOC %.0f percent, %@"), BAProcessValue(last, BAAnalyticsHistorySOCPercent).doubleValue, BAProcessClock(last.timestamp)])];
    }
    if (peak) {
        NSString *peakLabel = [NSString stringWithFormat:_("Peak (obs.) %.1f°C"), BAProcessValue(peak, BAAnalyticsHistoryTemperatureCelsius).doubleValue];
        CGFloat peakX = BAProcessTimeX(peak.timestamp, session.startDate, session.endDate, temperaturePlot);
        CGFloat labelWidth = MIN(plotWidth, caption.pointSize * 11.5);
        CGRect label = CGRectMake(MAX(CGRectGetMinX(temperaturePlot), MIN(peakX - labelWidth * 0.5, CGRectGetMaxX(temperaturePlot) - labelWidth)),
            CGRectGetMinY(temperaturePlot) - caption.lineHeight - 1, labelWidth, caption.lineHeight + 2);
        if (tall) BAProcessText(peakLabel, label, caption, UIColor.compatOrangeColor, NSTextAlignmentCenter);
        else {
            double peakValue = BAProcessValue(peak, BAAnalyticsHistoryTemperatureCelsius).doubleValue;
            CGFloat peakY = CGRectGetMaxY(temperaturePlot) - (peakValue - temperatureMinimum) / (temperatureMaximum - temperatureMinimum) * temperaturePlot.size.height;
            label = CGRectMake(peakX - 5, peakY - 5, 10, 10);
        }
        NSMutableDictionary *peakContext = [sessionContext mutableCopy];
        peakContext[@"statistic"] = @"observed-maximum";
        [regions addObject:BAProcessRegion(label, BAProcessSelection(self, @"record", @[peak.identifier], @[BAAnalyticsHistoryTemperatureCelsius], peak.timestamp, peak.timestamp, peakContext),
            [NSString stringWithFormat:_("%@, %@. This is the observed maximum, not the unobserved session maximum."), peakLabel, BAProcessClock(peak.timestamp)])];
    }

    BAAnalyticsDrawGlyph(BAAnalyticsGlyphConnected, CGRectMake(12, CGRectGetMidY(statePlot) - 6.5, 13, 13), muted);
    BAProcessStateStrip(self, session.intervals, session.gaps, session.startDate, session.endDate, statePlot, session.identifier, regions);
    for (BAAnalyticsHistoryInterval *interval in session.intervals) {
        if (!BAProcessIntervalUsable(interval, @[], session.gaps) || interval.state == BAAnalyticsObservedStateUnknown) continue;
        CGFloat startX = BAProcessTimeX(interval.startDate, session.startDate, session.endDate, statePlot);
        CGFloat endX = BAProcessTimeX(interval.endDate, session.startDate, session.endDate, statePlot);
        if (endX - startX > 18) {
            BAAnalyticsGlyph glyph = interval.state == BAAnalyticsObservedStateCharging ? BAAnalyticsGlyphBolt :
                interval.state == BAAnalyticsObservedStateConnectedNotCharging ? BAAnalyticsGlyphPause :
                interval.state == BAAnalyticsObservedStateFull ? BAAnalyticsGlyphCheck : BAAnalyticsGlyphUnplugged;
            BAAnalyticsDrawGlyph(glyph, CGRectMake((startX + endX) / 2 - 6, CGRectGetMidY(statePlot) - 6, 12, 12), UIColor.compatLabelColor);
        }
    }
    CGFloat footerY = CGRectGetMaxY(statePlot) + 5;
    NSString *coverageLine = [NSString stringWithFormat:_("Coverage SOC %.0f%% · °C %.0f%% · A %.0f%%"),
        socCoverage / duration * 100, temperatureCoverage / duration * 100, currentCoverage / duration * 100];
    NSString *windowLine = [NSString stringWithFormat:_("≈%@ · n=%lu%@"), BAProcessDuration(duration),
        (unsigned long)session.observations.count, partial ? _(" · partial") : @""];
    CGFloat coverageHeight = caption.lineHeight * (largeText ? 2 : 1);
    BAProcessText(coverageLine, CGRectMake(12, footerY, width - 24, coverageHeight + 2), caption, muted, NSTextAlignmentLeft);
    BAProcessText(windowLine, CGRectMake(12, footerY + coverageHeight, width - 24, caption.lineHeight + 3), caption, muted, NSTextAlignmentLeft);
    [regions addObject:BAProcessRegion(CGRectMake(12, footerY, width - 24, footerHeight), sessionSelection,
        [NSString stringWithFormat:_("%@. %@"), coverage, windowLine])];
    return regions;
}

@end

@interface BASessionDetailViewController : BAAnalyticsDetailViewController
@end
@implementation BASessionDetailViewController
- (UIView *)makeVisualizationView {
    BASessionCanvasView *view = [BASessionCanvasView new];
    view.cardSize = BAAnalyticsCardSize2x2; view.familyIdentifier = self.familyReport.family;
    view.latestReport = self.report; view.latestSnapshot = self.snapshot;
    view.detailEnabled = NO;
    return view;
}
- (NSArray<NSDictionary *> *)summaryRows {
    BAAnalyticsHistorySession *session = BAProcessSession(self.familyReport, @"connected");
    if (!session) return @[];
    NSNumber *first = BAProcessValue(session.observations.firstObject, BAAnalyticsHistorySOCPercent);
    NSNumber *last = BAProcessValue(session.observations.lastObject, BAAnalyticsHistorySOCPercent);
    return @[@{@"title":_("Observed charge"), @"value":first && last ? [NSString stringWithFormat:@"%.0f%% → %.0f%%", first.doubleValue, last.doubleValue] : _("Unavailable")},
        @{@"title":_("Session duration"), @"value":BAProcessDuration([session.endDate timeIntervalSinceDate:session.startDate])}];
}
@end

@implementation BAAnalyticsSessionCanvasCard
- (BOOL)supportsDetails { return YES; }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    (void)size;
    return [[BASessionDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier
         report:self.latestReport snapshot:self.latestSnapshot selection:selection];
}


- (instancetype)init {
    return [super initWithIdentifier:@"com.torrekie.battman.analytics.session"
        displayName:_("Connected session") familyIdentifier:BAAnalyticsFamilySession
        supportedSizes:BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x2];
}

- (BAAnalyticsCanvasView *)makeCanvasView {
    return [[BASessionCanvasView alloc] initWithFrame:CGRectZero];
}

- (void)updateCanvasView:(BAAnalyticsCanvasView *)view {
    [view setNeedsLayout];
    [view setNeedsDisplay];
}

@end
