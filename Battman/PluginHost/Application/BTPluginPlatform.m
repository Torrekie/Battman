//
//  BTPluginPlatform.m
//  Battman
//

#import "BTPluginPlatform.h"
#import "../../BattmanDataPaths.h"

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

NSNotificationName const BTPluginPlatformDidFinishStartupNotification = @"BTPluginPlatformDidFinishStartupNotification";

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
@property (atomic, strong, readwrite, nullable) BTPluginStartupSnapshot *startupSnapshot;
@property (atomic, strong, readwrite, nullable) BTPluginDiscoveryResult *discoveryResult;
@property (atomic, copy, readwrite) NSArray<BTPluginRuntimeLoadResult *> *loadedPlugins;
@property (atomic, copy, readwrite) NSArray<BTPluginPlatformDiagnostic *> *diagnostics;
@property (atomic, readwrite, getter=isPreparedForApplicationLaunch) BOOL preparedForApplicationLaunch;
@property (atomic, readwrite, getter=isExternalStartupComplete) BOOL externalStartupComplete;
@property (nonatomic) dispatch_queue_t startupQueue;
@property (nonatomic) dispatch_group_t startupGroup;
@property (nonatomic, strong) id<BTPluginActivationStore> activationStore;
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@property (nonatomic, strong) BTPluginImportCoordinator *importCoordinator;
@property (atomic, strong, readwrite, nullable) BTPluginManagementService *managementService;
@property (nonatomic, strong) BTPluginRuntimeLoader *runtimeLoader;
@property (nonatomic, strong) BTPluginRuntimeEnvironment *runtimeEnvironment;
@property (nonatomic, strong) NSURL *configDirectoryURL;
@property (nonatomic, strong) NSURL *safeModeSentinelURL;
@property (nonatomic, strong) BTPluginSafeModeRequest *safeModeRequest;
@property (nonatomic) NSUInteger activeSettlementGeneration;
@property (atomic) BOOL startupSettled;
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
	_startupQueue = dispatch_queue_create("com.torrekie.Battman.PluginStartup", DISPATCH_QUEUE_SERIAL);
	_startupGroup = dispatch_group_create();
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

	_configDirectoryURL = BattmanConfigDirectoryURL();
	NSURL *hostSupportURL = _configDirectoryURL;
	_safeModeSentinelURL = [hostSupportURL URLByAppendingPathComponent:BTPluginSafeModeSentinelName isDirectory:NO];
	_safeModeRequest = [[BTPluginSafeModeRequest alloc] initWithSentinelURL:_safeModeSentinelURL];
	return self;
}

// Serial worker only: Keychain, filesystem, signatures and store recovery must
// not extend the UIApplication startup watchdog interval.
- (void)initializeExternalServices {
	NSURL *hostSupportURL = self.configDirectoryURL;
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
		self.diagnostics = [self.diagnostics arrayByAddingObject:diagnostic];
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
		NSURL *applicationDataPluginURL = [hostSupportURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES];
		NSError *applicationDataError = nil;
		BTPluginApplicationDataStore *applicationDataStore = [[BTPluginApplicationDataStore alloc]
			initWithRootURL:applicationDataPluginURL packageVerifier:_packageVerifier error:&applicationDataError];
		NSArray<BTPluginDiscoveryRoot *> *managementRoots = [BTPluginDiscovery
			defaultRootsForConfigDirectoryURL:_configDirectoryURL mainBundleURL:NSBundle.mainBundle.bundleURL];
		if (applicationDataStore) {
			self.managementService = [[BTPluginManagementService alloc]
				initWithPackageVerifier:_packageVerifier trustStore:trustStore activationStore:_activationStore
				applicationDataStore:applicationDataStore quarantineStore:quarantineStore
				environment:_runtimeEnvironment discoveryRoots:managementRoots];
		} else {
			BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
			diagnostic.stage = @"management-initialization";
			diagnostic.error = applicationDataError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
				@"The private plug-in installation directory could not be initialized.", nil, nil);
			self.diagnostics = [self.diagnostics arrayByAddingObject:diagnostic];
		}
	} else {
		BTPluginPlatformDiagnostic *diagnostic = [[BTPluginPlatformDiagnostic alloc] bt_init];
		diagnostic.stage = @"import-initialization";
		diagnostic.error = quarantineError ?: BTPluginPackageMakeError(BTPluginPackageErrorImport,
			@"The private plug-in quarantine could not be initialized.", nil, nil);
		self.diagnostics = [self.diagnostics arrayByAddingObject:diagnostic];
	}
}

- (BOOL)handleOpenPackageURL:(NSURL *)packageURL {
	// Document delivery may race the worker's initialization. Keep the URL's
	// security scope alive until the import coordinator accepts ownership.
	if (![packageURL isKindOfClass:[NSURL class]] || !packageURL.isFileURL ||
		![packageURL.pathExtension isEqualToString:@"battman"] ||
		packageURL.lastPathComponent.length <= @".battman".length ||
		![packageURL.lastPathComponent isEqualToString:packageURL.lastPathComponent.precomposedStringWithCanonicalMapping])
		return NO;
	NSURL *capturedURL = [packageURL copy];
	BOOL scoped = [capturedURL startAccessingSecurityScopedResource];
	dispatch_async(self.startupQueue, ^{
		BOOL accepted = [self.importCoordinator handleOpenPackageURL:capturedURL];
		if (scoped)
			[capturedURL stopAccessingSecurityScopedResource];
		if (!accepted) {
			NSError *error = BTPluginPackageMakeError(BTPluginPackageErrorImport,
				@"Plug-in import is unavailable because its private storage failed to initialize.", nil, nil);
			dispatch_async(dispatch_get_main_queue(), ^{
				[NSNotificationCenter.defaultCenter postNotificationName:BTPluginImportDidFinishNotification
					object:self userInfo:@{ BTPluginImportErrorUserInfoKey: error }];
			});
		}
	});
	return YES;
}

- (BTPluginManagementSnapshot *)currentManagementSnapshotWithError:(NSError **)error {
	if (!self.externalStartupComplete) {
		if (NSThread.isMainThread || !self.preparedForApplicationLaunch) {
			BTPluginPlatformSetError(error, @"Plug-in startup is still in progress.");
			return nil;
		}
		// The management UI already requests snapshots on its own worker. It
		// can wait here; the main thread must never wait for plugin startup.
		dispatch_group_wait(self.startupGroup, DISPATCH_TIME_FOREVER);
	}
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
	if (self.preparedForApplicationLaunch)
		return YES;
	[[BTPluginImportPresenter sharedPresenter] startObserving];
	NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
	[center addObserver:self selector:@selector(applicationDidBecomeActive:)
		name:UIApplicationDidBecomeActiveNotification object:nil];
	[center addObserver:self selector:@selector(applicationWillLeaveActive:)
		name:UIApplicationWillResignActiveNotification object:nil];
	[center addObserver:self selector:@selector(applicationWillLeaveActive:)
		name:UIApplicationDidEnterBackgroundNotification object:nil];
	self.preparedForApplicationLaunch = YES;
	dispatch_group_async(self.startupGroup, self.startupQueue, ^{
		@autoreleasepool {
			[self initializeExternalServices];
			NSError *startupError = nil;
			if (![self loadExternalPluginsWithError:&startupError]) {
				NSMutableArray *diagnostics = [self.diagnostics mutableCopy];
				[self addDiagnosticStage:@"startup" pluginIdentifier:nil
					error:startupError ?: BTPluginPackageMakeError(BTPluginPackageErrorRuntime,
						@"External plug-in startup failed closed.", nil, nil) toArray:diagnostics];
				self.diagnostics = diagnostics;
			}
			dispatch_sync(dispatch_get_main_queue(), ^{
				self.externalStartupComplete = YES;
				[NSNotificationCenter.defaultCenter postNotificationName:BTPluginPlatformDidFinishStartupNotification
					object:self];
				if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
					[self applicationDidBecomeActive:nil];
			});
		}
	});
	return YES;
}

- (BOOL)loadExternalPluginsWithError:(NSError **)error {
	if (!self.runtimeLoader || !self.activationStore)
		return BTPluginPlatformSetError(error, @"The plug-in platform composition root is incomplete.");
	if (self.managementService &&
		![self.managementService reconcilePendingApplicationDataTransactionWithError:error])
		return NO;
	BOOL safeModeRequested = [self safeModeWasRequested] || self.officialTrustFailedClosed;
	BTPluginStartupSnapshot *snapshot = [self.activationStore
		beginStartupWithSafeModeRequested:safeModeRequested error:error];
	if (!snapshot)
		return NO;
	self.startupSnapshot = snapshot;
	NSArray<BTPluginDiscoveryRoot *> *roots = [BTPluginDiscovery
		defaultRootsForConfigDirectoryURL:self.configDirectoryURL
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
		@autoreleasepool {
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
			BTPluginPreparedActivation *prepared = [self.runtimeLoader
				prepareDiscoveredPackage:package activationRecord:recordsByIdentifier[package.claimedPluginIdentifier]
				startupSnapshot:snapshot developerMode:NO error:&loadError];
			__block BTPluginRuntimeLoadResult *result = nil;
			if (prepared) {
				__block NSError *activationError = nil;
				dispatch_sync(dispatch_get_main_queue(), ^{
					result = [self.runtimeLoader activatePreparedPackage:prepared error:&activationError];
				});
				loadError = activationError;
			}
			if (result)
				[loaded addObject:result];
			else if (loadError)
				[self addDiagnosticStage:@"activation" pluginIdentifier:package.claimedPluginIdentifier
					error:loadError toArray:diagnostics];
		}
	}
	self.loadedPlugins = loaded;
	self.diagnostics = diagnostics;
	return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	(void)notification;
	if (self.startupSettled || !self.externalStartupComplete || !self.startupSnapshot)
		return;
	NSUInteger generation = ++self.activeSettlementGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
		dispatch_get_main_queue(), ^{
			if (self.startupSettled || !self.externalStartupComplete ||
				generation != self.activeSettlementGeneration ||
				UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
				return;
			dispatch_async(self.startupQueue, ^{
				NSError *settlementError = nil;
				BOOL settled = [self markStartupSettledWithError:&settlementError];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (settled) {
						self.startupSettled = YES;
					} else {
						NSMutableArray *diagnostics = [self.diagnostics mutableCopy];
						[self addDiagnosticStage:@"startup-settlement" pluginIdentifier:nil
							error:settlementError toArray:diagnostics];
						self.diagnostics = diagnostics;
					}
				});
			});
		});
}

- (void)applicationWillLeaveActive:(NSNotification *)notification {
	(void)notification;
	self.activeSettlementGeneration++;
}

- (BOOL)markStartupSettledWithError:(NSError **)error {
	if (self.startupSettled)
		return YES;
	if (!self.externalStartupComplete || !self.startupSnapshot)
		return BTPluginPlatformSetError(error, @"No plug-in startup session exists to settle.");
	return [self.activationStore markStartupSettledWithIdentifier:self.startupSnapshot.startupIdentifier
		error:error];
}

@end
