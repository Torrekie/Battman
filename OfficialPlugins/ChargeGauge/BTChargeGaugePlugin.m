//
//  BTChargeGaugePlugin.m
//  Battman official Charge Gauge plug-in
//
//  This implementation imports only the public Battman SDK and Apple system
//  frameworks. It owns its complete UIView/CALayer content tree and receives
//  immutable host snapshots; it never polls battery hardware itself.
//

#import <BAAnalyticsCard.h>
#import <QuartzCore/QuartzCore.h>

#import "BTChargeGaugePlugin.h"

#include <math.h>

#ifndef BT_CHARGE_GAUGE_PLUGIN_VERSION
#define BT_CHARGE_GAUGE_PLUGIN_VERSION "1"
#endif

static NSString * const BTChargeGaugePluginIdentifier =
	@"com.torrekie.battman.plugin.charge-gauge";
static NSString * const BTChargeGaugeCardIdentifier =
	@"com.torrekie.battman.plugin.charge-gauge.card";

static CGFloat BTChargeGaugeVisualCenterOffset(CGRect bounds) {
	CGRect gaugeBounds = CGRectInset(bounds, 12.0, 12.0);
	CGFloat diameter = MIN(CGRectGetWidth(gaugeBounds), CGRectGetHeight(gaugeBounds));
	if (diameter <= 0.0)
		return 0.0;
	CGFloat lineWidth = MAX(8.0, MIN(18.0, diameter * 0.11));
	CGFloat radius = MAX(0.0, diameter * 0.5 - lineWidth * 0.5);
	// A 270-degree gauge reaches one radius above center but only sqrt(1/2)
	// radii below it. Compensate for that asymmetric visible bounding box.
	return radius * (1.0 - 0.7071067811865475) * 0.5;
}

@interface BTChargeGaugeResourceAnchor : NSObject
@end

@implementation BTChargeGaugeResourceAnchor
@end

static NSString *BTChargeGaugeLocalizedString(NSString *key) {
	NSBundle *bundle = [NSBundle bundleForClass:[BTChargeGaugeResourceAnchor class]];
	return [bundle localizedStringForKey:key value:key table:nil];
}

@interface BTChargeGaugeLayer : CALayer
@property (nonatomic) CGFloat chargeFraction;
@property (nonatomic, getter=isValueAvailable) BOOL valueAvailable;
@property (nonatomic) BAAnalyticsChargingState chargingState;
@property (nonatomic, strong) UIColor *trackColor;
@property (nonatomic, strong) UIColor *chargeColor;
@property (nonatomic, strong) UIColor *pausedColor;
@property (nonatomic, strong) UIColor *lowChargeColor;
@property (nonatomic, strong) UIColor *markerColor;
@end

@implementation BTChargeGaugeLayer

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	self.needsDisplayOnBoundsChange = YES;
	self.contentsScale = [UIScreen mainScreen].scale;
	_chargeFraction = 0.0;
	_valueAvailable = NO;
	_chargingState = BAAnalyticsChargingStateUnavailable;
	_trackColor = [UIColor colorWithWhite:0.0 alpha:0.14];
	_chargeColor = [UIColor colorWithRed:0.20 green:0.82 blue:0.45 alpha:1.0];
	_pausedColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.22 alpha:1.0];
	_lowChargeColor = [UIColor colorWithRed:1.0 green:0.29 blue:0.30 alpha:1.0];
	_markerColor = [UIColor whiteColor];
	return self;
}

- (instancetype)initWithLayer:(id)layer {
	self = [super initWithLayer:layer];
	if (!self)
		return nil;
	if ([layer isKindOfClass:[BTChargeGaugeLayer class]]) {
		BTChargeGaugeLayer *source = layer;
		_chargeFraction = source.chargeFraction;
		_valueAvailable = source.isValueAvailable;
		_chargingState = source.chargingState;
		_trackColor = source.trackColor;
		_chargeColor = source.chargeColor;
		_pausedColor = source.pausedColor;
		_lowChargeColor = source.lowChargeColor;
		_markerColor = source.markerColor;
	}
	return self;
}

- (void)drawInContext:(CGContextRef)context {
	CGRect bounds = CGRectInset(self.bounds, 12.0, 12.0);
	CGFloat diameter = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds));
	if (diameter <= 0.0)
		return;
	CGPoint center = CGPointMake(CGRectGetMidX(self.bounds),
		CGRectGetMidY(self.bounds) + BTChargeGaugeVisualCenterOffset(self.bounds));
	CGFloat lineWidth = MAX(8.0, MIN(18.0, diameter * 0.11));
	CGFloat radius = MAX(0.0, diameter * 0.5 - lineWidth * 0.5);
	CGFloat start = (CGFloat)(M_PI * 0.75);
	CGFloat span = (CGFloat)(M_PI * 1.5);

	CGContextSetLineWidth(context, lineWidth);
	CGContextSetLineCap(context, kCGLineCapRound);
	CGContextSetStrokeColorWithColor(context, self.trackColor.CGColor);
	CGContextAddArc(context, center.x, center.y, radius, start, start + span, 0);
	CGContextStrokePath(context);

	if (!self.isValueAvailable)
		return;

	UIColor *color = self.chargeColor;
	if (self.chargingState == BAAnalyticsChargingStatePaused)
		color = self.pausedColor;
	else if (self.chargeFraction <= 0.20)
		color = self.lowChargeColor;
	CGContextSetStrokeColorWithColor(context, color.CGColor);
	CGFloat fraction = MIN(1.0, MAX(0.0, self.chargeFraction));
	CGContextAddArc(context, center.x, center.y, radius, start, start + span * fraction, 0);
	CGContextStrokePath(context);

	if (self.chargingState == BAAnalyticsChargingStateCharging) {
		CGFloat markerAngle = start + span * fraction;
		CGPoint marker = CGPointMake(center.x + cos(markerAngle) * radius,
			center.y + sin(markerAngle) * radius);
		CGContextSetFillColorWithColor(context, self.markerColor.CGColor);
		CGContextFillEllipseInRect(context, CGRectMake(marker.x - 3.0, marker.y - 3.0, 6.0, 6.0));
	}
}

@end

@interface BTChargeGaugeContentView : UIView
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BAAnalyticsCardSize cardSize;
@property (nonatomic, getter=isEditing) BOOL editing;
- (void)applyPercentage:(nullable NSNumber *)percentage
	chargingState:(BAAnalyticsChargingState)chargingState;
- (void)updateAppearanceColors;
@end

@implementation BTChargeGaugeContentView

+ (Class)layerClass {
	return [BTChargeGaugeLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.backgroundColor = [UIColor clearColor];
	self.isAccessibilityElement = YES;
	self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;

	_valueLabel = [UILabel new];
	_valueLabel.textAlignment = NSTextAlignmentCenter;
	_valueLabel.adjustsFontSizeToFitWidth = YES;
	_valueLabel.minimumScaleFactor = 0.55;
	[self addSubview:_valueLabel];

	_captionLabel = [UILabel new];
	_captionLabel.text = BTChargeGaugeLocalizedString(@"Charge");
	_captionLabel.textAlignment = NSTextAlignmentCenter;
	_captionLabel.adjustsFontSizeToFitWidth = YES;
	_captionLabel.minimumScaleFactor = 0.7;
	[self addSubview:_captionLabel];

	_statusLabel = [UILabel new];
	_statusLabel.textAlignment = NSTextAlignmentCenter;
	_statusLabel.adjustsFontSizeToFitWidth = YES;
	_statusLabel.minimumScaleFactor = 0.7;
	[self addSubview:_statusLabel];

	[self updateAppearanceColors];
	[self applyPercentage:nil chargingState:BAAnalyticsChargingStateUnavailable];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat height = CGRectGetHeight(self.bounds);
	BOOL compact = self.cardSize == BAAnalyticsCardSize1x1;
	CGFloat valueHeight = compact ? MIN(42.0, height * 0.31) : MIN(56.0, height * 0.34);
	CGFloat visualCenterY = CGRectGetMidY(self.bounds) + BTChargeGaugeVisualCenterOffset(self.bounds);
	CGFloat valueTop = MAX(10.0, visualCenterY - valueHeight * 0.78);
	CGFloat horizontalInset = compact ? 17.0 : 24.0;
	self.valueLabel.frame = CGRectMake(horizontalInset, valueTop,
		MAX(0.0, width - horizontalInset * 2.0), valueHeight);
	self.captionLabel.frame = CGRectMake(horizontalInset,
		CGRectGetMaxY(self.valueLabel.frame) - 2.0,
		MAX(0.0, width - horizontalInset * 2.0), 20.0);
	self.statusLabel.frame = CGRectMake(horizontalInset,
		CGRectGetMaxY(self.captionLabel.frame),
		MAX(0.0, width - horizontalInset * 2.0), 18.0);
	self.statusLabel.hidden = compact && height < 150.0;

	CGFloat valueSize = compact ? 30.0 : 38.0;
	self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:valueSize
		weight:UIFontWeightSemibold];
	self.captionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
	((BTChargeGaugeLayer *)self.layer).contentsScale = [UIScreen mainScreen].scale;
}

- (void)updateAppearanceColors {
	UIColor *primaryColor = [UIColor blackColor];
	UIColor *secondaryColor = [UIColor colorWithWhite:0.0 alpha:0.58];
	UIColor *trackColor = [UIColor colorWithWhite:0.0 alpha:0.14];
	UIColor *chargeColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.36 alpha:1.0];
	UIColor *pausedColor = [UIColor colorWithRed:1.0 green:0.58 blue:0.0 alpha:1.0];
	UIColor *lowChargeColor = [UIColor colorWithRed:1.0 green:0.23 blue:0.19 alpha:1.0];
	if (@available(iOS 13.0, *)) {
		primaryColor = [UIColor labelColor];
		secondaryColor = [UIColor secondaryLabelColor];
		trackColor = [[UIColor tertiaryLabelColor] resolvedColorWithTraitCollection:self.traitCollection];
		chargeColor = [[UIColor systemGreenColor] resolvedColorWithTraitCollection:self.traitCollection];
		pausedColor = [[UIColor systemOrangeColor] resolvedColorWithTraitCollection:self.traitCollection];
		lowChargeColor = [[UIColor systemRedColor] resolvedColorWithTraitCollection:self.traitCollection];
	}
	self.valueLabel.textColor = primaryColor;
	self.captionLabel.textColor = secondaryColor;
	self.statusLabel.textColor = secondaryColor;
	BTChargeGaugeLayer *gauge = (BTChargeGaugeLayer *)self.layer;
	gauge.trackColor = trackColor;
	gauge.chargeColor = chargeColor;
	gauge.pausedColor = pausedColor;
	gauge.lowChargeColor = lowChargeColor;
	gauge.markerColor = [UIColor whiteColor];
	[gauge setNeedsDisplay];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	[self updateAppearanceColors];
}

- (void)setEditing:(BOOL)editing {
	_editing = editing;
	self.alpha = editing ? 0.82 : 1.0;
}

- (void)applyPercentage:(NSNumber *)percentage
	chargingState:(BAAnalyticsChargingState)chargingState {
	double rawValue = percentage.doubleValue;
	BOOL available = [percentage isKindOfClass:[NSNumber class]] && isfinite(rawValue);
	double value = MIN(100.0, MAX(0.0, rawValue));
	NSString *status = BTChargeGaugeLocalizedString(@"Not Charging");
	if (chargingState == BAAnalyticsChargingStateCharging)
		status = BTChargeGaugeLocalizedString(@"Charging");
	else if (chargingState == BAAnalyticsChargingStatePaused)
		status = BTChargeGaugeLocalizedString(@"Paused");
	else if (chargingState == BAAnalyticsChargingStateUnavailable)
		status = BTChargeGaugeLocalizedString(@"Unavailable");
	self.valueLabel.text = available ? [NSString stringWithFormat:@"%.0f%%", value] : @"--";
	self.statusLabel.text = status;
	NSString *spokenValue = available ?
		[NSString stringWithFormat:BTChargeGaugeLocalizedString(@"%.0f percent"), value] :
		BTChargeGaugeLocalizedString(@"Unavailable");
	self.accessibilityLabel = [NSString stringWithFormat:
		BTChargeGaugeLocalizedString(@"Charge Gauge, %@, %@"), spokenValue, status];

	BTChargeGaugeLayer *gauge = (BTChargeGaugeLayer *)self.layer;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	gauge.valueAvailable = available;
	gauge.chargeFraction = available ? (CGFloat)(value / 100.0) : 0.0;
	gauge.chargingState = chargingState;
	[gauge setNeedsDisplay];
	[CATransaction commit];
}

@end

@interface BTChargeGaugeCard : NSObject <BAAnalyticsCard>
@property (nonatomic, strong) NSHashTable<BTChargeGaugeContentView *> *contentViews;
@property (nonatomic, strong, nullable) NSNumber *latestPercentage;
@property (nonatomic) BAAnalyticsChargingState latestChargingState;
@end

@implementation BTChargeGaugeCard

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	_contentViews = [NSHashTable weakObjectsHashTable];
	_latestChargingState = BAAnalyticsChargingStateUnavailable;
	return self;
}

- (NSString *)analyticsCardIdentifier {
	return BTChargeGaugeCardIdentifier;
}

- (NSString *)analyticsCardDisplayName {
	return BTChargeGaugeLocalizedString(@"Charge Gauge");
}

- (BAAnalyticsCardSizeMask)supportedAnalyticsCardSizes {
	return BAAnalyticsCardSizeMaskAll;
}

- (BAAnalyticsCardSize)defaultAnalyticsCardSize {
	return BAAnalyticsCardSize1x1;
}

- (UIColor *)analyticsCardBackgroundColor {
	if (@available(iOS 13.0, *)) {
		return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
			if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark)
				return [UIColor colorWithRed:28.0 / 255.0 green:28.0 / 255.0 blue:30.0 / 255.0 alpha:1.0];
			return [UIColor colorWithRed:242.0 / 255.0 green:242.0 / 255.0 blue:247.0 / 255.0 alpha:1.0];
		}];
	}
	return [UIColor colorWithRed:242.0 / 255.0 green:242.0 / 255.0 blue:247.0 / 255.0 alpha:1.0];
}

- (UIView *)makeAnalyticsCardContentView {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	BTChargeGaugeContentView *view = [BTChargeGaugeContentView new];
	[self.contentViews addObject:view];
	[view applyPercentage:self.latestPercentage chargingState:self.latestChargingState];
	return view;
}

- (void)configureAnalyticsCardContentView:(UIView *)contentView
	forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	BTChargeGaugeContentView *view = (BTChargeGaugeContentView *)contentView;
	view.cardSize = size;
	view.editing = editing;
	[view setNeedsLayout];
}

- (void)analyticsCardContentView:(UIView *)contentView
	didReceiveMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	self.latestPercentage = [snapshot valueForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent];
	NSNumber *rawState = [snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingState];
	self.latestChargingState = rawState ?
		(BAAnalyticsChargingState)rawState.integerValue : BAAnalyticsChargingStateUnavailable;
	[(BTChargeGaugeContentView *)contentView applyPercentage:self.latestPercentage
		chargingState:self.latestChargingState];
}

- (void)analyticsCardContentView:(UIView *)contentView didChangeEditing:(BOOL)editing {
	((BTChargeGaugeContentView *)contentView).editing = editing;
}

- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size {
	(void)size;
	NSString *status = BTChargeGaugeLocalizedString(@"Not Charging");
	if (self.latestChargingState == BAAnalyticsChargingStateCharging)
		status = BTChargeGaugeLocalizedString(@"Charging");
	else if (self.latestChargingState == BAAnalyticsChargingStatePaused)
		status = BTChargeGaugeLocalizedString(@"Paused");
	else if (self.latestChargingState == BAAnalyticsChargingStateUnavailable)
		status = BTChargeGaugeLocalizedString(@"Unavailable");
	NSString *spokenValue = self.latestPercentage ?
		[NSString stringWithFormat:BTChargeGaugeLocalizedString(@"%.0f percent"),
			self.latestPercentage.doubleValue] : BTChargeGaugeLocalizedString(@"Unavailable");
	return [NSString stringWithFormat:BTChargeGaugeLocalizedString(@"Charge Gauge, %@, %@"),
		spokenValue, status];
}

- (void)analyticsCardDidReceiveMemoryWarning {
	self.latestPercentage = nil;
	self.latestChargingState = BAAnalyticsChargingStateUnavailable;
	for (BTChargeGaugeContentView *view in self.contentViews)
		[view applyPercentage:nil chargingState:BAAnalyticsChargingStateUnavailable];
}

- (NSUInteger)analyticsCardRestorationSchemaVersion {
	return 1;
}

- (NSDictionary *)analyticsCardRestorationState {
	return @{};
}

- (NSDictionary *)analyticsCardMigrateRestorationState:(NSDictionary *)restorationState
	fromSchemaVersion:(NSUInteger)schemaVersion {
	return schemaVersion <= 1 && [restorationState isKindOfClass:[NSDictionary class]] ?
		restorationState : nil;
}

- (void)analyticsCardRestoreState:(NSDictionary *)restorationState {
	(void)restorationState;
}

@end

static void BTChargeGaugeWriteError(BTPluginErrorV1 *error,
	BTPluginResultV1 code, const char *message) {
	if (!error || error->structSize < BT_PLUGIN_ERROR_V1_MINIMUM_SIZE)
		return;
	error->abiVersion = BT_PLUGIN_ABI_VERSION_1;
	error->code = code;
	error->reserved = 0;
	error->message = message;
}

static BTPluginResultV1 BTChargeGaugeRegister(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	if (!host || host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		host->structSize < BT_PLUGIN_HOST_V1_MINIMUM_SIZE || !host->registerExtension) {
		BTChargeGaugeWriteError(error, BTPluginResultV1IncompatibleABI,
			"The Battman host table is incompatible.");
		return BTPluginResultV1IncompatibleABI;
	}
	BTChargeGaugeCard *card = [BTChargeGaugeCard new];
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1,
		.extensionPointVersion = BAAnalyticsCardExtensionPointVersion,
		.flags = 0,
		.extensionIdentifier = "com.torrekie.battman.plugin.charge-gauge.card",
		.extensionObject = (__bridge const void *)card,
	};
	return host->registerExtension(host->context, &registration, error);
}

static const BTPluginDescriptorV1 *BTChargeGaugeDescriptor(void) {
	static const BTPluginDescriptorV1 descriptor = {
		.structSize = sizeof(BTPluginDescriptorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.pluginIdentifier = "com.torrekie.battman.plugin.charge-gauge",
		.pluginVersion = BT_CHARGE_GAUGE_PLUGIN_VERSION,
		.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.registerPlugin = BTChargeGaugeRegister,
	};
	return &descriptor;
}

#if BT_PLUGIN_EMBEDDED
const BTPluginDescriptorV1 *BTChargeGaugePluginDescriptor(void) {
	return BTChargeGaugeDescriptor();
}
#else
BT_PLUGIN_EXPORT const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	return BTChargeGaugeDescriptor();
}
#endif
