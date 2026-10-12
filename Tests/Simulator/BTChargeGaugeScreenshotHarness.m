//
//  BTChargeGaugeScreenshotHarness.m
//  Battman release evidence
//
//  Renders the separately shipped official card through the same public
//  registration and Analytics host-cell contract used by Battman.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <BAAnalyticsCard.h>
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#import "../../Battman/Features/Analytics/Host/AnalyticsCardCell.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/PluginHost/BTPluginExtensionDescriptor.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../OfficialPlugins/ChargeGauge/BTChargeGaugePlugin.h"

#define BTRequire(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "FAIL: %s\n", [(message) UTF8String]); \
		return 1; \
	} \
} while (0)

NSString *cond_localize(const char *value) {
	return [NSString stringWithUTF8String:value];
}

const char *cond_localize_c(const char *value) {
	return value;
}

// The host cell only uses these built-in types for identity checks. This
// independently shipped provider must never enter a built-in renderer path.
@interface BAAnalyticsCanvasCard : NSObject @end
@implementation BAAnalyticsCanvasCard
+ (instancetype)allocWithZone:(NSZone *)zone { (void)zone; abort(); }
@end
@interface BAAnalyticsCanvasView : UIView @end
@implementation BAAnalyticsCanvasView
+ (instancetype)allocWithZone:(NSZone *)zone { (void)zone; abort(); }
@end

static id<BAAnalyticsCard> BTLegacyHostCard;
static BTPluginResultV1 BTLegacyHostRegister(void *context,
	const BTPluginExtensionRegistrationV1 *registration, BTPluginErrorV1 *error) {
	(void)context; (void)error;
	BTLegacyHostCard = (__bridge id)registration->extensionObject;
	return BTPluginResultV1Success;
}

id perform_selector(SEL selector, id target, id argument) {
	if (!target || ![target respondsToSelector:selector])
		return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [target performSelector:selector withObject:argument];
#pragma clang diagnostic pop
}

id perform_selector2(SEL selector, id target, id firstArgument, id secondArgument) {
	if (!target || ![target respondsToSelector:selector])
		return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	return [target performSelector:selector withObject:firstArgument withObject:secondArgument];
#pragma clang diagnostic pop
}

static NSData *BTRenderView(UIView *view) {
	UIGraphicsBeginImageContextWithOptions(view.bounds.size, YES, 1.0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context)
		return nil;
	[view.layer renderInContext:context];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return UIImagePNGRepresentation(image);
}

static int BTWriteEvidence(id<BAAnalyticsCard> card, NSString *outputDirectory,
	NSString *name, CGSize size, BAAnalyticsCardSize cardSize, NSNumber *percentage,
	BAAnalyticsChargingState chargingState) {
	UIView *canvas = [[UIView alloc] initWithFrame:(CGRect){ CGPointZero, size }];
	canvas.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
	BAAnalyticsCardCell *cell = [[BAAnalyticsCardCell alloc]
		initWithFrame:CGRectInset(canvas.bounds, 24.0, 24.0)];
	[cell configureWithCard:card size:cardSize editing:NO];
	[cell setAnalyticsCardDisplayed:YES];
	[canvas addSubview:cell];
	NSDictionary *values = percentage ? @{
		BAAnalyticsMetricStateOfChargePercent: percentage,
		BAAnalyticsMetricChargingState: @(chargingState),
	} : @{
		BAAnalyticsMetricChargingState: @(chargingState),
	};
	BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc]
		initWithSequenceNumber:100 timestamp:[NSDate dateWithTimeIntervalSince1970:1700000000]
		values:values histories:@{}];
	[cell applyMetricSnapshot:snapshot];
	[canvas setNeedsLayout];
	[canvas layoutIfNeeded];
	[cell setNeedsLayout];
	[cell layoutIfNeeded];
	NSData *png = BTRenderView(canvas);
	if (!png.length)
		return 1;
	NSString *path = [outputDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@.png", name]];
	if (![png writeToFile:path options:NSDataWritingAtomic error:nil])
		return 1;
	[cell setAnalyticsCardDisplayed:NO];
	return 0;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTRequire(argc == 2, @"provide an existing output directory");
		NSString *outputDirectory = [NSString stringWithUTF8String:argv[1]];
		BOOL directory = NO;
		BTRequire([[NSFileManager defaultManager] fileExistsAtPath:outputDirectory
			isDirectory:&directory] && directory, @"output directory is unavailable");
		BTRequire([NSThread isMainThread], @"UIKit evidence harness must run on the main thread");
		BTPluginSetPreferredLanguage(@"en");

		BTPluginRegistry *registry = [BTPluginRegistry new];
		NSError *error = nil;
		BTRequire([registry registerExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
			interfaceVersion:BAAnalyticsCardExtensionPointVersion
			requiredProtocol:@protocol(BAAnalyticsCard) error:&error],
			error.localizedDescription ?: @"could not register Analytics extension point");
		BTRequire(BTRegisterEmbeddedPluginDescriptor(BTChargeGaugePluginDescriptor(), registry,
			[NSSet setWithObject:BAAnalyticsCardExtensionPointIdentifier], &error),
			error.localizedDescription ?: @"Charge Gauge registration failed");
		NSArray<BTPluginExtensionDescriptor *> *descriptors = [registry
			extensionDescriptorsForExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier];
		BTRequire(descriptors.count == 1, @"Charge Gauge must register exactly one card");
		id<BAAnalyticsCard> card = descriptors.firstObject.extensionObject;
		BTRequire([card.analyticsCardIdentifier isEqualToString:
			@"com.torrekie.battman.plugin.charge-gauge.card"], @"card identity drifted");

		BTRequire(BTWriteEvidence(card, outputDirectory,
			@"plugin-1.1.0-charge-gauge-charging-2x1", CGSizeMake(416.0, 228.0),
			BAAnalyticsCardSize2x1, @73, BAAnalyticsChargingStateCharging) == 0,
			@"could not render charging state");
		BTRequire(BTWriteEvidence(card, outputDirectory,
			@"plugin-1.1.0-charge-gauge-paused-1x1", CGSizeMake(228.0, 228.0),
			BAAnalyticsCardSize1x1, @19, BAAnalyticsChargingStatePaused) == 0,
			@"could not render paused state");
		BTRequire(BTWriteEvidence(card, outputDirectory,
			@"plugin-1.1.0-charge-gauge-unavailable-1x1", CGSizeMake(228.0, 228.0),
			BAAnalyticsCardSize1x1, nil, BAAnalyticsChargingStateUnavailable) == 0,
			@"could not render unavailable state");

		NSDictionary *localizedNames = @{ @"de": @"Ladeanzeige", @"zh_CN": @"电量仪表",
			@"zh_TW": @"電量儀表", @"en": @"Charge Gauge" };
		for (NSString *language in @[ @"de", @"zh_CN", @"zh_TW", @"en" ]) {
			BTPluginSetPreferredLanguage(language);
			BTPluginRegistry *localizedRegistry = [BTPluginRegistry new];
			BTRequire([localizedRegistry registerExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
				interfaceVersion:BAAnalyticsCardExtensionPointVersion requiredProtocol:@protocol(BAAnalyticsCard) error:&error],
				error.localizedDescription);
			BTRequire(BTRegisterEmbeddedPluginDescriptor(BTChargeGaugePluginDescriptor(), localizedRegistry,
				[NSSet setWithObject:BAAnalyticsCardExtensionPointIdentifier], &error), error.localizedDescription);
			id<BAAnalyticsCard> localizedCard = [localizedRegistry
				extensionObjectsForExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier].firstObject;
			BTRequire([localizedCard.analyticsCardDisplayName isEqualToString:localizedNames[language]],
				([NSString stringWithFormat:@"Charge Gauge did not follow host language %@", language]));
		}
		BTPluginSetPreferredLanguage(nil);
		BTPluginHostV1 legacyHost = {
			.structSize = BT_PLUGIN_HOST_V1_MINIMUM_SIZE, .abiVersion = BT_PLUGIN_ABI_VERSION_1,
			.registerExtension = BTLegacyHostRegister,
			// Outside the advertised prefix: the plug-in must never read it.
			.preferredLanguage = (const char *)(uintptr_t)1,
		};
		BTRequire(BTChargeGaugePluginDescriptor()->registerPlugin(&legacyHost, NULL) == BTPluginResultV1Success &&
			BTLegacyHostCard.analyticsCardDisplayName.length > 0,
			@"Charge Gauge could not register with the original v1 host prefix");
		printf("Charge Gauge release screenshots rendered through the public card contract.\n");
	}
	return 0;
}
