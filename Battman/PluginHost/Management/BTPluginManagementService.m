//
//  BTPluginManagementService.m
//  Battman
//

#import "BTPluginManagementService.h"

#import "../Model/BTPluginPackageErrors.h"

static BOOL BTPluginManagementFail(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState, description, nil, nil);
	return NO;
}

@interface BTPluginManagementActionResult ()
@property (nonatomic, readwrite) BTPluginManagementActionOutcome outcome;
@property (nonatomic, strong, readwrite) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, strong, readwrite, nullable) NSURL *installedPackageURL;
- (instancetype)bt_init;
@end

@implementation BTPluginManagementActionResult
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManagedInstalledPackage ()
@property (nonatomic, strong, readwrite) BTPluginDiscoveredPackage *discoveredPackage;
@property (nonatomic, strong, readwrite, nullable) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, strong, readwrite, nullable) BTPluginActivationRecord *activationRecord;
@property (nonatomic, strong, readwrite, nullable) NSError *verificationError;
- (instancetype)bt_init;
@end

@implementation BTPluginManagedInstalledPackage
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManagementSnapshot ()
@property (nonatomic, readwrite, getter=areThirdPartyPluginsEnabled) BOOL thirdPartyPluginsEnabled;
@property (nonatomic, readwrite, getter=isSafeMode) BOOL safeMode;
@property (nonatomic, strong, readwrite, nullable) BTPluginStartupRecovery *recovery;
@property (nonatomic, copy, readwrite) NSArray<BTPluginQuarantinedPackage *> *quarantinedPackages;
@property (nonatomic, copy, readwrite) NSArray<BTPluginManagedInstalledPackage *> *installedPackages;
@property (nonatomic, copy, readwrite) NSArray<NSError *> *diagnostics;
@property (nonatomic, strong, readwrite) NSDate *generatedAt;
- (instancetype)bt_init;
@end

@implementation BTPluginManagementSnapshot
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManagementService ()
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@property (nonatomic, strong) id<BTPluginTrustStore> trustStore;
@property (nonatomic, strong) id<BTPluginActivationStore> activationStore;
@property (nonatomic, strong, nullable) id<BTPluginApplicationDataTransactionStore> applicationDataTransactionStore;
@property (nonatomic, strong) BTPluginApplicationDataStore *applicationDataStore;
@property (nonatomic, strong) BTPluginQuarantineStore *quarantineStore;
@property (nonatomic, strong) BTPluginRuntimeEnvironment *environment;
@property (nonatomic, copy) NSArray<BTPluginDiscoveryRoot *> *discoveryRoots;
- (BOOL)bt_reconcilePendingApplicationDataTransactionWithError:(NSError **)error;
- (BOOL)bt_validateAppDataCandidate:(BTPluginVerifiedPackage *)verified
	allowPublisherKeyChange:(BOOL)allowPublisherKeyChange error:(NSError **)error;
- (nullable BTPluginManagementActionResult *)bt_scheduleApprovedQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package allowPublisherKeyChange:(BOOL)allowPublisherKeyChange
	error:(NSError **)error;
- (BOOL)bt_removeDiscoveredPackage:(BTPluginDiscoveredPackage *)package
	expectedPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error;
@end

@implementation BTPluginManagementService

- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
										 trustStore:(id<BTPluginTrustStore>)trustStore
							 activationStore:(id<BTPluginActivationStore>)activationStore
					 applicationDataStore:(BTPluginApplicationDataStore *)applicationDataStore
							 quarantineStore:(BTPluginQuarantineStore *)quarantineStore
									environment:(BTPluginRuntimeEnvironment *)environment
								 discoveryRoots:(NSArray<BTPluginDiscoveryRoot *> *)discoveryRoots {
	self = [super init];
	if (!self)
		return nil;
	if (![packageVerifier isKindOfClass:[BTPluginPackageVerifier class]] || !trustStore || !activationStore ||
		![applicationDataStore isKindOfClass:[BTPluginApplicationDataStore class]] ||
		![quarantineStore isKindOfClass:[BTPluginQuarantineStore class]] ||
		![environment isKindOfClass:[BTPluginRuntimeEnvironment class]] ||
		![discoveryRoots isKindOfClass:[NSArray class]] || discoveryRoots.count == 0)
		return nil;
	_packageVerifier = packageVerifier;
	_trustStore = trustStore;
	_activationStore = activationStore;
	if ([activationStore conformsToProtocol:@protocol(BTPluginApplicationDataTransactionStore)])
		_applicationDataTransactionStore = (id<BTPluginApplicationDataTransactionStore>)activationStore;
	_applicationDataStore = applicationDataStore;
	_quarantineStore = quarantineStore;
	_environment = environment;
	_discoveryRoots = [discoveryRoots copy];
	return self;
}

- (BOOL)reconcilePendingApplicationDataTransactionWithError:(NSError **)error {
	@synchronized (self) {
		return [self bt_reconcilePendingApplicationDataTransactionWithError:error];
	}
}

- (BOOL)bt_reconcilePendingApplicationDataTransactionWithError:(NSError **)error {
	if (!self.applicationDataTransactionStore)
		return BTPluginManagementFail(error,
			@"Direct app-data management requires a journal-capable activation store.");
	NSError *pendingError = nil;
	BTPluginApplicationDataTransaction *pending =
		[self.applicationDataTransactionStore pendingApplicationDataTransactionWithError:&pendingError];
	if (pendingError) {
		if (error)
			*error = pendingError;
		return NO;
	}
	if (pending) {
		BOOL committed = NO;
		if (![self.applicationDataStore reconcileApplicationDataTransaction:pending
			committed:&committed error:error])
			return NO;
		BOOL stateChanged = committed ?
			[self.applicationDataTransactionStore finishApplicationDataTransactionWithIdentifier:
				pending.transactionIdentifier error:error] :
			[self.applicationDataTransactionStore abortApplicationDataTransactionWithIdentifier:
				pending.transactionIdentifier error:error];
		if (!stateChanged)
			return NO;
	}
	// Once the journal is successfully finished or aborted, its hidden staging
	// or tombstone path is no longer protected.  Preserve only a *different*
	// journal that may have appeared through a recovery-layer implementation;
	// retaining the just-closed token would leave aborted staging bytes behind
	// until a later launch.
	NSError *remainingError = nil;
	BTPluginApplicationDataTransaction *remaining =
		[self.applicationDataTransactionStore pendingApplicationDataTransactionWithError:&remainingError];
	if (remainingError) {
		if (error)
			*error = remainingError;
		return NO;
	}
	return [self.applicationDataStore discardUnjournaledPreparedTransactionsExceptIdentifier:
		remaining.transactionIdentifier error:error];
}

- (BOOL)bt_validateAppDataCandidate:(BTPluginVerifiedPackage *)verified
	allowPublisherKeyChange:(BOOL)allowPublisherKeyChange error:(NSError **)error {
	if (![verified isKindOfClass:[BTPluginVerifiedPackage class]] ||
		!verified.packageInspection.manifest.pluginIdentifier)
		return BTPluginManagementFail(error, @"The plug-in candidate is incomplete.");
	NSError *installedError = nil;
	BTPluginVerifiedPackage *existing = [self.applicationDataStore
		installedPackageForPluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
		error:&installedError];
	if (installedError) {
		if (error)
			*error = installedError;
		return NO;
	}
	if (!existing || [existing.packageInspection.packageSHA256
		isEqualToString:verified.packageInspection.packageSHA256])
		return YES;
	BTPluginPackageManifest *installedManifest = existing.packageInspection.manifest;
	BTPluginPackageManifest *candidateManifest = verified.packageInspection.manifest;
	// ABI v1 has no verified successor-chain resolver.  A package signed by a
	// different publisher key is therefore a new authorization, not an in-place
	// publisher update. Exact-build approval may explicitly authorize it; a
	// publisher-wide approval must wait until the old representation is removed.
	if (!allowPublisherKeyChange && ![installedManifest.publisher.primaryKeyIdentifier
		isEqualToString:candidateManifest.publisher.primaryKeyIdentifier])
		return BTPluginManagementFail(error,
			@"A publisher-key change cannot replace an installed app-data version without removing the prior version first.");
	if (candidateManifest.releaseSequence <= installedManifest.releaseSequence) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRollback,
				@"A lower or conflicting app-data release sequence cannot replace the installed version.",
				candidateManifest.pluginIdentifier, nil);
		return NO;
	}
	return YES;
}

- (BTPluginManagementSnapshot *)managementSnapshotWithStartupSnapshot:(BTPluginStartupSnapshot *)startupSnapshot
															 error:(NSError **)error {
	@synchronized (self) {
	// A management view may be the first code path reached after a terminated
	// update/removal.  Reconcile the journal before exposing records so the UI
	// cannot present a stale activation/package split until the next launch or
	// mutation.  Non-journal-capable test/legacy stores retain the read-only
	// snapshot behavior.
	if (self.applicationDataTransactionStore &&
		![self bt_reconcilePendingApplicationDataTransactionWithError:error])
		return nil;
	NSError *stateError = nil;
	NSArray<BTPluginActivationRecord *> *records = [self.activationStore activationRecordsWithError:&stateError];
	if (!records) {
		if (error)
			*error = stateError;
		return nil;
	}
	BOOL thirdPartyEnabled = [self.activationStore thirdPartyPluginsEnabledWithError:&stateError];
	if (stateError) {
		if (error)
			*error = stateError;
		return nil;
	}
	NSMutableDictionary<NSString *, BTPluginActivationRecord *> *recordsByIdentifier = [NSMutableDictionary dictionary];
	for (BTPluginActivationRecord *record in records)
		recordsByIdentifier[record.pluginIdentifier] = record;

	NSMutableArray<NSError *> *diagnostics = [NSMutableArray array];
	NSError *quarantineError = nil;
	NSArray<BTPluginQuarantinedPackage *> *quarantined = [self.quarantineStore
		quarantinedPackagesWithDeveloperMode:NO error:&quarantineError];
	if (!quarantined) {
		quarantined = @[];
		if (quarantineError)
			[diagnostics addObject:quarantineError];
	}
	BTPluginDiscoveryResult *discoveryResult = [[BTPluginDiscovery new] discoverRoots:self.discoveryRoots];
	for (BTPluginDiscoveryDiagnostic *diagnostic in discoveryResult.diagnostics)
		[diagnostics addObject:diagnostic.error];
	NSMutableArray<BTPluginManagedInstalledPackage *> *installed = [NSMutableArray array];
	for (BTPluginDiscoveredPackage *discoveredPackage in discoveryResult.packages) {
		NSError *verificationError = nil;
		BTPluginVerifiedPackage *verified = [self refreshDiscoveredPackage:discoveredPackage
			error:&verificationError];
		BTPluginManagedInstalledPackage *item = [[BTPluginManagedInstalledPackage alloc] bt_init];
		item.discoveredPackage = discoveredPackage;
		item.verifiedPackage = verified;
		item.activationRecord = recordsByIdentifier[discoveredPackage.claimedPluginIdentifier];
		item.verificationError = verificationError;
		[installed addObject:item];
		if (verificationError)
			[diagnostics addObject:verificationError];
	}
	BTPluginManagementSnapshot *snapshot = [[BTPluginManagementSnapshot alloc] bt_init];
	snapshot.thirdPartyPluginsEnabled = thirdPartyEnabled;
	snapshot.safeMode = startupSnapshot.isSafeMode;
	snapshot.recovery = startupSnapshot.recovery;
	snapshot.quarantinedPackages = quarantined;
	snapshot.installedPackages = installed;
	snapshot.diagnostics = diagnostics;
	snapshot.generatedAt = [NSDate date];
	return snapshot;
	}
}

- (BTPluginVerifiedPackage *)refreshQuarantinedPackage:(BTPluginQuarantinedPackage *)package
																					 error:(NSError **)error {
	if (![package isKindOfClass:[BTPluginQuarantinedPackage class]]) {
		BTPluginManagementFail(error, @"The selected quarantine package is invalid.");
		return nil;
	}
	BTPluginVerifiedPackage *verified = [self.packageVerifier verifyPackageAtURL:package.packageURL
		developerMode:NO error:error];
	if (verified && ![verified.packageInspection.packageSHA256
		isEqualToString:package.verification.packageInspection.packageSHA256]) {
		BTPluginManagementFail(error, @"The quarantine package changed after it was selected.");
		return nil;
	}
	return verified;
}

- (BTPluginVerifiedPackage *)refreshDiscoveredPackage:(BTPluginDiscoveredPackage *)package
																				 error:(NSError **)error {
	if (![package isKindOfClass:[BTPluginDiscoveredPackage class]]) {
		BTPluginManagementFail(error, @"The installed plug-in selection is invalid.");
		return nil;
	}
	BTPluginVerifiedPackage *verified = nil;
	if (package.representation == BTPluginInstalledRepresentationTransportPackage) {
		verified = [self.packageVerifier verifyPackageAtURL:package.packageURL developerMode:NO error:error];
	} else if (package.representation == BTPluginInstalledRepresentationSealedAppBundle &&
		package.metadataURL && package.payloadURL) {
		verified = [self.packageVerifier verifySealedMetadataAtURL:package.metadataURL
			payloadURL:package.payloadURL developerMode:NO error:error];
	} else {
		BTPluginManagementFail(error, @"The installed plug-in representation is unsupported.");
		return nil;
	}
	if (verified && ![verified.packageInspection.manifest.pluginIdentifier
		isEqualToString:package.claimedPluginIdentifier]) {
		BTPluginManagementFail(error, @"The installed plug-in name does not match its verified identity.");
		return nil;
	}
	return verified;
}

- (BTPluginManagementActionResult *)scheduleApprovedDiscoveredPackage:(BTPluginDiscoveredPackage *)package
																							 error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshDiscoveredPackage:package error:error];
	if (!verified || !verified.isApprovedForActivation) {
		if (verified)
			BTPluginManagementFail(error, @"The package approval did not match its current installed bytes and scope.");
		return nil;
	}
	BTPluginActivationMode mode = BTPluginActivationModeDirect;
	BTPluginSource source = package.source;
	BTPluginManagementActionOutcome outcome = BTPluginManagementActionOutcomeScheduledForNextLaunch;
	if (package.source == BTPluginSourceApplicationData &&
		self.environment.importedNativeCodeRequiresReplacementApp) {
		mode = BTPluginActivationModeRequiresReinstall;
		source = BTPluginSourceImport;
		outcome = BTPluginManagementActionOutcomeRequiresReplacementApp;
	}
	BTPluginActivationRecord *record = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
		packageSHA256:verified.packageInspection.packageSHA256 source:source activationMode:mode
		enabled:YES updatedAt:[NSDate date] error:error];
	if (!record || ![self.activationStore scheduleActivationRecord:record error:error])
		return nil;
	BTPluginManagementActionResult *result = [[BTPluginManagementActionResult alloc] bt_init];
	result.outcome = outcome;
	result.verifiedPackage = verified;
	result.installedPackageURL = mode == BTPluginActivationModeDirect ?
		verified.packageInspection.packageURL : nil;
	return result;
}

- (BTPluginManagementActionResult *)scheduleApprovedQuarantinedPackage:(BTPluginQuarantinedPackage *)package
																									 error:(NSError **)error {
	@synchronized (self) {
		return [self bt_scheduleApprovedQuarantinedPackage:package allowPublisherKeyChange:NO error:error];
	}
}

- (BTPluginManagementActionResult *)bt_scheduleApprovedQuarantinedPackage:(BTPluginQuarantinedPackage *)package
	allowPublisherKeyChange:(BOOL)allowPublisherKeyChange error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshQuarantinedPackage:package error:error];
	if (!verified || !verified.isApprovedForActivation) {
		if (verified)
			BTPluginManagementFail(error, @"The package approval did not match its current verified bytes and scope.");
		return nil;
	}
	BTPluginManagementActionResult *result = [[BTPluginManagementActionResult alloc] bt_init];
	result.verifiedPackage = verified;
	if (self.environment.importedNativeCodeRequiresReplacementApp) {
		BTPluginActivationRecord *record = [[BTPluginActivationRecord alloc]
			initWithPluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
			packageSHA256:verified.packageInspection.packageSHA256
			source:BTPluginSourceImport activationMode:BTPluginActivationModeRequiresReinstall
			enabled:YES updatedAt:[NSDate date] error:error];
		result.outcome = BTPluginManagementActionOutcomeRequiresReplacementApp;
		if (!record || ![self.activationStore scheduleActivationRecord:record error:error])
			return nil;
		return result;
	}
	if (!self.applicationDataTransactionStore)
	{
		BTPluginManagementFail(error, @"Direct app-data management requires a journal-capable activation store.");
		return nil;
	}
	if (![self bt_reconcilePendingApplicationDataTransactionWithError:error])
		return nil;
	NSString *pluginIdentifier = verified.packageInspection.manifest.pluginIdentifier;
	NSArray<BTPluginActivationRecord *> *records = [self.activationStore activationRecordsWithError:error];
	if (!records)
		return nil;
	BTPluginActivationRecord *previousRecord = nil;
	for (BTPluginActivationRecord *candidate in records)
		if ([candidate.pluginIdentifier isEqualToString:pluginIdentifier]) {
			previousRecord = candidate;
			break;
		}
	NSError *installedStateError = nil;
	BTPluginVerifiedPackage *existing = [self.applicationDataStore
		installedPackageForPluginIdentifier:pluginIdentifier error:&installedStateError];
	if (installedStateError) {
		if (error)
			*error = installedStateError;
		return nil;
	}
	if (previousRecord && (!existing || previousRecord.source != BTPluginSourceApplicationData ||
		previousRecord.activationMode != BTPluginActivationModeDirect ||
		![previousRecord.packageSHA256 isEqualToString:existing.packageInspection.packageSHA256])) {
		BTPluginManagementFail(error, @"The installed app-data package and restart activation state are inconsistent.");
		return nil;
	}
	if (existing) {
		BTPluginPackageManifest *installedManifest = existing.packageInspection.manifest;
		BTPluginPackageManifest *candidateManifest = verified.packageInspection.manifest;
		BOOL samePackage = [existing.packageInspection.packageSHA256
			isEqualToString:verified.packageInspection.packageSHA256];
		BOOL samePublisher = [installedManifest.publisher.primaryKeyIdentifier
			isEqualToString:candidateManifest.publisher.primaryKeyIdentifier];
		BOOL hasExplicitKeyChangeAuthorization = allowPublisherKeyChange ||
			verified.trustEvaluation.disposition == BTPluginTrustDispositionExactBuild ||
			verified.trustEvaluation.disposition == BTPluginTrustDispositionOfficial;
		if (!samePackage && !samePublisher && !hasExplicitKeyChangeAuthorization) {
			BTPluginManagementFail(error,
				@"Only explicit exact-build approval can replace an installed app-data plug-in under a different publisher key in ABI v1.");
			return nil;
		}
		if (!samePackage &&
			candidateManifest.releaseSequence <= installedManifest.releaseSequence) {
			if (error)
				*error = BTPluginPackageMakeError(BTPluginPackageErrorRollback,
					@"A lower or conflicting same-ID package cannot replace the installed app-data version.",
					pluginIdentifier, nil);
			return nil;
		}
	}
	BTPluginApplicationDataTransactionOperation operation = existing ?
		BTPluginApplicationDataTransactionOperationUpdate : BTPluginApplicationDataTransactionOperationInstall;
	BTPluginActivationRecord *targetRecord = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:pluginIdentifier packageSHA256:verified.packageInspection.packageSHA256
		source:BTPluginSourceApplicationData activationMode:BTPluginActivationModeDirect
		enabled:previousRecord ? previousRecord.isEnabled : YES
		updatedAt:[NSDate date] error:error];
	NSString *transactionIdentifier = NSUUID.UUID.UUIDString.lowercaseString;
	BTPluginApplicationDataTransaction *transaction = [[BTPluginApplicationDataTransaction alloc]
		initWithTransactionIdentifier:transactionIdentifier operation:operation pluginIdentifier:pluginIdentifier
		expectedPackageSHA256:existing.packageInspection.packageSHA256
		targetPackageSHA256:verified.packageInspection.packageSHA256 previousActivationRecord:previousRecord
		targetActivationRecord:targetRecord beganAt:[NSDate date] error:error];
	if (!transaction || ![self.applicationDataStore prepareQuarantinedPackage:package
		transactionIdentifier:transactionIdentifier developerMode:NO error:error])
		return nil;
	NSError *beginError = nil;
	if (![self.applicationDataTransactionStore beginApplicationDataTransaction:transaction
		expectedActivationRecord:previousRecord error:&beginError]) {
		NSError *pendingError = nil;
		BTPluginApplicationDataTransaction *otherPending =
			[self.applicationDataTransactionStore pendingApplicationDataTransactionWithError:&pendingError];
		if (!pendingError)
			(void)[self.applicationDataStore discardUnjournaledPreparedTransactionsExceptIdentifier:
				otherPending.transactionIdentifier error:NULL];
		if (error)
			*error = beginError ?: pendingError;
		return nil;
	}
	BOOL journalFinished = NO;
	NSError *publishError = nil;
	BTPluginVerifiedPackage *installed = [self.applicationDataStore
		publishPreparedApplicationDataTransaction:transaction error:&publishError];
	if (!installed) {
		NSError *reconcileError = nil;
		BOOL committed = NO;
		if (![self.applicationDataStore reconcileApplicationDataTransaction:transaction
			committed:&committed error:&reconcileError]) {
			if (error) *error = publishError ?: reconcileError;
			return nil;
		}
		BOOL closed = committed ?
			[self.applicationDataTransactionStore finishApplicationDataTransactionWithIdentifier:transactionIdentifier error:&reconcileError] :
			[self.applicationDataTransactionStore abortApplicationDataTransactionWithIdentifier:transactionIdentifier error:&reconcileError];
		if (!closed) {
			if (error) *error = reconcileError;
			return nil;
		}
		if (!committed) {
			if (error) *error = publishError;
			return nil;
		}
		NSError *installedError = nil;
		installed = [self.applicationDataStore installedPackageForPluginIdentifier:pluginIdentifier
			error:&installedError];
		if (!installed) {
			if (error)
				*error = installedError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
					@"The committed app-data transaction target could not be reopened.", nil, nil);
			return nil;
		}
		journalFinished = YES;
	}
	if (!journalFinished && ![self.applicationDataTransactionStore finishApplicationDataTransactionWithIdentifier:transactionIdentifier
		error:error])
		return nil;
	result.outcome = BTPluginManagementActionOutcomeScheduledForNextLaunch;
	result.installedPackageURL = installed.packageInspection.packageURL;
	result.verifiedPackage = installed;
	return result;
}

- (BTPluginManagementActionResult *)allowExactBuildAndScheduleQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshQuarantinedPackage:package error:error];
	if (!verified || ![self bt_validateAppDataCandidate:verified allowPublisherKeyChange:YES error:error])
		return nil;
	BTPluginExactBuildApproval *approval = [[BTPluginExactBuildApproval alloc]
		initWithPackageSHA256:verified.packageInspection.packageSHA256
		pluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
		publisherKeyIdentifier:verified.packageInspection.manifest.publisher.primaryKeyIdentifier
		approvedAt:[NSDate date] error:error];
	if (!approval || ![self.trustStore storeExactBuildApproval:approval error:error])
		return nil;
	@synchronized (self) {
		return [self bt_scheduleApprovedQuarantinedPackage:package allowPublisherKeyChange:YES error:error];
	}
}

- (BTPluginManagementActionResult *)installAlreadyTrustedQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError **)error {
	return [self scheduleApprovedQuarantinedPackage:package error:error];
}

- (BTPluginManagementActionResult *)allowExactBuildAndScheduleDiscoveredPackage:
	(BTPluginDiscoveredPackage *)package error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshDiscoveredPackage:package error:error];
	if (!verified || ![self bt_validateAppDataCandidate:verified allowPublisherKeyChange:YES error:error])
		return nil;
	BTPluginExactBuildApproval *approval = [[BTPluginExactBuildApproval alloc]
		initWithPackageSHA256:verified.packageInspection.packageSHA256
		pluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
		publisherKeyIdentifier:verified.packageInspection.manifest.publisher.primaryKeyIdentifier
		approvedAt:[NSDate date] error:error];
	if (!approval || ![self.trustStore storeExactBuildApproval:approval error:error])
		return nil;
	return [self scheduleApprovedDiscoveredPackage:package error:error];
}

- (BTPluginManagementActionResult *)trustPublisherAndScheduleQuarantinedPackage:
	(BTPluginQuarantinedPackage *)package error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshQuarantinedPackage:package error:error];
	if (!verified || ![self bt_validateAppDataCandidate:verified allowPublisherKeyChange:NO error:error])
		return nil;
	NSString *keyIdentifier = verified.packageInspection.manifest.publisher.primaryKeyIdentifier;
	NSData *publicKey = verified.packageInspection.includedPublisherKeysByIdentifier[keyIdentifier];
	if (!publicKey) {
		BTPluginManagementFail(error, @"This package does not include the stable publisher public key required for publisher trust.");
		return nil;
	}
	NSSet<NSString *> *pluginIdentifiers = [NSSet setWithObject:
		verified.packageInspection.manifest.pluginIdentifier];
	NSMutableSet<NSString *> *extensionPointIdentifiers = [NSMutableSet set];
	for (BTPluginManifestExtensionPoint *extensionPoint in verified.packageInspection.manifest.extensionPoints)
		[extensionPointIdentifiers addObject:extensionPoint.identifier];
	BTPluginPublisherApproval *approval = [[BTPluginPublisherApproval alloc]
		initWithKeyIdentifier:keyIdentifier publicKeyData:publicKey
		pluginIdentifiers:pluginIdentifiers extensionPointIdentifiers:extensionPointIdentifiers
		approvedAt:[NSDate date] error:error];
	if (!approval || ![self.trustStore storePublisherApproval:approval error:error])
		return nil;
	return [self scheduleApprovedQuarantinedPackage:package error:error];
}

- (BTPluginManagementActionResult *)trustPublisherAndScheduleDiscoveredPackage:
	(BTPluginDiscoveredPackage *)package error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshDiscoveredPackage:package error:error];
	if (!verified || ![self bt_validateAppDataCandidate:verified allowPublisherKeyChange:NO error:error])
		return nil;
	NSString *keyIdentifier = verified.packageInspection.manifest.publisher.primaryKeyIdentifier;
	NSData *publicKey = verified.packageInspection.includedPublisherKeysByIdentifier[keyIdentifier];
	if (!publicKey) {
		BTPluginManagementFail(error, @"This package does not include the stable publisher public key required for publisher trust.");
		return nil;
	}
	NSMutableSet<NSString *> *extensionPointIdentifiers = [NSMutableSet set];
	for (BTPluginManifestExtensionPoint *extensionPoint in verified.packageInspection.manifest.extensionPoints)
		[extensionPointIdentifiers addObject:extensionPoint.identifier];
	BTPluginPublisherApproval *approval = [[BTPluginPublisherApproval alloc]
		initWithKeyIdentifier:keyIdentifier publicKeyData:publicKey
		pluginIdentifiers:[NSSet setWithObject:verified.packageInspection.manifest.pluginIdentifier]
		extensionPointIdentifiers:extensionPointIdentifiers approvedAt:[NSDate date] error:error];
	if (!approval || ![self.trustStore storePublisherApproval:approval error:error])
		return nil;
	return [self scheduleApprovedDiscoveredPackage:package error:error];
}

- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError **)error {
	return [self.activationStore setThirdPartyPluginsEnabled:enabled error:error];
}

- (BOOL)setInstalledPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled error:(NSError **)error {
	return [self.activationStore setPluginIdentifier:pluginIdentifier enabled:enabled error:error];
}

- (BOOL)setDiscoveredPackage:(BTPluginDiscoveredPackage *)package enabled:(BOOL)enabled error:(NSError **)error {
	BTPluginVerifiedPackage *verified = [self refreshDiscoveredPackage:package error:error];
	if (!verified)
		return NO;
	BOOL officialWithoutRequiredRecord =
		verified.trustEvaluation.disposition == BTPluginTrustDispositionOfficial &&
		package.source != BTPluginSourceApplicationData;
	if (enabled && officialWithoutRequiredRecord)
		return [self.activationStore removePluginIdentifier:package.claimedPluginIdentifier error:error];
	BTPluginActivationRecord *record = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:verified.packageInspection.manifest.pluginIdentifier
		packageSHA256:verified.packageInspection.packageSHA256 source:package.source
		activationMode:BTPluginActivationModeDirect enabled:enabled updatedAt:[NSDate date] error:error];
	return record && [self.activationStore scheduleActivationRecord:record error:error];
}

- (BOOL)disableRecoveredPlugin:(BTPluginStartupRecovery *)recovery error:(NSError **)error {
	return [self.activationStore disablePluginFromRecovery:recovery error:error];
}

- (BOOL)removeDiscoveredPackage:(BTPluginDiscoveredPackage *)package
	expectedPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	@synchronized (self) {
		return [self bt_removeDiscoveredPackage:package expectedPackageSHA256:packageSHA256 error:error];
	}
}

- (BOOL)bt_removeDiscoveredPackage:(BTPluginDiscoveredPackage *)package
	expectedPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	if (![package isKindOfClass:[BTPluginDiscoveredPackage class]])
		return BTPluginManagementFail(error, @"The installed plug-in selection is invalid.");
	if (package.source != BTPluginSourceApplicationData)
		return BTPluginManagementFail(error,
			@"Battman can remove only its private app-data copy. App-bundle and package-manager files must be removed by their installer.");
	if (package.representation != BTPluginInstalledRepresentationTransportPackage ||
		package.payloadURL || package.metadataURL)
		return BTPluginManagementFail(error,
			@"The selected app-data removal is not a canonical transport-package representation.");
	if (!self.applicationDataTransactionStore)
		return BTPluginManagementFail(error,
			@"Direct app-data management requires a journal-capable activation store.");
	if (![self bt_reconcilePendingApplicationDataTransactionWithError:error])
		return NO;
	// Removal authority comes from the selected canonical path, structural tree
	// hash, and caller-confirmed exact digest—not from current trust. This keeps
	// revoked and approval-required bytes removable without turning removal into
	// an activation or trust decision.
	BTPluginPackageInspection *inspection = [self.applicationDataStore
		inspectInstalledPackageForRemovalAtURL:package.packageURL
		claimedPluginIdentifier:package.claimedPluginIdentifier
		expectedPackageSHA256:packageSHA256 error:error];
	if (!inspection)
		return NO;
	NSArray<BTPluginActivationRecord *> *records = [self.activationStore activationRecordsWithError:error];
	if (!records)
		return NO;
	BTPluginActivationRecord *previousRecord = nil;
	for (BTPluginActivationRecord *candidate in records)
		if ([candidate.pluginIdentifier isEqualToString:package.claimedPluginIdentifier]) {
			previousRecord = candidate;
			break;
		}
	if (previousRecord && (previousRecord.source != BTPluginSourceApplicationData ||
		previousRecord.activationMode != BTPluginActivationModeDirect ||
		![previousRecord.packageSHA256 isEqualToString:inspection.packageSHA256]))
		return BTPluginManagementFail(error,
			@"The selected app-data bytes do not match their active restart record.");
	BTPluginApplicationDataTransaction *transaction = [[BTPluginApplicationDataTransaction alloc]
		initWithTransactionIdentifier:NSUUID.UUID.UUIDString.lowercaseString
		operation:BTPluginApplicationDataTransactionOperationRemove
		pluginIdentifier:package.claimedPluginIdentifier expectedPackageSHA256:packageSHA256
		targetPackageSHA256:nil previousActivationRecord:previousRecord targetActivationRecord:nil
		beganAt:[NSDate date] error:error];
	if (!transaction || ![self.applicationDataTransactionStore beginApplicationDataTransaction:transaction
		expectedActivationRecord:previousRecord error:error])
		return NO;
	NSError *removeError = nil;
	(void)[self.applicationDataStore publishPreparedApplicationDataTransaction:transaction error:&removeError];
	BOOL committed = NO;
	NSError *reconcileError = nil;
	if (![self.applicationDataStore reconcileApplicationDataTransaction:transaction
		committed:&committed error:&reconcileError] || !committed) {
		if (error) *error = reconcileError ?: removeError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
			@"The app-data removal was not committed.", nil, nil);
		return NO;
	}
	if (![self.applicationDataTransactionStore finishApplicationDataTransactionWithIdentifier:
		transaction.transactionIdentifier error:error])
		return NO;
	return YES;
}

- (BOOL)removeQuarantinedPackage:(BTPluginQuarantinedPackage *)package error:(NSError **)error {
	if (![package isKindOfClass:[BTPluginQuarantinedPackage class]])
		return BTPluginManagementFail(error, @"The quarantine package selection is invalid.");
	BTPluginVerifiedPackage *verified = [self refreshQuarantinedPackage:package error:error];
	if (!verified)
		return NO;
	return [self.quarantineStore removeQuarantinedPluginIdentifier:
		verified.packageInspection.manifest.pluginIdentifier
		packageSHA256:verified.packageInspection.packageSHA256 error:error];
}

- (BOOL)revokeExactBuildForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	return [self.trustStore removeExactBuildApprovalForPackageSHA256:packageSHA256 error:error];
}

- (BOOL)revokePublisherKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	return [self.trustStore removePublisherApprovalForKeyIdentifier:keyIdentifier error:error];
}

@end
