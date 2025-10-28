#import "SimpleTemperatureViewController.h"
#import "common.h"
#include "intlextern.h"

#include "scprefs/wrapper.h"
#include "battery_utils/thermal.h"

// battery_utils/hid.m
extern NSDictionary        *getTemperatureHIDData(void);
extern NSDictionary        *getSensorTemperatures(void);

static NSMutableDictionary *knownHIDSensors;
static NSMutableDictionary *thermalBasics;

@implementation SimpleTemperatureViewController

- (instancetype)init {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}
	self.tableView.allowsSelection = 0;
	// This is terrible, try enhance the code later
	if (thermalBasics == NULL) {
		thermalBasics = [[NSMutableDictionary alloc] init];
		[thermalBasics setValue:[NSString stringWithCString:get_thermal_pressure_string(thermal_pressure()) encoding:NSUTF8StringEncoding] forKey:@"Thermal Pressure"];
		// OSNotification level is Embedded only
		thermal_notif_level_t notif_level = thermal_notif_level();
		if ((notif_level != kBattmanThermalNotificationLevelAny) && !(is_rosetta() || getenv("SIMULATOR_DEVICE_NAME")))
			[thermalBasics setValue:[NSString stringWithCString:get_thermal_notif_level_string(notif_level) encoding:NSUTF8StringEncoding] forKey:@"Thermal Notification Level"];
		float max_temp = thermal_max_trigger_temperature();
		if (max_temp > 0)
			[thermalBasics setValue:@(max_temp) forKey:@"Max Trigger Temperature"];
		[thermalBasics setValue:thermal_solar_state() == 100 ? _("True") : _("False") forKey:@"Sunlight Exposure"];
	}
	temperatureHIDData = getTemperatureHIDData();
	sensorTemperatures = getSensorTemperatures();
	if (knownHIDSensors == NULL) {
		extern float getTemperatureHIDAt(NSString *);
		knownHIDSensors = [[NSMutableDictionary alloc] init];
#if 0
		// Gettext
		NSArray __unused *knownKeys = @[
			_("Device Avg."),
			// _("iPad Skin"),
			_("Battery Cell 1"),
			_("Battery Cell 2"),
			_("Battery Cell 3"),
			_("Battery Cell 4"),
			_("Camera Module"),
		];
		NSArray __unused *knownBasics = @[
			_("Thermal Pressure"),
			/* Thermal Cold Pressure is only for (N112 N66 N66m N69 N69u N71 N71m D10 D101 D11 D111)*/
			_("Thermal Notification Level"),
			_("Max Trigger Temperature"),
			_("Sunlight Exposure"),
		];
#endif
		extern NSArray *getHIDSkinModelsOf(NSString * prod);
		// XXX: Try to figure out more
		// TODO: Warn on invalid VTs
		// TODO: Show die VTs
		// TG*B: 15 ~ 46
		// Die: 17 ~ 75
		// TSFC: 8 ~ 46
		NSDictionary   *dict = @{
            @"Device Avg.": getHIDSkinModelsOf([NSString stringWithCString:target_type() encoding:NSUTF8StringEncoding]),
			// TODO: Major skin sensor
            // @"iPad Skin": @"TSBM",
            @"Battery Cell 1": @"TG0B",
            @"Battery Cell 2": @"TG1B",
            @"Battery Cell 3": @"TG2B",
            @"Battery Cell 4": @"TG3B",
            @"Camera Module": @"TSFC",
		};

		NSArray<NSString *> *keys = [dict allKeys];
		NSArray             *vals = [dict allValues];
		for (NSUInteger i = 0; i < dict.count; i++) {
			NSString *className = NSStringFromClass([vals[i] class]);
			if ([className isEqualToString:@"__NSArrayI"] || [className isEqualToString:@"NSArray"]) {
				NSArray *buf         = (NSArray *)vals[i];
				float    avg         = 0;
				int      valid_count = 0;
				for (NSUInteger j = 0; j < buf.count; j++) {
					float temp = getTemperatureHIDAt(buf[j]);
					if (temp != -1) {
						avg += temp;
						valid_count++;
					}
				}
				if (valid_count) {
					avg /= valid_count;
					[knownHIDSensors setValue:[NSNumber numberWithFloat:avg] forKey:keys[i]];
				}
			}
			if ([className isEqualToString:@"__NSCFConstantString"] || [className isEqualToString:@"NSString"]) {
				float temp = getTemperatureHIDAt(vals[i]);
				if (temp != -1) {
					[knownHIDSensors setValue:[NSNumber numberWithFloat:temp] forKey:keys[i]];
				}
			}
		}
	}
	return self;
}

- (NSString *)title {
	return _("Hardware Temperature");
}

- (void)viewDidLoad {
	UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
	[refreshControl addTarget:self action:@selector(updateTableView) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = refreshControl;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
	// IOHID is not available in Simulators, try find other ways later
	return getenv("SIMULATOR_DEVICE_NAME") ? 2 : 5;
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
	if (section == 0) {
		return 2;
	} else if (section == 1) {
		return thermalBasics.count;
	} else if (section == 2) {
		return sensorTemperatures.count;
	} else if (section == 3) {
		return knownHIDSensors.count;
	}
	return temperatureHIDData.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case 0:
			return _("System Thermal Monitor State");
		case 1:
			return _("Thermal Basics");
		case 2:
			return _("Device Sensors");
		case 3:
			return _("HID");
	}
	return _("HID Raw Data");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	// Consider use NSAttributedString here
	if (section == 0) {
		return _("Adjust ThermalMonitor behavior on the Thermal Tunes page.");
	}
	if (section == 2) {
		return _("Some sensors may not provide real‑time temperature data.");
	}
	return nil;
}

- (void)updateTableView {
	DBGLOG(@"STVC: updateTableView");
	[self.refreshControl beginRefreshing];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self.tableView reloadData];
		[self.refreshControl endRefreshing];
	});
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

	if (indexPath.section == 0) {
		if ([cell.textLabel.text isEqualToString:_("Daemon State")]) {
			show_alert([cell.textLabel.text UTF8String], _C("ThermalMonitor is a critical system component responsible for managing device and battery health. Disabling it may lead to unexpected behavior and is not recommended."), L_OK);
		}
	} else if (indexPath.section == 1) {
		if ([cell.textLabel.text isEqualToString:_("Max Trigger Temperature")]) {
			show_alert([cell.textLabel.text UTF8String], _C("Maximum device‑skin temperature per thermal‑monitoring cycle. Exceeding this threshold within the cycle automatically generates an AppleCare thermal‑exception log."), L_OK);
		}
	}
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"stvc:main"];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"stvc:main"];
	NSDictionary *dict  = NULL;
	NSString     *label = NULL;
	/* Sect0/1 is handled differently */
	if (ip.section == 0) {
		cell = [tv dequeueReusableCellWithIdentifier:@"thermalmonitord"];
		if (!cell)
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"thermalmonitord"];
		if (ip.row == 0) {
			cell.textLabel.text = _("Daemon State");
			cell.detailTextLabel.text = _("Disabled");

			NSOperatingSystemVersion ios13 = {
				.majorVersion = 13,
				.minorVersion = 0,
				.patchVersion = 0,
			};
			int pid = -1;
			if (is_platformized() ) {
				if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios13]) {
					pid = get_pid_for_launchd_label("com.apple.thermalmonitord");
				} else {
					// TODO: iOS 12: also need to check if ThermalMonitor.bundle is loaded, but I don't have device
					pid = get_pid_for_launchd_label("com.apple.mobilewatchdog");
				}
			} else {
				// Not that accurate workaround
				// get_pid_for_procname() currently uses kp_proc.p_comm to match process
				// which can be possibly spoofed
				if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios13])
					pid = get_pid_for_procname("thermalmonitord");
				else
					pid = get_pid_for_procname("mobilewatchdog");
			}

			if (pid != -1 && pid != 0) {
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%d)", _("Running"), pid];
			} else if (is_rosetta() || getenv("SIMULATOR_DEVICE_NAME")) {
				cell.detailTextLabel.text = _("Simulator");
			} else {
				UIColor *red;
				if (@available(iOS 13.0, *))
					red = [UIColor systemRedColor];
				else
					red = [UIColor redColor];
				cell.detailTextLabel.textColor = red;
				cell.accessoryType = UITableViewCellAccessoryDetailButton;
				if (pid == -1) {
					cell.detailTextLabel.text = _("Unable to detect");
				}
			}
		} else if (ip.row == 1) {
			cell.textLabel.text = _("CLTM State");
			int status = getCLTMStatus();
			switch (status) {
				case 3:
					cell.detailTextLabel.text = _("Using CLTMv2");
					break;
				case 0:
					cell.detailTextLabel.text = _("Unsupported");
					break;
				case -1:
					cell.detailTextLabel.text = _("Error");
					break;
				default:
					cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ (%d)", _("Not Running"), status];
					break;
			}
			if (status != 3) {
				UIColor *red;
				if (@available(iOS 13.0, *))
					red = [UIColor systemRedColor];
				else
					red = [UIColor redColor];
				cell.detailTextLabel.textColor = red;
			}
		}
		return cell;
	} else if (ip.section == 1) {
		dict = thermalBasics;
		label = dict.allKeys[ip.row];
		if ([label isEqualToString:@"Max Trigger Temperature"]) {
			// XXX: temp workaround
			cell = [tv dequeueReusableCellWithIdentifier:@"maxtherm"];
			if (!cell)
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"maxtherm"];
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%.4g ℃", [dict[dict.allKeys[ip.row]] floatValue]];
			cell.accessoryType = UITableViewCellAccessoryDetailButton;
		} else {
			cell.detailTextLabel.text = dict[dict.allKeys[ip.row]];
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.accessoryView = nil;
		}
		// TODO: Better UI for pressures
		cell.textLabel.text = _([label UTF8String]);

		return cell;
	} else if (ip.section == 2) {
		dict  = sensorTemperatures;
		// ????? this is terrible, why not store cstring at beginning?
		label = _([dict.allKeys[ip.row] UTF8String]);
	} else if (ip.section == 3) {
		dict  = knownHIDSensors;
		label = _([dict.allKeys[ip.row] UTF8String]);
	} else if (ip.section == 4) {
		/* TODO: Filter stub & info only VTs */
		/* Some sensors are not actually getting its temperature
		   they always looks like 0.00 or 30.00 */

		/* TODO: Better UI for sensors having Avg & Cur & Max */
		/* Not every HID temp sensors recording realtime values */
		dict  = temperatureHIDData;
		label = dict.allKeys[ip.row];
	}
	cell.textLabel.text       = label;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%.4g ℃", [dict[dict.allKeys[ip.row]] floatValue]];

	/* TODO: thermtune */
	return cell;
}

@end
