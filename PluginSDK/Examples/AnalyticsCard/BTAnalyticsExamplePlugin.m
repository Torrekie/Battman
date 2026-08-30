//
//  BTAnalyticsExamplePlugin.m
//  Battman Plugin SDK example
//
//  One implementation is compiled either with BT_PLUGIN_EMBEDDED=1 or as an
//  MH_BUNDLE. It imports only public SDK headers and Apple frameworks.
//

#import <BAAnalyticsCard.h>
#import <QuartzCore/QuartzCore.h>

#import "BTAnalyticsExamplePlugin.h"

#ifndef BT_ANALYTICS_EXAMPLE_PLUGIN_VERSION
#define BT_ANALYTICS_EXAMPLE_PLUGIN_VERSION "1"
#endif

#include <math.h>

static NSString * const BTAnalyticsExampleCardIdentifier =
	@"com.torrekie.battman.example.analytics.charge";

@interface BTAnalyticsExampleGaugeLayer : CALayer
@property (nonatomic) CGFloat chargeFraction;
@property (nonatomic, getter=isValueAvailable) BOOL valueAvailable;
@property (nonatomic, strong) UIColor *gaugeColor;
@end

@implementation BTAnalyticsExampleGaugeLayer

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	self.contentsScale = 2.0;
	self.needsDisplayOnBoundsChange = YES;
	_chargeFraction = 0.0;
	_valueAvailable = NO;
	_gaugeColor = [UIColor colorWithRed:0.16 green:0.67 blue:0.38 alpha:1.0];
	return self;
}

- (instancetype)initWithLayer:(id)layer {
	self = [super initWithLayer:layer];
	if (!self)
		return nil;
	if ([layer isKindOfClass:[BTAnalyticsExampleGaugeLayer class]]) {
		BTAnalyticsExampleGaugeLayer *source = layer;
		_chargeFraction = source.chargeFraction;
		_valueAvailable = source.isValueAvailable;
		_gaugeColor = source.gaugeColor;
	}
	return self;
}

- (void)drawInContext:(CGContextRef)context {
	CGRect track = CGRectInset(self.bounds, 14.0, 14.0);
	CGFloat radius = MIN(18.0, CGRectGetHeight(track) * 0.22);
	CGPathRef trackPath = CGPathCreateWithRoundedRect(track, radius, radius, NULL);
	CGContextSetFillColorWithColor(context,
		[UIColor colorWithWhite:0.5 alpha:0.16].CGColor);
	CGContextAddPath(context, trackPath);
	CGContextFillPath(context);
	CGPathRelease(trackPath);

	if (!self.isValueAvailable)
		return;
	CGRect fill = track;
	fill.size.width = MAX(radius * 2.0, CGRectGetWidth(track) *
		MIN(1.0, MAX(0.0, self.chargeFraction)));
	CGPathRef fillPath = CGPathCreateWithRoundedRect(fill, radius, radius, NULL);
	CGContextSetFillColorWithColor(context, self.gaugeColor.CGColor);
	CGContextAddPath(context, fillPath);
	CGContextFillPath(context);
	CGPathRelease(fillPath);
}

@end

@interface BTAnalyticsExampleContentView : UIView
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic) BAAnalyticsCardSize cardSize;
- (void)applyPercentage:(NSNumber *)percentage;
@end

@implementation BTAnalyticsExampleContentView

+ (Class)layerClass {
	return [BTAnalyticsExampleGaugeLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.backgroundColor = [UIColor clearColor];
	self.isAccessibilityElement = YES;

	_valueLabel = [UILabel new];
	_valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:30.0 weight:UIFontWeightSemibold];
	_valueLabel.textAlignment = NSTextAlignmentCenter;
	_valueLabel.adjustsFontSizeToFitWidth = YES;
	_valueLabel.minimumScaleFactor = 0.6;
	[self addSubview:_valueLabel];

	_captionLabel = [UILabel new];
	_captionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	_captionLabel.textAlignment = NSTextAlignmentCenter;
	_captionLabel.text = @"Charge";
	[self addSubview:_captionLabel];

	[self applyPercentage:nil];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat height = CGRectGetHeight(self.bounds);
	CGFloat width = CGRectGetWidth(self.bounds);
	CGFloat valueHeight = MIN(44.0, height * 0.38);
	self.valueLabel.frame = CGRectMake(18.0, MAX(12.0, height * 0.24),
		MAX(0.0, width - 36.0), valueHeight);
	self.captionLabel.frame = CGRectMake(18.0, CGRectGetMaxY(self.valueLabel.frame) + 2.0,
		MAX(0.0, width - 36.0), 20.0);
}

- (void)applyPercentage:(NSNumber *)percentage {
	double value = percentage.doubleValue;
	BOOL available = [percentage isKindOfClass:[NSNumber class]] && isfinite(value);
	value = MIN(100.0, MAX(0.0, value));
	self.valueLabel.text = available ? [NSString stringWithFormat:@"%.0f%%", value] : @"--";
	self.accessibilityLabel = available ?
		[NSString stringWithFormat:@"Charge, %.0f percent", value] : @"Charge unavailable";
	BTAnalyticsExampleGaugeLayer *gauge = (BTAnalyticsExampleGaugeLayer *)self.layer;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	gauge.valueAvailable = available;
	gauge.chargeFraction = available ? (CGFloat)(value / 100.0) : 0.0;
	[gauge setNeedsDisplay];
	[CATransaction commit];
}

@end

@interface BTAnalyticsExampleCard : NSObject <BAAnalyticsCard>
@property (nonatomic, strong) NSHashTable<BTAnalyticsExampleContentView *> *contentViews;
@property (nonatomic, strong, nullable) NSNumber *latestPercentage;
@property (nonatomic, strong) NSMutableArray<NSString *> *lifecycleEvents;
@end

@implementation BTAnalyticsExampleCard

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	_contentViews = [NSHashTable weakObjectsHashTable];
	_lifecycleEvents = [NSMutableArray array];
	return self;
}

- (NSString *)analyticsCardIdentifier {
	return BTAnalyticsExampleCardIdentifier;
}

- (NSString *)analyticsCardDisplayName {
	return @"SDK Charge Example";
}

- (BAAnalyticsCardSizeMask)supportedAnalyticsCardSizes {
	return BAAnalyticsCardSizeMaskAll;
}

- (BAAnalyticsCardSize)defaultAnalyticsCardSize {
	return BAAnalyticsCardSize1x1;
}

- (UIColor *)analyticsCardBackgroundColor {
	return [UIColor colorWithRed:0.10 green:0.12 blue:0.14 alpha:1.0];
}

- (UIView *)makeAnalyticsCardContentView {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	[self.lifecycleEvents addObject:@"make"];
	BTAnalyticsExampleContentView *view = [BTAnalyticsExampleContentView new];
	[self.contentViews addObject:view];
	[view applyPercentage:self.latestPercentage];
	return view;
}

- (void)configureAnalyticsCardContentView:(UIView *)contentView
	forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	[self.lifecycleEvents addObject:editing ? @"configure-editing" : @"configure"];
	BTAnalyticsExampleContentView *view = (BTAnalyticsExampleContentView *)contentView;
	view.cardSize = size;
	view.alpha = editing ? 0.82 : 1.0;
	[view setNeedsLayout];
}

- (void)analyticsCardContentView:(UIView *)contentView
	didReceiveMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSAssert([NSThread isMainThread], @"Analytics UIKit entry points are main-thread only.");
	[self.lifecycleEvents addObject:@"snapshot"];
	self.latestPercentage = [snapshot valueForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent];
	[(BTAnalyticsExampleContentView *)contentView applyPercentage:self.latestPercentage];
}

- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size {
	(void)size;
	return self.latestPercentage ? [NSString stringWithFormat:@"Charge, %.0f percent",
		self.latestPercentage.doubleValue] : @"Charge unavailable";
}

- (void)analyticsCardDidEndDisplayingContentView:(UIView *)contentView {
	(void)contentView;
	[self.lifecycleEvents addObject:@"did-end"];
}

- (void)analyticsCardWillDisplayContentView:(UIView *)contentView {
	(void)contentView;
	[self.lifecycleEvents addObject:@"will-display"];
}

- (void)analyticsCardContentView:(UIView *)contentView didChangeEditing:(BOOL)editing {
	(void)contentView;
	[self.lifecycleEvents addObject:editing ? @"editing-on" : @"editing-off"];
}

- (void)analyticsCardDidReceiveMemoryWarning {
	self.latestPercentage = nil;
	[self.lifecycleEvents addObject:@"memory-warning"];
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

static BOOL BTAnalyticsExampleStructureContainsField(uint32_t structSize,
	size_t fieldOffset, size_t fieldSize) {
	return structSize >= fieldOffset && (size_t)structSize - fieldOffset >= fieldSize;
}

static void BTAnalyticsExampleWriteError(BTPluginErrorV1 *error,
	BTPluginResultV1 code, const char *message) {
	if (!error || !BTAnalyticsExampleStructureContainsField(error->structSize,
		offsetof(BTPluginErrorV1, message), sizeof(error->message)))
		return;
	error->abiVersion = BT_PLUGIN_ABI_VERSION_1;
	error->code = code;
	error->reserved = 0;
	error->message = message;
}

static BTPluginResultV1 BTAnalyticsExampleRegister(const BTPluginHostV1 *host,
	BTPluginErrorV1 *error) {
	if (!host || host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		host->structSize < BT_PLUGIN_HOST_V1_MINIMUM_SIZE ||
		!host->registerExtension) {
		BTAnalyticsExampleWriteError(error, BTPluginResultV1IncompatibleABI,
			"The Battman host table is incompatible.");
		return BTPluginResultV1IncompatibleABI;
	}
	BTAnalyticsExampleCard *card = [BTAnalyticsExampleCard new];
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1,
		.extensionPointVersion = BAAnalyticsCardExtensionPointVersion,
		.flags = 0,
		.extensionIdentifier = "com.torrekie.battman.example.analytics.charge",
		.extensionObject = (__bridge const void *)card,
	};
	return host->registerExtension(host->context, &registration, error);
}

static const BTPluginDescriptorV1 *BTAnalyticsExampleDescriptor(void) {
	static const BTPluginDescriptorV1 descriptor = {
		.structSize = sizeof(BTPluginDescriptorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.pluginIdentifier = "com.torrekie.battman.example.analytics",
		.pluginVersion = BT_ANALYTICS_EXAMPLE_PLUGIN_VERSION,
		.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.registerPlugin = BTAnalyticsExampleRegister,
	};
	return &descriptor;
}

#if BT_PLUGIN_EMBEDDED
const BTPluginDescriptorV1 *BTAnalyticsExamplePluginDescriptor(void) {
	return BTAnalyticsExampleDescriptor();
}
#else
BT_PLUGIN_EXPORT const BTPluginDescriptorV1 *BattmanPluginEntryPointV1(void) {
	return BTAnalyticsExampleDescriptor();
}
#endif
