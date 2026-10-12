#import "main.h"
#import "BAAnalyticsLiveDrawing.h"
#include <math.h>

NSNumber *BALiveFiniteNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]) ? value : nil;
}

NSNumber *BALiveObservationValue(BAAnalyticsObservation *observation, NSString *metric) {
    if (!observation.timestampValidated || !observation.fieldMetadata[metric].unitValidated)
        return nil;
    return BALiveFiniteNumber([observation valueForMetricIdentifier:metric]);
}

BAAnalyticsFamilyReport *BALiveFamilyReport(BAAnalyticsCanvasView *view, NSString *family) {
    return [view.latestReport reportForFamily:family];
}

UIFont *BALiveFont(CGFloat size, UIFontWeight weight) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
            scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
}

BOOL BALiveLargeType(UIView *view) {
    return UIContentSizeCategoryIsAccessibilityCategory(view.traitCollection.preferredContentSizeCategory) ||
           BALiveFont(12, UIFontWeightRegular).pointSize > 15.5;
}

CGFloat BALiveTextHeight(NSString *text, CGFloat width, UIFont *font) {
    if (width <= 0 || text.length == 0) return 0;
    return ceil([text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                               attributes:@{NSFontAttributeName:font} context:nil].size.height);
}

void BALiveDrawText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment) {
    if (CGRectIsEmpty(rect)) return;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = alignment;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    [text drawWithRect:rect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
           attributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color,
                        NSParagraphStyleAttributeName:paragraph} context:nil];
}

static NSDateFormatter *BALiveDateFormatter(NSString *template) {
    NSMutableDictionary *thread = NSThread.currentThread.threadDictionary;
    NSMutableDictionary *formats = thread[@"Battman.live.dateFormatters"];
    if (!formats) { formats = [NSMutableDictionary dictionary]; thread[@"Battman.live.dateFormatters"] = formats; }
    NSLocale *locale = NSLocale.currentLocale;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSString *signature = [NSString stringWithFormat:@"%@/%@/%@", locale.localeIdentifier, calendar.calendarIdentifier, calendar.timeZone.name];
    NSDictionary *entry = formats[template];
    if (![entry[@"signature"] isEqual:signature]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = locale; formatter.calendar = calendar; formatter.timeZone = calendar.timeZone;
        [formatter setLocalizedDateFormatFromTemplate:template];
        entry = @{@"signature":signature,@"formatter":formatter}; formats[template] = entry;
    }
    return entry[@"formatter"];
}

NSString *BALiveTime(NSDate *date) {
    if (!date) return _("Time unknown");
    return [BALiveDateFormatter(@"HHmmss") stringFromDate:date];
}

NSString *BALiveWindow(NSDate *start, NSDate *end) {
    if (!start || !end || [end compare:start] == NSOrderedAscending)
        return _("Window unavailable");
    BOOL sameDay = [[NSCalendar currentCalendar] isDate:start inSameDayAsDate:end];
    NSDateFormatter *formatter = BALiveDateFormatter(sameDay ? @"HHmm" : @"MMdd");
    return [NSString stringWithFormat:@"%@–%@", [formatter stringFromDate:start], [formatter stringFromDate:end]];
}

NSString *BALiveAge(NSDate *timestamp) {
    if (!timestamp) return _("Age unknown");
    NSTimeInterval seconds = [[NSDate date] timeIntervalSinceDate:timestamp];
    if (!isfinite(seconds) || seconds < -1) return _("Clock mismatch");
    if (seconds < 60) return [NSString stringWithFormat:_("%.0f s ago"), MAX(0, seconds)];
    if (seconds < 3600) return [NSString stringWithFormat:_("%.0f min ago"), floor(seconds / 60)];
    if (seconds < 86400) return [NSString stringWithFormat:_("%.0f h ago"), floor(seconds / 3600)];
    return [NSString stringWithFormat:_("%.0f d ago"), floor(seconds / 86400)];
}

void BALiveHatch(CGRect rect) {
    if (CGRectIsEmpty(rect)) return;
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextClipToRect(context, rect);
    [[UIColor secondaryCompatFillColor] setFill];
    UIRectFillUsingBlendMode(rect, kCGBlendModeNormal);
    CGContextSetStrokeColorWithColor(context, [UIColor.compatSecondaryLabelColor colorWithAlphaComponent:0.45].CGColor);
    CGContextSetLineWidth(context, 0.65);
    for (CGFloat x = CGRectGetMinX(rect) - CGRectGetHeight(rect); x < CGRectGetMaxX(rect); x += 6) {
        CGContextMoveToPoint(context, x, CGRectGetMaxY(rect));
        CGContextAddLineToPoint(context, x + CGRectGetHeight(rect), CGRectGetMinY(rect));
    }
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

void BALiveHatchRegions(CGRect bounds, NSArray<NSValue *> *rectangles) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context || CGRectIsEmpty(bounds) || !rectangles.count) return;
    CGMutablePathRef mask = CGPathCreateMutable();
    for (NSValue *value in rectangles) {
        CGRect rect = CGRectIntersection(bounds, value.CGRectValue);
        if (!CGRectIsEmpty(rect)) CGPathAddRect(mask, NULL, rect);
    }
    if (!CGPathIsEmpty(mask)) {
        // One union mask and one hatch pass preserve the actual missing-time
        // widths. Repeating a full diagonal stroke set for every narrow gap
        // both wastes work and encourages misleading coarse quantization.
        CGContextSaveGState(context);
        CGContextAddPath(context, mask); CGContextClip(context);
        BALiveHatch(bounds);
        CGContextRestoreGState(context);
    }
    CGPathRelease(mask);
}

void BALiveLine(CGPoint start, CGPoint end, UIColor *color, CGFloat width, BOOL dashed) {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, width);
    CGFloat dash[] = {4, 3};
    if (dashed) CGContextSetLineDash(context, 0, dash, 2);
    CGContextMoveToPoint(context, start.x, start.y);
    CGContextAddLineToPoint(context, end.x, end.y);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

BAAnalyticsDetailSelection *BALiveSelection(BAAnalyticsCanvasView *view, NSString *kind,
        NSArray<NSString *> *records, NSArray<NSString *> *metrics, NSDate *start, NSDate *end, NSDictionary *context) {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:context ?: @{}];
    if (view.latestReport) metadata[@"reportSequence"] = @(view.latestReport.sequenceNumber);
    if (view.latestSnapshot) metadata[@"snapshotSequence"] = @(view.latestSnapshot.sequenceNumber);
    return [BAAnalyticsDetailSelection selectionForFamily:view.familyIdentifier kind:kind
                                       recordIdentifiers:records metricIdentifiers:metrics
                                               startDate:start endDate:end context:metadata];
}

@interface BALiveSummaryScrollView ()
@property (nonatomic, strong) UILabel *summaryLabel;
@end
@implementation BALiveSummaryScrollView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _summaryLabel = [UILabel new];
        _summaryLabel.numberOfLines = 0;
        _summaryLabel.isAccessibilityElement = NO;
        [self addSubview:_summaryLabel];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openOverview:)];
        tap.cancelsTouchesInView = NO;
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)setSummaryText:(NSString *)summaryText {
    _summaryText = [summaryText copy] ?: @"";
    self.summaryLabel.text = _summaryText;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(1, self.bounds.size.width - 24);
    self.summaryLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightMedium] maximumPointSize:26];
    self.summaryLabel.textColor = UIColor.compatLabelColor;
    CGFloat height = BALiveTextHeight(self.summaryText, width, self.summaryLabel.font);
    self.summaryLabel.frame = CGRectMake(12, 12, width, height);
    self.contentSize = CGSizeMake(self.bounds.size.width, height + 24);
}
- (void)openOverview:(UITapGestureRecognizer *)recognizer {
    if (!self.canvas.isEditing && recognizer.state == UIGestureRecognizerStateEnded)
        [self.canvas requestDetailForSelection:nil];
}
@end

UIColor *BALiveBatteryFillColor(NSNumber *soc, BOOL lowPowerMode, BOOL charging) {
    // UIKitCore iOS 12 _UIBatteryView: saver -> isLowBattery -> charging -> fill.
    // Its iPhone low threshold includes exactly 20%; public colors keep traits.
    if (lowPowerMode) return UIColor.compatYellowColor;
    if (soc && soc.doubleValue <= 20) return UIColor.compatRedColor;
    if (charging) return UIColor.compatGreenColor;
    return UIColor.compatLabelColor;
}
