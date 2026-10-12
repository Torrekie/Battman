#import "../Canvas/BAAnalyticsDetailViewController.h"
#import "main.h"
#import "BAAnalyticsLiveDrawing.h"
#include <float.h>
#include <math.h>

// These are normalized history identifiers, not invented live SDK readings.
static NSNumber *BACellIndex(NSString *metric) {
    NSArray<NSString *> *parts = [metric componentsSeparatedByString:@"."];
    if (parts.count != 3 || ![parts[0] isEqualToString:@"cell-voltage"] ||
        ![parts[2] isEqualToString:@"millivolts"] || parts[1].length == 0) return nil;
    if ([parts[1] rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return nil;
    NSScanner *scanner = [NSScanner scannerWithString:parts[1]];
    long long index = 0;
    if (![scanner scanLongLong:&index] || !scanner.isAtEnd || index < 0 || index >= NSIntegerMax) return nil;
    return @(index);
}

static UIFont *BACellsAnnotationFont(CGFloat size, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] maximumPointSize:15];
}


static void BACellsStroke(CGPoint a, CGPoint b, NSUInteger ordinal) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextSetStrokeColorWithColor(context, UIColor.compatBlueColor.CGColor);
    CGContextSetLineWidth(context, 1.7);
    CGFloat dashed[] = {5, 3}, dotted[] = {1, 3};
    if (ordinal % 3 == 1) CGContextSetLineDash(context, 0, dashed, 2);
    if (ordinal % 3 == 2) CGContextSetLineDash(context, 0, dotted, 2);
    CGContextMoveToPoint(context, a.x, a.y); CGContextAddLineToPoint(context, b.x, b.y);
    CGContextStrokePath(context); CGContextRestoreGState(context);
}

static void BACellsMarker(CGPoint point, NSUInteger ordinal) {
    CGContextRef c = UIGraphicsGetCurrentContext(); if (!c) return;
    CGRect rect = CGRectMake(point.x - 2.5, point.y - 2.5, 5, 5);
    CGContextSetFillColorWithColor(c, UIColor.compatBlueColor.CGColor);
    switch (ordinal % 3) {
        case 1: CGContextFillRect(c, rect); break;
        case 2:
            CGContextMoveToPoint(c, point.x, point.y - 3.5); CGContextAddLineToPoint(c, point.x + 3.5, point.y);
            CGContextAddLineToPoint(c, point.x, point.y + 3.5); CGContextAddLineToPoint(c, point.x - 3.5, point.y);
            CGContextClosePath(c); CGContextFillPath(c); break;
        default: CGContextFillEllipseInRect(c, rect); break;
    }
}

typedef struct {
    NSTimeInterval time;
    double value;
    NSUInteger run;
} BACellsSample;

@interface BACellsPreparedHistory : NSObject
@property (nonatomic, copy) NSArray<NSString *> *metrics;
@property (nonatomic, strong) BAAnalyticsObservation *latest;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *latestValues;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<BAAnalyticsObservation *> *> *pointsByMetric;
@property (nonatomic, copy) NSDictionary<NSString *, NSData *> *samplesByMetric;
@property (nonatomic, copy) NSData *missingRanges;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@end
@implementation BACellsPreparedHistory
@end

@interface BACellsPreparationToken : NSObject
@property (atomic, getter=isCancelled) BOOL cancelled;
@end
@implementation BACellsPreparationToken
@end

// Work only with immutable Foundation report objects on the shared serial
// preparation queue. Channel discovery, range/trust scans and sorting are not
// part of drawing, layout, accessibility construction or touch handling.
static BACellsPreparedHistory *BACellsPrepare(BAAnalyticsFamilyReport *family, NSDictionary *fieldMetadata, BACellsPreparationToken *token) {
    if (token.isCancelled) return nil;
    BACellsPreparedHistory *prepared = [BACellsPreparedHistory new];
    BAAnalyticsHistoryWindow *window = family.window;
    NSMutableSet<NSString *> *metrics = [NSMutableSet set];
    NSUInteger scanned = 0;
    for (NSString *key in fieldMetadata) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if (BACellIndex(key) && [fieldMetadata[key] unitValidated]) [metrics addObject:key];
    }
    id payload = family.payload[BAAnalyticsPayloadLatestObservation];
    BAAnalyticsObservation *latest = [payload isKindOfClass:BAAnalyticsObservation.class] ? payload : nil;
    NSMutableArray *discovery = [window.observations mutableCopy] ?: [NSMutableArray array];
    if (latest) [discovery addObject:latest];
    scanned = 0;
    for (BAAnalyticsObservation *observation in discovery) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        BOOL hasCell = NO;
        for (NSString *key in observation.fieldMetadata) {
            if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
            if (BACellIndex(key)) { [metrics addObject:key]; hasCell = YES; }
        }
        for (NSString *key in observation.values) {
            if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
            if (BACellIndex(key)) { [metrics addObject:key]; hasCell = YES; }
        }
        if (hasCell && observation.timestampValidated && (!latest || !latest.timestampValidated ||
            [observation.timestamp compare:latest.timestamp] == NSOrderedDescending)) latest = observation;
    }
    if (!latest.timestampValidated) latest = nil;
    prepared.latest = latest;
    if (token.isCancelled) return nil;
    prepared.metrics = [metrics.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [BACellIndex(a) compare:BACellIndex(b)]; }];
    if (token.isCancelled) return nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    double low = DBL_MAX, high = -DBL_MAX;
    for (NSString *metric in prepared.metrics) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        NSNumber *value = BALiveObservationValue(latest, metric);
        if (value) { values[metric] = value; low = MIN(low, value.doubleValue); high = MAX(high, value.doubleValue); }
    }
    prepared.latestValues = values;
    scanned = 0;
    for (BAAnalyticsObservation *observation in window.observations) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        for (NSString *metric in prepared.metrics) {
            if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
            NSNumber *value = BALiveObservationValue(observation, metric);
            if (value) { low = MIN(low, value.doubleValue); high = MAX(high, value.doubleValue); }
        }
    }
    if (low == DBL_MAX) { prepared.minimum = 0; prepared.maximum = 1; }
    else { double padding = MAX(10, (high - low) * .12); prepared.minimum = floor((low - padding) / 10) * 10; prepared.maximum = ceil((high + padding) / 10) * 10; }
    // Interval endpoint records can lie just outside a clipped window. Keep
    // them for faithful boundary interpolation, without inventing edge samples.
    NSMutableDictionary<NSString *, BAAnalyticsObservation *> *records = [NSMutableDictionary dictionary];
    scanned = 0;
    for (BAAnalyticsObservation *observation in window.observations) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if (observation.identifier) records[observation.identifier] = observation;
    }
    scanned = 0;
    for (BAAnalyticsHistoryInterval *interval in window.intervals) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if (interval.startObservation.identifier && !records[interval.startObservation.identifier]) records[interval.startObservation.identifier] = interval.startObservation;
        if (interval.endObservation.identifier && !records[interval.endObservation.identifier]) records[interval.endObservation.identifier] = interval.endObservation;
    }
    NSArray<BAAnalyticsObservation *> *orderedRecords = [records.allValues sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
        NSComparisonResult order = [a.timestamp compare:b.timestamp]; return order == NSOrderedSame ? [a.identifier compare:b.identifier] : order;
    }];
    if (token.isCancelled) return nil;
    NSMutableDictionary *pointsByMetric = [NSMutableDictionary dictionary], *indicesByMetric = [NSMutableDictionary dictionary], *trustedByMetric = [NSMutableDictionary dictionary];
    for (NSString *metric in prepared.metrics) {
        if (token.isCancelled) return nil;
        NSMutableArray *points = [NSMutableArray array]; NSMutableDictionary *indices = [NSMutableDictionary dictionary];
        scanned = 0;
        for (BAAnalyticsObservation *observation in orderedRecords) {
            if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
            if (BALiveObservationValue(observation, metric)) { indices[observation.identifier] = @(points.count); [points addObject:observation]; }
        }
        pointsByMetric[metric] = points; indicesByMetric[metric] = indices; trustedByMetric[metric] = [NSMutableIndexSet indexSet];
    }
    NSArray<BAAnalyticsHistoryInterval *> *intervals = [window.intervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) { return [a.startDate compare:b.startDate]; }];
    if (token.isCancelled) return nil;
    NSArray<BAAnalyticsHistoryGap *> *gaps = [window.gaps sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryGap *a, BAAnalyticsHistoryGap *b) { return [a.startDate compare:b.startDate]; }];
    if (token.isCancelled) return nil;
    NSMutableArray<NSArray<NSDate *> *> *missing = [NSMutableArray array];
    NSDate *cursor = window.startDate; NSUInteger gapIndex = 0;
    scanned = 0;
    for (BAAnalyticsHistoryInterval *interval in intervals) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if ([interval.endDate compare:interval.startDate] != NSOrderedDescending) continue;
        while (gapIndex < gaps.count && [gaps[gapIndex].endDate compare:interval.startDate] != NSOrderedDescending) gapIndex++;
        BOOL gap = gapIndex < gaps.count && [gaps[gapIndex].startDate compare:interval.endDate] == NSOrderedAscending;
        BOOL any = NO;
        for (NSString *metric in prepared.metrics) {
            if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
            if (![interval.coveredMetricIdentifiers containsObject:metric] || !BALiveObservationValue(interval.startObservation, metric) || !BALiveObservationValue(interval.endObservation, metric)) continue;
            any = YES;
            NSNumber *a = interval.startObservation.identifier ? indicesByMetric[metric][interval.startObservation.identifier] : nil;
            NSNumber *b = interval.endObservation.identifier ? indicesByMetric[metric][interval.endObservation.identifier] : nil;
            if (!gap && a && b && b.unsignedIntegerValue == a.unsignedIntegerValue + 1) [trustedByMetric[metric] addIndex:b.unsignedIntegerValue];
        }
        if (any && cursor) {
            NSDate *a = [interval.startDate compare:window.startDate] == NSOrderedAscending ? window.startDate : interval.startDate;
            NSDate *b = [interval.endDate compare:window.endDate] == NSOrderedDescending ? window.endDate : interval.endDate;
            if ([b compare:a] != NSOrderedDescending) continue;
            if ([a compare:cursor] == NSOrderedDescending) [missing addObject:@[cursor, a]];
            if ([b compare:cursor] == NSOrderedDescending) cursor = b;
        }
    }
    if (cursor && [window.endDate compare:cursor] == NSOrderedDescending) [missing addObject:@[cursor, window.endDate]];
    scanned = 0;
    for (BAAnalyticsHistoryGap *gap in gaps) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        NSDate *a = [gap.startDate compare:window.startDate] == NSOrderedAscending ? window.startDate : gap.startDate;
        NSDate *b = [gap.endDate compare:window.endDate] == NSOrderedDescending ? window.endDate : gap.endDate;
        if ([b compare:a] == NSOrderedDescending) [missing addObject:@[a, b]];
    }
    [missing sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    if (token.isCancelled) return nil;
    NSMutableData *missingData = [NSMutableData data]; double a = 0, b = 0; BOOL open = NO;
    scanned = 0;
    for (NSArray<NSDate *> *range in missing) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        double start = range[0].timeIntervalSince1970, end = range[1].timeIntervalSince1970;
        if (open && start > b) { double pair[] = {a, b}; [missingData appendBytes:pair length:sizeof(pair)]; open = NO; }
        if (!open) { a = start; b = end; open = YES; } else b = MAX(b, end);
    }
    if (open) { double pair[] = {a, b}; [missingData appendBytes:pair length:sizeof(pair)]; }
    prepared.missingRanges = missingData;
    NSMutableDictionary *samplesByMetric = [NSMutableDictionary dictionary];
    for (NSString *metric in prepared.metrics) {
        if (token.isCancelled) return nil;
        NSArray<BAAnalyticsObservation *> *points = pointsByMetric[metric]; NSIndexSet *trusted = trustedByMetric[metric];
        NSMutableData *data = [NSMutableData dataWithLength:points.count * sizeof(BACellsSample)]; BACellsSample *samples = data.mutableBytes;
        for (NSUInteger i = 0; i < points.count; i++) {
            if ((i & 255) == 0 && token.isCancelled) return nil;
            samples[i].time = points[i].timestamp.timeIntervalSince1970;
            samples[i].value = BALiveObservationValue(points[i], metric).doubleValue;
            samples[i].run = i ? samples[i - 1].run + ![trusted containsIndex:i] : 0;
        }
        samplesByMetric[metric] = data;
    }
    prepared.pointsByMetric = pointsByMetric; prepared.samplesByMetric = samplesByMetric;
    if (token.isCancelled) return nil;
    return prepared;
}

static NSArray<NSNumber *> *BACellsEnvelope(NSData *data, NSTimeInterval start, NSTimeInterval end, NSUInteger columns) {
    NSUInteger count = data.length / sizeof(BACellsSample); if (!count) return @[];
    NSMutableIndexSet *kept = [NSMutableIndexSet indexSet]; const BACellsSample *samples = data.bytes;
    if (count <= 192) [kept addIndexesInRange:NSMakeRange(0, count)];
    else {
        NSUInteger first = 0, minimum = 0, maximum = 0, last = 0, priorColumn = NSNotFound;
        for (NSUInteger i = 0; i < count; i++) {
            double fraction = end > start ? (samples[i].time - start) / (end - start) : .5;
            NSUInteger column = MIN(columns - 1, (NSUInteger)MAX(0, floor(fraction * columns)));
            BOOL runChanged = i && samples[i].run != samples[i - 1].run;
            BOOL previousConnected = i > 1 && samples[i - 1].run == samples[i - 2].run;
            BOOL currentConnected = i + 1 < count && samples[i].run == samples[i + 1].run;
            // Singleton readings remain scatter points; only trusted runs
            // need explicit endpoints in addition to the column extrema.
            if (column != priorColumn || (runChanged && (previousConnected || currentConnected))) {
                if (priorColumn != NSNotFound) { [kept addIndex:first]; [kept addIndex:minimum]; [kept addIndex:maximum]; [kept addIndex:last]; }
                first = minimum = maximum = i; priorColumn = column;
            }
            if (samples[i].value < samples[minimum].value) minimum = i;
            if (samples[i].value > samples[maximum].value) maximum = i;
            last = i;
        }
        [kept addIndex:first]; [kept addIndex:minimum]; [kept addIndex:maximum]; [kept addIndex:last];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:kept.count];
    [kept enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [result addObject:@(index)]; }]; return result;
}

@interface BACellsMark : NSObject
@property (nonatomic, strong) BAAnalyticsObservation *observation;
@property (nonatomic, copy) NSString *metric;
@property (nonatomic) NSUInteger ordinal;
@property (nonatomic) CGPoint point;
@end
@implementation BACellsMark
@end

@interface BAAnalyticsCellsCanvasView : BAAnalyticsCanvasView
@property (nonatomic, strong) BAAnalyticsFamilyReport *cellsReport;
@property (nonatomic, strong) BAAnalyticsObservation *latestCellObservation;
@property (nonatomic, copy) NSArray<NSString *> *cellMetrics;
@property (nonatomic, copy) NSArray<NSString *> *visibleMetrics;
@property (nonatomic, copy) NSArray<BACellsMark *> *marks;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *latestValues;
@property (nonatomic, copy) NSArray<NSValue *> *untrustedRects;
@property (nonatomic, strong) NSNumber *observedDelta;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@property (nonatomic) BOOL compact;
@property (nonatomic) BOOL largeType;
@property (nonatomic) CGRect plotRect;
@property (nonatomic) CGRect summaryRect;
@property (nonatomic) CGRect unitRect;
@property (nonatomic) CGRect countRect;
@property (nonatomic) CGRect timestampRect;
@property (nonatomic) CGRect ageRect;
@property (nonatomic) CGRect windowRect;
@property (nonatomic, copy) NSString *summaryText;
@property (nonatomic, copy) NSString *countText;
@property (nonatomic, copy) NSString *timestampText;
@property (nonatomic, copy) NSString *ageText;
@property (nonatomic, copy) NSString *windowText;
@property (nonatomic, strong) BALiveSummaryScrollView *largeTypeSummary;
@property (nonatomic, strong) BAAnalyticsFamilyReport *requestedFamily;
@property (nonatomic, strong) BAAnalyticsReport *incomingReport;
@property (nonatomic, strong) BAAnalyticsReport *requestedReport;
@property (nonatomic, strong) BAAnalyticsReport *displayedReport;
@property (nonatomic, strong) NSDictionary *requestedMetadata;
@property (nonatomic, strong) BACellsPreparedHistory *preparedHistory;
@property (nonatomic, getter=isPreparingHistory) BOOL preparingHistory;
@property (nonatomic) NSUInteger preparationGeneration;
@property (nonatomic) CGRect geometryRect;
@property (nonatomic, copy) NSArray<NSString *> *geometryMetrics;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSNumber *> *> *displayIndices;
@property (nonatomic, strong) NSDateFormatter *pointFormatter;
@property (nonatomic, strong) BACellsPreparationToken *preparationToken;
- (void)reloadReport;
- (void)startHistoryPreparation;
@end

@implementation BAAnalyticsCellsCanvasView
@synthesize preparingHistory = _preparingHistory;
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor; self.opaque = NO;
        _cellMetrics = @[]; _visibleMetrics = @[]; _marks = @[]; _latestValues = @{}; _untrustedRects = @[];
        _displayIndices = @{}; _geometryMetrics = @[]; _geometryRect = CGRectNull;
        _pointFormatter = [NSDateFormatter new]; [_pointFormatter setLocalizedDateFormatFromTemplate:@"MMddHHmm"];
        _largeTypeSummary = [BALiveSummaryScrollView new];
        _largeTypeSummary.canvas = self;
        _largeTypeSummary.hidden = YES;
        [self addSubview:_largeTypeSummary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentSizeChanged:)
                    name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { _preparationToken.cancelled = YES; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)contentSizeChanged:(NSNotification *)notification { self.geometryRect = CGRectNull; [self setNeedsLayout]; [self setNeedsDisplay]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; self.geometryRect = CGRectNull; [self setNeedsLayout]; [self setNeedsDisplay];
}

- (void)setLatestReport:(BAAnalyticsReport *)report {
    self.incomingReport = report;
    if (!self.preparedHistory) [self adoptDisplayedReport:report];
}

- (void)adoptDisplayedReport:(BAAnalyticsReport *)report {
    self.displayedReport = report;
    [super setLatestReport:report];
}

- (void)requestDetailForSelection:(BAAnalyticsDetailSelection *)selection {
    [super requestDetailForSelection:selection ?: [self selectionForObservation:self.latestCellObservation metric:nil]];
}

- (void)startHistoryPreparation {
    if (self.preparingHistory || !self.requestedFamily ||
        self.requestedFamily.availability == BAAnalyticsReportAvailabilityLoading ||
        self.requestedFamily.availability == BAAnalyticsReportAvailabilityUnavailable) return;
    self.preparingHistory = YES;
    BAAnalyticsFamilyReport *family = self.requestedFamily;
    BAAnalyticsReport *report = self.requestedReport;
    NSDictionary *metadata = self.requestedMetadata;
    NSUInteger generation = self.preparationGeneration;
    BACellsPreparationToken *token = [BACellsPreparationToken new]; self.preparationToken = token;
    __weak BAAnalyticsCellsCanvasView *weakSelf = self;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            BACellsPreparedHistory *prepared = BACellsPrepare(family, metadata, token);
            dispatch_async(dispatch_get_main_queue(), ^{
                BAAnalyticsCellsCanvasView *view = weakSelf;
                if (!view) return;
                view.preparingHistory = NO;
                view.preparationToken = nil;
                if (prepared && !token.isCancelled && generation == view.preparationGeneration && family == view.requestedFamily && report == view.requestedReport) {
                    view.preparedHistory = prepared; view.geometryRect = CGRectNull;
                    [view adoptDisplayedReport:report];
                    [view reloadReport];
                } else [view startHistoryPreparation];
            });
        }
    });
}

- (void)reloadReport {
    BAAnalyticsFamilyReport *family = [self.incomingReport reportForFamily:BAAnalyticsFamilyCells];
    NSDictionary *metadata = self.incomingReport.fieldMetadata;
    if (self.requestedReport != self.incomingReport || self.requestedMetadata != metadata) {
        self.preparationToken.cancelled = YES;
        self.requestedReport = self.incomingReport;
        self.requestedFamily = family; self.requestedMetadata = metadata; self.preparationGeneration++;
        BOOL sameSource = [self.displayedReport.sourceProfileIdentifier isEqualToString:self.incomingReport.sourceProfileIdentifier];
        BOOL retainDisplayed = self.preparedHistory && sameSource && family &&
            family.availability != BAAnalyticsReportAvailabilityUnavailable;
        if (!retainDisplayed) {
            self.preparedHistory = nil; self.geometryRect = CGRectNull;
            self.displayIndices = @{}; self.marks = @[]; self.untrustedRects = @[]; self.hitRegions = @[];
            [self adoptDisplayedReport:self.incomingReport];
        }
        [self startHistoryPreparation];
    }
    self.cellsReport = [self.displayedReport reportForFamily:BAAnalyticsFamilyCells];
    family = self.cellsReport;
    BACellsPreparedHistory *prepared = self.preparedHistory;
    self.latestCellObservation = prepared.latest;
    self.cellMetrics = prepared.metrics ?: @[];
    self.latestValues = prepared.latestValues ?: @{};
    self.minimum = prepared ? prepared.minimum : 0; self.maximum = prepared ? prepared.maximum : 1;
    BAAnalyticsHistoryWindow *window = family.window;
    BAAnalyticsObservation *latest = self.latestCellObservation;
    NSDictionary *values = self.latestValues;
    double low = DBL_MAX, high = -DBL_MAX;
    for (NSNumber *value in values.allValues) { low = MIN(low, value.doubleValue); high = MAX(high, value.doubleValue); }
    self.observedDelta = values.count >= 2 ? @(high - low) : nil;
    self.countText = self.cellMetrics.count ?
        [NSString stringWithFormat:_("%lu valid cells"), (unsigned long)values.count] :
        _("Cell count unavailable");
    self.summaryText = self.observedDelta ? [NSString stringWithFormat:_("Δobs %.0f"), self.observedDelta.doubleValue] :
        (values.count == 1 ? _("Single cell") : _("No readings"));
    self.timestampText = latest.timestamp ? [self.pointFormatter stringFromDate:latest.timestamp] : _("Historical time unavailable");
    self.ageText = BALiveAge(latest.timestamp);
    self.windowText = window ? BALiveWindow(window.startDate, window.endDate) : _("Window unavailable");
    NSMutableArray *readings = [NSMutableArray array];
    for (NSString *metric in self.cellMetrics) {
        NSNumber *value = values[metric];
        [readings addObject:[NSString stringWithFormat:_("Cell %lld: %@"), BACellIndex(metric).longLongValue + 1,
            value ? [NSString stringWithFormat:@"%.0f mV", value.doubleValue] : _("unavailable")]];
    }
    self.accessibilityValue = [NSString stringWithFormat:@"%@. %@. %@. %@. %@. %@", self.countText, [readings componentsJoinedByString:@"; "],
        self.observedDelta ? [NSString stringWithFormat:_("Observed cells delta %.0f mV; maximum minus minimum in the same record"), self.observedDelta.doubleValue] : _("Group delta unavailable"),
        self.timestampText, self.ageText, self.windowText];
    // The shared Canvas overview speaks accessibilityLabel, so it must retain
    // all evidence rather than relying on UIControl's separate value field.
    self.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", _("Cell voltage history"), self.accessibilityValue];
    [self setNeedsLayout]; [self setNeedsDisplay];
}

- (BOOL)dateIsInWindow:(NSDate *)date {
    BAAnalyticsHistoryWindow *window = self.cellsReport.window;
    return window && [date compare:window.startDate] != NSOrderedAscending && [date compare:window.endDate] != NSOrderedDescending;
}
- (CGFloat)xForDate:(NSDate *)date {
    BAAnalyticsHistoryWindow *window = self.cellsReport.window;
    NSTimeInterval duration = [window.endDate timeIntervalSinceDate:window.startDate];
    double fraction = duration > 0 ? [date timeIntervalSinceDate:window.startDate] / duration : .5;
    return CGRectGetMinX(self.plotRect) + MIN(1, MAX(0, fraction)) * CGRectGetWidth(self.plotRect);
}
- (CGFloat)yForValue:(double)value {
    return CGRectGetMaxY(self.plotRect) - (value - self.minimum) / (self.maximum - self.minimum) * CGRectGetHeight(self.plotRect);
}
- (NSDictionary *)contextForObservation:(BAAnalyticsObservation *)observation metric:(NSString *)metric {
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:@{@"sourceKind":@"history", @"unit":@"mV",
        @"knownChannelCount":@(self.cellMetrics.count), @"deltaScope":@"concurrently-observed-cells", @"notAFaultDiagnosis":@YES}];
    NSMutableArray *available = [NSMutableArray array], *missing = [NSMutableArray array];
    double low = DBL_MAX, high = -DBL_MAX;
    for (NSString *key in self.cellMetrics) {
        NSNumber *value = BALiveObservationValue(observation, key);
        if (value) { [available addObject:key]; low = MIN(low, value.doubleValue); high = MAX(high, value.doubleValue); }
        else [missing addObject:key];
    }
    context[@"observedCellCount"] = @(available.count); context[@"concurrentMetricIdentifiers"] = available;
    context[@"missingMetricIdentifiers"] = missing; context[@"deltaAvailable"] = @(available.count >= 2);
    if (available.count >= 2) context[@"observedDeltaMillivolts"] = @(high - low);
    if (metric) { context[@"cellIndex"] = BACellIndex(metric); context[@"valueAvailable"] = @(BALiveObservationValue(observation, metric) != nil); }
    return context;
}
- (BAAnalyticsDetailSelection *)selectionForObservation:(BAAnalyticsObservation *)observation metric:(NSString *)metric {
    return BALiveSelection(self, metric ? @"cell-observation" : @"cell-group-observation",
        observation ? @[observation.identifier] : @[], metric ? @[metric] : self.cellMetrics,
        observation.timestamp, observation.timestamp, [self contextForObservation:observation metric:metric]);
}
- (NSString *)labelForObservation:(BAAnalyticsObservation *)observation metric:(NSString *)metric {
    NSNumber *value = BALiveObservationValue(observation, metric);
    return [NSString stringWithFormat:_("Cell %lld, %@, %@"), BACellIndex(metric).longLongValue + 1,
        value ? [NSString stringWithFormat:@"%.0f mV", value.doubleValue] : _("unavailable"), observation.timestamp ? [self.pointFormatter stringFromDate:observation.timestamp] : _("Historical time unavailable")];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.compact = self.cardSize == BAAnalyticsCardSize1x1;
    self.largeType = BALiveLargeType(self);
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds), inset = 10;
    CGFloat contentWidth = MAX(0, width - 2 * inset);
    self.largeTypeSummary.hidden = !self.largeType;
    self.largeTypeSummary.frame = self.bounds;
    if (self.largeType) {
        self.largeTypeSummary.summaryText = self.accessibilityLabel;
        self.hitRegions = @[[BAAnalyticsCanvasHitRegion regionWithRect:self.bounds
                   selection:[self selectionForObservation:self.latestCellObservation metric:nil]
                   accessibilityLabel:self.accessibilityLabel]];
        self.marks = @[];
        [self setNeedsDisplay];
        return;
    }
    UIFont *small = BACellsAnnotationFont(11, UIFontWeightRegular);
    CGFloat row = ceil(small.lineHeight) + 2;
    CGFloat top = 8;
    if (self.largeType) {
        // Keep the Dynamic Type count large; remove secondary tracks first.
        self.summaryText = [NSString stringWithFormat:@"%lu", (unsigned long)self.latestValues.count];
        CGFloat mainHeight = BALiveTextHeight(self.summaryText, contentWidth * .6, BALiveFont(20, UIFontWeightSemibold));
        self.summaryRect = CGRectMake(inset, top, contentWidth * .6, MIN(mainHeight, height - 4 * row - 16));
        self.unitRect = CGRectMake(inset + contentWidth * .6, top, contentWidth * .4, MAX(row, self.summaryRect.size.height));
        top = CGRectGetMaxY(self.summaryRect) + 4;
    } else {
        self.summaryText = self.observedDelta ? [NSString stringWithFormat:_("Δobs %.0f"), self.observedDelta.doubleValue] :
            (self.latestValues.count == 1 ? _("Single cell") : _("No readings"));
        UIFont *summary = BACellsAnnotationFont(self.compact ? 13 : 15, UIFontWeightSemibold);
        CGFloat headerHeight = MAX(row, BALiveTextHeight(self.summaryText, contentWidth - 26, summary));
        self.unitRect = CGRectMake(inset, top, 25, headerHeight);
        self.summaryRect = CGRectMake(inset + 26, top, contentWidth - 26, headerHeight);
        top += headerHeight + 6;
    }
    // Reflow annotations rather than spending four rows of a short card on
    // metadata. Exact dates and the full age remain in accessible details.
    if (self.compact) {
        self.countRect = CGRectMake(inset, height - 3 * row - 4, contentWidth, row);
        self.timestampRect = CGRectMake(inset, height - 2 * row - 4, contentWidth, row);
        self.ageRect = CGRectZero;
    } else if (self.cardSize == BAAnalyticsCardSize2x1) {
        self.countRect = CGRectMake(inset, height - 2 * row - 4, contentWidth, row);
        self.timestampRect = CGRectZero;
        self.ageRect = CGRectZero;
    } else {
        self.countRect = CGRectMake(inset, height - 4 * row - 4, contentWidth, row);
        self.timestampRect = CGRectMake(inset, height - 3 * row - 4, contentWidth, row);
        self.ageRect = CGRectMake(inset, height - 2 * row - 4, contentWidth, row);
    }
    self.windowRect = CGRectMake(inset, height - row - 4, contentWidth, row);
    // The line-style swatches and cell numbers belong to a gutter outside
    // the data plot, including when a trace reaches its highest endpoint.
    self.plotRect = CGRectMake(36, top, MAX(0, width - (self.compact ? 58 : 72)), MAX(0, CGRectGetMinY(self.countRect) - top - row));
    NSUInteger capacity = self.compact ? MAX(1, (NSUInteger)floor(self.plotRect.size.width / 20)) : MAX(1, (NSUInteger)floor(self.plotRect.size.height / 13));
    // A dense pack still retains its actual count; overflow opens the full group.
    self.visibleMetrics = [self.cellMetrics subarrayWithRange:NSMakeRange(0, MIN(capacity, self.cellMetrics.count))];
    if (CGRectEqualToRect(self.geometryRect, self.plotRect) && [self.geometryMetrics isEqualToArray:self.visibleMetrics]) return;
    self.geometryRect = self.plotRect; self.geometryMetrics = self.visibleMetrics;
    NSMutableArray<BAAnalyticsCanvasHitRegion *> *regions = [NSMutableArray array];
    if (self.detailEnabled) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:self.summaryRect
        selection:[self selectionForObservation:self.latestCellObservation metric:nil] accessibilityLabel:self.accessibilityValue]];
    NSMutableArray<BACellsMark *> *marks = [NSMutableArray array];
    NSMutableDictionary *display = [NSMutableDictionary dictionary];
    BOOL dense = self.cellsReport.window.observations.count + self.cellsReport.window.intervals.count > 192;
    if (self.compact) {
        CGFloat step = self.visibleMetrics.count ? self.plotRect.size.width / self.visibleMetrics.count : 0;
        for (NSUInteger ordinal = 0; ordinal < self.visibleMetrics.count; ordinal++) {
            NSString *metric = self.visibleMetrics[ordinal]; NSNumber *value = self.latestValues[metric];
            BACellsMark *mark = [BACellsMark new]; mark.observation = self.latestCellObservation; mark.metric = metric; mark.ordinal = ordinal;
            mark.point = CGPointMake(self.plotRect.origin.x + (ordinal + .5) * step, value ? [self yForValue:value.doubleValue] : CGRectGetMidY(self.plotRect));
            [marks addObject:mark];
            CGRect rect = CGRectMake(mark.point.x - step / 2, self.plotRect.origin.y, step, self.plotRect.size.height + row);
            if (self.detailEnabled) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:rect selection:[self selectionForObservation:mark.observation metric:metric]
                accessibilityLabel:[self labelForObservation:mark.observation metric:metric]]];
        }
    } else {
        NSTimeInterval start = self.cellsReport.window.startDate.timeIntervalSince1970, end = self.cellsReport.window.endDate.timeIntervalSince1970;
        NSUInteger columns = MAX(1, MIN(512, (NSUInteger)ceil(self.plotRect.size.width / 3)));
        for (NSUInteger ordinal = 0; ordinal < self.visibleMetrics.count; ordinal++) {
            NSString *metric = self.visibleMetrics[ordinal]; NSData *data = self.preparedHistory.samplesByMetric[metric];
            NSArray<BAAnalyticsObservation *> *points = self.preparedHistory.pointsByMetric[metric];
            const BACellsSample *samples = data.bytes;
            NSArray<NSNumber *> *indices = BACellsEnvelope(data, start, end, columns); display[metric] = indices;
            for (NSNumber *number in indices) {
                NSUInteger index = number.unsignedIntegerValue;
                // Clipped original endpoints contribute to lines, not to a
                // claimed observation at the visible window boundary.
                if (samples[index].time < start || samples[index].time > end) continue;
                BOOL endpoint = !index || index + 1 == points.count ||
                    samples[index].run != samples[index - 1].run || samples[index].run != samples[index + 1].run;
                CGPoint point = CGPointMake([self xForDate:points[index].timestamp], [self yForValue:samples[index].value]);
                BACellsMark *priorMark = marks.lastObject;
                if (dense && !endpoint && samples[index].value != self.preparedHistory.minimum && samples[index].value != self.preparedHistory.maximum &&
                    [priorMark.metric isEqualToString:metric] && fabs(point.x - priorMark.point.x) < 12) continue;
                BACellsMark *mark = [BACellsMark new]; mark.observation = points[index]; mark.metric = metric; mark.ordinal = ordinal;
                mark.point = point; [marks addObject:mark];
                if (self.detailEnabled && !dense) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(mark.point.x - 3, mark.point.y - 3, 6, 6)
                    selection:[self selectionForObservation:mark.observation metric:metric] accessibilityLabel:[self labelForObservation:mark.observation metric:metric]]];
            }
            CGRect identity = CGRectMake(CGRectGetMaxX(self.plotRect) + 13, self.plotRect.origin.y + ordinal * 13, 18, 13);
            if (self.detailEnabled) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:identity selection:[self selectionForObservation:self.latestCellObservation metric:metric]
                accessibilityLabel:[self labelForObservation:self.latestCellObservation metric:metric]]];
        }
        if (self.detailEnabled && dense && !CGRectIsEmpty(self.plotRect)) {
            NSUInteger slices = end > start ? MAX(1, MIN(64, (NSUInteger)ceil(self.plotRect.size.width / 6))) : 1;
            for (NSUInteger slice = 0; slice < slices; slice++) {
                NSDate *a = [NSDate dateWithTimeIntervalSince1970:start + (end - start) * slice / slices];
                NSDate *b = [NSDate dateWithTimeIntervalSince1970:start + (end - start) * (slice + 1) / slices];
                BAAnalyticsDetailSelection *selection = BALiveSelection(self, @"cell-time-slice", nil, self.visibleMetrics, a, b,
                    @{@"unit":@"mV", @"scope":@"original records in the visible time slice, including missing cell fields", @"displayEnvelope":@"first/minimum/maximum/last per screen column; trusted original runs only"});
                [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(self.plotRect.origin.x + self.plotRect.size.width * slice / slices, self.plotRect.origin.y, self.plotRect.size.width / slices, self.plotRect.size.height)
                    selection:selection accessibilityLabel:[NSString stringWithFormat:@"%@ · %@", _("Cell voltage history"), BALiveWindow(a, b)]]];
            }
        }
    }
    // A single bounded group opens all channels, including dense-pack
    // overflow, without allocating one accessibility object per hidden cell.
    if (self.detailEnabled && self.visibleMetrics.count < self.cellMetrics.count)
        [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:self.countRect
            selection:BALiveSelection(self, @"cell-time-slice", nil, self.cellMetrics, self.cellsReport.window.startDate, self.cellsReport.window.endDate,
                @{@"unit":@"mV", @"knownChannelCount":@(self.cellMetrics.count)}) accessibilityLabel:self.accessibilityValue]];
    self.displayIndices = display; self.marks = marks; self.hitRegions = regions;
    [self rebuildUntrustedRects];
}

- (void)rebuildUntrustedRects {
    if (self.compact || self.largeType || CGRectIsEmpty(self.plotRect)) { self.untrustedRects = @[]; return; }
    NSTimeInterval start = self.cellsReport.window.startDate.timeIntervalSince1970, span = [self.cellsReport.window.endDate timeIntervalSinceDate:self.cellsReport.window.startDate];
    NSUInteger columns = MAX(1, MIN(512, (NSUInteger)ceil(self.plotRect.size.width / 3)));
    NSMutableIndexSet *missing = [NSMutableIndexSet indexSet];
    const double *ranges = self.preparedHistory.missingRanges.bytes;
    for (NSUInteger i = 0; span > 0 && i < self.preparedHistory.missingRanges.length / (2 * sizeof(double)); i++) {
        NSUInteger a = MIN(columns - 1, (NSUInteger)MAX(0, floor((ranges[2 * i] - start) / span * columns)));
        NSUInteger b = MIN(columns, (NSUInteger)MAX(0, ceil((ranges[2 * i + 1] - start) / span * columns)));
        if (b > a) [missing addIndexesInRange:NSMakeRange(a, b - a)];
    }
    NSMutableArray *rects = [NSMutableArray array]; CGRect plot = self.plotRect;
    [missing enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
        [rects addObject:[NSValue valueWithCGRect:CGRectMake(plot.origin.x + (double)range.location / columns * plot.size.width, plot.origin.y,
            (double)range.length / columns * plot.size.width, plot.size.height)]];
    }];
    self.untrustedRects = rects;
}

- (void)drawRect:(CGRect)rect {
    if (self.largeType) return;
    UIFont *small = BACellsAnnotationFont(11, UIFontWeightRegular);
    UIColor *label = UIColor.compatLabelColor, *secondary = UIColor.compatSecondaryLabelColor;
    BALiveDrawText(self.largeType ? _("cells\nmV") : @"mV", self.unitRect, small, secondary, NSTextAlignmentLeft);
    BALiveDrawText(self.summaryText ?: @"", self.summaryRect, self.largeType ? BALiveFont(20, UIFontWeightSemibold) :
        BACellsAnnotationFont(self.compact ? 13 : 15, UIFontWeightSemibold), label, self.largeType ? NSTextAlignmentLeft : NSTextAlignmentRight);
    NSString *count = self.countText;
    if (self.visibleMetrics.count < self.cellMetrics.count) count = [NSString stringWithFormat:_("%lu valid · +%lu in detail"),
        (unsigned long)self.latestValues.count, (unsigned long)(self.cellMetrics.count - self.visibleMetrics.count)];
    NSString *timeAndAge = self.latestCellObservation ?
        [NSString stringWithFormat:@"%@ · %@", BALiveTime(self.latestCellObservation.timestamp), self.ageText] :
        _("Time/age unavailable");
    if (self.cardSize == BAAnalyticsCardSize2x1) count = [NSString stringWithFormat:@"%@ · %@", count, timeAndAge];
    BALiveDrawText(count ?: @"", self.countRect, small, secondary, NSTextAlignmentLeft);
    BALiveDrawText(self.compact ? timeAndAge : self.timestampText ?: @"", self.timestampRect, small, secondary, NSTextAlignmentLeft);
    BALiveDrawText(self.ageText ?: @"", self.ageRect, small, secondary, NSTextAlignmentLeft);
    BALiveDrawText(self.windowText ?: @"", self.windowRect, small, secondary, NSTextAlignmentLeft);
    if (CGRectIsEmpty(self.plotRect)) return;
    if (!self.cellMetrics.count) {
        BALiveHatch(self.plotRect);
        return;
    }
    BOOL hasScale = self.latestValues.count != 0 || self.marks.count != 0;
    if (hasScale && !self.largeType) {
        BALiveDrawText([NSString stringWithFormat:@"%.0f", self.maximum], CGRectMake(2, self.plotRect.origin.y - 4, self.plotRect.origin.x - 5, small.lineHeight), small, secondary, NSTextAlignmentRight);
        BALiveDrawText([NSString stringWithFormat:@"%.0f", self.minimum], CGRectMake(2, CGRectGetMaxY(self.plotRect) - small.lineHeight, self.plotRect.origin.x - 5, small.lineHeight), small, secondary, NSTextAlignmentRight);
        BALiveLine(self.plotRect.origin, CGPointMake(CGRectGetMaxX(self.plotRect), CGRectGetMinY(self.plotRect)), UIColor.compatSeparatorColor, .5, NO);
        BALiveLine(CGPointMake(CGRectGetMinX(self.plotRect), CGRectGetMaxY(self.plotRect)), CGPointMake(CGRectGetMaxX(self.plotRect), CGRectGetMaxY(self.plotRect)), UIColor.compatSeparatorColor, .5, NO);
    }
    if (self.compact || self.largeType) {
        CGFloat step = self.visibleMetrics.count ? self.plotRect.size.width / self.visibleMetrics.count : 0;
        for (BACellsMark *mark in self.marks) {
            NSNumber *value = self.latestValues[mark.metric]; CGFloat rodWidth = MIN(12, step * .45);
            CGRect rod = CGRectMake(mark.point.x - rodWidth / 2, self.plotRect.origin.y, rodWidth, self.plotRect.size.height);
            if (!value) BALiveHatch(rod);
            else {
                BACellsStroke(CGPointMake(mark.point.x, CGRectGetMaxY(self.plotRect)), mark.point, mark.ordinal);
                BACellsMarker(mark.point, mark.ordinal);
            }
            BALiveDrawText([NSString stringWithFormat:@"%lld%@", BACellIndex(mark.metric).longLongValue + 1, value ? @"" : @"—"],
                CGRectMake(mark.point.x - step / 2, CGRectGetMaxY(self.plotRect) + 1, step, small.lineHeight), small, secondary, NSTextAlignmentCenter);
        }
    } else {
        for (NSValue *value in self.untrustedRects) BALiveHatch(value.CGRectValue);
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context); CGContextClipToRect(context, CGRectInset(self.plotRect, -3, -3));
        CGContextSetStrokeColorWithColor(context, UIColor.compatBlueColor.CGColor); CGContextSetLineWidth(context, 1.7);
        for (NSUInteger ordinal = 0; ordinal < self.visibleMetrics.count; ordinal++) {
            NSString *metric = self.visibleMetrics[ordinal];
            NSData *data = self.preparedHistory.samplesByMetric[metric]; const BACellsSample *samples = data.bytes;
            NSArray<NSNumber *> *indices = self.displayIndices[metric];
            CGFloat dashed[] = {5, 3}, dotted[] = {1, 3};
            CGContextSetLineDash(context, 0, ordinal % 3 == 1 ? dashed : ordinal % 3 == 2 ? dotted : NULL, ordinal % 3 ? 2 : 0);
            NSUInteger previous = NSNotFound;
            NSTimeInterval start = self.cellsReport.window.startDate.timeIntervalSince1970, duration = [self.cellsReport.window.endDate timeIntervalSinceDate:self.cellsReport.window.startDate];
            for (NSNumber *number in indices) {
                NSUInteger index = number.unsignedIntegerValue;
                if (previous != NSNotFound && samples[index].run == samples[previous].run) {
                    CGFloat ax = self.plotRect.origin.x + (duration > 0 ? (samples[previous].time - start) / duration : .5) * self.plotRect.size.width;
                    CGFloat bx = self.plotRect.origin.x + (duration > 0 ? (samples[index].time - start) / duration : .5) * self.plotRect.size.width;
                    CGContextMoveToPoint(context, ax, [self yForValue:samples[previous].value]);
                    CGContextAddLineToPoint(context, bx, [self yForValue:samples[index].value]);
                }
                previous = index;
            }
            CGContextStrokePath(context);
        }
        CGContextSetLineDash(context, 0, NULL, 0);
        for (BACellsMark *mark in self.marks) BACellsMarker(mark.point, mark.ordinal);
        CGContextRestoreGState(context);
        for (NSUInteger ordinal = 0; ordinal < self.visibleMetrics.count; ordinal++) {
            NSString *metric = self.visibleMetrics[ordinal]; NSNumber *value = self.latestValues[metric];
            CGRect identity = CGRectMake(CGRectGetMaxX(self.plotRect) + 13, self.plotRect.origin.y + ordinal * 13, 18, 13);
            if (!value) BALiveHatch(identity);
            else BACellsStroke(CGPointMake(CGRectGetMaxX(self.plotRect) + 2, CGRectGetMidY(identity)), CGPointMake(CGRectGetMaxX(self.plotRect) + 11, CGRectGetMidY(identity)), ordinal);
            BALiveDrawText([NSString stringWithFormat:@"%lld%@", BACellIndex(metric).longLongValue + 1, value ? @"" : @"—"], identity, small, label, NSTextAlignmentLeft);
        }
    }
}
@end

@interface BAAnalyticsCellsCanvasCard : BAAnalyticsCanvasCard
@property (nonatomic, strong) NSHashTable<BAAnalyticsCellsCanvasView *> *cellViews;
@end
@interface BACellsDetailViewController : BAAnalyticsDetailViewController
@end
@implementation BACellsDetailViewController
- (UIView *)makeVisualizationView {
    BAAnalyticsCellsCanvasView *view = [BAAnalyticsCellsCanvasView new];
    view.cardSize = BAAnalyticsCardSize2x2; view.familyIdentifier = self.familyReport.family;
    view.latestReport = self.report; view.latestSnapshot = self.snapshot;
    view.detailEnabled = NO;
    [view reloadReport];
    return view;
}
- (NSArray<NSDictionary *> *)summaryRows {
    BAAnalyticsObservation *point = self.selectedObservations.lastObject ?: self.familyReport.window.observations.lastObject;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *metric in [point.values.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![metric hasPrefix:@"cell-voltage."]) continue;
        NSNumber *number = BALiveObservationValue(point, metric); if (!number) continue;
        NSArray *parts = [metric componentsSeparatedByString:@"."];
        [rows addObject:@{@"title":[NSString stringWithFormat:_("Cell %ld"), (long)[parts[1] integerValue] + 1], @"value":[NSString stringWithFormat:@"%.0f mV", number.doubleValue]}];
    }
    return rows;
}
@end

@implementation BAAnalyticsCellsCanvasCard
- (BOOL)supportsDetails { return YES; }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    BAAnalyticsReport *report = nil;
    NSNumber *sequence = selection.context[@"reportSequence"];
    for (BAAnalyticsCellsCanvasView *view in self.cellViews.allObjects) {
        if (sequence ? view.displayedReport.sequenceNumber == sequence.unsignedLongLongValue : view.cardSize == size) {
            report = view.displayedReport; if (report) break;
        }
    }
    if (!report && (!sequence || self.latestReport.sequenceNumber == sequence.unsignedLongLongValue)) report = self.latestReport;
    if (sequence && !report) return nil;
    return [[BACellsDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier
         report:report snapshot:self.latestSnapshot selection:selection];
}

- (BAAnalyticsCanvasView *)makeCanvasView {
    BAAnalyticsCellsCanvasView *view = [[BAAnalyticsCellsCanvasView alloc] initWithFrame:CGRectZero];
    if (!self.cellViews) self.cellViews = [NSHashTable weakObjectsHashTable];
    [self.cellViews addObject:view];
    return view;
}
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view { [(BAAnalyticsCellsCanvasView *)view reloadReport]; }
@end

id<BAAnalyticsCard> BAAnalyticsCreateCellsCanvasCard(void) {
    return [[BAAnalyticsCellsCanvasCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.cells"
             displayName:_("Cell consistency") familyIdentifier:BAAnalyticsFamilyCells
          supportedSizes:BAAnalyticsCardSizeMask1x1 | BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2
             defaultSize:BAAnalyticsCardSize2x1];
}
