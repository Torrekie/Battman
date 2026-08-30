//
//  BTPluginImportPresenter.m
//  Battman
//

#import "BTPluginImportPresenter.h"

#import <UIKit/UIKit.h>

#import "BTPluginManagementViewController.h"
#import "../Import/BTPluginImportCoordinator.h"
#import "../Model/BTPluginPackageManifest.h"
#include "../../common.h"

extern id gWindow;
extern id find_top_controller(id rootVC);

static const NSUInteger BTPluginImportPresenterMaximumPendingResults = 8;

@interface BTPluginImportPresenter ()
@property (nonatomic, strong) NSMutableArray<NSNotification *> *pendingNotifications;
@property (nonatomic) BOOL observing;
@property (nonatomic) BOOL presenting;
@end

@implementation BTPluginImportPresenter

+ (instancetype)sharedPresenter {
	static BTPluginImportPresenter *presenter = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		presenter = [BTPluginImportPresenter new];
		presenter.pendingNotifications = [NSMutableArray array];
	});
	return presenter;
}

- (void)startObserving {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self startObserving]; });
		return;
	}
	if (self.observing)
		return;
	self.observing = YES;
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(importDidFinish:)
		name:BTPluginImportDidFinishNotification object:nil];
	[center addObserver:self selector:@selector(applicationDidBecomeActive:)
		name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)importDidFinish:(NSNotification *)notification {
	if (self.pendingNotifications.count >= BTPluginImportPresenterMaximumPendingResults)
		[self.pendingNotifications removeObjectAtIndex:0];
	[self.pendingNotifications addObject:notification];
	[self presentNextIfPossible];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	(void)notification;
	[self presentNextIfPossible];
}

- (UIViewController *)availablePresenter {
	UIWindow *window = [gWindow isKindOfClass:[UIWindow class]] ? gWindow : nil;
	if (!window)
		window = UIApplication.sharedApplication.keyWindow;
	UIViewController *top = window ? find_top_controller(window.rootViewController) : nil;
	if (!top || top.presentedViewController)
		return nil;
	return top;
}

- (void)presentNextIfPossible {
	if (self.presenting || self.pendingNotifications.count == 0 ||
		UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
		return;
	UIViewController *presenter = [self availablePresenter];
	if (!presenter)
		return;
	NSNotification *notification = self.pendingNotifications.firstObject;
	[self.pendingNotifications removeObjectAtIndex:0];
	BTPluginImportResult *result = notification.userInfo[BTPluginImportResultUserInfoKey];
	NSError *error = notification.userInfo[BTPluginImportErrorUserInfoKey];
	NSString *title = nil;
	NSString *message = nil;
	if (result) {
		BTPluginPackageManifest *manifest = result.quarantinedPackage.verification.packageInspection.manifest;
		title = _("Plug-in Quarantined");
		message = [NSString stringWithFormat:
			_("%@ %@ was verified without running its code and saved in Battman's private quarantine. It is not approved, installed, enabled, or loaded. Review its identity and requested extension points in Plug-ins."),
			manifest.displayName, manifest.displayVersion];
	} else {
		title = _("Plug-in Import Failed");
		message = error.localizedDescription ?: _("The selected package could not be verified and was not imported.");
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
		preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	void (^completion)(void) = ^{
		__strong typeof(weakSelf) self = weakSelf;
		self.presenting = NO;
		[self presentNextIfPossible];
	};
	[alert addAction:[UIAlertAction actionWithTitle:result ? _("Not Now") : _("OK")
		style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { (void)action; completion(); }]];
	if (result) {
		[alert addAction:[UIAlertAction actionWithTitle:_("Review Plug-in")
			style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				(void)action;
				BTPluginManagementViewController *management = [BTPluginManagementViewController new];
				UINavigationController *navigation = [[UINavigationController alloc]
					initWithRootViewController:management];
				management.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
					initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:management
					action:@selector(closePresentedManagement)];
				dispatch_async(dispatch_get_main_queue(), ^{
					[presenter presentViewController:navigation animated:YES completion:nil];
				});
				completion();
			}]];
	}
	self.presenting = YES;
	[presenter presentViewController:alert animated:YES completion:nil];
}

@end
