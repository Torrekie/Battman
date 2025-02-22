#import "BatteryInfoTableViewCell.h"
#include "../common.h"
#include <stdint.h>
#include <stdlib.h>

#include "../battery_utils/libsmc.h"

@implementation BatteryInfoTableViewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    BatteryCellView *batteryCell =
        [[BatteryCellView alloc] initWithFrame:CGRectMake(20, 20, 80, 80)
                          foregroundPercentage:0
                          backgroundPercentage:0];
    batteryCell.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:batteryCell];
    //[batteryCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
    //constant:0].active=YES;
    UILabel *batteryRemainingLabel =
        [[UILabel alloc] initWithFrame:CGRectMake(120, 10, 600, 100)];
    batteryRemainingLabel.lineBreakMode = NSLineBreakByWordWrapping;
    batteryRemainingLabel.numberOfLines = 0;
    // batteryRemainingLabel.text=@"Battery Capacity: 80%\nCharge: 50%\nTest:
    // 0%";
    [self.contentView addSubview:batteryRemainingLabel];
    _batteryLabel = batteryRemainingLabel;
    _batteryCell = batteryCell;
    _batteryInfo = NULL;
    return self;
}

- (void)updateBatteryInfo {
    NSString *final_str = @"";
    // TODO: Arabian? We need Arabian hackers to fix this code
    for (struct battery_info_node *i = _batteryInfo; i->description != NULL; i++) {
        if (i->content & BIN_IS_SPECIAL) {
        	uint32_t value=i->content>>16;
            if ((i->content & BIN_IS_FOREGROUND) == BIN_IS_FOREGROUND) {
                [_batteryCell updateForegroundPercentage:bi_node_load_float(i)];
            } else if ((i->content & BIN_IS_BACKGROUND) == BIN_IS_BACKGROUND) {
                [_batteryCell updateBackgroundPercentage:bi_node_load_float(i)];
            }
            if (i->content & BIN_IS_HIDDEN)
                continue;

            if ((i->content & BIN_IS_BOOLEAN) == BIN_IS_BOOLEAN && value) {
                final_str = [NSString
                    stringWithFormat:@"%@\n%@", final_str, _(i->description)];
            } else if ((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT) {
                final_str =
                    [NSString stringWithFormat:@"%@\n%@: %0.2f", final_str,
                                               _(i->description), bi_node_load_float(i)];
            }
            if (i->content & BIN_HAS_UNIT) {
                uint32_t unit = (i->content & BIN_UNIT_BITMASK) >> 6;
                NSString *unit_str =_(bin_unit_strings[unit]);
                final_str =
                    [NSString stringWithFormat:@"%@ %@", final_str, unit_str];
            }
        }
        // Only show in details if is string
    }
    _batteryLabel.text = [final_str substringFromIndex:1];
}

@end
