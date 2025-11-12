#import "../ObjCExt/CALayer+smoothCorners.h"
#import "SegmentButton.h"
#import "Constants.h"


@implementation SegmentButton

#pragma mark - Initializers

- (instancetype)initWithFont:(UIFont *)font tintColor:(UIColor *)tintColor {
    self = [self initWithFrame:CGRectZero];
    
    if (self) {
        self.titleLabel.font = font;
        self.tintColor = tintColor;
        [self setTitleColor:tintColor forState:UIControlStateNormal];
    }
    
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setup];
    }
    
    return self;
}

#pragma mark - Property Overrides

- (void)setSelected:(BOOL)selected {
    BOOL oldValue = self.isSelected;
    
    [super setSelected:selected];
    
    if (selected && self.isHighlighted) {
        [self setHighlighted:NO];
    }
    
    if (selected != oldValue) {
        [self updateBackground];
    }
}

- (void)setHighlighted:(BOOL)highlighted {
    BOOL oldValue = self.isHighlighted;
    
    [super setHighlighted:highlighted];
    
/* Please ignore this, they planned to derpecate it since iOS 4 */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (highlighted != oldValue) {
        // Animate alpha fade
        [UIView animateWithDuration:[ConstantsDuration regular] animations:^{
            [UIView setAnimationBeginsFromCurrentState:YES];
            
            if (self.isSelected) {
                self.alpha = 1.0;
            } else {
                self.alpha = highlighted ? [ConstantsMeasure highlightedAlpha] : 1.0;
            }
        }];
        
        // Animate scale
        [UIView animateWithDuration:[ConstantsDuration snappy] animations:^{
            [UIView setAnimationBeginsFromCurrentState:YES];
            
            if (self.isSelected) {
                if (highlighted) {
                    CGFloat kHighlightedScale = [ConstantsMeasure highlightedScale];
                    self.transform = CGAffineTransformMakeScale(kHighlightedScale, kHighlightedScale);
                } else {
                    self.transform = CGAffineTransformIdentity;
                }
            } else {
                self.transform = CGAffineTransformIdentity;
            }
        }];
    }
#pragma clang diagnostic pop
}

#pragma mark - Private Methods

- (void)setup {
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.adjustsImageWhenHighlighted = NO;

    self.layer.cornerRadius = [ConstantsMeasure segmentCornerRadius];
	[self.layer setSmoothCorners:YES];
    self.layer.shadowRadius = [ConstantsMeasure segmentShadowRadius];
    self.layer.shadowColor = [ConstantsColor segmentShadow].CGColor;
    self.layer.shadowOffset = [ConstantsMeasure segmentShadowOffset];
    self.layer.shadowOpacity = [ConstantsMeasure segmentShadowOpacity];
}

- (void)updateBackground {
    if (self.isSelected && self.selectedBackgroundColor) {
        self.backgroundColor = self.selectedBackgroundColor;
    } else {
        self.backgroundColor = [UIColor clearColor];
    }
}

@end


