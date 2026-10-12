#import "../Canvas/BAAnalyticsDetailViewController.h"
#import "main.h"
#import "BAAnalyticsLiveDrawing.h"
#include <float.h>
#include <math.h>

// FCC is an estimate at a point in time. Neither this graph nor its ratio is a
// health score, continuous 30-day coverage, or a battery-lifetime forecast.
static NSNumber *BACapacityPositive(NSNumber *value) {
    return value.doubleValue > 0 ? value : nil;
}

static NSNumber *BACapacityFCC(NSNumber *value) {
    return value && value.doubleValue >= 0 ? value : nil;
}

static BOOL BACapacitySelectionUsesCurrentSnapshot(BAAnalyticsDetailSelection *selection) {
    return !selection || [selection.kind isEqual:@"overview"] ||
        ([selection.kind isEqual:@"capacity-ratio"] && [selection.context[@"source"] isEqual:@"metricSnapshot"]);
}

static BAAnalyticsObservation *BACapacityLastValidObservation(NSArray<BAAnalyticsObservation *> *points) {
    for (BAAnalyticsObservation *point in points.reverseObjectEnumerator) {
        if (BACapacityFCC(BALiveObservationValue(point, BAAnalyticsHistoryFullChargeCapacityMilliampHours))) return point;
    }
    return nil;
}

static NSString *BACapacityNumber(double value, NSUInteger decimals) {
    NSMutableDictionary *storage = NSThread.currentThread.threadDictionary;
    NSString *key = [NSString stringWithFormat:@"Battman.capacity.number.%lu", (unsigned long)decimals];
    NSNumberFormatter *formatter = storage[key];
    NSLocale *locale = NSLocale.currentLocale;
    if (!formatter || ![formatter.locale.localeIdentifier isEqualToString:locale.localeIdentifier]) {
        formatter = [NSNumberFormatter new];
        formatter.locale = locale;
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.maximumFractionDigits = decimals;
        formatter.minimumFractionDigits = decimals;
        storage[key] = formatter;
    }
    return [formatter stringFromNumber:@(value)] ?: @"—";
}

static BOOL BACapacitySameField(BAAnalyticsObservation *a, BAAnalyticsObservation *b, NSString *metric) {
    BAAnalyticsFieldMetadata *left = a.fieldMetadata[metric];
    BAAnalyticsFieldMetadata *right = b.fieldMetadata[metric];
    return left.unitValidated && right.unitValidated &&
           [left.sourceTable isEqual:right.sourceTable] &&
           [left.sourceColumn isEqual:right.sourceColumn] &&
           [left.unit isEqual:right.unit] &&
           [left.decoderIdentifier isEqual:right.decoderIdentifier];
}

static BOOL BACapacitySameConfiguration(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
    NSNumber *leftDesign = BACapacityPositive(BALiveObservationValue(a, BAAnalyticsHistoryDesignCapacityMilliampHours));
    NSNumber *rightDesign = BACapacityPositive(BALiveObservationValue(b, BAAnalyticsHistoryDesignCapacityMilliampHours));
    if (!leftDesign || !rightDesign || ![leftDesign isEqualToNumber:rightDesign] ||
        !BACapacitySameField(a, b, BAAnalyticsHistoryFullChargeCapacityMilliampHours) ||
        !BACapacitySameField(a, b, BAAnalyticsHistoryDesignCapacityMilliampHours)) return NO;
    NSNumber *leftCycles = BALiveObservationValue(a, BAAnalyticsHistoryCycleCount);
    NSNumber *rightCycles = BALiveObservationValue(b, BAAnalyticsHistoryCycleCount);
    // A reset is a boundary, not proof of a diagnosed replacement/calibration.
    return !(leftCycles && rightCycles && rightCycles.doubleValue < leftCycles.doubleValue);
}

typedef struct {
    NSTimeInterval time;
    double value;
    NSUInteger run;
    BOOL boundary;
} BACapacitySample;

@interface BACapacityPreparedHistory : NSObject
@property (nonatomic, copy) NSArray<BAAnalyticsObservation *> *points;
@property (nonatomic, copy) NSData *samples;
@property (nonatomic, copy) NSData *gaps;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@end
@implementation BACapacityPreparedHistory
@end

@interface BACapacityPreparationToken : NSObject
@property (atomic, getter=isCancelled) BOOL cancelled;
@end
@implementation BACapacityPreparationToken
@end

// Foundation-only preparation. Original records in the selected scope and
// every trusted/untrusted edge are retained before choosing a display envelope.
static BACapacityPreparedHistory *BACapacityPrepare(BAAnalyticsFamilyReport *family, BAAnalyticsDetailSelection *selection, BACapacityPreparationToken *token) {
    if (token.isCancelled) return nil;
    BACapacityPreparedHistory *prepared = [BACapacityPreparedHistory new];
    NSMutableArray<BAAnalyticsObservation *> *points = [NSMutableArray array];
    NSSet<NSString *> *selectedIDs = [NSSet setWithArray:selection.recordIdentifiers ?: @[]];
    NSUInteger scanned = 0; BOOL ordered = YES; BAAnalyticsObservation *priorPoint = nil;
    for (BAAnalyticsObservation *point in family.window.observations) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if (BACapacityFCC(BALiveObservationValue(point, BAAnalyticsHistoryFullChargeCapacityMilliampHours)) &&
            [point.timestamp compare:family.window.startDate] != NSOrderedAscending &&
            [point.timestamp compare:family.window.endDate] != NSOrderedDescending &&
            (!selectedIDs.count || [selectedIDs containsObject:point.identifier]) &&
            (!selection.startDate || [point.timestamp compare:selection.startDate] != NSOrderedAscending) &&
            (!selection.endDate || [point.timestamp compare:selection.endDate] != NSOrderedDescending)) {
            NSComparisonResult order = priorPoint ? [priorPoint.timestamp compare:point.timestamp] : NSOrderedAscending;
            if (order == NSOrderedDescending || (order == NSOrderedSame && [priorPoint.identifier compare:point.identifier] == NSOrderedDescending)) ordered = NO;
            [points addObject:point]; priorPoint = point;
        }
    }
    if (token.isCancelled) return nil;
    if (!ordered) [points sortUsingComparator:^NSComparisonResult(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
        NSComparisonResult order = [a.timestamp compare:b.timestamp];
        return order == NSOrderedSame ? [a.identifier compare:b.identifier] : order;
    }];
    if (token.isCancelled) return nil;
    prepared.points = points;
    NSMutableData *data = [NSMutableData dataWithLength:points.count * sizeof(BACapacitySample)];
    BACapacitySample *samples = data.mutableBytes;
    NSMutableDictionary<NSString *, NSNumber *> *indices = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *duplicates = [NSMutableSet set];
    for (NSUInteger i = 0; i < points.count; i++) {
        if ((i & 255) == 0 && token.isCancelled) return nil;
        NSString *identifier = points[i].identifier;
        if (!identifier.length) continue;
        if (indices[identifier]) [duplicates addObject:identifier];
        indices[identifier] = @(i);
    }
    NSMutableIndexSet *trusted = [NSMutableIndexSet indexSet];
    scanned = 0;
    for (BAAnalyticsHistoryInterval *interval in family.window.intervals) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        if (!interval.startObservation.identifier.length || !interval.endObservation.identifier.length) continue;
        NSNumber *a = indices[interval.startObservation.identifier], *b = indices[interval.endObservation.identifier];
        if (!a || !b || b.unsignedIntegerValue != a.unsignedIntegerValue + 1 ||
            [duplicates containsObject:interval.startObservation.identifier] || [duplicates containsObject:interval.endObservation.identifier]) continue;
        if (interval.duration > 0 && [interval.coveredMetricIdentifiers containsObject:BAAnalyticsHistoryFullChargeCapacityMilliampHours] &&
            [interval.startDate compare:points[a.unsignedIntegerValue].timestamp] != NSOrderedDescending &&
            [interval.endDate compare:points[b.unsignedIntegerValue].timestamp] != NSOrderedAscending)
            [trusted addIndex:b.unsignedIntegerValue];
    }
    NSArray<BAAnalyticsHistoryGap *> *gaps = [family.window.gaps sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryGap *a, BAAnalyticsHistoryGap *b) {
        return [a.startDate compare:b.startDate];
    }];
    if (token.isCancelled) return nil;
    NSUInteger gapIndex = 0;
    double low = DBL_MAX, high = -DBL_MAX;
    for (NSUInteger i = 0; i < points.count; i++) {
        if ((i & 255) == 0 && token.isCancelled) return nil;
        BAAnalyticsObservation *point = points[i], *previous = i ? points[i - 1] : nil;
        samples[i].time = point.timestamp.timeIntervalSince1970;
        samples[i].value = BALiveObservationValue(point, BAAnalyticsHistoryFullChargeCapacityMilliampHours).doubleValue;
        low = MIN(low, samples[i].value); high = MAX(high, samples[i].value);
        if (!previous) continue;
        while (gapIndex < gaps.count && [gaps[gapIndex].endDate compare:previous.timestamp] != NSOrderedDescending) gapIndex++;
        BOOL gap = gapIndex < gaps.count && [gaps[gapIndex].startDate compare:point.timestamp] == NSOrderedAscending;
        BOOL joined = [trusted containsIndex:i] && !gap && BACapacitySameConfiguration(previous, point);
        samples[i].run = samples[i - 1].run + !joined;
        NSNumber *a = BACapacityPositive(BALiveObservationValue(previous, BAAnalyticsHistoryDesignCapacityMilliampHours));
        NSNumber *b = BACapacityPositive(BALiveObservationValue(point, BAAnalyticsHistoryDesignCapacityMilliampHours));
        NSNumber *ac = BALiveObservationValue(previous, BAAnalyticsHistoryCycleCount), *bc = BALiveObservationValue(point, BAAnalyticsHistoryCycleCount);
        samples[i].boundary = !BACapacitySameField(previous, point, BAAnalyticsHistoryFullChargeCapacityMilliampHours) ||
            (a && b && ![a isEqualToNumber:b]) || (ac && bc && bc.doubleValue < ac.doubleValue);
    }
    prepared.samples = data;
    NSMutableData *gapData = [NSMutableData data];
    NSTimeInterval gapStart = 0, gapEnd = 0;
    BOOL openGap = NO;
    scanned = 0;
    for (BAAnalyticsHistoryGap *gap in gaps) {
        if ((scanned++ & 255) == 0 && token.isCancelled) return nil;
        double a = MAX(points.firstObject.timestamp.timeIntervalSince1970, gap.startDate.timeIntervalSince1970);
        double b = MIN(points.lastObject.timestamp.timeIntervalSince1970, gap.endDate.timeIntervalSince1970);
        if (b <= a) continue;
        if (openGap && a > gapEnd) { double pair[] = {gapStart, gapEnd}; [gapData appendBytes:pair length:sizeof(pair)]; openGap = NO; }
        if (!openGap) { gapStart = a; gapEnd = b; openGap = YES; } else gapEnd = MAX(gapEnd, b);
    }
    if (openGap) { double pair[] = {gapStart, gapEnd}; [gapData appendBytes:pair length:sizeof(pair)]; }
    prepared.gaps = gapData;
    prepared.minimum = points.count ? low : 0; prepared.maximum = points.count ? high : 1;
    if (token.isCancelled) return nil;
    return prepared;
}

static NSUInteger BACapacitySampleBound(BACapacityPreparedHistory *prepared, NSTimeInterval time, BOOL upper) {
    const BACapacitySample *samples = prepared.samples.bytes;
    NSUInteger low = 0, high = prepared.points.count;
    while (low < high) {
        NSUInteger middle = low + (high - low) / 2;
        if (samples[middle].time < time || (upper && samples[middle].time == time)) low = middle + 1;
        else high = middle;
    }
    return low;
}

static NSArray<NSNumber *> *BACapacityEnvelopeInRange(BACapacityPreparedHistory *prepared, NSRange range,
                                                      NSTimeInterval start, NSTimeInterval span, NSUInteger columns) {
    NSUInteger count = range.length;
    if (!count) return @[];
    if (count <= 4 * columns) {
        NSMutableArray *all = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger i = range.location; i < NSMaxRange(range); i++) [all addObject:@(i)];
        return all;
    }
    const BACapacitySample *samples = prepared.samples.bytes;
    NSMutableIndexSet *kept = [NSMutableIndexSet indexSet];
    NSUInteger first = range.location, minimum = first, maximum = first, last = first, priorColumn = NSNotFound;
    for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
        NSUInteger column = span > 0 ? MIN(columns - 1, (NSUInteger)MAX(0, floor((samples[i].time - start) / span * columns))) : 0;
        // Bound even a heavily fragmented history to four original points per
        // time bucket. Monotone original run IDs below still prohibit a line
        // across any omitted untrusted edge or configuration change.
        if (column != priorColumn) {
            if (priorColumn != NSNotFound) { [kept addIndex:first]; [kept addIndex:minimum]; [kept addIndex:maximum]; [kept addIndex:last]; }
            first = minimum = maximum = i; priorColumn = column;
        }
        if (samples[i].value < samples[minimum].value) minimum = i;
        if (samples[i].value > samples[maximum].value) maximum = i;
        last = i;
    }
    [kept addIndex:first]; [kept addIndex:minimum]; [kept addIndex:maximum]; [kept addIndex:last];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:kept.count];
    [kept enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [result addObject:@(index)]; }];
    return result;
}

static NSArray<NSNumber *> *BACapacityEnvelope(BACapacityPreparedHistory *prepared, NSUInteger columns) {
    NSUInteger count = prepared.points.count;
    if (!count) return @[];
    const BACapacitySample *samples = prepared.samples.bytes;
    return BACapacityEnvelopeInRange(prepared, NSMakeRange(0, count), samples[0].time,
                                     samples[count - 1].time - samples[0].time, columns);
}

static NSArray<NSNumber *> *BACapacityMarkers(BACapacityPreparedHistory *prepared, NSArray<NSNumber *> *indices, NSUInteger budget) {
    if (!indices.count) return @[];
    const BACapacitySample *samples = prepared.samples.bytes;
    NSMutableIndexSet *kept = [NSMutableIndexSet indexSet];
    NSUInteger minimum = indices.firstObject.unsignedIntegerValue, maximum = minimum;
    for (NSNumber *number in indices) {
        NSUInteger index = number.unsignedIntegerValue;
        if (samples[index].value < samples[minimum].value) minimum = index;
        if (samples[index].value > samples[maximum].value) maximum = index;
    }
    [kept addIndex:indices.firstObject.unsignedIntegerValue];
    [kept addIndex:indices.lastObject.unsignedIntegerValue];
    [kept addIndex:minimum]; [kept addIndex:maximum];
    // Circles distinguish sparse estimates without obscuring the trend. The
    // endpoints and measured extrema are mandatory; remaining space is spread
    // across the complete window rather than filled with every run endpoint.
    NSTimeInterval first = samples[indices.firstObject.unsignedIntegerValue].time;
    NSTimeInterval span = samples[indices.lastObject.unsignedIntegerValue].time - first;
    NSUInteger remaining = budget > kept.count ? budget - kept.count : 0;
    for (NSUInteger slot = 0; slot < remaining; slot++) {
        double target = first + span * (slot + 1) / (remaining + 1);
        NSUInteger nearest = indices.firstObject.unsignedIntegerValue;
        double distance = DBL_MAX;
        for (NSNumber *number in indices) {
            NSUInteger index = number.unsignedIntegerValue;
            if ([kept containsIndex:index]) continue;
            double candidate = fabs(samples[index].time - target);
            if (candidate < distance) { nearest = index; distance = candidate; }
        }
        if (distance != DBL_MAX) [kept addIndex:nearest];
    }
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:kept.count];
    [kept enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [result addObject:@(index)]; }];
    return result;
}

@interface BAAnalyticsCapacityCanvasView : BAAnalyticsCanvasView <UIScrollViewDelegate>
@property (nonatomic, copy) NSArray<BAAnalyticsObservation *> *capacityObservations;
@property (nonatomic, strong) NSNumber *fullCharge;
@property (nonatomic, strong) NSNumber *designCapacity;
@property (nonatomic, strong) NSDate *capacityTimestamp;
@property (nonatomic, copy) NSArray<NSString *> *currentRecordIdentifiers;
@property (nonatomic, copy) NSString *currentSource;
@property (nonatomic, strong) UIScrollView *largeTypeScrollView;
@property (nonatomic, strong) UILabel *largeTypeLabel;
@property (nonatomic, strong) BAAnalyticsFamilyReport *requestedFamily;
@property (nonatomic, strong) BAAnalyticsReport *incomingReport;
@property (nonatomic, strong) BAAnalyticsReport *requestedReport;
@property (nonatomic, strong) BAAnalyticsReport *displayedReport;
@property (nonatomic, strong) BACapacityPreparedHistory *preparedHistory;
@property (nonatomic, getter=isPreparingHistory) BOOL preparingHistory;
@property (nonatomic) NSUInteger preparationGeneration;
@property (nonatomic, copy) NSArray<NSNumber *> *displayIndices;
@property (nonatomic, copy) NSArray<NSNumber *> *displayMarkerIndices;
@property (nonatomic, copy) NSArray<NSNumber *> *boundaryIndices;
@property (nonatomic, copy) NSArray<NSValue *> *displayGaps;
@property (nonatomic, copy) NSArray<NSValue *> *displayGapRects;
@property (nonatomic) CGRect displayGapGeometry;
@property (nonatomic) CGFloat displayWidth;
@property (nonatomic, strong) NSDateFormatter *pointFormatter;
@property (nonatomic, strong) BACapacityPreparationToken *preparationToken;
// Set before a detail canvas receives its report. Historical selections scope
// both the graphic and its capacity pair; overview keeps the complete trend.
@property (nonatomic, strong) BAAnalyticsDetailSelection *capacitySelection;
@property (nonatomic) BOOL detailBrowsingEnabled;
@property (nonatomic, strong) UISegmentedControl *historyRangeControl;
@property (nonatomic, strong) UIScrollView *historyScrollView;
@property (nonatomic, weak) BACapacityPreparedHistory *browsingPreparedHistory;
@property (nonatomic) NSTimeInterval historyWindowStart;
@property (nonatomic) NSTimeInterval historyWindowDuration;
@property (nonatomic) BOOL updatingHistoryScroller;
@property (nonatomic) BOOL historyViewportInitialized;
@property (nonatomic) NSUInteger selectedHistoryIndex;
@property (nonatomic) CGRect historyPlotRect;
@property (nonatomic, strong) UIAccessibilityElement *historyOverviewElement;
- (void)refreshCapacity;
- (void)startHistoryPreparation;
- (void)renderCapacityWithRegions:(NSMutableArray *)regions;
@end

@implementation BAAnalyticsCapacityCanvasView
@synthesize preparingHistory = _preparingHistory;

- (void)dealloc { _preparationToken.cancelled = YES; }

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        _capacityObservations = @[];
        _currentRecordIdentifiers = @[];
        _currentSource = @"unavailable";
        _displayIndices = @[]; _displayMarkerIndices = @[]; _boundaryIndices = @[]; _displayGaps = @[]; _displayGapRects = @[];
        _displayGapGeometry = CGRectNull;
        _selectedHistoryIndex = NSNotFound;
        _pointFormatter = [NSDateFormatter new];
        [_pointFormatter setLocalizedDateFormatFromTemplate:@"MMddHHmmss"];
        // At accessibility sizes a compact card cannot hold the complete
        // enlarged summary. Reflow it into a scrollable text canvas rather
        // than shrinking every label or clipping essential units/window/n.
        _largeTypeScrollView = [UIScrollView new];
        _largeTypeScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        _largeTypeScrollView.alwaysBounceVertical = NO;
        _largeTypeScrollView.showsVerticalScrollIndicator = YES;
        _largeTypeScrollView.backgroundColor = UIColor.clearColor;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openLargeTypeOverview:)];
        tap.cancelsTouchesInView = NO;
        [_largeTypeScrollView addGestureRecognizer:tap];
        _largeTypeLabel = [UILabel new];
        _largeTypeLabel.numberOfLines = 0;
        _largeTypeLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _largeTypeLabel.isAccessibilityElement = NO;
        [_largeTypeScrollView addSubview:_largeTypeLabel];
        [self addSubview:_largeTypeScrollView];
    }
    return self;
}

- (void)setDetailBrowsingEnabled:(BOOL)enabled {
    if (_detailBrowsingEnabled == enabled) return;
    _detailBrowsingEnabled = enabled;
    if (enabled && !self.historyRangeControl) {
        self.historyRangeControl = [[UISegmentedControl alloc] initWithItems:@[_("1 day"), _("7 days"), _("All")]];
        self.historyRangeControl.selectedSegmentIndex = 1;
        [self.historyRangeControl addTarget:self action:@selector(historyRangeChanged:) forControlEvents:UIControlEventValueChanged];
        self.historyRangeControl.accessibilityLabel = _("History range");
        [self addSubview:self.historyRangeControl];
        self.historyScrollView = [UIScrollView new];
        self.historyScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        self.historyScrollView.delegate = self;
        self.historyScrollView.directionalLockEnabled = YES;
        self.historyScrollView.showsVerticalScrollIndicator = NO;
        self.historyScrollView.showsHorizontalScrollIndicator = YES;
        self.historyScrollView.backgroundColor = UIColor.clearColor;
        self.historyScrollView.isAccessibilityElement = YES;
        self.historyScrollView.accessibilityLabel = _("Capacity history");
        self.historyScrollView.accessibilityHint = _("Swipe for history; tap a reading for its value and time.");
        self.historyScrollView.accessibilityCustomActions = @[
            [[UIAccessibilityCustomAction alloc] initWithName:_("Earlier readings") target:self selector:@selector(showEarlierHistory:)],
            [[UIAccessibilityCustomAction alloc] initWithName:_("Later readings") target:self selector:@selector(showLaterHistory:)]];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectHistoryReading:)];
        [self.historyScrollView addGestureRecognizer:tap];
        [self addSubview:self.historyScrollView];
        self.historyOverviewElement = [[UIAccessibilityElement alloc] initWithAccessibilityContainer:self];
    }
    self.historyRangeControl.hidden = !enabled;
    self.historyScrollView.hidden = !enabled;
    [self setNeedsLayout];
}

- (void)historyRangeChanged:(UISegmentedControl *)sender {
    self.historyViewportInitialized = NO;
    self.selectedHistoryIndex = NSNotFound;
    self.displayWidth = -1;
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)prepareHistoryViewport {
    BACapacityPreparedHistory *prepared = self.preparedHistory;
    const BACapacitySample *samples = prepared.samples.bytes;
    NSUInteger count = prepared.points.count;
    if (!count) return;
    NSTimeInterval first = samples[0].time, last = samples[count - 1].time;
    NSTimeInterval wholeSpan = MAX(1, last - first);
    [self.historyRangeControl setEnabled:wholeSpan > 86400 forSegmentAtIndex:0];
    [self.historyRangeControl setEnabled:wholeSpan > 604800 forSegmentAtIndex:1];
    NSInteger choice = self.historyRangeControl.selectedSegmentIndex;
    if ((choice == 0 && wholeSpan <= 86400) || (choice == 1 && wholeSpan <= 604800)) {
        choice = 2;
        self.historyRangeControl.selectedSegmentIndex = choice;
    }
    NSTimeInterval duration = MIN(wholeSpan, choice == 0 ? 86400 : choice == 1 ? 604800 : wholeSpan);
    if (!self.historyViewportInitialized || self.browsingPreparedHistory != prepared) {
        self.historyWindowStart = MAX(first, last - duration);
        self.historyViewportInitialized = YES;
        self.browsingPreparedHistory = prepared;
        self.selectedHistoryIndex = NSNotFound;
        self.displayWidth = -1;
    }
    self.historyWindowDuration = duration;
    self.historyWindowStart = MAX(first, MIN(self.historyWindowStart, MAX(first, last - duration)));
}

- (void)layoutHistoryScrollerInRect:(CGRect)graph {
    self.historyPlotRect = graph;
    BACapacityPreparedHistory *prepared = self.preparedHistory;
    const BACapacitySample *samples = prepared.samples.bytes;
    NSUInteger count = prepared.points.count;
    if (!count || CGRectIsEmpty(graph)) {
        self.historyScrollView.hidden = YES;
        return;
    }
    NSTimeInterval first = samples[0].time, wholeSpan = MAX(1, samples[count - 1].time - first);
    NSTimeInterval duration = self.historyWindowDuration;
    BOOL widthChanged = graph.size.width != self.historyScrollView.bounds.size.width;
    self.updatingHistoryScroller = YES;
    self.historyScrollView.hidden = NO;
    if (!CGRectEqualToRect(self.historyScrollView.frame, graph)) self.historyScrollView.frame = graph;
    // Only the content extent grows. The drawing remains in this fixed-size
    // canvas, with no wide image or view backing store to allocate.
    CGSize extent = CGSizeMake(graph.size.width * wholeSpan / duration, graph.size.height);
    if (!CGSizeEqualToSize(self.historyScrollView.contentSize, extent)) self.historyScrollView.contentSize = extent;
    // Footer reflow can change the height while a horizontal pan is active.
    // Keep UIKit's in-flight offset unless the horizontal geometry changed.
    if (widthChanged || (!self.historyScrollView.tracking && !self.historyScrollView.dragging && !self.historyScrollView.decelerating)) {
        CGPoint offset = CGPointMake((self.historyWindowStart - first) / duration * graph.size.width, 0);
        CGPoint currentOffset = self.historyScrollView.contentOffset;
        // Absolute timestamps lose tiny fractions on conversion back to an
        // offset. Do not interrupt a programmatic scroll animation for them.
        if (fabs(currentOffset.x - offset.x) > .25 || fabs(currentOffset.y - offset.y) > .25)
            self.historyScrollView.contentOffset = offset;
    }
    self.updatingHistoryScroller = NO;
    [self updateHistoryAccessibility];
}

- (void)updateHistoryAccessibility {
    if (!self.historyViewportInitialized) return;
    NSString *window = BALiveWindow([NSDate dateWithTimeIntervalSince1970:self.historyWindowStart],
        [NSDate dateWithTimeIntervalSince1970:self.historyWindowStart + self.historyWindowDuration]);
    NSString *reading = [self selectedHistoryReadingText];
    self.historyScrollView.accessibilityValue = reading ? [NSString stringWithFormat:@"%@. %@", reading, window] : window;
}

- (NSString *)selectedHistoryReadingText {
    if (self.selectedHistoryIndex >= self.preparedHistory.points.count) return nil;
    BAAnalyticsObservation *reading = self.preparedHistory.points[self.selectedHistoryIndex];
    const BACapacitySample *samples = self.preparedHistory.samples.bytes;
    return [NSString stringWithFormat:@"%@ mAh · %@", BACapacityNumber(samples[self.selectedHistoryIndex].value, 0), [self.pointFormatter stringFromDate:reading.timestamp]];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.historyScrollView || self.updatingHistoryScroller || !self.preparedHistory.points.count || scrollView.bounds.size.width <= 0) return;
    const BACapacitySample *samples = self.preparedHistory.samples.bytes;
    NSUInteger count = self.preparedHistory.points.count;
    NSTimeInterval first = samples[0].time, latestStart = MAX(first, samples[count - 1].time - self.historyWindowDuration);
    NSTimeInterval start = MAX(first, MIN(latestStart, first + scrollView.contentOffset.x / scrollView.bounds.size.width * self.historyWindowDuration));
    if (start == self.historyWindowStart) return;
    self.historyWindowStart = start;
    self.selectedHistoryIndex = NSNotFound;
    self.displayWidth = -1;
    [self updateHistoryAccessibility];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (BOOL)moveHistoryByDirection:(NSInteger)direction {
    CGFloat target = self.historyScrollView.contentOffset.x + direction * self.historyScrollView.bounds.size.width;
    target = MAX(0, MIN(target, MAX(0, self.historyScrollView.contentSize.width - self.historyScrollView.bounds.size.width)));
    if (target == self.historyScrollView.contentOffset.x) return NO;
    [self.historyScrollView setContentOffset:CGPointMake(target, 0) animated:YES];
    return YES;
}
- (BOOL)showEarlierHistory:(UIAccessibilityCustomAction *)action { return [self moveHistoryByDirection:-1]; }
- (BOOL)showLaterHistory:(UIAccessibilityCustomAction *)action { return [self moveHistoryByDirection:1]; }

- (void)selectHistoryReading:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded || !self.historyViewportInitialized || !self.preparedHistory.points.count) return;
    CGPoint point = [recognizer locationInView:self];
    CGFloat fraction = (point.x - self.historyPlotRect.origin.x) / MAX(1, self.historyPlotRect.size.width);
    NSTimeInterval target = self.historyWindowStart + MAX(0, MIN(1, fraction)) * self.historyWindowDuration;
    NSUInteger first = BACapacitySampleBound(self.preparedHistory, self.historyWindowStart, NO);
    NSUInteger end = BACapacitySampleBound(self.preparedHistory, self.historyWindowStart + self.historyWindowDuration, YES);
    if (first >= end) return;
    NSUInteger index = MIN(end - 1, MAX(first, BACapacitySampleBound(self.preparedHistory, target, NO)));
    const BACapacitySample *samples = self.preparedHistory.samples.bytes;
    if (index > first && fabs(samples[index - 1].time - target) < fabs(samples[index].time - target)) index--;
    self.selectedHistoryIndex = index;
    [self updateHistoryAccessibility];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [self selectedHistoryReadingText]);
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)openLargeTypeOverview:(UITapGestureRecognizer *)recognizer {
    if (!self.isEditing && recognizer.state == UIGestureRecognizerStateEnded)
        [self requestDetailForSelection:nil];
}

- (void)setLatestReport:(BAAnalyticsReport *)report {
    // The base card may receive a newer report while this canvas is preparing.
    // Keep geometry, field metadata and selection sequence on the displayed
    // generation until its replacement is complete.
    self.incomingReport = report;
    if (!self.preparedHistory) [self adoptDisplayedReport:report];
}

- (void)adoptDisplayedReport:(BAAnalyticsReport *)report {
    self.displayedReport = report;
    [super setLatestReport:report];
}

- (void)requestDetailForSelection:(BAAnalyticsDetailSelection *)selection {
    [super requestDetailForSelection:selection ?: [self overviewSelection]];
}

- (void)startHistoryPreparation {
    if (self.preparingHistory || !self.requestedFamily ||
        self.requestedFamily.availability == BAAnalyticsReportAvailabilityLoading ||
        self.requestedFamily.availability == BAAnalyticsReportAvailabilityUnavailable) return;
    self.preparingHistory = YES;
    BAAnalyticsFamilyReport *family = self.requestedFamily;
    BAAnalyticsReport *report = self.requestedReport;
    BAAnalyticsDetailSelection *selection = BACapacitySelectionUsesCurrentSnapshot(self.capacitySelection) ? nil : self.capacitySelection;
    NSUInteger generation = self.preparationGeneration;
    BACapacityPreparationToken *token = [BACapacityPreparationToken new]; self.preparationToken = token;
    __weak BAAnalyticsCapacityCanvasView *weakSelf = self;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            BACapacityPreparedHistory *prepared = BACapacityPrepare(family, selection, token);
            dispatch_async(dispatch_get_main_queue(), ^{
                BAAnalyticsCapacityCanvasView *view = weakSelf;
                if (!view) return;
                view.preparingHistory = NO;
                view.preparationToken = nil;
                if (prepared && !token.isCancelled && generation == view.preparationGeneration && family == view.requestedFamily && report == view.requestedReport) {
                    view.preparedHistory = prepared;
                    [view adoptDisplayedReport:report];
                    view.capacityObservations = prepared.points;
                    view.displayWidth = -1;
                    [view refreshCapacity];
                } else [view startHistoryPreparation];
            });
        }
    });
}

- (void)refreshCapacity {
    BAAnalyticsFamilyReport *family = [self.incomingReport reportForFamily:BAAnalyticsFamilyCapacity];
    if (self.requestedReport != self.incomingReport) {
        self.preparationToken.cancelled = YES;
        self.requestedReport = self.incomingReport;
        self.requestedFamily = family; self.preparationGeneration++;
        BOOL sameSource = [self.displayedReport.sourceProfileIdentifier isEqualToString:self.incomingReport.sourceProfileIdentifier];
        BOOL retainDisplayed = self.preparedHistory && sameSource && family &&
            family.availability != BAAnalyticsReportAvailabilityUnavailable;
        if (!retainDisplayed) {
            self.preparedHistory = nil; self.capacityObservations = @[];
            self.displayIndices = @[]; self.displayMarkerIndices = @[]; self.boundaryIndices = @[]; self.displayGaps = @[]; self.displayGapRects = @[]; self.displayGapGeometry = CGRectNull; self.displayWidth = -1;
            self.hitRegions = @[];
            [self adoptDisplayedReport:self.incomingReport];
        }
        [self startHistoryPreparation];
    }
    BAAnalyticsObservation *latest = self.capacityObservations.lastObject;
    self.fullCharge = BACapacityFCC(BALiveFiniteNumber([self.latestSnapshot valueForMetricIdentifier:BAAnalyticsMetricFullChargeCapacityMilliampHours]));
    self.designCapacity = BACapacityPositive(BALiveFiniteNumber([self.latestSnapshot valueForMetricIdentifier:BAAnalyticsMetricDesignCapacityMilliampHours]));
    self.capacityTimestamp = self.fullCharge ? self.latestSnapshot.timestamp : nil;
    self.currentRecordIdentifiers = @[];
    self.currentSource = self.fullCharge ? @"metricSnapshot" : @"unavailable";
    if (!self.fullCharge && latest) {
        self.fullCharge = BACapacityFCC(BALiveObservationValue(latest, BAAnalyticsHistoryFullChargeCapacityMilliampHours));
        // Never join a design-only row to a separately timestamped FCC row.
        self.designCapacity = BACapacityPositive(BALiveObservationValue(latest, BAAnalyticsHistoryDesignCapacityMilliampHours));
        self.capacityTimestamp = latest.timestamp;
        self.currentRecordIdentifiers = @[latest.identifier];
        self.currentSource = @"historyObservation";
    }
    if (!self.fullCharge) self.designCapacity = nil;
    NSNumber *frozenFull = BACapacityFCC(BALiveFiniteNumber(self.capacitySelection.context[@"fullChargeMilliampHours"]));
    if (frozenFull) {
        self.fullCharge = frozenFull;
        self.designCapacity = BACapacityPositive(BALiveFiniteNumber(self.capacitySelection.context[@"designCapacityMilliampHours"]));
        NSNumber *time = BALiveFiniteNumber(self.capacitySelection.context[@"observationTimestamp"]);
        self.capacityTimestamp = time ? [NSDate dateWithTimeIntervalSince1970:time.doubleValue] : nil;
        self.currentSource = self.capacitySelection.context[@"source"] ?: @"historyObservation";
        self.currentRecordIdentifiers = self.capacitySelection.recordIdentifiers;
    }
    self.accessibilityLabel = [self capacitySummary];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (NSString *)capacityPrimary {
    if (!self.fullCharge) return _("Unavailable");
    if (self.designCapacity) return [NSString stringWithFormat:@"%@%%", BACapacityNumber(self.fullCharge.doubleValue / self.designCapacity.doubleValue * 100, 1)];
    return BACapacityNumber(self.fullCharge.doubleValue, 0);
}

- (NSString *)capacityHeading {
    if (self.detailBrowsingEnabled)
        return self.designCapacity ? _("Latest maximum capacity") : _("Latest full charge (mAh)");
    return self.designCapacity ? _("Maximum capacity") : _("Full charge (mAh)");
}

- (NSString *)observationWindow {
    BAAnalyticsObservation *first = self.capacityObservations.firstObject;
    BAAnalyticsObservation *last = self.capacityObservations.lastObject;
    return first ? BALiveWindow(first.timestamp, last.timestamp) : _("Window unavailable");
}

- (NSString *)capacitySummary {
    NSString *quantity = self.fullCharge ? [NSString stringWithFormat:_("Full charge %@ mAh"), BACapacityNumber(self.fullCharge.doubleValue, 0)] : _("Full charge unavailable");
    NSString *design = self.designCapacity ? [NSString stringWithFormat:_("Design %@ mAh. Full / design %@"), BACapacityNumber(self.designCapacity.doubleValue, 0), [self capacityPrimary]] : _("Design capacity unknown");
    return [NSString stringWithFormat:_("%@. %@. %@. Capacity readings from %@; %lu valid readings. Sparse point estimates; gaps and configuration changes are not joined. Capacity retention is not a health score."), quantity, design, BALiveAge(self.capacityTimestamp), [self observationWindow], (unsigned long)self.capacityObservations.count];
}

- (BAAnalyticsDetailSelection *)currentSelection {
    NSMutableDictionary *context = [@{@"quantity": @"full-charge/design-capacity", @"source": self.currentSource,
                                     @"ratioAvailable": @(self.designCapacity != nil),
                                     @"interpretation": @"capacity retention, not a health score"} mutableCopy];
    if (self.fullCharge) context[@"fullChargeMilliampHours"] = self.fullCharge;
    if (self.designCapacity) context[@"designCapacityMilliampHours"] = self.designCapacity;
    if (self.capacityTimestamp) context[@"observationTimestamp"] = @(self.capacityTimestamp.timeIntervalSince1970);
    NSArray<NSString *> *metrics = [self.currentSource isEqualToString:@"metricSnapshot"] ?
        @[BAAnalyticsMetricFullChargeCapacityMilliampHours, BAAnalyticsMetricDesignCapacityMilliampHours] :
        @[BAAnalyticsHistoryFullChargeCapacityMilliampHours, BAAnalyticsHistoryDesignCapacityMilliampHours];
    return BALiveSelection(self, @"capacity-ratio", self.currentRecordIdentifiers,
                           metrics,
                           self.capacityTimestamp, self.capacityTimestamp, context);
}

- (BAAnalyticsDetailSelection *)historySelection {
    // Time/field selection preserves the complete history, beyond the shared
    // selection contract's 256 explicit-ID limit.
    return BALiveSelection(self, @"capacity-observations", nil,
                           @[BAAnalyticsHistoryFullChargeCapacityMilliampHours, BAAnalyticsHistoryDesignCapacityMilliampHours, BAAnalyticsHistoryCycleCount],
                           self.capacityObservations.firstObject.timestamp, self.capacityObservations.lastObject.timestamp,
                           @{@"sampleCount": @(self.capacityObservations.count), @"coverageKind": @"sparse-point-observations",
                             @"validatedMetricIdentifiers":@[BAAnalyticsHistoryFullChargeCapacityMilliampHours],
                             @"filters": @{BAAnalyticsHistoryFullChargeCapacityMilliampHours:@{@"minimum":@0, @"maximum":@(DBL_MAX), @"includeMaximum":@YES}},
                             @"configurationPolicy": @"Only equal validated design/source plus trusted FCC intervals can join; gaps and cycle-count resets split. Calibration/replacement identity is unavailable."});
}

- (BAAnalyticsDetailSelection *)overviewSelection {
    NSArray<NSString *> *metrics = @[BAAnalyticsMetricFullChargeCapacityMilliampHours, BAAnalyticsMetricDesignCapacityMilliampHours,
                                    BAAnalyticsHistoryFullChargeCapacityMilliampHours, BAAnalyticsHistoryDesignCapacityMilliampHours,
                                    BAAnalyticsHistoryCycleCount];
    NSMutableDictionary *context = [[self currentSelection].context mutableCopy];
    context[@"sampleCount"] = @(self.capacityObservations.count);
    context[@"summary"] = [self capacitySummary];
    context[@"coverageKind"] = @"sparse-point-observations";
    context[@"validatedMetricIdentifiers"] = @[BAAnalyticsHistoryFullChargeCapacityMilliampHours];
    return BALiveSelection(self, @"overview", nil, metrics,
                          self.capacityObservations.firstObject.timestamp, self.capacityObservations.lastObject.timestamp,
                          context);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL large = BALiveLargeType(self);
    self.historyRangeControl.hidden = !self.detailBrowsingEnabled || large;
    self.historyScrollView.hidden = !self.detailBrowsingEnabled || large;
    self.largeTypeScrollView.hidden = !large;
    self.largeTypeScrollView.frame = self.bounds;
    if (large) {
        CGFloat width = MAX(1, CGRectGetWidth(self.bounds) - 24);
        NSString *text = [NSString stringWithFormat:@"%@\n%@%@\n%@\n%@\n%@",
                          [self capacityHeading], [self capacityPrimary],
                          self.fullCharge && !self.designCapacity ? @" mAh" : @"",
                          [self observationWindow],
                          [NSString stringWithFormat:_("%lu capacity readings"), (unsigned long)self.capacityObservations.count],
                          self.designCapacity ? BALiveAge(self.capacityTimestamp) : _("Design unknown")];
        self.largeTypeLabel.text = text;
        self.largeTypeLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium] maximumPointSize:26];
        self.largeTypeLabel.textColor = UIColor.compatLabelColor;
        CGFloat height = BALiveTextHeight(text, width, self.largeTypeLabel.font);
        self.largeTypeLabel.frame = CGRectMake(12, 10, width, height);
        self.largeTypeScrollView.contentSize = CGSizeMake(CGRectGetWidth(self.bounds), height + 20);
        self.hitRegions = @[[BAAnalyticsCanvasHitRegion regionWithRect:self.bounds
                                                              selection:[self overviewSelection]
                                                     accessibilityLabel:[self capacitySummary]]];
    } else {
        NSMutableArray *regions = [NSMutableArray array];
        [self renderCapacityWithRegions:regions];
        self.hitRegions = regions;
        if (self.detailBrowsingEnabled) {
            self.historyOverviewElement.accessibilityLabel = [self capacitySummary];
            self.historyOverviewElement.accessibilityFrameInContainerSpace = CGRectMake(0, 0, self.bounds.size.width, MAX(0, self.historyPlotRect.origin.y));
            NSMutableArray *elements = [NSMutableArray arrayWithObject:self.historyOverviewElement];
            if (!self.historyRangeControl.hidden) [elements addObject:self.historyRangeControl];
            if (!self.historyScrollView.hidden) [elements addObject:self.historyScrollView];
            self.isAccessibilityElement = NO;
            self.accessibilityElements = elements;
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    [self renderCapacityWithRegions:nil];
}

- (void)renderCapacityWithRegions:(NSMutableArray *)regions {
    if (BALiveLargeType(self)) return;
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    if (width < 40 || height < 40) return;
    BOOL drawing = UIGraphicsGetCurrentContext() != NULL;
    if (!drawing && self.detailBrowsingEnabled) [self prepareHistoryViewport];
    BOOL wide = self.cardSize == BAAnalyticsCardSize2x1 || self.cardSize == BAAnalyticsCardSize2x2;
    BOOL tall = self.cardSize == BAAnalyticsCardSize1x2 || self.cardSize == BAAnalyticsCardSize2x2;
    CGFloat padding = 10, contentWidth = width - 2 * padding;
    UIColor *ink = UIColor.compatLabelColor, *secondary = UIColor.compatSecondaryLabelColor;
    UIColor *capacityColor = UIColor.compatGreenColor;
    UIFont *caption = BALiveFont(11, UIFontWeightRegular), *heading = BALiveFont(11, UIFontWeightMedium);
    UIFont *primary = BALiveFont(self.fullCharge ? (wide ? 30 : 25) : 17, UIFontWeightSemibold);
    CGFloat headingHeight = BALiveTextHeight([self capacityHeading], contentWidth, heading);
    if (drawing) BALiveDrawText([self capacityHeading], CGRectMake(padding, padding, contentWidth, headingHeight), heading, secondary, NSTextAlignmentNatural);
    CGFloat primaryY = padding + headingHeight + 2;
    CGFloat primaryHeight = BALiveTextHeight([self capacityPrimary], contentWidth, primary);
    if (drawing) BALiveDrawText([self capacityPrimary], CGRectMake(padding, primaryY, contentWidth, primaryHeight), primary, ink, NSTextAlignmentNatural);
    CGFloat gaugeY = primaryY + primaryHeight + 4;
    CGFloat gaugeHeight = 8;
    if (self.designCapacity) {
        double scale = MAX(self.designCapacity.doubleValue, self.fullCharge.doubleValue);
        CGFloat designWidth = contentWidth * self.designCapacity.doubleValue / scale;
        CGFloat fullWidth = contentWidth * self.fullCharge.doubleValue / scale;
        if (drawing) {
            [UIColor.secondaryCompatFillColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(padding, gaugeY, designWidth, gaugeHeight) cornerRadius:4] fill];
            [capacityColor setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(padding, gaugeY, fullWidth, gaugeHeight) cornerRadius:4] fill];
            // The reference marker retains design's identity, including FCC > design.
            BALiveLine(CGPointMake(padding + designWidth, gaugeY - 3), CGPointMake(padding + designWidth, gaugeY + gaugeHeight + 3), ink, 1.3, YES);
        }
    } else {
        NSString *unknown = self.fullCharge ? _("Design unknown") : _("No capacity readings");
        gaugeHeight = BALiveTextHeight(unknown, contentWidth, caption);
        if (drawing) BALiveDrawText(unknown, CGRectMake(padding, gaugeY, contentWidth, gaugeHeight), caption, secondary, NSTextAlignmentNatural);
    }
    if (regions && self.detailEnabled) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(padding, padding, contentWidth, gaugeY + gaugeHeight - padding)
                                                               selection:[self currentSelection]
                                                      accessibilityLabel:[self capacitySummary]]];

    NSString *countLabel = self.capacityObservations.count ?
        ((wide || tall) ? [NSString stringWithFormat:_("%lu readings · mAh"), (unsigned long)self.capacityObservations.count] : _("Capacity trend · mAh")) :
        _("No capacity history");
    NSString *windowLabel = [self observationWindow];
    if (self.detailBrowsingEnabled && self.capacityObservations.count) {
        NSTimeInterval wholeSpan = [self.capacityObservations.lastObject.timestamp timeIntervalSinceDate:self.capacityObservations.firstObject.timestamp];
        countLabel = self.historyWindowDuration > 0 && wholeSpan > self.historyWindowDuration ?
            _("mAh · swipe to browse; tap to read") : _("mAh · tap a reading for its value");
        if (self.historyViewportInitialized && self.capacityObservations.count > 1)
            windowLabel = BALiveWindow([NSDate dateWithTimeIntervalSince1970:self.historyWindowStart],
                [NSDate dateWithTimeIntervalSince1970:self.historyWindowStart + self.historyWindowDuration]);
        countLabel = [self selectedHistoryReadingText] ?: countLabel;
    }
    CGFloat countHeight = BALiveTextHeight(countLabel, contentWidth, caption);
    CGFloat windowHeight = BALiveTextHeight(windowLabel, contentWidth, caption);
    CGFloat footerHeight = countHeight + windowHeight + 2;
    CGFloat graphY = gaugeY + gaugeHeight + (tall ? 16 : 7);
    if (self.detailBrowsingEnabled) {
        BOOL showRange = self.capacityObservations.count > 1 &&
            [self.capacityObservations.lastObject.timestamp timeIntervalSinceDate:self.capacityObservations.firstObject.timestamp] > 86400;
        if (!drawing) {
            self.historyRangeControl.hidden = !showRange;
            self.historyRangeControl.frame = CGRectMake(padding, graphY, contentWidth, 30);
        }
        if (showRange) graphY += 38;
    }
    CGFloat graphBottom = height - padding - footerHeight - 4;
    double margin = MAX(1, (self.preparedHistory.maximum - self.preparedHistory.minimum) * .15);
    CGFloat axisWidth = MAX([BACapacityNumber(self.preparedHistory.maximum + margin, 0) sizeWithAttributes:@{NSFontAttributeName:caption}].width,
                            [BACapacityNumber(MAX(0, self.preparedHistory.minimum - margin), 0) sizeWithAttributes:@{NSFontAttributeName:caption}].width) + 7;
    CGFloat leftInset = wide && tall ? axisWidth : 0;
    CGRect graph = CGRectMake(padding + leftInset, graphY, contentWidth - leftInset, MAX(0, graphBottom - graphY));
    if (!drawing && self.detailBrowsingEnabled) [self layoutHistoryScrollerInRect:graph];
    if (CGRectGetHeight(graph) >= 8) [self drawObservationGraph:graph showAxis:wide && tall regions:regions];
    if (drawing) BALiveDrawText(countLabel, CGRectMake(padding, height - padding - footerHeight, contentWidth, countHeight), caption, secondary, NSTextAlignmentNatural);
    if (drawing) BALiveDrawText(windowLabel, CGRectMake(padding, height - padding - windowHeight, contentWidth, windowHeight), caption, secondary, NSTextAlignmentNatural);
    if (regions && self.detailEnabled) [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(padding, height - padding - footerHeight, contentWidth, footerHeight)
                                                               selection:[self historySelection]
                                                      accessibilityLabel:[NSString stringWithFormat:@"%@. %@", countLabel, windowLabel]]];
}

- (void)drawObservationGraph:(CGRect)graph showAxis:(BOOL)showAxis regions:(NSMutableArray *)regions {
    if (CGRectIsEmpty(graph)) return;
    BACapacityPreparedHistory *prepared = self.preparedHistory;
    NSArray<BAAnalyticsObservation *> *points = prepared.points;
    CGContextRef c = UIGraphicsGetCurrentContext();
    if (!points.count) { if (c) BALiveHatch(graph); return; }
    const BACapacitySample *samples = prepared.samples.bytes;
    NSTimeInterval first = samples[0].time, span = samples[points.count - 1].time - first;
    NSRange visibleRange = NSMakeRange(0, points.count);
    if (self.detailBrowsingEnabled && self.historyViewportInitialized && points.count > 1) {
        first = self.historyWindowStart;
        span = self.historyWindowDuration;
        NSUInteger lower = BACapacitySampleBound(prepared, first, NO);
        NSUInteger upper = BACapacitySampleBound(prepared, first + span, YES);
        // Include a neighboring endpoint only so an existing trusted segment
        // can be clipped at the viewport edge. Its original run ID is retained.
        if (lower) lower--;
        if (upper < points.count) upper++;
        visibleRange = NSMakeRange(lower, upper - lower);
    }
    double margin = MAX(1, (prepared.maximum - prepared.minimum) * .15);
    double low = MAX(0, prepared.minimum - margin), high = prepared.maximum + margin;
    CGFloat (^x)(NSTimeInterval) = ^CGFloat(NSTimeInterval time) {
        return span > 0 ? graph.origin.x + (time - first) / span * graph.size.width : CGRectGetMidX(graph);
    };
    CGFloat (^y)(double) = ^CGFloat(double value) { return CGRectGetMaxY(graph) - (value - low) / (high - low) * graph.size.height; };
    // A widget trend has at most 128 vertices, independent of history length
    // or the number of original trusted/untrusted runs. Exact records remain
    // available to its detail selection and all summary statistics.
    NSUInteger columns = MAX(1, MIN(32, (NSUInteger)ceil(graph.size.width / 10)));
    if (self.displayWidth != columns) {
        self.displayWidth = columns;
        self.displayIndices = self.detailBrowsingEnabled ? BACapacityEnvelopeInRange(prepared, visibleRange, first, span, columns) :
            BACapacityEnvelope(prepared, columns);
        NSUInteger markerBudget = MAX(4, MIN(12, (NSUInteger)floor(graph.size.width / 24)));
        self.displayMarkerIndices = BACapacityMarkers(prepared, self.displayIndices, markerBudget);
        NSMutableArray *boundaries = [NSMutableArray array]; NSUInteger lastColumn = NSNotFound;
        for (NSUInteger i = MAX((NSUInteger)1, visibleRange.location); i < NSMaxRange(visibleRange); i++) if (samples[i].boundary) {
            double fraction = span > 0 ? ((samples[i - 1].time + samples[i].time) * .5 - first) / span : .5;
            if (fraction < 0 || fraction > 1) continue;
            NSUInteger column = MIN(columns - 1, (NSUInteger)MAX(0, floor(fraction * columns)));
            if (column != lastColumn) { [boundaries addObject:@(i)]; lastColumn = column; }
        }
        self.boundaryIndices = boundaries;
        const double *gaps = prepared.gaps.bytes;
        NSMutableArray *displayGaps = [NSMutableArray array];
        NSUInteger gapCount = prepared.gaps.length / (2 * sizeof(double)), gapFirst = 0, gapEnd = gapCount;
        while (gapFirst < gapEnd) {
            NSUInteger middle = gapFirst + (gapEnd - gapFirst) / 2;
            if (gaps[2 * middle + 1] <= first) gapFirst = middle + 1;
            else gapEnd = middle;
        }
        for (NSUInteger i = gapFirst; span > 0 && i < gapCount && gaps[2 * i] < first + span; i++) {
            double a = MAX(0, MIN(1, (gaps[2 * i] - first) / span));
            double b = MAX(0, MIN(1, (gaps[2 * i + 1] - first) / span));
            if (b > a) [displayGaps addObject:[NSValue valueWithCGRect:CGRectMake(a, 0, b - a, 1)]];
        }
        self.displayGaps = displayGaps;
        self.displayGapGeometry = CGRectNull;
    }
    if (!CGRectEqualToRect(self.displayGapGeometry, graph)) {
        NSMutableArray *rects = [NSMutableArray arrayWithCapacity:self.displayGaps.count];
        for (NSValue *value in self.displayGaps) {
            CGRect range = value.CGRectValue;
            [rects addObject:[NSValue valueWithCGRect:CGRectMake(graph.origin.x + range.origin.x * graph.size.width,
                graph.origin.y, range.size.width * graph.size.width, graph.size.height)]];
        }
        self.displayGapRects = rects; self.displayGapGeometry = graph;
    }
    if (c) {
        CGContextSaveGState(c); CGContextClipToRect(c, CGRectInset(graph, -4, -4));
        BALiveHatchRegions(graph, self.displayGapRects);
        BALiveLine(CGPointMake(graph.origin.x, CGRectGetMaxY(graph)), CGPointMake(CGRectGetMaxX(graph), CGRectGetMaxY(graph)), UIColor.compatSeparatorColor, .7, NO);
        CGContextSetStrokeColorWithColor(c, UIColor.compatGreenColor.CGColor); CGContextSetLineWidth(c, 1.2);
        NSUInteger previous = NSNotFound;
        for (NSNumber *number in self.displayIndices) {
            NSUInteger index = number.unsignedIntegerValue;
            if (previous != NSNotFound && samples[previous].run == samples[index].run) {
                CGContextAddLineToPoint(c, x(samples[index].time), y(samples[index].value));
            } else CGContextMoveToPoint(c, x(samples[index].time), y(samples[index].value));
            previous = index;
        }
        CGContextStrokePath(c);
        CGContextSetFillColorWithColor(c, UIColor.compatBackgroundColor.CGColor);
        CGMutablePathRef markerPath = CGPathCreateMutable();
        for (NSNumber *number in self.displayMarkerIndices) {
            NSUInteger index = number.unsignedIntegerValue;
            CGFloat markerX = x(samples[index].time);
            CGPathAddEllipseInRect(markerPath, NULL, CGRectMake(markerX - 3, y(samples[index].value) - 3, 6, 6));
        }
        CGContextAddPath(c, markerPath); CGContextDrawPath(c, kCGPathFillStroke); CGPathRelease(markerPath);
        CGContextSetStrokeColorWithColor(c, UIColor.compatSecondaryLabelColor.CGColor);
        CGFloat dash[] = {3, 3}; CGContextSetLineDash(c, 0, dash, 2);
        for (NSNumber *number in self.boundaryIndices) {
            NSUInteger index = number.unsignedIntegerValue; CGFloat bx = x((samples[index - 1].time + samples[index].time) * .5);
            CGContextMoveToPoint(c, bx, graph.origin.y); CGContextAddLineToPoint(c, bx, CGRectGetMaxY(graph));
        }
        CGContextStrokePath(c);
        if (self.detailBrowsingEnabled && self.selectedHistoryIndex < points.count) {
            NSUInteger selected = self.selectedHistoryIndex;
            CGFloat selectedX = x(samples[selected].time), selectedY = y(samples[selected].value);
            CGContextSetLineDash(c, 0, NULL, 0);
            CGContextSetStrokeColorWithColor(c, UIColor.compatLabelColor.CGColor);
            CGContextMoveToPoint(c, selectedX, graph.origin.y); CGContextAddLineToPoint(c, selectedX, CGRectGetMaxY(graph));
            CGContextStrokePath(c);
            CGContextSetFillColorWithColor(c, UIColor.compatLabelColor.CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(selectedX - 3, selectedY - 3, 6, 6));
        }
        CGContextRestoreGState(c);
        if (showAxis) {
            UIFont *font = BALiveFont(11, UIFontWeightRegular);
            CGFloat lineHeight = ceil(font.lineHeight), axisWidth = MAX(0, graph.origin.x - 17);
            BALiveDrawText(BACapacityNumber(high, 0), CGRectMake(10, graph.origin.y, axisWidth, lineHeight), font, UIColor.compatSecondaryLabelColor, NSTextAlignmentRight);
            BALiveDrawText(BACapacityNumber(low, 0), CGRectMake(10, CGRectGetMaxY(graph) - lineHeight, axisWidth, lineHeight), font, UIColor.compatSecondaryLabelColor, NSTextAlignmentRight);
        }
    }
    if (!regions || !self.detailEnabled) return;
    NSArray *metrics = @[BAAnalyticsHistoryFullChargeCapacityMilliampHours, BAAnalyticsHistoryDesignCapacityMilliampHours, BAAnalyticsHistoryCycleCount];
    if (points.count > 192) {
        // A small trend is an overview affordance. Dense six-point-wide slices
        // became overlapping 44-point targets and selected arbitrary time ranges
        // when users tapped the compact card's central canvas.
        if (self.cardSize == BAAnalyticsCardSize1x1 || graph.size.width < 132 || graph.size.height < 44) {
            [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:graph selection:[self overviewSelection]
                accessibilityLabel:[self capacitySummary]]];
            return;
        }
        NSUInteger slices = span > 0 ? MAX(1, MIN(64, (NSUInteger)floor(graph.size.width / 44))) : 1;
        for (NSUInteger slice = 0; slice < slices; slice++) {
            NSDate *start = [NSDate dateWithTimeIntervalSince1970:first + span * slice / slices];
            NSDate *end = [NSDate dateWithTimeIntervalSince1970:first + span * (slice + 1) / slices];
            NSDictionary *context = @{ @"coverageKind":@"sparse-point-observations", @"sampleCount":@(points.count),
                @"validatedMetricIdentifiers":@[BAAnalyticsHistoryFullChargeCapacityMilliampHours],
                @"filters":@{BAAnalyticsHistoryFullChargeCapacityMilliampHours:@{@"minimum":@0, @"maximum":@(DBL_MAX), @"includeMaximum":@YES}},
                @"displayEnvelope":@"first/minimum/maximum/last per screen column; original records retained" };
            BAAnalyticsDetailSelection *selection = BALiveSelection(self, @"capacity-observations", nil, metrics, start, end, context);
            [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(graph.origin.x + graph.size.width * slice / slices, graph.origin.y, graph.size.width / slices, graph.size.height)
                selection:selection accessibilityLabel:[NSString stringWithFormat:@"%@ · %@", _("Full charge (mAh)"), BALiveWindow(start, end)]]];
        }
        return;
    }
    for (NSNumber *number in self.displayIndices) {
        NSUInteger index = number.unsignedIntegerValue; BAAnalyticsObservation *point = points[index];
        BOOL trusted = index && samples[index].run == samples[index - 1].run;
        NSMutableDictionary *context = [@{@"fullChargeMilliampHours":@(samples[index].value), @"pathSegment":@(samples[index].run),
            @"trustedLinkFromPrevious":@(trusted), @"observationTimestamp":@(samples[index].time), @"coverageKind":@"point-estimate"} mutableCopy];
        NSNumber *design = BACapacityPositive(BALiveObservationValue(point, BAAnalyticsHistoryDesignCapacityMilliampHours));
        NSNumber *cycles = BALiveObservationValue(point, BAAnalyticsHistoryCycleCount);
        if (design) context[@"designCapacityMilliampHours"] = design;
        if (cycles) context[@"cycleCount"] = cycles;
        BAAnalyticsDetailSelection *selection = BALiveSelection(self, @"capacity-point", @[point.identifier], metrics, point.timestamp, point.timestamp, context);
        NSString *label = [NSString stringWithFormat:_("Full charge %@ mAh, %@, %@"), BACapacityNumber(samples[index].value, 0),
            [self.pointFormatter stringFromDate:point.timestamp], design ? [NSString stringWithFormat:_("design %@ mAh"), BACapacityNumber(design.doubleValue, 0)] : _("design unknown")];
        [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(x(samples[index].time) - 4, y(samples[index].value) - 4, 8, 8) selection:selection accessibilityLabel:label]];
        if (index && samples[index].boundary) {
            BAAnalyticsObservation *prior = points[index - 1];
            NSNumber *a = BACapacityPositive(BALiveObservationValue(prior, BAAnalyticsHistoryDesignCapacityMilliampHours));
            NSNumber *ac = BALiveObservationValue(prior, BAAnalyticsHistoryCycleCount);
            BOOL sourceChanged = !BACapacitySameField(prior, point, BAAnalyticsHistoryFullChargeCapacityMilliampHours);
            NSDictionary *boundaryContext = @{@"designChanged":@(a && design && ![a isEqualToNumber:design]), @"sourceChanged":@(sourceChanged),
                @"cycleReset":@(ac && cycles && cycles.doubleValue < ac.doubleValue), @"interpretation":@"Observed design/source/cycle-count boundary; cause unknown"};
            BAAnalyticsDetailSelection *boundary = BALiveSelection(self, @"capacity-configuration-boundary", @[prior.identifier, point.identifier], metrics, prior.timestamp, point.timestamp, boundaryContext);
            CGFloat bx = x((samples[index - 1].time + samples[index].time) * .5);
            [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(bx - 2, graph.origin.y, 4, graph.size.height) selection:boundary
                accessibilityLabel:_("Observed design, source or cycle-count boundary; cause unknown")]];
        }
    }
}

@end

@interface BAAnalyticsCapacityCanvasCard : BAAnalyticsCanvasCard
@property (nonatomic, strong) NSHashTable<BAAnalyticsCapacityCanvasView *> *capacityViews;
@end

@interface BACapacityDetailViewController : BAAnalyticsDetailViewController
@end
@implementation BACapacityDetailViewController
- (BOOL)allowsVisualizationInteraction { return YES; }
- (UIView *)makeVisualizationView {
    BAAnalyticsCapacityCanvasView *view = [BAAnalyticsCapacityCanvasView new];
    view.cardSize = BAAnalyticsCardSize2x2; view.familyIdentifier = self.familyReport.family;
    view.detailBrowsingEnabled = YES;
    view.capacitySelection = self.selection;
    view.latestReport = self.report;
    view.latestSnapshot = BACapacitySelectionUsesCurrentSnapshot(self.selection) ? self.snapshot : nil;
    view.detailEnabled = NO;
    [view refreshCapacity];
    return view;
}
- (NSArray<NSDictionary *> *)summaryRows {
    BAAnalyticsObservation *point = BACapacityLastValidObservation(self.selectedObservations);
    BOOL snapshotSelection = [self.selection.context[@"source"] isEqual:@"metricSnapshot"];
    BOOL overview = !self.selection || [self.selection.kind isEqual:@"overview"];
    if (!point && overview) point = BACapacityLastValidObservation(self.familyReport.window.observations);
    NSNumber *full = BACapacityFCC(BALiveFiniteNumber(self.selection.context[@"fullChargeMilliampHours"]));
    NSNumber *design = full ? BACapacityPositive(BALiveFiniteNumber(self.selection.context[@"designCapacityMilliampHours"])) : nil;
    if (!full && (snapshotSelection || overview)) {
        // Read both capacities from one acquisition; a design-only snapshot
        // cannot supply the denominator of a historical FCC observation.
        full = BACapacityFCC(BALiveFiniteNumber([self.snapshot valueForMetricIdentifier:BAAnalyticsMetricFullChargeCapacityMilliampHours]));
        design = full ? BACapacityPositive(BALiveFiniteNumber([self.snapshot valueForMetricIdentifier:BAAnalyticsMetricDesignCapacityMilliampHours])) : nil;
    }
    if (!full && !snapshotSelection) {
        full = BACapacityFCC(BALiveObservationValue(point, BAAnalyticsHistoryFullChargeCapacityMilliampHours));
        design = full ? BACapacityPositive(BALiveObservationValue(point, BAAnalyticsHistoryDesignCapacityMilliampHours)) : nil;
    }
    return @[@{@"title":_("Full charge capacity"), @"value":full ? [NSString stringWithFormat:@"%@ mAh", BACapacityNumber(full.doubleValue, 0)] : _("Unavailable")},
        @{@"title":_("Design capacity"), @"value":design ? [NSString stringWithFormat:@"%@ mAh", BACapacityNumber(design.doubleValue, 0)] : _("Unavailable")},
        @{@"title":_("Full / design"), @"value":full && design.doubleValue > 0 ? [NSString stringWithFormat:@"%@%%", BACapacityNumber(100 * full.doubleValue / design.doubleValue, 1)] : _("Unavailable")}];
}
@end

@implementation BAAnalyticsCapacityCanvasCard
- (BOOL)supportsDetails { return YES; }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    BAAnalyticsReport *report = nil;
    NSNumber *sequence = selection.context[@"reportSequence"];
    for (BAAnalyticsCapacityCanvasView *view in self.capacityViews.allObjects) {
        if (sequence ? view.displayedReport.sequenceNumber == sequence.unsignedLongLongValue : view.cardSize == size) {
            report = view.displayedReport; if (report) break;
        }
    }
    if (!report && (!sequence || self.latestReport.sequenceNumber == sequence.unsignedLongLongValue)) report = self.latestReport;
    // A stale hit target may outlive a frame, but must never query newer evidence.
    if (sequence && !report) return nil;
    BOOL current = BACapacitySelectionUsesCurrentSnapshot(selection);
    BOOL hasFrozenSnapshot = [selection.context[@"source"] isEqual:@"metricSnapshot"] &&
        BACapacityFCC(BALiveFiniteNumber(selection.context[@"fullChargeMilliampHours"])) != nil;
    NSNumber *full = BACapacityFCC(BALiveFiniteNumber([self.latestSnapshot valueForMetricIdentifier:BAAnalyticsMetricFullChargeCapacityMilliampHours]));
    if (current && !hasFrozenSnapshot && full) {
        NSMutableDictionary *context = [selection.context mutableCopy] ?: [NSMutableDictionary dictionary];
        context[@"source"] = @"metricSnapshot";
        context[@"fullChargeMilliampHours"] = full;
        NSNumber *design = BACapacityPositive(BALiveFiniteNumber([self.latestSnapshot valueForMetricIdentifier:BAAnalyticsMetricDesignCapacityMilliampHours]));
        [context removeObjectForKey:@"designCapacityMilliampHours"];
        if (design) context[@"designCapacityMilliampHours"] = design;
        context[@"ratioAvailable"] = @(design != nil);
        context[@"observationTimestamp"] = @(self.latestSnapshot.timestamp.timeIntervalSince1970);
        selection = [BAAnalyticsDetailSelection selectionForFamily:self.familyIdentifier kind:selection.kind ?: @"overview"
            recordIdentifiers:selection.recordIdentifiers
            metricIdentifiers:selection.metricIdentifiers ?: @[BAAnalyticsMetricFullChargeCapacityMilliampHours, BAAnalyticsMetricDesignCapacityMilliampHours]
            startDate:selection.startDate endDate:selection.endDate context:context];
    }
    return [[BACapacityDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier
         report:report snapshot:self.latestSnapshot selection:selection];
}

- (BAAnalyticsCanvasView *)makeCanvasView {
    BAAnalyticsCapacityCanvasView *view = [BAAnalyticsCapacityCanvasView new];
    if (!self.capacityViews) self.capacityViews = [NSHashTable weakObjectsHashTable];
    [self.capacityViews addObject:view];
    return view;
}
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view { [(BAAnalyticsCapacityCanvasView *)view refreshCapacity]; }
@end

id<BAAnalyticsCard> BAAnalyticsCreateCapacityCanvasCard(void) {
    return [[BAAnalyticsCapacityCanvasCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.capacity" displayName:_("Capacity observations")
                                                  familyIdentifier:BAAnalyticsFamilyCapacity supportedSizes:BAAnalyticsCardSizeMaskAll defaultSize:BAAnalyticsCardSize1x1];
}
