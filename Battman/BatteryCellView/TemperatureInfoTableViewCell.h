#include "../battery_utils/battery_info.h"
#import "BatteryCellView.h"
#import <UIKit/UIKit.h>

@interface TemperatureCellView : UIView
- (instancetype)initWithFrame:(CGRect)frame percentage:(CGFloat)percentage;
- (void)updatePercentage:(CGFloat)percentage;
- (void)updatePercentage:(CGFloat)percentage duration:(NSTimeInterval)duration;
@end

@interface TemperatureInfoTableViewCell : UITableViewCell
@property(nonatomic, strong, readonly) TemperatureCellView *temperatureCell;
@property(nonatomic, strong, readonly) UILabel *temperatureLabel;

- (void)updateTemperatureInfo;

@end
