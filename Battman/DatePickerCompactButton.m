//
//  DatePickerCompactButton.m
//  Battman
//
//  Created by Torrekie on 2025/8/28.
//

#import "ObjCExt/CALayer+smoothCorners.h"
#import "ObjCExt/UIColor+compat.h"
#import "DatePickerCompactButton.h"

@implementation DatePickerCompactButton

- (instancetype)initWithTitle:(NSString *)title {
	if (self = [super initWithFrame:CGRectZero]) {
		[self commonInit];
		[self setTitle:title forState:UIControlStateNormal];
		[self sizeToFit];
	}
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame]) {
		[self commonInit];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
	if (self = [super initWithCoder:aDecoder]) {
		[self commonInit];
	}
	return self;
}

- (void)commonInit {
	[self.heightAnchor constraintEqualToConstant:34.3333].active = YES;

	[self setTitleColor:[UIColor compatLinkColor] forState:UIControlStateSelected];
	[self setTitleColor:[UIColor compatLabelColor] forState:UIControlStateNormal];
	
	self.backgroundColor = [UIColor tertiaryCompatFillColor];

	self.contentEdgeInsets = UIEdgeInsetsMake(4, 8, 4, 8);
	// Rounded border
	self.layer.bounds = CGRectMake(0, 0, self.layer.frame.size.width * 1.5, self.layer.frame.size.height * 1.5);
	self.layer.cornerRadius = 8;
	self.layer.masksToBounds = YES;
	[self.layer setSmoothCorners:YES];
}

@end
