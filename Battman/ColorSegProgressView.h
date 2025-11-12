#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ColorSegTransitionMode) {
	kColorSegTransitionRGB,        // Linear RGB interpolation (default)
	kColorSegTransitionHSB,        // HSB interpolation taking longer path around color wheel
	kColorSegTransitionAnalogous   // HSB interpolation taking shorter path (analogous colors)
};

@interface ColorSegProgressView : UIControl

- (instancetype)initWithSegmentCount:(NSUInteger)count colorTransition:(NSArray<UIColor *> *)colorTransition NS_DESIGNATED_INITIALIZER;

@property (nonatomic) double value;
- (void)setValue:(double)value animated:(BOOL)animated;

@property (nonatomic) double minimumValue;
@property (nonatomic) double maximumValue;

@property (nonatomic) CGFloat progress;
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;

@property (nonatomic) BOOL valueShouldFollowSegments;

@property (nonatomic) CGFloat segmentSpacing;

@property (nonatomic) BOOL forceSquareSegments;

@property (nonatomic) CGFloat unfilledAlpha;

@property (nonatomic, nullable) UIColor *colorForUnfilled;

@property (nonatomic) BOOL showSeparators;

@property (nonatomic, strong) UIColor *separatorColor;
@property (nonatomic) CGFloat separatorWidth;

@property (nonatomic) CGFloat borderWidth;
@property (nonatomic, strong, nullable) UIColor *borderColor;

@property (nonatomic) BOOL continuousUpdates;

@property (nonatomic) ColorSegTransitionMode colorTransitionMode;

@property (nonatomic, strong, nullable) UIColor *backgroundColor;

- (void)updateColorTransition:(NSArray<UIColor *> *)colorTransition;

// Currently Battman does not use those, if you wish to, try implement your own
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
