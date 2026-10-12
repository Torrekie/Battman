#import "BAAnalyticsCanvasCard.h"
#import "main.h"
#include <float.h>

static CGRect BAAnalyticsCanvasExpandedTarget(CGRect rect, CGRect bounds) {
    CGFloat width = MIN(CGRectGetWidth(bounds), MAX(44.0, CGRectGetWidth(rect)));
    CGFloat height = MIN(CGRectGetHeight(bounds), MAX(44.0, CGRectGetHeight(rect)));
    CGFloat x = MAX(CGRectGetMinX(bounds), MIN(CGRectGetMidX(rect) - width / 2.0, CGRectGetMaxX(bounds) - width));
    CGFloat y = MAX(CGRectGetMinY(bounds), MIN(CGRectGetMidY(rect) - height / 2.0, CGRectGetMaxY(bounds) - height));
    return CGRectMake(x, y, width, height);
}

@interface BAAnalyticsCanvasAccessibilityElement : UIAccessibilityElement
@property (nonatomic, weak) BAAnalyticsCanvasView *canvas;
@property (nonatomic, strong, nullable) BAAnalyticsDetailSelection *selection;
@end

@implementation BAAnalyticsCanvasAccessibilityElement
- (BOOL)accessibilityActivate {
    BAAnalyticsCanvasView *canvas = self.canvas;
    if (!canvas || canvas.isEditing || !canvas.detailEnabled)
        return NO;
    [canvas requestDetailForSelection:self.selection];
    return YES;
}
@end

@interface BAAnalyticsCanvasView ()
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsDetailSelection *selectedDetail;
@property (nonatomic) BOOL accessibilityNeedsRebuild;
@property (nonatomic) CGRect accessibilityBounds;
@property (nonatomic, copy) NSString *accessibilityOverviewLabel;
- (void)rebuildCanvasAccessibility;
@end

@implementation BAAnalyticsCanvasView
- (BOOL)isPreparingHistory { return NO; }
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.familyIdentifier = @"";
    self.hitRegions = @[];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitNone;
    self.accessibilityHint = nil;
    return self;
}

- (void)setDetailEnabled:(BOOL)detailEnabled {
    if (_detailEnabled == detailEnabled) return;
    _detailEnabled = detailEnabled;
    self.accessibilityNeedsRebuild = YES;
    self.accessibilityHint = detailEnabled ? _("View exact readings, times and sources") : nil;
    self.accessibilityTraits = detailEnabled ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
    [self rebuildCanvasAccessibility];
}

- (void)setHitRegions:(NSArray<BAAnalyticsCanvasHitRegion *> *)hitRegions {
    if (_hitRegions == hitRegions) return;
    _hitRegions = [hitRegions copy] ?: @[];
    self.accessibilityNeedsRebuild = YES;
    [self rebuildCanvasAccessibility];
}

- (void)setEditing:(BOOL)editing {
    if (_editing == editing) return;
    _editing = editing;
    self.accessibilityNeedsRebuild = YES;
    if (editing)
        self.selectedDetail = nil;
    [self rebuildCanvasAccessibility];
}

- (void)setCardSize:(BAAnalyticsCardSize)cardSize {
    if (_cardSize == cardSize) return;
    _cardSize = cardSize;
    self.selectedDetail = nil;
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self rebuildCanvasAccessibility];
}

- (void)rebuildCanvasAccessibility {
    NSString *label = self.accessibilityLabel ?: @"";
    if (!self.accessibilityNeedsRebuild && CGRectEqualToRect(self.accessibilityBounds, self.bounds) &&
        [self.accessibilityOverviewLabel isEqualToString:label]) return;
    self.accessibilityNeedsRebuild = NO;
    self.accessibilityBounds = self.bounds;
    self.accessibilityOverviewLabel = label;
    if (self.isEditing || self.hitRegions.count == 0) {
        self.accessibilityElements = nil;
        self.isAccessibilityElement = !self.isEditing;
        return;
    }
    self.isAccessibilityElement = NO;
    NSMutableArray<UIAccessibilityElement *> *elements = [NSMutableArray array];
    BAAnalyticsCanvasAccessibilityElement *overview = [[BAAnalyticsCanvasAccessibilityElement alloc] initWithAccessibilityContainer:self];
    overview.canvas = self;
    overview.accessibilityLabel = self.accessibilityLabel.length > 0 ? self.accessibilityLabel : _("View readings");
    overview.accessibilityHint = self.detailEnabled ? self.accessibilityHint : nil;
    overview.accessibilityTraits = self.detailEnabled ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
    overview.accessibilityFrameInContainerSpace = self.bounds;
    [elements addObject:overview];
    for (BAAnalyticsCanvasHitRegion *region in self.hitRegions) {
        if (![region isKindOfClass:[BAAnalyticsCanvasHitRegion class]] || CGRectIsEmpty(region.rect))
            continue;
        CGRect target = BAAnalyticsCanvasExpandedTarget(region.rect, self.bounds);
        if (CGRectIsNull(target) || CGRectIsEmpty(target))
            continue;
        BAAnalyticsCanvasAccessibilityElement *element = [[BAAnalyticsCanvasAccessibilityElement alloc] initWithAccessibilityContainer:self];
        element.canvas = self;
        element.selection = region.selection;
        element.accessibilityLabel = region.accessibilityLabel;
        element.accessibilityHint = self.detailEnabled ? self.accessibilityHint : nil;
        element.accessibilityTraits = self.detailEnabled ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
        element.accessibilityFrameInContainerSpace = target;
        [elements addObject:element];
    }
    self.accessibilityElements = elements;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)touch;
    (void)event;
    return !self.isEditing && self.detailEnabled;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (self.isEditing || !self.detailEnabled || !touch)
        return;
    CGPoint point = [touch locationInView:self];
    if (!CGRectContainsPoint(self.bounds, point))
        return;
    BAAnalyticsCanvasHitRegion *bestRegion = nil;
    CGFloat bestDistance = CGFLOAT_MAX;
    BOOL bestIsDirect = NO;
    for (BAAnalyticsCanvasHitRegion *region in self.hitRegions) {
        if (![region isKindOfClass:[BAAnalyticsCanvasHitRegion class]] || CGRectIsEmpty(region.rect))
            continue;
        CGRect target = BAAnalyticsCanvasExpandedTarget(region.rect, self.bounds);
        if (!CGRectContainsPoint(target, point))
            continue;
        BOOL direct = CGRectContainsPoint(region.rect, point);
        CGFloat dx = point.x - CGRectGetMidX(region.rect);
        CGFloat dy = point.y - CGRectGetMidY(region.rect);
        CGFloat distance = dx * dx + dy * dy;
        if (!bestRegion || (direct && !bestIsDirect) || (direct == bestIsDirect && distance < bestDistance)) {
            bestRegion = region;
            bestDistance = distance;
            bestIsDirect = direct;
        }
    }
    [self requestDetailForSelection:bestRegion.selection];
}

- (void)requestDetailForSelection:(BAAnalyticsDetailSelection *)selection {
    NSAssert([NSThread isMainThread], @"Canvas interaction is main-thread only.");
    if (self.isEditing || !self.detailEnabled)
        return;
    self.selectedDetail = selection;
    [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

- (BOOL)accessibilityActivate {
    if (self.isEditing || !self.detailEnabled)
        return NO;
    [self requestDetailForSelection:nil];
    return YES;
}
@end
