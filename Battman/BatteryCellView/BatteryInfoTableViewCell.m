#import "BatteryInfoTableViewCell.h"
#include "../common.h"
#include <stdint.h>
#include <stdlib.h>

#include "../battery_utils/libsmc.h"

@implementation BatteryInfoTableViewCell

- (void)setupCellUI {
	BatteryCellView *batteryCell = [[BatteryCellView alloc] initWithFrame:CGRectMake(0, 0, 80, 80) foregroundPercentage:0 backgroundPercentage:0];
	batteryCell.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:batteryCell];
	[batteryCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[batteryCell.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:20].active = 1;
	[batteryCell.heightAnchor constraintEqualToConstant:80].active = 1;
	[batteryCell.widthAnchor constraintEqualToAnchor:batteryCell.heightAnchor].active = 1;
	UILabel *batteryRemainingLabel = [UILabel new];
	batteryRemainingLabel.lineBreakMode = NSLineBreakByWordWrapping;
	batteryRemainingLabel.numberOfLines = 0;
	[self.contentView addSubview:batteryRemainingLabel];
	[batteryRemainingLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[batteryRemainingLabel.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-20].active = 1;
	[batteryRemainingLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.8].active = 1;
	[batteryRemainingLabel.leftAnchor constraintEqualToAnchor:batteryCell.rightAnchor constant:20].active = 1;
	batteryRemainingLabel.translatesAutoresizingMaskIntoConstraints = 0;
	_batteryLabel = batteryRemainingLabel;
	_batteryCell = batteryCell;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (instancetype)init {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BTTVC-cell"];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (void)updateBatteryInfo {
	NSString *final_str = @"";
	// TODO: Arabian? We need Arabian hackers to fix this code
	for (struct battery_info_section *sect = *_batteryInfo; sect; sect = sect->next) {
		if (sect->context->custom_identifier != BI_GAS_GAUGE_SECTION_ID)
			continue;

		for (struct battery_info_node *i = sect->data; i->name != NULL; i++) {
			if (i->content & BIN_IS_SPECIAL) {
				uint32_t value = i->content >> 16;
				if ((i->content & BIN_IS_FOREGROUND) == BIN_IS_FOREGROUND) {
					[_batteryCell updateForegroundPercentage:bi_node_load_float(i)];
				} else if ((i->content & BIN_IS_BACKGROUND) == BIN_IS_BACKGROUND) {
					[_batteryCell updateBackgroundPercentage:bi_node_load_float(i)];
				}
				if (i->content & BIN_IS_HIDDEN)
					continue;

				if ((i->content & BIN_IS_BOOLEAN) == BIN_IS_BOOLEAN && value) {
					final_str = [NSString
					    stringWithFormat:@"%@\n%@", final_str, _(i->name)];
				} else if ((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT) {
					final_str =
					    [NSString stringWithFormat:@"%@\n%@: %.4g", final_str, _(i->name), bi_node_load_float(i)];
				}
				if (i->content & BIN_HAS_UNIT) {
					uint32_t  unit     = (i->content & BIN_UNIT_BITMASK) >> 6;
					NSString *unit_str = _(bin_unit_strings[unit]);
					final_str =
					    [NSString stringWithFormat:@"%@ %@", final_str, unit_str];
				}
			}
			// Only show in details if is string
		}
	}
	if (!final_str.length)
		return;
	_batteryLabel.text = [final_str substringFromIndex:1];
}

@end
