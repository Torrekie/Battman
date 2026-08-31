#import "BatteryInfoTableViewCell.h"
#include "../battery_utils/bin_display.h"
#include "../common.h"
#include <math.h>
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
	BOOL updatedForeground = NO;
	BOOL updatedBackground = NO;
	battery_info_read_lock();
	// TODO: Arabian? We need Arabian hackers to fix this code
	for (struct battery_info_section *sect = *_batteryInfo; sect; sect = sect->next) {
		if (sect->context->custom_identifier != BI_GAS_GAUGE_SECTION_ID)
			continue;

		for (struct battery_info_node *i = sect->data; i->name != NULL; i++) {
			if (i->content & BIN_IS_SPECIAL) {
				uint32_t value = i->content >> 16;
				/* A dynamically unavailable node may still carry the
				 * foreground/background flag used by the previous value.  Do
				 * not animate the gauge from that stale payload, while keeping
				 * intrinsic hidden rows (such as ASoC) functional. */
				if (!(i->content & BIN_DYNAMIC_HIDDEN)) {
					float percentage = bi_node_load_float(i);
					BOOL validPercentage = isfinite(percentage) && percentage >= 0.0f && percentage <= 100.0f;
					if (validPercentage &&
					    (i->content & BIN_IS_FOREGROUND) == BIN_IS_FOREGROUND) {
						[_batteryCell updateForegroundPercentage:percentage];
						updatedForeground = YES;
					} else if (validPercentage &&
					           (i->content & BIN_IS_BACKGROUND) == BIN_IS_BACKGROUND) {
						[_batteryCell updateBackgroundPercentage:percentage];
						updatedBackground = YES;
					}
				}
				if (i->content & BIN_IS_HIDDEN)
					continue;

				if ((i->content & BIN_IS_BOOLEAN) == BIN_IS_BOOLEAN && value) {
					final_str = [NSString
					    stringWithFormat:@"%@\n%@", final_str, _(i->name)];
				} else if ((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT) {
					final_str =
					    [NSString stringWithFormat:@"%@\n%@: %@", final_str, _(i->name), bin_format_special(i->content)];
				}
			}
		}
		// Only show in details if is string
	}
	battery_info_unlock();
	/* A failed refresh must not leave the previous gauge percentages animating
	 * indefinitely. Zeroing each missing layer leaves the neutral battery
	 * outline while preserving any layer that did receive a valid value. */
	if (!updatedForeground)
		[_batteryCell updateForegroundPercentage:0.0f];
	if (!updatedBackground)
		[_batteryCell updateBackgroundPercentage:0.0f];
	if (!final_str.length) {
		/* Do not leave the previous refresh's values on screen when the SMC
		 * temporarily stops answering. */
		_batteryLabel.text = _("Unavailable");
		return;
	}
	_batteryLabel.text = [final_str substringFromIndex:1];
}

@end
