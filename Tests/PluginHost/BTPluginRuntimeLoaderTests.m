#import <Foundation/Foundation.h>

#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/Discovery/BTPluginDiscovery.h"
#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Model/BTPluginPackageManifest.h"
#import "../../Battman/PluginHost/Runtime/BTPluginNativeImageLoaderPrivate.h"
#import "../../Battman/PluginHost/Runtime/BTPluginRuntimeLoaderInternal.h"
#import "../../Battman/PluginHost/Security/BTPluginTrustEvaluator.h"
#import "Fixtures/BTPluginSignedPackageFixture.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

@interface BTPluginStartupSnapshot (BTPluginRuntimeLoaderTestConstruction)
- (instancetype)bt_init;
- (void)setStartupIdentifier:(NSString *)startupIdentifier;
- (void)setSafeMode:(BOOL)safeMode;
- (void)setThirdPartyPluginsEnabled:(BOOL)thirdPartyPluginsEnabled;
- (void)setActivationRecords:(NSArray<BTPluginActivationRecord *> *)activationRecords;
- (void)setRecovery:(nullable BTPluginStartupRecovery *)recovery;
@end

@interface BTPluginRuntimeLoaderTestTrustStore : NSObject <BTPluginTrustStore>
@property (nonatomic) NSUInteger commitInvocationCount;
@property (nonatomic) BOOL failNextCommit;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *sequences;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *digests;
@end

@implementation BTPluginRuntimeLoaderTestTrustStore

- (instancetype)init {
	self = [super init];
	if (self) {
		_sequences = [NSMutableDictionary dictionary];
		_digests = [NSMutableDictionary dictionary];
	}
	return self;
}

- (NSString *)stateKeyForPluginIdentifier:(NSString *)pluginIdentifier
	publisherKeyIdentifier:(NSString *)publisherKeyIdentifier {
	return [NSString stringWithFormat:@"%@|%@", pluginIdentifier, publisherKeyIdentifier];
}

- (BTPluginPublisherApproval *)publisherApprovalForKeyIdentifier:(NSString *)keyIdentifier
	error:(NSError **)error {
	(void)keyIdentifier;
	(void)error;
	return nil;
}

- (BTPluginExactBuildApproval *)exactBuildApprovalForPackageSHA256:(NSString *)packageSHA256
	error:(NSError **)error {
	(void)packageSHA256;
	(void)error;
	return nil;
}

- (uint64_t)highestReleaseSequenceForPluginIdentifier:(NSString *)pluginIdentifier
	publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)error;
	return self.sequences[[self stateKeyForPluginIdentifier:pluginIdentifier
		publisherKeyIdentifier:publisherKeyIdentifier]].unsignedLongLongValue;
}

- (NSString *)packageSHA256ForHighestReleaseOfPluginIdentifier:(NSString *)pluginIdentifier
	publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	(void)error;
	return self.digests[[self stateKeyForPluginIdentifier:pluginIdentifier
		publisherKeyIdentifier:publisherKeyIdentifier]];
}

- (BOOL)storePublisherApproval:(BTPluginPublisherApproval *)approval error:(NSError **)error {
	(void)approval;
	(void)error;
	return YES;
}

- (BOOL)storeExactBuildApproval:(BTPluginExactBuildApproval *)approval error:(NSError **)error {
	(void)approval;
	(void)error;
	return YES;
}

- (BOOL)recordReleaseSequence:(uint64_t)releaseSequence packageSHA256:(NSString *)packageSHA256
	forPluginIdentifier:(NSString *)pluginIdentifier
	publisherKeyIdentifier:(NSString *)publisherKeyIdentifier error:(NSError **)error {
	self.commitInvocationCount++;
	if (self.failNextCommit) {
		self.failNextCommit = NO;
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"Injected rollback-state write failure.", nil, nil);
		return NO;
	}
	NSString *key = [self stateKeyForPluginIdentifier:pluginIdentifier
		publisherKeyIdentifier:publisherKeyIdentifier];
	self.sequences[key] = @(releaseSequence);
	self.digests[key] = packageSHA256;
	return YES;
}

- (BOOL)removePublisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	(void)keyIdentifier;
	(void)error;
	return YES;
}

- (BOOL)removeExactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	(void)packageSHA256;
	(void)error;
	return YES;
}

@end

@interface BTPluginRuntimeLoaderTestActivationStore : NSObject <BTPluginActivationStore>
@property (nonatomic) NSUInteger loadAttemptInvocationCount;
@property (nonatomic) BOOL failNextLoadAttempt;
@property (nonatomic, copy) NSString *lastPluginIdentifier;
@property (nonatomic, copy) NSString *lastPackageSHA256;
@property (nonatomic) BTPluginSource lastSource;
@property (nonatomic, copy) NSString *lastStartupIdentifier;
@end

@implementation BTPluginRuntimeLoaderTestActivationStore

- (BOOL)thirdPartyPluginsEnabledWithError:(NSError **)error { (void)error; return YES; }
- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError **)error {
	(void)enabled; (void)error; return YES;
}
- (NSArray<BTPluginActivationRecord *> *)activationRecordsWithError:(NSError **)error {
	(void)error; return @[];
}
- (BOOL)scheduleActivationRecord:(BTPluginActivationRecord *)record error:(NSError **)error {
	(void)record; (void)error; return YES;
}
- (BOOL)setPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled error:(NSError **)error {
	(void)pluginIdentifier; (void)enabled; (void)error; return YES;
}
- (BOOL)removePluginIdentifier:(NSString *)pluginIdentifier error:(NSError **)error {
	(void)pluginIdentifier; (void)error; return YES;
}
- (BTPluginStartupSnapshot *)beginStartupWithSafeModeRequested:(BOOL)safeModeRequested
	error:(NSError **)error {
	(void)safeModeRequested; (void)error; return nil;
}
- (BOOL)recordThirdPartyLoadAttemptForPluginIdentifier:(NSString *)pluginIdentifier
	packageSHA256:(NSString *)packageSHA256 source:(BTPluginSource)source
	startupIdentifier:(NSString *)startupIdentifier error:(NSError **)error {
	self.loadAttemptInvocationCount++;
	self.lastPluginIdentifier = pluginIdentifier;
	self.lastPackageSHA256 = packageSHA256;
	self.lastSource = source;
	self.lastStartupIdentifier = startupIdentifier;
	if (self.failNextLoadAttempt) {
		self.failNextLoadAttempt = NO;
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"Injected load-attempt write failure.", nil, nil);
		return NO;
	}
	return YES;
}
- (BOOL)markStartupSettledWithIdentifier:(NSString *)startupIdentifier error:(NSError **)error {
	(void)startupIdentifier; (void)error; return YES;
}
- (BOOL)disablePluginFromRecovery:(BTPluginStartupRecovery *)recovery error:(NSError **)error {
	(void)recovery; (void)error; return YES;
}

@end


@interface BTPluginRuntimeLoaderRecordingImageLoader : BTPluginNativeImageLoader
@property (nonatomic) NSUInteger prepareInvocationCount;
@property (nonatomic) NSUInteger loadInvocationCount;
@property (nonatomic) BOOL failPrepare;
@property (nonatomic) BOOL failLoad;
@property (nonatomic, strong) NSURL *lastExecutableURL;
@property (nonatomic, strong) BTPluginPreparedNativeImage *lastPreparedImage;
@property (nonatomic, copy) NSString *lastPluginIdentifier;
@property (nonatomic, copy) NSString *lastPluginVersion;
@property (nonatomic, copy) NSSet<NSString *> *lastExtensionPoints;
@property (nonatomic, weak) BTPluginRegistry *lastRegistry;
@property (nonatomic, copy) void (^beforePrepare)(BTPluginVerifiedPackage *verifiedPackage);
@property (nonatomic, copy) void (^afterPrepare)(BTPluginPreparedNativeImage *preparedImage);
@end

@implementation BTPluginRuntimeLoaderRecordingImageLoader

- (BTPluginPreparedNativeImage *)prepareImageForVerifiedPackage:
	(BTPluginVerifiedPackage *)verifiedPackage error:(NSError **)error {
	self.prepareInvocationCount++;
	if (self.beforePrepare)
		self.beforePrepare(verifiedPackage);
	if (self.failPrepare) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRaceDetected,
				@"Injected native image preparation failure.", nil, nil);
		return nil;
	}
	BTPluginPreparedNativeImage *prepared =
		[super prepareImageForVerifiedPackage:verifiedPackage error:error];
	if (prepared && self.afterPrepare)
		self.afterPrepare(prepared);
	self.lastPreparedImage = prepared;
	return prepared;
}

- (BOOL)loadPreparedImage:(BTPluginPreparedNativeImage *)preparedImage
	expectedPluginIdentifier:(NSString *)pluginIdentifier
	expectedPluginVersion:(NSString *)pluginVersion
	declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
	registry:(BTPluginRegistry *)registry error:(NSError **)error {
	self.loadInvocationCount++;
	self.lastPreparedImage = preparedImage;
	self.lastExecutableURL = preparedImage.stagedExecutableURL;
	self.lastPluginIdentifier = pluginIdentifier;
	self.lastPluginVersion = pluginVersion;
	self.lastExtensionPoints = declaredExtensionPoints;
	self.lastRegistry = registry;
	if (self.failLoad) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorRuntime,
				@"Injected native image load failure.", nil, nil);
		return NO;
	}
	return YES;
}

@end

static BTPluginTrustPolicy *BTPluginRuntimeLoaderTestPolicy(void) {
	NSError *error = nil;
	BTPluginTrustPolicy *policy = [[BTPluginTrustPolicy alloc]
		initWithOfficialPublicKeysByIdentifier:@{} officialScopesByKeyIdentifier:@{}
		revokedKeyIdentifiers:[NSSet set] metadataSequence:1
		metadataUpdatedAt:[NSDate dateWithTimeIntervalSince1970:1] error:&error];
	BTAssert(policy != nil, error.localizedDescription.UTF8String);
	return policy;
}

static BTPluginStartupSnapshot *BTPluginRuntimeLoaderTestSnapshot(BOOL thirdPartyEnabled,
	BOOL safeMode, NSString *startupIdentifier) {
	BTPluginStartupSnapshot *snapshot = [[BTPluginStartupSnapshot alloc] bt_init];
	[snapshot setStartupIdentifier:startupIdentifier];
	[snapshot setSafeMode:safeMode];
	[snapshot setThirdPartyPluginsEnabled:thirdPartyEnabled];
	[snapshot setActivationRecords:@[]];
	[snapshot setRecovery:nil];
	return snapshot;
}

static BTPluginActivationRecord *BTPluginRuntimeLoaderTestActivationRecord(NSString *digest,
	BTPluginSource source, BOOL enabled) {
	NSError *error = nil;
	BTPluginActivationRecord *record = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:BTPluginTestSignedPackageIdentifier packageSHA256:digest source:source
		activationMode:BTPluginActivationModeDirect enabled:enabled
		updatedAt:[NSDate dateWithTimeIntervalSince1970:1] error:&error];
	BTAssert(record != nil, error.localizedDescription.UTF8String);
	return record;
}

static BTPluginRegistry *BTPluginRuntimeLoaderTestRegistry(uint32_t interfaceVersion) {
	BTPluginRegistry *registry = [BTPluginRegistry new];
	NSError *error = nil;
	BTAssert([registry registerExtensionPointIdentifier:BTPluginTestSignedPackageExtensionPoint
		interfaceVersion:interfaceVersion requiredProtocol:@protocol(NSObject) error:&error],
		error.localizedDescription.UTF8String);
	return registry;
}

static BTPluginDiscoveredPackage *BTPluginRuntimeLoaderTestDiscover(NSURL *rootURL) {
	BTPluginDiscoveryResult *result = [[BTPluginDiscovery new] discoverRoots:@[
		[BTPluginDiscoveryRoot transportPackageRootURL:rootURL source:BTPluginSourceApplicationData],
	]];
	BTAssert(result.diagnostics.count == 0, "valid runtime fixture produced a discovery diagnostic");
	BTAssert(result.packages.count == 1, "valid runtime fixture was not discovered exactly once");
	return result.packages.firstObject;
}

static BTPluginRuntimeLoader *BTPluginRuntimeLoaderTestLoader(BTPluginPackageVerifier *verifier,
	BTPluginRegistry *registry, BTPluginRuntimeLoaderTestActivationStore *activationStore,
	BTPluginRuntimeEnvironment *environment,
	BTPluginRuntimeLoaderRecordingImageLoader *imageLoader) {
	BTPluginRuntimeLoader *loader = [[BTPluginRuntimeLoader alloc]
		initWithPackageVerifier:verifier registry:registry activationStore:activationStore
		environment:environment nativeImageLoaderForTesting:imageLoader];
	BTAssert(loader != nil, "runtime loader dependency composition failed");
	return loader;
}

static BTPluginPackageManifest *BTPluginRuntimeLoaderTestManifestWithExtensionPoints(
	NSDictionary *baseManifest, NSArray<NSDictionary *> *extensionPoints) {
	NSMutableDictionary *dictionary = [baseManifest mutableCopy];
	dictionary[@"extensionPoints"] = extensionPoints;
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary
		options:NSJSONWritingSortedKeys error:&error];
	BTAssert(data != nil, error.localizedDescription.UTF8String);
	BTPluginPackageManifest *manifest = [BTPluginPackageManifest manifestWithData:data error:&error];
	BTAssert(manifest != nil, error.localizedDescription.UTF8String);
	return manifest;
}

static NSURL *BTPluginRuntimeLoaderTestCreateRoot(NSURL *temporaryURL, NSString *name) {
	NSURL *rootURL = [temporaryURL URLByAppendingPathComponent:name isDirectory:YES];
	NSError *error = nil;
	BTAssert([[NSFileManager defaultManager] createDirectoryAtURL:rootURL
		withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @0700 } error:&error],
		error.localizedDescription.UTF8String);
	return rootURL;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTAssert(argc == 2, "expected signed iOS constructor fixture path");
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-runtime-loader-tests-%@",
				NSUUID.UUID.UUIDString]] isDirectory:YES];
		BTAssert([manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:YES
			attributes:@{ NSFilePosixPermissions: @0700 } error:&error], error.localizedDescription.UTF8String);
		NSURL *fixtureURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		NSURL *installedRootURL = BTPluginRuntimeLoaderTestCreateRoot(temporaryURL, @"Installed");
		BTPluginTestCreateSignedPackage(installedRootURL, fixtureURL,
			[BTPluginTestSignedPackageIdentifier stringByAppendingPathExtension:@"battman"]);
		BTPluginDiscoveredPackage *discovered = BTPluginRuntimeLoaderTestDiscover(installedRootURL);
		BTAssert([discovered.claimedPluginIdentifier isEqualToString:BTPluginTestSignedPackageIdentifier],
			"canonical installed package did not preserve its claimed identifier");

		NSString *sentinelPath = [temporaryURL.path stringByAppendingPathComponent:@"constructor-ran"];
		BTAssert(setenv("BT_PLUGIN_CONSTRUCTOR_SENTINEL", sentinelPath.fileSystemRepresentation, 1) == 0,
			"could not configure constructor sentinel");
		BTAssert(![manager fileExistsAtPath:sentinelPath], "constructor ran before runtime verification");

		BTPluginRuntimeLoaderTestTrustStore *trustStore = [BTPluginRuntimeLoaderTestTrustStore new];
		BTPluginTrustEvaluator *evaluator = [[BTPluginTrustEvaluator alloc]
			initWithPolicy:BTPluginRuntimeLoaderTestPolicy() trustStore:trustStore];
		NSOperatingSystemVersion iOS17 = { .majorVersion = 17, .minorVersion = 2, .patchVersion = 0 };
		BTPluginPackageVerifier *verifier = [[BTPluginPackageVerifier alloc]
			initWithTrustEvaluator:evaluator hostIOSVersion:iOS17];
		BTPluginVerifiedPackage *preverified = [verifier verifyPackageAtURL:discovered.packageURL
			developerMode:YES error:&error];
		BTAssert(preverified != nil && preverified.isApprovedForActivation &&
			preverified.trustEvaluation.disposition == BTPluginTrustDispositionDeveloper,
			(error.localizedDescription ?: @"developer fixture did not pass complete non-executing verification").UTF8String);
		NSString *digest = preverified.packageInspection.packageSHA256;
		NSDictionary *baseManifest = [NSJSONSerialization JSONObjectWithData:
			[NSData dataWithContentsOfURL:[discovered.packageURL URLByAppendingPathComponent:@"Manifest.json"]]
			options:0 error:&error];
		BTAssert([baseManifest isKindOfClass:[NSDictionary class]], error.localizedDescription.UTF8String);
		BTPluginPackageManifest *previousManifest = BTPluginRuntimeLoaderTestManifestWithExtensionPoints(baseManifest, @[
			@{ @"identifier": BTPluginTestSignedPackageExtensionPoint, @"interfaceVersion": @1 },
			@{ @"identifier": @"com.example.battman.removed.v1", @"interfaceVersion": @1 },
		]);
		NSMutableDictionary *newerBaseManifest = [baseManifest mutableCopy];
		newerBaseManifest[@"releaseSequence"] = @2;
		BTPluginPackageManifest *currentManifest = BTPluginRuntimeLoaderTestManifestWithExtensionPoints(newerBaseManifest, @[
			@{ @"identifier": BTPluginTestSignedPackageExtensionPoint, @"interfaceVersion": @2 },
			@{ @"identifier": @"com.example.battman.added.v1", @"interfaceVersion": @1 },
		]);
		NSArray<BTPluginExtensionPointChange *> *changes =
			BTPluginExtensionPointChangesFromManifests(previousManifest, currentManifest);
		BTAssert(changes.count == 3 &&
			[changes[0].identifier isEqualToString:@"com.example.battman.added.v1"] &&
			changes[0].kind == BTPluginExtensionPointChangeKindAdded &&
			[changes[1].identifier isEqualToString:@"com.example.battman.removed.v1"] &&
			changes[1].kind == BTPluginExtensionPointChangeKindRemoved &&
			[changes[2].identifier isEqualToString:BTPluginTestSignedPackageExtensionPoint] &&
			changes[2].kind == BTPluginExtensionPointChangeKindVersionChanged &&
			changes[2].previousInterfaceVersion.unsignedIntValue == 1 &&
			changes[2].currentInterfaceVersion.unsignedIntValue == 2,
			"extension-point delta comparison was not deterministic or complete");
		NSMutableDictionary *changedPublisherDictionary = [newerBaseManifest mutableCopy];
		NSMutableDictionary *changedPublisher = [changedPublisherDictionary[@"publisher"] mutableCopy];
		NSString *changedKey = [@"" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0];
		changedPublisher[@"primaryKeyIdentifier"] = changedKey;
		changedPublisher[@"signatureKeyIdentifiers"] = @[ changedKey ];
		changedPublisherDictionary[@"publisher"] = changedPublisher;
		BTPluginPackageManifest *changedPublisherManifest =
			BTPluginRuntimeLoaderTestManifestWithExtensionPoints(changedPublisherDictionary,
				newerBaseManifest[@"extensionPoints"]);
		BTAssert(BTPluginManifestUpdateLineageStatusFromManifests(previousManifest, currentManifest) ==
			BTPluginManifestUpdateLineageStatusAvailable &&
			BTPluginManifestUpdateLineageStatusFromManifests(nil, currentManifest) ==
			BTPluginManifestUpdateLineageStatusNoPriorVersion &&
			BTPluginManifestUpdateLineageStatusFromManifests(previousManifest, previousManifest) ==
			BTPluginManifestUpdateLineageStatusNotNewer &&
			BTPluginManifestUpdateLineageStatusFromManifests(previousManifest, changedPublisherManifest) ==
			BTPluginManifestUpdateLineageStatusPublisherChanged &&
			BTPluginExtensionPointChangesFromManifests(previousManifest, previousManifest).count == 0 &&
			BTPluginExtensionPointChangesFromManifests(nil, currentManifest).count == 0 &&
			BTPluginExtensionPointChangesFromManifests(previousManifest, changedPublisherManifest).count == 0,
			"extension-point delta comparison accepted an unavailable or unsafe publisher lineage");
		BTPluginActivationRecord *activationRecord = BTPluginRuntimeLoaderTestActivationRecord(digest,
			BTPluginSourceApplicationData, YES);
		BTPluginStartupSnapshot *enabledSnapshot = BTPluginRuntimeLoaderTestSnapshot(YES, NO, @"startup-enabled");
		BTPluginRuntimeEnvironment *directEnvironment = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:@"/Applications/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindJailbrokenDirect];

		BTPluginRuntimeLoaderTestActivationStore *activationStore = [BTPluginRuntimeLoaderTestActivationStore new];
		BTPluginRuntimeLoaderRecordingImageLoader *imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		BTPluginRegistry *registry = BTPluginRuntimeLoaderTestRegistry(1);
		BTPluginRuntimeLoadResult *loaded = [BTPluginRuntimeLoaderTestLoader(verifier, registry,
			activationStore, directEnvironment, imageLoader) loadDiscoveredPackage:discovered
			activationRecord:activationRecord startupSnapshot:enabledSnapshot developerMode:YES error:&error];
		BTAssert(loaded != nil && loaded.isThirdParty && loaded.discoveredPackage == discovered,
			(error.localizedDescription ?: @"approved composed runtime load failed").UTF8String);
		BTAssert(trustStore.commitInvocationCount == 1 && activationStore.loadAttemptInvocationCount == 1 &&
			imageLoader.prepareInvocationCount == 1 && imageLoader.loadInvocationCount == 1,
			"approved load did not traverse each staging and state boundary exactly once");
		BTAssert([activationStore.lastPluginIdentifier isEqualToString:BTPluginTestSignedPackageIdentifier] &&
			[activationStore.lastPackageSHA256 isEqualToString:digest] &&
			activationStore.lastSource == BTPluginSourceApplicationData &&
			[activationStore.lastStartupIdentifier isEqualToString:@"startup-enabled"],
			"crash-recovery marker did not receive the exact verified activation identity");
		NSURL *stagedContentRoot = [imageLoader.lastPreparedImage.stageRootURL
			URLByAppendingPathComponent:digest isDirectory:YES];
		BTAssert(![imageLoader.lastExecutableURL isEqual:preverified.packageInspection.executableURL] &&
			[imageLoader.lastPreparedImage.contentSHA256 isEqualToString:digest] &&
			[manager fileExistsAtPath:imageLoader.lastExecutableURL.path] &&
			[manager fileExistsAtPath:[[stagedContentRoot
				URLByAppendingPathComponent:@"Example.bundle/Info.plist"] path]] &&
			![manager fileExistsAtPath:[[stagedContentRoot
				URLByAppendingPathComponent:@"Manifest.json"] path]] &&
			[imageLoader.lastPluginIdentifier isEqualToString:BTPluginTestSignedPackageIdentifier] &&
			[imageLoader.lastPluginVersion isEqualToString:@"1"] &&
			[imageLoader.lastExtensionPoints isEqualToSet:[NSSet setWithObject:BTPluginTestSignedPackageExtensionPoint]] &&
			imageLoader.lastRegistry == registry,
			"native loader did not receive the pinned bytes and exact verified manifest contract");
		BTAssert(![manager fileExistsAtPath:sentinelPath],
			"constructor executed before the injected final native-loader boundary");

		NSUInteger commitBaseline = trustStore.commitInvocationCount;
		NSUInteger attemptBaseline = activationStore.loadAttemptInvocationCount;
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:NO error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline &&
			activationStore.loadAttemptInvocationCount == attemptBaseline,
			"unapproved third-party package reached an activation or native-loader boundary");

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:BTPluginRuntimeLoaderTestSnapshot(YES, YES, @"startup-safe")
			developerMode:YES error:&error] && imageLoader.prepareInvocationCount == 0 &&
			imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"safe mode allowed a third-party package to reach activation commit or native loading");

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:BTPluginRuntimeLoaderTestSnapshot(NO, NO, @"startup-disabled")
			developerMode:YES error:&error] && imageLoader.prepareInvocationCount == 0 &&
			imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"globally disabled third-party package reached activation commit or native loading");

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:nil startupSnapshot:enabledSnapshot
			developerMode:YES error:&error] && imageLoader.prepareInvocationCount == 0 &&
			imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"third-party package without an exact restart record reached native loading");

		NSString *wrongDigest = [@"" stringByPaddingToLength:64 withString:@"f" startingAtIndex:0];
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered
			activationRecord:BTPluginRuntimeLoaderTestActivationRecord(wrongDigest,
				BTPluginSourceApplicationData, YES) startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"mismatched package digest reached activation commit or native loading");

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, BTPluginRuntimeLoaderTestRegistry(2),
			activationStore, directEnvironment, imageLoader) loadDiscoveredPackage:discovered
			activationRecord:activationRecord startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"incompatible extension-point interface reached activation commit or native loading");

		BTPluginRuntimeEnvironment *replacementEnvironment = [[BTPluginRuntimeEnvironment alloc]
			initWithApplicationBundleURL:[NSURL fileURLWithPath:@"/Applications/Battman.app" isDirectory:YES]
			installationKind:BTPluginRuntimeInstallationKindTrollStoreReplacement];
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, replacementEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"TrollStore app-data package bypassed the replacement-app runtime policy");

		NSURL *wrongNameRootURL = BTPluginRuntimeLoaderTestCreateRoot(temporaryURL, @"WrongName");
		BTPluginTestCreateSignedPackage(wrongNameRootURL, fixtureURL, @"com.example.wrong.battman");
		BTPluginDiscoveredPackage *wrongNamePackage = BTPluginRuntimeLoaderTestDiscover(wrongNameRootURL);
		BTPluginVerifiedPackage *wrongNameVerified = [verifier verifyPackageAtURL:wrongNamePackage.packageURL
			developerMode:YES error:&error];
		BTAssert(wrongNameVerified != nil, error.localizedDescription.UTF8String);
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:wrongNamePackage
			activationRecord:BTPluginRuntimeLoaderTestActivationRecord(
				wrongNameVerified.packageInspection.packageSHA256, BTPluginSourceApplicationData, YES)
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline,
			"installed filename/verified identifier mismatch reached activation commit or native loading");

		trustStore.failNextCommit = YES;
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 1 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline + 1 &&
			activationStore.loadAttemptInvocationCount == attemptBaseline,
			"failed anti-rollback commit reached crash marker or native loading");
		commitBaseline = trustStore.commitInvocationCount;

		activationStore.failNextLoadAttempt = YES;
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 1 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline + 1 &&
			activationStore.loadAttemptInvocationCount == attemptBaseline + 1,
			"failed crash-recovery marker write reached native loading");
		commitBaseline = trustStore.commitInvocationCount;
		attemptBaseline = activationStore.loadAttemptInvocationCount;

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		imageLoader.failLoad = YES;
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:discovered activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 1 && imageLoader.loadInvocationCount == 1 &&
			trustStore.commitInvocationCount == commitBaseline + 1 &&
			activationStore.loadAttemptInvocationCount == attemptBaseline + 1,
			"native-loader failure did not remain after rollback and crash-marker commits");
		commitBaseline = trustStore.commitInvocationCount;
		attemptBaseline = activationStore.loadAttemptInvocationCount;

		NSURL *tamperedRootURL = BTPluginRuntimeLoaderTestCreateRoot(temporaryURL, @"Tampered");
		NSURL *tamperedPackageURL = BTPluginTestCreateSignedPackage(tamperedRootURL, fixtureURL,
			[BTPluginTestSignedPackageIdentifier stringByAppendingPathExtension:@"battman"]);
		NSURL *tamperedExecutableURL = [tamperedPackageURL URLByAppendingPathComponent:@"Example.bundle/Example"];
		NSFileHandle *tamperedHandle = [NSFileHandle fileHandleForWritingToURL:tamperedExecutableURL error:&error];
		BTAssert(tamperedHandle != nil, error.localizedDescription.UTF8String);
		[tamperedHandle seekToEndOfFile];
		[tamperedHandle writeData:[NSData dataWithBytes:"\0" length:1]];
		[tamperedHandle closeFile];
		BTPluginDiscoveredPackage *tamperedPackage = BTPluginRuntimeLoaderTestDiscover(tamperedRootURL);
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:tamperedPackage activationRecord:activationRecord
			startupSnapshot:enabledSnapshot developerMode:YES error:&error] &&
			imageLoader.prepareInvocationCount == 0 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline &&
			activationStore.loadAttemptInvocationCount == attemptBaseline,
			"tampered package reached activation state or native loading");

		NSURL *prepareMismatchRootURL = BTPluginRuntimeLoaderTestCreateRoot(temporaryURL, @"PrepareMismatch");
		BTPluginTestCreateSignedPackage(prepareMismatchRootURL, fixtureURL,
			[BTPluginTestSignedPackageIdentifier stringByAppendingPathExtension:@"battman"]);
		BTPluginDiscoveredPackage *prepareMismatchPackage =
			BTPluginRuntimeLoaderTestDiscover(prepareMismatchRootURL);
		BTPluginVerifiedPackage *prepareMismatchVerified = [verifier
			verifyPackageAtURL:prepareMismatchPackage.packageURL developerMode:YES error:&error];
		BTAssert(prepareMismatchVerified != nil, error.localizedDescription.UTF8String);
		NSString *prepareMismatchDigest = prepareMismatchVerified.packageInspection.packageSHA256;
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		imageLoader.beforePrepare = ^(BTPluginVerifiedPackage *verifiedPackage) {
			NSError *mutationError = nil;
			NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:
				verifiedPackage.packageInspection.executableURL error:&mutationError];
			BTAssert(handle != nil, mutationError.localizedDescription.UTF8String);
			[handle seekToEndOfFile];
			[handle writeData:[NSData dataWithBytes:"\0" length:1]];
			[handle closeFile];
		};
		error = nil;
		BTAssert(![BTPluginRuntimeLoaderTestLoader(verifier, registry, activationStore, directEnvironment,
			imageLoader) loadDiscoveredPackage:prepareMismatchPackage
			activationRecord:BTPluginRuntimeLoaderTestActivationRecord(prepareMismatchDigest,
				BTPluginSourceApplicationData, YES) startupSnapshot:enabledSnapshot
			developerMode:YES error:&error] && error.code == BTPluginPackageErrorRaceDetected &&
			imageLoader.prepareInvocationCount == 1 && imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline &&
			activationStore.loadAttemptInvocationCount == attemptBaseline,
			"post-verification source mutation reached activation state or dlopen preparation");

		NSURL *pinnedRaceRootURL = BTPluginRuntimeLoaderTestCreateRoot(temporaryURL, @"PinnedRace");
		BTPluginTestCreateSignedPackage(pinnedRaceRootURL, fixtureURL,
			[BTPluginTestSignedPackageIdentifier stringByAppendingPathExtension:@"battman"]);
		BTPluginDiscoveredPackage *pinnedRacePackage = BTPluginRuntimeLoaderTestDiscover(pinnedRaceRootURL);
		BTPluginVerifiedPackage *pinnedRaceVerified = [verifier verifyPackageAtURL:pinnedRacePackage.packageURL
			developerMode:YES error:&error];
		BTAssert(pinnedRaceVerified != nil, error.localizedDescription.UTF8String);
		NSString *pinnedRaceDigest = pinnedRaceVerified.packageInspection.packageSHA256;
		NSURL *pinnedSourceURL = pinnedRaceVerified.packageInspection.executableURL;
		NSURL *pinnedBackupURL = [pinnedSourceURL URLByAppendingPathExtension:@"verified-backup"];
		NSData *unverifiedReplacement = [@"unverified native replacement"
			dataUsingEncoding:NSUTF8StringEncoding];
		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		imageLoader.afterPrepare = ^(BTPluginPreparedNativeImage *preparedImage) {
			(void)preparedImage;
			NSError *mutationError = nil;
			BTAssert([manager moveItemAtURL:pinnedSourceURL toURL:pinnedBackupURL error:&mutationError],
				mutationError.localizedDescription.UTF8String);
			BTAssert([unverifiedReplacement writeToURL:pinnedSourceURL
				options:NSDataWritingAtomic error:&mutationError], mutationError.localizedDescription.UTF8String);
		};
		error = nil;
		BTPluginRuntimeLoadResult *pinnedLoad = [BTPluginRuntimeLoaderTestLoader(verifier, registry,
			activationStore, directEnvironment, imageLoader) loadDiscoveredPackage:pinnedRacePackage
			activationRecord:BTPluginRuntimeLoaderTestActivationRecord(pinnedRaceDigest,
				BTPluginSourceApplicationData, YES) startupSnapshot:enabledSnapshot
			developerMode:YES error:&error];
		NSData *stagedExecutableData = [NSData dataWithContentsOfURL:imageLoader.lastExecutableURL
			options:0 error:&error];
		NSData *verifiedBackupData = [NSData dataWithContentsOfURL:pinnedBackupURL options:0 error:&error];
		BTAssert(pinnedLoad != nil && imageLoader.prepareInvocationCount == 1 &&
			imageLoader.loadInvocationCount == 1 &&
			[imageLoader.lastPreparedImage.contentSHA256 isEqualToString:pinnedRaceDigest] &&
			[stagedExecutableData isEqualToData:verifiedBackupData] &&
			![[NSData dataWithContentsOfURL:pinnedSourceURL] isEqualToData:stagedExecutableData] &&
			trustStore.commitInvocationCount == commitBaseline + 1 &&
			activationStore.loadAttemptInvocationCount == attemptBaseline + 1,
			(error.localizedDescription ?: @"the source rename/replace escaped private byte pinning").UTF8String);
		commitBaseline = trustStore.commitInvocationCount;
		attemptBaseline = activationStore.loadAttemptInvocationCount;

		imageLoader = [BTPluginRuntimeLoaderRecordingImageLoader new];
		BTPluginRuntimeLoader *backgroundLoader = BTPluginRuntimeLoaderTestLoader(verifier, registry,
			activationStore, directEnvironment, imageLoader);
		__block BOOL backgroundRejected = NO;
		dispatch_semaphore_t backgroundFinished = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError *backgroundError = nil;
			backgroundRejected = ![backgroundLoader loadDiscoveredPackage:discovered
				activationRecord:activationRecord startupSnapshot:enabledSnapshot developerMode:YES
				error:&backgroundError] && backgroundError.code == BTPluginPackageErrorRuntime;
			dispatch_semaphore_signal(backgroundFinished);
		});
		BTAssert(dispatch_semaphore_wait(backgroundFinished,
			dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))) == 0,
			"background runtime-loader check timed out");
		BTAssert(backgroundRejected && imageLoader.prepareInvocationCount == 0 &&
			imageLoader.loadInvocationCount == 0 &&
			trustStore.commitInvocationCount == commitBaseline &&
			activationStore.loadAttemptInvocationCount == attemptBaseline,
			"background activation reached verification, state mutation, or native loading");
		BTAssert(![manager fileExistsAtPath:sentinelPath],
			"constructor executed during composed verification or a rejected runtime path");

		BTAssert(unsetenv("BT_PLUGIN_CONSTRUCTOR_SENTINEL") == 0,
			"could not clear constructor sentinel environment");
		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		puts("Composed verifier, trust, activation, safe-mode, and native-loader boundary tests passed.");
	}
	return 0;
}
