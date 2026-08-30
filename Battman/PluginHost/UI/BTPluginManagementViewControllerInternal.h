//
//  BTPluginManagementViewControllerInternal.h
//  Battman
//
//  Host-internal dependency seam for deterministic UI evidence and tests.
//  This is not part of PluginSDK or the public native plug-in ABI.
//

#import "BTPluginManagementViewController.h"

@class BTPluginManagementService;
@class BTPluginManagementSnapshot;
@class BTPluginVerifiedPackage;
@class BTPluginPackageManifest;

NS_ASSUME_NONNULL_BEGIN

@protocol BTPluginManagementPlatformProviding <NSObject>
@property (nonatomic, strong, readonly, nullable) BTPluginManagementService *managementService;
- (nullable BTPluginManagementSnapshot *)currentManagementSnapshotWithError:
	(NSError * _Nullable * _Nullable)error;
- (BOOL)requestSafeModeForNextLaunchWithError:(NSError * _Nullable * _Nullable)error;
@end

@interface BTPluginManagementViewController (BTPluginManagementInternal)
- (instancetype)initWithPlatformProvider:(id<BTPluginManagementPlatformProviding>)platformProvider;
- (instancetype)initWithPlatformProvider:(id<BTPluginManagementPlatformProviding>)platformProvider
	initialSnapshot:(nullable BTPluginManagementSnapshot *)initialSnapshot;
@end

extern __attribute__((visibility("hidden"))) UIAlertController *
BTPluginCreateDangerousLoadConsentAlert(BTPluginVerifiedPackage *verifiedPackage,
	BOOL publisherTrust, dispatch_block_t approvalHandler);
extern __attribute__((visibility("hidden"))) UIAlertController *
BTPluginCreateDangerousLoadConsentAlertWithPriorManifest(BTPluginVerifiedPackage *verifiedPackage,
	BTPluginPackageManifest * _Nullable priorManifest,
	NSString * _Nullable comparisonMessage, BOOL publisherTrust, dispatch_block_t approvalHandler);
extern __attribute__((visibility("hidden"))) UIAlertController *
BTPluginCreateThirdPartyEnableConsentAlert(dispatch_block_t enableHandler);
extern __attribute__((visibility("hidden"))) UIAlertController *
BTPluginCreateSafeModeScheduledAlert(void);
extern __attribute__((visibility("hidden"))) UIAlertController *
BTPluginCreateDiagnosticDisclosureAlert(dispatch_block_t continueHandler);

NS_ASSUME_NONNULL_END
