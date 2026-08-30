//
//  BTAnalyticsExampleParityHarness.m
//  Battman tests
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

#import <BAAnalyticsCard.h>
#import "../../Battman/Features/Analytics/Public/BAAnalyticsMetricSnapshot.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/PluginHost/BTPluginExtensionDescriptor.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/Runtime/BTPluginNativeImageLoaderPrivate.h"

#if BT_ANALYTICS_EXAMPLE_EMBEDDED
#import "../../PluginSDK/Examples/AnalyticsCard/BTAnalyticsExamplePlugin.h"
#endif

#define BTRequire(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "FAIL: %s\n", [(message) UTF8String]); \
		return 1; \
	} \
} while (0)

static NSString *BTDataSHA256(NSData *data) {
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	static const char digits[] = "0123456789abcdef";
	char output[CC_SHA256_DIGEST_LENGTH * 2 + 1];
	for (NSUInteger index = 0; index < sizeof(digest); index++) {
		output[index * 2] = digits[digest[index] >> 4];
		output[index * 2 + 1] = digits[digest[index] & 0x0f];
	}
	output[sizeof(digest) * 2] = '\0';
	return [NSString stringWithUTF8String:output];
}

static NSString *BTRenderCard(id<BAAnalyticsCard> card, UIView *view) {
	const size_t width = 320;
	const size_t height = 180;
	const size_t bytesPerRow = width * 4;
	NSMutableData *pixels = [NSMutableData dataWithLength:bytesPerRow * height];
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8,
		bytesPerRow, colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	if (!context)
		return nil;
	UIColor *background = [card respondsToSelector:@selector(analyticsCardBackgroundColor)] ?
		[card analyticsCardBackgroundColor] : [UIColor whiteColor];
	CGContextSetFillColorWithColor(context, background.CGColor);
	CGContextFillRect(context, CGRectMake(0, 0, width, height));
	CGContextTranslateCTM(context, 0, height);
	CGContextScaleCTM(context, 1.0, -1.0);
	[view.layer renderInContext:context];
	CGContextRelease(context);
	return BTDataSHA256(pixels);
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSString *expectedPluginVersion = [NSString
			stringWithUTF8String:BT_ANALYTICS_EXAMPLE_PLUGIN_VERSION];
		BTRequire([NSThread isMainThread], @"parity harness must start on the main thread");
		BTPluginRegistry *registry = [BTPluginRegistry new];
		NSError *error = nil;
		BTRequire([registry registerExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
			interfaceVersion:BAAnalyticsCardExtensionPointVersion requiredProtocol:@protocol(BAAnalyticsCard)
			error:&error], error.localizedDescription ?: @"could not register Analytics extension point");
		NSSet<NSString *> *declared = [NSSet setWithObject:BAAnalyticsCardExtensionPointIdentifier];

#if BT_ANALYTICS_EXAMPLE_EMBEDDED
		(void)argc;
		(void)argv;
		BTRequire(BTRegisterEmbeddedPluginDescriptor(BTAnalyticsExamplePluginDescriptor(), registry,
			declared, &error), error.localizedDescription ?: @"embedded registration failed");
#else
		BTRequire(argc == 2, @"native harness requires the bundle executable path");
		NSURL *executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		BTPluginNativeImageLoader *loader = [BTPluginNativeImageLoader new];
		BTRequire([loader loadImageAtURL:executableURL
			expectedPluginIdentifier:@"com.torrekie.battman.example.analytics"
			expectedPluginVersion:expectedPluginVersion declaredExtensionPoints:declared
			registry:registry error:&error],
			error.localizedDescription ?: @"native registration failed");
#endif

		NSArray<BTPluginExtensionDescriptor *> *descriptors = [registry
			extensionDescriptorsForExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier];
		BTRequire(descriptors.count == 1, @"example must register exactly one Analytics card");
		BTPluginExtensionDescriptor *descriptor = descriptors.firstObject;
		BTRequire([descriptor.pluginIdentifier isEqualToString:@"com.torrekie.battman.example.analytics"],
			@"registered plug-in identity changed");
		BTRequire([descriptor.pluginVersion isEqualToString:expectedPluginVersion],
			@"registered build version changed");
		BTRequire([descriptor.extensionIdentifier isEqualToString:
			@"com.torrekie.battman.example.analytics.charge"], @"registered card identity changed");
		id<BAAnalyticsCard> card = descriptor.extensionObject;
		BTRequire([card conformsToProtocol:@protocol(BAAnalyticsCard)], @"registered object lost public protocol");
		BTRequire(card.supportedAnalyticsCardSizes == BAAnalyticsCardSizeMaskAll,
			@"example supported-size mask changed");
		BTRequire(card.defaultAnalyticsCardSize == BAAnalyticsCardSize1x1,
			@"example default size changed");

		UIView *view = [card makeAnalyticsCardContentView];
		BTRequire([view isKindOfClass:[UIView class]], @"card did not create its content root view");
		view.frame = CGRectMake(0, 0, 320, 180);
		[card configureAnalyticsCardContentView:view forSize:BAAnalyticsCardSize2x1 editing:NO];
		if ([card respondsToSelector:@selector(analyticsCardWillDisplayContentView:)])
			[card analyticsCardWillDisplayContentView:view];
		BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc]
			initWithSequenceNumber:42 timestamp:[NSDate dateWithTimeIntervalSince1970:1000]
			values:@{ BAAnalyticsMetricStateOfChargePercent: @73 } histories:@{}];
		if ([card respondsToSelector:@selector(analyticsCardContentView:didReceiveMetricSnapshot:)])
			[card analyticsCardContentView:view didReceiveMetricSnapshot:snapshot];
		if ([card respondsToSelector:@selector(analyticsCardContentView:didChangeEditing:)]) {
			[card analyticsCardContentView:view didChangeEditing:YES];
			[card analyticsCardContentView:view didChangeEditing:NO];
		}
		[card configureAnalyticsCardContentView:view forSize:BAAnalyticsCardSize2x1 editing:YES];
		[view setNeedsLayout];
		[view layoutIfNeeded];
		NSString *pixelSHA256 = BTRenderCard(card, view);
		BTRequire(pixelSHA256.length == 64, @"card rendering did not produce a pixel digest");
		if ([card respondsToSelector:@selector(analyticsCardDidEndDisplayingContentView:)])
			[card analyticsCardDidEndDisplayingContentView:view];
		if ([card respondsToSelector:@selector(analyticsCardDidReceiveMemoryWarning)])
			[card analyticsCardDidReceiveMemoryWarning];

		NSArray<NSString *> *events = [(id)card valueForKey:@"lifecycleEvents"];
		NSArray<NSString *> *expectedEvents = @[ @"make", @"configure", @"will-display", @"snapshot",
			@"editing-on", @"editing-off", @"configure-editing", @"did-end", @"memory-warning" ];
		NSString *lifecycleMessage = [NSString stringWithFormat:@"lifecycle mismatch: %@", events];
		BTRequire([events isEqualToArray:expectedEvents], lifecycleMessage);
		NSDictionary *result = @{
			@"card": descriptor.extensionIdentifier,
			@"defaultSize": @(card.defaultAnalyticsCardSize),
			@"events": events,
			@"pixelSHA256": pixelSHA256,
			@"plugin": descriptor.pluginIdentifier,
			@"sizes": @(card.supportedAnalyticsCardSizes),
			@"version": descriptor.pluginVersion,
		};
		NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:&error];
		BTRequire(json != nil, error.localizedDescription ?: @"could not serialize parity result");
		fwrite(json.bytes, 1, json.length, stdout);
		fputc('\n', stdout);
	}
	return 0;
}
