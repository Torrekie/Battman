#import "main.h"
#import "BAAnalyticsEventsCanvasCard.h"
#import "BAAnalyticsProcessDrawing.h"
#include <math.h>
#include <stdlib.h>

typedef struct {
    NSTimeInterval start;
    NSTimeInterval end;
} BAEventTimeRange;

static int BAEventCompareRanges(const void *left, const void *right) {
    const BAEventTimeRange *a = left, *b = right;
    return a->start == b->start ? 0 : a->start < b->start ? -1 : 1;
}

static NSData *BAEventMergedRanges(NSMutableData *storage) {
    NSUInteger count = storage.length / sizeof(BAEventTimeRange), merged = 0;
    BAEventTimeRange *ranges = storage.mutableBytes;
    for (NSUInteger index = 1; index < count; index++) {
        if (ranges[index - 1].start > ranges[index].start) {
            qsort(ranges, count, sizeof(BAEventTimeRange), BAEventCompareRanges);
            break;
        }
    }
    for (NSUInteger index = 0; index < count; index++) {
        BAEventTimeRange range = ranges[index];
        if (merged && range.start <= ranges[merged - 1].end)
            ranges[merged - 1].end = MAX(ranges[merged - 1].end, range.end);
        else ranges[merged++] = range;
    }
    [storage setLength:merged * sizeof(BAEventTimeRange)];
    return storage.copy;
}

static BOOL BAEventPointInClosedRanges(NSDate *date, NSData *storage) {
    const BAEventTimeRange *ranges = storage.bytes;
    NSTimeInterval point = date.timeIntervalSince1970;
    NSUInteger lo = 0, hi = storage.length / sizeof(BAEventTimeRange);
    while (lo < hi) {
        NSUInteger middle = lo + (hi - lo) / 2;
        if (ranges[middle].end < point) lo = middle + 1; else hi = middle;
    }
    return lo < storage.length / sizeof(BAEventTimeRange) && ranges[lo].start <= point;
}

static NSArray<NSString *> *BAEventStateMetrics(void) {
    return @[BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging, BAAnalyticsHistoryFullyCharged];
}

static NSString *BAEventSymbol(BAAnalyticsObservedState state) {
    switch (state) {
        case BAAnalyticsObservedStateCharging: return @"C";
        case BAAnalyticsObservedStateConnectedNotCharging: return @"Ⅱ";
        case BAAnalyticsObservedStateFull: return @"F";
        case BAAnalyticsObservedStateUnplugged: return @"U";
        case BAAnalyticsObservedStateUnknown: return @"?";
    }
    return @"?";
}

static NSString *BAEventShortName(BAAnalyticsObservedState state) {
    return state == BAAnalyticsObservedStateConnectedNotCharging ? _("Connected idle") : BAProcessStateName(state);
}

static CGFloat BAEventLegendLabelHeight(BAAnalyticsObservedState state, CGFloat width, UIFont *font) {
    return ceil(MAX(font.lineHeight, [BAEventShortName(state) boundingRectWithSize:CGSizeMake(MAX(1, width), CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:font} context:nil].size.height));
}

static NSUInteger BAEventLegendColumns(CGFloat width, UIFont *font, BOOL compact, BOOL vertical) {
    if (compact) return 5;
    if (vertical) return 1;
    CGFloat longestWord = 0;
    for (NSNumber *state in @[@(BAAnalyticsObservedStateCharging), @(BAAnalyticsObservedStateConnectedNotCharging),
            @(BAAnalyticsObservedStateFull), @(BAAnalyticsObservedStateUnplugged), @(BAAnalyticsObservedStateUnknown)]) {
        for (NSString *word in [BAEventShortName(state.integerValue) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet])
            longestWord = MAX(longestWord, ceil([word sizeWithAttributes:@{NSFontAttributeName:font}].width));
    }
    NSUInteger columns = 3;
    while (columns > 1 && width / columns - 19 < longestWord) columns--;
    return columns;
}

static NSDate *BAEventLater(NSDate *a, NSDate *b) {
    return [a compare:b] == NSOrderedAscending ? b : a;
}

static NSDate *BAEventEarlier(NSDate *a, NSDate *b) {
    return [a compare:b] == NSOrderedDescending ? b : a;
}

static NSString *BAEventDate(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.dateFormat = @"MM/dd HH:mm";
    return [formatter stringFromDate:date];
}

static CGRect BAEventSpan(NSDate *first, NSDate *last, BAAnalyticsHistoryWindow *window, CGRect plot, BOOL vertical) {
    CGRect axis = vertical ? CGRectMake(CGRectGetMinY(plot), 0, CGRectGetHeight(plot), 1) : plot;
    CGFloat a = BAProcessTimeX(first, window.startDate, window.endDate, axis);
    CGFloat b = BAProcessTimeX(last, window.startDate, window.endDate, axis);
    return vertical ? CGRectMake(CGRectGetMinX(plot), a, CGRectGetWidth(plot), MAX(0, b - a)) :
        CGRectMake(a, CGRectGetMinY(plot), MAX(0, b - a), CGRectGetHeight(plot));
}

static double BAEventCurrentAt(BAAnalyticsHistoryInterval *interval, NSDate *date) {
    double first = BAProcessValue(interval.startObservation, BAAnalyticsHistoryCurrentMilliamps).doubleValue;
    double last = BAProcessValue(interval.endObservation, BAAnalyticsHistoryCurrentMilliamps).doubleValue;
    NSTimeInterval duration = [interval.endObservation.timestamp timeIntervalSinceDate:interval.startObservation.timestamp];
    double fraction = duration > 0 ? [date timeIntervalSinceDate:interval.startObservation.timestamp] / duration : 0;
    return (first + (last - first) * MIN(1, MAX(0, fraction))) / 1000.0;
}

@interface BAAnalyticsEventsCanvasView : BAAnalyticsCanvasView
@property (nonatomic, weak) BAAnalyticsFamilyReport *preparedFamily;
@property (nonatomic, copy) NSArray<BAAnalyticsStateTransition *> *preparedTransitions;
@property (nonatomic, copy) NSArray<BAAnalyticsHistoryInterval *> *preparedIntervals;
@property (nonatomic, copy) NSData *transitionRanges;
@property (nonatomic, copy) NSData *closedGapRanges;
@property (nonatomic, copy) NSNumber *preparedKnownDuration;
- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderEvidence;
@end

@implementation BAAnalyticsEventsCanvasView

- (void)clearPreparedEvidence {
    self.preparedFamily = nil;
    self.preparedTransitions = nil;
    self.preparedIntervals = nil;
    self.transitionRanges = nil;
    self.closedGapRanges = nil;
    self.preparedKnownDuration = nil;
}

- (void)setLatestReport:(BAAnalyticsReport *)latestReport {
    BAAnalyticsFamilyReport *family = [latestReport reportForFamily:self.familyIdentifier];
    if (!family || family != self.preparedFamily) [self clearPreparedEvidence];
    [super setLatestReport:latestReport];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.hitRegions = [self renderEvidence];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    [self renderEvidence];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (NSArray<BAAnalyticsStateTransition *> *)transitionsForFamily:(BAAnalyticsFamilyReport *)family {
    if (family == self.preparedFamily && self.preparedTransitions) return self.preparedTransitions;
    [self clearPreparedEvidence];
    self.preparedFamily = family;
    self.preparedIntervals = BAProcessOrderedIntervals(family.window.intervals);
    id payload = family.payload[BAAnalyticsPayloadTransitions];
    NSMutableArray *transitions = [NSMutableArray array];
    for (id item in [payload isKindOfClass:NSArray.class] ? payload : @[]) {
        if (![item isKindOfClass:BAAnalyticsStateTransition.class]) continue;
        BAAnalyticsStateTransition *transition = item;
        if ([transition.latestDate compare:transition.earliestDate] == NSOrderedAscending ||
            [transition.latestDate compare:family.window.startDate] == NSOrderedAscending ||
            [transition.earliestDate compare:family.window.endDate] == NSOrderedDescending ||
            transition.previousState == transition.nextState) continue;
        BOOL point = [transition.earliestDate isEqualToDate:transition.latestDate];
        BOOL intersectsGap = BAAnalyticsHistoryHasGap(family.window.gaps, transition.earliestDate, transition.latestDate, NO);
        if (point) {
            if (!self.closedGapRanges) {
                NSMutableData *ranges = [NSMutableData dataWithCapacity:family.window.gaps.count * sizeof(BAEventTimeRange)];
                for (BAAnalyticsHistoryGap *gap in family.window.gaps) {
                    BAEventTimeRange range = {gap.startDate.timeIntervalSince1970, gap.endDate.timeIntervalSince1970};
                    [ranges appendBytes:&range length:sizeof range];
                }
                self.closedGapRanges = BAEventMergedRanges(ranges);
            }
            // Point transitions keep the original inclusive gap-boundary rule.
            intersectsGap = BAEventPointInClosedRanges(transition.earliestDate, self.closedGapRanges);
        }
        // A missing sample span cannot establish a cable change or a pause.
        if (!intersectsGap) [transitions addObject:transition];
    }
    for (NSUInteger index = 1; index < transitions.count; index++) {
        if ([((BAAnalyticsStateTransition *)transitions[index - 1]).earliestDate compare:((BAAnalyticsStateTransition *)transitions[index]).earliestDate] == NSOrderedDescending) {
            [transitions sortUsingComparator:^NSComparisonResult(BAAnalyticsStateTransition *a, BAAnalyticsStateTransition *b) { return [a.earliestDate compare:b.earliestDate]; }];
            break;
        }
    }
    self.preparedTransitions = transitions;
    NSMutableData *ranges = [NSMutableData dataWithCapacity:transitions.count * sizeof(BAEventTimeRange)];
    for (BAAnalyticsStateTransition *transition in transitions) {
        BAEventTimeRange range = {transition.earliestDate.timeIntervalSince1970, transition.latestDate.timeIntervalSince1970};
        [ranges appendBytes:&range length:sizeof range];
    }
    self.transitionRanges = BAEventMergedRanges(ranges);
    return self.preparedTransitions;
}

- (BAAnalyticsObservedState)stateForInterval:(BAAnalyticsHistoryInterval *)interval
                           transitionCursor:(NSUInteger *)cursor {
    const BAEventTimeRange *ranges = self.transitionRanges.bytes;
    NSUInteger count = self.transitionRanges.length / sizeof(BAEventTimeRange);
    NSTimeInterval start = interval.startDate.timeIntervalSince1970, end = interval.endDate.timeIntervalSince1970;
    // Interval starts are ordered; their ends may be nested or overlap. Only
    // advance by start, so a long earlier interval cannot hide a later boundary.
    while (*cursor < count && ranges[*cursor].end <= start) (*cursor)++;
    if (*cursor < count && ranges[*cursor].start < end && ranges[*cursor].end > start)
        return BAAnalyticsObservedStateUnknown;
    return interval.state;
}

- (void)drawState:(BAAnalyticsObservedState)state inRect:(CGRect)rect vertical:(BOOL)vertical {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context || CGRectIsEmpty(rect)) return;
    UIColor *color = BAProcessStateColor(state);
    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, UIColor.compatBackgroundColor.CGColor);
    CGContextFillRect(context, rect);
    if (state == BAAnalyticsObservedStateUnknown) {
        BAProcessHatch(rect, color);
    } else {
        CGFloat alpha = state == BAAnalyticsObservedStateUnplugged ? 0.08 : 0.56;
        CGContextSetFillColorWithColor(context, [color colorWithAlphaComponent:alpha].CGColor);
        CGContextFillRect(context, rect);
    }
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 1);
    CGFloat dash[] = {3, 2};
    if (state == BAAnalyticsObservedStateConnectedNotCharging) CGContextSetLineDash(context, 0, dash, 2);
    CGContextStrokeRect(context, CGRectInset(rect, 0.5, 0.5));
    if (state == BAAnalyticsObservedStateFull && CGRectGetWidth(rect) > 5 && CGRectGetHeight(rect) > 5)
        CGContextStrokeRect(context, CGRectInset(rect, 2.5, 2.5));
    CGContextRestoreGState(context);
    CGFloat span = vertical ? CGRectGetHeight(rect) : CGRectGetWidth(rect);
    if (span >= 16) {
        UIFont *font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        CGRect label = CGRectMake(CGRectGetMidX(rect) - 8, CGRectGetMidY(rect) - 7, 16, 15);
        BAProcessText(BAEventSymbol(state), label, font, UIColor.compatLabelColor, NSTextAlignmentCenter);
    }
}

- (void)stateStrip:(CGRect)plot vertical:(BOOL)vertical family:(BAAnalyticsFamilyReport *)family
       transitions:(NSArray<BAAnalyticsStateTransition *> *)transitions regions:(NSMutableArray *)regions {
    (void)transitions;
    BAAnalyticsHistoryWindow *window = family.window;
    BOOL collect = UIGraphicsGetCurrentContext() == NULL, dense = window.intervals.count + window.gaps.count > 192;
    if (collect && dense) {
        [regions addObjectsFromArray:BAProcessTimeSliceRegions(self, BAEventStateMetrics(), window.startDate, window.endDate,
            plot, vertical, nil, @{@"stateBoundaries":_("Sampled ranges; mixed and unknown states remain separate in the evidence")})];
        return;
    }
    BAProcessHatch(plot, UIColor.compatSecondaryLabelColor);
    NSArray *ordered = self.preparedIntervals;
    NSDate *cursor = window.startDate;
    NSUInteger transitionCursor = 0;
    NSDate *runFirst = nil, *runLast = nil;
    BAAnalyticsObservedState runState = BAAnalyticsObservedStateUnknown;
    BAAnalyticsHistoryInterval *previous = nil;
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[], window.gaps)) {
            if (runFirst) [self drawState:runState inRect:BAEventSpan(runFirst, runLast, window, plot, vertical) vertical:vertical];
            runFirst = nil; previous = nil;
            continue;
        }
        NSDate *first = BAEventLater(interval.startDate, window.startDate);
        NSDate *last = BAEventEarlier(interval.endDate, window.endDate);
        if ([last compare:first] != NSOrderedDescending) continue;
        if ([first compare:cursor] == NSOrderedDescending) {
            CGRect gapRect = BAEventSpan(cursor, first, window, plot, vertical);
            if (collect && !dense) [regions addObject:BAProcessRegion(gapRect, BAProcessSelection(self, @"gap", @[], BAEventStateMetrics(), cursor, first,
                @{@"state":@(BAAnalyticsObservedStateUnknown), @"eventCountKnown":@NO}),
                [NSString stringWithFormat:_("Unknown state, %@; events in this gap are unknown"), BAProcessWindow(cursor, first)])];
        }
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
        BAAnalyticsObservedState state = [self stateForInterval:interval transitionCursor:&transitionCursor];
        CGRect band = CGRectZero;
        if (dense) {
            BOOL adjacent = runFirst && runState == state && [runLast isEqualToDate:first] &&
                [previous.endObservation.identifier isEqualToString:interval.startObservation.identifier] &&
                !BAAnalyticsHistoryHasGap(window.gaps, runFirst, last, NO);
            if (runFirst && !adjacent) {
                [self drawState:runState inRect:BAEventSpan(runFirst, runLast, window, plot, vertical) vertical:vertical];
                runFirst = nil;
            }
            if (!runFirst) { runFirst = first; runState = state; }
            runLast = last; previous = interval;
        } else {
            band = BAEventSpan(first, last, window, plot, vertical);
            [self drawState:state inRect:band vertical:vertical];
        }
        if (collect && !dense) {
            NSDictionary *evidence = @{@"state":@(state), @"reportedState":@(interval.state), @"boundaryEstimate":@YES,
                @"clippedStartTimestamp":@([first timeIntervalSince1970]), @"clippedEndTimestamp":@([last timeIntervalSince1970]),
                @"intervalIdentifier":[NSString stringWithFormat:@"%@:%@", interval.startObservation.identifier, interval.endObservation.identifier]};
            [regions addObject:BAProcessRegion(band, BAProcessSelection(self, @"interval",
                @[interval.startObservation.identifier, interval.endObservation.identifier], BAEventStateMetrics(),
                interval.startObservation.timestamp, interval.endObservation.timestamp, evidence),
                [NSString stringWithFormat:_("%@, approximately %@, sampled interval %@"), BAProcessStateName(state),
                 BAProcessDuration([last timeIntervalSinceDate:first]), BAProcessWindow(first, last)])];
        }
    }
    if (runFirst) [self drawState:runState inRect:BAEventSpan(runFirst, runLast, window, plot, vertical) vertical:vertical];
    if ([window.endDate compare:cursor] == NSOrderedDescending) {
        CGRect gapRect = BAEventSpan(cursor, window.endDate, window, plot, vertical);
        if (collect && !dense) [regions addObject:BAProcessRegion(gapRect, BAProcessSelection(self, @"gap", @[], BAEventStateMetrics(), cursor, window.endDate,
            @{@"state":@(BAAnalyticsObservedStateUnknown), @"eventCountKnown":@NO}),
            [NSString stringWithFormat:_("Unknown state, %@; events in this gap are unknown"), BAProcessWindow(cursor, window.endDate)])];
    }
    // Explicit gaps retain the source reason, rather than becoming unplugged.
    for (BAAnalyticsHistoryGap *gap in window.gaps) {
        NSDate *first = BAEventLater(gap.startDate, window.startDate);
        NSDate *last = BAEventEarlier(gap.endDate, window.endDate);
        if ([last compare:first] != NSOrderedDescending) continue;
        CGRect band = BAEventSpan(first, last, window, plot, vertical);
        [self drawState:BAAnalyticsObservedStateUnknown inRect:band vertical:vertical];
        if (collect && !dense) [regions addObject:BAProcessRegion(band, BAProcessSelection(self, @"gap", @[], BAEventStateMetrics(), first, last,
            @{@"reason":gap.reason, @"state":@(BAAnalyticsObservedStateUnknown), @"eventCountKnown":@NO}),
            [NSString stringWithFormat:_("Unknown state, %@, %@; no event count inferred"), BAProcessWindow(first, last), gap.reason])];
    }
}

- (NSArray<NSString *> *)recordsForTransition:(BAAnalyticsStateTransition *)transition window:(BAAnalyticsHistoryWindow *)window {
    NSMutableArray *records = [NSMutableArray arrayWithObject:transition.identifier];
    for (BAAnalyticsObservation *observation in window.observations) {
        if (!observation.timestampValidated) continue;
        if ([observation.timestamp isEqualToDate:transition.earliestDate] || [observation.timestamp isEqualToDate:transition.latestDate])
            [records addObject:observation.identifier];
        if (records.count == 256) break;
    }
    return records;
}

- (void)transitionMarks:(CGRect)track vertical:(BOOL)vertical family:(BAAnalyticsFamilyReport *)family
             transitions:(NSArray<BAAnalyticsStateTransition *> *)transitions regions:(NSMutableArray *)regions {
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL collect = context == NULL, dense = transitions.count > 128;
    if (collect && dense) {
        [regions addObjectsFromArray:BAProcessTimeSliceRegions(self, [BAEventStateMetrics() arrayByAddingObject:BAAnalyticsHistoryNotChargingReasonCode],
            family.window.startDate, family.window.endDate, track, vertical, nil, @{@"transitionBoundaries":_("earliest/latest sampled ranges")})];
        return;
    }
    for (BAAnalyticsStateTransition *transition in transitions) {
        NSDate *first = BAEventLater(transition.earliestDate, family.window.startDate);
        NSDate *last = BAEventEarlier(transition.latestDate, family.window.endDate);
        CGRect range = BAEventSpan(first, last, family.window, track, vertical);
        CGRect mark = vertical ? CGRectMake(CGRectGetMinX(track), CGRectGetMidY(range) - 4, CGRectGetWidth(track), 8) :
            CGRectMake(CGRectGetMidX(range) - 4, CGRectGetMinY(track), 8, CGRectGetHeight(track));
        if (context) {
            CGContextSaveGState(context);
            UIColor *color = BAProcessStateColor(transition.nextState);
            CGContextSetStrokeColorWithColor(context, color.CGColor);
            CGContextSetFillColorWithColor(context, [color colorWithAlphaComponent:0.15].CGColor);
            CGContextSetLineWidth(context, 1.5);
            CGContextFillRect(context, range);
            // The bracket shows both sampled bounds. Its centre is not an exact event time.
            if (vertical) {
                CGFloat x = CGRectGetMidX(track);
                CGContextMoveToPoint(context, x, CGRectGetMinY(range));
                CGContextAddLineToPoint(context, x, CGRectGetMaxY(range));
                CGContextMoveToPoint(context, x - 3, CGRectGetMinY(range));
                CGContextAddLineToPoint(context, x + 3, CGRectGetMinY(range));
                CGContextMoveToPoint(context, x - 3, CGRectGetMaxY(range));
                CGContextAddLineToPoint(context, x + 3, CGRectGetMaxY(range));
            } else {
                CGFloat y = CGRectGetMidY(track);
                CGContextMoveToPoint(context, CGRectGetMinX(range), y);
                CGContextAddLineToPoint(context, CGRectGetMaxX(range), y);
                CGContextMoveToPoint(context, CGRectGetMinX(range), y - 3);
                CGContextAddLineToPoint(context, CGRectGetMinX(range), y + 3);
                CGContextMoveToPoint(context, CGRectGetMaxX(range), y - 3);
                CGContextAddLineToPoint(context, CGRectGetMaxX(range), y + 3);
            }
            CGContextStrokePath(context);
            CGContextFillEllipseInRect(context, CGRectInset(mark, vertical ? 1 : 0, vertical ? 0 : 1));
            CGContextRestoreGState(context);
        }
        if (!collect || dense) continue;
        NSMutableDictionary *evidence = [@{@"transitionIdentifier":transition.identifier,
            @"previousState":@(transition.previousState), @"nextState":@(transition.nextState), @"boundaryEstimate":@YES,
            @"earliestTimestamp":@([transition.earliestDate timeIntervalSince1970]),
            @"latestTimestamp":@([transition.latestDate timeIntervalSince1970])} mutableCopy];
        if (transition.reasonCode) evidence[@"reasonCode"] = transition.reasonCode;
        NSArray *metrics = [BAEventStateMetrics() arrayByAddingObjectsFromArray:
            @[BAAnalyticsHistoryNotChargingReasonCode, BAAnalyticsHistoryCurrentMilliamps]];
        NSString *label = [NSString stringWithFormat:_("Observed %@ to %@, between %@ and %@; exact transition time unknown%@"),
            BAProcessStateName(transition.previousState), BAProcessStateName(transition.nextState),
            BAEventDate(transition.earliestDate), BAEventDate(transition.latestDate),
            transition.reasonCode ? [NSString stringWithFormat:_("; system reason code %@, meaning not inferred"), transition.reasonCode] : @""];
        [regions addObject:BAProcessRegion(CGRectUnion(range, mark), BAProcessSelection(self, @"transition",
            [self recordsForTransition:transition window:family.window], metrics,
            transition.earliestDate, transition.latestDate, evidence), label)];
    }
}

- (void)verticalCurrent:(CGRect)plot family:(BAAnalyticsFamilyReport *)family minimum:(double)minimum maximum:(double)maximum
                 regions:(NSMutableArray *)regions {
    BAAnalyticsHistoryWindow *window = family.window;
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL collect = context == NULL, dense = window.observations.count + window.intervals.count > 192;
    if (dense) {
        if (collect) {
            [regions addObjectsFromArray:BAProcessTimeSliceRegions(self, @[BAAnalyticsHistoryCurrentMilliamps],
                window.startDate, window.endDate, plot, YES, nil, @{@"unit":@"A", @"signed":@YES})];
            return;
        }
        CGContextSaveGState(context);
        CGContextClipToRect(context, plot);
        CGContextSetFillColorWithColor(context, UIColor.compatBackgroundColor.CGColor);
        CGContextFillRect(context, plot);
        // Reuse the bounded trace envelope. The orthogonal transform maps its
        // time axis to y and signed current to x; existing labels stay outside.
        CGContextTranslateCTM(context, plot.origin.x, plot.origin.y);
        CGContextConcatCTM(context, CGAffineTransformMake(0, 1, -1, 0, plot.size.width, 0));
        BAProcessTrace(self, window.observations, window.intervals, window.gaps, BAAnalyticsHistoryCurrentMilliamps, @"A",
            window.startDate, window.endDate, CGRectMake(0, 0, plot.size.height, plot.size.width), minimum, maximum,
            1000, UIColor.compatBlueColor, NO, nil);
        CGContextRestoreGState(context);
        CGContextSaveGState(context);
        CGFloat zeroX = CGRectGetMinX(plot) + (0 - minimum) / (maximum - minimum) * CGRectGetWidth(plot);
        CGFloat dash[] = {2, 3};
        CGContextSetStrokeColorWithColor(context, UIColor.compatSeparatorColor.CGColor);
        CGContextSetLineDash(context, 0, dash, 2);
        CGContextMoveToPoint(context, zeroX, CGRectGetMinY(plot));
        CGContextAddLineToPoint(context, zeroX, CGRectGetMaxY(plot));
        CGContextStrokePath(context);
        CGContextRestoreGState(context);
        return;
    }
    if (context) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, plot);
    }
    BAProcessHatch(plot, UIColor.compatSecondaryLabelColor);
    NSArray *ordered = BAProcessOrderedIntervals(window.intervals);
    NSDate *cursor = window.startDate;
    for (BAAnalyticsHistoryInterval *interval in ordered) {
        if (!BAProcessIntervalUsable(interval, @[BAAnalyticsHistoryCurrentMilliamps], window.gaps)) continue;
        NSDate *first = BAEventLater(interval.startDate, window.startDate);
        NSDate *last = BAEventEarlier(interval.endDate, window.endDate);
        if ([last compare:first] != NSOrderedDescending) continue;
        if ([first compare:cursor] == NSOrderedDescending) {
            CGRect missing = BAEventSpan(cursor, first, window, plot, YES);
            if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(self, @"gap", @[], @[BAAnalyticsHistoryCurrentMilliamps],
                cursor, first, @{@"unit":@"A", @"signed":@YES}),
                [NSString stringWithFormat:_("Battery current unavailable, %@"), BAProcessWindow(cursor, first)])];
        }
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
        CGRect band = BAEventSpan(first, last, window, plot, YES);
        CGFloat x0 = CGRectGetMinX(plot) + (BAEventCurrentAt(interval, first) - minimum) / (maximum - minimum) * CGRectGetWidth(plot);
        CGFloat x1 = CGRectGetMinX(plot) + (BAEventCurrentAt(interval, last) - minimum) / (maximum - minimum) * CGRectGetWidth(plot);
        if (context) {
            CGContextSetFillColorWithColor(context, UIColor.compatBackgroundColor.CGColor);
            CGContextFillRect(context, band);
            CGContextSetStrokeColorWithColor(context, UIColor.compatBlueColor.CGColor);
            CGContextSetLineWidth(context, 1.6);
            CGContextMoveToPoint(context, x0, CGRectGetMinY(band));
            CGContextAddLineToPoint(context, x1, CGRectGetMaxY(band));
            CGContextStrokePath(context);
        }
        CGRect segment = CGRectMake(MIN(x0, x1), CGRectGetMinY(band), MAX(1, fabs(x1 - x0)), CGRectGetHeight(band));
        if (collect && !dense) [regions addObject:BAProcessRegion(segment, BAProcessSelection(self, @"interval",
            @[interval.startObservation.identifier, interval.endObservation.identifier], @[BAAnalyticsHistoryCurrentMilliamps],
            interval.startObservation.timestamp, interval.endObservation.timestamp,
            @{@"unit":@"A", @"signed":@YES, @"clippedStartTimestamp":@([first timeIntervalSince1970]),
              @"clippedEndTimestamp":@([last timeIntervalSince1970])}),
            [NSString stringWithFormat:_("Signed battery current, approximately %@, %+.3g to %+.3g A"),
             BAProcessWindow(first, last), BAEventCurrentAt(interval, first), BAEventCurrentAt(interval, last)])];
    }
    if ([window.endDate compare:cursor] == NSOrderedDescending) {
        CGRect missing = BAEventSpan(cursor, window.endDate, window, plot, YES);
        if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(self, @"gap", @[], @[BAAnalyticsHistoryCurrentMilliamps],
            cursor, window.endDate, @{@"unit":@"A", @"signed":@YES}),
            [NSString stringWithFormat:_("Battery current unavailable, %@"), BAProcessWindow(cursor, window.endDate)])];
    }
    if (context) {
        CGFloat zeroX = CGRectGetMinX(plot) + (0 - minimum) / (maximum - minimum) * CGRectGetWidth(plot);
        CGContextSetStrokeColorWithColor(context, UIColor.compatSeparatorColor.CGColor);
        CGFloat dash[] = {2, 3};
        CGContextSetLineDash(context, 0, dash, 2);
        CGContextMoveToPoint(context, zeroX, CGRectGetMinY(plot));
        CGContextAddLineToPoint(context, zeroX, CGRectGetMaxY(plot));
        CGContextStrokePath(context);
        CGContextSetLineDash(context, 0, NULL, 0);
        CGContextSetFillColorWithColor(context, UIColor.compatBlueColor.CGColor);
    }
    for (BAAnalyticsObservation *observation in window.observations) {
        NSNumber *value = BAProcessValue(observation, BAAnalyticsHistoryCurrentMilliamps);
        if (!value || [observation.timestamp compare:window.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:window.endDate] == NSOrderedDescending) continue;
        CGFloat x = CGRectGetMinX(plot) + (value.doubleValue / 1000.0 - minimum) / (maximum - minimum) * CGRectGetWidth(plot);
        CGRect timeAxis = CGRectMake(CGRectGetMinY(plot), 0, CGRectGetHeight(plot), 1);
        CGFloat y = BAProcessTimeX(observation.timestamp, window.startDate, window.endDate, timeAxis);
        CGRect dot = CGRectMake(x - 2, y - 2, 4, 4);
        if (context) CGContextFillEllipseInRect(context, dot);
        if (collect && !dense) [regions addObject:BAProcessRegion(dot, BAProcessSelection(self, @"record", @[observation.identifier],
            @[BAAnalyticsHistoryCurrentMilliamps], observation.timestamp, observation.timestamp, @{@"unit":@"A", @"signed":@YES}),
            [NSString stringWithFormat:_("%@, signed battery current %+.3g A"), BAEventDate(observation.timestamp), value.doubleValue / 1000.0])];
    }
    if (context) CGContextRestoreGState(context);
}

- (NSTimeInterval)knownStateDuration:(BAAnalyticsFamilyReport *)family transitions:(NSArray *)transitions {
    (void)transitions;
    [self transitionsForFamily:family];
    if (self.preparedKnownDuration) return self.preparedKnownDuration.doubleValue;
    NSTimeInterval duration = 0;
    NSDate *cursor = family.window.startDate;
    NSUInteger transitionCursor = 0;
    for (BAAnalyticsHistoryInterval *interval in self.preparedIntervals) {
        if (!BAProcessIntervalUsable(interval, @[], family.window.gaps) ||
            [self stateForInterval:interval transitionCursor:&transitionCursor] == BAAnalyticsObservedStateUnknown) continue;
        NSDate *first = BAEventLater(BAEventLater(interval.startDate, family.window.startDate), cursor);
        NSDate *last = BAEventEarlier(interval.endDate, family.window.endDate);
        if ([last compare:first] == NSOrderedDescending) duration += [last timeIntervalSinceDate:first];
        if ([last compare:cursor] == NSOrderedDescending) cursor = last;
    }
    self.preparedKnownDuration = @(duration);
    return duration;
}

- (void)legend:(CGRect)rect compact:(BOOL)compact vertical:(BOOL)vertical family:(BAAnalyticsFamilyReport *)family regions:(NSMutableArray *)regions {
    NSArray *states = @[@(BAAnalyticsObservedStateCharging), @(BAAnalyticsObservedStateConnectedNotCharging),
        @(BAAnalyticsObservedStateFull), @(BAAnalyticsObservedStateUnplugged), @(BAAnalyticsObservedStateUnknown)];
    UIFont *font = BAProcessFont(UIFontTextStyleCaption2, 11, UIFontWeightRegular);
    NSUInteger columns = BAEventLegendColumns(CGRectGetWidth(rect), font, compact, vertical);
    NSUInteger rows = (states.count + columns - 1) / columns;
    CGFloat cellWidth = CGRectGetWidth(rect) / columns;
    CGFloat cellHeight = CGRectGetHeight(rect) / rows;
    CGFloat cursorY = CGRectGetMinY(rect);
    for (NSUInteger index = 0; index < states.count; index++) {
        BAAnalyticsObservedState state = [states[index] integerValue];
        if (vertical && !compact) cellHeight = BAEventLegendLabelHeight(state, cellWidth - 19, font) + 2;
        CGRect cell = CGRectMake(CGRectGetMinX(rect) + (index % columns) * cellWidth,
            vertical && !compact ? cursorY : CGRectGetMinY(rect) + (index / columns) * cellHeight, cellWidth, cellHeight);
        cursorY = CGRectGetMaxY(cell);
        CGRect swatch = CGRectMake(CGRectGetMinX(cell), CGRectGetMidY(cell) - 5, 12, 10);
        [self drawState:state inRect:swatch vertical:NO];
        NSString *text = compact ? BAEventSymbol(state) : BAEventShortName(state);
        BAProcessText(text, CGRectMake(CGRectGetMinX(cell) + 16, CGRectGetMinY(cell), MAX(0, cellWidth - 19), cellHeight),
            font, UIColor.compatSecondaryLabelColor, NSTextAlignmentLeft);
        [regions addObject:BAProcessRegion(cell, BAProcessSelection(self, @"legend", @[], BAEventStateMetrics(),
            family.window.startDate, family.window.endDate, @{@"state":@(state), @"legend":@YES}),
            [NSString stringWithFormat:_("%@ means %@; sampled state in this window"), BAEventSymbol(state), BAProcessStateName(state)])];
    }
}

- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderEvidence {
    NSMutableArray *regions = [NSMutableArray array];
    CGRect bounds = CGRectInset(self.bounds, 12, 10);
    if (CGRectIsEmpty(bounds)) return regions;
    BAAnalyticsFamilyReport *family = BAProcessFamily(self);
    UIFont *caption = BAProcessFont(UIFontTextStyleCaption1, 11, UIFontWeightRegular);
    UIFont *secondary = BAProcessFont(UIFontTextStyleCaption2, 11, UIFontWeightRegular);
    if (!family || family.availability == BAAnalyticsReportAvailabilityLoading ||
        family.availability == BAAnalyticsReportAvailabilityUnavailable ||
        [family.window.endDate compare:family.window.startDate] != NSOrderedDescending) {
        BAProcessHatch(CGRectInset(bounds, 0, 26), UIColor.compatSecondaryLabelColor);
        BAProcessText(_("Observed states"), CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, caption.lineHeight * 2),
            caption, UIColor.compatLabelColor, NSTextAlignmentLeft);
        BAProcessText(BAProcessAvailability(family), CGRectMake(bounds.origin.x, CGRectGetMidY(bounds) - caption.lineHeight,
            bounds.size.width, caption.lineHeight * 3), caption, UIColor.compatSecondaryLabelColor, NSTextAlignmentLeft);
        self.accessibilityLabel = [NSString stringWithFormat:_("Observed states. %@"), BAProcessAvailability(family)];
        [regions addObject:BAProcessRegion(bounds, BAProcessSelection(self, @"metric", @[], BAEventStateMetrics(),
            family.window.startDate, family.window.endDate, @{@"availability":@(family ? family.availability : BAAnalyticsReportAvailabilityLoading)}),
            [NSString stringWithFormat:_("Observed states. %@"), BAProcessAvailability(family)])];
        return regions;
    }
    BAAnalyticsHistoryWindow *window = family.window;
    NSArray *transitions = [self transitionsForFamily:family];
    BOOL vertical = self.cardSize == BAAnalyticsCardSize1x2;
    BOOL expanded = self.cardSize == BAAnalyticsCardSize2x2;
    BOOL largeText = BAProcessLargeText(self);
    NSString *range = vertical ? [NSString stringWithFormat:_("%@\n→ %@"), BAEventDate(window.startDate), BAEventDate(window.endDate)] :
        BAProcessWindow(window.startDate, window.endDate);
    CGFloat headerHeight = [range boundingRectWithSize:CGSizeMake(bounds.size.width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:caption} context:nil].size.height;
    headerHeight = ceil(MAX(headerHeight, caption.lineHeight));
    NSTimeInterval requested = [window.endDate timeIntervalSinceDate:window.startDate];
    NSTimeInterval known = [self knownStateDuration:family transitions:transitions];
    BOOL hasUnknown = known < requested - 0.5;
    NSString *summary = [NSString stringWithFormat:_("Known %@ / %@"), BAProcessDuration(known), BAProcessDuration(requested)];
    NSString *events = [NSString stringWithFormat:_("%lu sampled changes%@"), (unsigned long)transitions.count,
        hasUnknown ? _(" · gap events unknown") : @""];
    if (known == 0 && transitions.count == 0) events = _("No verified states");
    NSString *footer = largeText ? summary : [NSString stringWithFormat:@"%@\n%@", summary, events];
    CGFloat footerHeight = ceil([footer boundingRectWithSize:CGSizeMake(bounds.size.width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:secondary} context:nil].size.height) + 3;
    CGFloat fullLegendHeight = 0, maximumLabelHeight = 0;
    NSUInteger legendColumns = BAEventLegendColumns(bounds.size.width, secondary, NO, vertical);
    CGFloat legendLabelWidth = bounds.size.width / legendColumns - 19;
    for (NSNumber *state in @[@(BAAnalyticsObservedStateCharging), @(BAAnalyticsObservedStateConnectedNotCharging),
            @(BAAnalyticsObservedStateFull), @(BAAnalyticsObservedStateUnplugged), @(BAAnalyticsObservedStateUnknown)]) {
        CGFloat labelHeight = BAEventLegendLabelHeight(state.integerValue, legendLabelWidth, secondary) + 2;
        fullLegendHeight += labelHeight;
        maximumLabelHeight = MAX(maximumLabelHeight, labelHeight);
    }
    if (!vertical) fullLegendHeight = maximumLabelHeight * ceil(5.0 / legendColumns);
    BOOL compactLegend = headerHeight + fullLegendHeight + footerHeight + 38 > bounds.size.height;
    CGFloat legendHeight = compactLegend ? secondary.lineHeight + 6 : fullLegendHeight;
    CGFloat top = bounds.origin.y + headerHeight + 7;
    CGFloat bottom = CGRectGetMaxY(bounds) - footerHeight - legendHeight - 7;
    CGFloat plotHeight = MAX(12, bottom - top);
    BAProcessText(range, CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, headerHeight), caption,
        UIColor.compatSecondaryLabelColor, NSTextAlignmentLeft);
    CGRect legendRect = CGRectMake(bounds.origin.x, bottom + 4, bounds.size.width, legendHeight);
    [self legend:legendRect compact:compactLegend vertical:vertical family:family regions:regions];
    CGRect footerRect = CGRectMake(bounds.origin.x, CGRectGetMaxY(bounds) - footerHeight, bounds.size.width, footerHeight);
    BAProcessText(footer, footerRect, secondary,
        UIColor.compatSecondaryLabelColor, NSTextAlignmentLeft);
    [regions addObject:BAProcessRegion(footerRect, BAProcessSelection(self, @"coverage", @[], BAEventStateMetrics(), window.startDate, window.endDate,
        @{@"knownStateSeconds":@(known), @"requestedSeconds":@(requested), @"observedTransitionCount":@(transitions.count),
          @"gapEventCountKnown":@(!hasUnknown)}), [NSString stringWithFormat:_("%@. %@. Transition times are bounded by samples"), summary, events])];
    double minimum = 0, maximum = 0;
    BOOL hasCurrent = NO;
    for (BAAnalyticsObservation *observation in window.observations) {
        NSNumber *value = BAProcessValue(observation, BAAnalyticsHistoryCurrentMilliamps);
        if (!value || [observation.timestamp compare:window.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:window.endDate] == NSOrderedDescending) continue;
        hasCurrent = YES;
        minimum = MIN(minimum, value.doubleValue / 1000.0);
        maximum = MAX(maximum, value.doubleValue / 1000.0);
    }
    double margin = MAX(0.05, (maximum - minimum) * 0.08);
    minimum -= margin;
    maximum += margin;
    BOOL showCurrent = hasCurrent && !largeText && !compactLegend && (vertical || expanded) && plotHeight > 65;
    if (vertical) {
        CGRect strip = CGRectMake(bounds.origin.x + 3, top, 14, plotHeight);
        [self stateStrip:strip vertical:YES family:family transitions:transitions regions:regions];
        CGRect marks = CGRectMake(CGRectGetMaxX(strip) + 5, top, 10, plotHeight);
        [self transitionMarks:marks vertical:YES family:family transitions:transitions regions:regions];
        if (showCurrent) {
            // Keep the unit beside the trace, outside its value/time domain.
            // Both vertical tracks still use the same full time range.
            NSString *unit = _("A ±");
            CGFloat unitWidth = ceil([unit sizeWithAttributes:@{NSFontAttributeName:secondary}].width);
            CGRect unitRect = CGRectMake(CGRectGetMaxX(marks) + 3, top, unitWidth, secondary.lineHeight + 2);
            CGFloat currentLeft = CGRectGetMaxX(unitRect) + 5;
            CGRect current = CGRectMake(currentLeft, top,
                MAX(12, CGRectGetMaxX(bounds) - currentLeft), plotHeight);
            [self verticalCurrent:current family:family minimum:minimum maximum:maximum regions:regions];
            BAProcessText(unit, unitRect, secondary, UIColor.compatBlueColor, NSTextAlignmentLeft);
        } else {
            BAAnalyticsDrawGlyph(BAAnalyticsGlyphClock, CGRectMake(CGRectGetMaxX(marks) + 10, top + 2, 16, 16),
                UIColor.compatSecondaryLabelColor);
        }
    } else {
        CGFloat stripHeight = MIN(28, showCurrent ? plotHeight * 0.25 : plotHeight - 14);
        stripHeight = MAX(12, stripHeight);
        CGRect strip = CGRectMake(bounds.origin.x, top, bounds.size.width, stripHeight);
        [self stateStrip:strip vertical:NO family:family transitions:transitions regions:regions];
        CGRect marks = CGRectMake(bounds.origin.x, CGRectGetMaxY(strip) + 4, bounds.size.width, 8);
        [self transitionMarks:marks vertical:NO family:family transitions:transitions regions:regions];
        if (showCurrent) {
            CGFloat currentTop = CGRectGetMaxY(marks) + secondary.lineHeight + 7;
            CGRect current = CGRectMake(bounds.origin.x, currentTop, bounds.size.width, MAX(12, bottom - currentTop));
            BAProcessText(_("signed A"), CGRectMake(bounds.origin.x, CGRectGetMaxY(marks) + 3, bounds.size.width, secondary.lineHeight + 2), secondary,
                UIColor.compatBlueColor, NSTextAlignmentLeft);
            [regions addObjectsFromArray:BAProcessTrace(self, window.observations, window.intervals, window.gaps,
                BAAnalyticsHistoryCurrentMilliamps, @"A", window.startDate, window.endDate, current,
                minimum, maximum, 1000.0, UIColor.compatBlueColor, NO, nil)];
        }
    }
    self.accessibilityLabel = [NSString stringWithFormat:_("Observed states, %@. %@. %@. C charging; two bars connected but not charging; F full; U unplugged; question mark unknown."),
        BAProcessWindow(window.startDate, window.endDate), summary, events];
    return regions;
}

@end

@implementation BAAnalyticsEventsCanvasCard

- (instancetype)init {
    return [super initWithIdentifier:@"com.torrekie.battman.analytics.events" displayName:_("Connection and charging states")
        familyIdentifier:BAAnalyticsFamilyEvents
        supportedSizes:BAAnalyticsCardSizeMask1x2 | BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2
        defaultSize:BAAnalyticsCardSize1x2];
}

- (BAAnalyticsCanvasView *)makeCanvasView {
    BAAnalyticsEventsCanvasView *view = [BAAnalyticsEventsCanvasView new];
    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    return view;
}

- (void)updateCanvasView:(BAAnalyticsCanvasView *)view {
    [view setNeedsLayout];
    [view setNeedsDisplay];
}

@end
