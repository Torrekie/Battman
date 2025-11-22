//
//  BrightnessInfoTableViewCell.h
//  Battman
//
//  Created by Torrekie on 2025/10/15.
//

#import <UIKit/UIKit.h>

@interface BrightnessCellView : UIView
- (instancetype)initWithFrame:(CGRect)frame percentage:(CGFloat)percentage;
- (void)updateBrightness:(CGFloat)percentage;
@end

@interface BrightnessInfoTableViewCell : UITableViewCell
@property(nonatomic, strong, readonly) BrightnessCellView *brightnessCell;
@property(nonatomic, strong, readonly) UILabel *brightnessLabel;

- (void)updateBrightnessInfo;

@end
