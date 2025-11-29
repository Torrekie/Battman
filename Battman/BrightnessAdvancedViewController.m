//
//  BrightnessAdvancedViewController.m
//  Battman
//
//  Created by Torrekie on 2025/11/25.
//

#import "common.h"
#import <notify.h>
#import "SliderTableViewCell.h"
#import "BrightnessAdvancedViewController.h"

extern uint64_t battman_worker_call(char cmd, void *arg, uint64_t arglen);
extern void battman_worker_oneshot(char cmd, char arg);

@interface BrightnessAdvancedViewController () <SliderTableViewCellDelegate> {
	NSUserDefaults *batterysaver;
	const char *batterysaver_notif;
	
	float reduction;
}
@end

typedef enum {
	BA_SECT_REDUCT,
	BA_SECT_COUNT,
} BASect;

typedef enum {
	BA_ROW_REDUCT_SLIDER,
	BA_ROW_REDUCT_COUNT,
} BARowReduct;

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
	}
	return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
	[self.tableView registerClass:[SliderTableViewCell class] forCellReuseIdentifier:@"BA_REDUCT"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return BA_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	BASect sect = (BASect)section;
	switch (sect) {
		case BA_SECT_REDUCT: return _("LPM Brightness Reduction");
		default: break;
	}
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
		default:
			break;
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
