//
//  BTPluginSafeModeRequest.m
//  Battman
//

#import "BTPluginSafeModeRequest.h"

#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../Model/BTPluginPackageErrors.h"

NSString * const BTPluginSafeModeLaunchArgument = @"--battman-safe-mode";
NSString * const BTPluginSafeModeSentinelName = @"Start Without Third-Party Plugins";
static const char BTPluginOneShotSafeModeMarker[] = "battman-safe-mode-once-v1\n";

static BOOL BTPluginSafeModeSetError(NSError **error, NSString *description,
	int posixCode) {
	if (error) {
		NSError *underlying = posixCode == 0 ? nil :
			[NSError errorWithDomain:NSPOSIXErrorDomain code:posixCode userInfo:nil];
		*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
			description, nil, underlying);
	}
	return NO;
}

static BOOL BTPluginSafeModeStatIsPrivateRegular(struct stat value, off_t expectedSize) {
	return S_ISREG(value.st_mode) && value.st_uid == geteuid() &&
		value.st_nlink == 1 && value.st_size == expectedSize &&
		(value.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) == 0;
}

@interface BTPluginSafeModeRequest ()
@property (nonatomic, strong, readwrite) NSURL *sentinelURL;
@end

@implementation BTPluginSafeModeRequest

- (instancetype)initWithSentinelURL:(NSURL *)sentinelURL {
	self = [super init];
	if (!self)
		return nil;
	if (![sentinelURL isKindOfClass:[NSURL class]] || !sentinelURL.isFileURL ||
		!sentinelURL.path.isAbsolutePath ||
		![sentinelURL.lastPathComponent isEqualToString:BTPluginSafeModeSentinelName])
		return nil;
	_sentinelURL = sentinelURL.standardizedURL;
	return self;
}

- (int)openPrivateParentWithError:(NSError **)error createIfMissing:(BOOL)createIfMissing {
	NSURL *parentURL = self.sentinelURL.URLByDeletingLastPathComponent;
	if (createIfMissing) {
		NSError *directoryError = nil;
		if (![[NSFileManager defaultManager] createDirectoryAtURL:parentURL
			withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @0700 }
			error:&directoryError]) {
			if (error)
				*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
					@"The private plug-in support directory could not be created.", nil,
					directoryError);
			return -1;
		}
	}
	int parent = open(parentURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (parent < 0) {
		BTPluginSafeModeSetError(error,
			@"The private plug-in support directory could not be opened safely.", errno);
		return -1;
	}
	struct stat parentStat;
	if (fstat(parent, &parentStat) != 0 || !S_ISDIR(parentStat.st_mode) ||
		parentStat.st_uid != geteuid() ||
		(parentStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) != 0) {
		close(parent);
		BTPluginSafeModeSetError(error,
			@"The private plug-in support directory has unsafe ownership or permissions.", 0);
		return -1;
	}
	return parent;
}

- (BOOL)requestOneShotWithError:(NSError **)error {
	int parent = [self openPrivateParentWithError:error createIfMissing:YES];
	if (parent < 0)
		return NO;
	int descriptor = openat(parent, BTPluginSafeModeSentinelName.fileSystemRepresentation,
		O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
	if (descriptor < 0 && errno == EEXIST) {
		close(parent);
		return YES;
	}
	if (descriptor < 0) {
		int savedErrno = errno;
		close(parent);
		return BTPluginSafeModeSetError(error,
			@"The one-shot safe-mode request could not be created.", savedErrno);
	}
	ssize_t expected = (ssize_t)(sizeof(BTPluginOneShotSafeModeMarker) - 1);
	ssize_t written = write(descriptor, BTPluginOneShotSafeModeMarker, (size_t)expected);
	BOOL stored = written == expected && fsync(descriptor) == 0 && fsync(parent) == 0;
	close(descriptor);
	if (!stored)
		(void)unlinkat(parent, BTPluginSafeModeSentinelName.fileSystemRepresentation, 0);
	close(parent);
	if (!stored)
		return BTPluginSafeModeSetError(error,
			@"The one-shot safe-mode request could not be synchronized.", 0);
	return YES;
}

- (BOOL)consumeOneShotRequestIfPresent {
	struct stat initial;
	if (lstat(self.sentinelURL.fileSystemRepresentation, &initial) != 0)
		return NO;
	off_t expected = (off_t)(sizeof(BTPluginOneShotSafeModeMarker) - 1);
	if (!BTPluginSafeModeStatIsPrivateRegular(initial, expected))
		return YES;

	int parent = [self openPrivateParentWithError:NULL createIfMissing:NO];
	if (parent < 0)
		return YES;
	int descriptor = openat(parent, BTPluginSafeModeSentinelName.fileSystemRepresentation,
		O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0) {
		close(parent);
		return YES;
	}
	struct stat opened;
	BOOL sameFile = fstat(descriptor, &opened) == 0 &&
		opened.st_dev == initial.st_dev && opened.st_ino == initial.st_ino &&
		BTPluginSafeModeStatIsPrivateRegular(opened, expected);
	char marker[sizeof(BTPluginOneShotSafeModeMarker)] = {0};
	ssize_t count = sameFile ? read(descriptor, marker, sizeof(marker)) : -1;
	close(descriptor);
	BOOL oneShot = count == expected &&
		memcmp(marker, BTPluginOneShotSafeModeMarker, (size_t)expected) == 0;
	if (oneShot) {
		struct stat current;
		if (fstatat(parent, BTPluginSafeModeSentinelName.fileSystemRepresentation,
			&current, AT_SYMLINK_NOFOLLOW) == 0 && current.st_dev == opened.st_dev &&
			current.st_ino == opened.st_ino)
			(void)unlinkat(parent, BTPluginSafeModeSentinelName.fileSystemRepresentation, 0);
	}
	close(parent);
	return YES;
}

@end
