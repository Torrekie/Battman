#import "BatteryInfoTableViewCell.h"
#include <stdint.h>
#include <stdlib.h>
#include "../common.h"

@implementation BatteryInfoTableViewCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	BatteryCellView *batteryCell = [[BatteryCellView alloc] initWithFrame:CGRectMake(20, 20, 80, 80) foregroundPercentage:0 backgroundPercentage:0];
	batteryCell.translatesAutoresizingMaskIntoConstraints=NO;
	[self.contentView addSubview:batteryCell];
	//[batteryCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:0].active=YES;
	UILabel *batteryRemainingLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 10, 600, 100)];
	batteryRemainingLabel.lineBreakMode = NSLineBreakByWordWrapping;
	batteryRemainingLabel.numberOfLines = 0;
	//batteryRemainingLabel.text=@"Battery Capacity: 80%\nCharge: 50%\nTest: 0%";
	[self.contentView addSubview:batteryRemainingLabel];
	_batteryLabel = batteryRemainingLabel;
	_batteryCell = batteryCell;
	_batteryInfo = NULL;
	return self;
}

- (void)updateBatteryInfo {
	NSString *final_str = @"";
#warning TODO: Turn those magic bitwise to macros
	// TODO: Arabian? We need Arabian hackers to fix this code
	for (struct battery_info_node *i = _batteryInfo; i != NULL; i = i->next) {
		if ((uint64_t)i->content >= 1024) {
			final_str = [NSString stringWithFormat:@"%@\n%@: %s", final_str, _(i->description), (char*)i->content];
		} else if (((uint64_t)i->content & (1 << 9))) {
			// True
			if ((uint64_t)i->content & 1) {
				final_str = [NSString stringWithFormat:@"%@\n%@", final_str, _(i->description)];
			}
		} else {
			uint64_t masked_num = (uint64_t)i->content;
#warning This is not keeping float points
			float val = (masked_num & ((1 << 7) - 1));
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setMinimumFractionDigits:2];
            [numberFormatter setMaximumFractionDigits:2];

            NSMeasurementFormatter *formatter = [[NSMeasurementFormatter alloc] init];
            [formatter setNumberFormatter:numberFormatter];

            // FIXME: i->id is not in header, this is terrible
            if (!strcmp(i->description, "Temperature")) {
                NSMeasurement *temperature = [[NSMeasurement alloc] initWithDoubleValue:val unit:[NSUnitTemperature celsius]];
                final_str = [NSString stringWithFormat:@"%@\n%@: %@", final_str, _(i->description), [formatter stringFromMeasurement:temperature]];
            } else {
                // TODO: format all values base on NSNumberFormatter/NSMeasurementFormatter
                final_str = [NSString stringWithFormat:@"%@\n%@: %0.2f", final_str, _(i->description), val];
            }

            if (masked_num & (1 << 8)) {
				final_str = [final_str stringByAppendingString:@"%"];
				if (masked_num & (1 << 7)) {
					[_batteryCell updateForegroundPercentage:val];
				} else {
					[_batteryCell updateBackgroundPercentage:val];
				}
			}
		}
	}
	_batteryLabel.text = [final_str substringFromIndex:1];
}

- (void)dealloc {
//#warning potential memory leakage
#warning TODO: NO LEAKAGE, if confirmed remove
// Analysis: >1024: malloc()ed ptrs, free
// else: numbers within structs, no free
// then: free structure itself.
	for (struct battery_info_node *i = _batteryInfo; i != NULL; /*i=i->next*/) {
		if ((uint64_t)i->content > 1024) {
			free(i->content);
		}
		void *cur = i;
		i = i->next;
		free(cur);
	}
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

@end
