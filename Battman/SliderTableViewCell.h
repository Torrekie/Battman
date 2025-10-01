//
//  SliderTableViewCell.h
//  Battman
//
//  Created by Torrekie on 2025/5/1.
//

#import <UIKit/UIKit.h>

@protocol SliderTableViewCellDelegate;

@interface SliderTableViewCell : UITableViewCell <UITextFieldDelegate>

@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, weak) id<SliderTableViewCellDelegate> delegate;

// Call this method to dismiss the keyboard programmatically
- (void)dismissKeyboard;

@end

@protocol SliderTableViewCellDelegate <NSObject>
@optional
- (void)sliderTableViewCell:(SliderTableViewCell *)cell didChangeValue:(float)value;
- (void)sliderTableViewCell:(SliderTableViewCell *)cell didEndChangingValue:(float)value;
- (void)sliderTableViewCellDidBeginChanging:(SliderTableViewCell *)cell;
// Called when text field editing begins - implement to add tap gesture to dismiss keyboard
- (void)sliderTableViewCellDidBeginEditing:(SliderTableViewCell *)cell;
// Called when text field editing ends - implement to remove tap gesture
- (void)sliderTableViewCellDidEndEditing:(SliderTableViewCell *)cell;
@end
