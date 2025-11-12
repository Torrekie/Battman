//
//  ThermalTunesViewContoller.m
//  Battman
//
//  Created by Torrekie on 2025/8/2.
//

#import "ThermalTunesViewContoller.h"
#import "ObjCExt/UIColor+compat.h"

#include <sys/sysctl.h>
#include "battery_utils/thermal.h"
#import "common.h"
#import "intlextern.h"
#import "FooterHyperlinkView.h"
#import "UberSegmentedControl/UberSegmentedControl.h"
#import "ColorSegProgressView.h"
//#import "PickerAccessoryView.h"
#import "DatePickerCompactButton.h"

@interface ThermalSegmentedControl : UIView
@property (nonatomic, assign) BOOL toggled;
@property (nonatomic, assign) BOOL persist;
@property (nonatomic) BOOL isLockerSwitch;
@property (nonatomic, strong) UberSegmentedControl *control;
@end

@implementation ThermalSegmentedControl
@dynamic toggled;
@dynamic persist;

- (instancetype)initWithLockerSwitch {

	NSArray *items;
	if (@available(iOS 13.0, *)) {
		items = @[[UIImage systemImageNamed:@"lock.fill"], [UIImage systemImageNamed:@"checkmark"]];
	} else {
		// lock.fill U+1003A1
		// checkmark U+100185
		items = @[@"􀎡", @"􀆅"];
	}
	self = [super initWithFrame:CGRectMake(0, 0, 74, 32)];
	if (self) {
		self.isLockerSwitch = YES;

		UberSegmentedControlConfig *conf = [[UberSegmentedControlConfig alloc] initWithFont:[UIFont systemFontOfSize:UIFont.systemFontSize weight:UIFontWeightRegular] tintColor:nil allowsMultipleSelection:YES];

		_control = [[UberSegmentedControl alloc] initWithItems:items config:conf];
		[_control setFrame:CGRectMake(0, 0, 74, 32)];
		[self addSubview:_control];
		
		_control.translatesAutoresizingMaskIntoConstraints = NO;
		[_control.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
		[_control.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
	}
	return self;
}

- (BOOL)toggled {
	BOOL ret = NO;
	if (self.isLockerSwitch) {
		ret = [[_control selectedSegmentIndexes] containsIndex:1];
	}
	return ret;
}

- (BOOL)persist {
	BOOL ret = NO;
	if (self.isLockerSwitch) {
		ret = [[_control selectedSegmentIndexes] containsIndex:0];
	}
	return ret;
}

- (void)setToggled:(BOOL)toggled {
	if (self.isLockerSwitch) {
		NSMutableIndexSet *indexes = (NSMutableIndexSet*)[_control selectedSegmentIndexes];
		if(toggled) {
			[indexes addIndex:1];
		}else{
			[indexes removeIndex:1];
		}
		[_control setSelectedSegmentIndexes:indexes];
	}
}
- (void)setPersist:(BOOL)persist {
	if (self.isLockerSwitch) {
		NSMutableIndexSet *indexes = (NSMutableIndexSet*)[_control selectedSegmentIndexes];
		if(persist) {
			[indexes addIndex:0];
		}else{
			[indexes removeIndex:0];
		}
		[_control setSelectedSegmentIndexes:indexes];
	}
}
- (void)updateLockerSwitchByFunction:(bool (*)(bool *, bool *))function {
	bool enabled = false;
	bool persist = false;
	(void)function(&enabled, &persist);
	NSLog(@"ENABLED %d PERSIST %d", enabled, persist);
	[self setToggled:enabled];
	[self setPersist:persist];
}

@end

typedef enum {
	TT_SECT_HEADER,
	TT_SECT_GENERAL,
	TT_SECT_HIP,
	TT_SECT_SUNLIGHT,
	TT_SECT_LEVEL,

	TT_SECT_COUNT
} TTSects;

// TT_SECT_GENERAL
typedef enum {
	TT_ROW_GENERAL_ENABLED,
	TT_ROW_GENERAL_CLTM,
} TTSectGeneral;

// TT_SECT_HIP
typedef enum {
	TT_ROW_HIP_ENABLED,
	TT_ROW_HIP_SIMULATE,
} TTSectHIP;

// TT_SECT_SUNLIGHT
typedef enum {
	TT_ROW_SUNLIGHT_AUTO,
	TT_ROW_SUNLIGHT_OVERRIDE,
	TT_ROW_SUNLIGHT_STATUS,
} TTSectSunlight;

// TT_SECT_LEVEL
typedef enum {
	TT_ROW_LEVEL_PRESSURE,
	TT_ROW_LEVEL_NOTIF,
} TTSectLevel;

static bool has_hip = false;

@interface ThermalTunesViewContoller ()
@property BOOL show_sunlight_override;
@property (nonatomic, strong) FooterHyperlinkView *warnTitle;
@end

extern UITableViewCell *find_cell(UIView *view);

@implementation ThermalTunesViewContoller

- (NSString *)title {
	return _("Thermal Tunes");
}

- (instancetype)init {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}

	size_t size = 0;
	char   machine[256];
	// Do not use uname()
	if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) == 0 && sysctlbyname("hw.machine", &machine, &size, NULL, 0) == 0 && strncmp("iPhone", machine, 6) == 0) {
		// Only iPhones and Watches has HIP
		has_hip = true;
	}

	extern bool getSunlightEnabled(bool *enable, bool *persist);
	bool buf1, buf2;
	_show_sunlight_override = getSunlightEnabled(&buf1, &buf2);

	FooterHyperlinkViewConfiguration *conf = [[FooterHyperlinkViewConfiguration alloc] init];
	NSString *hyper = _("Learn more…");
	conf.text = [NSString stringWithFormat:_("Review the documentation before making any changes. %@"), hyper];
	conf.URL = nil;
	conf.target = self;
	conf.action = @selector(openDocumentationURL);
	NSRange range = [conf.text rangeOfString:hyper];
	conf.linkRange = NSStringFromRange(range);
	FooterHyperlinkView *view = [[FooterHyperlinkView alloc] initWithTableView:self.tableView configuration:conf];
	_warnTitle = view;
	
	return self;
}

- (void)openDocumentationURL {
	open_url(BATTMAN_DOC_URL);
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return is_simulator() ? 1 : TT_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	TTSects sect = (TTSects)section;
	switch (sect) {
		case TT_SECT_HEADER: return nil;
		case TT_SECT_GENERAL: return _("General");
		case TT_SECT_HIP: return has_hip ? _("Hot-In-Pocket Mode") : nil; // Sadly, HIP heuristics has no official translations
		case TT_SECT_SUNLIGHT: return _("Sunlight Exposure");
		case TT_SECT_LEVEL: return _("Thermal Levels");
		case TT_SECT_COUNT: break;
	}
	return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section == TT_SECT_HEADER)
		return self.warnTitle;
	else if ([super respondsToSelector:@selector(tableView:viewForFooterInSection:)])
		return [super tableView:tableView viewForFooterInSection:section];
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	TTSects sect = (TTSects)section;
	switch (sect) {
		case TT_SECT_HEADER: return nil;
		case TT_SECT_GENERAL: return _("Changing the default thermal behavior may increase wear on your battery and reduce its lifespan.");
		case TT_SECT_HIP: return has_hip ? _("Hot-In-Pocket Protection automatically reduces CPU & GPU power when the display is off and no media is playing, to prevent overheating while the device is stored in a pocket.") : nil;
		case TT_SECT_SUNLIGHT: return nil;
		case TT_SECT_LEVEL: return _("Thermal levels are normally controlled by the system. Changing them can affect power, media playback, backlight, flashlight and wireless charging.");
		case TT_SECT_COUNT: break;
	}
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	TTSects sect = (TTSects)section;
	switch (sect) {
		case TT_SECT_HEADER: return 0;
		case TT_SECT_GENERAL: return 2;
		case TT_SECT_HIP: return has_hip ? 2 : 0;
		case TT_SECT_SUNLIGHT: return 3;
		case TT_SECT_LEVEL: return 2 - (is_maccatalyst());
		case TT_SECT_COUNT: break;
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	if (indexPath.section == TT_SECT_SUNLIGHT && indexPath.row == TT_ROW_SUNLIGHT_OVERRIDE) {
		if (!_show_sunlight_override) {
			cell.hidden = true;
			return 0;
		}
		cell.hidden = false;
	}
	if (indexPath.section == TT_SECT_HIP && !has_hip) {
		cell.hidden = true;
		return 0;
	}
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	if (indexPath.section == TT_SECT_GENERAL) {
		TTSectGeneral row = (TTSectGeneral)indexPath.row;
		switch (row) {
			case TT_ROW_GENERAL_ENABLED: {
				cell.textLabel.text = _("State Updates");
				cell.detailTextLabel.textColor = [UIColor compatGrayColor];
				cell.detailTextLabel.text = _("Whether applications receive thermal state updates");
				ThermalSegmentedControl *control = [[ThermalSegmentedControl alloc] initWithLockerSwitch];
				extern bool getOSNotifEnabled(bool *enable, bool *persist);
				[control updateLockerSwitchByFunction:getOSNotifEnabled];
				cell.accessoryView = control;
				[cell.accessoryView sizeToFit];
				// Consider create a protocol
				[control.control addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
			case TT_ROW_GENERAL_CLTM: {
				cell.textLabel.text = _("Thermal Mitigations");
				cell.detailTextLabel.textColor = [UIColor compatGrayColor];
				cell.detailTextLabel.text = _("Reduce power budget when heating");
				ThermalSegmentedControl *control = [[ThermalSegmentedControl alloc] initWithLockerSwitch];
				extern bool getCLTMEnabled(bool *enable, bool *persist);
				[control updateLockerSwitchByFunction:getCLTMEnabled];
				cell.accessoryView = control;
				[cell.accessoryView sizeToFit];
				[control.control addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
		}
	}

	if (indexPath.section == TT_SECT_HIP && has_hip) {
		TTSectHIP row = (TTSectHIP)indexPath.row;
		switch (row) {
			case TT_ROW_HIP_ENABLED: {
				cell.textLabel.text = _("Enable");
				ThermalSegmentedControl *control = [[ThermalSegmentedControl alloc] initWithLockerSwitch];
				cell.accessoryView = control;
				[cell.accessoryView sizeToFit];
				extern bool getHIPEnabled(bool *enable, bool *persist);
				[control updateLockerSwitchByFunction:getHIPEnabled];
				[control.control addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
			case TT_ROW_HIP_SIMULATE: {
				cell.textLabel.text = _("Simulate HIP");
				UISwitch *button = [UISwitch new];
				extern bool getSimulateHIPEnabled(bool *enable, bool *persist);
				bool toggled = false;
				getSimulateHIPEnabled(&toggled, NULL);
				button.on = toggled;
				cell.accessoryView = button;
				[button addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
		}
	}

	if (indexPath.section == TT_SECT_SUNLIGHT) {
		TTSectSunlight row = (TTSectSunlight)indexPath.row;
		switch (row) {
			case TT_ROW_SUNLIGHT_AUTO: {
				cell.textLabel.text = _("Auto Detect");
				UISwitch *button = [UISwitch new];
				button.on = !_show_sunlight_override;
				cell.accessoryView = button;
				[button addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
			case TT_ROW_SUNLIGHT_OVERRIDE: {
				cell.textLabel.text = _("Exposure Mode");
				ThermalSegmentedControl *control = [[ThermalSegmentedControl alloc] initWithLockerSwitch];
				cell.accessoryView = control;
				cell.hidden = !_show_sunlight_override;
				[cell.accessoryView sizeToFit];
				extern bool getSunlightEnabled(bool *enable, bool *persist);
				[control updateLockerSwitchByFunction:getSunlightEnabled];
				[control.control addTarget:self action:@selector(controllerChanged:) forControlEvents:UIControlEventValueChanged];
				break;
			}
			case TT_ROW_SUNLIGHT_STATUS: {
				UITableViewCell *altcell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				altcell.textLabel.text = _("Status");
				altcell.detailTextLabel.text = [NSString stringWithFormat:@"%d", thermal_solar_state()];
				return altcell;
			}
		}
	}
	if (indexPath.section == TT_SECT_LEVEL) {
		TTSectLevel row = (TTSectLevel)indexPath.row;
		switch (row) {
			case TT_ROW_LEVEL_PRESSURE: {
				thermal_pressure_t pressure = thermal_pressure();
				if (pressure == kBattmanThermalPressureLevelError) {
					cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
					cell.textLabel.text = _("Pressure");
					cell.detailTextLabel.text = _("Unavailable");
					break;
				}
				cell.textLabel.text = _("Pressure");
				cell.detailTextLabel.text = _("Tap to adjust");

				ColorSegProgressView *seg = [[ColorSegProgressView alloc] initWithSegmentCount:kBattmanThermalPressureLevelSleeping colorTransition:@[UIColor.compatGreenColor, UIColor.compatRedColor]];
				seg.segmentSpacing = 1.0;
				seg.userInteractionEnabled = YES;
				seg.forceSquareSegments = YES;
				seg.valueShouldFollowSegments = YES;
				seg.showSeparators = NO;
				seg.colorForUnfilled = UIColor.clearColor;
				seg.colorTransitionMode = kColorSegTransitionAnalogous;
				seg.maximumValue = 5;
				seg.minimumValue = 0;
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
				[seg addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
				cell.accessoryView = seg;
				break;
			}
			case TT_ROW_LEVEL_NOTIF: {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
				thermal_notif_level_t notif = thermal_notif_level();
				cell.textLabel.text = _("Notification");
				if (notif == kBattmanThermalNotificationLevelAny) {
					cell.detailTextLabel.text = _("Unavailable");
					break;
				}
				cell.detailTextLabel.text = [NSString stringWithUTF8String:get_thermal_notif_level_string(notif, true)];
				DatePickerCompactButton *btn = [[DatePickerCompactButton alloc] initWithTitle:_("Reset")];
				[btn addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
				[btn setTitleColor:[UIColor compatLinkColor] forState:UIControlStateNormal];
				btn.titleLabel.font = cell.detailTextLabel.font;
				cell.accessoryView = btn;
				break;
#if 0
				/* Don't provide explicit setter for notif level, OSNotif seems unstable */
				NSMutableArray *options = [NSMutableArray array];
				int *levels = thermal_notif_levels();
				if (levels != NULL) {
					for (int i = 0; i < kBattmanThermalNotificationLevelUnknown; i++) {
						NSString *optionText = [NSString stringWithFormat:@"%d", levels[i]];
						if (![options containsObject:optionText])
							[options addObject:optionText];
					}
				}

				PickerAccessoryView *picker = [[PickerAccessoryView alloc] initWithFrame:CGRectZero font:nil options:options];
				[picker addTarget:self action:@selector(pickerChanged:)];
				[picker selectAutomaticRow:[options indexOfObject:[NSString stringWithFormat:@"%d", notif]] animated:YES];
				cell.detailTextLabel.text = [NSString stringWithUTF8String:get_thermal_notif_level_string(notif, false)];
				cell.accessoryView = picker;
				break;
#else
				
#endif
			}
		}
	}
	// TODO: Override4CC
	return cell;
}

- (void)controllerChanged:(UIView *)controller {
	UITableViewCell *cell = find_cell(controller);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for UIView %@", controller);
		return;
	}

	if (self.tableView) {
		[self writeThermalBoolByIndexPath:indexPath control:(UIControl *)cell.accessoryView];
		// Special
		if (indexPath.section == TT_SECT_SUNLIGHT && indexPath.row == TT_ROW_SUNLIGHT_AUTO) {
			UISwitch *control = (UISwitch *)controller;
			_show_sunlight_override = !control.on;
			[self.tableView beginUpdates];
			[self.tableView endUpdates];
			return;
		}
	}

	DBGLOG(@"FIXME: controllerChanged without tableView!");
}

- (void)sliderChanged:(ColorSegProgressView *)slider {
	UITableViewCell *cell = find_cell(slider);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for ColorSegProgressView %@", slider);
		return;
	}
	DBGLOG(@"sliderChanged: %f", slider.value);
	if (slider.value < 1.0) {
		slider.value = 1.0;
	}

	if (slider.value >= 4.0) {
		UIAlertController *warning = [UIAlertController alertControllerWithTitle:_("Are you 100% sure?") message:[NSString stringWithFormat:_("Setting thermal pressure to %s may trigger a persistent temperature warning screen. Do you want to continue?"), get_thermal_pressure_string((int)floor(slider.value - 1))] preferredStyle:UIAlertControllerStyleAlert];
		[warning addAction:[UIAlertAction actionWithTitle:_("Proceed") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			[self writeThermalInt8ByIndexPath:indexPath control:(UIControl *)slider];
		}]];
		[warning addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
			thermal_pressure_t pressure = thermal_pressure();
			slider.value = pressure + (pressure < kBattmanThermalPressureLevelSleeping);
		}]];
		[self presentViewController:warning animated:1 completion:nil];
	} else
		[self writeThermalInt8ByIndexPath:indexPath control:(UIControl *)slider];
}

#if 0
- (void)pickerChanged:(PickerAccessoryView *)picker {
	UITableViewCell *cell = find_cell(picker);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for PickerAccessoryView %@", picker);
		return;
	}
	
	[self writeThermalInt8ByIndexPath:indexPath control:(UIControl *)picker];
	[self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
}
#else
- (void)buttonTapped:(DatePickerCompactButton *)button {
	UITableViewCell *cell = find_cell(button);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for DatePickerCompactButton %@", button);
		return;
	}
	
	[self writeThermalInt8ByIndexPath:indexPath control:(UIControl *)button];
}
#endif

// 0    0   00
// SECT ROW VALUE
//          0x1: On/Off
//          0x2: Persist
#define WORKER_THERMAL_BOOL_CMD (uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | (ctrl.persist << 1) | (ctrl.toggled))

- (void)writeThermalCmd:(uint16_t)cmd {
	extern uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen);
	// SCStatus and SCError is int (4 bytes)
	uint32_t ret = battman_worker_call(5, (void *)&cmd, 2) & 0xFFFFFFFF;
	if (ret != 0) {
		char *errstr = calloc(1024, 1);
		sprintf(errstr, "%s: 0x%x", _C("Thermal Tuning failed with error"), ret);
		show_alert(L_FAILED, errstr, L_OK);
		free(errstr);
	}
}

- (void)writeThermalBoolByIndexPath:(NSIndexPath *)indexPath control:(UIControl *)control {
	if ([control isKindOfClass:[ThermalSegmentedControl class]]) {
		ThermalSegmentedControl *ctrl = (ThermalSegmentedControl *)control;
		if (ctrl.isLockerSwitch)
			[self writeThermalCmd:WORKER_THERMAL_BOOL_CMD];
	}
	if ([control isKindOfClass:[UISwitch class]]) {
		UISwitch *ctrl = (UISwitch *)control;
		[self writeThermalCmd:(uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | (ctrl.on))];
	}
}

// 0    0   00
// SECT ROW VALUE
- (void)writeThermalInt8ByIndexPath:(NSIndexPath *)indexPath control:(UIControl *)control {
	if ([control isKindOfClass:[ColorSegProgressView class]]) {
		ColorSegProgressView *ctrl = (ColorSegProgressView *)control;
		uint16_t cmd = (uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | (uint8_t)(((int)floor(ctrl.value - 1)) & 0xFF));
		[self writeThermalCmd:cmd];
	}
#if 0
	if ([control isKindOfClass:[PickerAccessoryView class]]) {
		PickerAccessoryView *picker = (PickerAccessoryView *)control;
		NSInteger row = [picker selectedRowInComponent:0];
		NSInteger opt = row % picker.options.count;
		show_alert("PICKER", [NSString stringWithFormat:@"ROW: %ld\nOPT: %ld\nTITLE: %@", row, opt, picker.options[opt]].UTF8String, L_OK);
		[self writeThermalCmd:(uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | ([picker.options[opt] intValue] & 0xFF))];
	}
#else
	if ([control isKindOfClass:[DatePickerCompactButton class]]) {
		// Reset OSNotif to 0, instead of custom values
		[self writeThermalCmd:(uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | 0)];
		[self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	}
#endif
}

@end
