//
//  PickerAccessoryView.m
//  Battman
//
//  Created by Torrekie on 2025/8/29.
//

#import "ObjCExt/CALayer+smoothCorners.h"
#import "PickerAccessoryView.h"
#import <objc/message.h>

static UIView *find_first_subview_class(id view, char *className) {
	if (!view || !className) return nil;
	UIView *tgt = view;
	const char *target = className;
	
	for (UIView *subview in tgt.subviews) {
		const char *name = object_getClassName(subview);
		if (name && strcmp(name, target) == 0) {
			return subview;
		}
		UIView *found = find_first_subview_class(subview, className);
		if (found) return found;
	}
	return nil;
}

@interface PickerAccessoryView () <UIPickerViewDataSource, UIPickerViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, assign) CGPoint touchStartPoint;
@property (nonatomic, assign) CGFloat pickerMaxWidth;
@property (nonatomic, assign) int numberOfRows;
@property (nonatomic, strong) CALayer *border;
@end

@implementation PickerAccessoryView

- (void)layoutSubviews {
	[super layoutSubviews];
	[self applyMagics:YES];
}

- (void)didMoveToSuperview {
	[self setNeedsLayout];
}

-(void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[self setNeedsLayout];
}

- (void)applyMagics:(BOOL)setFrames {
	if (@available(iOS 14.0, *)) {
		// Nothing to do
	} else if (@available(iOS 12.0, *)) {
		// This has only been tested on iOS 12/13, I dont have more space to install simulators
		// Remove top/bottom border
		for (UIView *view in self.subviews) {
			view.layer.backgroundColor = [UIColor clearColor].CGColor;
		}
		UIView *column = find_first_subview_class((id)self, "UIPickerColumnView");
		CGRect columnRect = column.frame;
		if (setFrames) {
			[column setFrame:CGRectMake(columnRect.origin.x + 9, columnRect.origin.y, columnRect.size.width - 18, columnRect.size.height)];
			
			for (UIView *sub in column.subviews) {
				CGRect subRect = sub.frame;
				[sub setFrame:CGRectMake(columnRect.origin.x, subRect.origin.y, subRect.size.width - 18, subRect.size.height)];
				UIView *table = find_first_subview_class((id)sub, "UIPickerTableView");
				if (table) {
					CGRect tableRect = table.frame;
					[table setFrame:CGRectMake(tableRect.origin.x - 9, tableRect.origin.y, tableRect.size.width, tableRect.size.height)];
				}
			}
		}
		// Full of magics, man
		column.subviews[2].layer.cornerRadius = 8;
		if (@available(iOS 13.0, *)) {
			// tertiarySystemFillColor does not working quite well on iOS 13
			// this dynamic color does not cover all cases, but has been calibrated with iOS 14 Dark/Light mode
			column.subviews[2].backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
				if ([(id)traits userInterfaceStyle] == UIUserInterfaceStyleDark) {
					return [UIColor colorWithRed:(118.0f / 255) green:(118.0f / 255) blue:(129.0f / 255) alpha:0.30];
				} else {
					return [UIColor colorWithRed:(118.0f / 255) green:(118.0f / 255) blue:(128.0f / 255) alpha:0.15];
				}
			}];
			//column.subviews[2].backgroundColor = [UIColor tertiarySystemFillColor];
		} else {
			column.subviews[2].backgroundColor = [UIColor colorWithRed:118.0f / 255 green:118.0f / 255 blue:129.0f / 255 alpha:0.15];
		}
		[column.subviews[2].layer setSmoothCorners:YES];
	}
}

- (instancetype)initWithFrame:(CGRect)frame font:(UIFont *)font options:(NSArray<NSString *> *)options {
	self = [super initWithFrame:frame];
	if (self) {
		_font = font ?: [UIFont systemFontOfSize:17];
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		CGSize fittingSize = [self sizeThatFits:CGSizeZero];
		self.autoresizingMask = UIViewAutoresizingNone;
		CGFloat maxWidth = 0;
		self.numberOfRows = (int)options.count * 400; // Consider control this by arg?
		for (NSString *str in options) {
			CGSize size = [str sizeWithAttributes:@{NSFontAttributeName: _font}];
			maxWidth = MAX(maxWidth, size.width);
		}
		self.pickerMaxWidth = maxWidth + 34; // 34 is the height when UIPickerView using as accessoryView, we should make this value dynamically retrieved
		
		self.frame = CGRectMake(0, 0, self.pickerMaxWidth, fittingSize.height);
		_options = [options copy];
		self.dataSource = self;
		self.delegate = self;
		self.showsSelectionIndicator = true;

		[self selectAutomaticRow:0 animated:YES];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
		tap.cancelsTouchesInView = NO;
		tap.delegate = self;
		[self addGestureRecognizer:tap];
	}
	return self;
}

- (void)selectAutomaticRow:(NSInteger)row animated:(BOOL)animated {
	// Center initial selection
	NSInteger mid = self.numberOfRows / 2;
	NSInteger startRow = mid - (mid % _options.count);
	[self selectRow:startRow + row inComponent:0 animated:animated];
}


- (void)addTarget:(id)target action:(SEL)action {
	self.target = target;
	self.action = action;
}

#pragma mark - Gesture Handler

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	return YES;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	UITouch *t = [touches anyObject];
	self.touchStartPoint = [t locationInView:self];
	[super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
	UITouch *t = [touches anyObject];
	CGPoint end = [t locationInView:self];
	CGFloat dx = end.x - self.touchStartPoint.x;
	CGFloat dy = end.y - self.touchStartPoint.y;
	CGFloat distance = sqrt(dx * dx + dy * dy);
	NSTimeInterval duration = t.timestamp - event.timestamp;
	const CGFloat maxDistance = 0.1;    // Leeway in points
	const NSTimeInterval maxDuration = 0.1; // Maximum for taps
	if (distance <= maxDistance && duration <= maxDuration) {
		[self handleTapGestureRecognized];
	}
	[super touchesEnded:touches withEvent:event];
}

- (void)handleTap:(UITapGestureRecognizer *)tapRecognizer {
	if (tapRecognizer.state != UIGestureRecognizerStateEnded) return;
	
	CGFloat rowHeight = [self rowSizeForComponent:0].height;
	CGRect selectedRect = CGRectInset(self.bounds, 0.0, (CGRectGetHeight(self.frame) - rowHeight)/2.0);
	CGPoint location = [tapRecognizer locationInView:self];
	if (CGRectContainsPoint(selectedRect, location)) {
		[self handleTapGestureRecognized];
	}
}


- (void)handleTapGestureRecognized {
	NSInteger selected = [self selectedRowInComponent:0];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if ((selected + 1) == self.numberOfRows) {
			NSInteger mid = self.numberOfRows / 2;
			NSInteger startRow = mid - (mid % self.options.count);
			[self selectRow:startRow inComponent:0 animated:YES];
		} else {
			[self selectRow:selected + 1 inComponent:0 animated:YES];
		}
		[self notifyValueChanged];
	});
}


#pragma mark - Notify Target

- (void)notifyValueChanged {
	if (self.target && self.action && [self.target respondsToSelector:self.action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		[self.target performSelector:self.action withObject:self];
#pragma clang diagnostic pop
	}
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
	return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
	return self.numberOfRows;
}

- (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component {
	return self.pickerMaxWidth;
}

#pragma mark - UIPickerViewDelegate

- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
	NSInteger idx = row % self.options.count;
	UILabel *label = (UILabel *)view;
	if (!label) {
		label = [[UILabel alloc] initWithFrame:CGRectZero];
		label.textAlignment = NSTextAlignmentCenter;
		label.font = self.font;
	}
	label.text = self.options[idx];
	CGSize bounds = [pickerView rowSizeForComponent:component];
	label.frame = CGRectMake(0, 0, bounds.width, bounds.height);
	return label;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
	[self notifyValueChanged];
}

@end
