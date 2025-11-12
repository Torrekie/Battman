#import "ChargingManagementViewController.h"
#import "DatePickerTableViewCell.h"
#import "SliderTableViewCell.h"
#include "battery_utils/libsmc.h"
#include "common.h"
#include "intlextern.h"

#import "ObjCExt/UIColor+compat.h"

#include <notify.h>

enum sections_cl {
	CM_SECT_GENERAL,
	CM_SECT_SMART_CHARGING,
	CM_SECT_LOW_POWER_MODE,
	CM_SECT_COUNT
};

extern uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen);
extern void battman_worker_oneshot(char cmd, char arg);

#pragma mark - ViewController

@interface ChargingManagementViewController () <SliderTableViewCellDelegate, DatePickerTableViewCellDelegate>

@end

@implementation ChargingManagementViewController

- (NSString *)title {
	return _("Charging Management");
}

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        self = [super initWithStyle:UITableViewStyleInsetGrouped];
    } else {
        self = [super initWithStyle:UITableViewStyleGrouped];
    }

    if (@available(iOS 15.0, macOS 12.0, *)) {
        batterysaver_notif = "com.apple.powerd.lowpowermode.prefs";
        if (@available(iOS 16.0, macOS 13.0, *)) {
            batterysaver_state = @"com.apple.powerd.lowpowermode.state";
        } else {
            // iOS 15 has not completely migrated to powerd
            // Or mabe we should try both
            batterysaver_state = @"com.apple.coreduetd.batterysaver.state";
        }
        system_lpm_notif = "com.apple.system.lowpowermode";
    } else {
        /* afaik, at least iOS 13 */
        batterysaver = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.coreduetd.batterysaver"];
        batterysaver_notif = "com.apple.coreduetd.batterysaver.prefs";
        batterysaver_state = @"com.apple.coreduetd.batterysaver.state";
        system_lpm_notif = "com.apple.system.batterysavermode";
    }
    if (!springboard)
        springboard = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.springboard"];
	//self.tableView.allowsSelection=NO;

	char  buf[1024];
	daemon_pid = 0;
	char *end = stpcpy(stpcpy(buf, battman_config_dir()), "/daemon");
	strcpy(end, ".run");
	int drfd = open(buf, O_RDONLY);
	if (drfd != -1) {
		int pid;
		if (read(drfd, &pid, 4) == 4) {
			if (kill(pid, 0) == 0 || errno != ESRCH) {
				daemon_pid = pid;
			}
		}
		close(drfd);
	}

	return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"LPM_THR"];
	[self.tableView registerClass:[DatePickerTableViewCell class] forCellReuseIdentifier:@"DATE_PIK"];

	self.tableView.estimatedRowHeight = 500;
	self.tableView.rowHeight          = UITableViewAutomaticDimension;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)sect {
	switch (sect) {
        case CM_SECT_GENERAL:
            return _("General");
        case CM_SECT_SMART_CHARGING:
            return _("Smart Charging");
        case CM_SECT_LOW_POWER_MODE:
            return _("Low Power Mode");
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)sect {
    if (sect == CM_SECT_GENERAL) {
		if (daemon_pid)
			return _("These values can’t be overridden when the Charging Limit daemon is running.");
		BOOL obc = NO;
		smc_read_n('CH0C', &obc, 1);
		if (!obc)
			smc_read_n('CH0I', &obc, 1);
		return [NSString stringWithFormat:_("Block Charging suspends battery charging and allows the battery to discharge while maintaining power source operation. %@"), obc ? _("Certain values may not be overridable when Optimized Battery Charging is enabled.") : @""];
    } else if (sect == CM_SECT_SMART_CHARGING) {
		return _("Smart Charging will start 900 seconds (15 minutes) after power is plugged-in, or the date you scheduled, whichever one comes first.");
    } else if (sect == CM_SECT_LOW_POWER_MODE) {
        NSUserDefaults *suite = [[NSUserDefaults alloc] initWithSuiteName:batterysaver_state];

#if USE_MOBILEGESTALT && 0
        /* The problem is, MobileGestalt is returning Apple preferred presets,
         * but not always the real condition of a device.
         */
        void *mobileGestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        if (mobileGestalt) {
            bool (*MGGetBoolAnswer)(CFStringRef) = (bool(*)(CFStringRef))dlsym(mobileGestalt, "MGGetBoolAnswer");
            if (MGGetBoolAnswer)
                lpm_supported = MGGetBoolAnswer(CFSTR("f+PE44W6AO2UENJk3p2s5A"));
            dlclose(mobileGestalt);
        }
#else
        lpm_supported = 1;
        /* TODO: Alternative checks if MobileGestalt is unreliable */
#endif
        if (lpm_supported) {
            NSMutableString *finalStr = [[NSMutableString alloc] init];
            [suite synchronize];

            id date, soc;
            /* State */
            id state = [suite valueForKey:@"state"];
#if 0
            /* The official way is to check this value, but it was not updated
             * instantly, so it may differ than actual condition */
            lpm_on = [state boolValue];
#else
            /* call setLPM with nil button, which only checks for instant LPM */
            [self setLPM:nil];
#endif
            if (state) {
                [finalStr appendString:lpm_on ? _("Enabled") : _("Disabled")];
            } else {
                [finalStr setString:_("Never been used before")];
                goto final;
            }

            /* Date */
            date = [suite objectForKey:@"stateChangeDate"];
            if (date) {
                NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                fmt.locale = [NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]];
//                fmt.locale = [NSLocale currentLocale];
                [fmt setLocalizedDateFormatFromTemplate:@"MMM ddHH:mm:ss"];
                NSString *strfmt = [NSString stringWithFormat:_(" since %@"), [fmt stringFromDate:date]];
                [finalStr appendString:strfmt];
            }

            /* at SoC */
            soc = [suite valueForKey:@"stateBatteryCharge"];
            if (soc) {
                double value = [soc doubleValue];
                NSString *strfmt = [NSString stringWithFormat:_(" at %d%% charge"), (unsigned int)(int)value];
                [finalStr appendString:strfmt];
            }
final:
            [finalStr appendFormat:@"\n%@", _("These settings are retained across iTunes backups and restores.")];
            return finalStr;
        } else {
            return _("Not supported on this device");
        }
    }
	return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sect {
	switch (sect) {
        case CM_SECT_GENERAL:
            return 2;
        case CM_SECT_SMART_CHARGING:
            return 3;
        case CM_SECT_LOW_POWER_MODE:
            return 5;
        default:
            return 1;
    }
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return CM_SECT_COUNT;
}

#pragma mark - Switches

- (void)setBlockCharging:(UISwitch *)cswitch {
	BOOL val = cswitch.on;
    /* FIXME: kIOReturnNotPrivileged */
	int ret = smc_write_safe('CH0C', &val, 1);
    if (ret)
    	show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
    int new_val;
	smc_read_n('CH0C', &new_val, 1);
    DBGLOG(@"setBlockCharging: set: %d, new: %d", val, new_val & 0xFF);
	new_val &= 0xFF;
	if ((new_val != 0) != val) {
		cswitch.on = (new_val != 0);
	}
}

- (void)setBlockPower:(UISwitch *)cswitch {
    BOOL val = cswitch.on;
    /* FIXME: kIOReturnNotPrivileged */
    int ret = smc_write_safe('CH0I', &val, 1);
    if (ret)
    	show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
    int new_val;
    smc_read_n('CH0I', &new_val, 1);
    DBGLOG(@"setBlockPower: set: %d, new: %d", val, new_val & 0xFF);
    new_val &= 0xFF;
    if ((new_val != 0) != val) {
        cswitch.on = (new_val != 0);
    }
}

- (void)setLPM:(UISwitch *)cswitch {
    NSError *err = nil;
    NSString *bundle_name = nil;
    if (@available(iOS 16.0, macOS 13.0, *)) {
        bundle_name = @"LowPowerMode.framework";
    } else {
        bundle_name = @"CoreDuet.framework";
    }

    NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@", bundle_name]];
    if (![bundle loadAndReturnError:&err]) {
        NSString *errorMessage = [NSString stringWithFormat:@"%@ %@\n\n%s: %@", _("Failed to load"), bundle_name, L_ERR, [err localizedDescription]];
        show_alert(L_FAILED, [errorMessage UTF8String], L_OK);
        return;
    }

    BOOL val = NO;
    if (cswitch) {
        val = cswitch.on;
        NSLog(@"%@abling Low Power Mode", val ? @"En" : @"Dis");
    }

    id LPMClass = nil;
    id LPMObject = nil;
    bool get_notif = false;
    if (@available(iOS 16.0, macOS 13.0, *)) {
        get_notif = true;
    } else {
        LPMClass = [bundle classNamed:@"_CDBatterySaver"];
        LPMObject = [LPMClass batterySaver];
        if (@available(iOS 15.0, macOS 12.0, *)) {
            // On iOS 15 we can set LPM by CoreDuet, but cannot get it from.
            get_notif = true;
        } else {
            // We can get LPM state by notify, but I cannot test.
            // Need someone to confirm if it was available for older OS
            lpm_on = [LPMObject getPowerMode] & 1;
        }
    }

    if (get_notif) {
        int token;
        uint64_t state;
        if (notify_register_check(system_lpm_notif, &token) == NOTIFY_STATUS_OK) {
            if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
                lpm_on = state;
            }
            notify_cancel(token);
            DBGLOG(@"LPM is currently %@abled.", lpm_on ? @"en" : @"dis");
        }
    }

    if (cswitch) {
        if (@available(iOS 16.0, macOS 13.0, *)) {
            LPMClass = [bundle classNamed:@"_PMLowPowerMode"];
            LPMObject = [LPMClass sharedInstance];
            [LPMObject setPowerMode:val fromSource:@"com.torrekie.Battman" withCompletion:^(BOOL success, NSError *error) {
                DBGLOG(@"Switching %@ LPM. Success=%d error: %@", val ? @"into" : @"out of", success, error);
                if (success) self->lpm_on = val;
            }];
        } else {
            /* 0 = Normal, 1 = LPM */
            [LPMObject setPowerMode:val error:&err];
            lpm_on = [LPMObject getPowerMode] & 1;
            if (lpm_on != val) {
                NSString *errorMessage = [NSString stringWithFormat:@"%@\n\n%@: %@", _("Unable to set Low Power Mode."), _("Error"), [err localizedDescription]];
                show_alert(L_FAILED, [errorMessage UTF8String], L_OK);
            } else {
                NSLog(@"[batterySaver getPowerMode] = %lld", [LPMObject getPowerMode]);
            }
        }
		/* FIXME: The correct way of setting LPM is set & push com.apple.system.lowpowermode */
        cswitch.on = lpm_on;
    }
}

- (void)setLPMAutoDisable:(UISwitch *)cswitch {
	if (batterysaver) {
		[batterysaver setBool:cswitch.on forKey:@"autoDisableWhenPluggedIn"];
	} else {
		battman_worker_oneshot(1, cswitch.on);
	}
	notify_post(batterysaver_notif);
}

- (void)setAllowThr:(UISwitch *)cswitch {
	if (!cswitch.on) {
		if (batterysaver) {
			[batterysaver removeObjectForKey:@"autoDisableThreshold"];
		} else {
			battman_worker_oneshot(2, 0);
		}
		lpm_thr = 0;
	} else {
		lpm_thr = 80;
		if (batterysaver) {
			[batterysaver setFloat:lpm_thr forKey:@"autoDisableThreshold"];
		} else {
			battman_worker_oneshot(2, 1);
		}
	}
    notify_post(batterysaver_notif);

    /* Find current indexPath, control next row */
    UIView *view = cswitch;
    UITableViewCell *cell;

    UITableView *tv;
    NSIndexPath *ip;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) {
        view = [view superview];
    }
    if (view) {
        cell = (UITableViewCell *)view;
        UIView *tb = view;
        while (tb && ![tb isKindOfClass:[UITableView class]]) {
            tb = [tb superview];
        }
        if (tb) {
            tv = (UITableView *)tb;
            ip = [tv indexPathForCell:cell];
            NSIndexPath *ip_next = [NSIndexPath indexPathForRow:ip.row + 1 inSection:ip.section];
            [self.tableView reloadRowsAtIndexPaths:@[ip_next] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (void)setHideLPMAlerts:(UISwitch *)cswitch {
    BOOL val = cswitch.on;
    if (val) {
        [springboard setBool:val forKey:@"SBHideLowPowerAlerts"];
    } else {
        // Do not keep this entry in settings
        [springboard removeObjectForKey:@"SBHideLowPowerAlerts"];
    }

    [springboard synchronize];

    BOOL new = NO;
    id state = [springboard valueForKey:@"SBHideLowPowerAlerts"];
    if (state)
        new = [state boolValue];

    if (val != new)
        show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
}

#pragma mark - TableView

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == CM_SECT_SMART_CHARGING) {
		if (indexPath.row == 2) {
			NSError *err = nil;
			NSBundle *powerUIBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/PowerUI.framework"];
			if (![powerUIBundle loadAndReturnError:&err]) {
				NSString *errorMessage = [NSString stringWithFormat:@"%@ %@\n\n%s: %@", _("Failed to load"), @"PowerUI.framework", L_ERR, [err localizedDescription]];
				show_alert(L_FAILED, [errorMessage UTF8String], L_OK);
				goto tvend;
			}
			id sccClass = [powerUIBundle classNamed:@"PowerUISmartChargeClient"];
			id sccObject = [[sccClass alloc] initWithClientName:@"ok"];
			if(![sccObject setState:1 error:&err]) {
				NSString *errorMessage = [NSString stringWithFormat:@"%@\n\n%s: %@", _("Failed to enable Smart Charging."), L_ERR, [err localizedDescription]];
				show_alert(L_FAILED, [errorMessage UTF8String], L_OK);
				goto tvend;
			}
			[sccObject engageFrom:fromPicker.date until:untilPicker.date repeatUntil:untilPicker.date overrideAllSignals:1];
			//BOOL yyy=1;
			//smc_write_safe('CH0C', &yyy, 1);
			show_alert(_C("Engaged"), _C("Smart Charging has been engaged. It will start after 15 minutes of power supply, or at the date you picked, whichever comes first."), L_OK);
		}
	}
tvend:
	return [tv deselectRowAtIndexPath:indexPath animated:YES];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == CM_SECT_SMART_CHARGING) {
		if (indexPath.row == 0) {
			if (@available(iOS 13.0, *)) {
				// Nothing
			} else {
				DatePickerTableViewCell *dcell = [tableView cellForRowAtIndexPath:indexPath];
				if (dcell.isExpanded)
					return dcell.button.bounds.size.height + dcell.picker.bounds.size.height;
			}
		}
	}
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [UITableViewCell new];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
    // FIXME: Disable this section when daemon running
    if (indexPath.section == CM_SECT_GENERAL) {
        UISwitch *cswitch = [UISwitch new];
        int switchOn = 0;
        SEL action = nil;
        // TODO: Reduce redundant codes
        if (indexPath.row == 0) {
            cell.textLabel.text = _("Block Charging");
            smc_read_n('CH0C', &switchOn, 1);
            action = @selector(setBlockCharging:);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = _("Block Power Supply");
            smc_read_n('CH0I', &switchOn, 1);
            action = @selector(setBlockPower:);
        }
        [cswitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        cswitch.on = (switchOn & 0xFF) != 0;
        /* 0: disabled, 1: enabled, 2: managed */
        /* while 2, user cannot reset the value */
        cswitch.enabled = !(switchOn & 0x2);
        cell.accessoryView = cswitch;
    } else if (indexPath.section == CM_SECT_SMART_CHARGING) {
		if (indexPath.row == 0) {
			if (@available(iOS 13.4, *)) {
				UIDatePicker *datePicker = [UIDatePicker new];
				// Default behavior determines locale by Region
				[datePicker setLocale:[NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]]];
				datePicker.datePickerMode = UIDatePickerModeDateAndTime;
				datePicker.date = [NSDate now];
				datePicker.minimumDate = datePicker.date;
				datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
				cell.accessoryView = datePicker;
				fromPicker = datePicker;
				cell.textLabel.text = _("Starting at");
			} else {
				DatePickerTableViewCell *dcell = [[DatePickerTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
				[dcell.picker setLocale:[NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]]];
				dcell.picker.datePickerMode = UIDatePickerModeDateAndTime;
				dcell.picker.date = [NSDate date];
				dcell.picker.minimumDate = dcell.picker.date;
				dcell.delegate = self;
				NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
				fmt.calendar.locale = [NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]];
				fmt.dateStyle = NSDateFormatterShortStyle;
				fmt.timeStyle = NSDateFormatterShortStyle;
				[dcell.button setTitle:[fmt stringFromDate:dcell.picker.date] forState:UIControlStateNormal];

				fromPicker = dcell.picker;
				cell = (id)dcell;
				dcell.titleLabel.text = _("Starting at");
			}
		} else if (indexPath.row == 1) {
			if (@available(iOS 13.4, *)) {
				UIDatePicker *datePicker = [UIDatePicker new];
				[datePicker setLocale:[NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]]];
				datePicker.datePickerMode = UIDatePickerModeDateAndTime;
				datePicker.date = [NSDate dateWithTimeIntervalSinceNow:3600 * 5];
				datePicker.minimumDate = [NSDate now];
				datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
				cell.accessoryView = datePicker;
				untilPicker = datePicker;
				cell.textLabel.text = _("Until");
			} else {
				DatePickerTableViewCell *dcell = [[DatePickerTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
				[dcell.picker setLocale:[NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]]];
				dcell.picker.datePickerMode = UIDatePickerModeDateAndTime;
				dcell.picker.date = [NSDate dateWithTimeIntervalSinceNow:3600 * 5];
				dcell.picker.minimumDate = [NSDate date];
				dcell.delegate = self;
				NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
				fmt.calendar.locale = [NSLocale localeWithLocaleIdentifier:[NSString stringWithUTF8String:preferred_language()]];
				fmt.dateStyle = NSDateFormatterShortStyle;
				fmt.timeStyle = NSDateFormatterShortStyle;
				[dcell.button setTitle:[fmt stringFromDate:dcell.picker.date] forState:UIControlStateNormal];
				
				untilPicker = dcell.picker;
				cell = (id)dcell;
				dcell.titleLabel.text = _("Until");
			}
		} else {
			cell.selectionStyle = UITableViewCellSelectionStyleDefault;
			cell.textLabel.text = _("Schedule");
			cell.textLabel.textColor = [UIColor compatLinkColor];
		}
    } else if (indexPath.section == CM_SECT_LOW_POWER_MODE) {
        UISwitch *cswitch = [UISwitch new];
        SEL selector = nil;

        if (indexPath.row == 0) {
            cell.textLabel.text = _("Low Power Mode");
            cswitch.enabled = lpm_supported;
            cswitch.on = lpm_on;
            selector = @selector(setLPM:);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = _("Disable on A/C");
            if (batterysaver) {
                id state = [batterysaver valueForKey:@"autoDisableWhenPluggedIn"];
                if (state)
                    cswitch.on = [state boolValue];
                else
                    cswitch.on = 0;
            } else {
                uint64_t data = battman_worker_call(4, NULL, 0);
                //NSLog(@"data=%llu",data);
                cswitch.on = ((char *)&data)[5];
            }
            selector = @selector(setLPMAutoDisable:);
        } else if (indexPath.row == 2) {
            cell.textLabel.text = _("Disable When Exceeds");
            if (batterysaver) {
                id value = [batterysaver valueForKey:@"autoDisableThreshold"];
                lpm_thr = [value floatValue];
                cswitch.on = (value) ? YES : NO;
            } else {
                uint64_t data = battman_worker_call(4, NULL, 0);
                lpm_thr = *(float *)&data;
                cswitch.on = ((char *)&data)[4];
            }
            selector = @selector(setAllowThr:);
        } else if (indexPath.row == 3) {
            SliderTableViewCell *cell_s = [tv dequeueReusableCellWithIdentifier:@"LPM_THR" forIndexPath:indexPath];
            if (!cell_s)
                cell_s = [[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LPM_THR"];
            
            cell_s.slider.minimumValue = 10.0f;
            cell_s.slider.maximumValue = 100.0f;

            cell_s.slider.enabled = (lpm_thr) ? YES : NO;
            cell_s.textField.enabled = cell_s.slider.enabled;
            cell_s.slider.userInteractionEnabled = cell_s.slider.enabled;
            cell_s.textField.userInteractionEnabled = cell_s.slider.enabled;
            cell_s.userInteractionEnabled = cell_s.slider.enabled;

            cell_s.slider.value = (lpm_thr) ? lpm_thr : 80;
            cell_s.textField.text = (lpm_thr) ? [NSString stringWithFormat:@"%.4g", lpm_thr] : @"80.00";

            /* Set delegate */
            cell_s.delegate = self;
            
            return cell_s;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = _("Hide Low Power Alert");
            id state = [springboard valueForKey:@"SBHideLowPowerAlerts"];
            if (state) cswitch.on = [state boolValue];
            selector = @selector(setHideLPMAlerts:);
        }
        [cswitch addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = cswitch;
    }

    return cell;
}

#pragma mark - SliderTableViewCell Delegate

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
    DBGLOG(@"Slider changed at row %ld: %f", (long) [self.tableView indexPathForCell:cell].row, value);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value {
	if ([cell.reuseIdentifier isEqualToString:@"LPM_THR"]) {
		lpm_thr = value;
		if (batterysaver)
			[batterysaver setFloat:value forKey:@"autoDisableThreshold"];
		else
			battman_worker_call(3, (void *)&value, 4);
		notify_post(batterysaver_notif);
	}
}


#pragma mark - DatePickerTableViewCell Delegate

- (void)datePickerCellDidToggleExpansion:(DatePickerTableViewCell *)cell {
	NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
	if (indexPath) {
		cell.pickerBorder.hidden = !cell.isExpanded;
		[self.tableView beginUpdates];
		[self.tableView endUpdates];
	}
}

@end
