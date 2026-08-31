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
/// When enabled, the text field and slider expose whole-number values only.
@property (nonatomic) BOOL integerOnly;
/// Value used when editing ends with invalid input. NaN keeps the current slider value.
@property (nonatomic) float invalidInputFallbackValue;

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
