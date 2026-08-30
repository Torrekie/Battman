//
//  BTPluginManagementService.h
//  Battman
//
//  Offline approval, restart-only activation, and bounded removal orchestration.
//  This layer never maps code and never mutates app-bundle or dpkg payloads.
//

#import <Foundation/Foundation.h>

#import "../Discovery/BTPluginDiscovery.h"
#import "../Import/BTPluginApplicationDataStore.h"
#import "../Runtime/BTPluginActivationStore.h"
#import "../Runtime/BTPluginRuntimeEnvironment.h"
#import "../Security/BTPluginTrustStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginManagementActionOutcome) {
	BTPluginManagementActionOutcomeScheduledForNextLaunch = 1,
	BTPluginManagementActionOutcomeRequiresReplacementApp = 2,
};

typedef NS_ENUM(NSUInteger, BTPluginPriorVersionComparisonStatus) {
	BTPluginPriorVersionComparisonStatusAvailable = 1,
	BTPluginPriorVersionComparisonStatusNoInstalledVersion = 2,
	BTPluginPriorVersionComparisonStatusAmbiguousInstalledRepresentations = 3,
	BTPluginPriorVersionComparisonStatusPriorVerificationFailed = 4,
	BTPluginPriorVersionComparisonStatusPriorNotApproved = 5,
	BTPluginPriorVersionComparisonStatusActivationMismatch = 6,
	BTPluginPriorVersionComparisonStatusPublisherChanged = 7,
	BTPluginPriorVersionComparisonStatusCandidateNotNewer = 8,
	BTPluginPriorVersionComparisonStatusUnavailable = 9,
};

@interface BTPluginManagementActionResult : NSObject
@property (nonatomic, readonly) BTPluginManagementActionOutcome outcome;
@property (nonatomic, strong, readonly) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, strong, readonly, nullable) NSURL *installedPackageURL;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManagedInstalledPackage : NSObject
@property (nonatomic, strong, readonly) BTPluginDiscoveredPackage *discoveredPackage;
@property (nonatomic, strong, readonly, nullable) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, strong, readonly, nullable) BTPluginActivationRecord *activationRecord;
@property (nonatomic, strong, readonly, nullable) NSError *verificationError;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManagementSnapshot : NSObject
@property (nonatomic, readonly, getter=areThirdPartyPluginsEnabled) BOOL thirdPartyPluginsEnabled;
@property (nonatomic, readonly, getter=isSafeMode) BOOL safeMode;
@property (nonatomic, strong, readonly, nullable) BTPluginStartupRecovery *recovery;
@property (nonatomic, copy, readonly) NSArray<BTPluginQuarantinedPackage *> *quarantinedPackages;
@property (nonatomic, copy, readonly) NSArray<BTPluginManagedInstalledPackage *> *installedPackages;
@property (nonatomic, copy, readonly) NSArray<NSError *> *diagnostics;
@property (nonatomic, strong, readonly) NSDate *generatedAt;
- (instancetype)init NS_UNAVAILABLE;
@end

// Derives an informational extension-point comparison from a complete
// management snapshot. Every same-ID discovered representation participates in
// ambiguity detection, including entries that failed verification. The result
// never grants trust or activation authority.
FOUNDATION_EXPORT BTPluginPriorVersionComparisonStatus
BTPluginPriorVersionComparisonForCandidate(BTPluginVerifiedPackage *candidate,
	NSArray<BTPluginManagedInstalledPackage *> *installedPackages,
	BTPluginPackageManifest * _Nullable * _Nullable priorManifest);

@interface BTPluginManagementService : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
											 trustStore:(id<BTPluginTrustStore>)trustStore
								 activationStore:(id<BTPluginActivationStore>)activationStore
						 applicationDataStore:(BTPluginApplicationDataStore *)applicationDataStore
								 quarantineStore:(BTPluginQuarantineStore *)quarantineStore
										environment:(BTPluginRuntimeEnvironment *)environment
									 discoveryRoots:(NSArray<BTPluginDiscoveryRoot *> *)discoveryRoots NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginManagementSnapshot *)managementSnapshotWithStartupSnapshot:
	(nullable BTPluginStartupSnapshot *)startupSnapshot error:(NSError * _Nullable * _Nullable)error;

// Replays or safely abandons a pending app-data transaction before the
// immutable startup snapshot is created. This is idempotent and never maps
// native code.
- (BOOL)reconcilePendingApplicationDataTransactionWithError:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginVerifiedPackage *)refreshQuarantinedPackage:(BTPluginQuarantinedPackage *)package
																							 error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginManagementActionResult *)allowExactBuildAndScheduleQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginManagementActionResult *)trustPublisherAndScheduleQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginManagementActionResult *)installAlreadyTrustedQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginVerifiedPackage *)refreshDiscoveredPackage:(BTPluginDiscoveredPackage *)package
	error:(NSError * _Nullable * _Nullable)error;
- (nullable BTPluginManagementActionResult *)allowExactBuildAndScheduleDiscoveredPackage:
	(BTPluginDiscoveredPackage *)package error:(NSError * _Nullable * _Nullable)error;
- (nullable BTPluginManagementActionResult *)trustPublisherAndScheduleDiscoveredPackage:
	(BTPluginDiscoveredPackage *)package error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setInstalledPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setDiscoveredPackage:(BTPluginDiscoveredPackage *)package enabled:(BOOL)enabled
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)disableRecoveredPlugin:(BTPluginStartupRecovery *)recovery
	error:(NSError * _Nullable * _Nullable)error;

- (BOOL)removeDiscoveredPackage:(BTPluginDiscoveredPackage *)package
	expectedPackageSHA256:(NSString *)packageSHA256
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeQuarantinedPackage:(BTPluginQuarantinedPackage *)package
	error:(NSError * _Nullable * _Nullable)error;

- (BOOL)revokeExactBuildForPackageSHA256:(NSString *)packageSHA256
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)revokePublisherKeyIdentifier:(NSString *)keyIdentifier
	error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
