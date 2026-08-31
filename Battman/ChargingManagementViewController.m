#import "ChargingManagementViewController.h"
#import "DatePickerTableViewCell.h"
#import "SliderTableViewCell.h"
#include "battery_utils/libsmc.h"
#include "common.h"
#include "intlextern.h"

#import "ObjCExt/NSBundle+Auto.h"
#import "ObjCExt/UIColor+compat.h"

#include <notify.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>

enum sections_cl {
	CM_SECT_GENERAL,
	CM_SECT_SMART_CHARGING,
	CM_SECT_LOW_POWER_MODE,
	CM_SECT_COUNT
};

extern uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen);
extern void battman_worker_oneshot(char cmd, char arg);

static BOOL CLReadNotifyState(const char *name, BOOL *state) {
	if (!name || !state)
		return NO;
	int token = 0;
	uint64_t value = 0;
	if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return NO;
	int result = notify_get_state(token, &value);
	notify_cancel(token);
	if (result != NOTIFY_STATUS_OK)
		return NO;
	*state = value != 0;
	return YES;
}

static BOOL CLWriteNotifyState(const char *name, BOOL desired, BOOL *actual) {
	if (!name)
		return NO;
	int token = 0;
	if (notify_register_check(name, &token) != NOTIFY_STATUS_OK)
		return NO;
	uint64_t value = desired ? 1 : 0;
	int setResult = notify_set_state(token, value);
	if (setResult == NOTIFY_STATUS_OK)
		setResult = notify_post(name);
	int getResult = (setResult == NOTIFY_STATUS_OK) ? notify_get_state(token, &value) : setResult;
	notify_cancel(token);
	if (setResult != NOTIFY_STATUS_OK || getResult != NOTIFY_STATUS_OK)
		return NO;
	if (actual)
		*actual = value != 0;
	return value == (desired ? 1 : 0);
}

static BOOL CMReadDaemonPID(pid_t *pid_out) {
	if (!pid_out)
		return NO;
	const char *config_dir = battman_config_dir();
	if (!config_dir)
		return NO;
	char path[PATH_MAX];
	int length = snprintf(path, sizeof(path), "%s/daemon.run", config_dir);
	if (length <= 0 || (size_t)length >= sizeof(path))
		return NO;
	int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
	if (fd < 0)
		return NO;
	struct stat st;
	BOOL safe = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) &&
	            st.st_size == (off_t)sizeof(pid_t) && (st.st_mode & 022) == 0;
	pid_t pid = 0;
	ssize_t bytes = safe ? pread(fd, &pid, sizeof(pid), 0) : -1;
	close(fd);
	if (bytes != (ssize_t)sizeof(pid) || pid <= 1)
		return NO;
	if (kill(pid, 0) != 0 && errno != EPERM)
		return NO;
	*pid_out = pid;
	return YES;
}

#pragma mark - ViewController

@interface ChargingManagementViewController () <SliderTableViewCellDelegate, DatePickerTableViewCellDelegate>
- (BOOL)refreshLowPowerModeSupport;
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

	// Only test UI on Simulators
	if (batterysaver == nil && is_simulator()) {
		if (@available(iOS 15.0, macOS 12.0, *))
			batterysaver = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.powerd.lowpowermode"];
		else
			batterysaver = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.coreduetd.batterysaver"];
	}

    if (!springboard)
        springboard = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.springboard"];
	//self.tableView.allowsSelection=NO;

	daemon_pid = 0;
	lpm_request_generation = 0;
	pid_t detected_pid = 0;
	if (CMReadDaemonPID(&detected_pid))
		daemon_pid = (int)detected_pid;
	[self refreshLowPowerModeSupport];

	return self;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	pid_t detected_pid = 0;
	daemon_pid = CMReadDaemonPID(&detected_pid) ? (int)detected_pid : 0;
	[self refreshLowPowerModeSupport];
	[self.tableView reloadData];
}

- (BOOL)refreshLowPowerModeSupport {
	lpm_supported = NO;
	NSBundle *bundle = nil;
	if (@available(iOS 16.0, macOS 13.0, *))
		bundle = [NSBundle systemBundleWithName:@"powerd.LowPowerMode" fallbackExecutable:@"LowPowerMode"];
	else
		bundle = [NSBundle systemBundleWithName:@"CoreDuet"];
	if (!bundle || ![bundle loadAndReturnError:nil]) {
		/* Older systems exposed the notify state even when CoreDuet was not
		 * loadable.  Keep that path available for iOS 12/15 instead of hiding
		 * Low Power Mode solely because the private bundle is absent. */
		if (@available(iOS 16.0, macOS 13.0, *))
			return NO;
		BOOL state = NO;
		if (system_lpm_notif && CLReadNotifyState(system_lpm_notif, &state)) {
			lpm_on = state;
			lpm_supported = YES;
			return YES;
		}
		return NO;
	}

	if (@available(iOS 16.0, macOS 13.0, *)) {
		Class cls = [bundle classNamed:@"_PMLowPowerMode"];
		id object = (cls && [cls respondsToSelector:@selector(sharedInstance)]) ? [cls sharedInstance] : nil;
		if (!object || ![object respondsToSelector:@selector(getPowerMode)] ||
			![object respondsToSelector:@selector(setPowerMode:fromSource:withCompletion:)])
			return NO;
		lpm_on = ((NSInteger)[object getPowerMode] & 1) != 0;
	} else {
		Class cls = [bundle classNamed:@"_CDBatterySaver"];
		id object = (cls && [cls respondsToSelector:@selector(batterySaver)]) ? [cls batterySaver] : nil;
		if (!object || ![object respondsToSelector:@selector(setPowerMode:error:)])
			return NO;
		BOOL state = NO;
		if (system_lpm_notif && CLReadNotifyState(system_lpm_notif, &state))
			lpm_on = state;
		else if ([object respondsToSelector:@selector(getPowerMode)])
			lpm_on = ((NSInteger)[object getPowerMode] & 1) != 0;
		else
			return NO;
	}
	lpm_supported = YES;
	return YES;
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
		if (!hasSMC)
			return _("Charging controls are unavailable because this device does not expose the required power sensor.");
		uint8_t obc = NO;
		BOOL has_pwr = NO;
		smc_read_n('CH0C', &obc, 1);
		if (!(obc & 2))
			smc_read_n('CH0I', &obc, 1);
		smc_read_n('CHCC', &has_pwr, 1);
		if (!has_pwr)
			smc_read_n('CHCE', &has_pwr, 1);

		NSString *append = @"";
		if (!has_pwr)
			append = _("Certain values may not be overridable when no wired A/C connected.");
		else if (obc & 2)
			append = _("Certain values may not be overridable when Optimized Battery Charging is enabled.");
		return [NSString stringWithFormat:_("Block Charging suspends battery charging and allows the battery to discharge while maintaining power source operation. %@"), append];
    } else if (sect == CM_SECT_SMART_CHARGING) {
		return _("Smart Charging will start 900 seconds (15 minutes) after power is plugged-in, or the date you scheduled, whichever one comes first.");
    } else if (sect == CM_SECT_LOW_POWER_MODE) {
        NSUserDefaults *suite = batterysaver_state ? [[NSUserDefaults alloc] initWithSuiteName:batterysaver_state] : nil;
        [self refreshLowPowerModeSupport];
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
	if (daemon_pid) {
		cswitch.on = !cswitch.on;
		show_alert(L_FAILED, _C("These values can’t be overridden when the Charging Limit daemon is running."), L_OK);
		return;
	}
	BOOL val = cswitch.on;
    /* FIXME: kIOReturnNotPrivileged */
	int ret = smc_write_safe('CH0C', &val, 1);
	if (ret) {
		show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
		return;
	}
	uint8_t new_val = 0;
	if (smc_read_n('CH0C', &new_val, 1) != 0) {
		cswitch.on = !val;
		show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
		return;
	}
	DBGLOG(@"setBlockCharging: set: %d, new: %d", val, new_val & 0xFF);
	if ((new_val != 0) != val) {
		cswitch.on = (new_val != 0);
	}
}

- (void)setBlockPower:(UISwitch *)cswitch {
	if (daemon_pid) {
		cswitch.on = !cswitch.on;
		show_alert(L_FAILED, _C("These values can’t be overridden when the Charging Limit daemon is running."), L_OK);
		return;
	}
    BOOL val = cswitch.on;
    /* FIXME: kIOReturnNotPrivileged */
    int ret = smc_write_safe('CH0I', &val, 1);
	if (ret) {
    	show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
		return;
	}
	uint8_t new_val = 0;
	if (smc_read_n('CH0I', &new_val, 1) != 0) {
		cswitch.on = !val;
		show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
		return;
	}
    DBGLOG(@"setBlockPower: set: %d, new: %d", val, new_val & 0xFF);
    if ((new_val != 0) != val) {
        cswitch.on = (new_val != 0);
    }
}

- (void)setLPM:(UISwitch *)cswitch {
	BOOL requested = cswitch ? cswitch.on : lpm_on;
	if (![self refreshLowPowerModeSupport]) {
		if (cswitch) {
			cswitch.on = lpm_on;
			show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
		}
		return;
	}
	if (!cswitch)
		return;

	NSBundle *bundle = nil;
	if (@available(iOS 16.0, macOS 13.0, *))
		bundle = [NSBundle systemBundleWithName:@"powerd.LowPowerMode" fallbackExecutable:@"LowPowerMode"];
	else
		bundle = [NSBundle systemBundleWithName:@"CoreDuet"];
	NSError *error = nil;
	id object = nil;
	BOOL bundleLoaded = bundle && [bundle loadAndReturnError:nil];
	if (!bundleLoaded) {
		if (@available(iOS 16.0, macOS 13.0, *)) {
			cswitch.on = lpm_on;
			show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
			return;
		}
		BOOL notifyActual = NO;
		if (CLWriteNotifyState(system_lpm_notif, requested, &notifyActual) && notifyActual == requested) {
			lpm_on = notifyActual;
			cswitch.on = notifyActual;
			return;
		}
		cswitch.on = lpm_on;
		show_alert(L_FAILED, _C("Unable to set Low Power Mode."), L_OK);
		return;
	}
	if (@available(iOS 16.0, macOS 13.0, *)) {
		Class cls = [bundle classNamed:@"_PMLowPowerMode"];
		object = (cls && [cls respondsToSelector:@selector(sharedInstance)]) ? [cls sharedInstance] : nil;
		if (!object) {
			cswitch.on = lpm_on;
			show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
			return;
		}
		__weak ChargingManagementViewController *weakSelf = self;
		__weak id weakLPMObject = object;
		NSUInteger requestGeneration = ++lpm_request_generation;
		[object setPowerMode:requested fromSource:@"com.torrekie.Battman" withCompletion:^(BOOL success, NSError *completionError) {
			dispatch_async(dispatch_get_main_queue(), ^{
				ChargingManagementViewController *strongSelf = weakSelf;
				id strongLPMObject = weakLPMObject;
				if (!strongSelf || !strongLPMObject)
					return;
				if (strongSelf->lpm_request_generation != requestGeneration)
					return;
				(void)success;
				(void)completionError;
				BOOL readbackAvailable = [strongLPMObject respondsToSelector:@selector(getPowerMode)];
				BOOL actual = readbackAvailable && (((NSInteger)[strongLPMObject getPowerMode] & 1) != 0);
				DBGLOG(@"Switching %@ LPM. Success=%d error: %@ readbackAvailable=%d actual=%d", requested ? @"into" : @"out of", success, completionError, readbackAvailable, actual);
				/* The completion result only reports whether the request was
				 * accepted.  Trust the independently read system state, including
				 * when the callback reports an error after applying the change. */
				if (readbackAvailable && actual == requested) {
					strongSelf->lpm_on = actual;
					cswitch.on = actual;
					return;
				}
				BOOL notifyActual = NO;
				if (CLWriteNotifyState(strongSelf->system_lpm_notif, requested, &notifyActual) && notifyActual == requested) {
					strongSelf->lpm_on = notifyActual;
					cswitch.on = notifyActual;
					return;
				}
				cswitch.on = strongSelf->lpm_on;
				show_alert(L_FAILED, _C("Unable to set Low Power Mode."), L_OK);
			});
		}];
		return;
	}

	Class cls = [bundle classNamed:@"_CDBatterySaver"];
	object = (cls && [cls respondsToSelector:@selector(batterySaver)]) ? [cls batterySaver] : nil;
	if (!object || ![object respondsToSelector:@selector(setPowerMode:error:)]) {
		cswitch.on = lpm_on;
		show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
		return;
	}
	BOOL callSucceeded = [object setPowerMode:requested error:&error];
	BOOL actual = lpm_on;
	BOOL readbackAvailable = NO;
	if ([object respondsToSelector:@selector(getPowerMode)]) {
		actual = (((NSInteger)[object getPowerMode] & 1) != 0);
		readbackAvailable = YES;
	} else if (system_lpm_notif) {
		BOOL notifyActual = NO;
		if (CLReadNotifyState(system_lpm_notif, &notifyActual)) {
			actual = notifyActual;
			readbackAvailable = YES;
		}
	}
	/* A failed setter callback is not proof that the state stayed unchanged;
	 * use an independent getter/notify readback as the source of truth before
	 * attempting the legacy notify write fallback. */
	if (!readbackAvailable || actual != requested) {
		BOOL notifyActual = NO;
		if (!CLWriteNotifyState(system_lpm_notif, requested, &notifyActual) || notifyActual != requested) {
			cswitch.on = lpm_on;
			show_alert(L_FAILED, _C("Unable to set Low Power Mode."), L_OK);
			return;
		}
		actual = notifyActual;
	}
	(void)callSucceeded;
	DBGLOG(@"Synchronous LPM request success=%d error=%@ readback=%d", callSucceeded, error, actual);
	lpm_on = actual;
	cswitch.on = actual;
}

- (void)setLPMAutoDisable:(UISwitch *)cswitch {
	if (!lpm_supported) {
		cswitch.on = NO;
		return;
	}
	if (batterysaver || is_simulator()) {
		[batterysaver setBool:cswitch.on forKey:@"autoDisableWhenPluggedIn"];
	} else {
		battman_worker_oneshot(1, cswitch.on);
	}
	notify_post(batterysaver_notif);
}

- (void)setAllowThr:(UISwitch *)cswitch {
	if (!lpm_supported) {
		cswitch.on = NO;
		return;
	}
	if (!cswitch.on) {
		if (batterysaver || is_simulator()) {
			[batterysaver removeObjectForKey:@"autoDisableThreshold"];
		} else {
			battman_worker_oneshot(2, 0);
		}
		lpm_thr = 0;
	} else {
		lpm_thr = 80;
		if (batterysaver || is_simulator()) {
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
			NSBundle *powerUIBundle = [NSBundle systemBundleWithName:@"PowerUI"];
				if (![powerUIBundle loadAndReturnError:&err]) {
				NSString *errorMessage = [NSString stringWithFormat:@"%@ %@\n\n%s: %@", _("Failed to load"), @"PowerUI.framework", L_ERR, [err localizedDescription]];
				show_alert(L_FAILED, [errorMessage UTF8String], L_OK);
					goto tvend;
				}
				id sccClass = [powerUIBundle classNamed:@"PowerUISmartChargeClient"];
				if (!sccClass || ![sccClass instancesRespondToSelector:@selector(initWithClientName:)] ||
					![sccClass instancesRespondToSelector:@selector(setState:error:)] ||
					![sccClass instancesRespondToSelector:@selector(engageFrom:until:repeatUntil:overrideAllSignals:)]) {
					show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
					goto tvend;
				}
				id sccObject = [[sccClass alloc] initWithClientName:@"ok"];
				if (!sccObject) {
					show_alert(L_FAILED, _C("Not supported on this device"), L_OK);
					goto tvend;
				}
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
		BOOL readOK = hasSMC && !daemon_pid;
        SEL action = nil;
        // TODO: Reduce redundant codes
        if (indexPath.row == 0) {
            cell.textLabel.text = _("Block Charging");
			readOK = readOK && (smc_read_n('CH0C', &switchOn, 1) == 0);
            action = @selector(setBlockCharging:);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = _("Block Power Supply");
			readOK = readOK && (smc_read_n('CH0I', &switchOn, 1) == 0);
            action = @selector(setBlockPower:);
        }
        [cswitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
        cswitch.on = (switchOn & 0xFF) != 0;
		cswitch.accessibilityLabel = cell.textLabel.text;
		cswitch.accessibilityValue = cswitch.on ? _("Enabled") : _("Disabled");
        /* 0: disabled, 1: enabled, 2: managed */
        /* while 2, user cannot reset the value */
		cswitch.enabled = readOK && !(switchOn & 0x2);
		if (!readOK)
			cell.detailTextLabel.text = _("Unavailable");
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
            cswitch.enabled = lpm_supported;
            if (!lpm_supported) {
                cswitch.on = NO;
            } else if (batterysaver || is_simulator()) {
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
            cswitch.enabled = lpm_supported;
            if (!lpm_supported) {
                lpm_thr = 0;
                cswitch.on = NO;
            } else if (batterysaver || is_simulator()) {
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
			cell_s.integerOnly = YES;
			cell_s.slider.accessibilityLabel = _("Disable When Exceeds");
			cell_s.textField.accessibilityLabel = _("Disable When Exceeds");

			cell_s.slider.enabled = lpm_supported && (lpm_thr) ? YES : NO;
			cell_s.textField.enabled = cell_s.slider.enabled;
            cell_s.slider.userInteractionEnabled = cell_s.slider.enabled;
            cell_s.textField.userInteractionEnabled = cell_s.slider.enabled;
            cell_s.userInteractionEnabled = cell_s.slider.enabled;

            cell_s.slider.value = (lpm_thr) ? lpm_thr : 80;
            cell_s.textField.text = (lpm_thr) ? [NSString stringWithFormat:@"%d", (int)lpm_thr] : @"80";

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
		cswitch.accessibilityLabel = cell.textLabel.text;
		cswitch.accessibilityValue = cswitch.on ? _("Enabled") : _("Disabled");
        cell.accessoryView = cswitch;
    }

    return cell;
}

#pragma mark - SliderTableViewCell Delegate

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
    int rounded = (int)lroundf(value);
    cell.slider.value = rounded;
    cell.textField.text = [NSString stringWithFormat:@"%d", rounded];
    DBGLOG(@"Slider changed at row %ld: %d", (long) [self.tableView indexPathForCell:cell].row, rounded);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value {
	if ([cell.reuseIdentifier isEqualToString:@"LPM_THR"]) {
		int rounded = (int)lroundf(value);
		float roundedFloat = (float)rounded;
		lpm_thr = roundedFloat;
		if (batterysaver || is_simulator())
			[batterysaver setFloat:roundedFloat forKey:@"autoDisableThreshold"];
		else
			battman_worker_call(3, (void *)&roundedFloat, 4);
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
