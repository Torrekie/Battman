//
//  AnalyticsCardCell.m
//  Battman — Analytics Host
//

#import "common.h"
#import "AnalyticsCardCell.h"

#import "ObjCExt/CALayer+smoothCorners.h"
#import "ObjCExt/UIColor+compat.h"

static BOOL BAAnalyticsCellIsDarkInterface(void) {
	UITraitCollection *trait = [UIScreen mainScreen].traitCollection;
	if ([trait respondsToSelector:@selector(userInterfaceStyle)])
		return trait.userInterfaceStyle == UIUserInterfaceStyleDark;
	return NO;
}

static UIColor *BAAnalyticsDefaultCardBackgroundColor(void) {
	return BAAnalyticsCellIsDarkInterface() ? UIColorWithRGBA8(28, 28, 30, 255) : UIColorWithRGBA8(242, 242, 247, 255);
}

static UIColor *BAAnalyticsPressedCardBackgroundColor(void) {
	return BAAnalyticsCellIsDarkInterface() ? UIColorWithRGBA8(44, 44, 46, 255) : UIColorWithRGBA8(229, 229, 234, 255);
}

static NSString *const BAAnalyticsCardJiggleRotationAnimationKey = @"BAAnalyticsCardJiggleRotation";
static NSString *const BAAnalyticsCardJiggleTranslationXAnimationKey = @"BAAnalyticsCardJiggleTranslationX";
static NSString *const BAAnalyticsCardJiggleTranslationYAnimationKey = @"BAAnalyticsCardJiggleTranslationY";

static CGFloat BAAnalyticsCardRandomUnit(void) {
	return (CGFloat)arc4random_uniform(10000) / 9999.0;
}

static CGFloat BAAnalyticsCardRandomRange(CGFloat minimum, CGFloat maximum) {
	return minimum + (maximum - minimum) * BAAnalyticsCardRandomUnit();
}

static NSArray<NSNumber *> *BAAnalyticsCardRandomJiggleValues(CGFloat amplitude) {
	CGFloat direction = arc4random_uniform(2) == 0 ? -1.0 : 1.0;
	return @[
		@(direction * amplitude * BAAnalyticsCardRandomRange(0.48, 0.92)),
		@(-direction * amplitude * BAAnalyticsCardRandomRange(0.78, 1.05)),
		@(direction * amplitude * BAAnalyticsCardRandomRange(0.58, 1.00)),
		@(-direction * amplitude * BAAnalyticsCardRandomRange(0.42, 0.88)),
		@(direction * amplitude * BAAnalyticsCardRandomRange(0.30, 0.68)),
	];
}

@interface BAAnalyticsRemoveBadgeView : UIButton {
	UIVisualEffectView *_materialView;
	UIView *_minusView;
}
- (void)updateAppearance;
@end

@implementation BAAnalyticsRemoveBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;

	// iOS 15's SpringBoard close box is a 26-point control whose material
	// background is inset by one point. A system material preserves the same
	// wallpaper/card color pickup without linking Battman to private frameworks.
	UIBlurEffect *blurEffect = nil;
	if (@available(iOS 13.0, *))
		blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
	else
		blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
	_materialView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
	_materialView.userInteractionEnabled = NO;
	_materialView.clipsToBounds = YES;
	[self addSubview:_materialView];

	_minusView = [UIView new];
	_minusView.userInteractionEnabled = NO;
	[self addSubview:_minusView];
	[self updateAppearance];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect materialFrame = CGRectInset(self.bounds, 1.0, 1.0);
	_materialView.frame = materialFrame;
	_materialView.layer.cornerRadius = CGRectGetHeight(materialFrame) / 2.0;
	CGFloat barWidth = 12.0;
	CGFloat barHeight = 2.5;
	_minusView.frame = CGRectMake(CGRectGetMidX(self.bounds) - barWidth / 2.0,
		CGRectGetMidY(self.bounds) - barHeight / 2.0, barWidth, barHeight);
	_minusView.layer.cornerRadius = barHeight / 2.0;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
	(void)event;
	// SpringBoard expands the 26-point close box by nine points on every side,
	// yielding the standard 44-point interactive target.
	return CGRectContainsPoint(CGRectInset(self.bounds, -9.0, -9.0), point);
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	_materialView.alpha = highlighted ? 0.72 : 1.0;
}

- (void)updateAppearance {
	_minusView.backgroundColor = [[UIColor compatLabelColor] colorWithAlphaComponent:0.72];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self updateAppearance];
}

@end

@implementation BAAnalyticsCardCell {
		UIView *_jiggleView;
		UIView *_cardView;
		UIView *_cardContentView;
	NSString *_mountedCardIdentifier;
	id<BAAnalyticsCard> _mountedCard;
	NSLayoutConstraint *_contentTopConstraint;
	NSLayoutConstraint *_contentBottomConstraint;
	NSLayoutConstraint *_contentLeadingConstraint;
	NSLayoutConstraint *_contentTrailingConstraint;
	UIButton *_resizeButton;
	UIButton *_removeButton;
	NSMutableArray<UIButton *> *_actionButtons;
	UIColor *_normalBackgroundColor;
	BOOL _jiggling;
	BOOL _analyticsCardDisplayed;
	BAAnalyticsCardSize _mountedCardSize;
}

@synthesize resizeButton = _resizeButton;
@synthesize removeButton = _removeButton;

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;

	self.contentView.backgroundColor = [UIColor clearColor];
	self.contentView.clipsToBounds = NO;

	_jiggleView = [UIView new];
	_jiggleView.translatesAutoresizingMaskIntoConstraints = NO;
	_jiggleView.backgroundColor = [UIColor clearColor];
	[self.contentView addSubview:_jiggleView];

	_cardView = [UIView new];
	_cardView.translatesAutoresizingMaskIntoConstraints = NO;
	_cardView.backgroundColor = BAAnalyticsDefaultCardBackgroundColor();
	_cardView.layer.cornerRadius = 18.0;
	[_cardView.layer setSmoothCorners:YES];
	_cardView.layer.masksToBounds = YES;
	[_jiggleView addSubview:_cardView];
	_actionButtons = [NSMutableArray array];
	[[NSNotificationCenter defaultCenter] addObserver:self
								 selector:@selector(accessibilityReduceMotionStatusDidChange:)
									 name:UIAccessibilityReduceMotionStatusDidChangeNotification
								   object:nil];

	_resizeButton = [UIButton buttonWithType:UIButtonTypeSystem];
	_resizeButton.translatesAutoresizingMaskIntoConstraints = NO;
	_resizeButton.tintColor = [UIColor compatLabelColor];
	_resizeButton.backgroundColor = [UIColor secondaryCompatFillColor];
	_resizeButton.layer.cornerRadius = 14.0;
	[_resizeButton.layer setSmoothCorners:YES];
	_resizeButton.layer.masksToBounds = YES;
	if (@available(iOS 13.0, *)) {
		UIImage *resizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"];
		[_resizeButton setImage:resizeImage forState:UIControlStateNormal];
	}
	if (!_resizeButton.imageView.image) {
		[_resizeButton.titleLabel setFont:[UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]];
		[_resizeButton setTitle:@"+" forState:UIControlStateNormal];
	}
	[_cardView addSubview:_resizeButton];

	_removeButton = [BAAnalyticsRemoveBadgeView buttonWithType:UIButtonTypeCustom];
	_removeButton.translatesAutoresizingMaskIntoConstraints = NO;
	[_jiggleView addSubview:_removeButton];

	[NSLayoutConstraint activateConstraints:@[
		[_jiggleView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[_jiggleView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		[_jiggleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[_jiggleView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
		[_cardView.topAnchor constraintEqualToAnchor:_jiggleView.topAnchor],
		[_cardView.bottomAnchor constraintEqualToAnchor:_jiggleView.bottomAnchor],
		[_cardView.leadingAnchor constraintEqualToAnchor:_jiggleView.leadingAnchor],
		[_cardView.trailingAnchor constraintEqualToAnchor:_jiggleView.trailingAnchor],
		[_resizeButton.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10.0],
		[_resizeButton.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10.0],
		[_resizeButton.widthAnchor constraintEqualToConstant:32.0],
		[_resizeButton.heightAnchor constraintEqualToConstant:32.0],
		// Match SpringBoard's corner-radius-derived editing-accessory placement.
		// For Battman's 18-point continuous corner this resolves to about 3.4 pt.
		[_removeButton.centerXAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:3.4],
		[_removeButton.centerYAnchor constraintEqualToAnchor:_cardView.topAnchor constant:3.4],
		[_removeButton.widthAnchor constraintEqualToConstant:26.0],
		[_removeButton.heightAnchor constraintEqualToConstant:26.0],
	]];

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray<UIButton *> *)actionButtons {
	return [_actionButtons copy];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
	if ([super pointInside:point withEvent:event])
		return YES;
	if (_removeButton.hidden)
		return NO;
	CGPoint removePoint = [_removeButton convertPoint:point fromView:self];
	return [_removeButton pointInside:removePoint withEvent:event];
}

- (NSString *)mountedCardIdentifier {
	return [_mountedCardIdentifier copy];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self setJiggling:NO];
	[_resizeButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[_removeButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[self removeActionButtons];
	[self unmountCardContentView];
}

- (void)removeActionButtons {
	for (UIButton *button in _actionButtons)
		[button removeFromSuperview];
	[_actionButtons removeAllObjects];
}

- (UIButton *)buttonForAction:(id<BAAnalyticsCardAction>)action index:(NSUInteger)index {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = [UIColor compatBlueColor];
	button.backgroundColor = [UIColor secondaryCompatFillColor];
	button.layer.cornerRadius = 14.0;
	[button.layer setSmoothCorners:YES];
	button.layer.masksToBounds = YES;
	button.tag = (NSInteger)index;

	NSString *title = nil;
	if ([action respondsToSelector:@selector(analyticsCardActionTitle)])
		title = action.analyticsCardActionTitle;

	UIImage *image = nil;
	if ([action respondsToSelector:@selector(analyticsCardActionSystemImageName)] && action.analyticsCardActionSystemImageName.length > 0) {
		if (@available(iOS 13.0, *))
			image = [UIImage systemImageNamed:action.analyticsCardActionSystemImageName];
	}

	if (image) {
		[button setImage:image forState:UIControlStateNormal];
	} else if (title.length > 0) {
		[button setTitle:title forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
	} else if ([action respondsToSelector:@selector(analyticsCardActionFallbackTitle)] && action.analyticsCardActionFallbackTitle.length > 0) {
		[button setTitle:action.analyticsCardActionFallbackTitle forState:UIControlStateNormal];
		button.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
	}
	button.accessibilityLabel = title.length > 0 ? title : action.analyticsCardActionIdentifier;
	return button;
}

- (void)unmountCardContentView {
	[self setAnalyticsCardDisplayed:NO];

	[_contentTopConstraint setActive:NO];
	[_contentBottomConstraint setActive:NO];
	[_contentLeadingConstraint setActive:NO];
	[_contentTrailingConstraint setActive:NO];
	_contentTopConstraint = nil;
	_contentBottomConstraint = nil;
	_contentLeadingConstraint = nil;
	_contentTrailingConstraint = nil;

	[_cardContentView removeFromSuperview];
	_cardContentView = nil;
	_mountedCardIdentifier = nil;
	_mountedCard = nil;
}

- (void)setAnalyticsCardDisplayed:(BOOL)displayed {
	if (_analyticsCardDisplayed == displayed || !_mountedCard || !_cardContentView)
		return;
	_analyticsCardDisplayed = displayed;
	if (displayed) {
		if ([_mountedCard respondsToSelector:@selector(analyticsCardWillDisplayContentView:)])
			[_mountedCard analyticsCardWillDisplayContentView:_cardContentView];
	} else if ([_mountedCard respondsToSelector:@selector(analyticsCardDidEndDisplayingContentView:)]) {
		[_mountedCard analyticsCardDidEndDisplayingContentView:_cardContentView];
	} else if ([_mountedCard respondsToSelector:@selector(analyticsCardWillEndDisplayingContentView:)]) {
		[_mountedCard analyticsCardWillEndDisplayingContentView:_cardContentView];
	}
}

- (void)applyMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	if (!_mountedCard || !_cardContentView || !snapshot)
		return;
	if ([_mountedCard respondsToSelector:@selector(analyticsCardContentView:didReceiveMetricSnapshot:)])
		[_mountedCard analyticsCardContentView:_cardContentView didReceiveMetricSnapshot:snapshot];
	if ([_mountedCard respondsToSelector:@selector(analyticsCardAccessibilityLabelForSize:)])
		self.accessibilityLabel = [_mountedCard analyticsCardAccessibilityLabelForSize:_mountedCardSize];
}

- (void)removeJiggleAnimations {
	[_jiggleView.layer removeAnimationForKey:BAAnalyticsCardJiggleRotationAnimationKey];
	[_jiggleView.layer removeAnimationForKey:BAAnalyticsCardJiggleTranslationXAnimationKey];
	[_jiggleView.layer removeAnimationForKey:BAAnalyticsCardJiggleTranslationYAnimationKey];
}

- (void)updateJiggleAnimations {
	[self removeJiggleAnimations];
	if (!_jiggling || UIAccessibilityIsReduceMotionEnabled())
		return;

	CFTimeInterval beginTime = CACurrentMediaTime();
	CFTimeInterval phaseOffset = BAAnalyticsCardRandomRange(0.0, 0.42);
	CGFloat rotationAmplitude = BAAnalyticsCardRandomRange(0.006, 0.012);
	CGFloat translationXAmplitude = BAAnalyticsCardRandomRange(0.35, 0.90);
	CGFloat translationYAmplitude = BAAnalyticsCardRandomRange(0.25, 0.72);

	CAKeyframeAnimation *rotationAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
	rotationAnimation.values = BAAnalyticsCardRandomJiggleValues(rotationAmplitude);
	rotationAnimation.duration = BAAnalyticsCardRandomRange(0.34, 0.48);
	rotationAnimation.beginTime = beginTime + phaseOffset;
	rotationAnimation.repeatCount = HUGE_VALF;
	rotationAnimation.autoreverses = YES;
	rotationAnimation.calculationMode = kCAAnimationCubic;
	rotationAnimation.removedOnCompletion = NO;
	[_jiggleView.layer addAnimation:rotationAnimation forKey:BAAnalyticsCardJiggleRotationAnimationKey];

	CAKeyframeAnimation *translationXAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
	translationXAnimation.values = BAAnalyticsCardRandomJiggleValues(translationXAmplitude);
	translationXAnimation.duration = BAAnalyticsCardRandomRange(0.42, 0.62);
	translationXAnimation.beginTime = beginTime + BAAnalyticsCardRandomRange(0.0, 0.36);
	translationXAnimation.repeatCount = HUGE_VALF;
	translationXAnimation.autoreverses = YES;
	translationXAnimation.calculationMode = kCAAnimationCubic;
	translationXAnimation.removedOnCompletion = NO;
	[_jiggleView.layer addAnimation:translationXAnimation forKey:BAAnalyticsCardJiggleTranslationXAnimationKey];

	CAKeyframeAnimation *translationYAnimation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
	translationYAnimation.values = BAAnalyticsCardRandomJiggleValues(translationYAmplitude);
	translationYAnimation.duration = BAAnalyticsCardRandomRange(0.46, 0.68);
	translationYAnimation.beginTime = beginTime + BAAnalyticsCardRandomRange(0.0, 0.40);
	translationYAnimation.repeatCount = HUGE_VALF;
	translationYAnimation.autoreverses = YES;
	translationYAnimation.calculationMode = kCAAnimationCubic;
	translationYAnimation.removedOnCompletion = NO;
	[_jiggleView.layer addAnimation:translationYAnimation forKey:BAAnalyticsCardJiggleTranslationYAnimationKey];
}

- (void)setJiggling:(BOOL)jiggling {
	_jiggling = jiggling;
	[self updateJiggleAnimations];
}

- (void)accessibilityReduceMotionStatusDidChange:(NSNotification *)notification {
	(void)notification;
	[self updateJiggleAnimations];
}

- (void)updateRemoveButtonStyle {
	_removeButton.backgroundColor = [UIColor clearColor];
	[_removeButton setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self updateRemoveButtonStyle];
}

- (void)mountContentViewForCard:(id<BAAnalyticsCard>)card {
	_cardContentView = [card makeAnalyticsCardContentView];
	_cardContentView.translatesAutoresizingMaskIntoConstraints = NO;
	[_cardView insertSubview:_cardContentView belowSubview:_resizeButton];

	_contentTopConstraint = [_cardContentView.topAnchor constraintEqualToAnchor:_cardView.topAnchor];
	_contentBottomConstraint = [_cardContentView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor];
	_contentLeadingConstraint = [_cardContentView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor];
	_contentTrailingConstraint = [_cardContentView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor];
	[NSLayoutConstraint activateConstraints:@[
		_contentTopConstraint,
		_contentBottomConstraint,
		_contentLeadingConstraint,
		_contentTrailingConstraint,
	]];

	_mountedCardIdentifier = [card.analyticsCardIdentifier copy];
	_mountedCard = card;
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	_cardView.backgroundColor = highlighted ? BAAnalyticsPressedCardBackgroundColor() : (_normalBackgroundColor ?: BAAnalyticsDefaultCardBackgroundColor());
}

- (void)configureWithCard:(id<BAAnalyticsCard>)card
					 size:(BAAnalyticsCardSize)size
				  editing:(BOOL)editing {
	if (![_mountedCardIdentifier isEqualToString:card.analyticsCardIdentifier]) {
		BOOL shouldRemainDisplayed = _analyticsCardDisplayed;
		[self unmountCardContentView];
		[self mountContentViewForCard:card];
		if (shouldRemainDisplayed)
			[self setAnalyticsCardDisplayed:YES];
	}
	_mountedCardSize = size;

	_normalBackgroundColor = [card respondsToSelector:@selector(analyticsCardBackgroundColor)] ? [card analyticsCardBackgroundColor] : BAAnalyticsDefaultCardBackgroundColor();
	_cardView.backgroundColor = _normalBackgroundColor;
	[self updateRemoveButtonStyle];

	[card configureAnalyticsCardContentView:_cardContentView forSize:size editing:editing];
	if ([card respondsToSelector:@selector(analyticsCardContentView:didChangeEditing:)])
		[card analyticsCardContentView:_cardContentView didChangeEditing:editing];

	BOOL supportsResizing = BAAnalyticsCardOrderedSizesForMask(card.supportedAnalyticsCardSizes).count > 1;
	_resizeButton.hidden = !editing || !supportsResizing;
	_resizeButton.alpha = _resizeButton.hidden ? 0.0 : 1.0;
	_resizeButton.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", _("Manage"), card.analyticsCardIdentifier];
	_removeButton.hidden = !editing;
	_removeButton.alpha = editing ? 1.0 : 0.0;
	_removeButton.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", _("Remove"), card.analyticsCardIdentifier];

	[self removeActionButtons];
	if (!editing && [card respondsToSelector:@selector(analyticsCardActionsForSize:)]) {
		NSArray<id<BAAnalyticsCardAction>> *actions = [card analyticsCardActionsForSize:size];
		NSUInteger actionCount = MIN(actions.count, 3u);
		UIView *previousButton = nil;
		for (NSUInteger index = 0; index < actionCount; index++) {
			UIButton *button = [self buttonForAction:actions[index] index:index];
			[_cardView addSubview:button];
			[_actionButtons addObject:button];
			[NSLayoutConstraint activateConstraints:@[
				[button.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-10.0],
				[button.widthAnchor constraintEqualToConstant:32.0],
				[button.heightAnchor constraintEqualToConstant:32.0],
				previousButton ? [button.trailingAnchor constraintEqualToAnchor:previousButton.leadingAnchor constant:-8.0] : [button.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-10.0],
			]];
			previousButton = button;
		}
	}
		[self setJiggling:editing];

	if ([card respondsToSelector:@selector(analyticsCardAccessibilityLabelForSize:)])
		self.accessibilityLabel = [card analyticsCardAccessibilityLabelForSize:size];
	else
		self.accessibilityLabel = card.analyticsCardIdentifier;
}

@end
