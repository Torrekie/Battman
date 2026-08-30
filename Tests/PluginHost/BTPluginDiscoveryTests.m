#import <Foundation/Foundation.h>

#import <sys/stat.h>
#import <unistd.h>

#import "../../Battman/PluginHost/Discovery/BTPluginDiscovery.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static void BTCreateDirectory(NSURL *url, NSNumber *permissions) {
	NSError *error = nil;
	BTAssert([[NSFileManager defaultManager] createDirectoryAtURL:url
		withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: permissions } error:&error],
		error.localizedDescription.UTF8String);
}

static void BTWriteFile(NSURL *url) {
	NSError *error = nil;
	BTAssert([[@"not a package directory" dataUsingEncoding:NSUTF8StringEncoding]
		writeToURL:url options:NSDataWritingAtomic error:&error], error.localizedDescription.UTF8String);
}

static BOOL BTHasDiagnosticForLastPathComponent(BTPluginDiscoveryResult *result, NSString *name) {
	for (BTPluginDiscoveryDiagnostic *diagnostic in result.diagnostics) {
		if ([diagnostic.url.lastPathComponent isEqualToString:name])
			return YES;
	}
	return NO;
}

static void BTTestDefaultRoots(void) {
	NSURL *support = [NSURL fileURLWithPath:@"/private/var/mobile/Containers/Data/Application/UUID/Library/Application Support"
		isDirectory:YES];
	NSURL *bundle = [NSURL fileURLWithPath:@"/Applications/Battman.app" isDirectory:YES];
	NSArray<BTPluginDiscoveryRoot *> *roots = [BTPluginDiscovery
		defaultRootsForApplicationSupportURL:support mainBundleURL:bundle];
	BTAssert(roots.count == 4, "default discovery roots changed unexpectedly");
	BTAssert(roots[0].source == BTPluginSourceAppBundle &&
		[roots[0].rootURL.path isEqualToString:@"/Applications/Battman.app/PlugIns"] &&
		[roots[0].metadataRootURL.path isEqualToString:@"/Applications/Battman.app/PluginManifests"],
		"sealed app-bundle discovery root is incorrect");
	BTAssert(roots[1].source == BTPluginSourceApplicationData &&
		[roots[1].rootURL.path hasSuffix:@"/Library/Application Support/Battman/PlugIns"],
		"application-data discovery root is incorrect");
	BTAssert(roots[2].source == BTPluginSourceRootedSystem &&
		[roots[2].rootURL.path isEqualToString:@"/Library/Battman/PlugIns"],
		"rooted discovery root is incorrect");
	BTAssert(roots[3].source == BTPluginSourceRootlessSystem &&
		[roots[3].rootURL.path isEqualToString:@"/var/jb/Library/Battman/PlugIns"],
		"rootless discovery root is incorrect");
	BTAssert(BTPluginSourceCanActivate(BTPluginSourceAppBundle) &&
		BTPluginSourceCanActivate(BTPluginSourceApplicationData) &&
		!BTPluginSourceCanActivate(BTPluginSourceQuarantine),
		"plug-in source policy helpers are inconsistent");
}

static void BTTestBoundedTransportDiscovery(NSURL *temporaryURL) {
	NSURL *root = [temporaryURL URLByAppendingPathComponent:@"Transport" isDirectory:YES];
	BTCreateDirectory(root, @0700);
	BTCreateDirectory([root URLByAppendingPathComponent:@"com.example.zeta.battman" isDirectory:YES], @0755);
	BTCreateDirectory([root URLByAppendingPathComponent:@"com.example.alpha.battman" isDirectory:YES], @0755);
	BTCreateDirectory([root URLByAppendingPathComponent:@"Ignored.BATTMAN" isDirectory:YES], @0755);
	BTCreateDirectory([root URLByAppendingPathComponent:@"Nested/com.example.hidden.battman" isDirectory:YES], @0755);
	BTWriteFile([root URLByAppendingPathComponent:@"com.example.regular.battman"]);

	NSURL *symlinkURL = [root URLByAppendingPathComponent:@"com.example.link.battman" isDirectory:YES];
	BTAssert(symlink([root URLByAppendingPathComponent:@"com.example.alpha.battman" isDirectory:YES].fileSystemRepresentation,
		symlinkURL.fileSystemRepresentation) == 0, "could not create discovery symlink fixture");

	BTPluginDiscoveryRoot *transport = [BTPluginDiscoveryRoot transportPackageRootURL:root
		source:BTPluginSourceApplicationData];
	NSURL *missingURL = [temporaryURL URLByAppendingPathComponent:@"Absent" isDirectory:YES];
	BTPluginDiscoveryRoot *missing = [BTPluginDiscoveryRoot transportPackageRootURL:missingURL
		source:BTPluginSourceApplicationData];
	BTPluginDiscoveryResult *result = [[BTPluginDiscovery new] discoverRoots:@[ transport, missing, transport ]];
	BTAssert(result.packages.count == 2, "transport discovery accepted an invalid, nested, or duplicate candidate");
	BTAssert([result.packages[0].packageURL.lastPathComponent isEqualToString:@"com.example.alpha.battman"] &&
		[result.packages[1].packageURL.lastPathComponent isEqualToString:@"com.example.zeta.battman"] &&
		[result.packages[0].claimedPluginIdentifier isEqualToString:@"com.example.alpha"],
		"transport candidates are not deterministically ordered");
	BTAssert(result.packages[0].representation == BTPluginInstalledRepresentationTransportPackage &&
		result.packages[0].payloadURL == nil && result.packages[0].metadataURL == nil,
		"transport candidate representation is incorrect");
	BTAssert(BTHasDiagnosticForLastPathComponent(result, @"com.example.link.battman") &&
		BTHasDiagnosticForLastPathComponent(result, @"com.example.regular.battman"),
		"unsafe immediate transport candidates were not diagnosed");
	BTAssert(!BTHasDiagnosticForLastPathComponent(result, @"Absent"),
		"an absent optional root should not produce a diagnostic");
}

static void BTTestSealedAppDiscovery(NSURL *temporaryURL) {
	NSURL *bundleRoot = [temporaryURL URLByAppendingPathComponent:@"App/PlugIns" isDirectory:YES];
	NSURL *metadataRoot = [temporaryURL URLByAppendingPathComponent:@"App/PluginManifests" isDirectory:YES];
	BTCreateDirectory(bundleRoot, @0755);
	BTCreateDirectory(metadataRoot, @0755);
	NSURL *officialBundle = [bundleRoot URLByAppendingPathComponent:@"com.torrekie.battman.official.bundle" isDirectory:YES];
	NSURL *officialMetadata = [metadataRoot URLByAppendingPathComponent:@"com.torrekie.battman.official" isDirectory:YES];
	BTCreateDirectory(officialBundle, @0755);
	BTCreateDirectory(officialMetadata, @0755);
	BTCreateDirectory([bundleRoot URLByAppendingPathComponent:@"com.torrekie.battman.orphan.bundle" isDirectory:YES], @0755);

	BTPluginDiscoveryRoot *sealed = [BTPluginDiscoveryRoot sealedAppBundleRootURL:bundleRoot
		metadataRootURL:metadataRoot];
	BTPluginDiscoveryResult *result = [[BTPluginDiscovery new] discoverRoots:@[ sealed ]];
	BTAssert(result.packages.count == 1, "sealed app discovery did not require exactly paired metadata");
	BTPluginDiscoveredPackage *package = result.packages.firstObject;
	BTAssert(package.source == BTPluginSourceAppBundle &&
		package.representation == BTPluginInstalledRepresentationSealedAppBundle &&
		[package.payloadURL isEqual:officialBundle] && [package.metadataURL isEqual:officialMetadata] &&
		[package.packageURL isEqual:officialMetadata],
		"sealed app candidate paths are incorrect");
	BTAssert(BTHasDiagnosticForLastPathComponent(result, @"com.torrekie.battman.orphan.bundle"),
		"unpaired sealed app payload was not diagnosed");
}

static void BTTestUnsafeRootIsRejected(NSURL *temporaryURL) {
	NSURL *root = [temporaryURL URLByAppendingPathComponent:@"Unsafe" isDirectory:YES];
	BTCreateDirectory([root URLByAppendingPathComponent:@"com.example.candidate.battman" isDirectory:YES], @0755);
	BTAssert(chmod(root.fileSystemRepresentation, 0777) == 0, "could not prepare unsafe-root fixture");
	BTPluginDiscoveryResult *result = [[BTPluginDiscovery new] discoverRoots:@[
		[BTPluginDiscoveryRoot transportPackageRootURL:root source:BTPluginSourceApplicationData]
	]];
	BTAssert(result.packages.count == 0 && result.diagnostics.count == 1,
		"group/world-writable discovery root was not rejected as a whole");
}

int main(void) {
	@autoreleasepool {
		BTTestDefaultRoots();
		NSFileManager *manager = [NSFileManager defaultManager];
		NSError *error = nil;
		NSURL *temporaryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory()
			stringByAppendingPathComponent:[NSString stringWithFormat:@"battman-discovery-tests-%@", NSUUID.UUID.UUIDString]]
			isDirectory:YES];
		BTCreateDirectory(temporaryURL, @0700);
		BTTestBoundedTransportDiscovery(temporaryURL);
		BTTestSealedAppDiscovery(temporaryURL);
		BTTestUnsafeRootIsRejected(temporaryURL);
		BTAssert([manager removeItemAtURL:temporaryURL error:&error], error.localizedDescription.UTF8String);
		puts("Bounded non-recursive plug-in discovery tests passed.");
	}
	return 0;
}
