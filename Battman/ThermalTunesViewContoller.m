//
//  ThermalTunesViewContoller.m
//  Battman
//
//  Created by Torrekie on 2025/8/2.
//

#import "ThermalTunesViewContoller.h"

#include <sys/sysctl.h>
#include "battery_utils/thermal.h"
#import "common.h"
#import "intlextern.h"
#import "FooterHyperlinkView.h"
#import "UberSegmentedControl/UberSegmentedControl.h"

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

static bool has_hip = false;

@interface ThermalTunesViewContoller ()
@property BOOL show_sunlight_override;
@property (nonatomic, strong) FooterHyperlinkView *warnTitle;
@end

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
	return getenv("SIMULATOR_DEVICE_NAME") ? 1 : TT_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	TTSects sect = (TTSects)section;
	switch (sect) {
		case TT_SECT_HEADER: return nil;
		case TT_SECT_GENERAL: return _("General");
		case TT_SECT_HIP: return has_hip ? _("Hot-In-Pocket Mode") : nil; // Sadly, HIP heuristics has no official translations
		case TT_SECT_SUNLIGHT: return _("Sunlight Exposure");
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
				if (@available(iOS 13.0, *))
					cell.detailTextLabel.textColor = [UIColor systemGrayColor];
				else
					cell.detailTextLabel.textColor = [UIColor grayColor];
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
				if (@available(iOS 13.0, *))
					cell.detailTextLabel.textColor = [UIColor systemGrayColor];
				else
					cell.detailTextLabel.textColor = [UIColor grayColor];
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
	// TODO: Override4CC
	return cell;
}

- (void)controllerChanged:(UIView *)controller {
	UIView *view = controller;
	while (view && ![view isKindOfClass:[UITableViewCell class]]) {
		view = [view superview];
	}
	if (view) {
		UITableViewCell *cell = (UITableViewCell *)view;
		UIView *tb = view;
		while (tb && ![tb isKindOfClass:[UITableView class]]) {
			tb = [tb superview];
		}
		if (tb) {
			UITableView *tv = (UITableView *)tb;
			NSIndexPath *ip = [tv indexPathForCell:cell];

			[self writeThermalBoolByIndexPath:ip control:(UIControl *)cell.accessoryView];

			// Special
			if (ip.section == TT_SECT_SUNLIGHT && ip.row == TT_ROW_SUNLIGHT_AUTO) {
				UISwitch *control = (UISwitch *)controller;
				_show_sunlight_override = !control.on;
				[tv beginUpdates];
				[tv endUpdates];
			}
			return;
		}
	}
	
	DBGLOG(@"FIXME: controllerChanged without cell view!");
}

// 0    0   00
// SECT ROW VALUE
//          0x1: On/Off
//          0x2: Persist
#define WORKER_THERMAL_BOOL_CMD (uint32_t)((indexPath.section << 12) | (indexPath.row << 8) | (ctrl.persist << 1) | (ctrl.toggled))

- (void)writeThermalBoolCmd:(uint16_t)cmd {
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
			[self writeThermalBoolCmd:WORKER_THERMAL_BOOL_CMD];
	}
	if ([control isKindOfClass:[UISwitch class]]) {
		UISwitch *ctrl = (UISwitch *)control;
		[self writeThermalBoolCmd:(uint16_t)((indexPath.section << 12) | (indexPath.row << 8) | (ctrl.on))];
	}
}

@end
