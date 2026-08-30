#import <Foundation/Foundation.h>

#import "../../Battman/PluginHost/Import/BTPluginQuarantineStore.h"
#import "../../Battman/PluginHost/Import/BTPluginImportCoordinator.h"
#import "../../Battman/PluginHost/Import/BTPluginApplicationDataStore.h"
#import "../../Battman/PluginHost/Management/BTPluginManagementService.h"
#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Security/BTPluginTrustEvaluator.h"
#import "../../Battman/PluginHost/Runtime/BTPluginApplicationDataTransaction.h"
#import "Fixtures/BTPluginSignedPackageFixture.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

@interface BTEmptyTrustStore : NSObject <BTPluginTrustStore>
@property (nonatomic) NSUInteger mutationCount;
@property (nonatomic, strong) BTPluginExactBuildApproval *exactApproval;
@property (nonatomic, strong) BTPluginPublisherApproval *publisherApproval;
@end

@interface BTMemoryActivationStore : NSObject <BTPluginActivationStore, BTPluginApplicationDataTransactionStore>
@property (nonatomic) BOOL thirdPartyEnabled;
@property (nonatomic) BOOL failNextSchedule;
@property (nonatomic) BOOL failNextRemove;
@property (nonatomic) BOOL failNextTransactionBegin;
@property (nonatomic) BOOL failNextTransactionFinish;
@property (nonatomic, strong) NSMutableDictionary<NSString *, BTPluginActivationRecord *> *records;
@property (nonatomic, strong) BTPluginApplicationDataTransaction *pendingTransaction;
@end

@implementation BTMemoryActivationStore
- (instancetype)init { self = [super init]; if (self) _records = [NSMutableDictionary dictionary]; return self; }
- (BOOL)thirdPartyPluginsEnabledWithError:(NSError **)error { (void)error; return self.thirdPartyEnabled; }
- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError **)error { (void)error; self.thirdPartyEnabled = enabled; return YES; }
- (NSArray<BTPluginActivationRecord *> *)activationRecordsWithError:(NSError **)error {
	(void)error;
	return [self.records.allValues sortedArrayUsingComparator:^NSComparisonResult(BTPluginActivationRecord *left,
		BTPluginActivationRecord *right) {
		return [left.pluginIdentifier compare:right.pluginIdentifier options:NSLiteralSearch];
	}];
}
- (BOOL)scheduleActivationRecord:(BTPluginActivationRecord *)record error:(NSError **)error {
	if (self.failNextSchedule) {
		self.failNextSchedule = NO;
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"Injected activation-record scheduling failure.", nil, nil);
		return NO;
	}
	(void)error;
	self.records[record.pluginIdentifier] = record;
	return YES;
}
- (BOOL)setPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled error:(NSError **)error {
	BTPluginActivationRecord *old = self.records[pluginIdentifier];
	if (!old) return NO;
	BTPluginActivationRecord *updated = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:old.pluginIdentifier packageSHA256:old.packageSHA256 source:old.source
		activationMode:old.activationMode enabled:enabled updatedAt:[NSDate date] error:error];
	if (!updated) return NO;
	self.records[pluginIdentifier] = updated;
	return YES;
}
- (BOOL)removePluginIdentifier:(NSString *)pluginIdentifier error:(NSError **)error {
	if (self.failNextRemove) {
		self.failNextRemove = NO;
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"Injected activation-record removal failure.", nil, nil);
		return NO;
	}
	(void)error;
	[self.records removeObjectForKey:pluginIdentifier];
	return YES;
}
- (BTPluginApplicationDataTransaction *)pendingApplicationDataTransactionWithError:(NSError **)error {
	(void)error;
	return self.pendingTransaction;
}
- (BOOL)beginApplicationDataTransaction:(BTPluginApplicationDataTransaction *)transaction
	 expectedActivationRecord:(BTPluginActivationRecord *)expectedActivationRecord error:(NSError **)error {
	if (self.failNextTransactionBegin) {
		self.failNextTransactionBegin = NO;
		if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			@"Injected transaction begin failure.", nil, nil);
		return NO;
	}
	if (self.pendingTransaction) {
		if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			@"A transaction is already pending.", nil, nil);
		return NO;
	}
	BTPluginActivationRecord *current = self.records[transaction.pluginIdentifier];
	if (current != expectedActivationRecord &&
		!([current.packageSHA256 isEqualToString:expectedActivationRecord.packageSHA256] &&
			current.source == expectedActivationRecord.source && current.activationMode == expectedActivationRecord.activationMode &&
			current.isEnabled == expectedActivationRecord.isEnabled)) {
		if (current || expectedActivationRecord) {
			if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"Activation state changed.", nil, nil);
			return NO;
		}
	}
	self.pendingTransaction = transaction;
	if (transaction.targetActivationRecord)
		self.records[transaction.pluginIdentifier] = transaction.targetActivationRecord;
	else
		[self.records removeObjectForKey:transaction.pluginIdentifier];
	return YES;
}
- (BOOL)finishApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier error:(NSError **)error {
	if (!self.pendingTransaction || ![self.pendingTransaction.transactionIdentifier isEqualToString:transactionIdentifier]) {
		if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			@"Stale transaction.", nil, nil);
		return NO;
	}
	if (self.failNextTransactionFinish) {
		self.failNextTransactionFinish = NO;
		if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			@"Injected transaction finish failure.", nil, nil);
		return NO;
	}
	self.pendingTransaction = nil;
	return YES;
}
- (BOOL)abortApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier error:(NSError **)error {
	if (!self.pendingTransaction || ![self.pendingTransaction.transactionIdentifier isEqualToString:transactionIdentifier]) {
		if (error) *error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			@"Stale transaction.", nil, nil);
		return NO;
	}
	BTPluginApplicationDataTransaction *transaction = self.pendingTransaction;
	if (transaction.previousActivationRecord)
		self.records[transaction.pluginIdentifier] = transaction.previousActivationRecord;
	else
		[self.records removeObjectForKey:transaction.pluginIdentifier];
	self.pendingTransaction = nil;
	return YES;
}
- (BTPluginStartupSnapshot *)beginStartupWithSafeModeRequested:(BOOL)safeModeRequested error:(NSError **)error { (void)safeModeRequested; (void)error; return nil; }
- (BOOL)recordThirdPartyLoadAttemptForPluginIdentifier:(NSString *)pluginIdentifier packageSHA256:(NSString *)packageSHA256 source:(BTPluginSource)source startupIdentifier:(NSString *)startupIdentifier error:(NSError **)error { (void)pluginIdentifier; (void)packageSHA256; (void)source; (void)startupIdentifier; (void)error; return YES; }
- (BOOL)markStartupSettledWithIdentifier:(NSString *)startupIdentifier error:(NSError **)error { (void)startupIdentifier; (void)error; return YES; }
- (BOOL)disablePluginFromRecovery:(BTPluginStartupRecovery *)recovery error:(NSError **)error { (void)recovery; (void)error; return NO; }
@end

@implementation BTEmptyTrustStore
- (BTPluginPublisherApproval *)publisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	(void)error;
	return [self.publisherApproval.keyIdentifier isEqualToString:keyIdentifier] ? self.publisherApproval : nil;
}
- (BTPluginExactBuildApproval *)exactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	(void)error;
	return [self.exactApproval.packageSHA256 isEqualToString:packageSHA256] ? self.exactApproval : nil;
}
- (uint64_t)highestReleaseSequenceForPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)pluginIdentifier; (void)publisherKeyIdentifier; (void)error; return 0;
}
- (NSString *)packageSHA256ForHighestReleaseOfPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)pluginIdentifier; (void)publisherKeyIdentifier; (void)error; return nil;
}
- (BOOL)storePublisherApproval:(BTPluginPublisherApproval *)approval error:(NSError **)error { (void)error; self.publisherApproval = approval; self.mutationCount++; return YES; }
- (BOOL)storeExactBuildApproval:(BTPluginExactBuildApproval *)approval error:(NSError **)error { (void)error; self.exactApproval = approval; self.mutationCount++; return YES; }
- (BOOL)recordReleaseSequence:(uint64_t)releaseSequence packageSHA256:(NSString *)packageSHA256 forPluginIdentifier:(NSString *)pluginIdentifier publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)releaseSequence; (void)packageSHA256; (void)pluginIdentifier; (void)publisherKeyIdentifier; (void)error; self.mutationCount++; return YES;
}
- (BOOL)removePublisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error { (void)keyIdentifier; (void)error; self.mutationCount++; return YES; }
- (BOOL)removeExactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error { (void)packageSHA256; (void)error; self.mutationCount++; return YES; }
@end

static BTPluginTrustPolicy *BTPolicyWithRevokedKeys(NSSet<NSString *> *revokedKeyIdentifiers) {
	NSError *error = nil;
	BTPluginTrustPolicy *policy = [[BTPluginTrustPolicy alloc]
		initWithOfficialPublicKeysByIdentifier:@{}
		officialScopesByKeyIdentifier:@{}
		revokedKeyIdentifiers:revokedKeyIdentifiers
		metadataSequence:1
		metadataUpdatedAt:[NSDate dateWithTimeIntervalSince1970:1]
		error:&error];
	BTAssert(policy != nil, error.localizedDescription.UTF8String);
	return policy;
}

static BTPluginTrustPolicy *BTEmptyPolicy(void) {
	return BTPolicyWithRevokedKeys([NSSet set]);
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTAssert(argc == 2, "expected signed constructor fixture path");
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-quarantine-tests-%@", NSUUID.UUID.UUIDString]]
			isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *sourceRootURL = [temporaryURL URLByAppendingPathComponent:@"Source" isDirectory:YES];
		NSURL *quarantineRootURL = [temporaryURL URLByAppendingPathComponent:@"Quarantine" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:sourceRootURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *fixtureURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		NSURL *packageURL = BTPluginTestCreateSignedPackage(sourceRootURL, fixtureURL,
			@"SignedNative.battman");
		NSString *sentinelPath = [temporaryURL.path stringByAppendingPathComponent:@"constructor-ran"];
		BTAssert(setenv("BT_PLUGIN_CONSTRUCTOR_SENTINEL", sentinelPath.fileSystemRepresentation, 1) == 0, "setenv failed");

		BTEmptyTrustStore *trustStore = [BTEmptyTrustStore new];
		BTPluginTrustEvaluator *evaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTEmptyPolicy() trustStore:trustStore];
		NSOperatingSystemVersion iOS17 = { .majorVersion = 17, .minorVersion = 2, .patchVersion = 0 };
		BTPluginPackageVerifier *verifier = [[BTPluginPackageVerifier alloc]
			initWithTrustEvaluator:evaluator hostIOSVersion:iOS17];
		BTPluginQuarantineStore *store = [[BTPluginQuarantineStore alloc]
			initWithRootURL:quarantineRootURL packageVerifier:verifier error:&error];
		BTAssert(store != nil, error.localizedDescription.UTF8String);
		BTPluginImportCoordinator *importCoordinator = [[BTPluginImportCoordinator alloc]
			initWithQuarantineStore:store];
		BTAssert(importCoordinator != nil, "import coordinator creation failed");
		BTAssert([importCoordinator canHandlePackageURL:packageURL], "valid local package URL was not accepted");
		BTAssert(![importCoordinator canHandlePackageURL:[NSURL URLWithString:@"https://example.com/Plugin.battman"]],
			"remote import URL was accepted");
		BTAssert(![importCoordinator canHandlePackageURL:[packageURL.URLByDeletingLastPathComponent
			URLByAppendingPathComponent:@"Plugin.BATTMAN" isDirectory:YES]],
			"non-canonical uppercase extension was accepted");

		BTPluginImportResult *importResult = [importCoordinator quarantineImportAtURL:packageURL
			developerMode:NO error:&error];
		BTPluginQuarantinedPackage *first = importResult.quarantinedPackage;
		BTAssert(first != nil, error.localizedDescription.UTF8String);
		BTAssert(!importResult.isApprovedByExistingTrust, "unknown import was reported as approved");
		BTAssert(!first.isApprovedForActivation &&
			first.verification.trustEvaluation.disposition == BTPluginTrustDispositionRequiresApproval,
			"unknown third-party quarantine import was activation-approved");
		BTAssert([first.packageURL.lastPathComponent isEqualToString:
			[first.verification.packageInspection.packageSHA256 stringByAppendingPathExtension:@"battman"]],
			"quarantine path is not content-addressed");
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during quarantine import");

		BTPluginQuarantinedPackage *second = [store quarantinePackageAtURL:packageURL developerMode:NO error:&error];
		BTAssert(second != nil && [second.packageURL isEqual:first.packageURL],
			"idempotent content-addressed quarantine import failed");
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during idempotent import");
		BTAssert(trustStore.mutationCount == 0,
			"import or quarantine changed trust or rollback state");
		NSArray<BTPluginQuarantinedPackage *> *inventory = [store
			quarantinedPackagesWithDeveloperMode:NO error:&error];
		BTAssert(inventory.count == 1 && [inventory[0].packageURL isEqual:first.packageURL],
			"persisted quarantine inventory did not reproduce the content-addressed package");

		NSURL *applicationDataRootURL = [temporaryURL URLByAppendingPathComponent:@"ApplicationData" isDirectory:YES];
		BTPluginApplicationDataStore *applicationDataStore = [[BTPluginApplicationDataStore alloc]
			initWithRootURL:applicationDataRootURL packageVerifier:verifier error:&error];
		BTAssert(applicationDataStore != nil, error.localizedDescription.UTF8String);
		BTMemoryActivationStore *activationStore = [BTMemoryActivationStore new];
		BTPluginRuntimeEnvironment *directEnvironment = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:@"/Applications/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindJailbrokenDirect];
		NSArray *discoveryRoots = @[[BTPluginDiscoveryRoot transportPackageRootURL:applicationDataRootURL
			source:BTPluginSourceApplicationData]];
		BTPluginManagementService *management = [[BTPluginManagementService alloc]
			initWithPackageVerifier:verifier trustStore:trustStore activationStore:activationStore
			applicationDataStore:applicationDataStore quarantineStore:store environment:directEnvironment
			discoveryRoots:discoveryRoots];
		BTAssert(management != nil, "management service creation failed");
		NSURL *expectedInstalledURL = [applicationDataRootURL URLByAppendingPathComponent:
			@"com.example.battman.analytics.fixture.battman" isDirectory:YES];
			activationStore.failNextTransactionBegin = YES;
	BTPluginManagementActionResult *approvalResult = [management
		allowExactBuildAndScheduleQuarantinedPackage:first error:&error];
		BTAssert(approvalResult == nil && ![manager fileExistsAtPath:expectedInstalledURL.path] &&
			activationStore.records.count == 0,
			"activation-state failure mutated app-data package bytes");
		error = nil;
		approvalResult = [management installAlreadyTrustedQuarantinedPackage:first error:&error];
		BTAssert(approvalResult.outcome == BTPluginManagementActionOutcomeScheduledForNextLaunch,
			(error.localizedDescription ?: @"direct approval was not scheduled").UTF8String);
		BTPluginVerifiedPackage *installed = approvalResult.verifiedPackage;
		BTAssert(installed != nil && installed.isApprovedForActivation &&
			[installed.packageInspection.packageSHA256 isEqualToString:first.verification.packageInspection.packageSHA256],
			(error.localizedDescription ?: @"exact-approved package was not installed with the same digest").UTF8String);
		BTAssert([installed.packageInspection.packageURL.lastPathComponent
			isEqualToString:@"com.example.battman.analytics.fixture.battman"],
			"app-data package did not use its verified identifier as the installed name");
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during app-data installation");
		BTPluginActivationRecord *scheduled = activationStore.records[@"com.example.battman.analytics.fixture"];
		BTAssert(scheduled.isEnabled && scheduled.source == BTPluginSourceApplicationData &&
			scheduled.activationMode == BTPluginActivationModeDirect &&
			[scheduled.packageSHA256 isEqualToString:installed.packageInspection.packageSHA256],
			"direct approval did not persist an exact restart activation record");
		BTPluginManagementSnapshot *managementSnapshot = [management
			managementSnapshotWithStartupSnapshot:nil error:&error];
		BTAssert(managementSnapshot != nil && managementSnapshot.quarantinedPackages.count == 1 &&
			managementSnapshot.installedPackages.count == 1 &&
			managementSnapshot.installedPackages[0].verifiedPackage != nil,
			"management snapshot did not reproduce quarantine and installed state");
		BTAssert([management setDiscoveredPackage:managementSnapshot.installedPackages[0].discoveredPackage
			enabled:NO error:&error] && !activationStore.records[@"com.example.battman.analytics.fixture"].isEnabled,
			"installed package could not be disabled for the next launch");

		NSURL *updateSourceRootURL = [temporaryURL URLByAppendingPathComponent:@"UpdateSource" isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:updateSourceRootURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *updatePackageURL = BTPluginTestCreateSignedPackageVersioned(updateSourceRootURL,
			fixtureURL, @"SignedNativeV2.battman", @"2.0", @"2", 2);
	BTPluginQuarantinedPackage *update = [store quarantinePackageAtURL:updatePackageURL
		developerMode:NO error:&error];
	BTAssert(update != nil && !update.isApprovedForActivation &&
		![update.verification.packageInspection.packageSHA256
			isEqualToString:installed.packageInspection.packageSHA256],
		(error.localizedDescription ?: @"same-ID update did not enter quarantine as new bytes").UTF8String);
	// The fixture intentionally receives a fresh publisher key.  A publisher-wide
	// approval must not silently rotate the identity of an installed app-data
	// plug-in; an exact-build approval remains the explicit escape hatch.
	error = nil;
	BTPluginManagementActionResult *rotatedPublisherResult = [management
		trustPublisherAndScheduleQuarantinedPackage:update error:&error];
	BTPluginVerifiedPackage *stillInstalled = [verifier verifyPackageAtURL:expectedInstalledURL
		developerMode:NO error:&error];
	BTAssert(rotatedPublisherResult == nil && stillInstalled != nil &&
		[stillInstalled.packageInspection.packageSHA256
			isEqualToString:installed.packageInspection.packageSHA256] &&
		error.code == BTPluginPackageErrorActivationState,
		"publisher-key rotation was accepted as an in-place app-data update");
	NSString *updatePublisherKey = update.verification.packageInspection.manifest.publisher.primaryKeyIdentifier;
	NSData *updatePublisherData = update.verification.packageInspection.includedPublisherKeysByIdentifier[
		updatePublisherKey];
	trustStore.publisherApproval = [[BTPluginPublisherApproval alloc]
		initWithKeyIdentifier:updatePublisherKey publicKeyData:updatePublisherData
		pluginIdentifiers:[NSSet setWithObject:BTPluginTestSignedPackageIdentifier]
		extensionPointIdentifiers:[NSSet setWithObject:BTPluginTestSignedPackageExtensionPoint]
		approvedAt:[NSDate date] error:&error];
	BTAssert(trustStore.publisherApproval != nil, error.localizedDescription.UTF8String);
	error = nil;
	BTPluginVerifiedPackage *pretrustedUpdate = [management refreshQuarantinedPackage:update error:&error];
	BTAssert(pretrustedUpdate.trustEvaluation.disposition == BTPluginTrustDispositionTrustedPublisher,
		"pre-existing publisher approval did not create the intended rotation fixture");
	BTPluginManagementActionResult *pretrustedRotation = [management
		installAlreadyTrustedQuarantinedPackage:update error:&error];
	BTAssert(pretrustedRotation == nil && error.code == BTPluginPackageErrorActivationState,
		"a pre-existing publisher approval bypassed the ABI-v1 key-change boundary");
	activationStore.failNextTransactionBegin = YES;
		error = nil;
		BTPluginManagementActionResult *failedUpdate = [management
			allowExactBuildAndScheduleQuarantinedPackage:update error:&error];
		BTPluginVerifiedPackage *preserved = [verifier verifyPackageAtURL:expectedInstalledURL
			developerMode:NO error:&error];
		BTAssert(failedUpdate == nil && preserved != nil &&
			[preserved.packageInspection.packageSHA256
				isEqualToString:installed.packageInspection.packageSHA256] &&
			[activationStore.records[@"com.example.battman.analytics.fixture"].packageSHA256
				isEqualToString:installed.packageInspection.packageSHA256],
			"failed update scheduling changed installed bytes or restart intent");
		error = nil;
		BTPluginVerifiedPackage *exactPreferred = [management refreshQuarantinedPackage:update error:&error];
		BTAssert(exactPreferred.trustEvaluation.disposition == BTPluginTrustDispositionExactBuild,
			"exact-build approval did not take precedence over broader publisher trust");
		error = nil;
		BTPluginManagementActionResult *updateResult = [management
			installAlreadyTrustedQuarantinedPackage:update error:&error];
		BTPluginVerifiedPackage *updated = updateResult.verifiedPackage;
		BTAssert(updateResult.outcome == BTPluginManagementActionOutcomeScheduledForNextLaunch &&
			updated != nil && [updated.packageInspection.manifest.displayVersion isEqualToString:@"2.0"] &&
			[updated.packageInspection.manifest.buildVersion isEqualToString:@"2"] &&
			[updated.packageInspection.packageSHA256
				isEqualToString:update.verification.packageInspection.packageSHA256] &&
			[activationStore.records[@"com.example.battman.analytics.fixture"].packageSHA256
				isEqualToString:updated.packageInspection.packageSHA256],
			(error.localizedDescription ?: @"same-ID app-data update did not atomically advance bytes and restart intent").UTF8String);
		NSArray<NSURL *> *appDataEntries = [manager contentsOfDirectoryAtURL:applicationDataRootURL
			includingPropertiesForKeys:nil options:0 error:&error];
		BTAssert(appDataEntries.count == 1 &&
			[appDataEntries.firstObject.lastPathComponent
				isEqualToString:@"com.example.battman.analytics.fixture.battman"],
			"same-ID update leaked old or staging app-data representations");
	managementSnapshot = [management managementSnapshotWithStartupSnapshot:nil error:&error];
	BTAssert(managementSnapshot.installedPackages.count == 1 &&
		[managementSnapshot.installedPackages[0].verifiedPackage.packageInspection.packageSHA256
			isEqualToString:updated.packageInspection.packageSHA256],
		"management snapshot did not reproduce the updated installed package");
	BTPluginPackageManifest *priorManifest = nil;
	BTAssert(BTPluginPriorVersionComparisonForCandidate(update.verification,
		managementSnapshot.installedPackages, &priorManifest) ==
		BTPluginPriorVersionComparisonStatusCandidateNotNewer && priorManifest == nil,
		"same-sequence candidate was incorrectly presented as a newer prior-version update");
	BTAssert(BTPluginPriorVersionComparisonForCandidate(update.verification, @[], &priorManifest) ==
		BTPluginPriorVersionComparisonStatusNoInstalledVersion,
		"missing installed baseline was not reported explicitly");
	BTAssert(BTPluginPriorVersionComparisonForCandidate(update.verification,
		@[ managementSnapshot.installedPackages[0], managementSnapshot.installedPackages[0] ], &priorManifest) ==
		BTPluginPriorVersionComparisonStatusAmbiguousInstalledRepresentations,
		"duplicate installed representations were not treated as ambiguous");

	// A committed filesystem publication must remain recoverable if the final
	// Keychain clear is interrupted.  The next startup reconciliation observes
	// the target digest and closes the same journal without guessing.
	activationStore.failNextTransactionFinish = YES;
	error = nil;
	BTPluginManagementActionResult *finishInterrupted = [management
		installAlreadyTrustedQuarantinedPackage:update error:&error];
	BTAssert(finishInterrupted == nil && activationStore.pendingTransaction != nil &&
		[activationStore.records[@"com.example.battman.analytics.fixture"].packageSHA256
			isEqualToString:updated.packageInspection.packageSHA256],
		"finish interruption did not leave a recoverable target journal");
	error = nil;
	managementSnapshot = [management managementSnapshotWithStartupSnapshot:nil error:&error];
	BTAssert(managementSnapshot != nil && activationStore.pendingTransaction == nil &&
		[management reconcilePendingApplicationDataTransactionWithError:&error] &&
		activationStore.pendingTransaction == nil,
		(error.localizedDescription ?: @"management snapshot did not reconcile the pending transaction").UTF8String);

		// A structurally valid package remains exactly removable after its local
		// approval is absent. The removal request is bound to the management
		// selection's digest, and the existing transaction journal still fences the
		// filesystem/activation-state update.
		BTPluginExactBuildApproval *savedExactApproval = trustStore.exactApproval;
		BTPluginPublisherApproval *savedPublisherApproval = trustStore.publisherApproval;
		trustStore.exactApproval = nil;
		trustStore.publisherApproval = nil;
		error = nil;
		managementSnapshot = [management managementSnapshotWithStartupSnapshot:nil error:&error];
		BTAssert(managementSnapshot.installedPackages.count == 1 &&
			managementSnapshot.installedPackages[0].verifiedPackage.trustEvaluation.disposition ==
				BTPluginTrustDispositionRequiresApproval,
			"installed valid bytes did not enter the approval-required removal fixture");
		BTPluginDiscoveredPackage *removalSelection = managementSnapshot.installedPackages[0].discoveredPackage;
		NSString *wrongDigest = [@"" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0];
		error = nil;
		BTAssert(![management removeDiscoveredPackage:removalSelection
			expectedPackageSHA256:wrongDigest error:&error] &&
			error.code == BTPluginPackageErrorRaceDetected &&
			[manager fileExistsAtPath:expectedInstalledURL.path],
			"approval-required app-data removal accepted a non-matching package digest");
		BTAssert([manager setAttributes:@{ NSFilePosixPermissions: @0775 }
			ofItemAtPath:expectedInstalledURL.path error:&error], error.localizedDescription.UTF8String);
		error = nil;
		BTAssert(![management removeDiscoveredPackage:removalSelection
			expectedPackageSHA256:updated.packageInspection.packageSHA256 error:&error] &&
			error.code == BTPluginPackageErrorUnsafePath &&
			[manager fileExistsAtPath:expectedInstalledURL.path],
			"app-data removal accepted a group-writable package root");
		BTAssert([manager setAttributes:@{ NSFilePosixPermissions: @0755 }
			ofItemAtPath:expectedInstalledURL.path error:&error], error.localizedDescription.UTF8String);
		activationStore.failNextTransactionBegin = YES;
		error = nil;
		BTAssert(![management removeDiscoveredPackage:removalSelection
			expectedPackageSHA256:updated.packageInspection.packageSHA256 error:&error] &&
			[manager fileExistsAtPath:expectedInstalledURL.path] &&
			[activationStore.records[@"com.example.battman.analytics.fixture"].packageSHA256
				isEqualToString:updated.packageInspection.packageSHA256],
			"approval-required transaction-begin failure changed package bytes or restart intent");
		error = nil;
		BTAssert([management removeDiscoveredPackage:removalSelection
			expectedPackageSHA256:updated.packageInspection.packageSHA256 error:&error] &&
			activationStore.pendingTransaction == nil && activationStore.records.count == 0,
			(error.localizedDescription ?: @"approval-required app-data bytes were not removable").UTF8String);
		BTAssert(![manager fileExistsAtPath:expectedInstalledURL.path] &&
			![manager fileExistsAtPath:sentinelPath],
			"approval-required removal left app-data bytes or executed the plug-in constructor");

		// Reinstall the exact same approved bytes, then make their signing key
		// locally revoked. Full verification must now fail, while the structural
		// removal path and activation-record digest still permit only those bytes.
		trustStore.exactApproval = savedExactApproval;
		trustStore.publisherApproval = savedPublisherApproval;
		error = nil;
		BTPluginManagementActionResult *reinstalled = [management
			installAlreadyTrustedQuarantinedPackage:update error:&error];
		BTAssert(reinstalled.outcome == BTPluginManagementActionOutcomeScheduledForNextLaunch &&
			[manager fileExistsAtPath:expectedInstalledURL.path],
			(error.localizedDescription ?: @"revoked-removal fixture could not be reinstalled").UTF8String);
		BTPluginTrustEvaluator *revokedEvaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPolicyWithRevokedKeys([NSSet setWithObject:updatePublisherKey])
			trustStore:trustStore];
		BTPluginPackageVerifier *revokedVerifier = [[BTPluginPackageVerifier alloc]
			initWithTrustEvaluator:revokedEvaluator hostIOSVersion:iOS17];
		BTPluginApplicationDataStore *revokedApplicationDataStore = [[BTPluginApplicationDataStore alloc]
			initWithRootURL:applicationDataRootURL packageVerifier:revokedVerifier error:&error];
		BTPluginManagementService *revokedManagement = [[BTPluginManagementService alloc]
			initWithPackageVerifier:revokedVerifier trustStore:trustStore activationStore:activationStore
			applicationDataStore:revokedApplicationDataStore quarantineStore:store
			environment:directEnvironment discoveryRoots:discoveryRoots];
		error = nil;
		BTPluginManagementSnapshot *revokedSnapshot = [revokedManagement
			managementSnapshotWithStartupSnapshot:nil error:&error];
		BTPluginManagedInstalledPackage *revokedItem = revokedSnapshot.installedPackages.firstObject;
		BTAssert(revokedSnapshot != nil && revokedItem.verifiedPackage == nil &&
			revokedItem.verificationError.code == BTPluginPackageErrorRevokedPublisher &&
			[revokedItem.activationRecord.packageSHA256
				isEqualToString:updated.packageInspection.packageSHA256],
			"revoked installed bytes did not retain an exact UI-manageable activation digest");
		error = nil;
		BTAssert(![revokedManagement removeDiscoveredPackage:revokedItem.discoveredPackage
			expectedPackageSHA256:wrongDigest error:&error] &&
			error.code == BTPluginPackageErrorRaceDetected &&
			[manager fileExistsAtPath:expectedInstalledURL.path],
			"revoked app-data removal accepted a non-matching package digest");
		BTPluginActivationRecord *matchingRecord = revokedItem.activationRecord;
		BTPluginActivationRecord *mismatchedRecord = [[BTPluginActivationRecord alloc]
			initWithPluginIdentifier:matchingRecord.pluginIdentifier packageSHA256:wrongDigest
			source:BTPluginSourceApplicationData activationMode:BTPluginActivationModeDirect
			enabled:matchingRecord.isEnabled updatedAt:[NSDate date] error:&error];
		activationStore.records[matchingRecord.pluginIdentifier] = mismatchedRecord;
		error = nil;
		BTAssert(![revokedManagement removeDiscoveredPackage:revokedItem.discoveredPackage
			expectedPackageSHA256:updated.packageInspection.packageSHA256 error:&error] &&
			error.code == BTPluginPackageErrorActivationState &&
			[manager fileExistsAtPath:expectedInstalledURL.path],
			"revoked removal ignored an inconsistent activation-record digest");
		activationStore.records[matchingRecord.pluginIdentifier] = matchingRecord;
		activationStore.failNextTransactionFinish = YES;
		error = nil;
		BTAssert(![revokedManagement removeDiscoveredPackage:revokedItem.discoveredPackage
			expectedPackageSHA256:revokedItem.activationRecord.packageSHA256 error:&error] &&
			activationStore.pendingTransaction != nil && activationStore.records.count == 0 &&
			![manager fileExistsAtPath:expectedInstalledURL.path],
			"revoked removal did not leave a recoverable journal after final-state interruption");
		error = nil;
		revokedSnapshot = [revokedManagement managementSnapshotWithStartupSnapshot:nil error:&error];
		BTAssert(revokedSnapshot != nil && revokedSnapshot.installedPackages.count == 0 &&
			activationStore.pendingTransaction == nil && activationStore.records.count == 0,
			(error.localizedDescription ?: @"revoked removal journal did not reconcile").UTF8String);
		BTAssert(![manager fileExistsAtPath:expectedInstalledURL.path] &&
			[manager fileExistsAtPath:first.packageURL.path] &&
			![manager fileExistsAtPath:sentinelPath],
			"revoked removal escaped app-data, retained bytes, or executed the constructor");

		// Missing bytes may safely abort only a fresh install.  An interrupted
		// update with neither canonical nor staged bytes must retain its journal
		// and fail closed rather than restoring a record for a nonexistent tree.
		BTPluginActivationRecord *missingTargetRecord = [[BTPluginActivationRecord alloc]
			initWithPluginIdentifier:@"com.example.battman.missing-update"
			packageSHA256:wrongDigest source:BTPluginSourceApplicationData
			activationMode:BTPluginActivationModeDirect enabled:YES updatedAt:[NSDate date]
			error:&error];
		BTPluginApplicationDataTransaction *missingUpdate = [[BTPluginApplicationDataTransaction alloc]
			initWithTransactionIdentifier:NSUUID.UUID.UUIDString.lowercaseString
			operation:BTPluginApplicationDataTransactionOperationUpdate
			pluginIdentifier:missingTargetRecord.pluginIdentifier
			expectedPackageSHA256:updated.packageInspection.packageSHA256
			targetPackageSHA256:wrongDigest previousActivationRecord:nil
			targetActivationRecord:missingTargetRecord beganAt:[NSDate date] error:&error];
		BOOL missingCommitted = YES;
		error = nil;
		BTAssert(missingUpdate != nil && ![applicationDataStore
			reconcileApplicationDataTransaction:missingUpdate committed:&missingCommitted error:&error] &&
			!missingCommitted, "missing update bytes were treated as an abortable fresh install");
		error = nil;
		BTPluginApplicationDataTransaction *missingInstall = [[BTPluginApplicationDataTransaction alloc]
			initWithTransactionIdentifier:NSUUID.UUID.UUIDString.lowercaseString
			operation:BTPluginApplicationDataTransactionOperationInstall
			pluginIdentifier:missingTargetRecord.pluginIdentifier expectedPackageSHA256:nil
			targetPackageSHA256:wrongDigest previousActivationRecord:nil
			targetActivationRecord:missingTargetRecord beganAt:[NSDate date] error:&error];
		missingCommitted = YES;
		error = nil;
		BTAssert(missingInstall != nil && [applicationDataStore
			reconcileApplicationDataTransaction:missingInstall committed:&missingCommitted error:&error] &&
			!missingCommitted, "fresh install absence was not safely abortable");

		BTMemoryActivationStore *replacementActivationStore = [BTMemoryActivationStore new];
		BTPluginRuntimeEnvironment *replacementEnvironment = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:
				@"/var/containers/Bundle/Application/UUID/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindTrollStoreReplacement];
		BTPluginManagementService *replacementManagement = [[BTPluginManagementService alloc]
			initWithPackageVerifier:verifier trustStore:trustStore activationStore:replacementActivationStore
			applicationDataStore:applicationDataStore quarantineStore:store environment:replacementEnvironment
			discoveryRoots:discoveryRoots];
		BTPluginManagementActionResult *replacementResult = [replacementManagement
			installAlreadyTrustedQuarantinedPackage:update error:&error];
		BTPluginActivationRecord *replacementRecord =
			replacementActivationStore.records[@"com.example.battman.analytics.fixture"];
		BTAssert(replacementResult.outcome == BTPluginManagementActionOutcomeRequiresReplacementApp &&
			replacementRecord.source == BTPluginSourceImport &&
			replacementRecord.activationMode == BTPluginActivationModeRequiresReinstall &&
			replacementResult.installedPackageURL == nil,
			"TrollStore policy did not remain replacement-app-only");
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor executed during replacement scheduling");

		NSArray<NSURL *> *pluginDirectoryEntries = [manager contentsOfDirectoryAtURL:first.packageURL.URLByDeletingLastPathComponent
			includingPropertiesForKeys:nil options:0 error:&error];
		NSPredicate *contentAddressedPackages = [NSPredicate predicateWithBlock:
			^BOOL(NSURL *URL, NSDictionary *bindings) {
			(void)bindings;
			return ![URL.lastPathComponent hasPrefix:@"."] &&
				[URL.pathExtension isEqualToString:@"battman"];
		}];
		BTAssert(pluginDirectoryEntries.count == 2 &&
			[[pluginDirectoryEntries filteredArrayUsingPredicate:contentAddressedPackages] count] == 2,
			"same-ID quarantine versions were lost or staging state leaked");
		NSDictionary *rootAttributes = [manager attributesOfItemAtPath:quarantineRootURL.path error:&error];
		BTAssert(([rootAttributes[NSFilePosixPermissions] unsignedShortValue] & 0777) == 0700,
			"quarantine root permissions are not private");

		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		printf("Document import, quarantine, exact app-data install/remove, and no-execution tests passed.\n");
	}
	return 0;
}
