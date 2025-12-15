//
//  BrightnessAdvancedViewController.m
//  Battman
//
//  Created by Torrekie on 2025/11/25.
//

#import "common.h"
#import "intlextern.h"
#import <notify.h>
#import "SliderTableViewCell.h"
#import "FooterHyperlinkView.h"
#import "BrightnessAdvancedViewController.h"

extern UITableViewCell *find_cell(UIView *view);

extern uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen);
extern void battman_worker_oneshot(char cmd, char arg);

@interface BrightnessAdvancedViewController () <SliderTableViewCellDelegate> {
	NSUserDefaults *batterysaver;
	NSUserDefaults *springboard;
	const char *batterysaver_notif;
	
	float reduction;
}
@property (nonatomic, strong) FooterHyperlinkView *warnTitle;
@end

typedef enum {
	BA_SECT_HEADER,
	BA_SECT_REDUCT,
	BA_SECT_AUTOLOCK,
	BA_SECT_COUNT,
} BASect;

// BA_SECT_REDUCT
typedef enum {
	BA_ROW_REDUCT_SLIDER,
	BA_ROW_REDUCT_COUNT,
} BARowReduct;

// BA_SECT_AUTOLOCK
typedef enum {
	BA_ROW_AUTOLOCK_NO_AUTODIM,
	BA_ROW_AUTOLOCK_NO_LOCK_ON_AC,
	BA_ROW_AUTOLOCK_COUNT,
} BARowAutoLock;

@implementation BrightnessAdvancedViewController

- (instancetype)init {
	UITableViewStyle style = UITableViewStyleGrouped;
	if (@available(iOS 13.0, *))
		style = UITableViewStyleInsetGrouped;
	self = [super initWithStyle:style];
	if (self) {
		// backlightReduction pref is owned by mobile, at least til iOS 16
		if (@available(iOS 15.0, macOS 12.0, *)) {
			batterysaver = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.powerd.lowpowermode"];
			batterysaver_notif = "com.apple.powerd.lowpowermode.prefs";
		} else {
			/* afaik, at least iOS 13 */
			batterysaver = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.coreduetd.batterysaver"];
			batterysaver_notif = "com.apple.coreduetd.batterysaver.prefs";
		}
		if (!springboard)
			springboard = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.springboard"];
		
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
	}
	return self;
}

- (void)openDocumentationURL {
	open_url(BATTMAN_DOC_URL "/metrics/brightness/");
}

- (void)viewDidLoad {
    [super viewDidLoad];
	// No plans yet
	self.tableView.allowsSelection = NO;
	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"BA_REDUCT"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return BA_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	BASect sect = (BASect)section;
	switch (sect) {
		case BA_SECT_REDUCT: return _("LPM Brightness Reduction");
		case BA_SECT_AUTOLOCK: return _("Dim & Lock");
		default: break;
	}
	return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (section == BA_SECT_HEADER)
		return self.warnTitle;
	else if ([super respondsToSelector:@selector(tableView:viewForFooterInSection:)])
		return [super tableView:tableView viewForFooterInSection:section];
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	BASect sect = (BASect)section;
	switch (sect) {
		case BA_SECT_REDUCT: return _("Reduce the screen brightness when Low Power Mode is enabled.");
		default: break;
	}
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	BASect sect = (BASect)section;
	switch (sect) {
		case BA_SECT_REDUCT: return BA_ROW_REDUCT_COUNT;
		case BA_SECT_AUTOLOCK: return BA_ROW_AUTOLOCK_COUNT;
		default: break;
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	BASect sect = (BASect)indexPath.section;
	UITableViewCell *cell = nil;
	switch (sect) {
		case BA_SECT_REDUCT: {
			BARowReduct row = (BARowReduct)indexPath.row;
			switch (row) {
				case BA_ROW_REDUCT_SLIDER: {
					cell = [tableView dequeueReusableCellWithIdentifier:@"BA_REDUCT"];
					if (!cell || ![cell isKindOfClass:[SliderTableViewCell class]])
						cell = (UITableViewCell *)[[SliderTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BA_REDUCT"];
					SliderTableViewCell *slider = (SliderTableViewCell *)cell;
					slider.slider.minimumValue = 0;
					slider.slider.maximumValue = 80;
					slider.textField.enabled = YES;
					slider.slider.enabled = YES;
					slider.textField.userInteractionEnabled = YES;
					slider.slider.userInteractionEnabled = YES;

					if (batterysaver) {
						id value = [batterysaver valueForKey:@"backlightReduction"];
						if (value)
							reduction = [value floatValue];
					} else if (!is_simulator()){
						uint64_t data = battman_worker_call(6, NULL, 0);
						reduction = *(float *)&data;
					}
					if (reduction == 0)
						reduction = 20; // system default

					slider.slider.value = reduction;
					slider.textField.text = [NSString stringWithFormat:@"%d", (int)reduction];
					
					slider.delegate = self;
					break;
				}
				default: break;
			}
			break;
		}
		case BA_SECT_AUTOLOCK: {
			BARowAutoLock row = (BARowAutoLock)indexPath.row;
			// Too less to reuse
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
			UISwitch *cswitch = [[UISwitch alloc] init];
			cell.accessoryView = cswitch;
			SEL action = nil;
			switch (row) {
				case BA_ROW_AUTOLOCK_NO_AUTODIM: {
					cell.textLabel.text = _("Auto Dim");
					cswitch.on = ![springboard boolForKey:@"SBDisableAutoDim"];
					action = @selector(setDisableAutoDim:);
					break;
				}
				case BA_ROW_AUTOLOCK_NO_LOCK_ON_AC: {
					cell.textLabel.text = _("Auto Dim/Lock on A/C");
					cswitch.on = ![springboard boolForKey:@"SBDontDimOrLockOnAC"];
					action = @selector(setDontDimOrLockOnAC:);
					break;
				}
				default: break;
			}
			[cswitch addTarget:self action:action forControlEvents:UIControlEventValueChanged];
		}
		default:
			break;
	}
	if (!cell) {
		cell = [UITableViewCell new];
		cell.textLabel.text = @"You should not reach here";
	}

	return cell;
}

- (void)setDisableAutoDim:(UISwitch *)cswitch {
	void (^postconf)(void) = ^{
		[self->springboard synchronize];
		
		BOOL new = NO;
		id state = [self->springboard valueForKey:@"SBDisableAutoDim"];
		if (state)
			new = [state boolValue];
		
		if (!cswitch.on != new)
			show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
	};

	if (!cswitch.on) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Notice") message:_("Turning this off will keep the display from dimming and may shorten battery life.") preferredStyle:UIAlertControllerStyleActionSheet];
		[alert addAction:[UIAlertAction actionWithTitle:_("Proceed") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			[self->springboard setBool:!cswitch.on forKey:@"SBDisableAutoDim"];
			postconf();
		}]];
		[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
			// Do not keep this entry in settings
			[self->springboard removeObjectForKey:@"SBDisableAutoDim"];
			cswitch.on = !cswitch.on;
			postconf();
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	} else {
		// Do not keep this entry in settings
		[springboard removeObjectForKey:@"SBDisableAutoDim"];
		postconf();
	}
}

- (void)setDontDimOrLockOnAC:(UISwitch *)cswitch {
	BOOL val = !cswitch.on;
	if (val) {
		[springboard setBool:val forKey:@"SBDontDimOrLockOnAC"];
	} else {
		// Do not keep this entry in settings
		[springboard removeObjectForKey:@"SBDontDimOrLockOnAC"];
	}
	
	[springboard synchronize];
	
	BOOL new = NO;
	id state = [springboard valueForKey:@"SBDontDimOrLockOnAC"];
	if (state)
		new = [state boolValue];
	
	if (val != new)
		show_alert(L_FAILED, _C("Something went wrong when setting this property."), L_OK);
}

#pragma mark - SliderTableViewCell Delegate

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value {
	int rounded = (int)lroundf(value);
	cell.slider.value = rounded;
	cell.textField.text = [NSString stringWithFormat:@"%d", rounded];
	DBGLOG(@"Slider changed at row %ld: %d", (long) [self.tableView indexPathForCell:cell].row, rounded);
}

- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value {
	if ([cell.reuseIdentifier isEqualToString:@"BA_REDUCT"]) {
		int rounded = (int)lroundf(value);
		float roundedFloat = (float)rounded;
		reduction = roundedFloat;
		if (batterysaver)
			[batterysaver setFloat:roundedFloat forKey:@"backlightReduction"];
		else
			battman_worker_call(7, (void *)&roundedFloat, 4);
		notify_post(batterysaver_notif);
	}
}

@end
