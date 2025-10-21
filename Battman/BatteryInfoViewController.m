#import "ObjCExt/UIScreen+Auto.h"

#import "BatteryInfoViewController.h"
#import "BatteryCellView/BatteryInfoTableViewCell.h"
#import "BatteryCellView/TemperatureInfoTableViewCell.h"
#import "BatteryDetailsViewController.h"
#import "ChargingManagementViewController.h"
#import "ChargingLimitViewController.h"
#import "ThermalTunesViewContoller.h"
#include "battery_utils/battery_utils.h"
#import "SimpleTemperatureViewController.h"
#import "BrightnessInfoTableViewCell.h"
#import "UPSMonitor.h"
#import "BattmanPrefs.h"

#include "common.h"
#include "intlextern.h"

// Privates
@interface CALayer ()
@property (atomic, assign) BOOL continuousCorners;
@end

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
	NSString   *size   = [NSString stringWithFormat:@"BattmanIcons@%dx", [UIScreen autoScreen].scale < 3.0 ? 2 : 3];
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
#if ENABLE_BRIGHTNESS
	BI_SECT_BRIGHTNESS,
#endif
	BI_SECT_MANAGE,
	BI_SECT_COUNT
};

@implementation BatteryInfoViewController

- (NSString *)title {
    return _("Battman");
}

- (void)batteryStatusDidUpdate:(NSDictionary *)info {
	battery_info_update(&batteryInfo);
	//battery_info_update_iokit_with_data(batteryInfo,(__bridge CFDictionaryRef)info,0);
	[super batteryStatusDidUpdate];
}

- (void)viewDidLoad {
    [super viewDidLoad];

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

	copyright.font = [UIFont systemFontOfSize:12];
    copyright.textAlignment = NSTextAlignmentCenter;
    copyright.textColor = [UIColor grayColor];
    [copyright sizeToFit];
    self.tableView.tableFooterView = copyright;
}

- (instancetype)init {
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
    battery_info_init(&batteryInfo);
	[UPSMonitor startWatchingUPS];

	_loadAppSupportBundle();
	if (@available(iOS 13.0, *))
		return [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		return [super initWithStyle:UITableViewStyleGrouped];
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
	switch(sect) {
        case BI_SECT_BATTERY_INFO:
            return _("Battery Info");
        case BI_SECT_HW_TEMP:
            return _("Hardware Temperature");
#if ENABLE_BRIGHTNESS
		case BI_SECT_BRIGHTNESS:
			return _("Brightness");
#endif
        case BI_SECT_MANAGE:
            return _("Manage");
        default:
            return nil;
	};
}

- (NSString *)tableView:(id)tv titleForFooterInSection:(NSInteger)section {
    return nil;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == BI_SECT_BATTERY_INFO)
        [self.navigationController pushViewController:[[BatteryDetailsViewController alloc] initWithBatteryInfo:&batteryInfo] animated:YES];
	else if (indexPath.section == BI_SECT_HW_TEMP)
		[self.navigationController pushViewController:[SimpleTemperatureViewController new] animated:YES];
#if ENABLE_BRIGHTNESS
	else if (indexPath.section == BI_SECT_BRIGHTNESS)
		show_alert(_C("Unimplemented Yet"), _C("Will be introduced in future updates."), L_OK);
		//[self.navigationController pushViewController:[BrightnessDetailsViewController new] animated:YES];
#endif
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
    if (indexPath.section == BI_SECT_BATTERY_INFO) {
        BatteryInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"BTTVC-cell"];
        if (!cell)
        	cell = [BatteryInfoTableViewCell new];
        cell.batteryInfo = &batteryInfo;
        // battery_info_update shall be called within cell impl.
        [cell updateBatteryInfo];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    } else if (indexPath.section == BI_SECT_HW_TEMP) {
        TemperatureInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"TITVC-ri"];
        if (!cell)
        	cell = [TemperatureInfoTableViewCell new];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
#if ENABLE_BRIGHTNESS
	} else if (indexPath.section == BI_SECT_BRIGHTNESS) {
		BrightnessInfoTableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"BITVC-ri"];
		if (!cell)
			cell = [BrightnessInfoTableViewCell new];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
#endif
    } else if (indexPath.section == BI_SECT_MANAGE) {
		// XXX: Try make this section "InsetGrouped"
        UITableViewCell *cell = [UITableViewCell new];
		// I want NSConstantArray
		NSArray *rows = @[_("Charging Management"), _("Charging Limit"), _("Thermal Tunes")];
		if (artwork_avail) {
			NSArray *icns = @[@"LowPowerUsage", @"ChargeLimit", @"Thermometer"];
			cell.imageView.image = [UIImage imageWithCGImage:getArtworkImageOf((__bridge CFStringRef)icns[indexPath.row]) scale:[UIScreen autoScreen].scale orientation:UIImageOrientationUp];
		}
		cell.textLabel.text = rows[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	// Smooth corners for icons
	// U think im goin to use the bundle icon huh? No, we are just lookin for default size
	UIImage *tmp = [UIImage _applicationIconImageForBundleIdentifier:[NSBundle.mainBundle bundleIdentifier] format:0 scale:[UIScreen autoScreen].scale];
	if (cell.imageView.image != nil) {
		[cell.imageView.layer setCornerRadius:tmp.size.width * 0.225f];
		if (@available(iOS 13.0, *)) {
			[cell.imageView.layer setCornerCurve:kCACornerCurveContinuous];
		}
		if ([cell.imageView.layer respondsToSelector:@selector(setContinuousCorners:)])
			[cell.imageView.layer setContinuousCorners:YES];
	}
	cell.imageView.clipsToBounds = YES;
}

- (CGFloat)tableView:(id)tv heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	// TODO: reduce redundant
    if (indexPath.section == BI_SECT_BATTERY_INFO && indexPath.row == 0) {
        return 120;
    } else if (indexPath.section == BI_SECT_HW_TEMP && indexPath.row == 0) {
        return 120;
#if ENABLE_BRIGHTNESS
	} else if (indexPath.section == BI_SECT_BRIGHTNESS && indexPath.row == 0) {
		return 120;
#endif
    } else {
        return [super tableView:tv heightForRowAtIndexPath:indexPath];
        // return 30;
    }
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
