//
//  BTPluginPlatform.m
//  Battman
//

#import "BTPluginPlatform.h"

#import <UIKit/UIKit.h>

#import "../../Features/Analytics/BuiltIn/BAAnalyticsBuiltInPlugin.h"
#import "../../Features/Analytics/Public/BAAnalyticsCard.h"
#import "../BTEmbeddedPluginRegistration.h"
#import "../BTPluginRegistry.h"
#import "../Discovery/BTPluginDiscovery.h"
#import "../Import/BTPluginImportCoordinator.h"
#import "../Import/BTPluginQuarantineStore.h"
#import "../Import/BTPluginApplicationDataStore.h"
#import "../Management/BTPluginManagementService.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Runtime/BTPluginActivationStore.h"
#import "../Runtime/BTPluginRuntimeLoader.h"
#import "../Runtime/BTPluginSafeModeRequest.h"
#import "../Security/BTPluginPackageVerifier.h"
#import "../Security/BTPluginOfficialTrustLoader.h"
#import "../Security/BTPluginTrustEvaluator.h"
#import "../Security/BTPluginTrustStore.h"
#import "../UI/BTPluginImportPresenter.h"

static BOOL BTPluginPlatformSetError(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorRuntime, description, nil, nil);
	return NO;
}

@interface BTPluginPlatformDiagnostic ()
@property (nonatomic, copy, readwrite) NSString *stage;
@property (nonatomic, copy, readwrite, nullable) NSString *pluginIdentifier;
@property (nonatomic, strong, readwrite) NSError *error;
- (instancetype)bt_init;
@end

@implementation BTPluginPlatformDiagnostic
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginPlatform ()
@property (nonatomic, strong, readwrite) BTPluginRegistry *registry;
@property (nonatomic, strong, readwrite, nullable) BTPluginStartupSnapshot *startupSnapshot;
@property (nonatomic, strong, readwrite, nullable) BTPluginDiscoveryResult *discoveryResult;
@property (nonatomic, copy, readwrite) NSArray<BTPluginRuntimeLoadResult *> *loadedPlugins;
@property (nonatomic, copy, readwrite) NSArray<BTPluginPlatformDiagnostic *> *diagnostics;
@property (nonatomic, readwrite, getter=isPreparedForApplicationLaunch) BOOL preparedForApplicationLaunch;
@property (nonatomic, strong) id<BTPluginActivationStore> activationStore;
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@property (nonatomic, strong) BTPluginImportCoordinator *importCoordinator;
@property (nonatomic, strong, readwrite, nullable) BTPluginManagementService *managementService;
@property (nonatomic, strong) BTPluginRuntimeLoader *runtimeLoader;
@property (nonatomic, strong) BTPluginRuntimeEnvironment *runtimeEnvironment;
@property (nonatomic, strong) NSURL *applicationSupportURL;
@property (nonatomic, strong) NSURL *safeModeSentinelURL;
@property (nonatomic, strong) BTPluginSafeModeRequest *safeModeRequest;
@property (nonatomic) NSUInteger activeSettlementGeneration;
@property (nonatomic) BOOL startupSettled;
@property (nonatomic) BOOL officialTrustFailedClosed;
@end

@implementation BTPluginPlatform

+ (instancetype)sharedPlatform {
	static BTPluginPlatform *platform = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		platform = [[BTPluginPlatform alloc] initPrivate];
	});
	return platform;
}

- (instancetype)initPrivate {
	self = [super init];
	if (!self)
		return nil;
	_registry = [BTPluginRegistry new];
	_loadedPlugins = @[];
	_diagnostics = @[];

	NSError *registryError = nil;
	BOOL registeredExtensionPoint = [_registry
		registerExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier
		interfaceVersion:BAAnalyticsCardExtensionPointVersion
		requiredProtocol:@protocol(BAAnalyticsCard) error:&registryError];
	BOOL registeredBuiltIns = registeredExtensionPoint && BTRegisterEmbeddedPluginDescriptor(
		BAAnalyticsBuiltInPluginDescriptor(), _registry,
		[NSSet setWithObject:BAAnalyticsCardExtensionPointIdentifier], &registryError);
	if (!registeredBuiltIns) {
		BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
		diagnostic.stage = @"embedded-registration";
		diagnostic.error = registryError ?: BTPluginPackageMakeError(BTPluginPackageErrorRuntime,
			@"Embedded Analytics registration failed.", nil, nil);
		_diagnostics = @[ diagnostic ];
	}

	NSArray<NSURL *> *supportURLs = [[NSFileManager defaultManager]
		URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
	_applicationSupportURL = supportURLs.firstObject ?: [NSURL fileURLWithPath:
		[NSTemporaryDirectory() stringByAppendingPathComponent:@"Battman Application Support"] isDirectory:YES];
	NSURL *hostSupportURL = [_applicationSupportURL URLByAppendingPathComponent:@"Battman" isDirectory:YES];
	_safeModeSentinelURL = [hostSupportURL URLByAppendingPathComponent:BTPluginSafeModeSentinelName isDirectory:NO];
	_safeModeRequest = [[BTPluginSafeModeRequest alloc] initWithSentinelURL:_safeModeSentinelURL];
	_activationStore = [BTPluginKeychainActivationStore new];

	// Root private keys are never generated or inferred here. A missing resource
	// keeps the engineering-build behavior of explicit local approval. A present
	// but invalid or rolled-back resource forces safe mode so no external native
	// image can load under an incomplete revocation policy.
	BTPluginTrustPolicy *policy = [BTPluginOfficialTrustLoader emptyTrustPolicy];
	BTPluginOfficialTrustLoader *officialTrustLoader = [[BTPluginOfficialTrustLoader alloc]
		initWithStateStore:[BTPluginKeychainTrustMetadataStateStore new]];
	NSError *officialTrustError = nil;
	BTPluginOfficialTrustLoadResult *officialTrust = [officialTrustLoader
		loadFromApplicationBundleURL:NSBundle.mainBundle.bundleURL error:&officialTrustError];
	if (officialTrust) {
		policy = officialTrust.trustPolicy;
	} else {
		_officialTrustFailedClosed = YES;
		BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
		diagnostic.stage = @"official-trust";
		diagnostic.error = officialTrustError ?: BTPluginPackageMakeError(BTPluginPackageErrorInvalidSignature,
			@"The bundled official plug-in trust policy could not be verified.", nil, nil);
		_diagnostics = [_diagnostics arrayByAddingObject:diagnostic];
	}
	BTPluginKeychainTrustStore *trustStore = [BTPluginKeychainTrustStore new];
	BTPluginTrustEvaluator *trustEvaluator = [[BTPluginTrustEvaluator alloc]
		initWithPolicy:policy trustStore:trustStore];
	_packageVerifier = [[BTPluginPackageVerifier alloc]
		initWithTrustEvaluator:trustEvaluator
		hostIOSVersion:NSProcessInfo.processInfo.operatingSystemVersion];
	_runtimeEnvironment = [BTPluginRuntimeEnvironment
		currentEnvironmentForApplicationBundleURL:NSBundle.mainBundle.bundleURL];
	_runtimeLoader = [[BTPluginRuntimeLoader alloc] initWithPackageVerifier:_packageVerifier
		registry:_registry activationStore:_activationStore environment:_runtimeEnvironment];
	NSURL *quarantineURL = [hostSupportURL URLByAppendingPathComponent:@"Plugin Quarantine" isDirectory:YES];
	NSError *quarantineError = nil;
	BTPluginQuarantineStore *quarantineStore = [[BTPluginQuarantineStore alloc]
		initWithRootURL:quarantineURL packageVerifier:_packageVerifier error:&quarantineError];
	if (quarantineStore) {
		_importCoordinator = [[BTPluginImportCoordinator alloc] initWithQuarantineStore:quarantineStore];
		[[BTPluginImportPresenter sharedPresenter] startObserving];
		NSURL *applicationDataPluginURL = [hostSupportURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
		NSError *applicationDataError = nil;
		BTPluginApplicationDataStore *applicationDataStore = [[BTPluginApplicationDataStore alloc]
			initWithRootURL:applicationDataPluginURL packageVerifier:_packageVerifier error:&applicationDataError];
		NSArray<BTPluginDiscoveryRoot *> *managementRoots = [BTPluginDiscovery
			defaultRootsForApplicationSupportURL:_applicationSupportURL mainBundleURL:NSBundle.mainBundle.bundleURL];
		if (applicationDataStore) {
			_managementService = [[BTPluginManagementService alloc]
				initWithPackageVerifier:_packageVerifier trustStore:trustStore activationStore:_activationStore
				applicationDataStore:applicationDataStore quarantineStore:quarantineStore
				environment:_runtimeEnvironment discoveryRoots:managementRoots];
		} else {
			BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
			diagnostic.stage = @"management-initialization";
			diagnostic.error = applicationDataError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
				@"The private plug-in installation directory could not be initialized.", nil, nil);
			_diagnostics = [_diagnostics arrayByAddingObject:diagnostic];
		}
	} else {
		BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
		diagnostic.stage = @"import-initialization";
		diagnostic.error = quarantineError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
			@"The private plug-in quarantine could not be initialized.", nil, nil);
		_diagnostics = [_diagnostics arrayByAddingObject:diagnostic];
	}
	return self;
}

- (BOOL)handleOpenPackageURL:(NSURL *)packageURL {
	return [self.importCoordinator handleOpenPackageURL:packageURL];
}

- (BTPluginManagementSnapshot *)currentManagementSnapshotWithError:(NSError **)error {
	if (!self.managementService) {
		BTPluginPlatformSetError(error, @"Plug-in management is unavailable because its private storage failed to initialize.");
		return nil;
	}
	return [self.managementService managementSnapshotWithStartupSnapshot:self.startupSnapshot error:error];
}

- (BOOL)requestSafeModeForNextLaunchWithError:(NSError **)error {
	return [self.safeModeRequest requestOneShotWithError:error];
}

- (BOOL)safeModeWasRequested {
	if ([NSProcessInfo.processInfo.arguments containsObject:BTPluginSafeModeLaunchArgument])
		return YES;
	return [self.safeModeRequest consumeOneShotRequestIfPresent];
}

- (void)addDiagnosticStage:(NSString *)stage pluginIdentifier:(NSString *)pluginIdentifier error:(NSError *)error
	toArray:(NSMutableArray<BTPluginPlatformDiagnostic *> *)diagnostics {
	BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
	diagnostic.stage = stage;
	diagnostic.pluginIdentifier = pluginIdentifier;
	diagnostic.error = error;
	[diagnostics addObject:diagnostic];
}

- (BOOL)prepareForApplicationLaunchWithError:(NSError **)error {
	if (![NSThread isMainThread])
		return BTPluginPlatformSetError(error, @"The plug-in platform must prepare on the main thread.");
	@synchronized (self) {
		if (self.preparedForApplicationLaunch)
			return YES;
		if (!self.runtimeLoader || !self.activationStore)
			return BTPluginPlatformSetError(error, @"The plug-in platform composition root is incomplete.");
		if (self.managementService) {
			NSError *transactionError = nil;
			if (![self.managementService reconcilePendingApplicationDataTransactionWithError:&transactionError]) {
				if (error)
					*error = transactionError;
				return NO;
			}
		}

		NSError *startupError = nil;
		BOOL safeModeRequested = [self safeModeWasRequested] || self.officialTrustFailedClosed;
		BTPluginStartupSnapshot *snapshot = [self.activationStore
			beginStartupWithSafeModeRequested:safeModeRequested error:&startupError];
		if (!snapshot) {
			if (error)
				*error = startupError;
			return NO;
		}
		self.startupSnapshot = snapshot;

		NSArray<BTPluginDiscoveryRoot *> *roots = [BTPluginDiscovery
			defaultRootsForApplicationSupportURL:self.applicationSupportURL
			mainBundleURL:NSBundle.mainBundle.bundleURL];
		self.discoveryResult = [[BTPluginDiscovery new] discoverRoots:roots];
		NSMutableArray<BTPluginPlatformDiagnostic *> *diagnostics = [self.diagnostics mutableCopy];
		for (BTPluginDiscoveryDiagnostic *discoveryDiagnostic in self.discoveryResult.diagnostics)
			[self addDiagnosticStage:@"discovery" pluginIdentifier:nil
				error:discoveryDiagnostic.error toArray:diagnostics];

		NSMutableDictionary<NSString *, BTPluginActivationRecord *> *recordsByIdentifier = [NSMutableDictionary dictionary];
		for (BTPluginActivationRecord *record in snapshot.activationRecords)
			recordsByIdentifier[record.pluginIdentifier] = record;

		// Discovery is already sorted by source priority and path. Accept the
		// first installed representation for an ID so a duplicate cannot reach a
		// second constructor after registration of the first image.
		NSMutableSet<NSString *> *selectedIdentifiers = [NSMutableSet set];
		NSMutableArray<BTPluginRuntimeLoadResult *> *loaded = [NSMutableArray array];
		for (BTPluginDiscoveredPackage *package in self.discoveryResult.packages) {
			if ([selectedIdentifiers containsObject:package.claimedPluginIdentifier]) {
				NSError *duplicateError = BTPluginPackageMakeError(BTPluginPackageErrorRuntime,
					@"A lower-priority installed representation was ignored for a duplicate plug-in identifier.",
					package.claimedPluginIdentifier, nil);
				[self addDiagnosticStage:@"selection" pluginIdentifier:package.claimedPluginIdentifier
					error:duplicateError toArray:diagnostics];
				continue;
			}
			[selectedIdentifiers addObject:package.claimedPluginIdentifier];
			NSError *loadError = nil;
			BTPluginRuntimeLoadResult *result = [self.runtimeLoader
				loadDiscoveredPackage:package activationRecord:recordsByIdentifier[package.claimedPluginIdentifier]
				startupSnapshot:snapshot developerMode:NO error:&loadError];
			if (result)
				[loaded addObject:result];
			else if (loadError)
				[self addDiagnosticStage:@"activation" pluginIdentifier:package.claimedPluginIdentifier
					error:loadError toArray:diagnostics];
		}
		self.loadedPlugins = loaded;
		self.diagnostics = diagnostics;
		self.preparedForApplicationLaunch = YES;
		NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
		[notificationCenter addObserver:self selector:@selector(applicationDidBecomeActive:)
			name:UIApplicationDidBecomeActiveNotification object:nil];
		[notificationCenter addObserver:self selector:@selector(applicationWillLeaveActive:)
			name:UIApplicationWillResignActiveNotification object:nil];
		[notificationCenter addObserver:self selector:@selector(applicationWillLeaveActive:)
			name:UIApplicationDidEnterBackgroundNotification object:nil];
		return YES;
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	(void)notification;
	@synchronized (self) {
		if (self.startupSettled || !self.startupSnapshot)
			return;
		NSUInteger generation = ++self.activeSettlementGeneration;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
				@synchronized (self) {
					if (self.startupSettled || generation != self.activeSettlementGeneration ||
						UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
						return;
					NSError *settlementError = nil;
					if ([self markStartupSettledWithError:&settlementError]) {
						self.startupSettled = YES;
					} else {
						NSMutableArray *diagnostics = [self.diagnostics mutableCopy];
						[self addDiagnosticStage:@"startup-settlement" pluginIdentifier:nil
							error:settlementError toArray:diagnostics];
						self.diagnostics = diagnostics;
					}
				}
			});
	}
}

- (void)applicationWillLeaveActive:(NSNotification *)notification {
	(void)notification;
	@synchronized (self) {
		self.activeSettlementGeneration++;
	}
}

- (BOOL)markStartupSettledWithError:(NSError **)error {
	@synchronized (self) {
		if (self.startupSettled)
			return YES;
		if (!self.startupSnapshot)
			return BTPluginPlatformSetError(error, @"No plug-in startup session exists to settle.");
		return [self.activationStore markStartupSettledWithIdentifier:self.startupSnapshot.startupIdentifier
			error:error];
	}
}

@end
