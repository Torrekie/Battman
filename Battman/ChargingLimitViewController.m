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
#include <signal.h>
#include <sqlite3.h>
#include <sys/errno.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

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

int connect_to_daemon(bool show_alerts) {
	struct sockaddr_un sockaddr;
	memset(&sockaddr, 0, sizeof(sockaddr));
	sockaddr.sun_family = AF_UNIX;

	// Use centralized socket path with iOS fallback paths
	const char *socket_path = battman_socket_path();
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
	
	if (connect(sock, (struct sockaddr *)&sockaddr, (socklen_t)addrlen) == -1) {
		/*
		char errstr[1024];
		snprintf(errstr, sizeof(errstr), "%s\n%s\n%s: %s", _C("Failed to connect to daemon at"), sockaddr.sun_path, L_ERR, strerror(errno));
		show_alert(L_ERR, errstr, L_OK);
		close(sock);
		 */
		// No alert bc we need to retry
		return 0;
	}
	
	char cmd = 2;
	if (write(sock, &cmd, 1) != 1) {
		NSLog(@"Failed to write ping to daemon: %s", strerror(errno));
		if (show_alerts) show_alert(L_FAILED, "Failed to write to daemon.", L_OK);
		close(sock);
		return 0;
	}
	if (read(sock, &cmd, 1) != 1 || cmd != 2) {
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

	char  buf[1024];
	char *end = stpcpy(stpcpy(buf, battman_config_dir()), "/daemon");
	strcpy(end, ".run");
	int drfd = open(buf, O_RDONLY);
	if (drfd != -1) {
		int pid;
		if (read(drfd, &pid, 4) == 4) {
			// Check if the process actually exists
			// kill(pid, 0) returns 0 if process exists, -1 if not
			// errno is ESRCH if process doesn't exist
			if (kill(pid, 0) == 0) {
				daemon_pid = pid;
			} else if (errno == ESRCH) {
				// Process doesn't exist, clean up stale PID file
				NSLog(@"Found stale daemon PID file for PID %d, cleaning up", pid);
				unlink(buf);
			} else {
				// Other error (EPERM, etc.), assume process exists for safety
				daemon_pid = pid;
			}
		}
		close(drfd);
	}

	strcpy(end, "_settings");
	int fd = open(buf, O_RDWR | O_CREAT, 0644);
	if (fd == -1) {
		NSLog(@"open %s: Error - %s", buf, strerror(errno));
		show_alert(L_ERR, _C("Failed to open daemon settings file"), L_OK);
		vals = NULL;
		return self;
	}
	// See daemon.c for vals struct, we are doing bad practice here
	char _vals[3];
	if (read(fd, _vals, 3) != 3) {
		NSLog(@"Writing initial values to daemon_settings");
		_vals[0] = -1;
		_vals[1] = -1;
		_vals[2] = 0;
		lseek(fd, 0, SEEK_SET);
		write(fd, _vals, 3);
	}
	lseek(fd, 0, SEEK_SET);
	vals = mmap(NULL, 3, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if ((long long)vals == -1) {
		NSLog(@"mmap: Error - %s", strerror(errno));
		show_alert(L_ERR, _C("File mapping failed"), L_OK);
		vals = NULL;
		close(fd);
		return self;
	}
	close(fd);
	if (daemon_pid) {
		NSLog(@"Daemon likely valid, trying to connect");
		[self connectToDaemon];
	}
	return self;
}

- (void)connectToDaemon {
	if (daemon_fd)
		return;
	daemon_fd = connect_to_daemon(true);
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
			return _("Charging Limit uses a background service to monitor your battery's charge level and automatically adjust charging behavior.");
		default:
			break;
	}
	return nil;
}

- (void)dealloc {
	const char endconnectioncmd = 5;
	if (daemon_fd) {
		write(daemon_fd, &endconnectioncmd, 1);
		close(daemon_fd);
	}
	if (vals)
		munmap(vals, 3);
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
		if (vals[1] < vals[0]) {
			show_alert(_C("Invalid Setup"), _C("Limit Value should be bigger than Resume Value"), L_OK);
			return;
		}
		if (daemon_pid) {
			NSLog(@"Daemon is likely active, requesting stop");
			if (!daemon_fd) {
				show_alert(L_ERR, _C("Unable to connect to the daemon."), L_OK);
				[tv deselectRowAtIndexPath:indexPath animated:YES];
				return;
			}
			char stop_cmd = 3;
			write(daemon_fd, &stop_cmd, 1);
			if (read(daemon_fd, &stop_cmd, 1) == 1 && stop_cmd == 3) {
				NSLog(@"Daemon returned 3 - stopped");
				daemon_pid = 0;
				close(daemon_fd);
				daemon_fd = 0;
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		} else {
			extern int battman_run_daemon(void);
			daemon_pid = battman_run_daemon();
			for (int i = 0; i < 30; i++) {
				usleep(50000);
				[self connectToDaemon];
				if (daemon_fd) {
					DBGLOG(@"%@: Got Daemon fd: %d", indexPath, daemon_fd);
					break;
				} else if (i == 29) {
					if (errno != 0) {
						char *errmsg = calloc(256, sizeof(char));
						sprintf(errmsg, "%s\n%s: %s", _C("Unable to connect to the daemon."), L_ERR, strerror(errno));
						show_alert(L_FAILED, errmsg, L_OK);
						free(errmsg);
					} else {
						show_alert(L_FAILED, _C("Couldn't start the daemon — it isn’t responding."), L_OK);
					}
				}
			}
			[tv reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:CL_MAIN_PIDLABEL inSection:CL_SECTION_MAIN], indexPath] withRowAnimation:UITableViewRowAnimationFade];
		}
	}
	[tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)cltypechanged:(UISegmentedControl *)segCon {
	vals[0] = segCon.selectedSegmentIndex ? 0 : -1;
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
	UITableViewCell *cell;
	CLSect section = (CLSect)indexPath.section;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
					if (@available(iOS 13.0, *)) {
						// Handle something?
					} else {
						[segCon setTitleTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:[UIFont fontWithName:@SFPRO size:12.0], NSFontAttributeName, nil] forState:UIControlStateNormal];
					}
					
					if (vals[0] == -1) {
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
					scell.slider.enabled      = 1;
					scell.textField.enabled   = 1;
					scell.delegate            = (id)self;
					if (vals[1] == -1) {
						scell.slider.value   = 100;
						scell.textField.text = @"100";
					} else {
						scell.slider.value   = (float)vals[1];
						scell.textField.text = [NSString stringWithFormat:@"%d", (int)vals[1]];
					}
					return scell;
				}
				case CL_MAIN_RESUMELABEL: {
					if (vals[0] == -1)
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
					scell.delegate            = (id)self;
					if (vals[0] == -1) {
						scell.slider.enabled                   = NO;
						scell.slider.userInteractionEnabled    = NO;
						scell.slider.value                     = 0;
						scell.textField.enabled                = 0;
						scell.textField.userInteractionEnabled = 0;
						scell.textField.text                   = @"0";
					} else {
						scell.slider.enabled                   = 1;
						scell.slider.userInteractionEnabled    = 1;
						scell.slider.value                     = (float)vals[0];
						scell.textField.enabled                = 1;
						scell.textField.userInteractionEnabled = 1;
						scell.textField.text                   = [NSString stringWithFormat:@"%d", (int)vals[0]];
					}
					return scell;
				}
				case CL_MAIN_DISCHGMODE: {
					cell.textLabel.text = _("Drain Mode");
					PickerAccessoryView *picker = [[PickerAccessoryView alloc] initWithFrame:CGRectZero font:nil options:self.drainModes];
					[picker addTarget:self action:@selector(drainModeChanged:)];
					[picker selectAutomaticRow:BIT_GET(vals[2], 0) animated:YES];
					cell.accessoryView = picker;
					cell.clipsToBounds = YES;
					break;
				}
				case CL_MAIN_OBCSWITCH: {
					cell.textLabel.text = _("Override OBC On Cycle");
					UISwitch *cswitch = [UISwitch new];
					cswitch.on = BIT_GET(vals[2], 1);
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
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
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
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];
		if (vals[0] != -1) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = NO;
		}
	}

	os_log_error(gLog, "sliderTableViewCellDidBeginChanging: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	int8_t rounded = (int8_t)lroundf(value);
	NSIndexPath *ip = [self.tableView indexPathForCell:cell];
	if (ip.section == CL_SECTION_MAIN) {
		if ((isHighThr && value < vals[0]) || (!isHighThr && value > vals[1])) {
			vals[!isHighThr] = rounded + (isHighThr ? -1 : 1);
			vals[!isHighThr] = MIN(MAX(vals[!isHighThr], 0), 100);

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
	BOOL isHighThr = [cell.reuseIdentifier isEqualToString:@"clhighthr"];
	NSIndexPath *curr = [self.tableView indexPathForCell:cell];
	if (curr.section == CL_SECTION_MAIN) {
		NSIndexPath *oppo = [NSIndexPath indexPathForRow:curr.row - (isHighThr ? -2 : 2) inSection:curr.section];

		if (vals[0] != -1) {
			SliderTableViewCell *oppocell = [self.tableView cellForRowAtIndexPath:oppo];
			oppocell.userInteractionEnabled = YES;
		}

		[self daemonRedecide];
	}

	os_log_error(gLog, "sliderTableViewCell:didEndChangingValue: unexpected call at indexPath %ld:%ld", curr.section, curr.row);
}


- (void)daemonRedecide {
	// Do msync after vals[] changes
	if (msync(vals, sizeof(vals), MS_SYNC) == -1) {
		os_log_error(gLog, "msync failed: %s", strerror(errno));
	}
	const char redecidecmd = 4;
	write(daemon_fd, &redecidecmd, 1);
}

- (void)drainModeChanged:(PickerAccessoryView *)sender {
	NSInteger row = [sender selectedRowInComponent:0];
	NSInteger opt = row % sender.options.count;
	DBGLOG(@"Value %ld: %@", opt, sender.options[opt]);
	/* Currently we only have 2 drain modes so this is a binary stored at bit 0
	 * This has to be changed once we have more than 2 */
	BIT_SET(vals[2], 0, (opt & 1));
	[self daemonRedecide];
}

- (void)overrideOBCChanged:(UISwitch *)sender {
	BIT_SET(vals[2], 1, sender.on);
	[self daemonRedecide];
	/* Im lazy, so hardcode here */
	NSIndexPath *ip = [NSIndexPath indexPathForRow:CL_MAIN_OBCSWITCH inSection:CL_SECTION_MAIN];
	NSIndexPath *button = [NSIndexPath indexPathForRow:CL_MAIN_DAEMONSWITCH inSection:CL_SECTION_MAIN];
	[self.tableView reloadRowsAtIndexPaths:@[ip, button] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
