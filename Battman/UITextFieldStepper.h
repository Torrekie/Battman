//
//  UITextFieldStepper.h
//  Battman
//
//  Created by Torrekie on 2025/10/22.
//

#import <UIKit/UIKit.h>

@protocol UIStepperControl
@required
- (void)visualElementDidSetValue:(id)arg1;
- (void)visualElementSendValueChangedEvent:(id)arg1;
@end

// Private
@interface UIStepperHorizontalVisualElement : UIView /*{
	BOOL _isRtoL;
	UIImageView *_leftBackground;
	UIImageView *_rightBackground;
	UIImageView *_leftHighlight;
	UIImageView *_rightHighlight;
	UIImageView *_middleView;
	UIButton __strong *_plusButton;
	UIButton *_minusButton;
	NSTimer *_repeatTimer;
	long long _repeatCount;
	NSMutableDictionary *_dividerImages;
	UIViewPropertyAnimator *_leftAlphaAnimator;
	UIViewPropertyAnimator *_rightAlphaAnimator;
	UIViewPropertyAnimator *_leftFrameAnimator;
	UIViewPropertyAnimator *_rightFrameAnimator;
	BOOL _autorepeat;
	BOOL _continuous;
	BOOL _enabled;
	BOOL _wraps;
	double _value;
	double _maximumValue;
	double _minimumValue;
	id<UIStepperControl> _stepperControl;
	double _stepValue;
}
@property (nonatomic, assign) CGFloat value;
@property (nonatomic, assign) CGFloat minimumValue;
@property (nonatomic, assign) CGFloat maximumValue;
@property (nonatomic, assign) CGFloat stepValue;
@property (nonatomic, assign, getter=isContinuous) BOOL continuous;
@property (nonatomic, assign) BOOL wraps;
@property (nonatomic, assign) BOOL autorepeat;
@property (nonatomic, weak) id<UIStepperControl> stepperControl;
*/
- (void)setBackgroundImage:(UIImage *)image forState:(UIControlState)state;
- (void)_updateBackgroundForButtonState;
- (void)setDividerImage:(UIImage *)image forLeftSegmentState:(UIControlState)leftState rightSegmentState:(UIControlState)rightState;
- (void)setIncrementImage:(UIImage *)image forState:(UIControlState)state;
- (void)setDecrementImage:(UIImage *)image forState:(UIControlState)state;
@end

@interface _UIStepperButton : UIButton
@property (nonatomic, assign, getter=isLeft) BOOL left;
@end

/*
@interface UITextFieldStepperHorizontalVisualElement : UIStepperHorizontalVisualElement <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *textField;
@end
 */

@interface UITextFieldStepper : UIStepper <UITextFieldDelegate> {
	UITextField *_textField;
	UIImageView *_middleBackground;
	UIImageView *_leftDividerView;
	UIImageView *_rightDividerView;
}
@end

// Initialize the runtime class
void UITextFieldStepperHorizontalVisualElement_init(void);
