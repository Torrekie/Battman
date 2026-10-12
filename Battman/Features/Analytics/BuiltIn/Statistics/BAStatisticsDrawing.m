#import "BAStatisticsDrawing.h"
NSString *BASTime(NSTimeInterval seconds) {
    return seconds >= 3600 ? [NSString stringWithFormat:_("%.1f h"), seconds / 3600] : [NSString stringWithFormat:_("%.1f min"), seconds / 60];
}
NSString *BASWindow(BAAnalyticsHistoryWindow *window) {
    if (!window) return _("History unavailable");
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"M/d HH:mm";
    return [NSString stringWithFormat:@"%@ – %@", [f stringFromDate:window.startDate], [f stringFromDate:window.endDate]];
}
UIFont *BASFont(CGFloat size) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:size]];
}
void BASText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color, NSParagraphStyleAttributeName:style}];
}
void BASFill(CGRect rect, UIColor *color) {
    [color setFill]; [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:3] fill];
}
void BASLine(CGPoint a, CGPoint b, UIColor *color, CGFloat width) {
    UIBezierPath *p = [UIBezierPath bezierPath]; [p moveToPoint:a]; [p addLineToPoint:b];
    p.lineWidth = width; [color setStroke]; [p stroke];
}
void BASHatch(CGRect rect) {
    CGContextRef c = UIGraphicsGetCurrentContext(); CGContextSaveGState(c);
    CGContextClipToRect(c, rect); BASFill(rect, [UIColor tertiaryCompatFillColor]);
    for (CGFloat x = CGRectGetMinX(rect) - rect.size.height; x < CGRectGetMaxX(rect); x += 6)
        BASLine(CGPointMake(x, CGRectGetMaxY(rect)), CGPointMake(x + rect.size.height, CGRectGetMinY(rect)), [UIColor compatSecondaryLabelColor], .6);
    CGContextRestoreGState(c);
}
void BASDot(CGPoint p, UIColor *color, CGFloat radius) {
    [color setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(p.x-radius,p.y-radius,2*radius,2*radius)] fill];
}

@interface BASSelectionButton : UIButton
@property (nonatomic, strong) BAAnalyticsDetailSelection *detailSelection;
@end
@implementation BASSelectionButton
@end

// Drawing consumes an already derived immutable result. No I/O or statistics in layout.
@implementation BASStatisticalView
- (BOOL)isPreparingHistory {
    return self.familyReport && !self.analysis &&
        (self.familyReport.availability == BAAnalyticsReportAvailabilityReady ||
         self.familyReport.availability == BAAnalyticsReportAvailabilityPartial);
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textSizeChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)textSizeChanged:(NSNotification *)note { self.largeTextRows = nil; [self setNeedsLayout]; [self setNeedsDisplay]; }
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous]; [self setNeedsLayout]; [self setNeedsDisplay];
}
- (void)setAnalysis:(NSDictionary *)analysis {
    _analysis = [analysis copy]; self.largeTextRows = nil; self.hitRegions = @[]; [self setNeedsLayout]; [self setNeedsDisplay];
}
- (BOOL)usesLargeText {
    // Preserve readable text by offering a scrollable evidence list at larger sizes.
    return BASFont(12).pointSize > 14;
}
- (BAAnalyticsDetailSelection *)selection:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics {
    NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:item[@"context"] ?: self.analysis[@"context"] ?: @{}];
    context[@"reportSequence"] = @(self.latestReport.sequenceNumber);
    if (self.latestReport.sourceProfileIdentifier) context[@"sourceProfile"] = self.latestReport.sourceProfileIdentifier;
    if (self.familyReport.limitations.count) context[@"limitations"] = [self.familyReport.limitations subarrayWithRange:NSMakeRange(0, MIN(12, self.familyReport.limitations.count))];
    if (item[@"identifier"]) context[@"identifier"] = item[@"identifier"];
    if (item[@"label"]) context[@"selectedBin"] = item[@"label"];
    return [BAAnalyticsDetailSelection selectionForFamily:self.familyIdentifier kind:kind recordIdentifiers:item[@"recordIdentifiers"] ?: (item[@"identifier"] ? @[item[@"identifier"]] : @[]) metricIdentifiers:metrics startDate:item[@"startDate"] ?: self.familyReport.window.startDate endDate:item[@"endDate"] ?: self.familyReport.window.endDate context:BAStatisticsBoundedDetailContext(context)];
}
- (void)addHit:(NSMutableArray *)hits rect:(CGRect)rect kind:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics label:(NSString *)label {
    [hits addObject:[BAAnalyticsCanvasHitRegion regionWithRect:rect selection:[self selection:kind item:item metrics:metrics] accessibilityLabel:label]];
}
- (NSArray<NSDictionary *> *)summaryRows { return @[]; }
- (void)largeTextTapped:(BASSelectionButton *)button {
    if (!self.isEditing) {
        // A report may arrive between the last displayed frame and this action.
        BOOL current = [button.detailSelection.context[@"reportSequence"] unsignedLongLongValue] == self.latestReport.sequenceNumber;
        [self requestDetailForSelection:current ? button.detailSelection : nil];
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL large = [self usesLargeText];
    self.largeTextScroll.hidden = !large;
    if (large) {
        if (!self.largeTextScroll) {
            self.largeTextScroll = [UIScrollView new]; self.largeTextScroll.backgroundColor = UIColor.clearColor;
            [self addSubview:self.largeTextScroll];
        }
        self.largeTextScroll.hidden = NO; self.largeTextScroll.frame = self.bounds;
        if (!self.largeTextRows) {
            for (UIView *child in self.largeTextScroll.subviews.copy) if ([child isKindOfClass:BASSelectionButton.class]) [child removeFromSuperview];
            NSMutableArray *rows = [NSMutableArray array];
            [rows addObject:@{@"text":self.accessibilityLabel ?: self.familyIdentifier, @"kind":@"overview", @"item":@{}}];
            [rows addObjectsFromArray:[self summaryRows]];
            if (rows.count == 1) [rows addObject:@{@"text":_("No validated history"), @"kind":@"coverage", @"item":@{}}];
            self.largeTextRows = rows;
            for (NSDictionary *row in rows) {
                BASSelectionButton *button = [BASSelectionButton buttonWithType:UIButtonTypeSystem];
                button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
                BOOL overview = [row[@"kind"] isEqualToString:@"overview"];
                button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:overview ? 13 : 15] maximumPointSize:overview ? 17 : 24];
                [button setTitleColor:[UIColor compatLabelColor] forState:UIControlStateNormal];
                if (overview) button.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", row[@"text"], BASWindow(self.familyReport.window)];
                button.titleLabel.numberOfLines = 0; button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
                [button setTitle:row[@"text"] forState:UIControlStateNormal];
                button.detailSelection = [self selection:row[@"kind"] item:row[@"item"] metrics:row[@"metrics"] ?: @[]];
                [button addTarget:self action:@selector(largeTextTapped:) forControlEvents:UIControlEventTouchUpInside];
                [self.largeTextScroll addSubview:button];
            }
        }
        CGFloat y = 10, width = MAX(1, self.bounds.size.width - 24);
        for (UIView *child in self.largeTextScroll.subviews) if ([child isKindOfClass:BASSelectionButton.class]) {
            BASSelectionButton *button = (id)child; button.enabled = !self.isEditing;
            CGFloat h = MAX(44, [button.titleLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height + 16);
            button.frame = CGRectMake(12, y, width, h); y += h + 4;
        }
        self.largeTextScroll.contentSize = CGSizeMake(self.bounds.size.width, y + 8);
        self.hitRegions = @[];
        self.isAccessibilityElement = NO; // Expose the scrollable buttons instead of hiding their subtree.
        self.accessibilityElements = nil;
    }
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    if ([self usesLargeText]) return;
    NSMutableArray *hits = [NSMutableArray array];
    if (!self.analysis || self.familyReport.availability == BAAnalyticsReportAvailabilityLoading || self.familyReport.availability == BAAnalyticsReportAvailabilityUnavailable) {
        BOOL loading = !self.familyReport || self.familyReport.availability == BAAnalyticsReportAvailabilityLoading;
        BASHatch(CGRectInset(self.bounds, 12, 40));
        BASText(self.accessibilityLabel ?: self.familyIdentifier, CGRectMake(12,10,self.bounds.size.width-24,30), BASFont(13), [UIColor compatLabelColor], NSTextAlignmentLeft);
        BASText(loading ? _("Loading history…") : _("No validated history"), CGRectMake(12,self.bounds.size.height-38,self.bounds.size.width-24,32), BASFont(12), [UIColor compatSecondaryLabelColor], NSTextAlignmentLeft);
    } else [self drawStatistics:hits];
    self.hitRegions = hits;
}
- (void)drawStatistics:(NSMutableArray *)hits {}
@end

NSString *BASCoverage(NSDictionary *analysis, NSString *validKey, NSString *missingKey) {
    return [NSString stringWithFormat:_("%@ / %@ · %@ missing"), BASTime([analysis[validKey] doubleValue]), BASTime([analysis[@"windowSeconds"] doubleValue]), BASTime([analysis[missingKey] doubleValue])];
}


@interface BASAnalysisCancellation : NSObject
@property (atomic) BOOL cancelled;
@end
@implementation BASAnalysisCancellation
@end

static NSString *BASCalendarSignature(NSCalendar *calendar) {
    return [NSString stringWithFormat:@"%@/%@/%lu/%lu", calendar.calendarIdentifier,
            calendar.timeZone.name, (unsigned long)calendar.firstWeekday,
            (unsigned long)calendar.minimumDaysInFirstWeek];
}

@interface BASStatisticalCard ()
@property (nonatomic, weak) BAAnalyticsReport *requestedReport;
@property (nonatomic, copy) NSString *requestedCalendarSignature;
@property (nonatomic, strong) BASAnalysisCancellation *analysisCancellation;
@property (nonatomic, strong) NSHashTable<BASStatisticalView *> *statisticalViews;
@end

@implementation BASStatisticalCard
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family { return nil; }
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family calendar:(NSCalendar *)calendar {
    return [self deriveAnalysisForFamilyReport:family];
}
- (void)deriveIfNeeded {
    NSAssert(NSThread.isMainThread, @"Statistical analysis requests are main-thread only.");
    NSCalendar *calendar = [NSCalendar.currentCalendar copy];
    NSString *signature = BASCalendarSignature(calendar);
    BAAnalyticsReport *report = self.latestReport;
    if (self.requestedReport != report || ![self.requestedCalendarSignature isEqualToString:signature]) {
        self.requestedReport = report;
        self.requestedCalendarSignature = signature;
        self.analysisCancellation.cancelled = YES;
        self.derivedReport = nil;
        self.calendarSignature = nil;
        // Never attach an earlier report's values or selections to newer evidence.
        self.analysis = nil;
    }
    if (self.derivedReport == report && [self.calendarSignature isEqualToString:signature]) return;
    BAAnalyticsFamilyReport *family = [report reportForFamily:self.familyIdentifier];
    if (!family || family.availability == BAAnalyticsReportAvailabilityLoading || family.availability == BAAnalyticsReportAvailabilityUnavailable) {
        self.derivedReport = report;
        self.calendarSignature = signature;
        self.analysis = nil;
        return;
    }
    // Keep the current report plus one in-flight generation, without retaining a
    // backlog of superseded reports when history or the local calendar changes.
    if (self.analysisCancellation) return;
    BASAnalysisCancellation *cancellation = [BASAnalysisCancellation new];
    self.analysisCancellation = cancellation;
    __weak BASStatisticalCard *weakSelf = self;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            BASStatisticalCard *card = weakSelf;
            NSDictionary *analysis = nil;
            if (card && !cancellation.cancelled)
                analysis = [card deriveAnalysisForFamilyReport:family calendar:calendar];
            dispatch_async(dispatch_get_main_queue(), ^{
                BASStatisticalCard *current = weakSelf;
                if (!current || current.analysisCancellation != cancellation) return;
                current.analysisCancellation = nil;
                NSString *currentSignature = BASCalendarSignature(NSCalendar.currentCalendar);
                if (cancellation.cancelled || current.latestReport != report || ![signature isEqualToString:currentSignature]) {
                    [current deriveIfNeeded];
                    return;
                }
                current.derivedReport = report;
                current.calendarSignature = signature;
                current.analysis = analysis;
                for (BASStatisticalView *view in current.statisticalViews.allObjects)
                    if (view.latestReport == report) [current updateCanvasView:view];
            });
        }
    });
}
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view {
    [self deriveIfNeeded]; BASStatisticalView *statistical=(id)view;
    if (!self.statisticalViews) self.statisticalViews = [NSHashTable weakObjectsHashTable];
    [self.statisticalViews addObject:statistical];
    BAAnalyticsFamilyReport *family = [self.latestReport reportForFamily:self.familyIdentifier];
    BOOL changed = statistical.familyReport != family || statistical.analysis != self.analysis;
    statistical.familyReport=family;
    if (statistical.analysis!=self.analysis) statistical.analysis=self.analysis;
    statistical.detailEnabled = self.supportsDetails && !statistical.isPreparingHistory;
    if (changed) { [statistical setNeedsLayout]; [statistical setNeedsDisplay]; }
}
- (void)analyticsCardDidReceiveMemoryWarning {
    self.analysisCancellation.cancelled = YES;
    self.analysis = nil;
    self.derivedReport = nil;
    self.calendarSignature = nil;
    self.requestedReport = nil;
    self.requestedCalendarSignature = nil;
    [super analyticsCardDidReceiveMemoryWarning];
}
- (BAAnalyticsDetailSelection *)defaultDetailSelection {
    [self deriveIfNeeded];
    BAAnalyticsFamilyReport *family=[self.latestReport reportForFamily:self.familyIdentifier];
    NSMutableDictionary *context=[NSMutableDictionary dictionaryWithDictionary:self.analysis[@"context"] ?: @{}];
    context[@"reportSequence"]=@(self.latestReport.sequenceNumber);
    if (family.limitations.count) context[@"limitations"]=[family.limitations subarrayWithRange:NSMakeRange(0,MIN(12,family.limitations.count))];
    return [BAAnalyticsDetailSelection selectionForFamily:self.familyIdentifier kind:@"overview" recordIdentifiers:nil metricIdentifiers:nil startDate:family.window.startDate endDate:family.window.endDate context:BAStatisticsBoundedDetailContext(context)];
}
@end
