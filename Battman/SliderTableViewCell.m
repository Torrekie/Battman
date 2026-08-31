//
//  SliderTableViewCell.m
//  Battman
//
//  Created by Torrekie on 2025/5/1.
//

#import "common.h"
#import "SliderTableViewCell.h"
#include <float.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>

static BOOL SLStringIsASCIIInteger(NSString *value, unsigned long long *result) {
    if (!value.length)
        return NO;

    unsigned long long parsed = 0;
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if (character < '0' || character > '9')
            return NO;
        unsigned int digit = character - '0';
        if (parsed > (ULLONG_MAX - digit) / 10)
            return NO;
        parsed = parsed * 10 + digit;
    }
    if (result)
        *result = parsed;
    return YES;
}

static float SLClampedValue(UISlider *slider, float value, BOOL integerOnly) {
	if (!isfinite(value))
		value = slider.minimumValue;
	value = fminf(fmaxf(value, slider.minimumValue), slider.maximumValue);
	if (!integerOnly)
		return value;
	/* Rounding can cross a non-integral slider bound (for example a maximum of
	 * 0.5). Clamp once more so every path, including pasted values, stays in
	 * the advertised range. */
	value = roundf(value);
	return fminf(fmaxf(value, slider.minimumValue), slider.maximumValue);
}

@implementation SliderTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        _integerOnly = NO;
        _invalidInputFallbackValue = NAN;
        // Create slider
        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        [_slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
		[_slider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
		[_slider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [self.contentView addSubview:_slider];
        
        // Create text field
        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.textAlignment = NSTextAlignmentCenter;
        _textField.keyboardType = UIKeyboardTypeDecimalPad;
        _textField.returnKeyType = UIReturnKeyDone;
        _textField.placeholder = @"0";
        _textField.delegate = self;
        
        // Add toolbar with Done button for decimal pad keyboard
        UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
        toolbar.barStyle = UIBarStyleDefault;
        UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
		//UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
		UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:_("Done") style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
        toolbar.items = @[flexSpace, doneButton];
        _textField.inputAccessoryView = toolbar;
        
        [self.contentView addSubview:_textField];
        
        // Add notification observer for when keyboard should be dismissed
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
        
        // Layout constraints for slider and text field
        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.slider.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [self.slider.trailingAnchor constraintEqualToAnchor:_textField.leadingAnchor constant:-10],
            [self.slider.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            
            [self.textField.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [self.textField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.textField.widthAnchor constraintEqualToConstant:60]
        ]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setIntegerOnly:(BOOL)integerOnly {
    _integerOnly = integerOnly;
    self.textField.keyboardType = integerOnly ? UIKeyboardTypeNumberPad : UIKeyboardTypeDecimalPad;
    if (integerOnly)
        self.slider.value = SLClampedValue(self.slider, self.slider.value, YES);
}

- (void)sliderValueChanged:(UISlider *)sender {
    // Update text field when slider value changes
    float value = SLClampedValue(sender, sender.value, self.integerOnly);
    sender.value = value;
    self.textField.text = self.integerOnly ? [NSString stringWithFormat:@"%d", (int)lroundf(value)] : [NSString stringWithFormat:@"%.4g", value];
    if ([self.delegate respondsToSelector:@selector(sliderTableViewCell:didChangeValue:)]) {
        [self.delegate sliderTableViewCell:self didChangeValue:value];
    }
}

- (void)sliderTouchDown:(UISlider *)sender {
	if ([self.delegate respondsToSelector:@selector(sliderTableViewCellDidBeginChanging:)]) {
		[self.delegate sliderTableViewCellDidBeginChanging:self];
	}
}

- (void)sliderTouchUp:(UISlider *)sender {
	// Make sure text field shows final value
	float value = SLClampedValue(sender, sender.value, self.integerOnly);
	sender.value = value;
	self.textField.text = self.integerOnly ? [NSString stringWithFormat:@"%d", (int)lroundf(value)] : [NSString stringWithFormat:@"%.4g", value];
	
	if ([self.delegate respondsToSelector:@selector(sliderTableViewCell:didEndChangingValue:)]) {
		[self.delegate sliderTableViewCell:self didEndChangingValue:value];
	}
}

- (void)dismissKeyboard {
    [self.textField resignFirstResponder];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    // do something here?
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(sliderTableViewCellDidBeginEditing:)]) {
        [self.delegate sliderTableViewCellDidBeginEditing:self];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (!self.integerOnly)
        return YES;

    NSString *candidate = [textField.text stringByReplacingCharactersInRange:range withString:string];
    if (!candidate.length)
        return YES;
    unsigned long long parsed = 0;
    if (!SLStringIsASCIIInteger(candidate, &parsed))
        return NO;
    /* A percentage has at most three digits; the range check on end-editing
     * remains authoritative for pasted values and slider bounds. */
    return candidate.length <= 3 && parsed <= 999;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(sliderTableViewCellDidEndEditing:)]) {
        [self.delegate sliderTableViewCellDidEndEditing:self];
    }
    
    NSString *inputText = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    float newValue = self.slider.value;
    BOOL valid = YES;
    if (self.integerOnly) {
        unsigned long long integerValue = 0;
        valid = SLStringIsASCIIInteger(inputText, &integerValue) && integerValue <= FLT_MAX;
        if (valid)
            newValue = (float)integerValue;
    } else {
        NSScanner *scanner = [NSScanner scannerWithString:inputText];
        valid = inputText.length > 0 && [scanner scanFloat:&newValue] && scanner.isAtEnd && isfinite(newValue);
    }

    if (!valid) {
        newValue = self.invalidInputFallbackValue;
        if (isnan(newValue))
            newValue = self.slider.value;
		UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, _("Invalid value; the previous value was restored."));
    }

    newValue = SLClampedValue(self.slider, newValue, self.integerOnly);
    self.slider.value = newValue;
    textField.text = self.integerOnly ? [NSString stringWithFormat:@"%d", (int)lroundf(newValue)] : [NSString stringWithFormat:@"%.4g", newValue];
        
    if ([self.delegate respondsToSelector:@selector(sliderTableViewCell:didChangeValue:)]) {
        [self.delegate sliderTableViewCell:self didChangeValue:newValue];
    }
	/* Text-field edits follow the same commit path as slider drags.  Without
	 * the end callback, controllers that persist/apply values there silently
	 * dropped a typed threshold until another slider event occurred. */
	if ([self.delegate respondsToSelector:@selector(sliderTableViewCell:didEndChangingValue:)]) {
		[self.delegate sliderTableViewCell:self didEndChangingValue:newValue];
	}
}

@end
