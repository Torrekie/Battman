#import "main.h"
#import "BAAnalyticsLiveDrawing.h"
#import "../../Data/BAAnalyticsMetricSnapshotInternal.h"
#include <float.h>
#include <math.h>

// The existing SDK exposes validated average battery-side current and power.
// These retain their sign. A connection flag never supplies a direction.
static NSTimeInterval const BALiveShortWindowSeconds = 300;
static NSTimeInterval const BALiveMaximumJoinSeconds = 7.5; // 5-second cadence plus bounded scheduling jitter.

static UIFont *BALiveGraphicFont(CGFloat size, CGFloat maximum, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] maximumPointSize:maximum];
}

static NSString *BALiveDuration(NSTimeInterval seconds) {
    return seconds < 60 ? [NSString stringWithFormat:_("%.0f s"), MAX(0, seconds)] :
                         [NSString stringWithFormat:_("%.0f min %.0f s"), floor(seconds / 60), floor(fmod(seconds, 60))];
}

@interface BALiveTrack : NSObject
@property (nonatomic, copy) NSString *metric;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, copy) NSArray<BAAnalyticsMetricPoint *> *points;
@property (nonatomic) CGRect rect;
@property (nonatomic) double minimum;
@property (nonatomic) double maximum;
@property (nonatomic) BOOL dashed;
@end
@implementation BALiveTrack
@end

@interface BAAnalyticsLiveCanvasView : BAAnalyticsCanvasView
@property (nonatomic, copy) NSArray<BALiveTrack *> *tracks;
@property (nonatomic, strong) NSNumber *soc;
@property (nonatomic, strong) NSNumber *current;
@property (nonatomic, strong) NSNumber *power;
@property (nonatomic, strong) NSNumber *temperature;
@property (nonatomic, copy) NSString *currentMetric;
@property (nonatomic, copy) NSString *powerMetric;
@property (nonatomic) BOOL instantaneousCurrent;
@property (nonatomic) BOOL instantaneousPower;
@property (nonatomic) BOOL lowPowerMode;
@property (nonatomic) BOOL charging;
@property (nonatomic, copy) NSDate *windowStart;
@property (nonatomic, copy) NSDate *windowEnd;
@property (nonatomic) CGRect batteryRect;
@property (nonatomic) CGRect currentRect;
@property (nonatomic) CGRect temperatureRect;
@property (nonatomic) CGRect powerRect;
@property (nonatomic) CGRect powerIdentityRect;
@property (nonatomic) CGRect ageRect;
@property (nonatomic) CGRect windowRect;
@property (nonatomic) BOOL hasGaps;
@property (nonatomic) BOOL compact;
@property (nonatomic) NSUInteger sampleCount;
@property (nonatomic, copy) NSString *windowText;
@property (nonatomic, strong) BALiveSummaryScrollView *largeTypeSummary;
@property (nonatomic, strong) UILabel *socLabel;
- (void)reloadSnapshot;
@end

@implementation BAAnalyticsLiveCanvasView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        _tracks = @[];
        _socLabel = [UILabel new];
        _socLabel.numberOfLines = 1;
        _socLabel.adjustsFontSizeToFitWidth = YES;
        _socLabel.minimumScaleFactor = .5;
        _socLabel.isAccessibilityElement = NO;
        _socLabel.userInteractionEnabled = NO;
        [self addSubview:_socLabel];
        _largeTypeSummary = [BALiveSummaryScrollView new];
        _largeTypeSummary.canvas = self;
        _largeTypeSummary.hidden = YES;
        [self addSubview:_largeTypeSummary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contentSizeChanged:)
                    name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)contentSizeChanged:(NSNotification *)notification { [self setNeedsLayout]; [self setNeedsDisplay]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsLayout]; [self setNeedsDisplay];
}

- (NSArray<BAAnalyticsMetricPoint *> *)shortPointsForMetric:(NSString *)metric {
    NSDate *cutoff = [self.latestSnapshot.timestamp dateByAddingTimeInterval:-BALiveShortWindowSeconds];
    NSMutableArray *points = [NSMutableArray array];
    // Preserve acquisition order. A backwards/duplicate clock starts a new
    // display segment; sorting would erase the evidence of a clock jump.
    for (BAAnalyticsMetricPoint *point in [self.latestSnapshot historyForMetricIdentifier:metric]) {
        if (!isfinite(point.value) || [point.timestamp compare:cutoff] == NSOrderedAscending ||
            [point.timestamp compare:self.latestSnapshot.timestamp] == NSOrderedDescending) continue;
        BAAnalyticsMetricPoint *previous = points.lastObject;
        if (previous && [point.timestamp compare:previous.timestamp] != NSOrderedDescending)
            [points removeAllObjects];
        [points addObject:point];
    }
    return points;
}

- (void)reloadSnapshot {
    BAAnalyticsMetricSnapshot *snapshot = self.latestSnapshot;
    self.soc = BALiveFiniteNumber([snapshot valueForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent]);
    if (self.soc && (self.soc.doubleValue < 0 || self.soc.doubleValue > 100)) self.soc = nil;
    self.lowPowerMode = BAAnalyticsValidatedBooleanMetric([snapshot valueForMetricIdentifier:BAAnalyticsMetricLowPowerMode]).boolValue;
    self.charging = [[snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingState] integerValue] == BAAnalyticsChargingStateCharging;
    self.instantaneousCurrent = NO; // The v1 snapshot names this measured field average current.
    self.instantaneousPower = BALiveFiniteNumber([snapshot valueForMetricIdentifier:@"battery.power.net.watts"]) != nil;
    self.currentMetric = BAAnalyticsMetricAverageCurrentMilliamps;
    // Defined by the data group's internal header; no SDK v1 change here.
    self.powerMetric = self.instantaneousPower ? @"battery.power.net.watts" : BAAnalyticsMetricAveragePowerWatts;
    self.current = BALiveFiniteNumber([snapshot valueForMetricIdentifier:self.currentMetric]);
    self.power = BALiveFiniteNumber([snapshot valueForMetricIdentifier:self.powerMetric]);
    self.temperature = BALiveFiniteNumber([snapshot valueForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius]);
    NSArray *definitions = @[
        @[self.powerMetric, self.instantaneousPower ? _("Battery net") : _("Battery net · avg"), @"W", UIColor.compatBlueColor, @NO],
        @[self.currentMetric, self.instantaneousCurrent ? _("Current") : _("Average current"), @"mA", UIColor.compatBlueColor, @YES],
        @[BAAnalyticsMetricAverageTemperatureCelsius, _("Temperature"), @"°C", UIColor.compatOrangeColor, @NO]
    ];
    NSMutableArray *tracks = [NSMutableArray array];
    NSDate *first = nil;
    NSDate *last = nil;
    NSUInteger count = 0;
    BOOL gaps = NO;
    for (NSArray *definition in definitions) {
        BALiveTrack *track = [BALiveTrack new];
        track.metric = definition[0]; track.label = definition[1]; track.unit = definition[2];
        track.color = definition[3]; track.dashed = [definition[4] boolValue];
        track.points = [self shortPointsForMetric:track.metric];
        double minimum = DBL_MAX, maximum = -DBL_MAX;
        NSDate *previous = nil;
        for (BAAnalyticsMetricPoint *point in track.points) {
            minimum = MIN(minimum, point.value); maximum = MAX(maximum, point.value);
            if (!first || [point.timestamp compare:first] == NSOrderedAscending) first = point.timestamp;
            if (!last || [point.timestamp compare:last] == NSOrderedDescending) last = point.timestamp;
            if (previous && [point.timestamp timeIntervalSinceDate:previous] > BALiveMaximumJoinSeconds) gaps = YES;
            previous = point.timestamp;
        }
        count = MAX(count, track.points.count);
        if (track.points.count == 0) { minimum = 0; maximum = 1; }
        if (![track.unit isEqualToString:@"°C"]) { minimum = MIN(minimum, 0); maximum = MAX(maximum, 0); }
        double padding = MAX((maximum - minimum) * .12, [track.unit isEqualToString:@"mA"] ? 10 : .5);
        track.minimum = minimum - padding; track.maximum = maximum + padding;
        [tracks addObject:track];
    }
    // SOC-only histories still provide an honest actual window when other
    // measured fields are unavailable. They do not become substitute curves.
    NSArray *socPoints = [self shortPointsForMetric:BAAnalyticsMetricStateOfChargePercent];
    NSDate *previousSOC = nil;
    for (BAAnalyticsMetricPoint *point in socPoints) {
        if (!first || [point.timestamp compare:first] == NSOrderedAscending) first = point.timestamp;
        if (!last || [point.timestamp compare:last] == NSOrderedDescending) last = point.timestamp;
        if (previousSOC && [point.timestamp timeIntervalSinceDate:previousSOC] > BALiveMaximumJoinSeconds) gaps = YES;
        previousSOC = point.timestamp;
    }
    count = MAX(count, socPoints.count);
    self.tracks = tracks;
    self.windowStart = first; self.windowEnd = last;
    self.sampleCount = count; self.hasGaps = gaps;
    if (!first) self.windowText = _("Short window unavailable");
    else self.windowText = [NSString stringWithFormat:@"%@ · %@%@", BALiveDuration([last timeIntervalSinceDate:first]),
                           _("foreground"), gaps ? _(" · gaps") : @""];
    self.accessibilityLabel = [NSString stringWithFormat:_("Current battery. Charge %@. %@ %@. %@ %@. Temperature %@. %@. Short window %@; %@. %@"),
        [self socText], self.tracks[1].label, [self currentText], self.tracks[0].label, [self powerText], [self temperatureText], BALiveAge(snapshot.timestamp),
        BALiveWindow(first, last), self.windowText, _("Positive is charge; negative is discharge.")];
    NSMutableArray *sampleCounts = [NSMutableArray array];
    for (BALiveTrack *track in self.tracks)
        [sampleCounts addObject:[NSString stringWithFormat:@"%@ n=%lu", track.label, (unsigned long)track.points.count]];
    self.accessibilityLabel = [self.accessibilityLabel stringByAppendingFormat:@" %@", [sampleCounts componentsJoinedByString:@"; "]];
    [self setNeedsLayout]; [self setNeedsDisplay];
}

- (BOOL)usesLightSOCInk {
    if (!self.soc || self.lowPowerMode || self.charging || self.soc.doubleValue <= 20) return NO;
    CGFloat red=0, green=0, blue=0;
    [UIColor.compatLabelColor getRed:&red green:&green blue:&blue alpha:NULL];
    return red + green + blue < 1.5;
}

- (NSString *)socText { return self.soc ? [NSString stringWithFormat:@"%.0f%%", self.soc.doubleValue] : @"— %"; }
- (NSString *)currentText { return self.current ? [NSString stringWithFormat:@"%+.2f A", self.current.doubleValue / 1000] : @"— A"; }
- (NSString *)powerText { return self.power ? [NSString stringWithFormat:@"%+.1f W", self.power.doubleValue] : @"— W"; }
- (NSString *)temperatureText { return self.temperature ? [NSString stringWithFormat:@"%.1f °C", self.temperature.doubleValue] : @"— °C"; }

- (BAAnalyticsDetailSelection *)currentSelectionForMetrics:(NSArray *)metrics {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *metric in metrics) {
        NSNumber *value = BALiveFiniteNumber([self.latestSnapshot valueForMetricIdentifier:metric]);
        if (value) values[metric] = value;
    }
    return BALiveSelection(self, @"snapshot", nil, metrics, self.latestSnapshot.timestamp, self.latestSnapshot.timestamp,
           @{@"values":values, @"scope":@"foreground metric snapshot", @"signConvention":@"positive charge; negative discharge"});
}

- (CGPoint)point:(BAAnalyticsMetricPoint *)point inTrack:(BALiveTrack *)track {
    NSTimeInterval elapsed = [self.windowEnd timeIntervalSinceDate:self.windowStart];
    CGFloat x = elapsed > 0 ? [point.timestamp timeIntervalSinceDate:self.windowStart] / elapsed : .5;
    CGFloat y = (point.value - track.minimum) / (track.maximum - track.minimum);
    return CGPointMake(CGRectGetMinX(track.rect) + MIN(1, MAX(0, x)) * CGRectGetWidth(track.rect),
                       CGRectGetMaxY(track.rect) - MIN(1, MAX(0, y)) * CGRectGetHeight(track.rect));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.tracks.count < 3) { self.socLabel.hidden = YES; self.hitRegions = @[]; return; }
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat padding = 12, contentWidth = MAX(0, width - padding * 2);
    self.compact = self.cardSize == BAAnalyticsCardSize1x1;
    BOOL large = BALiveLargeType(self);
    self.largeTypeSummary.hidden = !large;
    self.socLabel.hidden = large;
    self.largeTypeSummary.frame = self.bounds;
    if (large) {
        self.largeTypeSummary.summaryText = self.accessibilityLabel;
        self.hitRegions = @[[BAAnalyticsCanvasHitRegion regionWithRect:self.bounds
                       selection:[self currentSelectionForMetrics:@[BAAnalyticsMetricStateOfChargePercent, self.currentMetric, self.powerMetric,
                                                                    BAAnalyticsMetricAverageTemperatureCelsius]]
                       accessibilityLabel:self.accessibilityLabel]];
        [self setNeedsDisplay];
        return;
    }
    BOOL tall = self.cardSize == BAAnalyticsCardSize2x2;
    UIFont *annotation = BALiveGraphicFont(11, 14, UIFontWeightRegular);
    CGFloat annotationHeight = ceil(annotation.lineHeight);
    self.windowRect = CGRectMake(padding, height - padding - annotationHeight * (tall ? 2 : 1), contentWidth,
                                  annotationHeight * (tall ? 2 : 1));
    CGFloat footerTop = CGRectGetMinY(self.windowRect) - 6;
    if (self.compact) {
        CGFloat batteryHeight = MIN(58, MAX(36, height * .37));
        // The localized average and its value need a full row. Keep age above
        // the battery, rather than competing with the current's units.
        CGFloat ageHeight = annotationHeight + 2;
        if (ageHeight > 0) batteryHeight = MAX(32, batteryHeight - ageHeight);
        self.batteryRect = CGRectMake(padding, padding + ageHeight, contentWidth - 4, batteryHeight);
        self.ageRect = CGRectMake(padding, padding, contentWidth, annotationHeight);
        CGFloat lineHeight = ceil(BALiveGraphicFont(13, 17, UIFontWeightMedium).lineHeight);
        self.currentRect = CGRectMake(padding, CGRectGetMaxY(self.batteryRect) + 4, contentWidth, lineHeight);
        self.temperatureRect = CGRectMake(padding, CGRectGetMaxY(self.currentRect) + 1, contentWidth, lineHeight);
        self.powerRect = CGRectZero;
        self.powerIdentityRect = CGRectZero;
        CGFloat graphTop = CGRectGetMaxY(self.temperatureRect) + 4;
        BALiveTrack *track = self.tracks[1];
        track.rect = !large && footerTop - graphTop >= 9 ? CGRectMake(padding, graphTop, contentWidth, footerTop - graphTop) : CGRectZero;
        self.tracks[0].rect = CGRectZero; self.tracks[2].rect = CGRectZero;
    } else {
        CGFloat headerHeight = MIN(90, height * (tall ? .25 : .50));
        CGFloat batteryWidth = MIN(105, contentWidth * .36);
        self.batteryRect = CGRectMake(padding, padding + annotationHeight, batteryWidth - 4, headerHeight - annotationHeight - 8);
        self.ageRect = CGRectMake(padding, padding, batteryWidth, annotationHeight);
        CGFloat rightX = padding + batteryWidth + 12;
        self.powerIdentityRect = CGRectMake(rightX, padding, width - padding - rightX, annotationHeight);
        self.powerRect = CGRectMake(rightX, padding + annotationHeight + 1, width - padding - rightX, 36);
        self.currentRect = CGRectMake(rightX, CGRectGetMaxY(self.powerRect) + 1, width - padding - rightX, 22);
        self.temperatureRect = tall ? CGRectMake(padding, headerHeight + 8, contentWidth, 25) : CGRectZero;
        if (!tall) self.temperatureRect = CGRectMake(padding, CGRectGetMaxY(self.batteryRect) + 3, batteryWidth, annotationHeight + 2);
        CGFloat graphTop = tall ? CGRectGetMaxY(self.temperatureRect) + 22 : MAX(CGRectGetMaxY(self.temperatureRect), CGRectGetMaxY(self.currentRect)) + 8;
        CGFloat available = footerTop - graphTop;
        for (NSUInteger index = 0; index < self.tracks.count; index++) {
            BALiveTrack *track = self.tracks[index];
            if ((!tall && index != 0) || (large && index != 0) || available < 15) track.rect = CGRectZero;
            else {
                NSUInteger rows = large || !tall ? 1 : 3;
                CGFloat rowHeight = (available - (rows - 1) * 24) / rows;
                track.rect = rowHeight >= 12 ? CGRectMake(padding + 26, graphTop + index * (rowHeight + 24), contentWidth - 26, rowHeight) : CGRectZero;
            }
        }
        // A short wide card keeps the latest temperature even when its track
        // is omitted. Separate labels and signs identify the other metrics.

    }
    // Use a single-line native label independent of the battery fill's
    // clipping context. The complete number and % share one contrast color.
    self.socLabel.frame = CGRectInset(self.batteryRect, 7, 2);
    self.socLabel.text = [self socText];
    self.socLabel.font = BALiveGraphicFont(self.compact ? 27 : 30, 36, UIFontWeightSemibold);
    self.socLabel.textColor = self.soc ? ([self usesLightSOCInk] ? UIColor.whiteColor : UIColor.blackColor) : UIColor.compatLabelColor;
    NSMutableArray *regions = [NSMutableArray array];
    NSArray *marks = @[
        @[[NSValue valueWithCGRect:self.batteryRect], @[BAAnalyticsMetricStateOfChargePercent, BAAnalyticsMetricRemainingCapacityMilliampHours], [self socText]],
        @[[NSValue valueWithCGRect:self.currentRect], @[self.currentMetric], [NSString stringWithFormat:@"%@ %@", self.tracks[1].label, [self currentText]]],
        @[[NSValue valueWithCGRect:self.powerRect], @[self.powerMetric], [NSString stringWithFormat:@"%@ %@", self.tracks[0].label, [self powerText]]],
        @[[NSValue valueWithCGRect:self.temperatureRect], @[BAAnalyticsMetricAverageTemperatureCelsius], [NSString stringWithFormat:_("Temperature %@"), [self temperatureText]]]
    ];
    for (NSArray *mark in marks) {
        CGRect rect = [mark[0] CGRectValue];
        if (CGRectIsEmpty(rect)) continue;
        [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:rect
              selection:[self currentSelectionForMetrics:mark[1]] accessibilityLabel:mark[2]]];
    }
    for (BALiveTrack *track in self.tracks) {
        if (CGRectIsEmpty(track.rect)) continue;
        for (BAAnalyticsMetricPoint *point in track.points) {
            CGPoint position = [self point:point inTrack:track];
            NSString *label = [NSString stringWithFormat:@"%@, %.2f %@, %@", track.label, point.value, track.unit, BALiveTime(point.timestamp)];
            BAAnalyticsDetailSelection *selection = BALiveSelection(self, @"metric-point", nil, @[track.metric], point.timestamp, point.timestamp,
                @{@"value":@(point.value), @"unit":track.unit, @"scope":@"foreground short window", @"maximumJoinSeconds":@(BALiveMaximumJoinSeconds)});
            [regions addObject:[BAAnalyticsCanvasHitRegion regionWithRect:CGRectMake(position.x - 3, position.y - 3, 6, 6)
                                                        selection:selection accessibilityLabel:label]];
        }
    }
    self.hitRegions = regions;
    [self setNeedsDisplay];
}

- (void)drawTrack:(BALiveTrack *)track {
    if (CGRectIsEmpty(track.rect)) return;
    if (track.points.count == 0) { BALiveHatch(track.rect); return; }
    NSTimeInterval elapsed = [self.windowEnd timeIntervalSinceDate:self.windowStart];
    CGFloat minX = CGRectGetMinX(track.rect), maxX = CGRectGetMaxX(track.rect);
    BAAnalyticsMetricPoint *first = track.points.firstObject, *last = track.points.lastObject;
    CGFloat firstX = [self point:first inTrack:track].x, lastX = [self point:last inTrack:track].x;
    if (firstX > minX + 1) BALiveHatch(CGRectMake(minX, track.rect.origin.y, firstX - minX, track.rect.size.height));
    if (lastX < maxX - 1) BALiveHatch(CGRectMake(lastX, track.rect.origin.y, maxX - lastX, track.rect.size.height));
    if (track.minimum < 0 && track.maximum > 0) {
        CGFloat zeroY = CGRectGetMaxY(track.rect) - (0 - track.minimum) / (track.maximum - track.minimum) * CGRectGetHeight(track.rect);
        BALiveLine(CGPointMake(minX, zeroY), CGPointMake(maxX, zeroY), UIColor.compatGray4Color, 1, YES);
    }
    BAAnalyticsMetricPoint *previous = nil;
    for (BAAnalyticsMetricPoint *point in track.points) {
        CGPoint position = [self point:point inTrack:track];
        if (previous) {
            CGPoint prior = [self point:previous inTrack:track];
            if ([point.timestamp timeIntervalSinceDate:previous.timestamp] <= BALiveMaximumJoinSeconds)
                BALiveLine(prior, position, track.color, 1.8, track.dashed);
            else if (elapsed > 0)
                BALiveHatch(CGRectMake(prior.x, track.rect.origin.y, position.x - prior.x, track.rect.size.height));
        }
        [track.color setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(position.x - 1.8, position.y - 1.8, 3.6, 3.6)] fill];
        previous = point;
    }
}

- (void)drawRect:(CGRect)rect {
    if (BALiveLargeType(self) || self.tracks.count < 3) return;
    UIColor *muted = UIColor.compatSecondaryLabelColor;
    UIFont *small = BALiveGraphicFont(11, 14, UIFontWeightRegular);
    BOOL lightSOCInk = [self usesLightSOCInk];
    CGFloat emptyShade = lightSOCInk ? .35 : .75;
    [[UIColor colorWithRed:emptyShade green:emptyShade blue:emptyShade alpha:1] setFill];
    UIBezierPath *battery = [UIBezierPath bezierPathWithRoundedRect:self.batteryRect cornerRadius:9];
    [battery fill];
    if (self.soc) {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context); [battery addClip];
        [BALiveBatteryFillColor(self.soc, self.lowPowerMode, self.charging) setFill];
        UIRectFill(CGRectMake(self.batteryRect.origin.x, self.batteryRect.origin.y, self.batteryRect.size.width * self.soc.doubleValue / 100, self.batteryRect.size.height));
        CGContextRestoreGState(context);
    } else BALiveHatch(CGRectInset(self.batteryRect, 3, 3));
    [muted setStroke]; battery.lineWidth = 1; [battery stroke];
    [muted setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMaxX(self.batteryRect) + 1, CGRectGetMidY(self.batteryRect) - 7, 3, 14) cornerRadius:1] fill];
    BALiveDrawText(BALiveAge(self.latestSnapshot.timestamp), self.ageRect, small, muted, NSTextAlignmentRight);
    UIFont *metricFont = BALiveGraphicFont(13, 17, UIFontWeightMedium);
    BALiveDrawText([NSString stringWithFormat:@"%@%@", self.instantaneousCurrent ? @"" : _("avg "), [self currentText]], self.currentRect, metricFont, UIColor.compatBlueColor, NSTextAlignmentRight);
    BAAnalyticsDrawGlyph(BAAnalyticsGlyphThermometer, CGRectMake(self.temperatureRect.origin.x, self.temperatureRect.origin.y + 2, 13, 15), UIColor.compatOrangeColor);
    CGRect temperatureTextRect = self.temperatureRect; temperatureTextRect.origin.x += 17; temperatureTextRect.size.width -= 17;
    BALiveDrawText([self temperatureText], temperatureTextRect, metricFont, UIColor.compatOrangeColor, NSTextAlignmentLeft);
    BALiveDrawText([self powerText], self.powerRect, BALiveGraphicFont(25, 30, UIFontWeightMedium), UIColor.compatBlueColor, NSTextAlignmentRight);
    BAAnalyticsDrawGlyph(BAAnalyticsGlyphBolt, CGRectMake(CGRectGetMaxX(self.powerIdentityRect) - 14, self.powerIdentityRect.origin.y, 13, 14), muted);
    for (BALiveTrack *track in self.tracks) {
        [self drawTrack:track];
        if (!self.compact && !CGRectIsEmpty(track.rect)) {
            BALiveDrawText(track.unit, CGRectMake(12, track.rect.origin.y, 26, 22), small, muted, NSTextAlignmentLeft);
            if (self.cardSize == BAAnalyticsCardSize2x2 && !BALiveLargeType(self))
                BALiveDrawText([NSString stringWithFormat:@"%@ · n=%lu", track.label, (unsigned long)track.points.count], CGRectMake(track.rect.origin.x, track.rect.origin.y - 17, track.rect.size.width, 17), small, muted, NSTextAlignmentLeft);
        }
    }
    NSString *window = self.windowStart ? [NSString stringWithFormat:@"%@%@", BALiveDuration([self.windowEnd timeIntervalSinceDate:self.windowStart]),
                  self.hasGaps ? _(" · gaps") : @""] : _("No short window");
    if (self.compact && !CGRectIsEmpty(self.tracks[1].rect))
        window = [window stringByAppendingFormat:@" · n=%lu", (unsigned long)self.tracks[1].points.count];
    if (!self.compact) {
        if (self.cardSize == BAAnalyticsCardSize2x1)
            window = [window stringByAppendingFormat:@" · n=%lu", (unsigned long)self.tracks[0].points.count];
        window = [NSString stringWithFormat:@"%@ · %@", BALiveWindow(self.windowStart, self.windowEnd), window];
        if (self.cardSize == BAAnalyticsCardSize2x2)
            window = [window stringByAppendingFormat:@"\n%@", _("Foreground · +charge / −discharge")];
    }
    BALiveDrawText(window, self.windowRect, small, muted, NSTextAlignmentLeft);
}
@end

@interface BAAnalyticsLiveCanvasCard : BAAnalyticsCanvasCard
@end
@implementation BAAnalyticsLiveCanvasCard
- (BAAnalyticsCanvasView *)makeCanvasView { return [BAAnalyticsLiveCanvasView new]; }
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view { [(BAAnalyticsLiveCanvasView *)view reloadSnapshot]; }
@end

NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateLiveCanvasCards(void) {
    id<BAAnalyticsCard> live = [[BAAnalyticsLiveCanvasCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.live"
             displayName:_("Current Battery") familyIdentifier:BAAnalyticsFamilyLive
          supportedSizes:BAAnalyticsCardSizeMask1x1 | BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2
             defaultSize:BAAnalyticsCardSize1x1];
    return @[live, BAAnalyticsCreateCapacityCanvasCard(), BAAnalyticsCreateCellsCanvasCard()];
}
