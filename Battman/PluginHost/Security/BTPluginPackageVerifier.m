//
//  BTPluginPackageVerifier.m
//  Battman
//

#import "BTPluginPackageVerifier.h"

#import "../Model/BTPluginPackageErrors.h"
#import "BTPluginPlatformLoadabilityVerifier.h"
#import "BTPluginSealedPackageStructuralVerifier.h"

@interface BTPluginVerifiedPackage ()
@property (nonatomic, strong, readwrite) BTPluginPackageInspection *packageInspection;
@property (nonatomic, strong, readwrite) BTPluginMachOInspection *machOInspection;
@property (nonatomic, strong, readwrite) BTPluginTrustEvaluation *trustEvaluation;
- (instancetype)bt_init;
@end

@implementation BTPluginVerifiedPackage
- (instancetype)bt_init { return [super init]; }
- (BOOL)isApprovedForActivation { return self.trustEvaluation.isApprovedForActivation; }
@end

@interface BTPluginPackageVerifier ()
@property (nonatomic, strong) BTPluginTrustEvaluator *trustEvaluator;
@property (nonatomic) NSOperatingSystemVersion hostIOSVersion;
@property (nonatomic, strong) BTPluginPackageStructuralVerifier *structuralVerifier;
@property (nonatomic, strong) BTPluginSealedPackageStructuralVerifier *sealedStructuralVerifier;
@property (nonatomic, strong) BTPluginMachOInspector *machOInspector;
@property (nonatomic, strong) BTPluginPlatformLoadabilityVerifier *platformVerifier;
@end

@implementation BTPluginPackageVerifier

- (instancetype)initWithTrustEvaluator:(BTPluginTrustEvaluator *)trustEvaluator
						 hostIOSVersion:(NSOperatingSystemVersion)hostIOSVersion {
	self = [super init];
	if (self) {
		_trustEvaluator = trustEvaluator;
		_hostIOSVersion = hostIOSVersion;
		_structuralVerifier = [BTPluginPackageStructuralVerifier new];
		_sealedStructuralVerifier = [BTPluginSealedPackageStructuralVerifier new];
		_machOInspector = [BTPluginMachOInspector new];
		_platformVerifier = [BTPluginPlatformLoadabilityVerifier new];
	}
	return self;
}

- (BTPluginVerifiedPackage *)verifyPackageAtURL:(NSURL *)packageURL
									 developerMode:(BOOL)developerMode
											   error:(NSError **)error {
	BTPluginPackageInspection *packageInspection = [self.structuralVerifier inspectPackageAtURL:packageURL error:error];
	return [self verifyInspection:packageInspection developerMode:developerMode error:error];
}

- (BTPluginVerifiedPackage *)verifySealedMetadataAtURL:(NSURL *)metadataURL
														payloadURL:(NSURL *)payloadURL
												 developerMode:(BOOL)developerMode
															error:(NSError **)error {
	BTPluginPackageInspection *packageInspection = [self.sealedStructuralVerifier
		inspectMetadataAtURL:metadataURL payloadURL:payloadURL error:error];
	return [self verifyInspection:packageInspection developerMode:developerMode error:error];
}

- (BTPluginVerifiedPackage *)verifyInspection:(BTPluginPackageInspection *)packageInspection
										 developerMode:(BOOL)developerMode
													error:(NSError **)error {
	if (!packageInspection)
		return nil;
	BTPluginMachOInspection *machOInspection = [self.machOInspector inspectPackageInspection:packageInspection
		hostIOSVersion:self.hostIOSVersion error:error];
	if (!machOInspection)
		return nil;
	if (![self.platformVerifier verifyPackageInspection:packageInspection machOInspection:machOInspection error:error])
		return nil;
	BTPluginTrustEvaluation *trustEvaluation = [self.trustEvaluator evaluateInspection:packageInspection
		developerMode:developerMode error:error];
	if (!trustEvaluation)
		return nil;

	BTPluginVerifiedPackage *verified = [[BTPluginVerifiedPackage alloc] bt_init];
	verified.packageInspection = packageInspection;
	verified.machOInspection = machOInspection;
	verified.trustEvaluation = trustEvaluation;
	return verified;
}

- (BOOL)recordActivationCommitForVerifiedPackage:(BTPluginVerifiedPackage *)verifiedPackage
															 error:(NSError **)error {
	if (![verifiedPackage isKindOfClass:[BTPluginVerifiedPackage class]] ||
		!verifiedPackage.isApprovedForActivation) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"Only a completely verified and approved package can reach activation commit.", nil, nil);
		return NO;
	}
	return [self.trustEvaluator recordActivatedInspection:verifiedPackage.packageInspection
		evaluation:verifiedPackage.trustEvaluation error:error];
}

@end
