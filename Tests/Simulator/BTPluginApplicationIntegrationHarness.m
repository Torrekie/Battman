//
//  BTPluginApplicationIntegrationHarness.m
//  Battman tests
//
//  A small simulator-only contract test for the UIKit callback forwarding
//  layer.  The platform implementation is deliberately stubbed here: this
//  harness verifies callback ordering, fallback, and bounded URL forwarding,
//  not package verification or native-image loading.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "../../Battman/PluginHost/Application/BTPluginApplicationIntegration.h"
#import "../../Battman/PluginHost/Application/BTPluginPlatform.h"

static NSMutableArray<NSString *> *BTTestEvents;

static void BTResetEvents(void) {
	BTTestEvents = [NSMutableArray array];
}

static void BTRecordEvent(NSString *event) {
	[BTTestEvents addObject:event ?: @"<nil>"];
}

static BOOL BTAssert(BOOL condition, NSString *message) {
	if (condition)
		return YES;
	fprintf(stderr, "FAIL: %s\n", message.UTF8String ?: "<no message>");
	return NO;
}

static BOOL BTAssertEvents(NSArray<NSString *> *expected, NSString *label) {
	if ([BTTestEvents isEqualToArray:expected])
		return YES;
	NSString *message = [NSString stringWithFormat:@"%@ events differ. expected=%@ actual=%@",
		label, expected, BTTestEvents];
	return BTAssert(NO, message);
}

static NSURL *BTTestURL(NSString *lastPathComponent) {
	return [NSURL fileURLWithPath:[@"/tmp/BattmanPluginIntegration" stringByAppendingPathComponent:
		lastPathComponent]];
}

// The production platform is intentionally not linked into this standalone
// executable.  Returning YES only for .battman lets the app-delegate tests
// exercise both the handled and original-delegate fallback paths.
@implementation BTPluginPlatform

+ (instancetype)sharedPlatform {
	static BTPluginPlatform *platform;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		platform = [BTPluginPlatform new];
	});
	return platform;
}

- (BOOL)prepareForApplicationLaunchWithError:(NSError **)error {
	(void)error;
	return NO;
}

- (BOOL)markStartupSettledWithError:(NSError **)error {
	(void)error;
	return NO;
}

- (id)currentManagementSnapshotWithError:(NSError **)error {
	(void)error;
	return nil;
}

- (BOOL)requestSafeModeForNextLaunchWithError:(NSError **)error {
	(void)error;
	return NO;
}

- (BOOL)handleOpenPackageURL:(NSURL *)packageURL {
	BTRecordEvent([NSString stringWithFormat:@"route:%@", packageURL.absoluteString ?: @"<nil>"]);
	return packageURL.isFileURL &&
		[packageURL.pathExtension.lowercaseString isEqualToString:@"battman"];
}

@end

@interface BTTestApplicationDelegate : NSObject
- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (BOOL)application:(UIApplication *)application
	openURL:(NSURL *)url options:(NSDictionary *)options;
@end

@implementation BTTestApplicationDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	(void)application;
	(void)launchOptions;
	BTRecordEvent(@"application-launch-original");
	return YES;
}

- (BOOL)application:(UIApplication *)application
	openURL:(NSURL *)url options:(NSDictionary *)options {
	(void)application;
	(void)url;
	(void)options;
	BTRecordEvent(@"application-open-original");
	return YES;
}

@end

// BTPluginInstallApplicationIntegration intentionally looks up this exact
// runtime-created class name.  The test class mirrors the selectors and
// Objective-C type encodings without starting UIApplicationMain.
@interface SceneDelegate : NSObject
- (void)scene:(id)scene willConnectToSession:(id)session options:(id)connectionOptions;
- (void)scene:(id)scene openURLContexts:(NSSet *)URLContexts;
@end

@implementation SceneDelegate

- (void)scene:(id)scene willConnectToSession:(id)session options:(id)connectionOptions {
	(void)scene;
	(void)session;
	(void)connectionOptions;
	BTRecordEvent(@"scene-connect-original");
}

- (void)scene:(id)scene openURLContexts:(NSSet *)URLContexts {
	(void)scene;
	(void)URLContexts;
	BTRecordEvent(@"scene-open-original");
}

@end

@interface BTTestURLContext : NSObject
@property (nonatomic, strong) NSURL *URL;
- (instancetype)initWithURL:(NSURL *)URL;
@end

@implementation BTTestURLContext

- (instancetype)initWithURL:(NSURL *)URL {
	self = [super init];
	if (self)
		_URL = URL;
	return self;
}

@end

@interface BTTestConnectionOptions : NSObject
@property (nonatomic, copy) NSSet *URLContexts;
- (instancetype)initWithURLContexts:(NSSet *)URLContexts;
@end

@implementation BTTestConnectionOptions

- (instancetype)initWithURLContexts:(NSSet *)URLContexts {
	self = [super init];
	if (self)
		_URLContexts = [URLContexts copy];
	return self;
}

@end

static BTTestURLContext *BTContext(NSString *name) {
	return [[BTTestURLContext alloc] initWithURL:BTTestURL(name)];
}

static BOOL BTTestColdApplicationCallback(BTTestApplicationDelegate *delegate) {
	BTResetEvents();
	NSURL *url = BTTestURL(@"cold.battman");
	BOOL result = [delegate application:nil
		didFinishLaunchingWithOptions:@{ UIApplicationLaunchOptionsURLKey: url }];
	return BTAssert(result, @"cold application callback returned NO") &&
		BTAssertEvents(@[ @"application-launch-original",
			[NSString stringWithFormat:@"route:%@", url.absoluteString] ],
			@"cold application callback");
}

static BOOL BTTestWarmApplicationCallbacks(BTTestApplicationDelegate *delegate) {
	NSURL *handledURL = BTTestURL(@"warm.battman");
	BTResetEvents();
	BOOL handledResult = [delegate application:nil openURL:handledURL options:@{}];
	if (!BTAssert(handledResult, @"handled warm application callback returned NO") ||
		!BTAssertEvents(@[ [NSString stringWithFormat:@"route:%@", handledURL.absoluteString] ],
			@"handled warm application callback"))
		return NO;

	NSURL *fallbackURL = BTTestURL(@"warm.txt");
	BTResetEvents();
	BOOL fallbackResult = [delegate application:nil openURL:fallbackURL options:@{}];
	return BTAssert(fallbackResult, @"fallback warm application callback returned NO") &&
		BTAssertEvents(@[ [NSString stringWithFormat:@"route:%@", fallbackURL.absoluteString],
			@"application-open-original" ], @"fallback warm application callback");
}

static BOOL BTTestColdSceneCallback(SceneDelegate *delegate) {
	BTResetEvents();
	BTTestURLContext *first = BTContext(@"connect-z.battman");
	BTTestURLContext *second = BTContext(@"connect-a.battman");
	BTTestConnectionOptions *options = [[BTTestConnectionOptions alloc]
		initWithURLContexts:[NSSet setWithObjects:first, second, nil]];
	[delegate scene:nil willConnectToSession:nil options:options];
	return BTAssertEvents(@[ @"scene-connect-original",
		[NSString stringWithFormat:@"route:%@", second.URL.absoluteString],
		[NSString stringWithFormat:@"route:%@", first.URL.absoluteString] ],
		@"cold scene callback");
}

static BOOL BTTestWarmSceneAndContextCap(SceneDelegate *delegate) {
	BTResetEvents();
	NSMutableSet *contexts = [NSMutableSet setWithCapacity:18];
	NSMutableArray<NSString *> *expectedRoutes = [NSMutableArray arrayWithCapacity:17];
	for (NSInteger index = 17; index >= 0; index--) {
		NSString *name = [NSString stringWithFormat:@"cap-%02ld.battman", (long)index];
		BTTestURLContext *context = BTContext(name);
		[contexts addObject:context];
		if (index < 16) {
			[expectedRoutes addObject:[NSString stringWithFormat:@"route:%@",
				context.URL.absoluteString]];
		}
	}
	[expectedRoutes sortUsingSelector:@selector(compare:)];
	[expectedRoutes addObject:@"scene-open-original"];
	[delegate scene:nil openURLContexts:contexts];
	return BTAssertEvents(expectedRoutes, @"warm scene callback and 16-context cap");
}

int main(int argc, const char *argv[]) {
	(void)argc;
	(void)argv;
	@autoreleasepool {
		if (!BTAssert([NSThread isMainThread], @"callback harness must start on the main thread"))
			return 1;
		if (!BTAssert(NSClassFromString(@"SceneDelegate") == [SceneDelegate class],
			@"synthetic SceneDelegate class was not registered"))
			return 1;

		NSError *error = nil;
		NSString *applicationClassName = NSStringFromClass([BTTestApplicationDelegate class]);
		BOOL installed = BTPluginInstallApplicationIntegration(applicationClassName, &error);
		if (!BTAssert(installed, error.localizedDescription ?: @"application integration install failed"))
			return 1;
		error = nil;
		BOOL reinstalled = BTPluginInstallApplicationIntegration(applicationClassName, &error);
		if (!BTAssert(reinstalled, error.localizedDescription ?: @"idempotent integration install failed"))
			return 1;

		BTTestApplicationDelegate *applicationDelegate = [BTTestApplicationDelegate new];
		SceneDelegate *sceneDelegate = [SceneDelegate new];
		if (!BTTestColdApplicationCallback(applicationDelegate) ||
			!BTTestWarmApplicationCallbacks(applicationDelegate) ||
			!BTTestColdSceneCallback(sceneDelegate) ||
			!BTTestWarmSceneAndContextCap(sceneDelegate))
			return 1;

		// A second install must not add a second route wrapper.  This stays
		// separate so a duplicate wrapper cannot hide in a longer event list.
		NSURL *idempotenceURL = BTTestURL(@"idempotence.battman");
		BTResetEvents();
		BOOL idempotenceResult = [applicationDelegate application:nil
			openURL:idempotenceURL options:@{}];
		if (!BTAssert(idempotenceResult, @"idempotence callback returned NO") ||
			!BTAssertEvents(@[ [NSString stringWithFormat:@"route:%@",
				idempotenceURL.absoluteString] ], @"idempotence callback"))
			return 1;
		printf("BTPluginApplicationIntegration cold/warm callback tests passed.\n");
	}
	return 0;
}
