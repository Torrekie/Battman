#import "BAAnalyticsCanvasCard.h"
#import "../../Data/BAAnalyticsHistoryService.h"
#import "ObjCExt/UIColor+compat.h"

dispatch_queue_t BAAnalyticsCanvasPreparationQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.torrekie.battman.analytics.presentation",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    });
    return queue;
}

@interface BAAnalyticsCanvasCard () <BAAnalyticsHistoryServiceSubscriber>
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsReport *latestReport;
@property (nonatomic, strong) NSHashTable<BAAnalyticsCanvasView *> *mountedViews;
@property (nonatomic, strong) NSHashTable<BAAnalyticsCanvasView *> *visibleViews;
@property (nonatomic) BOOL historySubscribed;
- (void)updateView:(BAAnalyticsCanvasView *)view;
@end

@implementation BAAnalyticsCanvasCard
- (instancetype)initWithIdentifier:(NSString *)identifier displayName:(NSString *)displayName
                 familyIdentifier:(NSString *)familyIdentifier supportedSizes:(BAAnalyticsCardSizeMask)supportedSizes
                      defaultSize:(BAAnalyticsCardSize)defaultSize {
    self = [super init];
    if (!self)
        return nil;
    _analyticsCardIdentifier = [identifier copy];
    _analyticsCardDisplayName = [displayName copy];
    _familyIdentifier = [familyIdentifier copy];
    _supportedAnalyticsCardSizes = supportedSizes & BAAnalyticsCardSizeMaskAll;
    if (_supportedAnalyticsCardSizes == 0)
        _supportedAnalyticsCardSizes = BAAnalyticsCardSizeMask1x1;
    _defaultAnalyticsCardSize = BAAnalyticsCardSizeMaskContainsSize(_supportedAnalyticsCardSizes, defaultSize) ?
        defaultSize : BAAnalyticsCardDefaultSizeForMask(_supportedAnalyticsCardSizes);
    _mountedViews = [NSHashTable weakObjectsHashTable];
    _visibleViews = [NSHashTable weakObjectsHashTable];
    _historyService = [BAAnalyticsHistoryService sharedService];
    return self;
}

- (void)dealloc {
    // Registry-owned cards normally release on the main thread. A service's
    // weak subscriber table also safely drops a card released elsewhere.
    if (_historySubscribed && [NSThread isMainThread])
        [self.historyService removeSubscriber:self];
}

- (void)setHistoryService:(BAAnalyticsHistoryService *)historyService {
    NSAssert([NSThread isMainThread], @"History service changes are main-thread only.");
    NSParameterAssert(historyService);
    if (_historyService == historyService) return;
    if (self.historySubscribed) [_historyService removeSubscriber:self];
    _historyService = historyService;
    self.latestReport = nil;
    if (self.historySubscribed) [_historyService addSubscriber:self];
    for (BAAnalyticsCanvasView *view in self.mountedViews.allObjects) [self updateView:view];
}

- (BAAnalyticsCanvasView *)makeCanvasView {
    return [BAAnalyticsCanvasView new];
}

- (UIView *)makeAnalyticsCardContentView {
    NSAssert([NSThread isMainThread], @"Canvas creation is main-thread only.");
    BAAnalyticsCanvasView *view = [self makeCanvasView];
    view.familyIdentifier = self.familyIdentifier;
    view.detailEnabled = self.supportsDetails;
    view.latestSnapshot = self.latestSnapshot;
    view.latestReport = self.latestReport;
    [self.mountedViews addObject:view];
    return view;
}

- (void)configureAnalyticsCardContentView:(UIView *)contentView forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
    NSAssert([NSThread isMainThread], @"Canvas rendering is main-thread only.");
    if (![contentView isKindOfClass:[BAAnalyticsCanvasView class]])
        return;
    BAAnalyticsCanvasView *view = (BAAnalyticsCanvasView *)contentView;
    view.cardSize = BAAnalyticsCardSizeMaskContainsSize(self.supportedAnalyticsCardSizes, size) ? size : self.defaultAnalyticsCardSize;
    view.editing = editing;
    [self updateView:view];
}

- (void)updateView:(BAAnalyticsCanvasView *)view {
    view.familyIdentifier = self.familyIdentifier;
    view.detailEnabled = self.supportsDetails;
    view.latestSnapshot = self.latestSnapshot;
    view.latestReport = self.latestReport;
    [self updateCanvasView:view];
    [view setNeedsLayout];
    [view setNeedsDisplay];
}

- (void)updateCanvasView:(BAAnalyticsCanvasView *)view {
    // Subclasses supply independent visual layouts. This fallback carries
    // availability through accessibility without introducing a text template.
    view.accessibilityLabel = self.analyticsCardDisplayName;
}

- (void)analyticsCardContentView:(UIView *)contentView didReceiveMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
    NSAssert([NSThread isMainThread], @"Live snapshots are main-thread only.");
    self.latestSnapshot = snapshot;
    if ([contentView isKindOfClass:[BAAnalyticsCanvasView class]]) {
        BAAnalyticsCanvasView *view = (id)contentView;
        // Retain the current snapshot for a later frozen detail without rebuilding
        // static historical graphs on every five-second live acquisition.
        view.latestSnapshot = snapshot;
        BOOL historical = [self.familyIdentifier isEqual:BAAnalyticsFamilySession] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyDischarge] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyEvents] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyPath] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyDwell] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyCompare] ||
            [self.familyIdentifier isEqual:BAAnalyticsFamilyRhythm];
        if (!historical)
            [self updateView:view];
    }
}

- (void)analyticsCardContentView:(UIView *)contentView didChangeEditing:(BOOL)editing {
    NSAssert([NSThread isMainThread], @"Canvas editing is main-thread only.");
    if (![contentView isKindOfClass:[BAAnalyticsCanvasView class]])
        return;
    BAAnalyticsCanvasView *view = (BAAnalyticsCanvasView *)contentView;
    view.editing = editing;
    [self updateView:view];
}

- (void)analyticsCardWillDisplayContentView:(UIView *)contentView {
    NSAssert([NSThread isMainThread], @"Canvas lifecycle is main-thread only.");
    if (![contentView isKindOfClass:[BAAnalyticsCanvasView class]])
        return;
    BAAnalyticsCanvasView *view = (BAAnalyticsCanvasView *)contentView;
    [self.visibleViews addObject:view];
    if (!self.historySubscribed) {
        self.historySubscribed = YES;
        [self.historyService addSubscriber:self];
    }
    [self updateView:view];
}

- (void)analyticsCardDidEndDisplayingContentView:(UIView *)contentView {
    NSAssert([NSThread isMainThread], @"Canvas lifecycle is main-thread only.");
    if ([contentView isKindOfClass:[BAAnalyticsCanvasView class]])
        [self.visibleViews removeObject:(BAAnalyticsCanvasView *)contentView];
    if (self.historySubscribed && self.visibleViews.allObjects.count == 0) {
        self.historySubscribed = NO;
        [self.historyService removeSubscriber:self];
    }
}

- (void)analyticsHistoryService:(BAAnalyticsHistoryService *)service didPublishReport:(BAAnalyticsReport *)report {
    (void)service;
    NSAssert([NSThread isMainThread], @"History reports are main-thread only.");
    self.latestReport = report;
    for (BAAnalyticsCanvasView *view in self.visibleViews.allObjects)
        [self updateView:view];
}

- (void)analyticsCardDidReceiveMemoryWarning {
    NSAssert([NSThread isMainThread], @"Canvas memory-pressure handling is main-thread only.");
    self.latestReport = nil;
    self.latestSnapshot = nil;
    for (BAAnalyticsCanvasView *view in self.mountedViews.allObjects)
        [self updateView:view];
}

- (UIColor *)analyticsCardBackgroundColor { return [UIColor compatBackgroundColor]; }

- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size {
    for (BAAnalyticsCanvasView *view in self.visibleViews.allObjects)
        if (view.cardSize == size && view.accessibilityLabel.length > 0)
            return view.accessibilityLabel;
    return self.analyticsCardDisplayName;
}

- (UIViewController *)analyticsCardViewControllerForSize:(BAAnalyticsCardSize)size {
    return [self detailViewControllerForSelection:nil size:size];
}

- (BOOL)supportsDetails { return NO; }

- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    (void)selection; (void)size;
    return nil;
}
@end

void BAAnalyticsDrawGlyph(BAAnalyticsGlyph glyph, CGRect rect, UIColor *color) {
    if (CGRectIsEmpty(rect)) return;
    CGContextRef c = UIGraphicsGetCurrentContext(); if (!c) return;
    CGContextSaveGState(c); CGContextTranslateCTM(c, rect.origin.x, rect.origin.y);
    CGContextScaleCTM(c, rect.size.width / 16, rect.size.height / 16);
    [color setStroke]; [color setFill];
    UIBezierPath *p = [UIBezierPath bezierPath]; p.lineWidth = 1.5; p.lineCapStyle = kCGLineCapRound;
    switch (glyph) {
        case BAAnalyticsGlyphBolt:
            [p moveToPoint:CGPointMake(9, 1)]; [p addLineToPoint:CGPointMake(3, 9)];
            [p addLineToPoint:CGPointMake(7, 9)]; [p addLineToPoint:CGPointMake(6, 15)];
            [p addLineToPoint:CGPointMake(13, 6)]; [p addLineToPoint:CGPointMake(9, 6)]; [p closePath]; [p fill]; break;
        case BAAnalyticsGlyphThermometer:
            p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, 1, 4, 10) cornerRadius:2]; p.lineWidth = 1.5; [p stroke];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4, 9, 8, 6)] fill];
            UIRectFill(CGRectMake(7, 5, 2, 6)); break;
        case BAAnalyticsGlyphClock:
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 14, 14)] stroke];
            [p moveToPoint:CGPointMake(8, 4)]; [p addLineToPoint:CGPointMake(8, 8)]; [p addLineToPoint:CGPointMake(11, 9)]; [p stroke]; break;
        case BAAnalyticsGlyphConnected:
            p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4, 5, 8, 6) cornerRadius:2]; p.lineWidth = 1.5; [p stroke];
            [p moveToPoint:CGPointMake(6, 1)]; [p addLineToPoint:CGPointMake(6, 5)];
            [p moveToPoint:CGPointMake(10, 1)]; [p addLineToPoint:CGPointMake(10, 5)];
            [p moveToPoint:CGPointMake(8, 11)]; [p addLineToPoint:CGPointMake(8, 15)]; [p stroke]; break;
        case BAAnalyticsGlyphCheck:
            [p moveToPoint:CGPointMake(3, 8)]; [p addLineToPoint:CGPointMake(6, 11)]; [p addLineToPoint:CGPointMake(13, 4)]; [p stroke]; break;
        case BAAnalyticsGlyphUnplugged:
            BAAnalyticsDrawGlyph(BAAnalyticsGlyphConnected, CGRectMake(0, 0, 16, 16), color);
            [p moveToPoint:CGPointMake(2, 14)]; [p addLineToPoint:CGPointMake(14, 2)]; [p stroke]; break;
        case BAAnalyticsGlyphPause:
            UIRectFill(CGRectMake(4, 3, 3, 10)); UIRectFill(CGRectMake(9, 3, 3, 10)); break;
    }
    CGContextRestoreGState(c);
}
