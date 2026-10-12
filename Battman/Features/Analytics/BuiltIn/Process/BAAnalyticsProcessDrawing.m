#import "main.h"
#import "BAAnalyticsProcessDrawing.h"
#include <math.h>
#include <float.h>
#import <objc/runtime.h>

NSNumber *BAProcessValue(BAAnalyticsObservation *observation, NSString *metric) {
    if (!observation.timestampValidated) return nil;
    BAAnalyticsFieldMetadata *metadata = observation.fieldMetadata[metric];
    NSNumber *value = [observation valueForMetricIdentifier:metric];
    return metadata.unitValidated && [value isKindOfClass:[NSNumber class]] && isfinite(value.doubleValue) ? value : nil;
}

BAAnalyticsFamilyReport *BAProcessFamily(BAAnalyticsCanvasView *view) {
    return [view.latestReport reportForFamily:view.familyIdentifier];
}

BAAnalyticsHistorySession *BAProcessSession(BAAnalyticsFamilyReport *report, NSString *kind) {
    id selected = report.payload[BAAnalyticsPayloadSelectedSession];
    BOOL hasSelected = [selected isKindOfClass:[BAAnalyticsHistorySession class]] && [[selected kind] isEqualToString:kind];
    if (hasSelected && [[selected endDate] compare:[selected startDate]] == NSOrderedDescending && [[selected intervals] count]) return selected;
    id sessions = report.payload[BAAnalyticsPayloadSessions];
    if (![sessions isKindOfClass:[NSArray class]]) return hasSelected ? selected : nil;
    BAAnalyticsHistorySession *latest = nil, *drawable = nil;
    for (id session in sessions) {
        if (![session isKindOfClass:[BAAnalyticsHistorySession class]] || ![[session kind] isEqualToString:kind]) continue;
        if (!latest || [[session endDate] compare:latest.endDate] == NSOrderedDescending) latest = session;
        if ([[session endDate] compare:[session startDate]] == NSOrderedDescending && [[session intervals] count] &&
            (!drawable || [[session endDate] compare:drawable.endDate] == NSOrderedDescending)) drawable = session;
    }
    return drawable ?: (hasSelected ? selected : latest);
}

static NSDateFormatter *BAProcessFormatter(NSString *format) {
    NSMutableDictionary *storage = NSThread.currentThread.threadDictionary;
    NSString *key = [@"com.torrekie.battman.analytics.date." stringByAppendingString:format];
    NSDateFormatter *formatter = storage[key];
    NSLocale *locale = NSLocale.currentLocale;
    NSTimeZone *zone = NSTimeZone.localTimeZone;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    if (!formatter || ![formatter.locale.localeIdentifier isEqual:locale.localeIdentifier] ||
        ![formatter.timeZone.name isEqual:zone.name] ||
        ![formatter.calendar.calendarIdentifier isEqual:calendar.calendarIdentifier]) {
        formatter = [NSDateFormatter new];
        formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = zone;
        formatter.dateFormat = format; storage[key] = formatter;
    }
    return formatter;
}

NSString *BAProcessClock(NSDate *date) {
    NSDateFormatter *formatter = BAProcessFormatter(@"HH:mm");
    return [formatter stringFromDate:date];
}

NSString *BAProcessWindow(NSDate *start, NSDate *end) {
    NSDateFormatter *formatter = BAProcessFormatter(@"MM/dd HH:mm");
    BOOL sameDay = [[NSCalendar currentCalendar] isDate:start inSameDayAsDate:end];
    return [NSString stringWithFormat:@"%@–%@", [formatter stringFromDate:start], sameDay ? BAProcessClock(end) : [formatter stringFromDate:end]];
}

NSString *BAProcessDuration(NSTimeInterval seconds) {
    if (!isfinite(seconds) || seconds < 0) return @"—";
    if (seconds < 60) return [NSString stringWithFormat:_("%.0f s"), seconds];
    if (seconds < 3600) return [NSString stringWithFormat:_("%.0f min"), seconds / 60.0];
    return [NSString stringWithFormat:_("%.1f h"), seconds / 3600.0];
}

NSString *BAProcessAvailability(BAAnalyticsFamilyReport *report) {
    if (!report || report.availability == BAAnalyticsReportAvailabilityLoading) return _("Waiting for history");
    if (report.availability == BAAnalyticsReportAvailabilityUnavailable) return _("Unavailable");
    if (report.availability == BAAnalyticsReportAvailabilityPartial) return _("Partial observations");
    return _("No verified observations");
}

NSString *BAProcessStateName(BAAnalyticsObservedState state) {
    switch (state) {
        case BAAnalyticsObservedStateCharging: return _("Charging");
        case BAAnalyticsObservedStateConnectedNotCharging: return _("Connected, not charging");
        case BAAnalyticsObservedStateFull: return _("Full");
        case BAAnalyticsObservedStateUnplugged: return _("Unplugged");
        case BAAnalyticsObservedStateUnknown: return _("Unknown");
    }
    return _("Unknown");
}

UIColor *BAProcessStateColor(BAAnalyticsObservedState state) {
    switch (state) {
        case BAAnalyticsObservedStateCharging: return UIColor.compatGreenColor;
        case BAAnalyticsObservedStateConnectedNotCharging: return UIColor.compatOrangeColor;
        case BAAnalyticsObservedStateFull: return UIColor.compatBlueColor;
        case BAAnalyticsObservedStateUnplugged:
        case BAAnalyticsObservedStateUnknown: return UIColor.compatSecondaryLabelColor;
    }
    return UIColor.compatSecondaryLabelColor;
}

UIFont *BAProcessFont(UIFontTextStyle style, CGFloat size, UIFontWeight weight) {
    // Plot annotations have finite canvas space. They grow with Dynamic Type
    // up to a readable ceiling; accessibility sizes also reduce secondary
    // content, while native detail retains the user's full text size.
    BOOL annotation = [style isEqualToString:UIFontTextStyleCaption1] || [style isEqualToString:UIFontTextStyleCaption2] ||
        [style isEqualToString:UIFontTextStyleFootnote];
    CGFloat ceiling = annotation ? 17 : 26;
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]
        maximumPointSize:MAX(size, ceiling)];
}

BOOL BAProcessLargeText(UIView *view) {
    NSString *category = view.traitCollection.preferredContentSizeCategory;
    return UIContentSizeCategoryIsAccessibilityCategory(category) ||
        [category isEqualToString:UIContentSizeCategoryExtraExtraLarge] ||
        [category isEqualToString:UIContentSizeCategoryExtraExtraExtraLarge];
}

void BAProcessText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment) {
    if (!UIGraphicsGetCurrentContext() || CGRectIsEmpty(rect)) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = alignment;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:paragraph}];
}

void BAProcessHatch(CGRect rect, UIColor *color) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context || CGRectIsEmpty(rect)) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, rect);
    CGContextSetFillColorWithColor(context, [color colorWithAlphaComponent:0.06].CGColor);
    CGContextFillRect(context, rect);
    CGContextSetStrokeColorWithColor(context, [color colorWithAlphaComponent:0.32].CGColor);
    CGContextSetLineWidth(context, 0.7);
    for (CGFloat x = CGRectGetMinX(rect) - CGRectGetHeight(rect); x < CGRectGetMaxX(rect); x += 6) {
        CGContextMoveToPoint(context, x, CGRectGetMaxY(rect));
        CGContextAddLineToPoint(context, x + CGRectGetHeight(rect), CGRectGetMinY(rect));
    }
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

CGFloat BAProcessTimeX(NSDate *date, NSDate *start, NSDate *end, CGRect plot) {
    NSTimeInterval duration = [end timeIntervalSinceDate:start];
    double fraction = duration > 0 ? [date timeIntervalSinceDate:start] / duration : 0.5;
    return CGRectGetMinX(plot) + MIN(1.0, MAX(0.0, fraction)) * CGRectGetWidth(plot);
}

NSArray<BAAnalyticsHistoryInterval *> *BAProcessOrderedIntervals(NSArray<BAAnalyticsHistoryInterval *> *intervals) {
    // Report windows and reader sessions are already chronological. Keep the
    // defensive fallback for independently supplied immutable session evidence.
    for (NSUInteger i = 1; i < intervals.count; i++) {
        if ([intervals[i - 1].startDate compare:intervals[i].startDate] == NSOrderedDescending)
            return [intervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) {
                return [a.startDate compare:b.startDate];
            }];
    }
    return intervals ?: @[];
}

BOOL BAProcessIntervalUsable(BAAnalyticsHistoryInterval *interval, NSArray<NSString *> *metrics, NSArray<BAAnalyticsHistoryGap *> *gaps) {
    if (!(interval.duration > 0) || !interval.startObservation.timestampValidated || !interval.endObservation.timestampValidated ||
        [interval.endObservation.timestamp compare:interval.startObservation.timestamp] != NSOrderedDescending ||
        [interval.startDate compare:interval.startObservation.timestamp] == NSOrderedAscending ||
        [interval.endDate compare:interval.endObservation.timestamp] == NSOrderedDescending) return NO;
    for (NSString *metric in metrics) {
        if (![interval.coveredMetricIdentifiers containsObject:metric] ||
            !BAProcessValue(interval.startObservation, metric) || !BAProcessValue(interval.endObservation, metric)) return NO;
    }
    // Independent metric coverage may overlap the joint-coverage complement.
    // The immutable report pre-indexes genuine discontinuities for logarithmic lookup.
    return !BAAnalyticsHistoryHasGap(gaps, interval.startDate, interval.endDate, YES);
}

BAAnalyticsDetailSelection *BAProcessSelection(BAAnalyticsCanvasView *view, NSString *kind,
        NSArray<NSString *> *records, NSArray<NSString *> *metrics, NSDate *start, NSDate *end, NSDictionary<NSString *, id> *context) {
    NSMutableDictionary *evidence = [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
    if (view.latestReport) evidence[@"reportSequence"] = @(view.latestReport.sequenceNumber);
    // Detail's bounded ID contract; large graph selections use a time range.
    NSMutableArray *identifiers = [NSMutableArray arrayWithArray:records ?: @[]];
    NSString *sessionIdentifier = evidence[@"sessionIdentifier"];
    // Include the owner so shared detail can recover source rows outside a
    // family query edge from the session's complete normalized observations.
    if ([sessionIdentifier isKindOfClass:NSString.class] && ![identifiers containsObject:sessionIdentifier])
        [identifiers insertObject:sessionIdentifier atIndex:0];
    NSArray *bounded = identifiers.count <= 256 ? identifiers : [identifiers subarrayWithRange:NSMakeRange(0, 256)];
    return [BAAnalyticsDetailSelection selectionForFamily:view.familyIdentifier kind:kind recordIdentifiers:bounded
        metricIdentifiers:metrics startDate:start endDate:end context:evidence];
}

BAAnalyticsCanvasHitRegion *BAProcessRegion(CGRect rect, BAAnalyticsDetailSelection *selection, NSString *label) {
    return [BAAnalyticsCanvasHitRegion regionWithRect:rect selection:selection accessibilityLabel:label];
}

NSArray<BAAnalyticsCanvasHitRegion *> *BAProcessTimeSliceRegions(BAAnalyticsCanvasView *view,
        NSArray<NSString *> *metrics, NSDate *start, NSDate *end, CGRect plot, BOOL vertical,
        NSString *sessionIdentifier, NSDictionary<NSString *, id> *context) {
    NSMutableArray *regions = [NSMutableArray array];
    if (UIGraphicsGetCurrentContext() || CGRectIsEmpty(plot) || [end compare:start] != NSOrderedDescending) return regions;
    CGFloat length = vertical ? plot.size.height : plot.size.width;
    NSUInteger count = MAX(1, MIN(64, (NSUInteger)ceil(length / 6)));
    NSTimeInterval duration = [end timeIntervalSinceDate:start];
    NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
    if (sessionIdentifier) details[@"sessionIdentifier"] = sessionIdentifier;
    details[@"selectionConvention"] = _("Original observations in this visible time slice, including missing fields. No inference across unknown spans.");
    for (NSUInteger index = 0; index < count; index++) {
        NSDate *first = [start dateByAddingTimeInterval:duration * index / count];
        NSDate *last = [start dateByAddingTimeInterval:duration * (index + 1) / count];
        CGRect region = vertical ? CGRectMake(plot.origin.x, plot.origin.y + length * index / count, plot.size.width, length / count) :
            CGRectMake(plot.origin.x + length * index / count, plot.origin.y, length / count, plot.size.height);
        [regions addObject:BAProcessRegion(region, BAProcessSelection(view, @"time-slice", sessionIdentifier ? @[sessionIdentifier] : @[], metrics, first, last, details),
            [NSString stringWithFormat:_("Observed evidence, %@"), BAProcessWindow(first, last)])];
    }
    return regions;
}

static double BAProcessInterpolate(BAAnalyticsHistoryInterval *interval, NSString *metric, NSDate *date) {
    double first = BAProcessValue(interval.startObservation, metric).doubleValue;
    double last = BAProcessValue(interval.endObservation, metric).doubleValue;
    NSTimeInterval sampledDuration = [interval.endObservation.timestamp timeIntervalSinceDate:interval.startObservation.timestamp];
    double fraction = sampledDuration > 0 ? [date timeIntervalSinceDate:interval.startObservation.timestamp] / sampledDuration : 0;
    return first + (last - first) * MAX(0.0, MIN(1.0, fraction));
}

static CGRect BAProcessSpan(NSDate *first, NSDate *last, NSDate *start, NSDate *end, CGRect plot) {
    CGFloat x = BAProcessTimeX(first, start, end, plot);
    return CGRectMake(x, CGRectGetMinY(plot), MAX(0.0, BAProcessTimeX(last, start, end, plot) - x), CGRectGetHeight(plot));
}

typedef struct {
    NSTimeInterval time;
    double value;
    NSUInteger run;
} BAProcessDisplaySample;

@interface BAProcessPreparedTrace : NSObject
@property (nonatomic, weak) NSArray *observations;
@property (nonatomic, weak) NSArray *intervals;
@property (nonatomic, weak) NSArray *gaps;
@property (nonatomic, copy) NSDate *start;
@property (nonatomic, copy) NSDate *end;
@property (nonatomic) double divisor;
@property (nonatomic, copy) NSData *segments;
@property (nonatomic, copy) NSData *points;
@property (nonatomic, copy) NSData *missing;
@property (nonatomic) NSUInteger columns;
@property (nonatomic, copy) NSArray<NSNumber *> *lineIndices;
@property (nonatomic, copy) NSArray<NSNumber *> *markerIndices;
@end
@implementation BAProcessPreparedTrace
@end

// This affects the presentation only. The report and time-slice selections
// still contain every original reading and every trusted interval.
static NSArray<NSNumber *> *BAProcessDisplayEnvelope(NSData *data, NSTimeInterval start,
        NSTimeInterval end, NSUInteger columns, BOOL preserveRuns) {
    const BAProcessDisplaySample *samples = data.bytes;
    NSUInteger count = data.length / sizeof(BAProcessDisplaySample);
    if (!count) return @[];
    NSMutableIndexSet *kept = [NSMutableIndexSet indexSet];
    NSUInteger first = 0, low = 0, high = 0, last = 0, priorColumn = NSNotFound, zero = NSNotFound;
    for (NSUInteger i = 0; i < count; i++) {
        double fraction = end > start ? (samples[i].time - start) / (end - start) : .5;
        NSUInteger column = MIN(columns - 1, (NSUInteger)MAX(0, floor(fraction * columns)));
        // A short trusted run must survive even if it shares a display column
        // with another run. Its endpoints cannot be bridged across a gap.
        if (column != priorColumn || (preserveRuns && i && samples[i].run != samples[i - 1].run)) {
            if (priorColumn != NSNotFound) {
                [kept addIndex:first]; [kept addIndex:low]; [kept addIndex:high]; [kept addIndex:last];
            }
            first = low = high = i; priorColumn = column; zero = NSNotFound;
        }
        if (samples[i].value < samples[low].value) low = i;
        if (samples[i].value > samples[high].value) high = i;
        last = i;
        // Keep one real zero per bucket. The extrema retain both signs
        // without repeating every baseline point in a flat dense series.
        if (samples[i].value == 0 && zero == NSNotFound) { zero = i; [kept addIndex:i]; }
    }
    [kept addIndex:first]; [kept addIndex:low]; [kept addIndex:high]; [kept addIndex:last];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:kept.count];
    [kept enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [result addObject:@(index)]; }];
    return result;
}

static BAProcessPreparedTrace *BAProcessPrepareDisplayTrace(BAAnalyticsCanvasView *view,
        NSArray *observations, NSArray *intervals, NSArray *gaps, NSString *metric,
        NSDate *start, NSDate *end, double divisor, NSUInteger columns) {
    static char tracesKey;
    NSMutableDictionary *traces = objc_getAssociatedObject(view, &tracesKey);
    if (!traces) {
        traces = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(view, &tracesKey, traces, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BAProcessPreparedTrace *trace = traces[metric];
    if (!trace || trace.observations != observations || trace.intervals != intervals || trace.gaps != gaps ||
        ![trace.start isEqualToDate:start] || ![trace.end isEqualToDate:end] || trace.divisor != divisor) {
        trace = [BAProcessPreparedTrace new];
        trace.observations = observations; trace.intervals = intervals; trace.gaps = gaps;
        trace.start = start; trace.end = end; trace.divisor = divisor;
        NSMutableData *segments = [NSMutableData data], *points = [NSMutableData data], *missing = [NSMutableData data];
        NSDate *cursor = start; BAAnalyticsHistoryInterval *previous = nil; NSUInteger run = 0;
        for (BAAnalyticsHistoryInterval *interval in BAProcessOrderedIntervals(intervals)) {
            if (!BAProcessIntervalUsable(interval, @[metric], gaps)) continue;
            NSDate *first = [interval.startDate compare:start] == NSOrderedAscending ? start : interval.startDate;
            NSDate *last = [interval.endDate compare:end] == NSOrderedDescending ? end : interval.endDate;
            if ([last compare:first] != NSOrderedDescending) continue;
            if ([first compare:cursor] == NSOrderedDescending) {
                double range[] = {cursor.timeIntervalSince1970, first.timeIntervalSince1970};
                [missing appendBytes:range length:sizeof(range)];
            }
            if ([last compare:cursor] == NSOrderedDescending) cursor = last;
            BOOL joined = previous && [previous.endDate isEqualToDate:first] &&
                [previous.endObservation.identifier isEqualToString:interval.startObservation.identifier];
            if (!joined && previous) run++;
            BAProcessDisplaySample pair[] = {
                {first.timeIntervalSince1970, BAProcessInterpolate(interval, metric, first) / divisor, run},
                {last.timeIntervalSince1970, BAProcessInterpolate(interval, metric, last) / divisor, run}
            };
            [segments appendBytes:pair length:sizeof(pair)]; previous = interval;
        }
        if ([end compare:cursor] == NSOrderedDescending) {
            double range[] = {cursor.timeIntervalSince1970, end.timeIntervalSince1970};
            [missing appendBytes:range length:sizeof(range)];
        }
        for (BAAnalyticsObservation *observation in observations) {
            NSNumber *value = BAProcessValue(observation, metric);
            if (!value || [observation.timestamp compare:start] == NSOrderedAscending || [observation.timestamp compare:end] == NSOrderedDescending) continue;
            BAProcessDisplaySample point = {observation.timestamp.timeIntervalSince1970, value.doubleValue / divisor, 0};
            [points appendBytes:&point length:sizeof(point)];
        }
        trace.segments = segments; trace.points = points; trace.missing = missing;
        traces[metric] = trace;
    }
    if (trace.columns != columns) {
        trace.columns = columns;
        trace.lineIndices = BAProcessDisplayEnvelope(trace.segments, start.timeIntervalSince1970, end.timeIntervalSince1970, columns, YES);
        trace.markerIndices = BAProcessDisplayEnvelope(trace.points, start.timeIntervalSince1970, end.timeIntervalSince1970,
            MAX(1, columns / 4), NO);
    }
    return trace;
}

static void BAProcessDrawDenseTrace(BAAnalyticsCanvasView *view, NSArray *observations, NSArray *intervals,
        NSArray *gaps, NSString *metric, NSDate *start, NSDate *end, CGRect plot,
        double minimum, double maximum, double divisor, UIColor *color, BOOL dashed) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    NSUInteger columns = MAX(1, MIN(512, (NSUInteger)ceil(plot.size.width / 3)));
    BAProcessPreparedTrace *trace = BAProcessPrepareDisplayTrace(view, observations, intervals, gaps, metric, start, end, divisor, columns);
    double firstTime = start.timeIntervalSince1970, duration = [end timeIntervalSinceDate:start];
    CGFloat (^x)(double) = ^CGFloat(double time) { return plot.origin.x + (duration > 0 ? (time - firstTime) / duration : .5) * plot.size.width; };
    CGFloat (^y)(double) = ^CGFloat(double value) { return CGRectGetMaxY(plot) - (value - minimum) / (maximum - minimum) * plot.size.height; };
    const double *missing = trace.missing.bytes;
    for (NSUInteger i = 0; i < trace.missing.length / (2 * sizeof(double)); i++)
        BAProcessHatch(CGRectMake(x(missing[2 * i]), plot.origin.y, MAX(0, x(missing[2 * i + 1]) - x(missing[2 * i])), plot.size.height), UIColor.compatSecondaryLabelColor);
    CGContextSetStrokeColorWithColor(context, color.CGColor); CGContextSetLineWidth(context, 1.8);
    CGContextSetLineCap(context, kCGLineCapRound); CGFloat pattern[] = {4, 3};
    CGContextSetLineDash(context, 0, dashed ? pattern : NULL, dashed ? 2 : 0);
    const BAProcessDisplaySample *samples = trace.segments.bytes;
    NSUInteger previous = NSNotFound;
    for (NSNumber *number in trace.lineIndices) {
        NSUInteger index = number.unsignedIntegerValue;
        if (previous != NSNotFound && samples[index].run == samples[previous].run) {
            CGContextMoveToPoint(context, x(samples[previous].time), y(samples[previous].value));
            CGContextAddLineToPoint(context, x(samples[index].time), y(samples[index].value));
        }
        previous = index;
    }
    CGContextStrokePath(context); CGContextSetLineDash(context, 0, NULL, 0);
    CGContextSetFillColorWithColor(context, color.CGColor);
    samples = trace.points.bytes;
    for (NSNumber *number in trace.markerIndices) {
        NSUInteger index = number.unsignedIntegerValue;
        CGContextAddEllipseInRect(context, CGRectMake(x(samples[index].time) - 1.5, y(samples[index].value) - 1.5, 3, 3));
    }
    CGContextFillPath(context);
}

NSArray<BAAnalyticsCanvasHitRegion *> *BAProcessTrace(BAAnalyticsCanvasView *view,
        NSArray<BAAnalyticsObservation *> *observations, NSArray<BAAnalyticsHistoryInterval *> *intervals,
        NSArray<BAAnalyticsHistoryGap *> *gaps, NSString *metric, NSString *unit,
        NSDate *start, NSDate *end, CGRect plot, double minimum, double maximum,
        double divisor, UIColor *color, BOOL dashed, NSString *sessionIdentifier) {
    NSMutableArray *regions = [NSMutableArray array];
    if (CGRectIsEmpty(plot) || !isfinite(minimum) || !isfinite(maximum) || !(maximum > minimum) || !(divisor > 0)) return regions;
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL collect = context == NULL;
    BOOL dense = observations.count + intervals.count > 192;
    if (dense && context) {
        CGContextSaveGState(context); CGContextClipToRect(context, plot);
        BAProcessDrawDenseTrace(view, observations, intervals, gaps, metric, start, end, plot,
            minimum, maximum, divisor, color, dashed);
        CGContextRestoreGState(context);
        return regions;
    }
    NSUInteger slices = MAX(1, MIN(64, (NSUInteger)ceil(CGRectGetWidth(plot) / 6)));
    NSMutableIndexSet *pointSlices = [NSMutableIndexSet indexSet], *gapSlices = [NSMutableIndexSet indexSet];
    if (context) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, plot);
    }
    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    if (sessionIdentifier) base[@"sessionIdentifier"] = sessionIdentifier;
    NSArray *ordered = BAProcessOrderedIntervals(intervals);
    NSDate *cursor = start;
    // Complement of trusted coverage for this metric includes absent fields,
    // even when another track has valid readings over the same time span.
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[metric], gaps)) continue;
        NSDate *first = [interval.startDate compare:start] == NSOrderedAscending ? start : interval.startDate;
        NSDate *last = [interval.endDate compare:end] == NSOrderedDescending ? end : interval.endDate;
        if ([last compare:first] != NSOrderedDescending) continue;
        if ([first compare:cursor] == NSOrderedDescending) {
            CGRect missing = BAProcessSpan(cursor, first, start, end, plot);
            BAProcessHatch(missing, UIColor.compatSecondaryLabelColor);
            NSUInteger slice = MIN(slices - 1, (NSUInteger)MAX(0, floor((CGRectGetMidX(missing) - plot.origin.x) / plot.size.width * slices)));
            if (collect && (!dense || ![gapSlices containsIndex:slice])) {
                [gapSlices addIndex:slice];
                [regions addObject:BAProcessRegion(missing, BAProcessSelection(view, @"gap", @[], @[metric], cursor, first, base),
                    [NSString stringWithFormat:_("%@ missing, %@"), unit, BAProcessWindow(cursor, first)])];
            }
        }
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
    }
    if ([end compare:cursor] == NSOrderedDescending) {
        CGRect missing = BAProcessSpan(cursor, end, start, end, plot);
        BAProcessHatch(missing, UIColor.compatSecondaryLabelColor);
        if (collect) [regions addObject:BAProcessRegion(missing, BAProcessSelection(view, @"gap", @[], @[metric], cursor, end, base),
            [NSString stringWithFormat:_("%@ missing, %@"), unit, BAProcessWindow(cursor, end)])];
    }
    if (context) {
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, 1.8);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGFloat pattern[] = {4, 3};
        CGContextSetLineDash(context, 0, dashed ? pattern : NULL, dashed ? 2 : 0);
        CGContextBeginPath(context);
    }
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[metric], gaps)) continue;
        NSDate *first = [interval.startDate compare:start] == NSOrderedAscending ? start : interval.startDate;
        NSDate *last = [interval.endDate compare:end] == NSOrderedDescending ? end : interval.endDate;
        if ([last compare:first] != NSOrderedDescending) continue;
        double v0 = BAProcessInterpolate(interval, metric, first) / divisor;
        double v1 = BAProcessInterpolate(interval, metric, last) / divisor;
        CGFloat y0 = CGRectGetMaxY(plot) - (v0 - minimum) / (maximum - minimum) * CGRectGetHeight(plot);
        CGFloat y1 = CGRectGetMaxY(plot) - (v1 - minimum) / (maximum - minimum) * CGRectGetHeight(plot);
        CGFloat x0 = BAProcessTimeX(first, start, end, plot), x1 = BAProcessTimeX(last, start, end, plot);
        if (collect && !dense) {
            NSMutableDictionary *details = [base mutableCopy];
            details[@"clippedStartTimestamp"] = @(first.timeIntervalSince1970);
            details[@"clippedEndTimestamp"] = @(last.timeIntervalSince1970);
            details[@"interpolation"] = _("Linear within the trusted original sampled pair");
            // Detail includes original endpoint rows when visible bounds fall
            // inside those timestamps.
            BAAnalyticsDetailSelection *selection = BAProcessSelection(view, @"interval",
                @[interval.startObservation.identifier, interval.endObservation.identifier], @[metric],
                interval.startObservation.timestamp, interval.endObservation.timestamp, details);
            CGRect segment = CGRectMake(MIN(x0, x1), MAX(CGRectGetMinY(plot), MIN(y0, y1) - 2),
                MAX(2, fabs(x1 - x0)), MIN(CGRectGetHeight(plot), MAX(4, fabs(y1 - y0) + 4)));
            [regions addObject:BAProcessRegion(segment, selection,
                [NSString stringWithFormat:_("%@ sampled interval, %@"), unit, BAProcessWindow(first, last)])];
        }
        if (context) {
            CGContextMoveToPoint(context, x0, y0);
            CGContextAddLineToPoint(context, x1, y1);
        }
    }
    if (context) {
        CGContextStrokePath(context);
        CGContextSetLineDash(context, 0, NULL, 0);
        CGContextSetFillColorWithColor(context, color.CGColor);
    }
    for (BAAnalyticsObservation *observation in observations) {
        NSNumber *value = BAProcessValue(observation, metric);
        if (!value || [observation.timestamp compare:start] == NSOrderedAscending || [observation.timestamp compare:end] == NSOrderedDescending) continue;
        CGFloat x = BAProcessTimeX(observation.timestamp, start, end, plot);
        CGFloat y = CGRectGetMaxY(plot) - (value.doubleValue / divisor - minimum) / (maximum - minimum) * CGRectGetHeight(plot);
        CGRect dot = CGRectMake(x - 2, y - 2, 4, 4);
        if (context) CGContextFillEllipseInRect(context, dot);
        if (!collect) continue;
        if (!dense) {
            BAAnalyticsDetailSelection *selection = BAProcessSelection(view, @"record", @[observation.identifier], @[metric], observation.timestamp, observation.timestamp, base);
            [regions addObject:BAProcessRegion(dot, selection, [NSString stringWithFormat:_("%@, %+.3g %@"), BAProcessClock(observation.timestamp), value.doubleValue / divisor, unit])];
        } else {
            NSUInteger slice = MIN(slices - 1, (NSUInteger)MAX(0, floor((x - plot.origin.x) / plot.size.width * slices)));
            if ([pointSlices containsIndex:slice]) continue;
            [pointSlices addIndex:slice];
            NSTimeInterval duration = [end timeIntervalSinceDate:start];
            NSDate *first = [start dateByAddingTimeInterval:duration * slice / slices];
            NSDate *last = [start dateByAddingTimeInterval:duration * (slice + 1) / slices];
            NSMutableDictionary *details = [base mutableCopy];
            details[@"selectionConvention"] = _("All verified observations in this visible time slice; original samples are retained");
            details[@"filters"] = @{metric:@{@"minimum":@(-DBL_MAX), @"maximum":@(DBL_MAX), @"includeMaximum":@YES}};
            CGRect bucket = CGRectMake(plot.origin.x + plot.size.width * slice / slices, plot.origin.y, plot.size.width / slices, plot.size.height);
            [regions addObject:BAProcessRegion(bucket, BAProcessSelection(view, @"metric", sessionIdentifier ? @[sessionIdentifier] : @[], @[metric], first, last, details),
                [NSString stringWithFormat:_("%@ observations, %@"), unit, BAProcessWindow(first, last)])];
        }
    }
    if (context) CGContextRestoreGState(context);
    return regions;
}

void BAProcessStateStrip(BAAnalyticsCanvasView *view,
        NSArray<BAAnalyticsHistoryInterval *> *intervals, NSArray<BAAnalyticsHistoryGap *> *gaps,
        NSDate *start, NSDate *end, CGRect rect, NSString *sessionIdentifier,
        NSMutableArray<BAAnalyticsCanvasHitRegion *> *regions) {
    BAProcessHatch(rect, UIColor.compatSecondaryLabelColor);
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL collect = context == NULL, dense = intervals.count + gaps.count > 192;
    NSDictionary *base = sessionIdentifier ? @{@"sessionIdentifier":sessionIdentifier} : @{};
    NSArray *metrics = @[BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging, BAAnalyticsHistoryFullyCharged];
    if (dense) [regions addObjectsFromArray:BAProcessTimeSliceRegions(view, metrics, start, end, rect, NO, sessionIdentifier,
        @{@"stateBoundaries":_("Sampled ranges; unknown spans do not establish a cable event or pause")})];
    NSArray *ordered = BAProcessOrderedIntervals(intervals);
    NSDate *cursor = start;
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[], gaps) || interval.state == BAAnalyticsObservedStateUnknown) continue;
        NSDate *first = [interval.startDate compare:start] == NSOrderedAscending ? start : interval.startDate;
        NSDate *last = [interval.endDate compare:end] == NSOrderedDescending ? end : interval.endDate;
        if ([last compare:first] != NSOrderedDescending) continue;
        if ([first compare:cursor] == NSOrderedDescending) {
            CGRect missing = BAProcessSpan(cursor, first, start, end, rect);
            if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(view, @"gap", @[], metrics, cursor, first, base),
                [NSString stringWithFormat:_("Unknown state, %@"), BAProcessWindow(cursor, first)])];
        }
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
    }
    if ([end compare:cursor] == NSOrderedDescending) {
        CGRect missing = BAProcessSpan(cursor, end, start, end, rect);
        if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(view, @"gap", @[], metrics, cursor, end, base),
            [NSString stringWithFormat:_("Unknown state, %@"), BAProcessWindow(cursor, end)])];
    }
    for (BAAnalyticsHistoryInterval *interval in intervals) {
        if (!BAProcessIntervalUsable(interval, @[], gaps) || interval.state == BAAnalyticsObservedStateUnknown) continue;
        NSDate *first = [interval.startDate compare:start] == NSOrderedAscending ? start : interval.startDate;
        NSDate *last = [interval.endDate compare:end] == NSOrderedDescending ? end : interval.endDate;
        if ([last compare:first] != NSOrderedDescending) continue;
        CGRect band = BAProcessSpan(first, last, start, end, rect);
        UIColor *color = BAProcessStateColor(interval.state);
        if (context) {
            CGContextSaveGState(context);
            CGContextSetFillColorWithColor(context, UIColor.compatBackgroundColor.CGColor);
            CGContextFillRect(context, band);
            CGContextSetFillColorWithColor(context, [color colorWithAlphaComponent:interval.state == BAAnalyticsObservedStateUnplugged ? 0.1 : 0.65].CGColor);
            CGContextFillRect(context, band);
            CGContextSetStrokeColorWithColor(context, color.CGColor);
            CGContextSetLineWidth(context, 1);
            CGFloat dash[] = {3, 2};
            if (interval.state == BAAnalyticsObservedStateConnectedNotCharging) CGContextSetLineDash(context, 0, dash, 2);
            CGContextStrokeRect(context, CGRectInset(band, 0.5, 0.5));
            if (interval.state == BAAnalyticsObservedStateFull && CGRectGetHeight(band) > 5) CGContextStrokeRect(context, CGRectInset(band, 2, 2));
            CGContextRestoreGState(context);
        }
        if (!collect || dense) continue;
        NSMutableDictionary *details = [base mutableCopy];
        details[@"state"] = @(interval.state);
        details[@"boundaryEstimate"] = @YES;
        details[@"clippedStartTimestamp"] = @(first.timeIntervalSince1970);
        details[@"clippedEndTimestamp"] = @(last.timeIntervalSince1970);
        [regions addObject:BAProcessRegion(band, BAProcessSelection(view, @"interval", @[interval.startObservation.identifier, interval.endObservation.identifier], metrics,
            interval.startObservation.timestamp, interval.endObservation.timestamp, details),
            [NSString stringWithFormat:_("%@, approximately %@"), BAProcessStateName(interval.state), BAProcessWindow(first, last)])];
    }
    for (BAAnalyticsHistoryGap *gap in gaps) {
        if ([gap.endDate compare:start] != NSOrderedDescending || [gap.startDate compare:end] != NSOrderedAscending) continue;
        NSDate *first = [gap.startDate compare:start] == NSOrderedAscending ? start : gap.startDate;
        NSDate *last = [gap.endDate compare:end] == NSOrderedDescending ? end : gap.endDate;
        CGRect band = BAProcessSpan(first, last, start, end, rect);
        BAProcessHatch(band, UIColor.compatSecondaryLabelColor);
        if (!collect || dense) continue;
        NSMutableDictionary *details = [base mutableCopy];
        details[@"reason"] = gap.reason;
        [regions addObject:BAProcessRegion(band, BAProcessSelection(view, @"gap", @[], metrics, first, last, details),
            [NSString stringWithFormat:_("Unknown state, %@"), BAProcessWindow(first, last)])];
    }
}
