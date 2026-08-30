//
//  BAAnalyticsBuiltInCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "../Data/BAAnalyticsMetricSnapshotInternal.h"

#import "ObjCExt/CALayer+smoothCorners.h"
#import "ObjCExt/UIColor+compat.h"

#include <float.h>

NSString *BAAnalyticsLabeledValue(NSString *label, NSString *value) {
	return [NSString stringWithFormat:@"%@: %@", label ?: @"", value ?: @""];
}

@interface BAAnalyticsCardPresentation ()
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, copy) NSArray<NSString *> *detailLines;
@property (nonatomic, copy) NSArray<BAAnalyticsMetricPoint *> *historyPoints;
@end

@implementation BAAnalyticsCardPresentation

+ (instancetype)presentationWithValue:(NSString *)value
							 caption:(NSString *)caption
						 detailLines:(NSArray<NSString *> *)detailLines
						historyPoints:(NSArray<BAAnalyticsMetricPoint *> *)historyPoints {
	BAAnalyticsCardPresentation *presentation = [BAAnalyticsCardPresentation new];
	presentation.value = value ?: @"";
	presentation.caption = caption ?: @"";
	presentation.detailLines = detailLines ?: @[];
	presentation.historyPoints = historyPoints ?: @[];
	return presentation;
}

@end

@interface BAAnalyticsSparklineView : UIView
@property (nonatomic, strong) UIColor *lineColor;
@property (nonatomic, copy) NSArray<BAAnalyticsMetricPoint *> *points;
@end

@implementation BAAnalyticsSparklineView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.backgroundColor = [UIColor clearColor];
	self.lineColor = [UIColor compatBlueColor];
	self.accessibilityElementsHidden = YES;
	return self;
}

- (void)setPoints:(NSArray<BAAnalyticsMetricPoint *> *)points {
	_points = [points copy] ?: @[];
	[self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
	if (self.points.count < 2 || CGRectGetWidth(self.bounds) <= 1.0 || CGRectGetHeight(self.bounds) <= 1.0)
		return;

	double minimum = DBL_MAX;
	double maximum = -DBL_MAX;
	for (BAAnalyticsMetricPoint *point in self.points) {
		minimum = MIN(minimum, point.value);
		maximum = MAX(maximum, point.value);
	}
	double range = maximum - minimum;
	if (range < DBL_EPSILON) {
		minimum -= 0.5;
		maximum += 0.5;
		range = 1.0;
	}

	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetLineWidth(context, 2.0);
	CGContextSetStrokeColorWithColor(context, self.lineColor.CGColor);
	CGContextSetLineCap(context, kCGLineCapRound);
	CGContextSetLineJoin(context, kCGLineJoinRound);
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat height = CGRectGetHeight(self.bounds);
	for (NSUInteger index = 0; index < self.points.count; index++) {
		BAAnalyticsMetricPoint *point = self.points[index];
		CGFloat x = ((CGFloat)index / (CGFloat)(self.points.count - 1)) * width;
		CGFloat normalizedValue = (CGFloat)((point.value - minimum) / range);
		CGFloat y = (1.0 - normalizedValue) * MAX(0.0, height - 4.0) + 2.0;
		if (index == 0)
			CGContextMoveToPoint(context, x, y);
		else
			CGContextAddLineToPoint(context, x, y);
	}
	CGContextStrokePath(context);
}

@end

static UIFont *BAAnalyticsScaledFont(UIFontTextStyle textStyle, CGFloat size, UIFontWeight weight) {
	UIFont *baseFont = [UIFont systemFontOfSize:size weight:weight];
	if (@available(iOS 11.0, *))
		return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
	return baseFont;
}

@interface BAAnalyticsBuiltInCardContentView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIView *iconContainer;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *fallbackIconLabel;
@property (nonatomic, strong) BAAnalyticsSparklineView *sparklineView;
@property (nonatomic) BOOL hasHeader;
@property (nonatomic) BOOL showsGraph;
@property (nonatomic) BAAnalyticsCardSize cardSize;
@end

@implementation BAAnalyticsBuiltInCardContentView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.backgroundColor = [UIColor clearColor];
	self.isAccessibilityElement = YES;

	_iconContainer = [UIView new];
	_iconContainer.layer.cornerRadius = 11.0;
	[_iconContainer.layer setSmoothCorners:YES];
	_iconContainer.layer.masksToBounds = YES;
	[self addSubview:_iconContainer];
	_iconImageView = [UIImageView new];
	_iconImageView.contentMode = UIViewContentModeScaleAspectFit;
	[_iconContainer addSubview:_iconImageView];
	_fallbackIconLabel = [UILabel new];
	_fallbackIconLabel.textAlignment = NSTextAlignmentCenter;
	_fallbackIconLabel.font = BAAnalyticsScaledFont(UIFontTextStyleHeadline, 16.0, UIFontWeightSemibold);
	[_iconContainer addSubview:_fallbackIconLabel];

	_titleLabel = [UILabel new];
	_titleLabel.font = BAAnalyticsScaledFont(UIFontTextStyleHeadline, 16.0, UIFontWeightSemibold);
	_titleLabel.textColor = [UIColor compatLabelColor];
	_titleLabel.adjustsFontSizeToFitWidth = YES;
	_titleLabel.minimumScaleFactor = 0.75;
	_titleLabel.adjustsFontForContentSizeCategory = YES;
	[self addSubview:_titleLabel];

	_captionLabel = [UILabel new];
	_captionLabel.font = BAAnalyticsScaledFont(UIFontTextStyleCaption1, 12.0, UIFontWeightRegular);
	_captionLabel.textColor = [UIColor compatSecondaryLabelColor];
	_captionLabel.adjustsFontSizeToFitWidth = YES;
	_captionLabel.minimumScaleFactor = 0.72;
	_captionLabel.adjustsFontForContentSizeCategory = YES;
	[self addSubview:_captionLabel];

	_valueLabel = [UILabel new];
	_valueLabel.font = BAAnalyticsScaledFont(UIFontTextStyleTitle1, 31.0, UIFontWeightSemibold);
	_valueLabel.textColor = [UIColor compatLabelColor];
	_valueLabel.adjustsFontSizeToFitWidth = YES;
	_valueLabel.minimumScaleFactor = 0.48;
	_valueLabel.adjustsFontForContentSizeCategory = YES;
	[self addSubview:_valueLabel];

	_detailLabel = [UILabel new];
	_detailLabel.font = BAAnalyticsScaledFont(UIFontTextStyleFootnote, 13.0, UIFontWeightRegular);
	_detailLabel.textColor = [UIColor compatSecondaryLabelColor];
	_detailLabel.numberOfLines = 0;
	_detailLabel.adjustsFontForContentSizeCategory = YES;
	[self addSubview:_detailLabel];

	_sparklineView = [BAAnalyticsSparklineView new];
	[self addSubview:_sparklineView];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat padding = 14.0;
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat height = CGRectGetHeight(self.bounds);
	CGSize span = BAAnalyticsCardGridSpan(self.cardSize);
	BOOL compact = span.width < 2.0 && span.height < 2.0;
	BOOL horizontal = span.width >= 2.0 && span.height <= 1.0;
	CGFloat contentX = padding;
	CGFloat contentY = padding;
	CGFloat contentWidth = MAX(0.0, width - padding * 2.0);
	BOOL canDrawGraph = self.showsGraph && self.sparklineView.points.count >= 2 && !compact;
	CGFloat graphWidth = horizontal && canDrawGraph ? floor(contentWidth * 0.42) : contentWidth;
	CGFloat textWidth = horizontal && canDrawGraph ? MAX(0.0, contentWidth - graphWidth - 12.0) : contentWidth;
	BOOL rightToLeft = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
	CGFloat textX = contentX;
	CGFloat horizontalGraphX = contentX + textWidth + 12.0;
	if (horizontal && canDrawGraph && rightToLeft) {
		horizontalGraphX = contentX;
		textX = contentX + graphWidth + 12.0;
	}

	self.iconContainer.hidden = !self.hasHeader || (self.iconImageView.hidden && self.fallbackIconLabel.hidden);
	self.titleLabel.hidden = !self.hasHeader || self.titleLabel.text.length == 0;
	if (self.hasHeader) {
		CGFloat iconSize = self.iconContainer.hidden ? 0.0 : 34.0;
		CGFloat iconX = rightToLeft ? textX + textWidth - iconSize : textX;
		self.iconContainer.frame = CGRectMake(iconX, contentY, iconSize, iconSize);
		self.iconImageView.frame = CGRectInset(self.iconContainer.bounds, 7.0, 7.0);
		self.fallbackIconLabel.frame = self.iconContainer.bounds;
		CGFloat titleWidth = MAX(0.0, textWidth - (iconSize > 0.0 ? iconSize + 10.0 : 0.0));
		CGFloat titleX = rightToLeft ? textX : textX + (iconSize > 0.0 ? iconSize + 10.0 : 0.0);
		self.titleLabel.frame = CGRectMake(titleX, contentY, titleWidth, 22.0);
		self.captionLabel.frame = CGRectMake(titleX, contentY + 22.0, titleWidth, 18.0);
		contentY += 50.0;
	} else {
		self.iconContainer.frame = CGRectZero;
		self.titleLabel.frame = CGRectZero;
	}

	CGFloat valueHeight = compact ? 39.0 : 45.0;
	self.valueLabel.frame = CGRectMake(textX, contentY, textWidth, valueHeight);
	contentY += valueHeight + 5.0;
	self.captionLabel.hidden = self.captionLabel.text.length == 0 || (self.hasHeader && compact);
	if (!self.hasHeader && !self.captionLabel.hidden) {
		self.captionLabel.frame = CGRectMake(textX, contentY, textWidth, 18.0);
		contentY += 22.0;
	}

	BOOL showDetail = !compact && self.detailLabel.text.length > 0;
	self.detailLabel.hidden = !showDetail;
	self.detailLabel.frame = showDetail ? CGRectMake(textX, contentY, textWidth, MAX(0.0, height - contentY - padding)) : CGRectZero;
	self.sparklineView.hidden = !canDrawGraph;
	if (canDrawGraph) {
		if (horizontal)
			self.sparklineView.frame = CGRectMake(horizontalGraphX, padding + 12.0, graphWidth, MAX(40.0, height - padding * 2.0 - 24.0));
		else
			self.sparklineView.frame = CGRectMake(contentX, MAX(contentY + 8.0, height - 62.0), contentWidth, 46.0);
	} else {
		self.sparklineView.frame = CGRectZero;
	}
}

@end

@interface BAAnalyticsBuiltInCard ()
@property (nonatomic, copy) NSString *analyticsCardIdentifier;
@property (nonatomic, copy) NSString *analyticsCardDisplayName;
@property (nonatomic, copy, nullable) NSString *cardTitle;
@property (nonatomic, copy) NSString *defaultCaption;
@property (nonatomic, copy, nullable) NSString *symbolName;
@property (nonatomic, copy, nullable) NSString *fallbackGlyph;
@property (nonatomic, strong) UIColor *tintColor;
@property (nonatomic) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic) BAAnalyticsCardSize defaultAnalyticsCardSize;
@property (nonatomic) BOOL showsGraph;
@property (nonatomic, strong, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@end

@implementation BAAnalyticsBuiltInCard

- (instancetype)initWithIdentifier:(NSString *)identifier
						 displayName:(NSString *)displayName
						   cardTitle:(NSString *)cardTitle
					 defaultCaption:(NSString *)defaultCaption
						  symbolName:(NSString *)symbolName
					 fallbackGlyph:(NSString *)fallbackGlyph
						   tintColor:(UIColor *)tintColor
					 supportedSizes:(BAAnalyticsCardSizeMask)supportedSizes
						 defaultSize:(BAAnalyticsCardSize)defaultSize
						  showsGraph:(BOOL)showsGraph {
	self = [super init];
	if (!self)
		return nil;
	_analyticsCardIdentifier = [identifier copy];
	_analyticsCardDisplayName = [displayName copy];
	_cardTitle = [cardTitle copy];
	_defaultCaption = [defaultCaption copy];
	_symbolName = [symbolName copy];
	_fallbackGlyph = [fallbackGlyph copy];
	_tintColor = tintColor ?: [UIColor compatBlueColor];
	_supportedAnalyticsCardSizes = supportedSizes ?: BAAnalyticsCardSizeMask1x1;
	_defaultAnalyticsCardSize = BAAnalyticsCardSizeMaskContainsSize(_supportedAnalyticsCardSizes, defaultSize) ? defaultSize : BAAnalyticsCardDefaultSizeForMask(_supportedAnalyticsCardSizes);
	_showsGraph = showsGraph;
	return self;
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	return [BAAnalyticsCardPresentation presentationWithValue:_("Unavailable")
													 caption:self.defaultCaption
											   detailLines:nil
											  historyPoints:nil];
}

- (UIView *)makeAnalyticsCardContentView {
	return [BAAnalyticsBuiltInCardContentView new];
}

- (void)applyPresentationToContentView:(BAAnalyticsBuiltInCardContentView *)view {
	BAAnalyticsCardPresentation *presentation = [self presentationForSnapshot:self.latestSnapshot];
	view.showsGraph = self.showsGraph;
	view.titleLabel.text = self.cardTitle;
	view.captionLabel.text = presentation.caption;
	view.valueLabel.text = presentation.value;
	view.detailLabel.text = [presentation.detailLines componentsJoinedByString:@"\n"];
	view.sparklineView.lineColor = self.tintColor;
	view.sparklineView.points = presentation.historyPoints;
	view.iconContainer.backgroundColor = [self.tintColor colorWithAlphaComponent:0.18];
	view.iconImageView.tintColor = self.tintColor;
	view.fallbackIconLabel.textColor = self.tintColor;
	UIImage *image = nil;
	if (self.symbolName.length > 0) {
		if (@available(iOS 13.0, *))
			image = [UIImage systemImageNamed:self.symbolName];
	}
	view.iconImageView.image = image;
	view.iconImageView.hidden = image == nil;
	view.fallbackIconLabel.text = self.fallbackGlyph;
	view.fallbackIconLabel.hidden = image != nil || self.fallbackGlyph.length == 0;
	view.hasHeader = self.cardTitle.length > 0 || image != nil || self.fallbackGlyph.length > 0;
	NSMutableArray<NSString *> *accessibilityParts = [NSMutableArray arrayWithObjects:self.analyticsCardDisplayName, presentation.value, nil];
	[accessibilityParts addObjectsFromArray:presentation.detailLines];
	view.accessibilityLabel = [accessibilityParts componentsJoinedByString:@", "];
	[view setNeedsLayout];
}

- (void)configureAnalyticsCardContentView:(UIView *)contentView forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	BAAnalyticsBuiltInCardContentView *view = (BAAnalyticsBuiltInCardContentView *)contentView;
	view.cardSize = size;
	[self applyPresentationToContentView:view];
}

- (void)analyticsCardContentView:(UIView *)contentView didReceiveMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	self.latestSnapshot = snapshot;
	[self applyPresentationToContentView:(BAAnalyticsBuiltInCardContentView *)contentView];
}

- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size {
	BAAnalyticsCardPresentation *presentation = [self presentationForSnapshot:self.latestSnapshot];
	return [NSString stringWithFormat:@"%@, %@", self.analyticsCardDisplayName, presentation.value];
}

- (void)analyticsCardDidReceiveMemoryWarning {
	if (!self.latestSnapshot)
		return;
	self.latestSnapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:self.latestSnapshot.sequenceNumber
														 timestamp:self.latestSnapshot.timestamp
															values:self.latestSnapshot.values
														 histories:@{}];
}

- (NSUInteger)analyticsCardRestorationSchemaVersion {
	return 1;
}

- (NSDictionary *)analyticsCardRestorationState {
	return @{};
}

- (NSDictionary *)analyticsCardMigrateRestorationState:(NSDictionary *)restorationState fromSchemaVersion:(NSUInteger)schemaVersion {
	return schemaVersion <= 1 && [restorationState isKindOfClass:[NSDictionary class]] ? restorationState : nil;
}

- (void)analyticsCardRestoreState:(NSDictionary *)restorationState {
	(void)restorationState;
}

@end
