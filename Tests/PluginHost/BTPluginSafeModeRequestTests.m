#import <Foundation/Foundation.h>

#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../../Battman/PluginHost/Runtime/BTPluginSafeModeRequest.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static BOOL BTWriteExact(NSURL *url, const char *bytes, size_t length, mode_t mode) {
	int descriptor = open(url.fileSystemRepresentation,
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode);
	if (descriptor < 0)
		return NO;
	BOOL result = write(descriptor, bytes, length) == (ssize_t)length;
	close(descriptor);
	return result;
}

int main(void) {
	@autoreleasepool {
		NSString *rootPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
			[NSString stringWithFormat:@"battman-safe-mode-%@", NSUUID.UUID.UUIDString.lowercaseString]];
		NSURL *rootURL = [NSURL fileURLWithPath:rootPath isDirectory:YES];
		NSError *error = nil;
		BTAssert([[NSFileManager defaultManager] createDirectoryAtURL:rootURL
			withIntermediateDirectories:NO attributes:@{ NSFilePosixPermissions: @0700 } error:&error],
			error.localizedDescription.UTF8String);
		NSURL *sentinelURL = [rootURL URLByAppendingPathComponent:BTPluginSafeModeSentinelName];
		BTPluginSafeModeRequest *request = [[BTPluginSafeModeRequest alloc] initWithSentinelURL:sentinelURL];
		BTAssert(request != nil, "safe-mode request fixture was rejected");

		BTAssert(![request consumeOneShotRequestIfPresent], "missing sentinel unexpectedly requested safe mode");
		BTAssert([request requestOneShotWithError:&error], error.localizedDescription.UTF8String);
		BTAssert([[NSFileManager defaultManager] fileExistsAtPath:sentinelURL.path],
			"one-shot sentinel was not created");
		BTAssert([request consumeOneShotRequestIfPresent], "one-shot sentinel did not request safe mode");
		BTAssert(![[NSFileManager defaultManager] fileExistsAtPath:sentinelURL.path],
			"exact one-shot sentinel was not consumed");
		BTAssert(![request consumeOneShotRequestIfPresent], "consumed one-shot sentinel fired twice");

		const char manual[] = "manual-emergency-recovery\n";
		BTAssert(BTWriteExact(sentinelURL, manual, sizeof(manual) - 1, 0600),
			"manual sentinel could not be created");
		BTAssert([request consumeOneShotRequestIfPresent], "manual sentinel did not request safe mode");
		BTAssert([[NSFileManager defaultManager] fileExistsAtPath:sentinelURL.path],
			"manual sentinel was consumed instead of remaining persistent");
		BTAssert([request requestOneShotWithError:&error],
			"existing manual sentinel should make one-shot scheduling idempotent");
		BTAssert([request consumeOneShotRequestIfPresent], "manual sentinel stopped requesting safe mode");
		BTAssert(unlink(sentinelURL.fileSystemRepresentation) == 0, "manual sentinel cleanup failed");

		BTAssert(BTWriteExact(sentinelURL, "battman-safe-mode-once-v1\nX", 27, 0600),
			"oversized near-marker could not be created");
		BTAssert([request consumeOneShotRequestIfPresent], "near-marker did not fail safely into safe mode");
		BTAssert([[NSFileManager defaultManager] fileExistsAtPath:sentinelURL.path],
			"oversized near-marker was incorrectly consumed");
		BTAssert(unlink(sentinelURL.fileSystemRepresentation) == 0, "near-marker cleanup failed");

		NSURL *otherName = [rootURL URLByAppendingPathComponent:@"not-the-sentinel"];
		BTAssert([[BTPluginSafeModeRequest alloc] initWithSentinelURL:otherName] == nil,
			"arbitrary sentinel filename was accepted");
		BTAssert([[NSFileManager defaultManager] removeItemAtURL:rootURL error:&error],
			error.localizedDescription.UTF8String);
		puts("One-shot and persistent emergency safe-mode sentinel tests passed.");
	}
	return 0;
}
