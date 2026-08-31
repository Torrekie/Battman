#import "ChargingLimitViewController.h"
#import "SliderTableViewCell.h"
#import "PickerAccessoryView.h"
#import "BattmanPrefs.h"
#if __has_include("PLGraphViewTableCell.h")
#import "PLGraphViewTableCell.h"
#endif
#include "common.h"
#include "intlextern.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <sqlite3.h>
#include <sys/errno.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

#import "ObjCExt/UIColor+compat.h"
#import <objc/runtime.h>

typedef enum {
	CL_SECTION_GRAPH,
	CL_SECTION_MAIN,
	CL_SECTION_COUNT
} CLSect;

typedef enum {
	CL_GRAPH_ROW,
	CL_GRAPH_COUNT,
} CLRowGraph;

typedef enum {
	CL_MAIN_CYCLEMODE,
	CL_MAIN_LIMITLABEL,
	CL_MAIN_LIMIT,
	CL_MAIN_RESUMELABEL,
	CL_MAIN_RESUME,
	CL_MAIN_DISCHGMODE,
	CL_MAIN_OBCSWITCH,
	CL_MAIN_PIDLABEL,
	CL_MAIN_DAEMONSWITCH,
	CL_MAIN_COUNT,
} CLRowMain;

/*
 * Adapted from UIMenuItem-CXAImageSupport's marker-title + UILabel drawing
 * approach. Keep this local to the powerlog export menu instead of swizzling a
 * general UIMenuItem API surface for the whole app.
 */
static NSString * const CLPowerlogMenuImageMarker = @"\uFEFF\u200B";
static NSMutableDictionary<NSString *, UIImage *> *CLPowerlogMenuImageTitles;
static void (*CLOrigMenuImageDrawTextInRect)(UILabel *, SEL, CGRect);
static void (*CLOrigMenuImageSetFrame)(UILabel *, SEL, CGRect);
static CGSize (*CLOrigMenuImageSizeWithFont)(NSString *, SEL, UIFont *);
static CGSize (*CLOrigMenuImageSizeWithAttributes)(NSString *, SEL, NSDictionary *);

static NSMutableDictionary<NSString *, UIImage *> *CLPowerlogMenuImageTitleMap(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		CLPowerlogMenuImageTitles = [NSMutableDictionary dictionary];
	});
	return CLPowerlogMenuImageTitles;
}

static BOOL CLPowerlogMenuTitleHasImageMarker(NSString *title) {
	return [title hasPrefix:CLPowerlogMenuImageMarker] && [title hasSuffix:CLPowerlogMenuImageMarker];
}

static UIImage *CLPowerlogMenuImageForTitle(NSString *title) {
	if (!CLPowerlogMenuTitleHasImageMarker(title))
		return nil;

	UIImage *image = nil;
	NSMutableDictionary *titleMap = CLPowerlogMenuImageTitleMap();
	@synchronized (titleMap) {
		image = titleMap[title];
	}
	return image;
}

static NSString *CLPowerlogMenuTitleWithImage(NSString *title, UIImage *image) {
	if (!image)
		return title;

	NSString *wrappedTitle = [NSString stringWithFormat:@"%@%@%@", CLPowerlogMenuImageMarker, title, CLPowerlogMenuImageMarker];
	NSMutableDictionary *titleMap = CLPowerlogMenuImageTitleMap();
	@synchronized (titleMap) {
		titleMap[wrappedTitle] = image;
	}
	return wrappedTitle;
}

static UIImage *CLPowerlogImageByTintingMenuImage(UIImage *image, UIColor *tintColor) {
	CGSize size = image.size;
	if (size.width <= 0.0 || size.height <= 0.0)
		return image;

	UIGraphicsBeginImageContextWithOptions(size, NO, image.scale ?: 0.0);
	CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);
	[tintColor ?: [UIColor blackColor] setFill];
	UIRectFill(rect);
	[image drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1.0];
	UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return tintedImage ?: image;
}

static UIImage *CLPowerlogExportMenuImage(void) {
	UIImage *image = nil;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightRegular];
		image = [UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:configuration];
	}

	if (!image) {
		NSString *glyph = @"􀈂";
		UIFont *font = [UIFont fontWithName:@SFPRO size:22.0] ?: [UIFont systemFontOfSize:22.0];
		CGSize imageSize = CGSizeMake(24.0, 24.0);
		UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0.0);
		NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor blackColor] };
		CGSize glyphSize = [glyph sizeWithAttributes:attrs];
		CGPoint point = CGPointMake(ceil((imageSize.width - glyphSize.width) / 2.0), ceil((imageSize.height - glyphSize.height) / 2.0));
		[glyph drawAtPoint:point withAttributes:attrs];
		image = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}

	return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void CLPowerlogMenuImageDrawTextInRect(UILabel *label, SEL _cmd, CGRect rect) {
	UIImage *image = CLPowerlogMenuImageForTitle(label.text);
	if (!image || !CLOrigMenuImageDrawTextInRect) {
		if (CLOrigMenuImageDrawTextInRect)
			CLOrigMenuImageDrawTextInRect(label, _cmd, rect);
		return;
	}

	image = CLPowerlogImageByTintingMenuImage(image, label.textColor ?: label.tintColor);
	CGSize imageSize = image.size;
	CGPoint point = CGPointMake(ceil(CGRectGetMidX(label.bounds) - imageSize.width / 2.0),
	                            ceil(CGRectGetMidY(label.bounds) - imageSize.height / 2.0));
	[image drawAtPoint:point];
}

static void CLPowerlogMenuImageSetFrame(UILabel *label, SEL _cmd, CGRect rect) {
	if (CLPowerlogMenuImageForTitle(label.text) && label.superview)
		rect = label.superview.bounds;

	if (CLOrigMenuImageSetFrame)
		CLOrigMenuImageSetFrame(label, _cmd, rect);
}

static CGSize CLPowerlogMenuImageSizeWithFont(NSString *string, SEL _cmd, UIFont *font) {
	UIImage *image = CLPowerlogMenuImageForTitle(string);
	if (image)
		return image.size;

	if (CLOrigMenuImageSizeWithFont)
		return CLOrigMenuImageSizeWithFont(string, _cmd, font);
	return [string sizeWithAttributes:font ? @{ NSFontAttributeName: font } : nil];
}

static CGSize CLPowerlogMenuImageSizeWithAttributes(NSString *string, SEL _cmd, NSDictionary *attributes) {
	UIImage *image = CLPowerlogMenuImageForTitle(string);
	if (image)
		return image.size;

	if (CLOrigMenuImageSizeWithAttributes)
		return CLOrigMenuImageSizeWithAttributes(string, _cmd, attributes);
	return [string boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
	                            options:NSStringDrawingUsesLineFragmentOrigin
	                         attributes:attributes
	                            context:nil].size;
}

static void CLPowerlogInstallMenuImageSupport(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		Method method = class_getInstanceMethod([UILabel class], @selector(drawTextInRect:));
		if (method) {
			CLOrigMenuImageDrawTextInRect = (void *)method_getImplementation(method);
			method_setImplementation(method, (IMP)CLPowerlogMenuImageDrawTextInRect);
		}

		method = class_getInstanceMethod([UILabel class], @selector(setFrame:));
		if (method) {
			CLOrigMenuImageSetFrame = (void *)method_getImplementation(method);
			method_setImplementation(method, (IMP)CLPowerlogMenuImageSetFrame);
		}

		method = class_getInstanceMethod([NSString class], NSSelectorFromString(@"sizeWithFont:"));
		if (method) {
			CLOrigMenuImageSizeWithFont = (void *)method_getImplementation(method);
			method_setImplementation(method, (IMP)CLPowerlogMenuImageSizeWithFont);
		}

		method = class_getInstanceMethod([NSString class], @selector(sizeWithAttributes:));
		if (method) {
			CLOrigMenuImageSizeWithAttributes = (void *)method_getImplementation(method);
			method_setImplementation(method, (IMP)CLPowerlogMenuImageSizeWithAttributes);
		}
	});
}

@implementation UILabel (BattmanPowerlogMenuImageSupport)

+ (void)load {
	CLPowerlogInstallMenuImageSupport();
}

@end

/*
 * The daemon control socket is intentionally a tiny protocol, but it still
 * crosses a process boundary.  A daemon can be restarted while this view is
 * alive (for example after a respring), so all I/O must tolerate a closed or
 * stale descriptor.  Keep the timeout short: these calls can be made from a
 * table-view action and must never leave the UI blocked indefinitely.
 */
#define CL_DAEMON_IO_TIMEOUT_SECONDS 1

static void CLConfigureDaemonSocket(int sock) {
	struct timeval timeout = { CL_DAEMON_IO_TIMEOUT_SECONDS, 0 };
	(void)setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	(void)setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#ifdef SO_NOSIGPIPE
	int no_sigpipe = 1;
	(void)setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif
	int flags = fcntl(sock, F_GETFD, 0);
	if (flags >= 0)
		(void)fcntl(sock, F_SETFD, flags | FD_CLOEXEC);
}

static ssize_t CLDaemonSend(int sock, const void *bytes, size_t length) {
	ssize_t result;
	do {
		result = send(sock, bytes, length, MSG_NOSIGNAL);
	} while (result < 0 && errno == EINTR);
	return result;
}

static ssize_t CLDaemonReceive(int sock, void *bytes, size_t length) {
	ssize_t result;
	do {
		result = recv(sock, bytes, length, 0);
	} while (result < 0 && errno == EINTR);
	return result;
}

static BOOL CLDaemonPath(char *buffer, size_t capacity, const char *suffix) {
	const char *config_dir = battman_config_dir();
	if (!buffer || capacity == 0 || !config_dir || !suffix)
		return NO;
	int length = snprintf(buffer, capacity, "%s/daemon%s", config_dir, suffix);
	return length > 0 && (size_t)length < capacity;
}

static void CLRemoveStaleDaemonArtifacts(const char *run_path, pid_t expected_pid) {
	char derived_run_path[PATH_MAX];
	if (!run_path && CLDaemonPath(derived_run_path, sizeof(derived_run_path), ".run"))
		run_path = derived_run_path;
	if (!run_path)
		return;
	if (run_path && expected_pid > 1) {
		/* Never remove a newer daemon's lock after a PID race.  The daemon keeps
		 * an advisory write lock on this file for its whole lifetime; obtaining a
		 * read lock here lets us distinguish a released stale file and keeps that
		 * check held until the unlink. */
		int fd = open(run_path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
		if (fd < 0)
			return;
		struct flock lock = {
			.l_type = F_RDLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0
		};
		if (fcntl(fd, F_SETLK, &lock) != 0) {
			close(fd);
			return;
		}
		pid_t current_pid = 0;
		ssize_t bytes = pread(fd, &current_pid, sizeof(current_pid), 0);
		if (bytes != (ssize_t)sizeof(current_pid) || current_pid != expected_pid)
		{
			close(fd);
			return;
		}
		/* The pathname can be replaced while this descriptor waits for the
		 * released daemon lock.  Revalidate the descriptor's inode immediately
		 * before unlinking so a stale opener cannot remove a newly published
		 * daemon.run.  Cooperative daemon publishers hold a write lock on the
		 * old inode, so the check and unlink remain serialized with them. */
		struct stat locked_stat;
		struct stat path_stat;
		if (fstat(fd, &locked_stat) != 0 || lstat(run_path, &path_stat) != 0 ||
		    locked_stat.st_dev != path_stat.st_dev ||
		    locked_stat.st_ino != path_stat.st_ino) {
			close(fd);
			return;
		}
		(void)unlink(run_path);
		close(fd);
	} else {
		return;
	}
	/* Leave the socket node for the next daemon instance to remove while it
	 * holds its own run-file lock.  Unlinking it here after closing the run fd
	 * could delete a replacement daemon's live socket during a restart race. */
}

/* Return YES for a PID that is still alive, including a process hidden by
 * normal mobile-user permissions (kill(pid, 0) == EPERM). */
static BOOL CLDaemonPIDIsAlive(pid_t pid) {
	if (pid <= 1)
		return NO;
	if (kill(pid, 0) == 0)
		return YES;
	return errno == EPERM;
}

static BOOL CLReadDaemonPID(const char *run_path, pid_t *pid_out) {
	if (!run_path || !pid_out)
		return NO;
	int fd = open(run_path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
	if (fd < 0)
		return NO;

	struct stat st;
	BOOL valid_file = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) &&
	                  st.st_size == (off_t)sizeof(pid_t) &&
	                  (st.st_mode & 022) == 0;
	pid_t pid = 0;
	ssize_t bytes = valid_file ? pread(fd, &pid, sizeof(pid), 0) : -1;
	BOOL pid_alive = bytes == (ssize_t)sizeof(pid) && CLDaemonPIDIsAlive(pid);
	int pid_errno = errno;
	close(fd);
	if (bytes != (ssize_t)sizeof(pid) || !pid_alive) {
		/* Do not unlink a short file: the daemon may still be writing its PID. */
		if (bytes == (ssize_t)sizeof(pid) && pid > 1 && pid_errno == ESRCH)
			CLRemoveStaleDaemonArtifacts(run_path, pid);
		return NO;
	}
	*pid_out = pid;
	return YES;
}

static BOOL CLDaemonSettingLevelIsValid(unsigned char value) {
	return value == 255 || value <= 100;
}

static BOOL CLDaemonSettingsAreValid(const unsigned char values[BATTMAN_DAEMON_SETTINGS_SIZE]) {
	if (!values || !CLDaemonSettingLevelIsValid(values[0]) ||
	    !CLDaemonSettingLevelIsValid(values[1]))
		return NO;
	/* A limit-only configuration (resume == 255) is valid.  The inverse
	 * combination is not: without a disable threshold, an enable threshold
	 * leaves the daemon with no safe state above that threshold. */
	if (values[0] != 255 && values[1] == 255)
		return NO;
	return values[0] == 255 || values[0] < values[1];
}

static BOOL CLPrepareDaemonSettingsFile(int fd, unsigned char values[BATTMAN_DAEMON_SETTINGS_SIZE]) {
	if (fd < 0 || !values)
		return NO;

	struct stat st;
	if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode))
		return NO;
	if ((st.st_mode & 022) != 0 && fchmod(fd, st.st_mode & 0777 & ~022) != 0)
		return NO;

	unsigned char defaults[BATTMAN_DAEMON_SETTINGS_SIZE] = { 255, 255, 0 };
	unsigned char existing[BATTMAN_DAEMON_SETTINGS_SIZE] = { 255, 255, 0 };
	ssize_t bytes = pread(fd, existing, sizeof(existing), 0);
	BOOL needs_write = bytes != (ssize_t)sizeof(existing) ||
	                   st.st_size != (off_t)sizeof(existing);
	if (bytes > 0 && bytes < (ssize_t)sizeof(existing)) {
		/* Preserve settings written by older builds that only persisted two
		 * bytes, while initializing the newly persisted drain-mode byte. */
		memcpy(defaults, existing, (size_t)bytes);
	}
	if (bytes == (ssize_t)sizeof(existing)) {
		memcpy(defaults, existing, sizeof(defaults));
		needs_write = st.st_size != (off_t)sizeof(existing) ||
		              !CLDaemonSettingsAreValid(existing);
		if (needs_write) {
			defaults[0] = 255;
			defaults[1] = 255;
		}
	}
	if (!CLDaemonSettingLevelIsValid(defaults[0]))
		defaults[0] = 255;
	if (!CLDaemonSettingLevelIsValid(defaults[1]))
		defaults[1] = 255;
	if (!CLDaemonSettingsAreValid(defaults)) {
		defaults[0] = 255;
		defaults[1] = 255;
		needs_write = YES;
	}

	if (needs_write) {
		size_t written = 0;
		while (written < sizeof(defaults)) {
			ssize_t count = pwrite(fd, defaults + written, sizeof(defaults) - written,
			                       (off_t)written);
			if (count < 0 && errno == EINTR)
				continue;
			if (count <= 0)
				return NO;
			written += (size_t)count;
		}
		/* Publish the complete three-byte record before shrinking an oversized
		 * legacy file.  Truncating first made an interrupted write destroy the
		 * last known settings even when no replacement bytes were durable. */
		if (ftruncate(fd, BATTMAN_DAEMON_SETTINGS_SIZE) != 0)
			return NO;
		/* fsync is best effort on the simulator and on some jailbreak filesystems;
		 * mmap + MS_SYNC below remains the authoritative persistence operation. */
		(void)fsync(fd);
	}

	memcpy(values, needs_write ? defaults : existing, sizeof(existing));
	return CLDaemonSettingsAreValid((const unsigned char *)values);
}

int connect_to_daemon(bool show_alerts) {
	struct sockaddr_un sockaddr;
	memset(&sockaddr, 0, sizeof(sockaddr));
	sockaddr.sun_family = AF_UNIX;

	// Use centralized socket path with iOS fallback paths
	const char *socket_path = battman_socket_path();
	if (!socket_path || strlen(socket_path) >= sizeof(sockaddr.sun_path)) {
		if (show_alerts)
			show_alert(L_FAILED, _C("The daemon socket path is invalid."), L_OK);
		return 0;
	}
	strncpy(sockaddr.sun_path, socket_path, sizeof(sockaddr.sun_path) - 1);
	sockaddr.sun_path[sizeof(sockaddr.sun_path) - 1] = '\0';
	
	size_t addrlen = offsetof(struct sockaddr_un, sun_path) + strlen(sockaddr.sun_path) + 1;
	sockaddr.sun_len = (unsigned char)addrlen;

	int sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock == -1) {
		/*
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s: %s", _C("Failed to create socket"), L_ERR, strerror(errno));
		show_alert(L_ERR, errstr, L_OK);
		 */
		return 0;
	}
	/* A launched app normally has descriptors 0..2 occupied, but rooted
	 * launchers sometimes close stdin/stdout/stderr. Keep 0 as the failure
	 * sentinel used by this legacy C API and promote a valid socket if needed. */
	if (sock < 3) {
		int promoted = fcntl(sock, F_DUPFD, 3);
		if (promoted >= 0) {
			close(sock);
			sock = promoted;
		} else {
			close(sock);
			return 0;
		}
	}
	CLConfigureDaemonSocket(sock);
	
	if (connect(sock, (struct sockaddr *)&sockaddr, (socklen_t)addrlen) == -1) {
		/*
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s\n%s: %s", _C("Failed to connect to daemon at"), sockaddr.sun_path, L_ERR, strerror(errno));
		show_alert(L_ERR, errstr, L_OK);
		 */
		// No alert bc we need to retry
		close(sock);
		return 0;
	}
	
	char cmd = 2;
	if (CLDaemonSend(sock, &cmd, 1) != 1) {
		NSLog(@"Failed to write ping to daemon: %s", strerror(errno));
		if (show_alerts) show_alert(L_FAILED, "Failed to write to daemon.", L_OK);
		close(sock);
		return 0;
	}
	if (CLDaemonReceive(sock, &cmd, 1) != 1 || cmd != 2) {
		NSLog(@"Failed to ping daemon: %s", strerror(errno));
		if (show_alerts) show_alert(L_FAILED, "The daemon may not be working properly.", L_OK);
		close(sock);
		return 0;
	}

	NSLog(@"Connected to daemon and received ping!");
	return sock;
}

#if 0
// We are using our own impl now, no need to do such manual fixes now
static void changeLabelColorsInternal(UIView *view, UIColor *color) {
	if (!view)
		return;

	if ([view isKindOfClass:[UILabel class]]) {
		UILabel *label  = (UILabel *)view;
		label.textColor = color;
	}

	for (UIView *subview in view.subviews) {
		changeLabelColorsInternal(subview, color);
	}
}

static void changeLabelColors(UIView *inputView, UIColor *color) {
	if (!inputView || !color)
		return;

	if ([NSThread isMainThread]) {
		changeLabelColorsInternal(inputView, color);
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			changeLabelColorsInternal(inputView, color);
		});
	}
}
#endif

static int _cl_sql_pt_cb(void *arr_ref, int cnt, char **texts, char **names) {
	NSMutableArray    *arr = (__bridge NSMutableArray *)arr_ref;
	NSDate            *date = nil;
	NSNumber          *percent = nil;
	
	for (int i = 0; i < cnt; i++) {
		if (!names[i] || !texts[i])
			continue;
		
		if (!strcmp(names[i], "timestamp")) {
            char *endptr;
            double timestamp = strtod(texts[i], &endptr);
            if (*endptr == '\0' && timestamp > 0 && timestamp < 4102444800.0) { // Before year 2100
                date = [NSDate dateWithTimeIntervalSince1970:timestamp];
            }
		} else if (!strcmp(names[i], "Level")) {
			char *endptr;
            double level = strtod(texts[i], &endptr);
            if (*endptr == '\0' && level >= 0.0 && level <= 100.0) {
                percent = [NSNumber numberWithDouble:level];
            }
		}
	}
	// Only add the unit if both timestamp and level are valid
	if (date && percent) {
		[arr addObject:[NSArray arrayWithObjects:date, percent, nil]];
	}
	
	return 0;
}

@interface __some_random_defs_111 : NSObject
- (void)setGraphArray:(NSArray *)arr;
- (void)setLabelColor:(UIColor *)color;
- (UIView *)graphView;
@end

static NSString *CLPowerlogDatabasePathInContainer(NSString *containerPath) {
	if (!containerPath.length)
		return nil;
	return [containerPath stringByAppendingPathComponent:@"Library/BatteryLife/CurrentPowerlog.PLSQL"];
}

static BOOL CLPathIsReadableFile(NSString *path) {
	if (!path.length)
		return NO;
	struct stat st;
	if (stat(path.fileSystemRepresentation, &st) != 0)
		return NO;
	return S_ISREG(st.st_mode) && access(path.fileSystemRepresentation, R_OK) == 0;
}

static NSString *CLPowerlogContainerPathForMetadata(NSString *containerPath) {
	NSString *metadataPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
	NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
	if (![metadata isKindOfClass:[NSDictionary class]])
		return nil;
	if (![metadata[@"MCMMetadataIdentifier"] isEqualToString:@"systemgroup.com.apple.powerlog"])
		return nil;
	NSString *dbPath = CLPowerlogDatabasePathInContainer(containerPath);
	return CLPathIsReadableFile(dbPath) ? containerPath : nil;
}

static NSString *CLResolvePowerlogDatabasePath(void) {
	NSString *cachedContainerPath = [BattmanPrefs.sharedPrefs stringForKey:@kBattmanPrefs_POWERLOG_SYSTEMGROUP_PATH];
	NSString *cachedDBPath = CLPowerlogDatabasePathInContainer(cachedContainerPath);
	if (CLPathIsReadableFile(cachedDBPath))
		return cachedDBPath;
	if (cachedContainerPath.length) {
		[BattmanPrefs.sharedPrefs removeObjectForKey:@kBattmanPrefs_POWERLOG_SYSTEMGROUP_PATH];
		[BattmanPrefs.sharedPrefs synchronize];
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray<NSString *> *searchRoots = @[
		@"/var/containers/Shared/SystemGroup",
		@"/private/var/containers/Shared/SystemGroup",
	];
	for (NSString *searchRoot in searchRoots) {
		NSArray<NSString *> *containerNames = [fileManager contentsOfDirectoryAtPath:searchRoot error:nil];
		for (NSString *containerName in containerNames) {
			NSString *containerPath = [searchRoot stringByAppendingPathComponent:containerName];
			NSString *powerlogContainerPath = CLPowerlogContainerPathForMetadata(containerPath);
			if (!powerlogContainerPath)
				continue;

			if (![powerlogContainerPath isEqualToString:cachedContainerPath]) {
				[BattmanPrefs.sharedPrefs setString:powerlogContainerPath forKey:@kBattmanPrefs_POWERLOG_SYSTEMGROUP_PATH];
				[BattmanPrefs.sharedPrefs synchronize];
			}
			return CLPowerlogDatabasePathInContainer(powerlogContainerPath);
		}
	}

	NSArray<NSString *> *legacyPaths = @[
		@"/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL",
		@"/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL",
	];
	for (NSString *legacyPath in legacyPaths) {
		if (CLPathIsReadableFile(legacyPath))
			return legacyPath;
	}

	return nil;
}

@interface ChargingLimitViewController ()
@property (nonatomic, copy) NSArray *drainModes;
@property (nonatomic, weak) UIView *powerlogExportSourceView;
@property (nonatomic) CGRect powerlogExportSourceRect;
- (void)refreshDaemonStatus;
- (void)restoreDefaults:(id)sender;
- (BOOL)connectToDaemonWithAlerts:(BOOL)showAlerts;
- (void)invalidateDaemonConnection;
- (BOOL)sendDaemonCommand:(char)command reconnect:(BOOL)reconnect;
- (BOOL)receiveDaemonByte:(char *)byte;
- (BOOL)daemonRedecide;
@end

@implementation ChargingLimitViewController

- (NSURL *)exportPowerlogDatabaseSnapshotWithError:(NSError **)error {
	if (!powerlog_db_path) {
		if (error) {
			*error = [NSError errorWithDomain:@"BattmanPowerlogExport"
			                             code:ENOENT
			                         userInfo:@{ NSLocalizedDescriptionKey: _("Powerlog database is unavailable.") }];
		}
		return nil;
	}

	sqlite3 *sourceDB = NULL;
	int err = sqlite3_open_v2(powerlog_db_path, &sourceDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
	if (err != SQLITE_OK) {
		NSString *message = sourceDB ? [NSString stringWithUTF8String:sqlite3_errmsg(sourceDB)] : [NSString stringWithUTF8String:strerror(errno)];
		if (sourceDB)
			sqlite3_close_v2(sourceDB);
		if (error) {
			*error = [NSError errorWithDomain:@"BattmanPowerlogExport"
			                             code:err
			                         userInfo:@{ NSLocalizedDescriptionKey: message ?: _("Unable to export powerlog database.") }];
		}
		return nil;
	}
	sqlite3_busy_timeout(sourceDB, 5000);

	NSString *exportDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"BattmanPowerlogExport"];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	[fileManager removeItemAtPath:exportDir error:nil];
	if (![fileManager createDirectoryAtPath:exportDir withIntermediateDirectories:YES attributes:nil error:error]) {
		sqlite3_close_v2(sourceDB);
		return nil;
	}

	NSString *exportPath = [exportDir stringByAppendingPathComponent:@"CurrentPowerlog.PLSQL"];
	sqlite3 *destDB = NULL;
	err = sqlite3_open_v2(exportPath.fileSystemRepresentation, &destDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);
	if (err != SQLITE_OK) {
		NSString *message = destDB ? [NSString stringWithUTF8String:sqlite3_errmsg(destDB)] : [NSString stringWithUTF8String:strerror(errno)];
		sqlite3_close_v2(sourceDB);
		if (destDB)
			sqlite3_close_v2(destDB);
		if (error) {
			*error = [NSError errorWithDomain:@"BattmanPowerlogExport"
			                             code:err
			                         userInfo:@{ NSLocalizedDescriptionKey: message ?: _("Unable to export powerlog database.") }];
		}
		return nil;
	}
	sqlite3_busy_timeout(destDB, 5000);

	sqlite3_backup *backup = sqlite3_backup_init(destDB, "main", sourceDB, "main");
	if (!backup) {
		err = sqlite3_errcode(destDB);
		NSString *message = [NSString stringWithUTF8String:sqlite3_errmsg(destDB)];
		sqlite3_close_v2(destDB);
		sqlite3_close_v2(sourceDB);
		if (error) {
			*error = [NSError errorWithDomain:@"BattmanPowerlogExport"
			                             code:err
			                         userInfo:@{ NSLocalizedDescriptionKey: message ?: _("Unable to export powerlog database.") }];
		}
		return nil;
	}

	int busyRetries = 0;
	do {
		err = sqlite3_backup_step(backup, 256);
		if (err == SQLITE_BUSY || err == SQLITE_LOCKED) {
			usleep(100 * 1000);
			busyRetries++;
		} else {
			busyRetries = 0;
		}
	} while (err == SQLITE_OK || ((err == SQLITE_BUSY || err == SQLITE_LOCKED) && busyRetries < 50));

	sqlite3_backup_finish(backup);
	if (err == SQLITE_DONE)
		err = sqlite3_errcode(destDB);

	NSString *message = nil;
	if (err != SQLITE_OK)
		message = [NSString stringWithUTF8String:sqlite3_errmsg(destDB)];

	sqlite3_close_v2(destDB);
	sqlite3_close_v2(sourceDB);

	if (err != SQLITE_OK) {
		[fileManager removeItemAtPath:exportPath error:nil];
		if (error) {
			*error = [NSError errorWithDomain:@"BattmanPowerlogExport"
			                             code:err
			                         userInfo:@{ NSLocalizedDescriptionKey: message ?: _("Unable to export powerlog database.") }];
		}
		return nil;
	}

	return [NSURL fileURLWithPath:exportPath];
}

- (void)exportPowerlogFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
	NSError *error = nil;
	NSURL *exportURL = [self exportPowerlogDatabaseSnapshotWithError:&error];
	if (!exportURL) {
		show_alert(L_FAILED, error.localizedDescription.UTF8String ?: _C("Unable to export powerlog database."), L_OK);
		return;
	}

	UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[ exportURL ] applicationActivities:nil];
	UIView *presentingView = sourceView ?: self.view;
	activityViewController.popoverPresentationController.sourceView = presentingView;
	activityViewController.popoverPresentationController.sourceRect = CGRectIsEmpty(sourceRect) ? presentingView.bounds : sourceRect;
	[self presentViewController:activityViewController animated:YES completion:nil];
}

- (void)exportPowerlogMenuPressed:(id)sender {
	UIView *sourceView = self.powerlogExportSourceView ?: self.view;
	CGRect sourceRect = CGRectIsEmpty(self.powerlogExportSourceRect) ? sourceView.bounds : self.powerlogExportSourceRect;
	self.powerlogExportSourceView = nil;
	self.powerlogExportSourceRect = CGRectZero;
	[self exportPowerlogFromSourceView:sourceView sourceRect:sourceRect];
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
	if (action == @selector(exportPowerlogMenuPressed:))
		return powerlog_db_path != NULL;
	return [super canPerformAction:action withSender:sender];
}

- (void)graphLongPressed:(UILongPressGestureRecognizer *)gestureRecognizer {
	if (gestureRecognizer.state != UIGestureRecognizerStateBegan || !powerlog_db_path)
		return;

	UIView *sourceView = gestureRecognizer.view ?: self.view;
	if ([sourceView isKindOfClass:[UITableViewCell class]])
		sourceView = ((UITableViewCell *)sourceView).contentView;
	CGPoint location = [gestureRecognizer locationInView:sourceView];

	self.powerlogExportSourceView = sourceView;
	self.powerlogExportSourceRect = CGRectMake(location.x, location.y, 1.0, 1.0);

	NSString *menuTitle = CLPowerlogMenuTitleWithImage(_("Export Powerlog"), CLPowerlogExportMenuImage());
	UIMenuItem *exportItem = [[UIMenuItem alloc] initWithTitle:menuTitle action:@selector(exportPowerlogMenuPressed:)];
	UIMenuController *menuController = [UIMenuController sharedMenuController];
	menuController.menuItems = @[ exportItem ];
	[self becomeFirstResponder];
	[menuController setTargetRect:self.powerlogExportSourceRect inView:sourceView];
	[menuController setMenuVisible:YES animated:YES];
}

- (NSString *)title {
	return _("Charging Limit");
}

- (instancetype)init {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}
	if (!self)
		return nil;

	daemon_pid = 0;
	daemon_fd = -1;
	vals = NULL;
	vals_mapped = false;
	fallback_vals[0] = (char)255;
	fallback_vals[1] = (char)255;
	fallback_vals[2] = 0;
#if 0
	NSBundle *PLBundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/BatteryUsageUI.bundle"];
	if (PLBundle) {
		// TODO: Implement our own GraphView
		PSGraphViewTableCell = [PLBundle classNamed:@"PSGraphViewTableCell"];
		if (PSGraphViewTableCell) {
			NSString *resolvedPath = CLResolvePowerlogDatabasePath();
			if (resolvedPath)
				powerlog_db_path = strdup(resolvedPath.fileSystemRepresentation);
		}
	}
#elif __has_include("PLGraphViewTableCell.h")
	// We have implemented a clone of Apple's legacy PSGraphViewTableCell without 'PS'
	// Also fixed some bugs where iOS 16 users met ig
	NSString *resolvedPath = CLResolvePowerlogDatabasePath();
	if (resolvedPath)
		powerlog_db_path = strdup(resolvedPath.fileSystemRepresentation);
#endif

	self.drainModes = @[
		_("Discharge, Keep A/C"),
		_("Block A/C")
	];

	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"clhighthr"];
	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"cllowthr"];

	char settings_path[PATH_MAX];
	if (!CLDaemonPath(settings_path, sizeof(settings_path), "_settings")) {
		NSLog(@"Unable to construct daemon settings path");
		vals = fallback_vals;
		return self;
	}
	int fd = open(settings_path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0600);
	if (fd == -1) {
		NSLog(@"open %s: Error - %s", settings_path, strerror(errno));
		show_alert(L_ERR, _C("Failed to open daemon settings file"), L_OK);
		vals = fallback_vals;
		return self;
	}
	unsigned char prepared_vals[BATTMAN_DAEMON_SETTINGS_SIZE];
	if (!CLPrepareDaemonSettingsFile(fd, prepared_vals)) {
		NSLog(@"Unable to validate daemon settings file %s", settings_path);
		show_alert(L_ERR, _C("Failed to prepare daemon settings file"), L_OK);
		close(fd);
		vals = fallback_vals;
		daemon_pid = 0;
		return self;
	}
	memcpy(fallback_vals, prepared_vals, sizeof(prepared_vals));
	void *mapping = mmap(NULL, BATTMAN_DAEMON_SETTINGS_SIZE,
	                    PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (mapping == MAP_FAILED) {
		NSLog(@"mmap: Error - %s", strerror(errno));
		show_alert(L_ERR, _C("File mapping failed"), L_OK);
		vals = fallback_vals;
		daemon_pid = 0;
		close(fd);
		return self;
	}
	vals = (char *)mapping;
	vals_mapped = true;
	close(fd);
	[self refreshDaemonStatus];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIBarButtonItem *restore = [[UIBarButtonItem alloc] initWithTitle:_("Restore Defaults")
	                                                                  style:UIBarButtonItemStylePlain
	                                                                 target:self
	                                                                 action:@selector(restoreDefaults:)];
	restore.accessibilityLabel = _("Restore Defaults");
	restore.enabled = vals_mapped;
	self.navigationItem.rightBarButtonItem = restore;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refreshDaemonStatus];
	[self.tableView reloadData];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self refreshDaemonStatus];
}

- (void)refreshDaemonStatus {
	if (!vals_mapped) {
		[self invalidateDaemonConnection];
		daemon_pid = 0;
		self.navigationItem.rightBarButtonItem.enabled = NO;
		return;
	}

	char run_path[PATH_MAX];
	pid_t found_pid = 0;
	BOOL has_pid = CLDaemonPath(run_path, sizeof(run_path), ".run") &&
	               CLReadDaemonPID(run_path, &found_pid);
	if (!has_pid) {
		[self invalidateDaemonConnection];
		daemon_pid = 0;
		self.navigationItem.rightBarButtonItem.enabled = YES;
		return;
	}

	if (daemon_pid != (int)found_pid)
		[self invalidateDaemonConnection];
	daemon_pid = (int)found_pid;
	if (daemon_fd < 0 && ![self connectToDaemonWithAlerts:NO]) {
		/* A live PID without the tiny Battman handshake is not safe to control.
		 * Keep it visible as active so a later Stop/reconnect can recover it;
		 * never unlink a live process's run lock from this status refresh. */
		if (!CLDaemonPIDIsAlive(found_pid)) {
			CLRemoveStaleDaemonArtifacts(run_path, found_pid);
			daemon_pid = 0;
		}
	}
	self.navigationItem.rightBarButtonItem.enabled = YES;
}

- (void)restoreDefaults:(id)sender {
	(void)sender;
	if (!vals || !vals_mapped) {
		show_alert(L_FAILED, _C("Charging-limit settings are unavailable."), L_OK);
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Restore Defaults")
	                                                                   message:_("Restore the charging thresholds and mode settings to their defaults?")
	                                                            preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_("Restore") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		(void)action;
		unsigned char previous[BATTMAN_DAEMON_SETTINGS_SIZE];
		memcpy(previous, self->vals, sizeof(previous));
		self->vals[0] = (char)-1;
		self->vals[1] = (char)-1;
		self->vals[2] = 0;
		if (![self daemonRedecide]) {
			memcpy(self->vals, previous, sizeof(previous));
			(void)msync(self->vals, BATTMAN_DAEMON_SETTINGS_SIZE, MS_SYNC);
			show_alert(L_FAILED, _C("Unable to persist charging-limit defaults."), L_OK);
			return;
		}
		[self.tableView reloadData];
		UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, _("Charging-limit defaults restored."));
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)connectToDaemon {
	(void)[self connectToDaemonWithAlerts:YES];
}

- (BOOL)connectToDaemonWithAlerts:(BOOL)showAlerts {
	if (daemon_fd >= 0) {
		/* A descriptor can outlive the daemon across a respring/restart.  Do a
		 * bounded protocol ping before treating the cached connection as live;
		 * otherwise stop/redecide silently writes to a dead peer and never
		 * reaches the reconnect path. */
		char ping = 2;
		if (CLDaemonSend(daemon_fd, &ping, 1) == 1 &&
		    CLDaemonReceive(daemon_fd, &ping, 1) == 1 && ping == 2)
			return YES;
		[self invalidateDaemonConnection];
	}
	int fd = connect_to_daemon(showAlerts);
	if (fd <= 0) {
		daemon_fd = -1;
		return NO;
	}
	daemon_fd = fd;
	return YES;
}

- (void)invalidateDaemonConnection {
	if (daemon_fd >= 0)
		close(daemon_fd);
	daemon_fd = -1;
}

- (BOOL)receiveDaemonByte:(char *)byte {
	if (daemon_fd < 0 || !byte)
		return NO;
	return CLDaemonReceive(daemon_fd, byte, 1) == 1;
}

- (BOOL)sendDaemonCommand:(char)command reconnect:(BOOL)reconnect {
	for (int attempt = 0; attempt < (reconnect ? 2 : 1); attempt++) {
		/* Always validate a cached descriptor.  The daemon may have exited or
		 * been replaced since the previous command. */
		if (![self connectToDaemonWithAlerts:NO]) {
			/* A daemon can be between its PID-file and socket phases. Give a
			 * reconnecting command one more bounded attempt instead of returning
			 * before the retry loop has a chance to run. */
			if (reconnect && attempt == 0) {
				usleep(50000);
				continue;
			}
			return NO;
		}
		if (CLDaemonSend(daemon_fd, &command, 1) == 1)
			return YES;

		int saved_errno = errno;
		if (saved_errno == 0)
			saved_errno = EPIPE;
		[self invalidateDaemonConnection];
		BOOL transient = saved_errno == EPIPE || saved_errno == ECONNRESET ||
		                 saved_errno == ENOTCONN || saved_errno == EBADF ||
		                 saved_errno == ETIMEDOUT || saved_errno == EAGAIN;
		if (!reconnect || !transient)
			return NO;
	}
	return NO;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return powerlog_db_path ? _("7-Day Battery Level") : nil;
		case CL_SECTION_MAIN:
			return _("Charging Limit (Experimental)");
		default:
			break;
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return powerlog_db_path ? _("The system logs battery charge–level changes for the past 7 days. If this graph is empty, the power-log service may not be running correctly.") : nil;
		case CL_SECTION_MAIN:
			return vals_mapped ? _("Charging Limit uses a background service to monitor your battery's charge level and automatically adjust charging behavior.") : _("Charging-limit settings are unavailable because the settings file could not be opened safely.");
		default:
			break;
	}
	return nil;
}

- (void)dealloc {
	const char endconnectioncmd = 5;
	if (daemon_fd >= 0) {
		(void)CLDaemonSend(daemon_fd, &endconnectioncmd, 1);
		[self invalidateDaemonConnection];
	}
	if (vals && vals_mapped) {
		(void)msync(vals, BATTMAN_DAEMON_SETTINGS_SIZE, MS_SYNC);
		munmap(vals, BATTMAN_DAEMON_SETTINGS_SIZE);
	}
	free((void *)powerlog_db_path);
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)sect {
	CLSect section = (CLSect)sect;
	switch (section) {
		case CL_SECTION_GRAPH:
			return CL_GRAPH_COUNT;
		case CL_SECTION_MAIN:
			return CL_MAIN_COUNT;
		default:
			break;
	}
	return 0;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return CL_SECTION_COUNT;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == CL_SECTION_MAIN && indexPath.row == CL_MAIN_DAEMONSWITCH) {
		if (!vals || !vals_mapped) {
			show_alert(L_FAILED, _C("Charging-limit settings are unavailable."), L_OK);
			[tv deselectRowAtIndexPath:indexPath animated:YES];
			return;
		}
		if (daemon_pid) {
			NSLog(@"Daemon is likely active, requesting stop");
			if (![self connectToDaemonWithAlerts:NO]) {
				BOOL alive = CLDaemonPIDIsAlive((pid_t)daemon_pid);
				if (!alive) {
					CLRemoveStaleDaemonArtifacts(NULL, (pid_t)daemon_pid);
					daemon_pid = 0;
					[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
				} else {
				/* Keep a live-but-unresponsive PID visible as active. The run file
				 * remains a spawn lock and the user can retry Stop after the daemon
				 * finishes its startup/recovery work. */
					show_alert(L_ERR, _C("The daemon is running but did not answer. Try starting it again after it exits."), L_OK);
				}
				[tv deselectRowAtIndexPath:indexPath animated:YES];
				return;
			}
			char stop_cmd = 3;
			pid_t stopping_pid = (pid_t)daemon_pid;
			BOOL sent = [self sendDaemonCommand:stop_cmd reconnect:NO];
			BOOL stopped = sent && [self receiveDaemonByte:&stop_cmd] && stop_cmd == 3;
			[self invalidateDaemonConnection];
			if (stopped || !CLDaemonPIDIsAlive((pid_t)daemon_pid)) {
				NSLog(@"Daemon returned 3 - stopped");
				daemon_pid = 0;
				if (!stopped)
					CLRemoveStaleDaemonArtifacts(NULL, stopping_pid);
			} else if (!sent) {
				show_alert(L_ERR, _C("Unable to send the stop request to the daemon."), L_OK);
			} else {
				show_alert(L_ERR, _C("The daemon did not respond before the timeout."), L_OK);
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		} else {
			/* Validate only when starting.  A malformed settings record must not
			 * prevent the user from reaching the Stop/recovery path for an already
			 * running daemon. */
			if (!CLDaemonSettingsAreValid((const unsigned char *)vals)) {
				show_alert(_C("Invalid Setup"), _C("Limit Value should be bigger than Resume Value"), L_OK);
				[tv deselectRowAtIndexPath:indexPath animated:YES];
				return;
			}
			extern int battman_run_daemon(void);
			daemon_pid = battman_run_daemon();
			for (int i = 0; daemon_pid && i < 30; i++) {
				usleep(50000);
				(void)[self connectToDaemonWithAlerts:NO];
				if (daemon_fd >= 0) {
					DBGLOG(@"%@: Got Daemon fd: %d", indexPath, daemon_fd);
					break;
				}
			}
			if (daemon_pid && daemon_fd < 0) {
				pid_t started_pid = (pid_t)daemon_pid;
				if (!CLDaemonPIDIsAlive(started_pid)) {
					CLRemoveStaleDaemonArtifacts(NULL, started_pid);
					daemon_pid = 0;
				}
				/* Keep a live PID as active until it is confirmed dead. This avoids
				 * unlinking a replacement daemon's run/socket files and lets the user
				 * retry a bounded Stop request. */
				show_alert(L_FAILED, _C("Couldn't start the daemon — it isn’t responding."), L_OK);
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		}
	}
	[tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)cltypechanged:(UISegmentedControl *)segCon {
	if (!vals || !vals_mapped)
		return;
	if (segCon.selectedSegmentIndex) {
		/* Enabling resume mode requires a paired limit.  A fresh settings record
		 * represents the limit-only mode with 255 in both slots, so seed the
		 * visible/default 100% limit before publishing the resume threshold. */
		if ((unsigned char)vals[1] == 255)
			vals[1] = 100;
		vals[0] = 0;
	} else {
		vals[0] = (char)-1;
	}
	[self daemonRedecide];
	/* Refreshing the whole tableview causes animation lost */
	NSIndexPath *resumeIndexLabel  = [NSIndexPath indexPathForRow:CL_MAIN_RESUMELABEL inSection:CL_SECTION_MAIN];
	NSIndexPath *resumeIndexSlider = [NSIndexPath indexPathForRow:CL_MAIN_RESUME inSection:CL_SECTION_MAIN];
	[self.tableView reloadRowsAtIndexPaths:@[resumeIndexLabel, resumeIndexSlider] withRowAnimation:UITableViewRowAnimationFade];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (powerlog_db_path && indexPath.section == CL_SECTION_GRAPH) {
		return 150;
	}
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	if (previousTraitCollection)
		[super traitCollectionDidChange:previousTraitCollection];
	[self viewDidAppear:YES];
}

#if 0
// Only do this when we are using Apple provided legacy Graph
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (powerlog_db_path) {
		NSIndexPath *ip = [NSIndexPath indexPathForRow:CL_GRAPH_ROW inSection:CL_SECTION_GRAPH];
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
		if ([cell isKindOfClass:[PSGraphViewTableCell class]]) {
			UIView *graph = [(id)cell graphView];
		
			if (@available(iOS 13.0, *)) {
				changeLabelColors(cell, [UIColor labelColor]);
				@try {
					[(id)graph setLabelColor:[UIColor labelColor]];
				} @catch (NSException *exception) {
					os_log_error(gLog, "ChargingLimit: Failed to setLabelColor for graphView");
				}
			}

			[graph setNeedsLayout];
			[graph layoutSubviews];
			[graph setNeedsDisplay];
		}
	}
}
#endif

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = nil;
	CLSect section = (CLSect)indexPath.section;
	switch (section) {
		case CL_SECTION_GRAPH: {
			if (!powerlog_db_path) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = _("Unavailable");
				return cell;
			}
			sqlite3 *p_db = NULL;
			int      err = SQLITE_CANTOPEN;
			
			if (access(powerlog_db_path, R_OK) == 0) {
				// Use FULLMUTEX for thread safety and allow concurrent reads
				err = sqlite3_open_v2(powerlog_db_path, &p_db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, NULL);
			}
			
			if (err == SQLITE_OK) {
				// Set a 5-second timeout for busy database (when locked by other processes)
				sqlite3_busy_timeout(p_db, 5000);
			}
			if (err != SQLITE_OK) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = [NSString stringWithUTF8String:sqlite3_errmsg(p_db)];
				sqlite3_close_v2(p_db);
				return cell;
			}
			struct timespec ts;
			time_t cur_time;
			if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
				cur_time = ts.tv_sec;
			} else {
				cur_time = time(NULL);
			}
			double start_time = (double)(cur_time - 3600 * 24 * 7);
			double end_time = (double)cur_time;
			char query[256];
			snprintf(query, sizeof(query), "SELECT * FROM PLBatteryAgent_EventBackward_BatteryUI WHERE timestamp BETWEEN %lld AND %lld ORDER BY timestamp", (long long)start_time, (long long)end_time);
			char           *errmsg = NULL;
			NSMutableArray *arr = [NSMutableArray array];

			int retry_count = 0;
			const int max_retries = 3;
			do {
				err = sqlite3_exec(p_db, query, _cl_sql_pt_cb, (__bridge void *)arr, &errmsg);
				if (err == SQLITE_OK || err != SQLITE_BUSY) {
					break;
				}
				if (retry_count < max_retries) {
					usleep((100 * 1000) << retry_count);
					retry_count++;
					if (errmsg) {
						sqlite3_free(errmsg);
						errmsg = NULL;
					}
				}
			} while (retry_count < max_retries);
			if (err != SQLITE_OK) {
				cell                      = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				cell.textLabel.text       = _("7-Day Battery Level");
				cell.detailTextLabel.text = [NSString stringWithUTF8String:errmsg];
				sqlite3_free(errmsg);
				sqlite3_close_v2(p_db);
				return cell;
			}
			sqlite3_close_v2(p_db);
#if 0
			id            graphCell     = [PSGraphViewTableCell new];
			NSArray      *modelGraphArr = arr;
			UIScrollView *view          = [(id)graphCell scrollView];
			view.autoresizingMask       = UIViewAutoresizingFlexibleWidth;
#else
			PLGraphViewTableCell *graphCell = [PLGraphViewTableCell new];
#endif

#if 0
			[(id)graphCell setGraphArray:modelGraphArr];
#else
			graphCell.graphArray = arr;
#endif
			UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(graphLongPressed:)];
			[graphCell addGestureRecognizer:longPress];
			return graphCell;
		}
		case CL_SECTION_MAIN: {
			CLRowMain row = (CLRowMain)indexPath.row;
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			switch (row) {
				case CL_MAIN_CYCLEMODE: {
					cell.textLabel.text = _("When limit is reached");
					NSArray *items;
					if (@available(iOS 13.0, *)) {
						// XXX: Consider use dynamic check
						if (@available(iOS 14.0, *)) {
							items = @[[UIImage systemImageNamed:@"pause.rectangle"], [UIImage systemImageNamed:@"arrow.rectanglepath"]];
						} else {
							// Sadly arrow.rectanglepath is iOS 14+
							items = @[[UIImage systemImageNamed:@"pause.circle"], [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"]];
						}
					} else {
						// pause.rectangle U+10029B
						// arrow.rectanglepath U+1008C1
						items = @[@"􀊛", @"􀣁"];
					}
					UISegmentedControl *segCon = [[UISegmentedControl alloc] initWithItems:items];
					segCon.enabled = vals_mapped;
					segCon.accessibilityLabel = _("When limit is reached");
					if (@available(iOS 13.0, *)) {
						// Handle something?
					} else {
						[segCon setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIFont fontWithName:@SFPRO size:12.0], NSFontAttributeName, nil] forState:UIControlStateNormal];
					}
					
					if ((unsigned char)vals[0] == 255) {
						segCon.selectedSegmentIndex = 0;
					} else {
						segCon.selectedSegmentIndex = 1;
					}
					[segCon addTarget:self action:@selector(cltypechanged:) forControlEvents:UIControlEventValueChanged];
					cell.accessoryView = segCon;
					break;
				}
				case CL_MAIN_LIMITLABEL: {
					cell.textLabel.text = _("Limit charging at (%)");
					break;
				}
				case CL_MAIN_LIMIT: {
					SliderTableViewCell *scell = [tv dequeueReusableCellWithIdentifier:@"clhighthr" forIndexPath:indexPath];
					if (!scell) {
						scell = [[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"clhighthr"];
					}
					scell.slider.minimumValue = 1;
					 scell.slider.maximumValue = 100;
					scell.integerOnly     = YES;
					scell.slider.enabled      = vals_mapped;
					scell.textField.enabled   = vals_mapped;
					scell.slider.userInteractionEnabled = vals_mapped;
					scell.textField.userInteractionEnabled = vals_mapped;
					scell.slider.accessibilityLabel = _("Limit charging at (%)");
					scell.textField.accessibilityLabel = _("Limit charging at (%)");
					scell.delegate            = (id)self;
					if ((unsigned char)vals[1] == 255) {
						scell.slider.value   = 100;
						scell.textField.text = @"100";
					} else {
						scell.slider.value   = (float)vals[1];
						scell.textField.text = [NSString stringWithFormat:@"%d", (int)vals[1]];
					}
					return scell;
				}
				case CL_MAIN_RESUMELABEL: {
					if ((unsigned char)vals[0] == 255)
						cell.textLabel.enabled = NO;
					cell.textLabel.text = _("Resume charging at (%)");
					break;
				}
				case CL_MAIN_RESUME: {
					SliderTableViewCell *scell = [tv dequeueReusableCellWithIdentifier:@"cllowthr" forIndexPath:indexPath];
					if (!scell) {
						scell = [[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cllowthr"];
					}
					 scell.slider.minimumValue = 0;
					 scell.slider.maximumValue = 100;
					scell.integerOnly     = YES;
					scell.delegate            = (id)self;
					scell.slider.accessibilityLabel = _("Resume charging at (%)");
					scell.textField.accessibilityLabel = _("Resume charging at (%)");
					if ((unsigned char)vals[0] == 255) {
						scell.slider.enabled                   = NO;
						scell.slider.userInteractionEnabled    = NO;
						scell.slider.value                     = 0;
						scell.textField.enabled                = 0;
						scell.textField.userInteractionEnabled = 0;
						scell.textField.text                   = @"0";
					} else {
						scell.slider.enabled                   = vals_mapped;
						scell.slider.userInteractionEnabled    = vals_mapped;
						scell.slider.value                     = (float)vals[0];
						scell.textField.enabled                = vals_mapped;
						scell.textField.userInteractionEnabled = vals_mapped;
						scell.textField.text                   = [NSString stringWithFormat:@"%d", (int)vals[0]];
					}
					return scell;
				}
				case CL_MAIN_DISCHGMODE: {
					cell.textLabel.text = _("Drain Mode");
					PickerAccessoryView *picker = [[PickerAccessoryView alloc] initWithFrame:CGRectZero font:nil options:self.drainModes];
					[picker addTarget:self action:@selector(drainModeChanged:)];
					picker.userInteractionEnabled = vals_mapped;
					picker.accessibilityLabel = _("Drain Mode");
					[picker selectAutomaticRow:BIT_GET(vals[2], 0) animated:YES];
					cell.accessoryView = picker;
					cell.clipsToBounds = YES;
					break;
				}
				case CL_MAIN_OBCSWITCH: {
					cell.textLabel.text = _("Override OBC On Cycle");
					UISwitch *cswitch = [UISwitch new];
					cswitch.on = BIT_GET(vals[2], 1);
					cswitch.enabled = vals_mapped;
					cswitch.accessibilityLabel = _("Override OBC On Cycle");
					cswitch.accessibilityValue = cswitch.on ? _("Enabled") : _("Disabled");
					cell.detailTextLabel.text = cswitch.on ? _("OBC will turn off") : _("OBC will not be affected");
					[cswitch addTarget:self action:@selector(overrideOBCChanged:) forControlEvents:UIControlEventValueChanged];
					cell.accessoryView = cswitch;
					break;
				}
				case CL_MAIN_PIDLABEL: {
					if (daemon_pid) {
						DBGLOG(@"%@: Got Daemon PID: %d", indexPath, daemon_pid);
						cell.textLabel.text = [NSString stringWithFormat:@"%@ (%@: %d)", _("Daemon is active"), _("PID"), daemon_pid];
					} else {
						cell.textLabel.text = _("Daemon is inactive");
					}
					break;
				}
				case CL_MAIN_DAEMONSWITCH: {
					BOOL enforced = BIT_GET(vals[2], 1);
					NSString *labelText = [NSString stringWithFormat:@"%@", daemon_pid ? _("Stop Daemon %@") : _("Start Daemon %@")];
					cell.textLabel.text = [NSString stringWithFormat:labelText, enforced ? _("(Enforce Mode)") : _("(Soft Mode)")];
					cell.detailTextLabel.text = enforced ? _("Battman charging limits are enforced") : _("OBC may ignore Battman charging limits");
					cell.selectionStyle = vals_mapped ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
					cell.textLabel.textColor = [UIColor compatLinkColor];
					break;
				}
				case CL_MAIN_COUNT: {
					break;
				}
			}
		}
		default:
			break;
	}

	return cell;
}

#pragma mark - SliderTableViewCell Delegate

- (void)sliderTableViewCellDidBeginChanging:(SliderTableViewCell *)cell {
	if (!vals || !vals_mapped)
		return;
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];
		if ((unsigned char)vals[0] != 255) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = NO;
		}
		return;
	}

	os_log_error(gLog, "sliderTableViewCellDidBeginChanging: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
	if (!vals || !vals_mapped)
		return;
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	int8_t rounded = (int8_t)lroundf(value);
	NSIndexPath *ip = [self.tableView indexPathForCell:cell];
	if (ip.section == CL_SECTION_MAIN) {
		/* Keep the resume threshold strictly below the limit.  Equality used to
		 * pass the UI validation but selected the daemon's "resume" branch at the
		 * shared boundary, so charging could never be inhibited at that value. */
		int resumeThreshold = (unsigned char)vals[0];
		int limitThreshold = (unsigned char)vals[1];
		BOOL violatesOrder = isHighThr
			? (resumeThreshold != 255 && (int)rounded <= resumeThreshold)
			: (limitThreshold != 255 && (int)rounded >= limitThreshold);
		if (violatesOrder) {
			int adjusted = (int)rounded + (isHighThr ? -1 : 1);
			if (!isHighThr && adjusted > 100) {
				/* A 100% resume value cannot have a larger limit; clamp the
				 * edited value to 99 and retain the 100% limit. */
				rounded = 99;
				adjusted = 100;
			}
			adjusted = MIN(MAX(adjusted, 0), 100);
			vals[!isHighThr] = (char)adjusted;

			// XXX: Improve readability
			NSIndexPath *oppo = [NSIndexPath indexPathForRow:[self.tableView indexPathForCell:cell].row - (isHighThr ? -2 : 2) inSection:[self.tableView indexPathForCell:cell].section];
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.slider.value = vals[!isHighThr];
			oppocell.textField.text = [NSString stringWithFormat:@"%d", vals[!isHighThr]];
		}
		
		vals[isHighThr] = rounded;
		cell.slider.value = rounded;
		cell.textField.text = [NSString stringWithFormat:@"%d", rounded];
		return;
	}

	os_log_error(gLog, "sliderTableViewCell:didChangeValue: unexpected call at indexPath %ld:%ld", ip.section, ip.row);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value {
	if (!vals || !vals_mapped)
		return;
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];

		if ((unsigned char)vals[0] != 255) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = YES;
		}

		[self daemonRedecide];
		return;
	}

	os_log_error(gLog, "sliderTableViewCell:didEndChangingValue: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}



- (BOOL)daemonRedecide {
	if (!vals || !vals_mapped)
		return NO;
	/* Do msync after vals[] changes. The old sizeof(vals) expression measured
	 * the pointer (8 bytes on arm64), not the shared record. */
	if (msync(vals, BATTMAN_DAEMON_SETTINGS_SIZE, MS_SYNC) == -1) {
		os_log_error(gLog, "msync failed: %s", strerror(errno));
		return NO;
	}
	if (daemon_fd >= 0 || daemon_pid) {
		const char redecidecmd = 4;
		if (![self sendDaemonCommand:redecidecmd reconnect:YES])
			DBGLOG(@"Daemon is unavailable; persisted charging-limit settings will be applied on reconnect");
	}
	return YES;
}

- (void)drainModeChanged:(PickerAccessoryView *)sender {
	if (!vals || !vals_mapped || sender.options.count == 0)
		return;
	NSInteger row = [sender selectedRowInComponent:0];
	NSInteger opt = row % sender.options.count;
	DBGLOG(@"Value %ld: %@", opt, sender.options[opt]);
	/* Currently we only have 2 drain modes so this is a binary stored at bit 0
	 * This has to be changed once we have more than 2 */
	BIT_SET(vals[2], 0, (opt & 1));
	[self daemonRedecide];
}

- (void)overrideOBCChanged:(UISwitch *)sender {
	if (!vals || !vals_mapped)
		return;
	BIT_SET(vals[2], 1, sender.on);
	[self daemonRedecide];
	/* Im lazy, so hardcode here */
	NSIndexPath *ip = [NSIndexPath indexPathForRow:CL_MAIN_OBCSWITCH inSection:CL_SECTION_MAIN];
	NSIndexPath *button = [NSIndexPath indexPathForRow:CL_MAIN_DAEMONSWITCH inSection:CL_SECTION_MAIN];
	[self.tableView reloadRowsAtIndexPaths:@[ip, button] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
