#import "ObjCExt/UIScreen+Auto.h"
#import "ObjCExt/CALayer+smoothCorners.h"

#import "BatteryInfoViewController.h"
#import "BatteryCellView/BatteryInfoTableViewCell.h"
#import "BatteryCellView/TemperatureInfoTableViewCell.h"
#import "BatteryCellView/BrightnessInfoTableViewCell.h"

#import "BatteryDetailsViewController.h"
#import "ChargingManagementViewController.h"
#import "ChargingLimitViewController.h"
#import "ThermalTunesViewContoller.h"
#include "battery_utils/battery_utils.h"
#import "SimpleTemperatureViewController.h"
#import "BrightnessDetailsViewController.h"
#import "UPSMonitor.h"
#import "BattmanPrefs.h"

#include "common.h"
#include "intlextern.h"

@interface UIImage ()
+ (instancetype)_applicationIconImageForBundleIdentifier:(NSString*)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

BOOL artwork_avail = NO;
static CFArrayRef (*CPBitmapCreateImagesFromPath)(CFStringRef, CFPropertyListRef *, uint32_t, CFErrorRef *) = NULL;

// Cached arrays
static CFArrayRef sArtworkNames  = NULL;
static CFArrayRef sArtworkImages = NULL;

// Initialize by dlopen/dlsym + one call to CPBitmapCreateImagesFromPath
static void _loadAppSupportBundle(void) {
	void *h = dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
	if (!h) {
		os_log_error(gLog, "dlopen(AppSupport) failed: %s\n", dlerror());
		return;
	}

	CPBitmapCreateImagesFromPath = dlsym(h, "CPBitmapCreateImagesFromPath");
	if (!CPBitmapCreateImagesFromPath) {
		os_log_error(gLog, "dlsym(CPBitmapCreateImagesFromPath) failed: %s\n", dlerror());
		dlclose(h);
		return;
	}

	CFErrorRef  err    = NULL;
	UIScreen *screen = [UIScreen autoScreen];
	NSString   *size   = [NSString stringWithFormat:@"BattmanIcons@%dx", (screen && screen.scale >= 3.0) ? 3 : 2];
	CFStringRef cfPath = (__bridge CFStringRef)[[NSBundle mainBundle] pathForResource:size ofType:@"artwork"];
	CFPropertyListRef names = NULL;
	CFArrayRef images = CPBitmapCreateImagesFromPath(cfPath, &names, 0, &err);
	
	if (!images || !names) {
		if (err) {
			CFStringRef desc = CFErrorCopyDescription(err);
			char buf[256];
			CFStringGetCString(desc, buf, sizeof(buf), kCFStringEncodingUTF8);
			os_log_error(gLog, "Artwork load error: %s\n", buf);
			CFRelease(desc);
			CFRelease(err);
		}
		return;
	}
	artwork_avail  = true;
	sArtworkNames  = names;
	sArtworkImages = images;
}

CGImageRef getArtworkImageOf(CFStringRef name) {
	if (!sArtworkNames || !sArtworkImages)
		return NULL;

	CFIndex count = CFArrayGetCount(sArtworkNames);
	for (CFIndex i = 0; i < count; i++) {
		CFStringRef candidate = CFArrayGetValueAtIndex(sArtworkNames, i);
		if (CFStringCompare(candidate, name, 0) == kCFCompareEqualTo) {
			CGImageRef img = (CGImageRef)CFArrayGetValueAtIndex(sArtworkImages, i);
			return img;
		}
	}

	return NULL;
}

// TODO: UI Refreshing

enum sections_batteryinfo {
	BI_SECT_BATTERY_INFO,
	BI_SECT_HW_TEMP,
	BI_SECT_BRIGHTNESS,
	BI_SECT_MANAGE,
	BI_SECT_COUNT
};

@implementation BatteryInfoViewController {
	CGFloat _cachedIconCornerRadius;
	BOOL _cachedIconCornerRadiusValid;
}

- (NSString *)title {
    return _("Battman");
}

- (void)batteryStatusDidUpdate:(NSDictionary *)info {
	// Check refresh preferences - only update if in auto mode (0) or manual refresh
	float interval = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_BI_INTERVAL];
	if (interval == -1.0f) {
		// Never mode - don't update automatically
		return;
	}
	NSLog(@"batteryStatusDidUpdate: interval: %f", interval);
	// Only call super (which calls updateTableView) in auto mode
	// In timer mode, the timer handles calling updateTableView directly
	if (interval == 0.0f) {
		//battery_info_update(&batteryInfo);
		//battery_info_update_iokit_with_data(batteryInfo,(__bridge CFDictionaryRef)info,0);
		DBGLOG(@"BIVC: batteryStatusDidUpdate");
		[super batteryStatusDidUpdate];
	}
}

- (void)viewDidLoad {
    [super viewDidLoad];
	
	// Register cell classes for reuse - cells now support initWithStyle:reuseIdentifier:
	[self.tableView registerClass:[BatteryInfoTableViewCell class] forCellReuseIdentifier:@"BTTVC-cell"];
	[self.tableView registerClass:[TemperatureInfoTableViewCell class] forCellReuseIdentifier:@"TITVC-ri"];
	[self.tableView registerClass:[BrightnessInfoTableViewCell class] forCellReuseIdentifier:@"BITVC-ri"];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(updateTableView) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;

    // Copyright text
    UILabel *copyright;
    copyright = [[UILabel alloc] init];
    NSString *me = _("2025 Ⓒ Torrekie <me@torrekie.dev>");
#ifdef DEBUG
    /* FIXME: GIT_COMMIT_HASH should be a macro */
    copyright.text = [NSString stringWithFormat:@"%@\n%@ %@\n%s %s", me, _("Debug Commit"), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GIT_COMMIT_HASH"], __DATE__, __TIME__];
#else
	copyright.text = [NSString stringWithFormat:@"%@\n%@ %@", me, _("Commit"), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"GIT_COMMIT_HASH"]];
#endif
	copyright.numberOfLines = 0;

    /* FIXME: Containered is not Sandboxed, try some extra checks */
    char *home = getenv("HOME");
    if (match_regex(home, IOS_CONTAINER_FMT) || match_regex(home, MAC_CONTAINER_FMT)) {
        copyright.text = [copyright.text stringByAppendingFormat:@"\n%@", _("Sandboxed")];
    } else if (match_regex(home, SIM_CONTAINER_FMT)) {
        copyright.text = [copyright.text stringByAppendingFormat:@"\n%@", _("Simulator Sandboxed")];
    } else if (match_regex(home, SIM_UNSANDBOX_FMT)){
        copyright.text = [copyright.text stringByAppendingFormat:@"\n%@", _("Simulator Unsandboxed")];
	} else if (match_regex(home, IOS_ROOTHIDEN_FMT)) {
		copyright.text = [copyright.text stringByAppendingFormat:@"\n%@", _("Roothide Unsandboxed")];
    } else {
        DBGLOG(@"HOME: %s", home);
        copyright.text = [copyright.text stringByAppendingFormat:@"\n%@", _("Unsandboxed")];
    }

	if (is_platformized())
		copyright.text = [copyright.text stringByAppendingFormat:@", %@", _("Platfomized")];

	if (is_debugged())
		copyright.text = [copyright.text stringByAppendingFormat:@", %@", _("Debugger Attached")];

	extern int connect_to_daemon(bool);
	// Clear badge state
	if (!connect_to_daemon(false))
		set_badge(NULL);

	copyright.font = [UIFont systemFontOfSize:12];
    copyright.textAlignment = NSTextAlignmentCenter;
    copyright.textColor = [UIColor grayColor];
    [copyright sizeToFit];
    self.tableView.tableFooterView = copyright;
}

- (instancetype)init {
#ifdef DEBUG
	CFAbsoluteTime initStart = CFAbsoluteTimeGetCurrent();
	DBGLOG(@"[PERF] BatteryInfoViewController init START");
#endif
	
    UITabBarItem *tabbarItem = [UITabBarItem new];
    tabbarItem.title = _("Battery");
    if (@available(iOS 13.0, *)) {
		// This is really an odd bug, why systemImageNamed: cares about numeric localizations?
		char *old = setlocale(LC_NUMERIC, NULL);
		setlocale(LC_NUMERIC, "C");
        tabbarItem.image = [UIImage systemImageNamed:@"battery.100"];
		if (old)
			setlocale(LC_NUMERIC, old);
    } else {
        // U+1006E8
        tabbarItem.image = imageForSFProGlyph(@"􀛨", @SFPRO, 22, [UIColor grayColor]);
    }
    tabbarItem.tag = 0;
    self.tabBarItem = tabbarItem;
#ifdef DEBUG
	DBGLOG(@"[PERF]   After tab bar item setup: %.3fms", (CFAbsoluteTimeGetCurrent() - initStart) * 1000);
#endif
	
    battery_info_init(&batteryInfo);
#ifdef DEBUG
	DBGLOG(@"[PERF]   After battery_info_init: %.3fms", (CFAbsoluteTimeGetCurrent() - initStart) * 1000);
#endif
	
	[UPSMonitor startWatchingUPS];
#ifdef DEBUG
	DBGLOG(@"[PERF]   After UPSMonitor start: %.3fms", (CFAbsoluteTimeGetCurrent() - initStart) * 1000);
#endif

	_loadAppSupportBundle();
#ifdef DEBUG
	DBGLOG(@"[PERF]   After _loadAppSupportBundle: %.3fms", (CFAbsoluteTimeGetCurrent() - initStart) * 1000);
	DBGLOG(@"[PERF] BatteryInfoViewController init DONE: %.3fms", (CFAbsoluteTimeGetCurrent() - initStart) * 1000);
#endif
	
	if (@available(iOS 13.0, *))
		return [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewWillAppear:(BOOL)animated {
#ifdef DEBUG
	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	DBGLOG(@"[PERF] BatteryInfoViewController viewWillAppear START");
#endif
	
	[super viewWillAppear:animated];
#ifdef DEBUG
	DBGLOG(@"[PERF] After super viewWillAppear: %.3fms", (CFAbsoluteTimeGetCurrent() - start) * 1000);
#endif
	
	// Update refresh mode based on current preferences
	BSVCRefreshModeDidUpdate(self);
#ifdef DEBUG
	DBGLOG(@"[PERF] After BSVCRefreshModeDidUpdate: %.3fms", (CFAbsoluteTimeGetCurrent() - start) * 1000);
	DBGLOG(@"[PERF] BatteryInfoViewController viewWillAppear DONE: %.3fms", (CFAbsoluteTimeGetCurrent() - start) * 1000);
#endif
}

- (void)refreshModeDidUpdate {
	// Called when preferences change
	BSVCRefreshModeDidUpdate(self);
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
	if (section == BI_SECT_MANAGE)
		return 3;
    return 1;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
    return BI_SECT_COUNT;
}

- (NSString *)tableView:(id)t titleForHeaderInSection:(NSInteger)sect {
#ifdef DEBUG
	CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
	DBGLOG(@"[PERF] titleForHeaderInSection:%ld START", (long)sect);
#endif
	
	NSString *title = nil;
	switch(sect) {
        case BI_SECT_BATTERY_INFO:
            title = _("Battery Info");
			break;
        case BI_SECT_HW_TEMP:
            title = _("Hardware Temperature");
			break;
		case BI_SECT_BRIGHTNESS:
			title = _("Brightness");
			break;
        case BI_SECT_MANAGE:
            title = _("Manage");
			break;
        default:
            title = nil;
			break;
	}
	
#ifdef DEBUG
	DBGLOG(@"[PERF] titleForHeaderInSection:%ld DONE: %.3fms", (long)sect, (CFAbsoluteTimeGetCurrent() - start) * 1000);
#endif
	return title;
}

- (NSString *)tableView:(id)tv titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == BI_SECT_BATTERY_INFO)
        [self.navigationController pushViewController:[[BatteryDetailsViewController alloc] initWithBatteryInfo:&batteryInfo] animated:YES];
	else if (indexPath.section == BI_SECT_HW_TEMP)
		[self.navigationController pushViewController:[SimpleTemperatureViewController new] animated:YES];
	else if (indexPath.section == BI_SECT_BRIGHTNESS)
		[self.navigationController pushViewController:[BrightnessDetailsViewController new] animated:YES];
	else if (indexPath.section == BI_SECT_MANAGE) {
		UIViewController *vc = nil;
		switch (indexPath.row) {
			case 0:
				vc = [ChargingManagementViewController new];
				break;
			case 1:
				vc = [ChargingLimitViewController new];
				break;
			case 2:
				vc = [ThermalTunesViewContoller new];
				break;
			default:
				break;
		}
		if (vc)
			[self.navigationController pushViewController:vc animated:YES];
		else
			show_alert(_C("Unimplemented Yet"), _C("Will be introduced in future updates."), L_OK);
	}
    [tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
#ifdef DEBUG
	CFAbsoluteTime cellStart = CFAbsoluteTimeGetCurrent();
	DBGLOG(@"[PERF] cellForRowAtIndexPath section:%ld row:%ld START", (long)indexPath.section, (long)indexPath.row);
#endif
	
    if (indexPath.section == BI_SECT_BATTERY_INFO) {
        BatteryInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"BTTVC-cell"];
#ifdef DEBUG
		DBGLOG(@"[PERF]   After dequeue: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
        if (!cell) {
        	cell = [BatteryInfoTableViewCell new];
#ifdef DEBUG
			DBGLOG(@"[PERF]   After new cell: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
		}
        cell.batteryInfo = &batteryInfo;
        // Defer expensive update to avoid blocking main thread during cell creation
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell updateBatteryInfo];
        });
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
#ifdef DEBUG
		DBGLOG(@"[PERF] cellForRowAtIndexPath BATTERY DONE: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
        return cell;
    } else if (indexPath.section == BI_SECT_HW_TEMP) {
        TemperatureInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"TITVC-ri"];
#ifdef DEBUG
		DBGLOG(@"[PERF]   After dequeue: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
        if (!cell) {
        	cell = [TemperatureInfoTableViewCell new];
#ifdef DEBUG
			DBGLOG(@"[PERF]   After new cell: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
		}
        // Defer expensive SMC/IOKit calls to avoid blocking main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell updateTemperatureInfo];
        });
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
#ifdef DEBUG
		DBGLOG(@"[PERF] cellForRowAtIndexPath TEMP DONE: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
        return cell;
	} else if (indexPath.section == BI_SECT_BRIGHTNESS) {
		BrightnessInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"BITVC-ri"];
#ifdef DEBUG
		DBGLOG(@"[PERF]   After dequeue: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
		if (!cell) {
			cell = [BrightnessInfoTableViewCell new];
#ifdef DEBUG
			DBGLOG(@"[PERF]   After new cell: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
		}
        // Defer expensive brightness I/O to avoid blocking main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [cell updateBrightnessInfo];
        });
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
#ifdef DEBUG
		DBGLOG(@"[PERF] cellForRowAtIndexPath BRIGHTNESS DONE: %.3fms", (CFAbsoluteTimeGetCurrent() - cellStart) * 1000);
#endif
		return cell;
    } else if (indexPath.section == BI_SECT_MANAGE) {
		// XXX: Try make this section "InsetGrouped"
        UITableViewCell *cell = [UITableViewCell new];
		// I want NSConstantArray
		NSArray *rows = @[_("Charging Management"), _("Charging Limit"), _("Thermal Tunes")];
		if (artwork_avail) {
			NSArray *icns = @[@"LowPowerUsage", @"ChargeLimit", @"Thermometer"];
			UIScreen *screen = [UIScreen autoScreen];
			cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf((__bridge CFStringRef)icns[indexPath.row]) scale:(screen ? screen.scale : 2.0) orientation:UIImageOrientationUp];
		}
		cell.textLabel.text = rows[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	// Smooth corners for icons
	if (cell.imageView.image != nil) {
		// Cache the corner radius calculation to avoid expensive _applicationIconImageForBundleIdentifier calls
		if (!_cachedIconCornerRadiusValid) {
			UIScreen *screen = [UIScreen autoScreen];
			UIImage *tmp = [UIImage _applicationIconImageForBundleIdentifier:[NSBundle.mainBundle bundleIdentifier] format:0 scale:(screen ? screen.scale : 2.0)];
			_cachedIconCornerRadius = tmp.size.width * 0.225f;
			_cachedIconCornerRadiusValid = YES;
		}
		[cell.imageView.layer setCornerRadius:_cachedIconCornerRadius];
		[cell.imageView.layer setSmoothCorners:YES];
		cell.imageView.clipsToBounds = YES;
	}
}

- (CGFloat)tableView:(id)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	// TODO: reduce redundant
    if (indexPath.section == BI_SECT_BATTERY_INFO && indexPath.row == 0) {
        return 120;
    } else if (indexPath.section == BI_SECT_HW_TEMP && indexPath.row == 0) {
        return 120;
	} else if (indexPath.section == BI_SECT_BRIGHTNESS && indexPath.row == 0) {
		return 120;
    } else {
        return [super tableView:tv heightForRowAtIndexPath:indexPath];
        // return 30;
    }
}

- (void)updateTableView {
	DBGLOG(@"BIVC: updateTableView");
	[self.refreshControl beginRefreshing];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
	      battery_info_update(&self->batteryInfo);

		dispatch_async(dispatch_get_main_queue(), ^{
	      	[self.tableView reloadData];
			[self.refreshControl endRefreshing];
		});
	});
}

- (void)dealloc {
	for(struct battery_info_section *sect=batteryInfo;sect;) {
		struct battery_info_section *next=sect->next;
		for (struct battery_info_node *i = sect->data; i->name; i++) {
			if (i->content && !(i->content & BIN_IS_SPECIAL)) {
				bi_node_free_string(i);
			}
		}
		bi_destroy_section(sect);
		sect=next;
	}
}

@end
