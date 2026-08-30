//
//  BTPluginPackageErrors.h
//  Battman
//
//  Shared non-executing package-verifier errors. These errors describe hard
//  validation failures unless a trust evaluator explicitly classifies an
//  otherwise valid unknown publisher as requiring user approval.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const BTPluginPackageErrorDomain;
FOUNDATION_EXPORT NSString * const BTPluginPackageErrorRelativePathKey;

typedef NS_ERROR_ENUM(BTPluginPackageErrorDomain, BTPluginPackageErrorCode) {
	BTPluginPackageErrorInvalidPackage = 1,
	BTPluginPackageErrorUnsafePath = 2,
	BTPluginPackageErrorLimitExceeded = 3,
	BTPluginPackageErrorInvalidJSON = 4,
	BTPluginPackageErrorInvalidManifest = 5,
	BTPluginPackageErrorMissingFile = 6,
	BTPluginPackageErrorUnexpectedFile = 7,
	BTPluginPackageErrorHashMismatch = 8,
	BTPluginPackageErrorInvalidInfoPlist = 9,
	BTPluginPackageErrorInvalidSignature = 10,
	BTPluginPackageErrorUnknownPublisher = 11,
	BTPluginPackageErrorRevokedPublisher = 12,
	BTPluginPackageErrorRollback = 13,
	BTPluginPackageErrorIncompatibleABI = 14,
	BTPluginPackageErrorUnsupportedArchitecture = 15,
	BTPluginPackageErrorInvalidMachO = 16,
	BTPluginPackageErrorUnsafeDependency = 17,
	BTPluginPackageErrorPlatformSignature = 18,
	BTPluginPackageErrorQuarantine = 19,
	BTPluginPackageErrorRaceDetected = 20,
	BTPluginPackageErrorTrustStore = 21,
	BTPluginPackageErrorActivationState = 22,
	BTPluginPackageErrorRuntime = 23,
	BTPluginPackageErrorImport = 24,
	BTPluginPackageErrorSealedPackage = 25,
};

FOUNDATION_EXPORT NSError *BTPluginPackageMakeError(BTPluginPackageErrorCode code,
													 NSString *description,
													 NSString * _Nullable relativePath,
													 NSError * _Nullable underlyingError);

NS_ASSUME_NONNULL_END
