#import "../Canvas/BAAnalyticsDetailViewController.h"
#import "main.h"
#import "BAAnalyticsDischargeCanvasCard.h"
#import "BAAnalyticsProcessDrawing.h"
#include <math.h>

typedef struct {
    NSTimeInterval socSeconds;
    NSTimeInterval powerSeconds;
    double socLoss;
    double outputWattHours;
} BADischargeStatistics;

// The interval may be clipped, while its observations retain the original
// sample times. Never move an endpoint reading to the clipped boundary.
static double BADischargeInterpolatedValue(BAAnalyticsHistoryInterval *interval, NSString *metric, NSDate *date) {
    double first = BAProcessValue(interval.startObservation, metric).doubleValue;
    double last = BAProcessValue(interval.endObservation, metric).doubleValue;
    NSTimeInterval span = [interval.endObservation.timestamp timeIntervalSinceDate:interval.startObservation.timestamp];
    double fraction = span > 0 ? [date timeIntervalSinceDate:interval.startObservation.timestamp] / span : 0;
    return first + (last - first) * MIN(1.0, MAX(0.0, fraction));
}

static NSArray<BAAnalyticsHistoryInterval *> *BADischargeIntervals(BAAnalyticsHistorySession *session) {
    NSMutableArray *intervals = [NSMutableArray array];
    for (BAAnalyticsHistoryInterval *interval in session.intervals) {
        // A transition pair is Unknown, even when one endpoint is unplugged.
        if (interval.state == BAAnalyticsObservedStateUnplugged) [intervals addObject:interval];
    }
    [intervals sortUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) {
        NSComparisonResult order = [a.startDate compare:b.startDate];
        return order == NSOrderedSame ? [a.endDate compare:b.endDate] : order;
    }];
    return intervals;
}

static BOOL BADischargeClip(BAAnalyticsHistoryInterval *interval, BAAnalyticsHistorySession *session,
        NSDate *cursor, NSDate **first, NSDate **last) {
    NSDate *start = [interval.startDate compare:session.startDate] == NSOrderedAscending ? session.startDate : interval.startDate;
    NSDate *end = [interval.endDate compare:session.endDate] == NSOrderedDescending ? session.endDate : interval.endDate;
    if ([start compare:cursor] == NSOrderedAscending) start = cursor;
    // Reject extrapolation, including degenerate or reversed sample pairs.
    if ([interval.endObservation.timestamp compare:interval.startObservation.timestamp] != NSOrderedDescending ||
        [start compare:interval.startObservation.timestamp] == NSOrderedAscending ||
        [end compare:interval.endObservation.timestamp] == NSOrderedDescending ||
        [end compare:start] != NSOrderedDescending) return NO;
    *first = start;
    *last = end;
    return YES;
}

static BADischargeStatistics BADischargeSummarize(BAAnalyticsHistorySession *session,
        NSArray<BAAnalyticsHistoryInterval *> *intervals) {
    BADischargeStatistics result = {0, 0, 0, 0};
    NSDate *socCursor = session.startDate;
    NSDate *powerCursor = session.startDate;
    for (BAAnalyticsHistoryInterval *interval in intervals) {
        NSDate *first = nil, *last = nil;
        if (BAProcessIntervalUsable(interval, @[BAAnalyticsHistorySOCPercent], session.gaps) &&
            BADischargeClip(interval, session, socCursor, &first, &last)) {
            double s0 = BADischargeInterpolatedValue(interval, BAAnalyticsHistorySOCPercent, first);
            double s1 = BADischargeInterpolatedValue(interval, BAAnalyticsHistorySOCPercent, last);
            if (s0 >= 0 && s0 <= 100 && s1 >= 0 && s1 <= 100) {
                result.socSeconds += [last timeIntervalSinceDate:first];
                result.socLoss += s0 - s1;
                socCursor = last;
            }
        }
        if (BAProcessIntervalUsable(interval, @[BAAnalyticsHistoryBatteryPowerWatts], session.gaps) &&
            BADischargeClip(interval, session, powerCursor, &first, &last)) {
            NSTimeInterval seconds = [last timeIntervalSinceDate:first];
            double p0 = BADischargeInterpolatedValue(interval, BAAnalyticsHistoryBatteryPowerWatts, first);
            double p1 = BADischargeInterpolatedValue(interval, BAAnalyticsHistoryBatteryPowerWatts, last);
            double wattSeconds = 0;
            if (p0 <= 0 && p1 <= 0) wattSeconds = -(p0 + p1) * 0.5 * seconds;
            else if (p0 < 0) wattSeconds = -p0 * 0.5 * seconds * (-p0 / (p1 - p0));
            else if (p1 < 0) wattSeconds = -p1 * 0.5 * seconds * (-p1 / (p0 - p1));
            result.powerSeconds += seconds;
            result.outputWattHours += wattSeconds / 3600.0;
            powerCursor = last;
        }
    }
    return result;
}

static BAAnalyticsStateTransition *BADischargeReconnection(BAAnalyticsHistorySession *session) {
    BAAnalyticsStateTransition *boundary = nil;
    for (BAAnalyticsStateTransition *transition in session.transitions) {
        BOOL connected = transition.nextState == BAAnalyticsObservedStateCharging ||
            transition.nextState == BAAnalyticsObservedStateConnectedNotCharging || transition.nextState == BAAnalyticsObservedStateFull;
        if (transition.previousState != BAAnalyticsObservedStateUnplugged || !connected) continue;
        BOOL gap = NO;
        for (BAAnalyticsHistoryGap *missing in session.gaps) {
            if ([missing.endDate compare:transition.earliestDate] == NSOrderedDescending &&
                [missing.startDate compare:transition.latestDate] == NSOrderedAscending) { gap = YES; break; }
        }
        if (!gap && (!boundary || [transition.latestDate compare:boundary.latestDate] == NSOrderedDescending)) boundary = transition;
    }
    return boundary;
}

static NSDictionary<NSString *, id> *BADischargeContext(BAAnalyticsHistorySession *session, BADischargeStatistics statistics) {
    NSMutableDictionary *context = [@{
        @"sessionIdentifier":session.identifier,
        @"socCoverageSeconds":@(statistics.socSeconds),
        @"powerCoverageSeconds":@(statistics.powerSeconds),
        @"requestedDurationSeconds":@(MAX(0, [session.endDate timeIntervalSinceDate:session.startDate])),
        @"startBoundaryKnown":@(session.startBoundaryKnown),
        @"endBoundaryKnown":@(session.endBoundaryKnown),
        @"statisticsConvention":_("Linear interpolation within trusted unplugged sample pairs; overlapping durations unioned separately per metric. SOC loss is the signed net percentage-point change over SOC-covered intervals. Output energy integrates only the negative half of signed battery power; gaps contribute neither time nor energy."),
    } mutableCopy];
    if (statistics.socSeconds > 0) {
        context[@"socLossPercentagePoints"] = @(statistics.socLoss);
        context[@"socLossPercentagePointsPerHour"] = @(statistics.socLoss * 3600 / statistics.socSeconds);
    }
    if (statistics.powerSeconds > 0) context[@"outputWattHours"] = @(statistics.outputWattHours);
    // Shared detail lists the family transition payload. A discharge session
    // owns its boundary transition instead, so preserve that exact evidence in
    // the bounded selection context as well.
    BAAnalyticsStateTransition *reconnection = BADischargeReconnection(session);
    if (reconnection) {
        context[@"reconnectionIdentifier"] = reconnection.identifier;
        context[@"reconnectionEarliestDate"] = reconnection.earliestDate;
        context[@"reconnectionLatestDate"] = reconnection.latestDate;
        context[@"reconnectionPreviousState"] = BAProcessStateName(reconnection.previousState);
        context[@"reconnectionNextState"] = BAProcessStateName(reconnection.nextState);
        if (reconnection.reasonCode) context[@"reportedReasonCode"] = reconnection.reasonCode;
        context[@"reasonConvention"] = _("Raw system code; no pause cause or diagnosis inferred");
    }
    return context;
}

static CGFloat BADischargeTextHeight(NSString *text, CGFloat width, UIFont *font) {
    if (!(width > 0)) return 0;
    return ceil([text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:font} context:nil].size.height);
}

static void BADischargeLine(CGPoint first, CGPoint last, UIColor *color, BOOL dashed) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;
    CGContextSaveGState(context);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 1);
    CGFloat pattern[] = {3, 3};
    CGContextSetLineDash(context, 0, dashed ? pattern : NULL, dashed ? 2 : 0);
    CGContextMoveToPoint(context, first.x, first.y);
    CGContextAddLineToPoint(context, last.x, last.y);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

// Keep independent positive input, negative output extrema and a real zero
// in each display column. Energy and coverage still use the original intervals.
static NSIndexSet *BADischargePowerDisplayIndices(BAAnalyticsHistorySession *session, NSUInteger columns) {
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *buckets = [NSMutableDictionary dictionary];
    NSTimeInterval duration = [session.endDate timeIntervalSinceDate:session.startDate];
    NSUInteger first = NSNotFound, last = NSNotFound;
    for (NSUInteger i = 0; i < session.observations.count; i++) {
        BAAnalyticsObservation *observation = session.observations[i];
        NSNumber *power = BAProcessValue(observation, BAAnalyticsHistoryBatteryPowerWatts);
        if (!power || [observation.timestamp compare:session.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:session.endDate] == NSOrderedDescending) continue;
        double fraction = duration > 0 ? [observation.timestamp timeIntervalSinceDate:session.startDate] / duration : .5;
        NSNumber *column = @(MIN(columns - 1, (NSUInteger)MAX(0, floor(fraction * columns))));
        NSMutableDictionary *bucket = buckets[column];
        if (!bucket) { bucket = [NSMutableDictionary dictionary]; buckets[column] = bucket; }
        if (first == NSNotFound) first = i;
        last = i;
        NSString *kind = power.doubleValue < 0 ? @"output" : power.doubleValue > 0 ? @"input" : @"zero";
        NSNumber *prior = bucket[kind];
        NSNumber *priorPower = prior ? BAProcessValue(session.observations[prior.unsignedIntegerValue], BAAnalyticsHistoryBatteryPowerWatts) : nil;
        if (!prior || (power.doubleValue < 0 && power.doubleValue < priorPower.doubleValue) ||
            (power.doubleValue > 0 && power.doubleValue > priorPower.doubleValue)) bucket[kind] = @(i);
    }
    NSMutableIndexSet *kept = [NSMutableIndexSet indexSet];
    for (NSDictionary *bucket in buckets.allValues) for (NSNumber *index in bucket.allValues) [kept addIndex:index.unsignedIntegerValue];
    if (first != NSNotFound) { [kept addIndex:first]; [kept addIndex:last]; }
    return kept;
}

@interface BAAnalyticsDischargeCanvasView : BAAnalyticsCanvasView
@property (nonatomic, weak) BAAnalyticsHistorySession *preparedSession;
@property (nonatomic, copy) NSArray<BAAnalyticsHistoryInterval *> *preparedIntervals;
@property (nonatomic) BADischargeStatistics preparedStatistics;
@property (nonatomic, copy) NSDictionary *preparedContext;
@property (nonatomic, strong) BAAnalyticsStateTransition *preparedReconnection;
@property (nonatomic, strong) BAAnalyticsObservation *preparedFirstSOC;
@property (nonatomic, strong) BAAnalyticsObservation *preparedLastSOC;
@property (nonatomic) double preparedPowerMaximum;
@property (nonatomic) NSUInteger preparedPowerCount;
@property (nonatomic) double preparedTemperatureMinimum;
@property (nonatomic) double preparedTemperatureMaximum;
@property (nonatomic) NSUInteger preparedPowerColumns;
@property (nonatomic, copy) NSIndexSet *preparedPowerIndices;
@property (nonatomic, copy) NSData *preparedPowerMissingRanges;
- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderCanvas;
@end

@implementation BAAnalyticsDischargeCanvasView

- (void)setLatestReport:(BAAnalyticsReport *)latestReport {
    if (!latestReport || latestReport != self.latestReport) {
        self.preparedSession = nil; self.preparedIntervals = nil; self.preparedContext = nil;
        self.preparedReconnection = nil; self.preparedFirstSOC = nil; self.preparedLastSOC = nil;
        self.preparedPowerIndices = nil; self.preparedPowerMissingRanges = nil;
        self.preparedPowerColumns = 0; self.preparedPowerMaximum = 0; self.preparedPowerCount = 0;
        self.preparedTemperatureMinimum = INFINITY; self.preparedTemperatureMaximum = -INFINITY;
        self.preparedStatistics = (BADischargeStatistics){0, 0, 0, 0};
        BAProcessClearDisplayCaches(self);
    }
    [super setLatestReport:latestReport];
}

- (void)prepareSession:(BAAnalyticsHistorySession *)session {
    if (self.preparedSession == session) return;
    self.preparedSession = session;
    self.preparedIntervals = BADischargeIntervals(session);
    self.preparedStatistics = BADischargeSummarize(session, self.preparedIntervals);
    self.preparedContext = BADischargeContext(session, self.preparedStatistics);
    self.preparedReconnection = BADischargeReconnection(session);
    self.preparedFirstSOC = nil; self.preparedLastSOC = nil;
    self.preparedPowerMaximum = 0; self.preparedPowerCount = 0;
    self.preparedTemperatureMinimum = INFINITY; self.preparedTemperatureMaximum = -INFINITY;
    self.preparedPowerIndices = nil; self.preparedPowerColumns = 0;
    NSMutableData *missing = [NSMutableData data];
    NSDate *cursor = session.startDate;
    for (BAAnalyticsHistoryInterval *interval in self.preparedIntervals) {
        NSDate *first = nil, *last = nil;
        if (!BAProcessIntervalUsable(interval, @[BAAnalyticsHistoryBatteryPowerWatts], session.gaps) ||
            !BADischargeClip(interval, session, cursor, &first, &last)) continue;
        if ([first compare:cursor] == NSOrderedDescending) {
            double span[] = {cursor.timeIntervalSince1970, first.timeIntervalSince1970};
            [missing appendBytes:span length:sizeof span];
        }
        cursor = last;
    }
    if ([session.endDate compare:cursor] == NSOrderedDescending) {
        double span[] = {cursor.timeIntervalSince1970, session.endDate.timeIntervalSince1970};
        [missing appendBytes:span length:sizeof span];
    }
    self.preparedPowerMissingRanges = missing;
    for (BAAnalyticsObservation *observation in session.observations) {
        NSNumber *temperature = BAProcessValue(observation, BAAnalyticsHistoryTemperatureCelsius);
        if (temperature) {
            self.preparedTemperatureMinimum = MIN(self.preparedTemperatureMinimum, temperature.doubleValue);
            self.preparedTemperatureMaximum = MAX(self.preparedTemperatureMaximum, temperature.doubleValue);
        }
        if ([observation.timestamp compare:session.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:session.endDate] == NSOrderedDescending) continue;
        if (BAProcessValue(observation, BAAnalyticsHistorySOCPercent)) {
            if (!self.preparedFirstSOC || [observation.timestamp compare:self.preparedFirstSOC.timestamp] == NSOrderedAscending)
                self.preparedFirstSOC = observation;
            if (!self.preparedLastSOC || [observation.timestamp compare:self.preparedLastSOC.timestamp] == NSOrderedDescending)
                self.preparedLastSOC = observation;
        }
        NSNumber *power = BAProcessValue(observation, BAAnalyticsHistoryBatteryPowerWatts);
        if (power) {
            self.preparedPowerMaximum = MAX(self.preparedPowerMaximum, MAX(0, -power.doubleValue));
            self.preparedPowerCount++;
        }
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textSizeChanged:)
            name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)textSizeChanged:(NSNotification *)notification { [self setNeedsLayout]; [self setNeedsDisplay]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    NSArray *regions = [self renderCanvas];
    if (self.accessibilityValue.length)
        self.accessibilityLabel = [NSString stringWithFormat:_("Battery discharge. %@"), self.accessibilityValue];
    self.hitRegions = regions;
}
- (void)drawRect:(CGRect)rect { [self renderCanvas]; }

- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderPower:(BAAnalyticsHistorySession *)session
        intervals:(NSArray<BAAnalyticsHistoryInterval *> *)intervals plot:(CGRect)plot {
    NSMutableArray *regions = [NSMutableArray array];
    if (CGRectIsEmpty(plot)) return regions;
    NSDictionary *base = @{@"sessionIdentifier":session.identifier, @"displayConvention":_("Battery output magnitude |W|; detail preserves signed W.")};
    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL collect = context == NULL;
    BOOL dense = session.observations.count + intervals.count > 192;
    if (dense) [regions addObjectsFromArray:BAProcessTimeSliceRegions(self, @[BAAnalyticsHistoryBatteryPowerWatts],
        session.startDate, session.endDate, plot, NO, session.identifier, base)];
    if (dense && collect) return regions;
    if (dense && self.preparedPowerMissingRanges.length) {
        const double *missing = self.preparedPowerMissingRanges.bytes;
        double start = session.startDate.timeIntervalSince1970;
        NSTimeInterval duration = [session.endDate timeIntervalSinceDate:session.startDate];
        CGMutablePathRef mask = CGPathCreateMutable();
        for (NSUInteger i = 0; i < self.preparedPowerMissingRanges.length / (2 * sizeof(double)); i++) {
            CGFloat x0 = plot.origin.x + (missing[2 * i] - start) / duration * plot.size.width;
            CGFloat x1 = plot.origin.x + (missing[2 * i + 1] - start) / duration * plot.size.width;
            CGPathAddRect(mask, NULL, CGRectMake(x0, plot.origin.y, MAX(0, x1 - x0), plot.size.height));
        }
        CGContextSaveGState(context); CGContextAddPath(context, mask); CGContextClip(context);
        BAProcessHatch(plot, UIColor.compatSecondaryLabelColor);
        CGContextRestoreGState(context); CGPathRelease(mask);
    }
    if (!dense) {
        NSDate *cursor = session.startDate;
        for (BAAnalyticsHistoryInterval *interval in intervals) {
            NSDate *first = nil, *last = nil;
            if (!BAProcessIntervalUsable(interval, @[BAAnalyticsHistoryBatteryPowerWatts], session.gaps) ||
                !BADischargeClip(interval, session, cursor, &first, &last)) continue;
            CGFloat x0 = BAProcessTimeX(first, session.startDate, session.endDate, plot);
            CGFloat x1 = BAProcessTimeX(last, session.startDate, session.endDate, plot);
            if ([first compare:cursor] == NSOrderedDescending) {
                CGFloat gapX = BAProcessTimeX(cursor, session.startDate, session.endDate, plot);
                CGRect missing = CGRectMake(gapX, plot.origin.y, x0 - gapX, plot.size.height);
                BAProcessHatch(missing, UIColor.compatSecondaryLabelColor);
                if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(self, @"gap", @[], @[BAAnalyticsHistoryBatteryPowerWatts], cursor, first, base),
                    [NSString stringWithFormat:_("Battery power unavailable, %@"), BAProcessWindow(cursor, first)])];
            }
            cursor = last;
            if (collect && !dense) {
                NSMutableDictionary *details = [base mutableCopy];
                details[@"clippedStartTimestamp"] = @(first.timeIntervalSince1970);
                details[@"clippedEndTimestamp"] = @(last.timeIntervalSince1970);
                [regions addObject:BAProcessRegion(CGRectMake(x0, plot.origin.y, MAX(1, x1 - x0), plot.size.height),
                    BAProcessSelection(self, @"interval", @[interval.startObservation.identifier, interval.endObservation.identifier],
                        @[BAAnalyticsHistoryBatteryPowerWatts], interval.startObservation.timestamp, interval.endObservation.timestamp, details),
                    [NSString stringWithFormat:_("Trusted unplugged battery power, approximately %@"), BAProcessWindow(first, last)])];
            }
        }
        if ([session.endDate compare:cursor] == NSOrderedDescending) {
            CGFloat x = BAProcessTimeX(cursor, session.startDate, session.endDate, plot);
            CGRect missing = CGRectMake(x, plot.origin.y, CGRectGetMaxX(plot) - x, plot.size.height);
            BAProcessHatch(missing, UIColor.compatSecondaryLabelColor);
            if (collect && !dense) [regions addObject:BAProcessRegion(missing, BAProcessSelection(self, @"gap", @[], @[BAAnalyticsHistoryBatteryPowerWatts], cursor, session.endDate, base),
                [NSString stringWithFormat:_("Battery power unavailable, %@"), BAProcessWindow(cursor, session.endDate)])];
        }
    }
    double maximum = self.preparedPowerMaximum;
    NSUInteger count = self.preparedPowerCount;
    // A real zero has a baseline mark. Missing power has a hatch, never a zero.
    double scale = maximum > 0 ? maximum * 1.08 : 1;
    CGFloat barWidth = MIN(8, MAX(2, plot.size.width / MAX((NSUInteger)1, count) * 0.6));
    BADischargeLine(plot.origin, CGPointMake(CGRectGetMaxX(plot), plot.origin.y), UIColor.compatSeparatorColor, NO);
    NSUInteger columns = MAX(1, MIN(64, (NSUInteger)ceil(plot.size.width / 8)));
    if (dense && context && (self.preparedPowerColumns != columns || !self.preparedPowerIndices)) {
        self.preparedPowerColumns = columns;
        self.preparedPowerIndices = BADischargePowerDisplayIndices(session, columns);
    }
    NSIndexSet *displayIndices = dense && context ? self.preparedPowerIndices : nil;
    CGMutablePathRef outputPath = dense && context ? CGPathCreateMutable() : NULL;
    CGMutablePathRef inputPath = dense && context ? CGPathCreateMutable() : NULL;
    for (NSUInteger index = displayIndices ? displayIndices.firstIndex : 0; index < session.observations.count;
         index = displayIndices ? [displayIndices indexGreaterThanIndex:index] : index + 1) {
        BAAnalyticsObservation *observation = session.observations[index];
        NSNumber *power = BAProcessValue(observation, BAAnalyticsHistoryBatteryPowerWatts);
        if (!power || [observation.timestamp compare:session.startDate] == NSOrderedAscending ||
            [observation.timestamp compare:session.endDate] == NSOrderedDescending) continue;
        CGFloat x = BAProcessTimeX(observation.timestamp, session.startDate, session.endDate, plot);
        CGFloat height = MAX(1, MAX(0, -power.doubleValue) / scale * plot.size.height);
        CGRect bar = CGRectMake(MAX(plot.origin.x, MIN(CGRectGetMaxX(plot) - barWidth, x - barWidth / 2)), plot.origin.y, barWidth, height);
        if (power.doubleValue > 0) {
            // Positive net power is not output: outline its position and keep
            // the sign in its exact selection instead of turning it into |W|.
            bar.size.height = MIN(5, plot.size.height);
            if (context) {
                if (inputPath) CGPathAddRect(inputPath, NULL, CGRectInset(bar, 0.5, 0.5));
                else {
                    CGContextSetStrokeColorWithColor(context, UIColor.compatOrangeColor.CGColor);
                    CGContextStrokeRect(context, CGRectInset(bar, 0.5, 0.5));
                }
            }
        } else if (context) {
            if (outputPath) CGPathAddRect(outputPath, NULL, bar);
            else {
                CGContextSetFillColorWithColor(context, UIColor.compatBlueColor.CGColor);
                CGContextFillRect(context, bar);
            }
        }
        if (!collect || dense) continue;
        NSMutableDictionary *details = [base mutableCopy];
        details[@"signedBatteryPowerWatts"] = power;
        details[@"notOutput"] = @(power.doubleValue > 0);
        [regions addObject:BAProcessRegion(bar, BAProcessSelection(self, @"record", @[observation.identifier],
            @[BAAnalyticsHistoryBatteryPowerWatts], observation.timestamp, observation.timestamp, details),
            [NSString stringWithFormat:_("%@, signed battery power %+.3g W%@"), BAProcessClock(observation.timestamp), power.doubleValue,
                power.doubleValue > 0 ? _(", net input, not output") : @""])];
    }
    if (outputPath) {
        CGContextSetFillColorWithColor(context, UIColor.compatBlueColor.CGColor);
        CGContextAddPath(context, outputPath); CGContextFillPath(context); CGPathRelease(outputPath);
    }
    if (inputPath) {
        CGContextSetStrokeColorWithColor(context, UIColor.compatOrangeColor.CGColor);
        CGContextAddPath(context, inputPath); CGContextStrokePath(context); CGPathRelease(inputPath);
    }
    return regions;
}

- (NSArray<BAAnalyticsCanvasHitRegion *> *)renderCanvas {
    NSMutableArray *regions = [NSMutableArray array];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    if (width <= 24 || height <= 24) return regions;
    BAAnalyticsFamilyReport *family = BAProcessFamily(self);
    BAAnalyticsHistorySession *session = BAProcessSession(family, @"unplugged");
    UIFont *caption = BAProcessFont(UIFontTextStyleCaption1, 11, UIFontWeightRegular);
    UIFont *strong = BAProcessFont(UIFontTextStyleFootnote, 12, UIFontWeightMedium);
    UIColor *muted = UIColor.compatSecondaryLabelColor;
    if (!session || [session.endDate compare:session.startDate] != NSOrderedDescending) {
        NSString *unavailable = BAProcessAvailability(family);
        BAProcessText(_("Charge and battery use"), CGRectMake(12, 12, width - 24, strong.lineHeight * 2), strong, muted, NSTextAlignmentLeft);
        CGRect missing = CGRectMake(12, height * 0.45, width - 24, MAX(8, height * 0.2));
        BAProcessHatch(missing, muted);
        BAProcessText(unavailable, CGRectMake(12, CGRectGetMaxY(missing) + 5, width - 24, height - CGRectGetMaxY(missing) - 8), caption, muted, NSTextAlignmentLeft);
        self.accessibilityLabel = _("Battery discharge");
        self.accessibilityValue = unavailable;
        [regions addObject:BAProcessRegion(missing, BAProcessSelection(self, @"metric", @[],
            @[BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryBatteryPowerWatts], family.window.startDate, family.window.endDate,
            @{@"availability":unavailable}), unavailable)];
        return regions;
    }
    [self prepareSession:session];
    NSArray *intervals = self.preparedIntervals;
    BADischargeStatistics statistics = self.preparedStatistics;
    NSDictionary *context = self.preparedContext;
    BAAnalyticsStateTransition *reconnection = self.preparedReconnection;
    BOOL tall = self.cardSize == BAAnalyticsCardSize2x2;
    BOOL largeText = BAProcessLargeText(self);
    NSString *window = BAProcessWindow(session.startDate, session.endDate);
    NSString *socSummary = statistics.socSeconds > 0 ? [NSString stringWithFormat:
        statistics.socLoss >= 0 ? _("Used %.1f%% in %@ recorded") : _("Gained %.1f%% in %@ recorded"),
        fabs(statistics.socLoss), BAProcessDuration(statistics.socSeconds)] : _("Charge change unavailable");
    NSString *powerSummary = statistics.powerSeconds > 0 ? [NSString stringWithFormat:_("Energy used ≈%.2f Wh · %@ recorded"), statistics.outputWattHours, BAProcessDuration(statistics.powerSeconds)] : _("Output energy unavailable");
    NSString *boundary = reconnection ? [NSString stringWithFormat:_("Reconnected ~%@"), BAProcessWindow(reconnection.earliestDate, reconnection.latestDate)] : _("Reconnection not observed");
    if (!session.startBoundaryKnown || !session.endBoundaryKnown) boundary = [boundary stringByAppendingString:_(" · partial")];
    NSString *powerCaption = _("Battery use (W)");

    BAAnalyticsObservation *firstSOC = self.preparedFirstSOC, *lastSOC = self.preparedLastSOC;

    // Large text reduces secondary tracks and summary text, rather than
    // shrinking every label. Exact rate/energy remain accessible selections.
    CGFloat windowHeight = BADischargeTextHeight(window, width - 46, caption);
    CGRect windowRect = CGRectMake(34, 8, width - 46, windowHeight + 1);
    BAAnalyticsDrawGlyph(BAAnalyticsGlyphUnplugged, CGRectMake(12, 8, 15, 15), muted);
    BAProcessText(window, windowRect, caption, muted, NSTextAlignmentLeft);
    [regions addObject:BAProcessRegion(windowRect, BAProcessSelection(self, @"session", @[],
        @[BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryBatteryPowerWatts], session.startDate, session.endDate, context),
        [NSString stringWithFormat:_("Unplugged session, %@"), window])];
    CGFloat summaryHeight = BADischargeTextHeight(socSummary, width - 24, caption);
    CGFloat extraHeight = tall ? BADischargeTextHeight(powerSummary, width - 24, caption) +
        BADischargeTextHeight(boundary, width - 24, caption) + 6 : 0;
    CGFloat footerTop = height - 9 - summaryHeight - extraHeight;
    CGRect summaryRect = CGRectMake(12, footerTop, width - 24, summaryHeight + 1);
    BAProcessText(socSummary, summaryRect, caption, UIColor.compatLabelColor, NSTextAlignmentLeft);
    [regions addObject:BAProcessRegion(summaryRect, BAProcessSelection(self, @"metric", @[], @[BAAnalyticsHistorySOCPercent],
        session.startDate, session.endDate, context), [NSString stringWithFormat:_("%@, trusted unplugged intervals only"), socSummary])];
    CGFloat plotX = largeText ? 12 : 39;
    CGFloat plotWidth = width - 12 - plotX;
    // Endpoint readings have their own annotation row. Keeping them outside
    // the plot makes high/low SOC and compressed layouts equally readable.
    CGFloat annotationY = CGRectGetMaxY(windowRect) + 3;
    CGFloat graphTop = annotationY + strong.lineHeight + 5;
    CGFloat powerLabelHeight = BADischargeTextHeight(powerCaption, width - 24, caption);
    CGFloat graphAvailable = MAX(0, footerTop - graphTop - 5);
    self.accessibilityValue = [NSString stringWithFormat:_("%@. %@. %@. %@. SOC and power have independent coverage; no interpolation across gaps."), window, socSummary, powerSummary, boundary];
    self.accessibilityLabel = [NSString stringWithFormat:_("Battery discharge. %@"), self.accessibilityValue];
    if (graphAvailable < powerLabelHeight + 13 + 24) {
        if (annotationY + strong.lineHeight < footerTop - 4 && !largeText) {
            NSString *first = firstSOC ? [NSString stringWithFormat:@"%.0f%%", BAProcessValue(firstSOC, BAAnalyticsHistorySOCPercent).doubleValue] : @"—";
            NSString *last = lastSOC ? [NSString stringWithFormat:@"%.0f%%", BAProcessValue(lastSOC, BAAnalyticsHistorySOCPercent).doubleValue] : @"—";
            BAProcessText(first, CGRectMake(plotX, annotationY, plotWidth / 2, strong.lineHeight), strong, UIColor.compatGreenColor, NSTextAlignmentLeft);
            BAProcessText(last, CGRectMake(plotX + plotWidth / 2, annotationY, plotWidth / 2, strong.lineHeight), strong, UIColor.compatGreenColor, NSTextAlignmentRight);
        }
        if (graphAvailable >= 8) {
            CGRect plot = CGRectMake(plotX, graphTop, plotWidth, graphAvailable);
            [regions addObjectsFromArray:BAProcessTrace(self, session.observations, intervals, session.gaps, BAAnalyticsHistorySOCPercent, @"%",
                session.startDate, session.endDate, plot, 0, 100, 1, UIColor.compatGreenColor, NO, session.identifier)];
        }
        return regions;
    }
    CGFloat powerHeight = tall ? MIN(55, graphAvailable * 0.22) : MAX(5, MIN(18, graphAvailable * 0.18));
    CGFloat socHeight = MAX(6, graphAvailable - powerHeight - powerLabelHeight - 13);
    BOOL showTemperature = tall && !largeText && graphAvailable > 170;
    if (showTemperature) socHeight -= 45;
    CGRect socPlot = CGRectMake(plotX, graphTop, plotWidth, socHeight);
    if (!largeText && socHeight >= caption.lineHeight * 2 + 6) {
        BAProcessText(@"100%", CGRectMake(12, graphTop - 4, 30, caption.lineHeight), caption, muted, NSTextAlignmentLeft);
        BAProcessText(@"0%", CGRectMake(12, CGRectGetMaxY(socPlot) - caption.lineHeight, 27, caption.lineHeight), caption, muted, NSTextAlignmentLeft);
        BADischargeLine(CGPointMake(plotX, graphTop), CGPointMake(plotX, CGRectGetMaxY(socPlot)), UIColor.compatSeparatorColor, NO);
    } else if (largeText) {
        BAProcessText(_("Charge (%)"), CGRectMake(plotX, annotationY, plotWidth, strong.lineHeight), caption, UIColor.compatGreenColor, NSTextAlignmentLeft);
    }
    [regions addObjectsFromArray:BAProcessTrace(self, session.observations, intervals, session.gaps, BAAnalyticsHistorySOCPercent, @"%",
        session.startDate, session.endDate, socPlot, 0, 100, 1, UIColor.compatGreenColor, NO, session.identifier)];
    if (lastSOC && !largeText) {
        NSString *value = [NSString stringWithFormat:@"%.0f%%", BAProcessValue(lastSOC, BAAnalyticsHistorySOCPercent).doubleValue];
        CGRect mark = CGRectMake(CGRectGetMaxX(socPlot) - 55, annotationY, 55, strong.lineHeight);
        BAProcessText(value, mark, strong, UIColor.compatGreenColor, NSTextAlignmentRight);
        [regions addObject:BAProcessRegion(mark, BAProcessSelection(self, @"record", @[lastSOC.identifier], @[BAAnalyticsHistorySOCPercent],
            lastSOC.timestamp, lastSOC.timestamp, context), [NSString stringWithFormat:_("Last observed %@, %@"), value, BAProcessClock(lastSOC.timestamp)])];
    }
    if (firstSOC && firstSOC != lastSOC && !largeText) {
        NSString *value = [NSString stringWithFormat:@"%.0f%%", BAProcessValue(firstSOC, BAAnalyticsHistorySOCPercent).doubleValue];
        CGRect mark = CGRectMake(socPlot.origin.x + 3, annotationY, 55, strong.lineHeight);
        BAProcessText(value, mark, strong, UIColor.compatGreenColor, NSTextAlignmentLeft);
        [regions addObject:BAProcessRegion(mark, BAProcessSelection(self, @"record", @[firstSOC.identifier], @[BAAnalyticsHistorySOCPercent],
            firstSOC.timestamp, firstSOC.timestamp, context), [NSString stringWithFormat:_("First observed %@, %@"), value, BAProcessClock(firstSOC.timestamp)])];
    }
    CGRect powerLabelRect = CGRectMake(12, CGRectGetMaxY(socPlot) + 5, width - 24, powerLabelHeight);
    NSString *endLabel = reconnection ? [NSString stringWithFormat:@"≈%@", BAProcessClock(reconnection.latestDate)] : nil;
    CGFloat endWidth = endLabel ? ceil([endLabel sizeWithAttributes:@{NSFontAttributeName:caption}].width) + 20 : 0;
    if (!tall && !largeText && reconnection && [powerCaption sizeWithAttributes:@{NSFontAttributeName:caption}].width + endWidth + 12 < width - 24) {
        powerLabelRect.size.width -= endWidth + 8;
        CGRect boundaryRect = CGRectMake(width - 12 - endWidth, powerLabelRect.origin.y, endWidth, caption.lineHeight);
        BAAnalyticsDrawGlyph(BAAnalyticsGlyphConnected, CGRectMake(boundaryRect.origin.x, boundaryRect.origin.y, 13, 13), muted);
        CGRect timeRect = CGRectMake(boundaryRect.origin.x + 18, boundaryRect.origin.y, endWidth - 18, boundaryRect.size.height);
        BAProcessText(endLabel, timeRect, caption, muted, NSTextAlignmentRight);
        NSMutableDictionary *details = [context mutableCopy];
        if (reconnection) details[@"transitionIdentifier"] = reconnection.identifier;
        details[@"boundaryEstimate"] = @YES;
        [regions addObject:BAProcessRegion(boundaryRect, BAProcessSelection(self, reconnection ? @"transition" : @"session", reconnection ? @[reconnection.identifier] : @[],
            @[BAAnalyticsHistoryExternalConnected], reconnection ? reconnection.earliestDate : session.endDate,
            reconnection ? reconnection.latestDate : session.endDate, details), boundary)];
    }
    BAProcessText(powerCaption, powerLabelRect, caption, UIColor.compatBlueColor, NSTextAlignmentLeft);
    CGRect powerPlot = CGRectMake(plotX, CGRectGetMaxY(powerLabelRect) + 3, plotWidth, powerHeight);
    [regions addObjectsFromArray:[self renderPower:session intervals:intervals plot:powerPlot]];
    [regions addObject:BAProcessRegion(powerLabelRect, BAProcessSelection(self, @"metric", @[], @[BAAnalyticsHistoryBatteryPowerWatts],
        session.startDate, session.endDate, context), [NSString stringWithFormat:_("%@; %@; precise readings retain signed W"), powerCaption, powerSummary])];
    if (showTemperature) {
        CGRect temperature = CGRectMake(plotX, CGRectGetMaxY(powerPlot) + 9, plotWidth, 28);
        double low = self.preparedTemperatureMinimum, high = self.preparedTemperatureMaximum;
        BAProcessText(@"°C", CGRectMake(12, temperature.origin.y, 25, caption.lineHeight), caption, UIColor.compatOrangeColor, NSTextAlignmentLeft);
        if (isfinite(low) && isfinite(high)) {
            double padding = MAX(1, (high - low) * 0.1);
            [regions addObjectsFromArray:BAProcessTrace(self, session.observations, intervals, session.gaps, BAAnalyticsHistoryTemperatureCelsius, @"°C",
                session.startDate, session.endDate, temperature, low - padding, high + padding, 1, UIColor.compatOrangeColor, YES, session.identifier)];
        } else {
            BAProcessHatch(temperature, muted);
            [regions addObject:BAProcessRegion(temperature, BAProcessSelection(self, @"metric", @[], @[BAAnalyticsHistoryTemperatureCelsius],
                session.startDate, session.endDate, context), _("Temperature unavailable"))];
        }
    }
    if (reconnection) {
        CGFloat firstX = BAProcessTimeX(reconnection.earliestDate, session.startDate, session.endDate, socPlot);
        CGFloat lastX = BAProcessTimeX(reconnection.latestDate, session.startDate, session.endDate, socPlot);
        BADischargeLine(CGPointMake(firstX, graphTop), CGPointMake(firstX, CGRectGetMaxY(powerPlot)), muted, YES);
        if (lastX > firstX) BAProcessHatch(CGRectMake(firstX, graphTop, lastX - firstX, socPlot.size.height), muted);
    }
    if (tall) {
        CGFloat y = CGRectGetMaxY(summaryRect) + 2;
        CGFloat energyHeight = BADischargeTextHeight(powerSummary, width - 24, caption);
        CGRect energyRect = CGRectMake(12, y, width - 24, energyHeight);
        BAProcessText(powerSummary, energyRect, caption, UIColor.compatBlueColor, NSTextAlignmentLeft);
        [regions addObject:BAProcessRegion(energyRect, BAProcessSelection(self, @"metric", @[], @[BAAnalyticsHistoryBatteryPowerWatts],
            session.startDate, session.endDate, context), powerSummary)];
        CGRect boundaryRect = CGRectMake(12, CGRectGetMaxY(energyRect) + 2, width - 24,
            BADischargeTextHeight(boundary, width - 24, caption));
        BAProcessText(boundary, boundaryRect, caption, muted, NSTextAlignmentLeft);
        NSMutableDictionary *details = [context mutableCopy];
        details[@"boundaryEstimate"] = @YES;
        if (reconnection) details[@"transitionIdentifier"] = reconnection.identifier;
        [regions addObject:BAProcessRegion(boundaryRect, BAProcessSelection(self, reconnection ? @"transition" : @"session", reconnection ? @[reconnection.identifier] : @[],
            @[BAAnalyticsHistoryExternalConnected], reconnection ? reconnection.earliestDate : session.endDate,
            reconnection ? reconnection.latestDate : session.endDate, details), boundary)];
    }
    self.accessibilityLabel = _("Battery discharge");
    self.accessibilityValue = [NSString stringWithFormat:_("%@. %@. %@. %@. SOC and power have independent coverage; no interpolation across gaps."), window, socSummary, powerSummary, boundary];
    self.accessibilityLabel = [NSString stringWithFormat:_("Battery discharge. %@"), self.accessibilityValue];
    return regions;
}

@end

@interface BADischargeDetailViewController : BAAnalyticsDetailViewController
@end
@implementation BADischargeDetailViewController
- (UIView *)makeVisualizationView {
    BAAnalyticsDischargeCanvasView *view = [BAAnalyticsDischargeCanvasView new];
    view.cardSize = BAAnalyticsCardSize2x2; view.familyIdentifier = self.familyReport.family;
    view.latestReport = self.report; view.latestSnapshot = self.snapshot;
    view.detailEnabled = NO;
    return view;
}
- (NSArray<NSDictionary *> *)summaryRows {
    BAAnalyticsHistorySession *session = BAProcessSession(self.familyReport, @"unplugged");
    if (!session) return @[];
    BADischargeStatistics stats = BADischargeSummarize(session, BADischargeIntervals(session));
    return @[@{@"title":_("Battery level drop"), @"value":stats.socSeconds > 0 ? [NSString stringWithFormat:_("%.1f%% · %@ recorded"), stats.socLoss, BAProcessDuration(stats.socSeconds)] : _("Unavailable")},
        @{@"title":_("Battery output energy"), @"value":stats.powerSeconds > 0 ? [NSString stringWithFormat:_("%.2f Wh · %@ covered"), stats.outputWattHours, BAProcessDuration(stats.powerSeconds)] : _("Unavailable")}];
}
@end

@implementation BAAnalyticsDischargeCanvasCard
- (BOOL)supportsDetails { return YES; }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    (void)size;
    return [[BADischargeDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier
         report:self.latestReport snapshot:self.latestSnapshot selection:selection];
}

- (instancetype)init {
    return [super initWithIdentifier:@"com.torrekie.battman.analytics.discharge" displayName:_("Battery discharge") familyIdentifier:BAAnalyticsFamilyDischarge
        supportedSizes:BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x1];
}
- (BAAnalyticsCanvasView *)makeCanvasView { return [[BAAnalyticsDischargeCanvasView alloc] initWithFrame:CGRectZero]; }
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view { [view setNeedsLayout]; [view setNeedsDisplay]; }
@end
