//
//  BTPluginRuntimeLoader.m
//  Battman
//

#import "BTPluginRuntimeLoader.h"
#import "BTPluginRuntimeLoaderInternal.h"

#import "BTPluginNativeImageLoaderPrivate.h"
#import "../BTPluginRegistry.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"
#import "../Security/BTPluginTrustEvaluator.h"

static BOOL BTPluginLoaderFail(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorRuntime, description, nil, nil);
	return NO;
}

@interface BTPluginRuntimeLoadResult ()
@property (nonatomic, strong, readwrite) BTPluginDiscoveredPackage *discoveredPackage;
@property (nonatomic, strong, readwrite) BTPluginVerifiedPackage *verifiedPackage;
@property (nonatomic, readwrite, getter=isThirdParty) BOOL thirdParty;
- (instancetype)bt_init;
@end

@implementation BTPluginRuntimeLoadResult
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginRuntimeLoader ()
@property (nonatomic, strong) BTPluginPackageVerifier *packageVerifier;
@property (nonatomic, strong) BTPluginRegistry *registry;
@property (nonatomic, strong) id<BTPluginActivationStore> activationStore;
@property (nonatomic, strong) BTPluginRuntimeEnvironment *environment;
@property (nonatomic, strong) BTPluginNativeImageLoader *nativeImageLoader;
@end

@implementation BTPluginRuntimeLoader

- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
								 registry:(BTPluginRegistry *)registry
					 activationStore:(id<BTPluginActivationStore>)activationStore
							environment:(BTPluginRuntimeEnvironment *)environment {
	self = [super init];
	if (!self)
		return nil;
	if (![packageVerifier isKindOfClass:[BTPluginPackageVerifier class]] ||
		![registry isKindOfClass:[BTPluginRegistry class]] || !activationStore ||
		![environment isKindOfClass:[BTPluginRuntimeEnvironment class]])
		return nil;
	_packageVerifier = packageVerifier;
	_registry = registry;
	_activationStore = activationStore;
	_environment = environment;
	_nativeImageLoader = [BTPluginNativeImageLoader new];
	return self;
}

- (instancetype)initWithPackageVerifier:(BTPluginPackageVerifier *)packageVerifier
								 registry:(BTPluginRegistry *)registry
						 activationStore:(id<BTPluginActivationStore>)activationStore
							 environment:(BTPluginRuntimeEnvironment *)environment
			 nativeImageLoaderForTesting:(BTPluginNativeImageLoader *)nativeImageLoader {
	if (![nativeImageLoader isKindOfClass:[BTPluginNativeImageLoader class]])
		return nil;
	self = [self initWithPackageVerifier:packageVerifier registry:registry
		activationStore:activationStore environment:environment];
	if (self)
		_nativeImageLoader = nativeImageLoader;
	return self;
}

- (BTPluginRuntimeLoadResult *)loadDiscoveredPackage:(BTPluginDiscoveredPackage *)discoveredPackage
											 activationRecord:(BTPluginActivationRecord *)activationRecord
											startupSnapshot:(BTPluginStartupSnapshot *)startupSnapshot
												developerMode:(BOOL)developerMode
														 error:(NSError **)error {
	if (![NSThread isMainThread]) {
		BTPluginLoaderFail(error, @"Plug-in startup activation must run on the main thread.");
		return nil;
	}
	if (![discoveredPackage isKindOfClass:[BTPluginDiscoveredPackage class]] ||
		![startupSnapshot isKindOfClass:[BTPluginStartupSnapshot class]] ||
		!BTPluginSourceCanActivate(discoveredPackage.source)) {
		BTPluginLoaderFail(error, @"The discovered plug-in is not a directly loadable installed package.");
		return nil;
	}
	if (discoveredPackage.source == BTPluginSourceApplicationData &&
		!self.environment.allowsApplicationDataNativeLoading) {
		BTPluginLoaderFail(error,
			@"This installation requires native app-data plug-ins to be embedded in a replacement Battman app.");
		return nil;
	}

	// This complete verification occurs in the same method and immediately
	// before the one private image-loader call below.
	BTPluginVerifiedPackage *verified = nil;
	if (discoveredPackage.representation == BTPluginInstalledRepresentationTransportPackage) {
		verified = [self.packageVerifier verifyPackageAtURL:discoveredPackage.packageURL
			developerMode:developerMode error:error];
	} else if (discoveredPackage.representation == BTPluginInstalledRepresentationSealedAppBundle &&
		discoveredPackage.metadataURL && discoveredPackage.payloadURL) {
		verified = [self.packageVerifier verifySealedMetadataAtURL:discoveredPackage.metadataURL
			payloadURL:discoveredPackage.payloadURL developerMode:developerMode error:error];
	} else {
		BTPluginLoaderFail(error, @"The discovered plug-in representation is unsupported.");
		return nil;
	}
	if (!verified)
		return nil;
	BTPluginPackageManifest *manifest = verified.packageInspection.manifest;
	if (![manifest.pluginIdentifier isEqualToString:discoveredPackage.claimedPluginIdentifier]) {
		BTPluginLoaderFail(error, @"The installed package name does not match its verified plug-in identifier.");
		return nil;
	}
	BOOL thirdParty = verified.trustEvaluation.disposition != BTPluginTrustDispositionOfficial;
	if (!verified.isApprovedForActivation) {
		BTPluginLoaderFail(error, @"The plug-in has not received an offline trust approval.");
		return nil;
	}
	if (thirdParty && (!startupSnapshot.areThirdPartyPluginsEnabled || startupSnapshot.isSafeMode)) {
		BTPluginLoaderFail(error, @"Third-party native plug-ins are disabled for this startup.");
		return nil;
	}
	BOOL requiresActivationRecord = thirdParty || discoveredPackage.source == BTPluginSourceApplicationData;
	if (requiresActivationRecord && ![activationRecord isKindOfClass:[BTPluginActivationRecord class]]) {
		BTPluginLoaderFail(error, @"This installed plug-in requires an exact restart activation record.");
		return nil;
	}
	if (activationRecord) {
		BOOL directMatch = activationRecord.activationMode == BTPluginActivationModeDirect &&
			activationRecord.source == discoveredPackage.source;
		BOOL replacementMatch = discoveredPackage.representation == BTPluginInstalledRepresentationSealedAppBundle &&
			activationRecord.activationMode == BTPluginActivationModeRequiresReinstall &&
			activationRecord.source == BTPluginSourceImport;
		if (!activationRecord.isEnabled || (!directMatch && !replacementMatch) ||
			![activationRecord.pluginIdentifier isEqualToString:manifest.pluginIdentifier] ||
			![activationRecord.packageSHA256 isEqualToString:verified.packageInspection.packageSHA256]) {
			BTPluginLoaderFail(error, @"The startup activation record does not match the verified installed package.");
			return nil;
		}
	}
	for (BTPluginManifestExtensionPoint *extensionPoint in manifest.extensionPoints) {
		NSNumber *supportedVersion = [self.registry
			interfaceVersionForExtensionPointIdentifier:extensionPoint.identifier];
		if (!supportedVersion || supportedVersion.unsignedIntValue != extensionPoint.interfaceVersion) {
			BTPluginLoaderFail(error,
				@"The verified plug-in declares an unknown or incompatible extension-point interface version.");
			return nil;
		}
	}
	// Pin exactly the verified payload inventory before any irreversible trust
	// or crash-recovery state advances. The later pathname-based dlopen can then
	// consume only this process-private copy, even if the installed source is
	// renamed or replaced in the meantime.
	BTPluginPreparedNativeImage *preparedImage =
		[self.nativeImageLoader prepareImageForVerifiedPackage:verified error:error];
	if (!preparedImage)
		return nil;

	if (![self.packageVerifier recordActivationCommitForVerifiedPackage:verified error:error])
		return nil;
	if (thirdParty && ![self.activationStore recordThirdPartyLoadAttemptForPluginIdentifier:manifest.pluginIdentifier
		packageSHA256:verified.packageInspection.packageSHA256 source:discoveredPackage.source
		startupIdentifier:startupSnapshot.startupIdentifier error:error])
		return nil;

	NSMutableSet<NSString *> *declaredExtensionPoints = [NSMutableSet set];
	for (BTPluginManifestExtensionPoint *extensionPoint in manifest.extensionPoints)
		[declaredExtensionPoints addObject:extensionPoint.identifier];
	if (![self.nativeImageLoader loadPreparedImage:preparedImage
		expectedPluginIdentifier:manifest.pluginIdentifier expectedPluginVersion:manifest.buildVersion
		declaredExtensionPoints:declaredExtensionPoints registry:self.registry error:error])
		return nil;

	BTPluginRuntimeLoadResult *result = [[BTPluginRuntimeLoadResult alloc] bt_init];
	result.discoveredPackage = discoveredPackage;
	result.verifiedPackage = verified;
	result.thirdParty = thirdParty;
	return result;
}

@end
