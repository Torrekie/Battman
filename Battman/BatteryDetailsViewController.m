#import "BatteryDetailsViewController.h"
#import "FullSMCViewController.h"
#import "MultilineViewCell.h"
#import "SegmentedViewCell.h"
#import "WarnAccessoryView.h"
#import "BattmanPrefs.h"
#include "battery_utils/iokit_connection.h"
#include "battery_utils/libsmc.h"
#include "common.h"
#include "intlextern.h"

#import "ObjCExt/UIColor+compat.h"

#import <CoreText/CoreText.h>
#include <sys/sysctl.h>

/* Desc */
@interface BatteryDetailsViewController () {
	hvc_menu_t *hvc_menu;
	int8_t      hvc_index;
	size_t      hvc_menu_size;
	bool        hvc_soft;
}
@end

UILabel *equipCellTitle(UITableViewCell *cell, NSString *text) {
    // textLabel always exist
    cell.textLabel.text = text;
    if ([cell respondsToSelector:@selector(titleLabel)]) {
        // Suppress compiler warning about performSelector leak
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		UILabel *title = [cell performSelector:@selector(titleLabel)];
#pragma clang diagnostic pop

		if ([title isKindOfClass:[UILabel class]]) {
			title.text = text;
		}
		return title;
	}

	return cell.textLabel;
}

void equipCellHighLegit(UILabel *label) {
	CTFontDescriptorRef desc = CTFontDescriptorCreateCopyWithFeature((__bridge CTFontDescriptorRef)label.font.fontDescriptor, (__bridge CFNumberRef)@(kStylisticAlternativesType), (__bridge CFNumberRef)@(kStylisticAltSixOnSelector));
	CTFontRef font = CTFontCreateWithFontDescriptor(desc, label.font.pointSize, NULL);
	[label setFont:(__bridge UIFont *)font];

	if (desc) CFRelease(desc);
	if (font) CFRelease(font);
}

void equipDetailCell(UITableViewCell *cell, struct battery_info_node *i) {
	// PLEASE ENSURE no hidden cell is here when calling
	/*if ((i->content & BIN_DETAILS_SHARED) == BIN_DETAILS_SHARED ||
	    (i->content &&
	    !((i->content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL))) {
	    cell.hidden = NO;
	} else {
	    cell.hidden = YES;
	    return cell;
	}
	if (((i->content & 1) == 1) && (i->content & (1 << 5)) == (1 << 5)) {
	    cell.hidden = YES;
	    return cell;
	}*/
	NSString *final_str;
	equipCellTitle(cell, _(i->name));
	if (i->desc) {
		// DBGLOG(@"Accessory %@, Desc %@", cell.textLabel.text, components[1]);
		if (@available(iOS 13.0, *)) {
			cell.accessoryType = UITableViewCellAccessoryDetailButton;
		} else {
			WarnAccessoryView *button = [WarnAccessoryView altAccessoryView];
			[cell setAccessoryType:UITableViewCellAccessoryNone];
			[cell setAccessoryView:button];
		}
	} else {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	if ((i->content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL) {
		int16_t value = i->content >> 16;

		if ((i->content & BIN_IS_BOOLEAN) == BIN_IS_BOOLEAN) {
			if (value) {
				final_str = _("True");
			} else {
				final_str = _("False");
			}
		} else if ((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT) {
			final_str = [NSString stringWithFormat:@"%.4g", bi_node_load_float(i)];
		} else {
			final_str = [NSString stringWithFormat:@"%d", value];
		}
		if (i->content & BIN_HAS_UNIT) {
			uint32_t unit = (i->content & BIN_UNIT_BITMASK) >> 6;
			if (unit == (BIN_UNIT_MIN & BIN_UNIT_BITMASK) >> 6) {
				// Special: Convert minutes to localized timer
				NSDateComponentsFormatter *fmt = [[NSDateComponentsFormatter alloc] init];
				fmt.calendar.locale            = [NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]];
				fmt.allowedUnits               = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
				fmt.unitsStyle                 = NSDateComponentsFormatterUnitsStyleShort;
				fmt.zeroFormattingBehavior     = NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
				final_str                      = [fmt stringFromTimeInterval:value * 60];
			} else {
				final_str                      = [NSString stringWithFormat:@"%@ %@", final_str, _(bin_unit_strings[unit])];
			}
		}
	} else {
		final_str = [NSString stringWithUTF8String:bi_node_get_string(i)];
	}
	cell.detailTextLabel.text = final_str;

	// Consider add a "BIN_IS_HIGHLEGIT"
	if (strstr(i->name, "No.") || strstr(i->name, "ID")) {
		equipCellHighLegit(cell.detailTextLabel);
	}

	cell.detailTextLabel.textColor = [UIColor compatSecondaryLabelColor];

	return;
}

typedef enum {
	WARN_NONE,     // OK
	WARN_GENERAL,  // General warning
	WARN_UNUSUAL,  // Unusual value warning (including unusual exceeds)
	WARN_EXCEEDED, // Exceeded value warning
	WARN_EMPTYVAL, // Empty value warning
	WARN_MAX,      // max count of warn, should always be at bottom
} warn_condition_t;

/* TODO: Allow Warnings on other sections */
void equipWarningCondition_b(UITableViewCell *equippedCell, NSString *textLabel, warn_condition_t (^condition)(const char **warn)) {
	if (!equippedCell.textLabel.text) {
		DBGLOG(@"equipWarningCondition() called too early");
		return;
	}
	if (condition == nil)
		return;
	if (![equippedCell.textLabel.text isEqualToString:textLabel])
		return;

	UITableViewCellAccessoryType oldType  = [equippedCell accessoryType];
	const char                  *warnText = nil;
	warn_condition_t             number   = condition(&warnText);
	if (number == WARN_NONE) {
		[equippedCell setAccessoryType:oldType];
		[equippedCell setAccessoryView:nil];
		return; // Do nothing when condition is normal
	} else {
		WarnAccessoryView *button = [WarnAccessoryView warnAccessoryView];
		[equippedCell setAccessoryType:UITableViewCellAccessoryNone];
		[equippedCell setAccessoryView:button];
		equippedCell.detailTextLabel.textColor = [UIColor compatRedColor];

		if (warnText == NULL) {
			switch (number) {
			case WARN_EMPTYVAL:
				warnText = _C("No value returned from sensor, device should be checked by service technician.");
				break;
			case WARN_EXCEEDED:
				warnText = _C("Value exceeded the designed, device should be checked by service technician.");
				break;
			case WARN_UNUSUAL:
				warnText = _C("Unusual value, device should be checked by service technician.");
				break;
			case WARN_GENERAL:
			default:
				warnText = _C("Significant abnormal data, device should be checked by service technician.");
				break;
			}
		}
		button.warn_content = warnText;
		const char *title;
		switch (number) {
		case WARN_GENERAL:
			title = _C("Error Data");
			break;
		case WARN_UNUSUAL:
			title = _C("Unusual Data");
			break;
		case WARN_EXCEEDED:
			title = _C("Data Too Large");
			break;
		case WARN_EMPTYVAL:
			title = _C("Empty Data");
			break;
		default:
			title = _C("Wrong Data");
			break;
		}
		button.warn_title = title;
	}
}

@implementation BatteryDetailsViewController

- (NSString *)title {
	return _("Internal Battery");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Update refresh mode based on current preferences
	BSVCRefreshModeDidUpdate(self);
	// Defer battery update to avoid blocking main thread during view transition
	dispatch_async(dispatch_get_main_queue(), ^{
		[self updateTableView];
	});
}

- (void)refreshModeDidUpdate {
	// Called when preferences change
	BSVCRefreshModeDidUpdate(self);
}

- (void)batteryStatusDidUpdate:(NSDictionary *)info {
	// Check refresh preferences - only update if in auto mode (0) or manual refresh
	float interval = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_BI_INTERVAL];
	if (interval == -1.0f) {
		// Never mode - don't update automatically
		return;
	}
	
	// Only update in auto mode - in timer mode, the timer handles updates directly
	if (interval == 0.0f) {
		// TODO: reimplement IOKit method to update battery info
		DBGLOG(@"BDVC: batteryStatusDidUpdate");
		[self updateTableView];
	}
#if 0
	BOOL charging = [info[@"AppleRawExternalConnected"] boolValue];
	if(charging != last_charging) {
		last_charging = charging;
		[self updateTableView];
		return;
	}
	battery_info_update_iokit_with_data(batteryInfoStruct, (__bridge CFDictionaryRef)info, 1);
	[self.tableView reloadData];
	// DO NOT CALL updateTableView
#endif
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIRefreshControl *puller = [[UIRefreshControl alloc] init];
	[puller addTarget:self action:@selector(updateTableView) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = puller;

	// FIXME: use preferred_language() for "Copy"
	[[UIMenuController sharedMenuController] update];

	[self.tableView registerClass:[SegmentedHVCViewCell class] forCellReuseIdentifier:@"HVC"];
	[self.tableView registerClass:[SegmentedFlagViewCell class] forCellReuseIdentifier:@"FLAGS"];
	[self.tableView registerClass:[MultilineViewCell class] forCellReuseIdentifier:@"bdvc:addt"];
	self.tableView.estimatedRowHeight = 100;
	self.tableView.rowHeight          = UITableViewAutomaticDimension;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	return action == @selector(copy:);
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	if (action == @selector(copy:)) {
		UIPasteboard    *pasteboard;
		NSString        *pending;
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		pending               = cell.detailTextLabel.text;

		pasteboard = [UIPasteboard generalPasteboard];
		[pasteboard setString:pending];

		show_alert(_C("Copied!"), [pending UTF8String], L_OK);
	}
}

- (void)showAdvanced {
	[self.navigationController pushViewController:[FullSMCViewController new] animated:1];
}

- (instancetype)initWithBatteryInfo:(struct battery_info_section **)bi {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}

	self.tableView.allowsSelection = YES;
	battery_info_update(bi);
	batteryInfo = bi;
	for (int i = 0; i < BI_MAX_SECTION_NUM; i++)
		pendingLoadOffsets[i] = malloc(BI_APPROX_ROWS);
	if (!hasSMC)
		return self;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_("Advanced") style:UIBarButtonItemStylePlain target:self action:@selector(showAdvanced)];

	return self;
}

- (void)dealloc {
	//int section_num = battery_info_get_section_count(*batteryInfo);
	for (int i = 0; i < BI_MAX_SECTION_NUM; i++)
		free(pendingLoadOffsets[i]);
}

- (void)updateTableView {
	DBGLOG(@"BDVC: updateTableView");
	[self.refreshControl beginRefreshing];
	
	// Move heavy SMC operations to background queue to avoid blocking main thread
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		battery_info_update(self->batteryInfo);

		// Update UI on main thread
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.tableView reloadData];
			[self.refreshControl endRefreshing];
		});
	});
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

	//NSArray         *target_desc;
	NSString        *titleLabel;
	if ([cell respondsToSelector:@selector(titleLabel)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		UILabel *title = [cell performSelector:@selector(titleLabel)];
#pragma clang diagnostic pop

		if ([title isKindOfClass:[UILabel class]]) {
			titleLabel = title.text;
		}
	} else {
		titleLabel = cell.textLabel.text;
	}

	show_alert([titleLabel UTF8String], _C(battery_info_get_section(*batteryInfo, (int)indexPath.section)->data[indexPath.row + pendingLoadOffsets[indexPath.section][indexPath.row]].desc), L_OK);
	return;
	// TODO: Implement this
#if 0
    NSUInteger index = [target_desc indexOfObject:cell.textLabel.text];
    if (index != NSNotFound) {
        /* Special case: External */
        if ([cell.textLabel.text isEqualToString:_("Type")]) {
            NSString *finalstr = [target_desc objectAtIndex:(index + 1)];
            NSString *explaination_Ext = ((adapter_family & 0x20000) && (adapter_family & 0x7)) ? [NSString stringWithFormat:@"\n\n%@", _("\"External Power\" indicator may suggest that the connected adapter is a wireless charger. Most information may not be displayed because wireless chargers are handled differently by the hardware.")] : @"";
            show_alert([cell.textLabel.text UTF8String], [[NSString stringWithFormat:@"%@%@", finalstr, explaination_Ext] UTF8String], L_OK);
        } else {
            show_alert([cell.textLabel.text UTF8String], [[target_desc objectAtIndex:(index + 1)] UTF8String], L_OK);
        }
    }
    DBGLOG(@"Accessory Pressed, %@", cell.textLabel.text);
#endif
}

- (void)altAccTapped:(UIButton *)button {
	UIView          *view = button;
	UITableViewCell *cell;

	UITableView     *tv;
	NSIndexPath     *ip;
	while (view && ![view isKindOfClass:[UITableViewCell class]]) {
		view = [view superview];
	}
	if (view) {
		cell       = (UITableViewCell *)view;
		UIView *tb = view;
		while (tb && ![tb isKindOfClass:[UITableView class]]) {
			tb = [tb superview];
		}
		if (tb) {
			tv = (UITableView *)tb;
			ip = [tv indexPathForCell:cell];
			return [self tableView:tv accessoryButtonTappedForRowWithIndexPath:ip];
		}
	}
	DBGLOG(@"altAccTapped: Something goes wrong! view: %@, cell: %@, table: %@", view, cell, tv);
}

- (NSString *)tableView:(id)tv titleForHeaderInSection:(NSInteger)section {
	// if (batteryInfo[section][-1].content & (1 << 5))
	//     return nil;
	//  Doesn't matter, it will be changed by willDisplayHeaderView
	return @"This is a Title yeah";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
	header.textLabel.text               = _(battery_info_get_section(*batteryInfo, section)->data[0].name);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	struct battery_info_section *cur = battery_info_get_section(*batteryInfo, section);
	return cur->data[0].desc ? _(cur->data[0].desc) : nil;
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
	struct battery_info_section *sect = battery_info_get_section(*batteryInfo, section);
	int                          rows = 0;
	for (struct battery_info_node *i = sect->data + 1; i->name /*&& (i->content & BIN_SECTION) != BIN_SECTION*/; i++) {
		if ((i->content & BIN_DETAILS_SHARED) == BIN_DETAILS_SHARED || (i->content && !((i->content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL))) {
			if ((i->content & 1) != 1 || (i->content & (1 << 5)) != 1 << 5) {
				pendingLoadOffsets[section][rows] = (unsigned char)((i - sect->data) - rows);
				rows++;
			}
		}
	}
	pendingLoadOffsets[section][rows] = 255;
	return rows;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return battery_info_get_section_count(*batteryInfo);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	NSString *ident      = @"bdvc:sect0";
	id        cell_class = [UITableViewCell class];
	if (ip.section != 0) {
		ident      = @"bdvc:addt";
		cell_class = [MultilineViewCell class];
	}
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:ident];
	if (cell) {
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = nil;
		cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	} else {
		cell = [[cell_class alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
	}
	
	struct battery_info_section *bi_section = battery_info_get_section(*batteryInfo, ip.section);
	struct battery_info_node    *pending_bi = bi_section->data + ip.row + pendingLoadOffsets[ip.section][ip.row];
	/* Flags special handler */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstring-compare"
	// ^ We are comparing the pointers, not string contents.
	if (pending_bi->name == "Flags") {
		SegmentedFlagViewCell *cellf = [tv dequeueReusableCellWithIdentifier:@"FLAGS"];
		if (!cellf)
			cellf = [[SegmentedFlagViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"FLAGS"];

		cellf.textLabel.text       = _(pending_bi->name);
		cellf.titleLabel.text      = _(pending_bi->name);
		cellf.detailTextLabel.text = _(bi_node_get_string(pending_bi));
		[cellf selectByFlags:gGauge.Flags];
		if (strlen(gGauge.DeviceName)) {
			[cellf setBitSetByModel:[NSString stringWithFormat:@"%s", gGauge.DeviceName]];
		} else {
			[cellf setBitSetByTargetName];
		}
		return cellf;
	}
#pragma clang diagnostic pop

#pragma mark - Warn Conditions
	equipDetailCell(cell, pending_bi);
	
	// Workaround for too-long texts in section 0
	if (ip.section == 0 && cell.detailTextLabel.text.length > 25) {
		cell.detailTextLabel.numberOfLines = 0;
		cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	}
	/* Warning conditions */
	if (bi_section->context->custom_identifier == BI_GAS_GAUGE_SECTION_ID) {
		equipWarningCondition_b(cell, _("Remaining Capacity"), ^warn_condition_t(const char **str) {
			warn_condition_t code = WARN_NONE;
			uint16_t         remain_cap, full_cap, design_cap;
			get_capacity(&remain_cap, &full_cap, &design_cap);
			if (remain_cap > full_cap) {
				code = WARN_UNUSUAL;
				static char errmsg[256];
				// some Shenzhen battries is spoofing this data to affect internal battery health calculations
				// But they still had to report a real SoC so that indicating actual conditions.
				sprintf(errmsg, "%s\n%s: %ld", _C("Unusual Remaining Capacity, a non-genuine battery component may be in use."), _C("Estimated Remaining"), lrintf((float)full_cap * gGauge.StateOfCharge / 100.0f));
				*str = errmsg;
			} else if (remain_cap == 0) {
				code = WARN_EMPTYVAL;
				*str = _C("Remaining Capacity not detected.");
			}
			return code;
		});
		equipWarningCondition_b(cell, _("Cycle Count"), ^warn_condition_t(const char **str) {
			warn_condition_t code = WARN_NONE;
			int              count, design;
			count  = gGauge.CycleCount;
			design = gGauge.DesignCycleCount;

			if (gGauge.DesignCycleCount == 0) {
				// according to https://www.apple.com/batteries/service-and-recycling
				// Pre-iPhone15,3: 500, otherwise 1000
				// Watch*,* iPad*,*: 1000
				// iPod*,*: 400
				// MacBook**,*: 1000
				// AppleTV/Watch/AudioAccessory has no battery so ignored
				size_t size = 0;
				char   machine[256];
				// Do not use uname()
				if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0) {
					DBGLOG(@"sysctlbyname(hw.machine) failed");
					return code;
				}
				if (sysctlbyname("hw.machine", &machine, &size, NULL, 0) != 0) {
					DBGLOG(@"sysctlbyname(&machine) failed");
					return code;
				}
				if (match_regex(machine,
				        "^(iPhone|iPad|iPod|MacBook.*)[0-9]+,[0-9]+$")) {
					if (strncmp(machine, "iPhone", 6) == 0) {
						int major = 0, minor = 0;
						if (sscanf(machine + 6, "%d,%d", &major, &minor) != 2) {
							DBGLOG(@"Unexpected iPhone model: %s", machine);
							return code;
						}
						if (major < 15 || (major == 15 && minor < 4)) {
							design = 500;
						} else {
							design = 1000;
						}
					} else if (strncmp(machine, "iPad", 4) || strncmp(machine, "Watch", 5) || strncmp(machine, "MacBook", 7))
						design = 1000;
					else if (strncmp(machine, "iPod", 4))
						design = 400;
				}
				if (design == 0)
					return code;
			}
			if (count > design) {
				code = WARN_EXCEEDED;
				*str = _C("Cycle Count exceeded designed cycle count, consider replacing with a genuine battery.");
			}
			return code;
		});
		equipWarningCondition_b(cell, _("Time to Empty"), ^warn_condition_t(const char **str) {
			warn_condition_t code = WARN_NONE;
			uint16_t         remain_cap, full_cap, design_cap;
			int              tte = get_time_to_empty();
			get_capacity(&remain_cap, &full_cap, &design_cap);
			/* The most ideal TTE is TTE (Hour) = Capacity (mAh) / Current (mA),
			 * some user reported their non-genuine battries
			 * reporting a significant huge number of TTE */

			/* Battery charging, skip */
			if (gGauge.AverageCurrent > 0)
				return code;

			int ideal = (remain_cap / abs(gGauge.AverageCurrent)) * 60;
			/* Normally, TI's GG IC would not emulate its TTE bigger than ideal */
			/* for ensurence, we check if TTE is bigger than 1.5*ideal */
			if (tte > (ideal * 1.5)) {
				code = WARN_UNUSUAL;
				*str = _C("Unusual Time to Empty, a non-genuine battery component may be in use.");
			}
			return code;
		});
		equipWarningCondition_b(cell, _("Depth of Discharge"), ^warn_condition_t(const char **str) {
			warn_condition_t code = WARN_NONE;
			/* Non-genuine batteries are likely spoofing some unremarkable data */
			/* DOD0 is not going to bigger than Qmax normally, but sometimes it do
			 * exceeds when discharging/charging with adapter attached */
			if (gGauge.DOD0 > (gGauge.Qmax * 3)) {
				code = WARN_UNUSUAL;
				*str = _C("Unusual Depth of Discharge, a non-genuine battery component may be in use.");
			}
			return code;
		});
	}

	WarnAccessoryView *button = (WarnAccessoryView *)[cell accessoryView];
	if (button != nil && [button isKindOfClass:[WarnAccessoryView class]]) {
		if (button.isWarn) {
			[button addTarget:self action:@selector(warnTapped:) forControlEvents:UIControlEventTouchUpInside];
		} else {
			[button addTarget:self action:@selector(altAccTapped:) forControlEvents:UIControlEventTouchUpInside];
		}
	}
	/* TODO: record 1st-read capacity data in defaults in order to observe battery problems */
	/* HVC Mode special handler */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wstring-compare"
	if (pending_bi->name == "HVC Mode") {
#pragma clang diagnostic pop
		device_info_t adapter_info;
		is_charging(NULL, &adapter_info);
		/* Parse HVC Modes if have any */
		if (adapter_info.hvc_menu[27] != 0xFF) {
#ifdef DEBUG
			NSString *bits = [[NSString alloc] init];
			for (int i = 0; i < 27; i++) {
				[bits stringByAppendingFormat:@"%x ", adapter_info.hvc_menu[i]];
			}
			DBGLOG(@"HVC Menu Bits: %@", bits);
#endif
			hvc_menu  = hvc_menu_parse(adapter_info.hvc_menu, &hvc_menu_size);
			hvc_index = adapter_info.hvc_index;
			hvc_soft  = false;
		} else {
			hvc_soft = true;
			/* Avoid IOKit includes, we only use this one */
			extern CFDictionaryRef IOPSCopyExternalPowerAdapterDetails(void);
			hvc_menu = convert_hvc(IOPSCopyExternalPowerAdapterDetails(), &hvc_menu_size, &hvc_index);
		}
#if TARGET_OS_SIMULATOR
		/* Simulator builds cannot use IOPSCopyExternalPowerAdapterDetails() */
		/* We fake some hvc to test the UI instead */
		static hvc_menu_t fake_hvc[2];
		memset(fake_hvc, 0, sizeof(fake_hvc));
		fake_hvc[0].voltage = 114;
		fake_hvc[0].current = 514;
		fake_hvc[1].voltage = 1919;
		fake_hvc[1].current = 810;
		hvc_index           = 1;
		hvc_menu            = fake_hvc;
		hvc_menu_size       = 2;
#endif

		/* Only use SegmentedHVCViewCell when HVC exists */
		if (hvc_menu != NULL && hvc_menu_size != 0) {
			SegmentedHVCViewCell *cell_seg = [tv dequeueReusableCellWithIdentifier:@"HVC"];
			if (!cell_seg)
				cell_seg = [[SegmentedHVCViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"HVC"];
			if (@available(iOS 13.0, *)) {
				cell_seg.accessoryType = UITableViewCellAccessoryDetailButton;
			} else {
				WarnAccessoryView *button = [WarnAccessoryView altAccessoryView];
				[cell setAccessoryType:UITableViewCellAccessoryNone];
				[cell setAccessoryView:button];
				[button addTarget:self action:@selector(altAccTapped:) forControlEvents:UIControlEventTouchUpInside];
			}

			cell_seg.textLabel.text  = cell.textLabel.text; // For Accessory selection
			cell_seg.titleLabel.text = cell.textLabel.text;
			[cell_seg.segmentedControl addTarget:self action:@selector(hvcSegmentSelected:) forControlEvents:UIControlEventValueChanged];

			/* We have kept one sample seg to keep UI existence */
			// [cell_seg.segmentedControl setTitle:@"0" forSegmentAtIndex:0];
			[cell_seg.segmentedControl removeAllSegments];
			for (int i = 0; i < hvc_menu_size; i++) {
				[cell_seg.segmentedControl insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:YES];
			}

			/* Content */
			if (!hvc_soft && (hvc_index > hvc_menu_size)) {
				cell_seg.detailTextLabel.text    = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Not HVC")];
				cell_seg.subTitleLabel.text  = @" ";
				cell_seg.subDetailLabel.text = @" ";
			} else if (hvc_soft == true) {
				cell_seg.detailTextLabel.text = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Software Controlled")];
				[cell_seg.segmentedControl setSelectedSegmentIndex:hvc_index];
				/* Why its not refreshing label after setSelectedSegmentIndex? */
				cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].voltage, L_MV];
				cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].current, L_MA];
			} else if (hvc_index == -1) {
				cell_seg.detailTextLabel.text    = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Unavailable")];
				cell_seg.subTitleLabel.text  = @" ";
				cell_seg.subDetailLabel.text = @" ";
			} else {
				cell_seg.detailTextLabel.text = [NSString stringWithFormat:@"%d", hvc_index];
				[cell_seg.segmentedControl setSelectedSegmentIndex:hvc_index];
				/* Why its not refreshing label after setSelectedSegmentIndex? */
				cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].voltage, L_MV];
				cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].current, L_MA];
			}

			return cell_seg;
		} else {
			cell.detailTextLabel.text = _("None");
		}
	}
	//        [cell layoutIfNeeded];
	return cell;
}

- (void)hvcSegmentSelected:(UISegmentedControl *)segment {
	UIView *view = segment;
	while (view && ![view isKindOfClass:[SegmentedHVCViewCell class]]) {
		view = [view superview];
	}
	if (view) {
		SegmentedHVCViewCell *cell_seg  = (SegmentedHVCViewCell *)view;
		// Now update the cell's title
		cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[segment.selectedSegmentIndex].voltage, L_MV];
		cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[segment.selectedSegmentIndex].current, L_MA];
		return;
	}

	DBGLOG(@"FIXME: hvcSegmentSelected without cell view!");
}

- (void)warnTapped:(WarnAccessoryView *)button {
	show_alert(button.warn_title, button.warn_content, L_OK);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	struct battery_info_section *bi_section = battery_info_get_section(*batteryInfo, indexPath.section);
	struct battery_info_node    *pending_bi = bi_section->data + indexPath.row + pendingLoadOffsets[indexPath.section][indexPath.row];
	if(!(pending_bi->content&BIN_HAS_SUBCELLS))
		return;
	int rows=0;
	int is_hidden=0;
	NSMutableArray *indexPaths=[NSMutableArray array];
	for(struct battery_info_node *node=pending_bi+1;node->name&&(node->content&BIN_IS_SUBCELL);node++) {
		if(node->content&(1<<5))
			is_hidden=1;
		node->content^=(1<<5);
		rows++;
		[indexPaths addObject:[NSIndexPath indexPathForRow:indexPath.row+rows inSection:indexPath.section]];
	}
	if(!rows)
		return;
	if(is_hidden) {
		[tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
	}else{
		[tableView deleteRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationAutomatic];
	}
	//[self updateTableView];
}

@end
