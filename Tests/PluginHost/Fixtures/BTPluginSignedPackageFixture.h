#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BTPluginTestSignedPackageIdentifier;
FOUNDATION_EXPORT NSString * const BTPluginTestSignedPackageExtensionPoint;

// Creates a structurally valid, package-contained-key P-256 signed transport
// package around the supplied iOS Mach-O fixture. This helper is test-only and
// terminates the current test process if fixture construction fails.
FOUNDATION_EXPORT NSURL *BTPluginTestCreateSignedPackage(NSURL *parentURL,
	NSURL *executableSourceURL, NSString *packageFileName);
FOUNDATION_EXPORT NSURL *BTPluginTestCreateSignedPackageVersioned(NSURL *parentURL,
	NSURL *executableSourceURL, NSString *packageFileName, NSString *displayVersion,
	NSString *buildVersion, uint64_t releaseSequence);

NS_ASSUME_NONNULL_END
