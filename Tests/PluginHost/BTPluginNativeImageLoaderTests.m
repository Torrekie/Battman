#import <Foundation/Foundation.h>

#import "../../Battman/PluginHost/BTPluginRegistry.h"
#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Runtime/BTPluginNativeImageLoaderPrivate.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static NSString * const BTFixtureExtensionPoint = @"com.example.battman.runtime.v1";

@interface BTPluginNativeImageLoader (BTPluginNativeImageLoaderTests)
- (nullable BTPluginPreparedNativeImage *)bt_prepareLooseImageAtURL:(NSURL *)executableURL
	error:(NSError * _Nullable * _Nullable)error;
@end

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		BTAssert(argc == 3, "expected native fixture and constructor sentinel paths");
		NSURL *fixtureURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
		NSString *sentinelPath = [NSString stringWithUTF8String:argv[2]];
		BTAssert(setenv("BT_PLUGIN_RUNTIME_CONSTRUCTOR_SENTINEL", sentinelPath.fileSystemRepresentation, 1) == 0,
			"could not configure constructor sentinel");
		BTAssert(![[NSFileManager defaultManager] fileExistsAtPath:sentinelPath],
			"constructor ran before the explicit loader boundary");

		BTPluginRegistry *registry = [BTPluginRegistry new];
		NSError *error = nil;
		BTAssert([registry registerExtensionPointIdentifier:BTFixtureExtensionPoint interfaceVersion:1
			requiredProtocol:@protocol(NSObject) error:&error], error.localizedDescription.UTF8String);
		__weak BTPluginNativeImageLoader *weakLoader = nil;
		id registeredObject = nil;
		@autoreleasepool {
			BTPluginNativeImageLoader *loader = [BTPluginNativeImageLoader new];
			weakLoader = loader;
			NSURL *unmappedStageRoot = nil;
			@autoreleasepool {
				BTPluginPreparedNativeImage *unmapped =
					[loader bt_prepareLooseImageAtURL:fixtureURL error:&error];
				BTAssert(unmapped != nil, error.localizedDescription.UTF8String);
				unmappedStageRoot = unmapped.stageRootURL;
				BTAssert([[NSFileManager defaultManager] fileExistsAtPath:unmapped.stagedExecutableURL.path],
					"unmapped preparation did not create its private executable copy");
			}
			BTAssert(![[NSFileManager defaultManager] fileExistsAtPath:unmappedStageRoot.path],
				"an unmapped prepared image did not clean up its private staging root");

			BTPluginPreparedNativeImage *prepared =
				[loader bt_prepareLooseImageAtURL:fixtureURL error:&error];
			BTAssert(prepared != nil, error.localizedDescription.UTF8String);
			NSDictionary *rootAttributes = [[NSFileManager defaultManager]
				attributesOfItemAtPath:prepared.stageRootURL.path error:&error];
			NSDictionary *imageAttributes = [[NSFileManager defaultManager]
				attributesOfItemAtPath:prepared.stagedExecutableURL.path error:&error];
			BTAssert(([rootAttributes[NSFilePosixPermissions] unsignedShortValue] & 0777) == 0700 &&
				([imageAttributes[NSFilePosixPermissions] unsignedShortValue] & 0777) == 0500,
				"private staging did not finalize its capability root and executable modes");

			NSURL *originalBackupURL = [fixtureURL URLByAppendingPathExtension:@"verified-backup"];
			BTAssert([[NSFileManager defaultManager] moveItemAtURL:fixtureURL
				toURL:originalBackupURL error:&error], error.localizedDescription.UTF8String);
			NSData *replacement = [@"unverified replacement" dataUsingEncoding:NSUTF8StringEncoding];
			BTAssert([replacement writeToURL:fixtureURL options:NSDataWritingAtomic error:&error],
				error.localizedDescription.UTF8String);
			BTAssert([loader loadPreparedImage:prepared
				expectedPluginIdentifier:@"com.example.battman.runtime"
				expectedPluginVersion:@"7"
				declaredExtensionPoints:[NSSet setWithObject:BTFixtureExtensionPoint]
				registry:registry error:&error], error.localizedDescription.UTF8String);
			BTAssert([[NSFileManager defaultManager] removeItemAtURL:fixtureURL error:&error] &&
				[[NSFileManager defaultManager] moveItemAtURL:originalBackupURL
					toURL:fixtureURL error:&error], error.localizedDescription.UTF8String);
			BTAssert([[NSFileManager defaultManager] fileExistsAtPath:sentinelPath],
				"constructor did not run at the explicit native mapping boundary");
			NSArray *objects = [registry extensionObjectsForExtensionPointIdentifier:BTFixtureExtensionPoint];
			BTAssert(objects.count == 1, "native fixture did not commit exactly one extension");
			registeredObject = objects.firstObject;
			BTAssert([[registeredObject valueForKey:@"fixtureValue"] isEqualToString:@"native-runtime-fixture"],
				"native fixture extension object lost its expected behavior");
			error = nil;
			BTAssert(![loader loadImageAtURL:fixtureURL
				expectedPluginIdentifier:@"com.example.battman.runtime" expectedPluginVersion:@"7"
				declaredExtensionPoints:[NSSet setWithObject:BTFixtureExtensionPoint]
				registry:registry error:&error] && error.code == BTPluginPackageErrorRuntime,
				"the same content-addressed native image was mapped twice in one process");
		}
		BTAssert(weakLoader == nil, "native image loader unexpectedly remained retained");
		BTAssert([[registeredObject valueForKey:@"fixtureValue"] isEqualToString:@"native-runtime-fixture"],
			"registered native object stopped working after loader lifetime ended");

		__block BOOL backgroundRejected = NO;
		dispatch_semaphore_t backgroundFinished = dispatch_semaphore_create(0);
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			BTPluginRegistry *backgroundRegistry = [BTPluginRegistry new];
			NSError *backgroundError = nil;
			[backgroundRegistry registerExtensionPointIdentifier:BTFixtureExtensionPoint interfaceVersion:1
				requiredProtocol:@protocol(NSObject) error:&backgroundError];
			backgroundRejected = ![[BTPluginNativeImageLoader new] loadImageAtURL:fixtureURL
				expectedPluginIdentifier:@"com.example.battman.runtime" expectedPluginVersion:@"7"
				declaredExtensionPoints:[NSSet setWithObject:BTFixtureExtensionPoint]
				registry:backgroundRegistry error:&backgroundError] &&
				backgroundError.code == BTPluginPackageErrorRuntime;
			dispatch_semaphore_signal(backgroundFinished);
		});
		BTAssert(dispatch_semaphore_wait(backgroundFinished,
			dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC))) == 0,
			"background-thread loader check timed out");
		BTAssert(backgroundRejected, "background-thread native mapping was not rejected before dlopen");
		BTAssert(unsetenv("BT_PLUGIN_RUNTIME_CONSTRUCTOR_SENTINEL") == 0, "could not clear sentinel environment");
		puts("Minimal RTLD_LOCAL native loader and no-unload lifetime tests passed.");
	}
	return 0;
}
