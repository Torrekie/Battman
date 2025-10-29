//
//  SegmentedTextField.m
//  Battman
//
//  Created by Torrekie on 2025/10/16.
//

#import "common.h"
#import "SegmentedTextField.h"

@interface SegmentedTextField () {
	NSMutableArray *allowedItems;
	NSMutableDictionary *textFieldsAtIndex; // Maps segment index to UITextField
	BOOL hasAppliedReplacements;
}
@end

@interface UISegment : UIImageView
@end
@interface UISegmentLabel : UILabel
@end

@interface UISegmentedControl (Private)
- (UISegment *)_segmentAtIndex:(NSUInteger)index;
@end

@implementation SegmentedTextField

static void replaceView(UIView *oldView, UIView *newView) {
	UIView *superview = oldView.superview;

	// preserve geometry and common visual properties
	newView.frame = oldView.frame;
	newView.autoresizingMask = oldView.autoresizingMask;
	newView.translatesAutoresizingMaskIntoConstraints = oldView.translatesAutoresizingMaskIntoConstraints;
	newView.transform = oldView.transform;
	newView.alpha = oldView.alpha;
	newView.hidden = oldView.hidden;
	newView.clipsToBounds = oldView.clipsToBounds;
	
	// keep the same stacking index
	NSUInteger index = [superview.subviews indexOfObject:oldView];
	if (index != NSNotFound) {
		[superview insertSubview:newView atIndex:index];
	} else {
		[superview addSubview:newView];
	}

	[oldView removeFromSuperview];
}

- (instancetype)initWithItems:(NSArray *)items {
	allowedItems = [NSMutableArray array];
	textFieldsAtIndex = [NSMutableDictionary dictionary];
	hasAppliedReplacements = NO;

	for (NSInteger i = 0; i < items.count; i++) {
		NSObject *item = items[i];
		if ([item isKindOfClass:[UITextField class]]) {
			// This ensures we have enough width for textField
			UITextField *tf = (UITextField *)item;
			if ([tf.text isEqualToString:@""] && ![tf.placeholder isEqualToString:@""])
				[allowedItems addObject:tf.placeholder];
			else
				[allowedItems addObject:tf.text];
			textFieldsAtIndex[@(i)] = item;
		} else {
			[allowedItems addObject:item];
		}
	}

	self = [super initWithItems:allowedItems];
	if (self) {
		// What else?
		[self addTarget:self action:@selector(_handleValueChanged:) forControlEvents:UIControlEventValueChanged];
	}

	return self;
}

- (void)dealloc {
	[textFieldsAtIndex removeAllObjects];
	[allowedItems removeAllObjects];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	// Only apply replacements once and only if we have text fields to replace
	if (hasAppliedReplacements || textFieldsAtIndex.count == 0) {
		return;
	}
	
	NSInteger numberOfSegments = self.numberOfSegments;
	NSArray *allSubviews = self.subviews;
	
	if (allSubviews.count < numberOfSegments) {
		return;
	}
	
	for (NSNumber *indexKey in textFieldsAtIndex.allKeys) {
		NSInteger targetIndex = indexKey.integerValue;
		UITextField *textField = textFieldsAtIndex[indexKey];
		
		if (targetIndex < self.numberOfSegments) {
			UISegment *targetSegment = [self _segmentAtIndex:targetIndex];
			
			UISegmentLabel *segmentLabel = nil;
			for (UIView *subview in targetSegment.subviews) {
				if ([subview isKindOfClass:NSClassFromString(@"UISegmentLabel")]) {
					segmentLabel = (UISegmentLabel *)subview;
					break;
				}
			}
			
			if (segmentLabel) {
				segmentLabel.frame = CGRectMake(0, 0, targetSegment.frame.size.width, targetSegment.frame.size.height);
				segmentLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
				
				// Configure text field with toolbar if needed
				if (!textField.inputAccessoryView) {
					UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
					toolbar.barStyle = UIBarStyleDefault;
					UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
					UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithTitle:_("Done") style:UIBarButtonItemStyleDone target:self action:@selector(_dismissKeyboard)];
					toolbar.items = @[flexSpace, doneButton];
					textField.inputAccessoryView = toolbar;
				}
				
				// Defer font copying until the next run loop to ensure segment label has proper font
				UIFont *labelFont = segmentLabel.font;
				if (labelFont && ![labelFont.fontName isEqualToString:@".SFUI-Regular"] && labelFont.pointSize > 0) {
					// Font is properly configured
					textField.font = labelFont;
				} else {
					// Font not ready yet, defer to next run loop
					// Use weak references to avoid retain cycles
					__weak UISegmentLabel *weakSegmentLabel = segmentLabel;
					__weak UITextField *weakTextField = textField;
					dispatch_async(dispatch_get_main_queue(), ^{
						UIFont *deferredFont = weakSegmentLabel.font;
						if (deferredFont && deferredFont.pointSize > 0) {
							weakTextField.font = deferredFont;
						} else {
							// Fallback to system font with appropriate size
							weakTextField.font = [UIFont systemFontOfSize:13.0];
						}
					});
				}
				
				replaceView(segmentLabel, textField);
			}
		}
	}
	
	hasAppliedReplacements = YES;
}

- (void)didMoveToSuperview {
	[super didMoveToSuperview];
	[self setNeedsLayout];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	if (self.window) {
		[self setNeedsLayout];
		[self layoutIfNeeded];

		__weak typeof(self) weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (strongSelf) {
				[strongSelf synchronizeTextFieldFonts];
			}
		});
	}
}

// Override methods that might cause segment reconstruction
- (void)insertSegmentWithTitle:(NSString *)title atIndex:(NSUInteger)segment animated:(BOOL)animated {
	[super insertSegmentWithTitle:title atIndex:segment animated:animated];
	hasAppliedReplacements = NO;
	[self setNeedsLayout];
}

- (void)insertSegmentWithImage:(UIImage *)image atIndex:(NSUInteger)segment animated:(BOOL)animated {
	[super insertSegmentWithImage:image atIndex:segment animated:animated];
	hasAppliedReplacements = NO;
	[self setNeedsLayout];
}

- (void)removeSegmentAtIndex:(NSUInteger)segment animated:(BOOL)animated {
	[super removeSegmentAtIndex:segment animated:animated];
	hasAppliedReplacements = NO;
	[self setNeedsLayout];
}

- (void)removeAllSegments {
	[super removeAllSegments];
	hasAppliedReplacements = NO;
}

- (UITextField *)textFieldAtIndex:(NSInteger)index {
	return textFieldsAtIndex[@(index)];
}

- (void)synchronizeTextFieldFonts {
	// Synchronize text field fonts with their corresponding segment labels
	for (NSNumber *indexKey in textFieldsAtIndex.allKeys) {
		NSInteger targetIndex = indexKey.integerValue;
		UITextField *textField = textFieldsAtIndex[indexKey];

		if (targetIndex < self.numberOfSegments) {
			// Find a reference segment label to get the proper font
			UISegmentLabel *referenceLabel = nil;
			for (NSInteger i = 0; i < self.numberOfSegments; i++) {
				if (i != targetIndex) { // Skip the segment that has our text field
					UISegment *segment = [self _segmentAtIndex:i];
					for (UIView *subview in segment.subviews) {
						if ([subview isKindOfClass:NSClassFromString(@"UISegmentLabel")]) {
							referenceLabel = (UISegmentLabel *)subview;
							break;
						}
					}
					if (referenceLabel) break;
				}
			}
			
			if (referenceLabel && referenceLabel.font && referenceLabel.font.pointSize > 0) {
				textField.font = referenceLabel.font;
				CGRect newf = textField.frame;
				newf.origin.y = referenceLabel.frame.origin.y;
				newf.size.height = referenceLabel.frame.size.height;
				textField.frame = newf;
			}
		}
	}
}

- (void)_dismissKeyboard {
	for (UITextField *textField in textFieldsAtIndex.allValues) {
		[textField resignFirstResponder];
	}
}

- (void)_handleValueChanged:(SegmentedTextField *)sender {
	NSInteger selectedIndex = self.selectedSegmentIndex;
	
	// Check if the selected segment has a text field
	UITextField *selectedTextField = textFieldsAtIndex[@(selectedIndex)];
	
	if (selectedTextField) {
		// Make the text field first responder
		[selectedTextField becomeFirstResponder];
	} else {
		// If selected segment doesn't have a text field, dismiss any active text field
		for (UITextField *textField in textFieldsAtIndex.allValues) {
			[textField resignFirstResponder];
		}
	}
}

@end
