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
		printf("Charge Gauge release screenshots rendered through the public card contract.\n");
	}
	return 0;
}
