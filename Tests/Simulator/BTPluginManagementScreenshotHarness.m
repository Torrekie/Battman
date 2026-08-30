//
//  BTPluginManagementScreenshotHarness.m
//  Battman release evidence
//
//  Renders the production plug-in management controller and its host-owned
//  warnings against immutable in-memory fixture state. The provider exposes no
//  real management service, Keychain, filesystem, verifier, or loader.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <unistd.h>

#import "../../Battman/PluginHost/Application/BTPluginPlatform.h"
#import "../../Battman/PluginHost/Management/BTPluginManagementService.h"
#import "../../Battman/PluginHost/UI/BTPluginManagementViewControllerInternal.h"

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

// The harness never uses the default production initializer. Supplying this
// inert class implementation makes an accidental call fail at the injected
// provider assertion instead of constructing the real process-wide platform.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation BTPluginPlatform
+ (instancetype)sharedPlatform { return nil; }
@end
#pragma clang diagnostic pop

@interface BTFixturePublisher : NSObject
@property (nonatomic, copy) NSString *primaryKeyIdentifier;
@end
@implementation BTFixturePublisher
@end

@interface BTFixtureAuthor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *homepageURL;
@property (nonatomic, copy) NSString *supportEmail;
@end
@implementation BTFixtureAuthor
@end

@interface BTFixtureExtensionPoint : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) uint32_t interfaceVersion;
@end
@implementation BTFixtureExtensionPoint
@end

@interface BTFixtureManifest : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *pluginIdentifier;
@property (nonatomic, copy) NSString *displayVersion;
@property (nonatomic, copy) NSString *buildVersion;
@property (nonatomic, strong) BTFixturePublisher *publisher;
@property (nonatomic, strong) BTFixtureAuthor *author;
@property (nonatomic, copy) NSArray<BTFixtureExtensionPoint *> *extensionPoints;
@end
@implementation BTFixtureManifest
@end

@interface BTFixtureInspection : NSObject
@property (nonatomic, strong) BTFixtureManifest *manifest;
@property (nonatomic, copy) NSString *packageSHA256;
@end
@implementation BTFixtureInspection
@end

@interface BTFixtureTrustEvaluation : NSObject
@property (nonatomic) BTPluginTrustDisposition disposition;
@end
@implementation BTFixtureTrustEvaluation
@end

@interface BTFixtureVerifiedPackage : NSObject
@property (nonatomic, strong) BTFixtureInspection *packageInspection;
@property (nonatomic, strong) BTFixtureTrustEvaluation *trustEvaluation;
@end
@implementation BTFixtureVerifiedPackage
@end

@interface BTFixtureDiscoveredPackage : NSObject
@property (nonatomic, copy) NSString *claimedPluginIdentifier;
@property (nonatomic) BTPluginSource source;
@end
@implementation BTFixtureDiscoveredPackage
@end

@interface BTFixtureActivationRecord : NSObject
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end
@implementation BTFixtureActivationRecord
@end

@interface BTFixtureInstalledPackage : NSObject
@property (nonatomic, strong) BTFixtureDiscoveredPackage *discoveredPackage;
@property (nonatomic, strong) BTFixtureVerifiedPackage *verifiedPackage;
@property (nonatomic, strong) BTFixtureActivationRecord *activationRecord;
@property (nonatomic, strong) NSError *verificationError;
@end
@implementation BTFixtureInstalledPackage
@end

@interface BTFixtureQuarantinedPackage : NSObject
@property (nonatomic, strong) BTFixtureVerifiedPackage *verification;
@end
@implementation BTFixtureQuarantinedPackage
@end

@interface BTFixtureRecovery : NSObject
@property (nonatomic, copy) NSString *pluginIdentifier;
@end
@implementation BTFixtureRecovery
@end

@interface BTFixtureSnapshot : NSObject
@property (nonatomic, getter=areThirdPartyPluginsEnabled) BOOL thirdPartyPluginsEnabled;
@property (nonatomic, getter=isSafeMode) BOOL safeMode;
@property (nonatomic, strong) BTFixtureRecovery *recovery;
@property (nonatomic, copy) NSArray<BTFixtureQuarantinedPackage *> *quarantinedPackages;
@property (nonatomic, copy) NSArray<BTFixtureInstalledPackage *> *installedPackages;
@property (nonatomic, copy) NSArray<NSError *> *diagnostics;
@property (nonatomic, strong) NSDate *generatedAt;
@end
@implementation BTFixtureSnapshot
@end

@interface BTFixturePlatformProvider : NSObject <BTPluginManagementPlatformProviding>
@property (nonatomic, strong) BTFixtureSnapshot *snapshot;
@property (nonatomic) NSUInteger safeModeRequestCount;
@end

@implementation BTFixturePlatformProvider

- (BTPluginManagementService *)managementService { return nil; }

- (BTPluginManagementSnapshot *)currentManagementSnapshotWithError:(NSError **)error {
	if (error)
		*error = nil;
	return (BTPluginManagementSnapshot *)(id)self.snapshot;
}

- (BOOL)requestSafeModeForNextLaunchWithError:(NSError **)error {
	if (error)
		*error = nil;
	self.safeModeRequestCount++;
	return YES;
}

@end

@interface BTFixtureUIContext : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, strong) BTPluginManagementViewController *managementController;
@property (nonatomic, strong) BTFixturePlatformProvider *provider;
@end
@implementation BTFixtureUIContext
@end

static NSString *BTRepeatedCharacter(unichar character) {
	return [@"" stringByPaddingToLength:64 withString:[NSString stringWithCharacters:&character length:1]
		startingAtIndex:0];
}

static BTFixtureVerifiedPackage *BTVerifiedPackage(NSString *displayName,
	NSString *pluginIdentifier, unichar publisherCharacter, unichar packageCharacter,
	BTPluginTrustDisposition disposition) {
	BTFixturePublisher *publisher = [BTFixturePublisher new];
	publisher.primaryKeyIdentifier = BTRepeatedCharacter(publisherCharacter);
	BTFixtureAuthor *author = [BTFixtureAuthor new];
	author.name = disposition == BTPluginTrustDispositionOfficial ? @"Torrekie" : @"Cycle Labs";
	author.homepageURL = disposition == BTPluginTrustDispositionOfficial ?
		@"https://github.com/Torrekie/Battman" : @"https://example.com/cycle-rings";
	author.supportEmail = disposition == BTPluginTrustDispositionOfficial ?
		@"me@torrekie.dev" : @"support@example.com";
	BTFixtureExtensionPoint *extensionPoint = [BTFixtureExtensionPoint new];
	extensionPoint.identifier = @"com.torrekie.battman.analytics.card.v1";
	extensionPoint.interfaceVersion = 1;
	BTFixtureManifest *manifest = [BTFixtureManifest new];
	manifest.displayName = displayName;
	manifest.pluginIdentifier = pluginIdentifier;
	manifest.displayVersion = @"1.0.0";
	manifest.buildVersion = @"1";
	manifest.publisher = publisher;
	manifest.author = author;
	manifest.extensionPoints = @[ extensionPoint ];
	BTFixtureInspection *inspection = [BTFixtureInspection new];
	inspection.manifest = manifest;
	inspection.packageSHA256 = BTRepeatedCharacter(packageCharacter);
	BTFixtureTrustEvaluation *trust = [BTFixtureTrustEvaluation new];
	trust.disposition = disposition;
	BTFixtureVerifiedPackage *verified = [BTFixtureVerifiedPackage new];
	verified.packageInspection = inspection;
	verified.trustEvaluation = trust;
	return verified;
}

static BTFixtureSnapshot *BTCreateSnapshot(void) {
	BTFixtureVerifiedPackage *official = BTVerifiedPackage(@"Charge Gauge",
		@"com.torrekie.battman.plugin.charge-gauge", 'c', 'd', BTPluginTrustDispositionOfficial);
	BTFixtureDiscoveredPackage *discovered = [BTFixtureDiscoveredPackage new];
	discovered.claimedPluginIdentifier = official.packageInspection.manifest.pluginIdentifier;
	discovered.source = BTPluginSourceRootlessSystem;
	BTFixtureActivationRecord *activation = [BTFixtureActivationRecord new];
	activation.enabled = YES;
	BTFixtureInstalledPackage *installed = [BTFixtureInstalledPackage new];
	installed.discoveredPackage = discovered;
	installed.verifiedPackage = official;
	installed.activationRecord = activation;

	BTFixtureVerifiedPackage *thirdParty = BTVerifiedPackage(@"Community Cycle Rings",
		@"com.example.battman.cycle-rings", 'a', 'b', BTPluginTrustDispositionRequiresApproval);
	BTFixtureQuarantinedPackage *quarantine = [BTFixtureQuarantinedPackage new];
	quarantine.verification = thirdParty;
	BTFixtureRecovery *recovery = [BTFixtureRecovery new];
	recovery.pluginIdentifier = @"com.example.battman.last-loaded";

	BTFixtureSnapshot *snapshot = [BTFixtureSnapshot new];
	snapshot.thirdPartyPluginsEnabled = NO;
	snapshot.safeMode = NO;
	snapshot.recovery = recovery;
	snapshot.installedPackages = @[ installed ];
	snapshot.quarantinedPackages = @[ quarantine ];
	snapshot.diagnostics = @[
		[NSError errorWithDomain:@"com.torrekie.Battman.PluginPackage" code:17 userInfo:nil],
	];
	snapshot.generatedAt = [NSDate dateWithTimeIntervalSince1970:1700000000];
	return snapshot;
}

static void BTPumpRunLoop(NSTimeInterval interval) {
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:interval];
	while (deadline.timeIntervalSinceNow > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static BTFixtureUIContext *BTCreateContext(void) {
	BTFixturePlatformProvider *provider = [BTFixturePlatformProvider new];
	provider.snapshot = BTCreateSnapshot();
	BTPluginManagementViewController *management = [[BTPluginManagementViewController alloc]
		initWithPlatformProvider:provider
		initialSnapshot:(BTPluginManagementSnapshot *)(id)provider.snapshot];
	UINavigationController *navigation = [[UINavigationController alloc]
		initWithRootViewController:management];
	UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
	window.backgroundColor = [UIColor whiteColor];
	window.rootViewController = navigation;
	[window makeKeyAndVisible];
	[navigation.view setFrame:window.bounds];
	BTPumpRunLoop(0.05);
	[window setNeedsLayout];
	[window layoutIfNeeded];
	BTFixtureUIContext *context = [BTFixtureUIContext new];
	context.window = window;
	context.navigationController = navigation;
	context.managementController = management;
	context.provider = provider;
	return context;
}

static BOOL BTWaitForPresentation(UIViewController *controller) {
	for (NSUInteger attempt = 0; attempt < 100; attempt++) {
		UIViewController *presented = controller.presentedViewController;
		UIView *container = presented.presentationController.containerView;
		if (presented && presented.view.window && container.window) {
			BTPumpRunLoop(0.05);
			return YES;
		}
		BTPumpRunLoop(0.01);
	}
	return NO;
}

static NSData *BTRenderWindow(UIWindow *window) {
	[window setNeedsLayout];
	[window layoutIfNeeded];
	BTPumpRunLoop(0.05);
	UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 2.0);
	BOOL rendered = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
	if (!rendered)
		[window.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return UIImagePNGRepresentation(image);
}

static BOOL BTWriteScreenshot(UIWindow *window, NSString *outputDirectory, NSString *name) {
	NSData *data = BTRenderWindow(window);
	if (!data.length)
		return NO;
	NSString *path = [outputDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@.png", name]];
	BOOL directory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory)
		return NO;
	return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static BOOL BTWritePresentedScreenshot(UIWindow *window, UIViewController *presented,
	NSString *outputDirectory, NSString *name) {
	UIView *container = presented.presentationController.containerView;
	if (!container || !container.window)
		return NO;
	[window setNeedsLayout];
	[window layoutIfNeeded];
	[container setNeedsLayout];
	[container layoutIfNeeded];
	BTPumpRunLoop(0.05);
	UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 2.0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	[window.layer renderInContext:context];
	CGContextSaveGState(context);
	CGPoint origin = [container convertPoint:CGPointZero toView:window];
	CGContextTranslateCTM(context, origin.x, origin.y);
	[container.layer renderInContext:context];
	CGContextRestoreGState(context);
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	NSData *data = UIImagePNGRepresentation(image);
	if (!data.length)
		return NO;
	NSString *path = [outputDirectory stringByAppendingPathComponent:
		[NSString stringWithFormat:@"%@.png", name]];
	BOOL directory = NO;
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory)
		return NO;
	return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static void BTCloseContext(BTFixtureUIContext *context) {
	context.window.hidden = YES;
	context.window.rootViewController = nil;
	BTPumpRunLoop(0.02);
}

static UIAlertController *BTPresentedAlert(UIViewController *controller) {
	if (!BTWaitForPresentation(controller))
		return nil;
	return [controller.presentedViewController isKindOfClass:[UIAlertController class]] ?
		(UIAlertController *)controller.presentedViewController : nil;
}

static BOOL BTAlertHasAction(UIAlertController *alert, NSString *title, UIAlertActionStyle style) {
	for (UIAlertAction *action in alert.actions) {
		if ([action.title isEqualToString:title] && action.style == style)
			return YES;
	}
	return NO;
}

static int BTRunEvidence(NSString *outputDirectory) {
	@autoreleasepool {
		BOOL directory = NO;
		BTRequire([[NSFileManager defaultManager] fileExistsAtPath:outputDirectory
			isDirectory:&directory] && directory, @"output directory is unavailable");
		BTRequire([NSThread isMainThread], @"UIKit evidence harness must run on the main thread");
		[UIView setAnimationsEnabled:NO];

		BTFixtureUIContext *overview = BTCreateContext();
		BTPluginManagementViewController *management = overview.managementController;
		BTRequire([management.title isEqualToString:@"Plug-ins"], @"management title drifted");
		BTRequire([management tableView:management.tableView numberOfRowsInSection:0] == 2,
			@"security section row contract drifted");
		BTRequire([management tableView:management.tableView numberOfRowsInSection:1] == 1,
			@"recovery row is absent");
		BTRequire([management tableView:management.tableView numberOfRowsInSection:2] == 1,
			@"installed fixture row is absent");
		BTRequire([management tableView:management.tableView numberOfRowsInSection:3] == 1,
			@"quarantine fixture row is absent");
		UITableViewCell *installedCell = [management tableView:management.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
		BTRequire([installedCell.textLabel.text isEqualToString:@"Charge Gauge"] &&
			[installedCell.detailTextLabel.text containsString:@"Official"],
			@"official installed state drifted");
		UITableViewCell *quarantineCell = [management tableView:management.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
		BTRequire([quarantineCell.textLabel.text isEqualToString:@"Community Cycle Rings"] &&
			[quarantineCell.detailTextLabel.text isEqualToString:@"Approval Required"],
			@"quarantine approval state drifted");
		BTRequire(BTWriteScreenshot(overview.window, outputDirectory,
			@"plugin-1.1.0-management-overview"), @"could not render management overview");
		BTCloseContext(overview);

		BTFixtureUIContext *globalConsent = BTCreateContext();
		UITableViewCell *switchCell = [globalConsent.managementController tableView:
			globalConsent.managementController.tableView cellForRowAtIndexPath:
			[NSIndexPath indexPathForRow:0 inSection:0]];
		UISwitch *toggle = [switchCell.accessoryView isKindOfClass:[UISwitch class]] ?
			(UISwitch *)switchCell.accessoryView : nil;
	BTRequire(toggle != nil, @"third-party switch is absent");
	toggle.on = YES;
	perform_selector(NSSelectorFromString(@"thirdPartySwitchChanged:"),
		globalConsent.managementController, toggle);
	UIAlertController *enableAlert = BTPresentedAlert(globalConsent.managementController);
	NSMutableArray<NSString *> *enableActionTitles = [NSMutableArray array];
	for (UIAlertAction *action in enableAlert.actions)
		[enableActionTitles addObject:[NSString stringWithFormat:@"%@/%ld", action.title, (long)action.style]];
	NSString *enableFailure = [NSString stringWithFormat:
		@"global dangerous-load consent drifted: title=%@ message=%@ actions=%@ presented=%@",
		enableAlert.title, enableAlert.message, enableActionTitles,
		globalConsent.managementController.presentedViewController];
	BTRequire([enableAlert.title isEqualToString:@"Enable Third-Party Plug-ins?"] &&
		[enableAlert.message containsString:@"without isolation"] &&
		BTAlertHasAction(enableAlert, @"Cancel", UIAlertActionStyleCancel) &&
		BTAlertHasAction(enableAlert, @"I Understand, Enable", UIAlertActionStyleDestructive),
		enableFailure);
		BTRequire(BTWritePresentedScreenshot(globalConsent.window, enableAlert, outputDirectory,
			@"plugin-1.1.0-management-third-party-consent"), @"could not render global consent");
		BTCloseContext(globalConsent);

		BTFixtureUIContext *details = BTCreateContext();
		[details.managementController tableView:details.managementController.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
		BTPumpRunLoop(0.05);
		UITableViewController *detail = [details.navigationController.topViewController
			isKindOfClass:[UITableViewController class]] ?
			(UITableViewController *)details.navigationController.topViewController : nil;
		BTRequire(detail != nil && detail != details.managementController &&
			[detail.title isEqualToString:@"Plug-in Details"], @"package detail navigation failed");
		[detail.tableView layoutIfNeeded];
		UITableViewCell *nameCell = [detail.tableView.dataSource tableView:detail.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
		BTRequire([nameCell.detailTextLabel.text isEqualToString:@"Community Cycle Rings"],
			@"package detail identity drifted");
		UITableViewCell *authorCell = [detail.tableView.dataSource tableView:detail.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
		BTRequire([authorCell.textLabel.text isEqualToString:@"Author"] &&
			[authorCell.detailTextLabel.text isEqualToString:@"Cycle Labs"],
			@"package author identity drifted");
		UITableViewCell *technicalCell = [detail.tableView.dataSource tableView:detail.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
		BTRequire([technicalCell.textLabel.text isEqualToString:@"View Verification Details"],
			@"technical-details disclosure row drifted");
		BTRequire(BTWriteScreenshot(details.window, outputDirectory,
			@"plugin-1.1.0-management-package-details"), @"could not render package details");
		[detail.tableView.delegate tableView:detail.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];
		BTPumpRunLoop(0.05);
		UITableViewController *technical = [details.navigationController.topViewController
			isKindOfClass:[UITableViewController class]] ?
			(UITableViewController *)details.navigationController.topViewController : nil;
		BTRequire(technical != nil && [technical.title isEqualToString:@"Technical Details"],
			@"technical-details navigation failed");
		UITableViewCell *fingerprintCell = [technical.tableView.dataSource tableView:technical.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
		UITableViewCell *digestCell = [technical.tableView.dataSource tableView:technical.tableView
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
		BTRequire([fingerprintCell.detailTextLabel.text isEqualToString:@"aaaaaaaa…aaaaaaaa"] &&
			[digestCell.detailTextLabel.text isEqualToString:@"bbbbbbbb…bbbbbbbb"],
			@"technical identifiers are not bounded for display");
		BTRequire(BTWriteScreenshot(details.window, outputDirectory,
			@"plugin-1.1.0-management-technical-details"),
			@"could not render technical details");
		[technical.tableView.delegate tableView:technical.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
		BTRequire([[UIPasteboard generalPasteboard].string isEqualToString:BTRepeatedCharacter('a')],
			@"full publisher fingerprint was not copyable");
		[details.navigationController popViewControllerAnimated:NO];
		[detail.tableView.delegate tableView:detail.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
		UIAlertController *buildAlert = BTPresentedAlert(detail);
		BTRequire([buildAlert.title isEqualToString:@"Allow This Version?"] &&
			[buildAlert.message containsString:@"com.example.battman.cycle-rings"] &&
			[buildAlert.message containsString:@"Cycle Labs"] &&
			[buildAlert.message containsString:@"aaaaaaaa…aaaaaaaa"] &&
			[buildAlert.message containsString:@"bbbbbbbb…bbbbbbbb"] &&
			[buildAlert.message containsString:@"com.torrekie.battman.analytics.card.v1"] &&
			[buildAlert.message containsString:@"Nothing loads until Battman restarts."] &&
			BTAlertHasAction(buildAlert, @"Allow Version and Schedule", UIAlertActionStyleDestructive),
			@"exact-build dangerous-load consent drifted");
		BTRequire(BTWritePresentedScreenshot(details.window, buildAlert, outputDirectory,
			@"plugin-1.1.0-management-exact-build-consent"), @"could not render build consent");
		BTCloseContext(details);

		BTFixtureUIContext *safeMode = BTCreateContext();
		[safeMode.managementController tableView:safeMode.managementController.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
		UIAlertController *safeAlert = BTPresentedAlert(safeMode.managementController);
		BTRequire(safeMode.provider.safeModeRequestCount == 1 &&
			[safeAlert.title isEqualToString:@"Safe Mode Scheduled"] &&
			[safeAlert.message containsString:@"skip all third-party plug-ins once"],
			@"safe-mode confirmation drifted");
		BTRequire(BTWritePresentedScreenshot(safeMode.window, safeAlert, outputDirectory,
			@"plugin-1.1.0-management-safe-mode"), @"could not render safe-mode confirmation");
		BTCloseContext(safeMode);

		BTFixtureUIContext *diagnostics = BTCreateContext();
		[diagnostics.managementController tableView:diagnostics.managementController.tableView
			didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]];
		UIAlertController *diagnosticAlert = BTPresentedAlert(diagnostics.managementController);
		BTRequire([diagnosticAlert.title isEqualToString:@"Review Diagnostics Before Sharing"] &&
			[diagnosticAlert.message containsString:@"It excludes plug-in files, private keys"] &&
			[diagnosticAlert.message containsString:@"device identifiers, and filesystem paths"] &&
			BTAlertHasAction(diagnosticAlert, @"Continue", UIAlertActionStyleDefault),
			@"diagnostic disclosure drifted");
		BTRequire(BTWritePresentedScreenshot(diagnostics.window, diagnosticAlert, outputDirectory,
			@"plugin-1.1.0-management-diagnostics-disclosure"),
			@"could not render diagnostic disclosure");
		BTCloseContext(diagnostics);

		printf("Production plug-in management, consent, recovery, and diagnostic screenshots rendered.\n");
	}
	return 0;
}

@interface BTPluginManagementEvidenceAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation BTPluginManagementEvidenceAppDelegate

- (BOOL)application:(UIApplication *)application
	didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
	(void)application;
	(void)launchOptions;
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [UIViewController new];
	self.window.backgroundColor = [UIColor blackColor];
	[self.window makeKeyAndVisible];
	dispatch_async(dispatch_get_main_queue(), ^{
		NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
		NSString *outputDirectory = environment[@"BATTMAN_EVIDENCE_OUTPUT_DIR"];
		if (!outputDirectory.length)
			outputDirectory = NSSearchPathForDirectoriesInDomains(
				NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		int result = BTRunEvidence(outputDirectory);
		NSString *statusPath = [outputDirectory stringByAppendingPathComponent:
			@"plugin-management-evidence.status"];
		NSString *status = result == 0 ? @"PASS\n" : @"FAIL\n";
		[status writeToFile:statusPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
		fflush(stdout);
		fflush(stderr);
		_exit(result);
	});
	return YES;
}

@end


int main(int argc, char *argv[]) {
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil,
			NSStringFromClass([BTPluginManagementEvidenceAppDelegate class]));
	}
}
