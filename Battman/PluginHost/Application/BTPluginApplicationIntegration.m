//
//  BTPluginApplicationIntegration.m
//  Battman
//

#import "BTPluginApplicationIntegration.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "BTPluginPlatform.h"
#import "../Model/BTPluginPackageErrors.h"

typedef BOOL (*BTPluginDidFinishLaunchingIMP)(id, SEL, UIApplication *, NSDictionary *);
typedef BOOL (*BTPluginOpenURLIMP)(id, SEL, UIApplication *, NSURL *, NSDictionary *);
// Keep the stored IMP types availability-neutral for the iOS 12 deployment
// target. The typed wrappers below are themselves guarded as iOS 13 APIs.
typedef void (*BTPluginSceneConnectIMP)(id, SEL, id, id, id);
typedef void (*BTPluginSceneOpenURLsIMP)(id, SEL, id, id);

static BTPluginDidFinishLaunchingIMP BTOriginalDidFinishLaunching = NULL;
static BTPluginOpenURLIMP BTOriginalOpenURL = NULL;
static BTPluginSceneConnectIMP BTOriginalSceneConnect = NULL;
static BTPluginSceneOpenURLsIMP BTOriginalSceneOpenURLs = NULL;

static BOOL BTPluginIntegrationFail(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorImport, description, nil, nil);
	return NO;
}

static BOOL BTPluginRouteOpenedURL(NSURL *url) {
	return [[BTPluginPlatform sharedPlatform] handleOpenPackageURL:url];
}

static void BTPluginRouteURLContexts(NSSet<UIOpenURLContext *> *URLContexts) API_AVAILABLE(ios(13.0)) {
	NSArray<UIOpenURLContext *> *sortedContexts = [URLContexts.allObjects
		sortedArrayUsingComparator:^NSComparisonResult(UIOpenURLContext *left, UIOpenURLContext *right) {
			return [left.URL.absoluteString compare:right.URL.absoluteString options:NSLiteralSearch];
		}];
	NSUInteger count = MIN(sortedContexts.count, (NSUInteger)16);
	for (NSUInteger index = 0; index < count; index++)
		BTPluginRouteOpenedURL(sortedContexts[index].URL);
}

static BOOL BTPluginDidFinishLaunching(id self, SEL command, UIApplication *application,
	NSDictionary *launchOptions) {
	BOOL launched = BTOriginalDidFinishLaunching ?
		BTOriginalDidFinishLaunching(self, command, application, launchOptions) : YES;
	if (launched) {
		id value = launchOptions[UIApplicationLaunchOptionsURLKey];
		if ([value isKindOfClass:[NSURL class]])
			BTPluginRouteOpenedURL(value);
	}
	return launched;
}

static BOOL BTPluginApplicationOpenURL(id self, SEL command, UIApplication *application,
	NSURL *url, NSDictionary *options) {
	if (BTPluginRouteOpenedURL(url))
		return YES;
	return BTOriginalOpenURL ? BTOriginalOpenURL(self, command, application, url, options) : NO;
}

static void BTPluginSceneWillConnect(id self, SEL command, UIScene *scene, UISceneSession *session,
	UISceneConnectionOptions *connectionOptions) API_AVAILABLE(ios(13.0)) {
	if (BTOriginalSceneConnect)
		BTOriginalSceneConnect(self, command, scene, session, connectionOptions);
	BTPluginRouteURLContexts(connectionOptions.URLContexts);
}

static void BTPluginSceneOpenURLs(id self, SEL command, UIScene *scene,
	NSSet<UIOpenURLContext *> *URLContexts) API_AVAILABLE(ios(13.0)) {
	BTPluginRouteURLContexts(URLContexts);
	if (BTOriginalSceneOpenURLs)
		BTOriginalSceneOpenURLs(self, command, scene, URLContexts);
}

static IMP BTPluginReplaceMethod(Class targetClass, SEL selector, IMP replacement,
	const char *fallbackTypes) {
	Method existingMethod = class_getInstanceMethod(targetClass, selector);
	IMP existingImplementation = existingMethod ? method_getImplementation(existingMethod) : NULL;
	const char *types = existingMethod ? method_getTypeEncoding(existingMethod) : fallbackTypes;
	if (existingImplementation == replacement)
		return replacement;
	class_replaceMethod(targetClass, selector, replacement, types);
	return existingImplementation;
}

BOOL BTPluginInstallApplicationIntegration(NSString *applicationDelegateClassName, NSError **error) {
	if (![NSThread isMainThread])
		return BTPluginIntegrationFail(error, @"Plug-in application integration must be installed on the main thread.");
	if (![applicationDelegateClassName isKindOfClass:[NSString class]] || applicationDelegateClassName.length == 0)
		return BTPluginIntegrationFail(error, @"The runtime application delegate class name is missing.");

	static BOOL installed = NO;
	@synchronized ([BTPluginPlatform class]) {
		if (installed)
			return YES;
		Class applicationDelegateClass = NSClassFromString(applicationDelegateClassName);
		if (!applicationDelegateClass)
			return BTPluginIntegrationFail(error, @"Battman's runtime application delegate class was not registered.");

		SEL didFinishSelector = @selector(application:didFinishLaunchingWithOptions:);
		Method didFinishMethod = class_getInstanceMethod(applicationDelegateClass, didFinishSelector);
		if (!didFinishMethod)
			return BTPluginIntegrationFail(error, @"Battman's application delegate has no launch method to preserve.");

		// Validate every required class and preservation point before changing
		// any method. A failed iOS 13 scene lookup must not leave only half of
		// the import routes installed.
		Class sceneDelegateClass = Nil;
		Method connectMethod = NULL;
		if (@available(iOS 13.0, *)) {
			sceneDelegateClass = NSClassFromString(@"SceneDelegate");
			if (!sceneDelegateClass)
				return BTPluginIntegrationFail(error, @"Battman's runtime scene delegate class was not registered.");
			connectMethod = class_getInstanceMethod(sceneDelegateClass,
				@selector(scene:willConnectToSession:options:));
			if (!connectMethod)
				return BTPluginIntegrationFail(error, @"Battman's scene delegate has no connection method to preserve.");
		}

		IMP oldDidFinish = BTPluginReplaceMethod(applicationDelegateClass, didFinishSelector,
			(IMP)BTPluginDidFinishLaunching, "B@:@@");
		if (oldDidFinish != (IMP)BTPluginDidFinishLaunching)
			BTOriginalDidFinishLaunching = (BTPluginDidFinishLaunchingIMP)oldDidFinish;

		SEL openURLSelector = @selector(application:openURL:options:);
		IMP oldOpenURL = BTPluginReplaceMethod(applicationDelegateClass, openURLSelector,
			(IMP)BTPluginApplicationOpenURL, "B@:@@@");
		if (oldOpenURL != (IMP)BTPluginApplicationOpenURL)
			BTOriginalOpenURL = (BTPluginOpenURLIMP)oldOpenURL;

		if (@available(iOS 13.0, *)) {
			SEL connectSelector = @selector(scene:willConnectToSession:options:);
			IMP oldConnect = BTPluginReplaceMethod(sceneDelegateClass, connectSelector,
				(IMP)BTPluginSceneWillConnect, "v@:@@@");
			if (oldConnect != (IMP)BTPluginSceneWillConnect)
				BTOriginalSceneConnect = (BTPluginSceneConnectIMP)oldConnect;

			SEL openContextsSelector = @selector(scene:openURLContexts:);
			IMP oldSceneOpen = BTPluginReplaceMethod(sceneDelegateClass, openContextsSelector,
				(IMP)BTPluginSceneOpenURLs, "v@:@@");
			if (oldSceneOpen != (IMP)BTPluginSceneOpenURLs)
				BTOriginalSceneOpenURLs = (BTPluginSceneOpenURLsIMP)oldSceneOpen;
		}
		installed = YES;
	}
	return YES;
}
