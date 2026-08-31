#import "SimpleTemperatureViewController.h"
#import "ColorSegProgressView.h"
#import "common.h"
#include "intlextern.h"

#include "ObjCExt/UIColor+compat.h"

#include "scprefs/wrapper.h"
#include "battery_utils/bin_display.h"
#include "battery_utils/libsmc.h"
#include "battery_utils/thermal.h"

// battery_utils/hid.m
extern NSDictionary        *getTemperatureHIDData(void);
extern NSDictionary        *getSensorTemperatures(void);

static NSMutableDictionary *knownHIDSensors;
static NSMutableDictionary *thermalBasics;

@interface SimpleTemperatureViewController () {
	dispatch_queue_t sensorRefreshQueue;
	BOOL sensorRefreshInFlight;
	BOOL sensorRefreshPending;
}
@end

@implementation SimpleTemperatureViewController

- (NSDictionary *)readKnownHIDSensorsSnapshot {
	/* Build the derived HID rows off the main thread.  Each call creates one
	 * bounded snapshot and never mutates the UI-owned dictionary. */
	NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
	extern float getTemperatureHIDAt(NSString *);
	extern NSArray *getHIDSkinModelsOf(NSString *);
	const char *productCString = target_type();
	NSString *product = productCString ? [NSString stringWithCString:productCString encoding:NSUTF8StringEncoding] : nil;
	NSArray *deviceAverageModels = product ? getHIDSkinModelsOf(product) : nil;
	NSDictionary *definitions = @{
		@"Device Avg.": deviceAverageModels ?: @[],
		@"Battery Cell 1": @"TG0B",
		@"Battery Cell 2": @"TG1B",
		@"Battery Cell 3": @"TG2B",
		@"Battery Cell 4": @"TG3B",
		@"Camera Module": @"TSFC",
	};

	for (NSString *key in definitions) {
		id descriptor = definitions[key];
		if ([descriptor isKindOfClass:[NSArray class]]) {
			float total = 0.0f;
			NSUInteger validCount = 0;
			for (id model in (NSArray *)descriptor) {
				if (![model isKindOfClass:[NSString class]])
					continue;
				float temperature = getTemperatureHIDAt(model);
				if (!battman_temperature_is_valid(temperature))
					continue;
				total += temperature;
				validCount++;
			}
			if (validCount) {
				float average = total / (float)validCount;
				if (battman_temperature_is_valid(average))
					snapshot[key] = @(average);
			}
		} else if ([descriptor isKindOfClass:[NSString class]]) {
			float temperature = getTemperatureHIDAt(descriptor);
			if (battman_temperature_is_valid(temperature))
				snapshot[key] = @(temperature);
		}
	}
	return [snapshot copy];
}

- (void)applyTemperatureSnapshots:(NSDictionary *)snapshots {
	NSAssert([NSThread isMainThread], @"Temperature snapshots are UI state.");
	NSDictionary *hidData = snapshots[@"hid"];
	NSDictionary *sensorData = snapshots[@"sensors"];
	NSDictionary *knownData = snapshots[@"known"];
	temperatureHIDData = [hidData isKindOfClass:[NSDictionary class]] ? hidData : @{};
	sensorTemperatures = [sensorData isKindOfClass:[NSDictionary class]] ? sensorData : @{};
	if (!knownHIDSensors)
		knownHIDSensors = [[NSMutableDictionary alloc] init];
	[knownHIDSensors removeAllObjects];
	if ([knownData isKindOfClass:[NSDictionary class]])
		[knownHIDSensors addEntriesFromDictionary:knownData];
}

- (void)scheduleSensorRefresh {
	NSAssert([NSThread isMainThread], @"Temperature refresh scheduling is main-thread only.");
	if (!sensorRefreshQueue)
		sensorRefreshQueue = dispatch_queue_create("com.torrekie.Battman.temperature-sensors", DISPATCH_QUEUE_SERIAL);
	if (sensorRefreshInFlight) {
		sensorRefreshPending = YES;
		return;
	}
	sensorRefreshInFlight = YES;
	__weak SimpleTemperatureViewController *weakSelf = self;
	dispatch_async(sensorRefreshQueue, ^{
		@autoreleasepool {
			SimpleTemperatureViewController *strongSelf = weakSelf;
			if (!strongSelf)
				return;
			NSDictionary *freshHIDData = getTemperatureHIDData() ?: @{};
			NSDictionary *freshSensorTemperatures = getSensorTemperatures() ?: @{};
			NSDictionary *freshKnownHIDSensors = [strongSelf readKnownHIDSensorsSnapshot] ?: @{};
			NSDictionary *snapshots = @{
				@"hid": freshHIDData,
				@"sensors": freshSensorTemperatures,
				@"known": freshKnownHIDSensors,
			};
			dispatch_async(dispatch_get_main_queue(), ^{
				SimpleTemperatureViewController *controller = weakSelf;
				if (!controller)
					return;
				controller->sensorRefreshInFlight = NO;
				[controller applyTemperatureSnapshots:snapshots];
				if ([controller isViewLoaded]) {
					[controller.tableView reloadData];
					[controller.refreshControl endRefreshing];
				}
				if (controller->sensorRefreshPending) {
					controller->sensorRefreshPending = NO;
					[controller scheduleSensorRefresh];
				}
			});
		}
	});
}

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
	}
	[self refreshThermalBasics];
	temperatureHIDData = @{};
	sensorTemperatures = @{};
	if (!knownHIDSensors)
		knownHIDSensors = [[NSMutableDictionary alloc] init];
	sensorRefreshQueue = dispatch_queue_create("com.torrekie.Battman.temperature-sensors", DISPATCH_QUEUE_SERIAL);
	[self scheduleSensorRefresh];
	return self;
}

- (void)refreshThermalBasics {
	[thermalBasics removeAllObjects];
	[thermalBasics setValue:[NSString stringWithCString:get_thermal_pressure_string(thermal_pressure()) encoding:NSUTF8StringEncoding] forKey:@"Pressure"];
	// OSNotification level is Embedded only
	thermal_notif_level_t notif_level = thermal_notif_level();
	if ((notif_level != kBattmanThermalNotificationLevelAny) && !(is_rosetta() || is_simulator()))
		[thermalBasics setValue:[NSString stringWithCString:get_thermal_notif_level_string(notif_level, true) encoding:NSUTF8StringEncoding] forKey:@"Thermal Notification Level"];
	float max_temp = thermal_max_trigger_temperature();
	if (max_temp > 0)
		[thermalBasics setValue:@(max_temp) forKey:@"Max Trigger Temperature"];
	[thermalBasics setValue:thermal_solar_state() == 100 ? _("True") : _("False") forKey:@"Sunlight Exposure"];
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
	return is_simulator() ? 2 : 5;
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
	[self refreshThermalBasics];
	/* HID calls can block while the event system wakes. Keep all three sensor
	 * snapshots off the main thread and coalesce notifications while a read is
	 * in flight. */
	[self scheduleSensorRefresh];
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
			} else if (is_rosetta() || is_simulator()) {
				cell.detailTextLabel.text = _("Simulator");
			} else {
				cell.detailTextLabel.textColor = [UIColor compatRedColor];
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
				cell.detailTextLabel.textColor = [UIColor compatRedColor];
			}
		}
		return cell;
	} else if (ip.section == 1) {
		[self refreshThermalBasics];
		dict = thermalBasics;
		label = dict.allKeys[ip.row];
		if ([label isEqualToString:@"Max Trigger Temperature"]) {
			// XXX: temp workaround
			cell = [tv dequeueReusableCellWithIdentifier:@"maxtherm"];
			if (!cell)
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"maxtherm"];
			cell.detailTextLabel.text = battman_temp_display_string([dict[dict.allKeys[ip.row]] floatValue]);
			cell.accessoryType = UITableViewCellAccessoryDetailButton;
		} else if ([label isEqualToString:@"Pressure"]) {
			cell = [tv dequeueReusableCellWithIdentifier:@"thermpressure"];
			if (!cell)
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"thermpressure"];
			thermal_pressure_t pressure = thermal_pressure();
			if (pressure != kBattmanThermalPressureLevelError && pressure != kBattmanThermalPressureLevelUnknown) {
				// FIXME: macOS/macCatalyst/Simulator has no "light" level, so segment count should be 4
				ColorSegProgressView *seg = [[ColorSegProgressView alloc] initWithSegmentCount:kBattmanThermalPressureLevelSleeping colorTransition:@[UIColor.compatGreenColor, UIColor.compatRedColor]];
				seg.segmentSpacing = 1.0;
				seg.userInteractionEnabled = NO;
				seg.forceSquareSegments = YES;
				seg.valueShouldFollowSegments = YES;
				seg.showSeparators = NO;
				seg.colorForUnfilled = UIColor.clearColor;
				seg.colorTransitionMode = kColorSegTransitionAnalogous;
				seg.maximumValue = kBattmanThermalPressureLevelSleeping;
				seg.minimumValue = kBattmanThermalPressureLevelNominal;
				// XXX: Consider add this to UIColor+compat.m
				if (@available(iOS 14.0, *)) {
					seg.backgroundColor = UIColor.tertiarySystemFillColor;
				} else if (@available(iOS 13.0, *)) {
					// tertiarySystemFillColor does not working quite well on iOS 13
					// this dynamic color does not cover all cases, but has been calibrated with iOS 14 Dark/Light mode
					seg.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
						if ([(id)traits userInterfaceStyle] == UIUserInterfaceStyleDark) {
							return [UIColor colorWithRed:(118.0f / 255) green:(118.0f / 255) blue:(129.0f / 255) alpha:0.30];
						} else {
							return [UIColor colorWithRed:(118.0f / 255) green:(118.0f / 255) blue:(128.0f / 255) alpha:0.15];
						}
					}];
				} else {
					seg.backgroundColor = [UIColor colorWithRed:118.0f / 255 green:118.0f / 255 blue:129.0f / 255 alpha:0.15];
				}
				/* we display "Nominal" with one segment filled
				 * this will then map "Trapping" to a full value
				 * before the device actually got "Sleeping" */
				seg.value = pressure + (pressure < kBattmanThermalPressureLevelSleeping);
				CGSize progressSize = [seg sizeThatFits:CGSizeZero];
				seg.frame = CGRectMake(0, 0, progressSize.width, progressSize.height);
				cell.accessoryView = seg;
				
				// Check if detailTextLabel text can be fully displayed
				NSString *detailText = dict[dict.allKeys[ip.row]];
				CGFloat cellWidth = tv.frame.size.width - tv.separatorInset.left - tv.separatorInset.right;
				NSString *textLabelText = _([label UTF8String]);
				UIFont *textLabelFont = cell.textLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
				CGSize textLabelSize = [textLabelText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName: textLabelFont} context:nil].size;
				CGFloat availableWidth = cellWidth - textLabelSize.width - progressSize.width - 40; // 40 for spacing and padding
				if (availableWidth > 0) {
					UIFont *detailFont = cell.detailTextLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
					CGSize textSize = [detailText boundingRectWithSize:CGSizeMake(availableWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName: detailFont} context:nil].size;
					if (textSize.width <= availableWidth) {
						cell.detailTextLabel.text = detailText;
					}
				}
			}
		} else {
			cell.detailTextLabel.text = dict[dict.allKeys[ip.row]];
			cell.accessoryType = UITableViewCellAccessoryNone;
			cell.accessoryView = nil;
		}
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
	NSNumber *rawTemperature = dict[dict.allKeys[ip.row]];
	BOOL numericTemperature = [rawTemperature isKindOfClass:[NSNumber class]];
	float temperature = numericTemperature ? rawTemperature.floatValue : -1.0f;
	BOOL validTemperature = numericTemperature && battman_temperature_is_valid(temperature);
	cell.detailTextLabel.text = validTemperature ? battman_temp_display_string(temperature) : _("Unavailable");

	/* TODO: thermtune */
	return cell;
}

@end
