//
//  UITextFieldStepper.m
//  Battman
//
//  Created by Torrekie on 2025/10/22.
//

#import "common.h"
#import "UITextFieldStepper.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <float.h>
#import <QuartzCore/QuartzCore.h>

#if __has_include(<mach-o/loader.h>)
#include <mach-o/loader.h>
#else
#define PLATFORM_IOS 2
#endif

#if __has_include(<mach-o/dyld_priv.h>)
#include <mach-o/dyld_priv.h>
#else
typedef uint32_t dyld_platform_t;
typedef struct {
	dyld_platform_t platform;
	uint32_t        version;
} dyld_build_version_t;
#define DYLD_IOS_VERSION_13_0 0x000D0000
#define dyld_platform_version_iOS_13_0 ({ (dyld_build_version_t){PLATFORM_IOS, DYLD_IOS_VERSION_13_0}; })
extern bool dyld_program_sdk_at_least(dyld_build_version_t);
#endif

#define objc_msgSendSuper_t(RET, ...) ((RET(*)(struct objc_super*, SEL, ##__VA_ARGS__))objc_msgSendSuper)
#define objc_msgSend_t(RET, ...) ((RET(*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

@interface UIImage (Private)
- (instancetype)_resizableImageWithCapMask:(int)mask;
@end
@interface UIView (Private)
@property (nonatomic, readonly, assign) BOOL _shouldReverseLayoutDirection;
- (void)_setCornerRadius:(CGFloat)cornerRadius;
- (CGSize)size;
- (void)setSize:(CGSize)size;
@end
@interface UISegment : UIImageView
@end
@interface UISegmentLabel : UILabel
@end
@interface UISegmentedControl (Private)
+ (CGFloat)_dividerWidthForTraitCollection:(UITraitCollection *)traitCollection size:(NSInteger)size;
+ (CGFloat)_cornerRadiusForTraitCollection:(UITraitCollection *)traitCollection size:(NSInteger)size;
+ (UIImage *)_modernDividerImageBackground:(BOOL)modern traitCollection:(UITraitCollection *)traitCollection tintColor:(UIColor *)tintColor size:(NSInteger)size;
+ (UIImage *)_modernBackgroundSelected:(BOOL) modern disableShadow:(BOOL)disableShadow maximumSize:(CGSize)maximumSize highlighted:(BOOL)highlighted traitCollection:(UITraitCollection *)traitCollection tintColor:(UIColor *)tintColor size:(NSInteger)size;
- (UISegment *)_segmentAtIndex:(NSUInteger)index;
@end
@interface UIStepper (Private)
- (void)_commonStepperInit;
- (CGSize)_intrinsicSizeWithinSize:(CGSize)size;
- (void)_updateDividerImageForButtonState;
- (void)_emitValueChanged;
@end
@interface UIColor ()
+ (instancetype)tableCellBlueTextColor;
@end

UIImage *UIImageFromSegment(UISegmentedControl *segmentedControl, NSUInteger index, CGFloat desiredTotalWidth) {
	if (!segmentedControl) return nil;
	if (index >= segmentedControl.numberOfSegments) return nil;
	
	// Give the control a frame (height: use standard control height if 0)
	CGFloat defaultHeight = 32.0; // typical segmented control height
	CGSize intrinsicSize = [segmentedControl sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
	CGFloat width = (desiredTotalWidth > 0.0) ? desiredTotalWidth : (intrinsicSize.width > 0 ? intrinsicSize.width : segmentedControl.bounds.size.width);
	if (width <= 0) width = 141.0; // fallback
	CGFloat height = (intrinsicSize.height > 0) ? intrinsicSize.height : defaultHeight;
	
	segmentedControl.frame = CGRectMake(0, 0, width, height);
	// Ensure layout (important for proper rendering)
	[segmentedControl setNeedsLayout];
	[segmentedControl layoutIfNeeded];
	[segmentedControl drawRect:CGRectMake(0, 0, width, height)];

	//[segmentedControl drawRect:CGRectMake(0, 0, width, height)];
	return [segmentedControl _segmentAtIndex:index].image;
}


static inline void *object_getIvarAddress(id object, Ivar ivar) {
	return (void *)((uintptr_t)object + ivar_getOffset(ivar));
}

static Class UITextFieldStepperHorizontalVisualElement = nil;

static void UITextFieldStepperHorizontalVisualElement_commonStepperInit(id self, SEL _cmd) {
	if (dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0)) {
		if (@available(iOS 13.0, *)) {
			[(UIView *)self setClipsToBounds:YES];
			[(UIView *)self _setCornerRadius:[UISegmentedControl _cornerRadiusForTraitCollection:[(UIView *)self traitCollection] size:0]];
		}
	}

	BOOL _isRtoL = NO;
	BOOL _shouldReverseLayoutDirection = [(UIView *)self _shouldReverseLayoutDirection];
	NSMutableDictionary *_dividerImages = nil;
	UIImageView *_middleView = nil;
	UIImageView *_leftDividerView = nil;
	UIImageView *_rightDividerView = nil;
	
	void (*object_setBoolIvar)(id, Ivar, BOOL) = (void (*)(id, Ivar, BOOL))object_setIvar;
	Ivar ivar;
	ivar = class_getInstanceVariable([self class], "_isRtoL");
	if (ivar) {
		object_setBoolIvar(self, ivar, _shouldReverseLayoutDirection);
		_isRtoL = *(BOOL *)object_getIvarAddress(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_dividerImages");
	if (ivar) {
		object_setIvar(self, ivar, [[NSMutableDictionary alloc] init]);
		_dividerImages = object_getIvar(self, ivar);
	}
	// Compat
	ivar = class_getInstanceVariable([self class], "_middleView");
	if (ivar) {
		_middleView = [[UIImageView alloc] init];
		object_setIvar(self, ivar, _middleView);
		_middleView = object_getIvar(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_leftDividerView");
	if (ivar) {
		_leftDividerView = [[UIImageView alloc] init];
		object_setIvar(self, ivar, _leftDividerView);
		_leftDividerView = object_getIvar(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_rightDividerView");
	if (ivar) {
		_rightDividerView = [[UIImageView alloc] init];
		object_setIvar(self, ivar, _rightDividerView);
		_rightDividerView = object_getIvar(self, ivar);
	}
	[self addSubview:_middleView];
	[self addSubview:_leftDividerView];
	[self addSubview:_rightDividerView];
	
	id leftButton = ((id (*)(id, SEL, UIButtonType))objc_msgSend)(objc_getClass("_UIStepperButton"), sel_registerName("buttonWithType:"), UIButtonTypeCustom);
	[leftButton setValue:@(YES) forKey:@"left"];
	[leftButton setValue:@(NO) forKey:@"adjustsImageWhenHighlighted"];
	[self addSubview:leftButton];
	
	UITextField *_textField;
	ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		_textField = [[UITextField alloc] init];
		_textField.delegate = (id<UITextFieldDelegate>)self;
		_textField.textAlignment = NSTextAlignmentCenter;
		_textField.borderStyle = UITextBorderStyleNone;
		_textField.backgroundColor = [UIColor clearColor];
		_textField.keyboardType = UIKeyboardTypeDecimalPad;
		_textField.returnKeyType = UIReturnKeyDone;
		if (class_getInstanceVariable([self class], "_minimumValue")) {
			_textField.placeholder = [NSString stringWithFormat:@"%g", *(double *)object_getIvarAddress(self, class_getInstanceVariable([self class], "_minimumValue"))];
		}
		// Set initial text field value to current stepper value
		Ivar valueIvar = class_getInstanceVariable([self class], "_value");
		if (valueIvar) {
			double currentValue = *(double *)object_getIvarAddress(self, valueIvar);
			if (currentValue == floor(currentValue)) {
				_textField.text = [NSString stringWithFormat:@"%.0f", currentValue];
			} else {
				_textField.text = [NSString stringWithFormat:@"%g", currentValue];
			}
		}
		UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
		toolbar.barStyle = UIBarStyleDefault;
		UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:_("Done") style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
		toolbar.items = @[flexSpace, doneButton];
		_textField.inputAccessoryView = toolbar;
		
		object_setIvar(self, ivar, _textField);
		// Don't add text field directly to self on iOS 12 - it will be added to _middleBackground
		if (@available(iOS 13.0, *)) {
			[self addSubview:object_getIvar(self, ivar)];
		}
	}

	id rightButton = ((id (*)(id, SEL, UIButtonType))objc_msgSend)(objc_getClass("_UIStepperButton"), sel_registerName("buttonWithType:"), UIButtonTypeCustom);
	[rightButton setValue:@(NO) forKey:@"left"];
	[rightButton setValue:@(NO) forKey:@"adjustsImageWhenHighlighted"];
	[self addSubview:rightButton];

	UIImageView *_middleBackground;
	ivar = class_getInstanceVariable([self class], "_middleBackground");
	if (ivar) {
		_middleBackground = [[UIImageView alloc] init];
		object_setIvar(self, ivar, _middleBackground);
		_middleBackground = object_getIvar(self, ivar);
		
		if (@available(iOS 13.0, *)) {
			// iOS 13+ uses modern styling - will be set in layout
		} else {
			_middleBackground.backgroundColor = [UIColor clearColor];
			// Enable user interaction so the text field can receive touches
			_middleBackground.userInteractionEnabled = YES;
			// Add the text field as a subview of the middle background
			if (_textField) {
				_textField.backgroundColor = [UIColor clearColor];
				[_middleBackground addSubview:_textField];
			}
		}
	}
	[self addSubview:_middleBackground];

	if (_isRtoL) {
		ivar = class_getInstanceVariable([self class], "_plusButton");
		if (ivar) {
			object_setIvar(self, ivar, leftButton);
		}
		ivar = class_getInstanceVariable([self class], "_minusButton");
		if (ivar) {
			object_setIvar(self, ivar, rightButton);
		}
	} else {
		ivar = class_getInstanceVariable([self class], "_plusButton");
		if (ivar) {
			object_setIvar(self, ivar, rightButton);
		}
		ivar = class_getInstanceVariable([self class], "_minusButton");
		if (ivar) {
			object_setIvar(self, ivar, leftButton);
		}
	}
	
	[self setBackgroundImage:nil forState:UIControlStateNormal];
	[self setBackgroundImage:nil forState:UIControlStateDisabled];
	[self setBackgroundImage:nil forState:UIControlStateHighlighted | UIControlStateDisabled]; // WHAT
	[self setBackgroundImage:nil forState:UIControlStateHighlighted];

	if (!dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0))
		if (@available(iOS 13.0, *))
			[self _updateBackgroundForButtonState];
	
	[self setDividerImage:nil forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal];
	[self setDividerImage:nil forLeftSegmentState:UIControlStateHighlighted rightSegmentState:UIControlStateNormal];
	[self setDividerImage:nil forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateHighlighted];
	
	[self setIncrementImage:nil forState:UIControlStateNormal];
	[self setDecrementImage:nil forState:UIControlStateNormal];

	if (@available(iOS 13.0, *)) {
		// Nothing
	} else {
		[self setCharge:-0.3];
		void (*object_setBoolIvar)(id, Ivar, BOOL) = (void (*)(id, Ivar, BOOL))object_setIvar;
		void (*object_setDoubleIvar)(id, Ivar, CGFloat) = (void (*)(id, Ivar, CGFloat))object_setIvar;
		ivar = class_getInstanceVariable([self class], "_maximumValue");
		if (ivar)
			object_setDoubleIvar(self, ivar, 100.0);
		ivar = class_getInstanceVariable([self class], "_stepValue");
		if (ivar)
			object_setDoubleIvar(self, ivar, 1.0);
		ivar = class_getInstanceVariable([self class], "_continuous");
		if (ivar)
			object_setBoolIvar(self, ivar, YES);
		ivar = class_getInstanceVariable([self class], "_autorepeat");
		if (ivar)
			object_setBoolIvar(self, ivar, YES);
	}
}

void UITextFieldStepperHorizontalVisualElement_layoutSubviews(UIView *self, SEL _cmd) {
	struct objc_super super = {self, class_getSuperclass([self class])};
	objc_msgSendSuper_t(void)(&super, _cmd);
	BOOL _shouldReverseLayoutDirection = NO;

	if ([UIView respondsToSelector:@selector(_shouldReverseLayoutDirection)]) {
		_shouldReverseLayoutDirection = [self _shouldReverseLayoutDirection];
	}

	BOOL _isRtoL = NO;
	id _plusButton = nil;
	id _minusButton = nil;
	Ivar ivar;
	void (*object_setBoolIvar)(id, Ivar, BOOL) = (void (*)(id, Ivar, BOOL))object_setIvar;
	ivar = class_getInstanceVariable([self class], "_isRtoL");
	if (ivar) {
		object_setBoolIvar(self, ivar, _shouldReverseLayoutDirection);
		_isRtoL = *(BOOL *)object_getIvarAddress(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_plusButton");
	if (ivar) {
		_plusButton = object_getIvar(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_minusButton");
	if (ivar) {
		_minusButton = object_getIvar(self, ivar);
	}

	if (_isRtoL != _shouldReverseLayoutDirection) {
		_isRtoL = _shouldReverseLayoutDirection;
		if (_isRtoL) {
			[_plusButton setValue:@(YES) forKey:@"left"];
			[_minusButton setValue:@(NO) forKey:@"left"];
		} else {
			[_plusButton setValue:@(NO) forKey:@"left"];
			[_minusButton setValue:@(YES) forKey:@"left"];
		}
	}
	UIButton *leftButton  = _isRtoL ? _plusButton : _minusButton;
	UIButton *rightButton = _isRtoL ? _minusButton : _plusButton;

	UIControlState values[2] = {UIControlStateNormal, UIControlStateNormal};
	NSValue *dividerKey = [NSValue valueWithBytes:(void *)values objCType:"{?=QQ}"];

	NSMutableDictionary *_dividerImages = nil;
	ivar = class_getInstanceVariable([self class], "_dividerImages");
	if (ivar) {
		_dividerImages = object_getIvar(self, ivar);
	}

	UIImage *dividerImage = nil;
	CGFloat dividerWidth = 0;
	if (_dividerImages) {
		@try {
			dividerImage = [_dividerImages objectForKey:dividerKey];
		} @catch (NSException *exc) {
			dividerImage = nil;
		}
	}
	if (dividerImage) {
		dividerWidth = dividerImage.size.width;
	} else if (dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0)) {
		dividerWidth = [UISegmentedControl _dividerWidthForTraitCollection:[self traitCollection] size:0];
	}

	CGSize fitSize = [self sizeThatFits:[self size]];
	CGFloat buttonWidth = (fitSize.width - dividerWidth - dividerWidth) / 3.0;
	// [-]|[0]|[+]
	// [-]
	leftButton.frame = CGRectMake(0, 0, buttonWidth, fitSize.height);
	// [---------]
	//         [+]
	rightButton.frame = CGRectMake((dividerWidth + buttonWidth) * 2, 0, fitSize.width - (dividerWidth + buttonWidth) * 2, fitSize.height);
	
	UITextField *_textField = nil;
	UIImageView *_middleBackground = nil;
	ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		_textField = object_getIvar(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_middleBackground");
	if (ivar) {
		_middleBackground = object_getIvar(self, ivar);
	}
	// [---------]
	//     [0]
	if (@available(iOS 13.0, *)) {
		// iOS 13+: Text field is direct child of self
		if (_textField) {
			_textField.frame = CGRectMake(buttonWidth + dividerWidth, 0, buttonWidth, fitSize.height);
		}
	} else {
		// iOS 12: Text field is child of middle background
		if (_middleBackground) {
			_middleBackground.frame = CGRectMake(buttonWidth + dividerWidth, 0, buttonWidth, fitSize.height);
			if (_textField) {
				_textField.frame = CGRectMake(0, 0, buttonWidth, fitSize.height);
			}
		}
	}

	// Middle line
	ivar = class_getInstanceVariable([self class], "_middleView");
	if (ivar) {
		UIImageView *_middleView = object_getIvar(self, ivar);
		
		Ivar _leftDividerIvar = class_getInstanceVariable([self class], "_leftDividerView");
		if (_leftDividerIvar) {
			UIImageView *_leftDividerView = object_getIvar(self, _leftDividerIvar);
			if (_leftDividerView) {
				// [-]|[0]|[+]
				//    |
				_leftDividerView.frame = CGRectMake(buttonWidth, 0.0, dividerWidth, fitSize.height);
			}
		}
		Ivar _rightDividerIvar = class_getInstanceVariable([self class], "_rightDividerView");
		if (_rightDividerIvar) {
			UIImageView *_rightDividerView = object_getIvar(self, _rightDividerIvar);
			if (_rightDividerView) {
				// [-]|[0]|[+]
				//        |
				_rightDividerView.frame = CGRectMake(buttonWidth * 2 + dividerWidth, 0.0, dividerWidth, fitSize.height);
			}
		}
		
		// Hide the middle view since we're using the dividers instead
		// Kept for compat
		_middleView.hidden = YES;
	}

	if (dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0)) {
		if (@available(iOS 13.0, *)) {
			// Left
			ivar = class_getInstanceVariable([self class], "_leftBackground");
			if (ivar) {
				// [L]|[0]|[R]
				// [L]
				[(UIView *)object_getIvar(self, ivar) setFrame:CGRectMake(0.0, 0.0, buttonWidth, fitSize.height)];
			}
			CGFloat leftAlpha = 0;
			UIImageView *_leftHighlight = nil;
			ivar = class_getInstanceVariable([self class], "_leftHighlight");
			if (ivar) {
				_leftHighlight = object_getIvar(self, ivar);
				leftAlpha = [_leftHighlight alpha];
			}
			CGRect leftAlphaFrame;
			if (leftAlpha != 0.0) {
				leftAlphaFrame = objc_msgSend_t(CGRect)(self, sel_registerName("_leftHighlightFrame"));
			} else {
				leftAlphaFrame = objc_msgSend_t(CGRect)(self, sel_registerName("_leftHighlightInsetFrame"));
			}
			UIViewPropertyAnimator *_leftAlphaAnimator = nil;
			ivar = class_getInstanceVariable([self class], "_leftAlphaAnimator");
			if (ivar) {
				_leftAlphaAnimator = object_getIvar(self, ivar);
			}
			if (_leftAlphaAnimator && [_leftAlphaAnimator state] != UIViewAnimatingStateActive) {
				if (!CGRectEqualToRect(_leftHighlight.frame, leftAlphaFrame))
					_leftHighlight.frame = leftAlphaFrame;
			}
			
			// Right
			ivar = class_getInstanceVariable([self class], "_rightBackground");
			if (ivar) {
				// [L]|[0]|[R]
				//         [R]
				[(UIView *)object_getIvar(self, ivar) setFrame:CGRectMake((dividerWidth + buttonWidth) * 2, 0.0, fitSize.width - buttonWidth - dividerWidth, fitSize.height)];
			}
			CGFloat rightAlpha = 0;
			UIImageView *_rightHighlight = nil;
			ivar = class_getInstanceVariable([self class], "_rightHighlight");
			if (ivar) {
				_rightHighlight = object_getIvar(self, ivar);
				rightAlpha = [_rightHighlight alpha];
			}
			CGRect rightAlphaFrame;
			if (rightAlpha != 0.0) {
				rightAlphaFrame = objc_msgSend_t(CGRect)(self, sel_registerName("_rightHighlightFrame"));
			} else {
				rightAlphaFrame = objc_msgSend_t(CGRect)(self, sel_registerName("_rightHighlightInsetFrame"));
			}
			UIViewPropertyAnimator *_rightAlphaAnimator = nil;
			ivar = class_getInstanceVariable([self class], "_rightAlphaAnimator");
			if (ivar) {
				_rightAlphaAnimator = object_getIvar(self, ivar);
			}
			if (_rightAlphaAnimator && [_rightAlphaAnimator state] != UIViewAnimatingStateActive) {
				if (!CGRectEqualToRect(_rightHighlight.frame, rightAlphaFrame))
					_rightHighlight.frame = rightAlphaFrame;
			}

			UIImageView *_middleBackground = nil;
			ivar = class_getInstanceVariable([self class], "_middleBackground");
			if (ivar) {
				_middleBackground = object_getIvar(self, ivar);
			}
			// [---------]
			//     [0]
			if (_middleBackground) {
				_middleBackground.frame = CGRectMake(buttonWidth, 0, buttonWidth + (dividerWidth * 2), fitSize.height);
				_middleBackground.image = [[UISegmentedControl _modernBackgroundSelected:NO disableShadow:NO maximumSize:CGSizeMake(46.5 + 1 + 46.5 + 1 + 46.5, dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0) ? 32.0 : 28.0) highlighted:NO traitCollection:[self traitCollection] tintColor:nil size:0] _resizableImageWithCapMask:010];
			}
		}
		[self setSize:CGSizeMake(fitSize.width, fitSize.height)];
	}
}

void UITextFieldStepperHorizontalVisualElement_setValue(UIView *self, SEL _cmd, double value) {
	// Call the parent implementation first
	struct objc_super super = {self, class_getSuperclass([self class])};
	objc_msgSendSuper_t(void, double)(&super, _cmd, value);
	
	// Update the text field to reflect the new value
	Ivar ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		UITextField *_textField = object_getIvar(self, ivar);
		if (_textField) {
			// Format the value appropriately
			if (value == floor(value)) {
				_textField.text = [NSString stringWithFormat:@"%.0f", value];
			} else {
				_textField.text = [NSString stringWithFormat:@"%g", value];
			}
		}
	}
}

void UITextFieldStepperHorizontalVisualElement_visualElementDidSetValue(UIView *self, SEL _cmd, id arg1) {
	// This method is called by the stepper control when the value changes
	// Get the current value from the parent class
	double currentValue = objc_msgSend_t(double)(self, sel_registerName("value"));
	
	// Update the text field
	Ivar ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		UITextField *_textField = object_getIvar(self, ivar);
		if (_textField) {
			// Format the value appropriately
			if (currentValue == floor(currentValue)) {
				_textField.text = [NSString stringWithFormat:@"%.0f", currentValue];
			} else {
				_textField.text = [NSString stringWithFormat:@"%g", currentValue];
			}
		}
	}
}

BOOL UITextFieldStepperHorizontalVisualElement_textFieldShouldReturn(UIView *self, SEL _cmd, UITextField *textField) {
	[textField resignFirstResponder];
	return YES;
}

void UITextFieldStepperHorizontalVisualElement_textFieldDidEndEditing(UIView *self, SEL _cmd, UITextField *textField) {
	// Get the text field's value and update the stepper
	NSString *text = textField.text;
	if (text && text.length > 0) {
		double newValue = [text doubleValue];
		
		// Get the stepper's constraints and properties
		double minValue = objc_msgSend_t(double)(self, sel_registerName("minimumValue"));
		double maxValue = objc_msgSend_t(double)(self, sel_registerName("maximumValue"));
		double stepValue = objc_msgSend_t(double)(self, sel_registerName("stepValue"));
		BOOL wraps = objc_msgSend_t(BOOL)(self, sel_registerName("wraps"));
		
		// Handle wrapping behavior
		if (wraps) {
			if (newValue > maxValue) {
				// Wrap to minimum value
				double range = maxValue - minValue;
				newValue = minValue + fmod(newValue - minValue, range + stepValue);
			} else if (newValue < minValue) {
				// Wrap to maximum value
				double range = maxValue - minValue;
				newValue = maxValue - fmod(minValue - newValue, range + stepValue);
			}
		} else {
			// Clamp the value to the stepper's range
			if (newValue < minValue) {
				newValue = minValue;
			} else if (newValue > maxValue) {
				newValue = maxValue;
			}
		}
		
		// Respect stepValue - round to nearest valid step
		if (stepValue > 0) {
			double stepsFromMin = round((newValue - minValue) / stepValue);
			newValue = minValue + (stepsFromMin * stepValue);
			
			// Ensure we're still within bounds after step adjustment
			if (!wraps) {
				if (newValue < minValue) newValue = minValue;
				if (newValue > maxValue) newValue = maxValue;
			}
		}
		
		// Only update if the value actually changed
		double currentValue = objc_msgSend_t(double)(self, sel_registerName("value"));
		if (fabs(newValue - currentValue) > DBL_EPSILON) {
			// Set the stepper's value (this will trigger our setValue method)
			objc_msgSend_t(void, double)(self, sel_registerName("setValue:"), newValue);
			
			// Trigger UIControlEventValueChanged for the stepper control
			if ([self isKindOfClass:NSClassFromString(@"UITextFieldStepper")]) {
				objc_msgSend_t(void, UIControlEvents)(self, sel_registerName("sendActionsForControlEvents:"), UIControlEventValueChanged);
			}
			
			// Notify the stepper control of the value change
			Ivar stepperControlIvar = class_getInstanceVariable([self class], "_stepperControl");
			if (stepperControlIvar) {
				id<UIStepperControl> stepperControl = object_getIvar(self, stepperControlIvar);
				if (stepperControl && [(NSObject *)stepperControl respondsToSelector:@selector(visualElementSendValueChangedEvent:)]) {
					[stepperControl visualElementSendValueChangedEvent:self];
				}
				if (stepperControl && [(NSObject *)stepperControl respondsToSelector:@selector(sendActionsForControlEvents:)]) {
					[(UIControl *)stepperControl sendActionsForControlEvents:UIControlEventValueChanged];
				}
			}
		} else {
			// Value didn't change, but we should still update the text field to show the correct format
			Ivar ivar = class_getInstanceVariable([self class], "_textField");
			if (ivar) {
				UITextField *_textField = object_getIvar(self, ivar);
				if (_textField) {
					if (currentValue == floor(currentValue)) {
						_textField.text = [NSString stringWithFormat:@"%.0f", currentValue];
					} else {
						_textField.text = [NSString stringWithFormat:@"%g", currentValue];
					}
				}
			}
		}
	} else {
		// Text field is empty, revert to current stepper value
		double currentValue = objc_msgSend_t(double)(self, sel_registerName("value"));
		if (currentValue == floor(currentValue)) {
			textField.text = [NSString stringWithFormat:@"%.0f", currentValue];
		} else {
			textField.text = [NSString stringWithFormat:@"%g", currentValue];
		}
	}
}

void UITextFieldStepperHorizontalVisualElement_updateDividerImageForButtonState(UIView *self, SEL _cmd) {
	BOOL _isRtoL = NO;
	Ivar ivar;
	id _plusButton, _minusButton;
	ivar = class_getInstanceVariable([self class], "_isRtoL");
	if (ivar) {
		_isRtoL = *(BOOL *)object_getIvarAddress(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_plusButton");
	if (ivar) {
		_plusButton = object_getIvar(self, ivar);
	}
	ivar = class_getInstanceVariable([self class], "_minusButton");
	if (ivar) {
		_minusButton = object_getIvar(self, ivar);
	}

	UIButton *leftButton  = _isRtoL ? _plusButton : _minusButton;
	UIButton *rightButton = _isRtoL ? _minusButton : _plusButton;
	
	UIImageView *_middleView = nil;
	UIImageView *_middleImageView = nil;
	ivar = class_getInstanceVariable([self class], "_middleView");
	if (ivar) {
		// _middleView: [UIImageView, _UIImageViewOverlayView]
		_middleView = object_getIvar(self, ivar);
		_middleImageView = [_middleView.subviews firstObject];
	}

	UIImageView *_leftDividerView = nil;
	UIImageView *_leftDividerImageView = nil;
	ivar = class_getInstanceVariable([self class], "_leftDividerView");
	if (ivar) {
		_leftDividerView = object_getIvar(self, ivar);
		id tmp = [_leftDividerView.subviews firstObject];
		if ([tmp isKindOfClass:[UIImageView class]])
			_leftDividerImageView = tmp;
	}
	UIImageView *_rightDividerView = nil;
	UIImageView *_rightDividerImageView = nil;
	ivar = class_getInstanceVariable([self class], "_rightDividerView");
	if (ivar) {
		_rightDividerView = object_getIvar(self, ivar);
		id tmp = [_rightDividerView.subviews firstObject];
		if ([tmp isKindOfClass:[UIImageView class]])
			_rightDividerImageView = tmp;
	}

	UIImage *dividerImage = ((UIImage *(*)(id, SEL, UIControlState, UIControlState))objc_msgSend)(self, sel_registerName("dividerImageForLeftSegmentState:rightSegmentState:"), leftButton.state, rightButton.state);
	if (dividerImage || !dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0)) {
		if (_middleImageView)
			[_middleImageView removeFromSuperview];
		_middleView.image = dividerImage;
		if (_leftDividerImageView)
			[_leftDividerImageView removeFromSuperview];
		_leftDividerView.image = dividerImage;
		if (_rightDividerImageView)
			[_rightDividerImageView removeFromSuperview];
		_rightDividerView.image = dividerImage;
	} else if (@available(iOS 13.0, *)) {
		UIImage *modernBackground = [UISegmentedControl _modernDividerImageBackground:YES traitCollection:[self traitCollection] tintColor:nil size:0];
		UIImage *background = [UISegmentedControl _modernDividerImageBackground:NO traitCollection:[self traitCollection] tintColor:nil size:0];
		_middleView.image = modernBackground;
		if (_middleImageView) {
			_middleImageView.image = background;
		} else {
			_middleImageView = [[UIImageView alloc] initWithFrame:_middleView.bounds];
			_middleImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			_middleImageView.image = background;
			[_middleView insertSubview:_middleImageView atIndex:0];
		}
		if (_leftDividerImageView) {
			_leftDividerImageView.image = background;
		} else {
			_leftDividerImageView = [[UIImageView alloc] initWithFrame:_leftDividerView.bounds];
			_leftDividerImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			_leftDividerImageView.image = background;
			[_leftDividerView insertSubview:_leftDividerImageView atIndex:0];
		}
		if (_rightDividerImageView) {
			_rightDividerImageView.image = background;
		} else {
			_rightDividerImageView = [[UIImageView alloc] initWithFrame:_rightDividerView.bounds];
			_rightDividerImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			_rightDividerImageView.image = background;
			[_rightDividerView insertSubview:_rightDividerImageView atIndex:0];
		}
	}
}

CGSize UITextFieldStepperHorizontalVisualElement_intrinsicSizeWithinSize(UIView *self, SEL _cmd, CGSize size) {
	UIImage *plusButtonImage = nil;
	UIImage *minusButtonImage = nil;
	Ivar ivar = NULL;
	ivar = class_getInstanceVariable([self class], "_plusButton");
	if (ivar) {
		plusButtonImage = [(UIButton *)object_getIvar(self, ivar) backgroundImageForState:UIControlStateNormal];
	}
	ivar = class_getInstanceVariable([self class], "_minusButton");
	if (ivar) {
		minusButtonImage = [(UIButton *)object_getIvar(self, ivar) backgroundImageForState:UIControlStateNormal];
	}

	CGFloat width = fmax(plusButtonImage.size.width + minusButtonImage.size.width, 46.5 + 1 + 46.5 + 1 + 46.5);
	CGFloat height = 32.0;
	extern BOOL _UIApplicationUsesLegacyUI(void);
	if (!dyld_program_sdk_at_least(dyld_platform_version_iOS_13_0) || _UIApplicationUsesLegacyUI()) {
		height = 28.0;
	}

	if (height < plusButtonImage.size.height)
		height = plusButtonImage.size.height;

	return CGSizeMake(width, height);
}

void UITextFieldStepperHorizontalVisualElement_dismissKeyboard(UIView *self, SEL _cmd) {
	Ivar ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		[(UITextField *)object_getIvar(self, ivar) resignFirstResponder];
	}
}

void tfclean(id self, SEL _cmd) {
	Ivar ivar = class_getInstanceVariable([self class], "_textField");
	if (ivar) {
		UITextField *textField = object_getIvar(self, ivar);
		if (textField) {
			textField.delegate = nil;
			textField.inputAccessoryView = nil; // Remove toolbar to break target retain cycle
		}
	}
}

void UITextFieldStepperHorizontalVisualElement_dealloc(UIView *self, SEL _cmd) {
	tfclean(self, _cmd);

//	struct objc_super super = {self, class_getSuperclass([self class])};
//	objc_msgSendSuper_t(void)(&super, _cmd);
}

@implementation UITextFieldStepper

+ (void)load {
	// iOS 13+ UIStepper: [UIStepperHorizontalVisualElement]
	if (@available(iOS 13.0, *))
		UITextFieldStepperHorizontalVisualElement_init();
}

- (void)dealloc {
	tfclean(self, _cmd);
}

// iOS 13+
+ (Class)visualElementClassForTraitCollection:(UITraitCollection *)traitCollection {
	return [UITextFieldStepperHorizontalVisualElement class];
}

// iOS 13+
+ (UIView *)visualElementForTraitCollection:(UITraitCollection *)traitCollection {
	return [[UITextFieldStepper visualElementClassForTraitCollection:traitCollection] new];
}

- (void)_commonStepperInit {
	if (@available(iOS 13.0, *)) {
		// Handled by UITextFieldStepperHorizontalVisualElement
		if ([super respondsToSelector:_cmd]) {
			return [super _commonStepperInit];
		}
	} else {
		return UITextFieldStepperHorizontalVisualElement_commonStepperInit(self, _cmd);
	}
}

- (void)layoutSubviews {
	if (@available(iOS 13.0, *)) {
		// Handled by UITextFieldStepperHorizontalVisualElement
		if ([super respondsToSelector:_cmd]) {
			return [super layoutSubviews];
		}
	} else {
		return UITextFieldStepperHorizontalVisualElement_layoutSubviews(self, _cmd);
	}
}

- (void)didMoveToSuperview {
	[super didMoveToSuperview];
	
	// Clean up when removed from superview
	if (self.superview == nil) {
		tfclean(self, _cmd);
		return;
	}
	
	if (@available(iOS 13.0, *)) {
	} else {
		UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"L", @"", @"R"]];
		UIImage *img = UIImageFromSegment(seg, 1, 141);
		// Use weak reference to avoid retain cycle in dispatch block
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (strongSelf) {
				Ivar ivar = class_getInstanceVariable([strongSelf class], "_middleBackground");
				if (ivar)
					[object_getIvar(strongSelf, ivar) setImage:img];
			}
		});
	}
}

- (CGSize)_intrinsicSizeWithinSize:(CGSize)size {
	if (@available(iOS 13.0, *)) {
		// Handled by UITextFieldStepperHorizontalVisualElement
		if ([super respondsToSelector:_cmd]) {
			return [super _intrinsicSizeWithinSize:size];
		}
	} else {
		return UITextFieldStepperHorizontalVisualElement_intrinsicSizeWithinSize(self, _cmd, size);
	}
	return size;
}

- (void)_updateDividerImageForButtonState {
	if (@available(iOS 13.0, *)) {
		// Handled by UITextFieldStepperHorizontalVisualElement
		if ([super respondsToSelector:_cmd]) {
			return [super _updateDividerImageForButtonState];
		}
	} else {
		return UITextFieldStepperHorizontalVisualElement_updateDividerImageForButtonState(self, _cmd);
	}
}

- (void)setValue:(double)value {
	return UITextFieldStepperHorizontalVisualElement_setValue(self, _cmd, value);
}

- (void)_emitValueChanged {
	if ([super respondsToSelector:_cmd]) {
		[super _emitValueChanged];
	}

	if (@available(iOS 13.0, *)) {
	} else {
		return UITextFieldStepperHorizontalVisualElement_visualElementDidSetValue(self, _cmd, nil);
	}
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	return UITextFieldStepperHorizontalVisualElement_textFieldShouldReturn(self, _cmd, textField);
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	return UITextFieldStepperHorizontalVisualElement_textFieldDidEndEditing(self, _cmd, textField);
}

- (void)dismissKeyboard {
	return UITextFieldStepperHorizontalVisualElement_dismissKeyboard(self, _cmd);
}

@end

void UITextFieldStepperHorizontalVisualElement_init(void) {
	// Check if class already exists
	if (UITextFieldStepperHorizontalVisualElement != nil) {
		return;
	}
	
	Class parentClass = objc_getClass("UIStepperHorizontalVisualElement");
	if (!parentClass) {
		NSLog(@"Error: UIStepperHorizontalVisualElement parent class not found");
		return;
	}

	typedef struct ivar_UITextFieldStepperHorizontalVisualElement {
		UITextField *_textField;
		UIImageView *_middleBackground;
		UIImageView *_leftDividerView;
		UIImageView *_rightDividerView;
	} ivar_UITextFieldStepperHorizontalVisualElement;
	
	UITextFieldStepperHorizontalVisualElement = objc_allocateClassPair(parentClass, "UITextFieldStepperHorizontalVisualElement", sizeof(struct ivar_UITextFieldStepperHorizontalVisualElement));
	
	if (!UITextFieldStepperHorizontalVisualElement) {
		NSLog(@"Error: Failed to allocate class pair for UITextFieldStepperHorizontalVisualElement");
		return;
	}

	BOOL success = YES;
	success &= class_addIvar(UITextFieldStepperHorizontalVisualElement, "_textField", sizeof(UITextField *), log2(sizeof(UITextField *)), "@\"UITextField\"");
	success &= class_addIvar(UITextFieldStepperHorizontalVisualElement, "_middleBackground", sizeof(UIImageView *), log2(sizeof(UIImageView *)), "@\"UIImageView\"");
	success &= class_addIvar(UITextFieldStepperHorizontalVisualElement, "_leftDividerView", sizeof(UIImageView *), log2(sizeof(UIImageView *)), "@\"UIImageView\"");
	success &= class_addIvar(UITextFieldStepperHorizontalVisualElement, "_rightDividerView", sizeof(UIImageView *), log2(sizeof(UIImageView *)), "@\"UIImageView\"");
	
	if (!success) {
		NSLog(@"Error: Failed to add instance variables to UITextFieldStepperHorizontalVisualElement");
		return;
	}

	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("_commonStepperInit"), (IMP)UITextFieldStepperHorizontalVisualElement_commonStepperInit, "v@:");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("layoutSubviews"), (IMP)UITextFieldStepperHorizontalVisualElement_layoutSubviews, "v@:");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("_updateDividerImageForButtonState"), (IMP)UITextFieldStepperHorizontalVisualElement_updateDividerImageForButtonState, "v@:");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("_intrinsicSizeWithinSize:"), (IMP)UITextFieldStepperHorizontalVisualElement_intrinsicSizeWithinSize, "{CGSize=dd}32@0:8{CGSize=dd}16");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("setValue:"), (IMP)UITextFieldStepperHorizontalVisualElement_setValue, "v@:d");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("visualElementDidSetValue:"), (IMP)UITextFieldStepperHorizontalVisualElement_visualElementDidSetValue, "v@:@");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("textFieldShouldReturn:"), (IMP)UITextFieldStepperHorizontalVisualElement_textFieldShouldReturn, "B@:@");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("textFieldDidEndEditing:"), (IMP)UITextFieldStepperHorizontalVisualElement_textFieldDidEndEditing, "v@:@");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("dismissKeyboard"), (IMP)UITextFieldStepperHorizontalVisualElement_dismissKeyboard, "v@:@");
	success &= class_addMethod(UITextFieldStepperHorizontalVisualElement, sel_registerName("dealloc"), (IMP)UITextFieldStepperHorizontalVisualElement_dealloc, "v@:");
	
	if (!success) {
		NSLog(@"Error: Failed to add methods to UITextFieldStepperHorizontalVisualElement");
		return;
	}
	
	objc_registerClassPair(UITextFieldStepperHorizontalVisualElement);
}
