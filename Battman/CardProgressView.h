//
//  CardProgressView.h
//  Battman
//
//  Created by Torrekie on 2025/11/19.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CardProgressIndicator : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) CGFloat value;
@property (nonatomic, strong) UIColor *color;

+ (instancetype)indicatorWithName:(NSString *)name value:(CGFloat)value color:(UIColor *)color;

@end

@interface CardProgressView : UIView

/// Title displayed at the top of the progress bar
@property (nonatomic, copy, nullable) NSString *title;

/// Title label displayed at the top of the progress bar
@property (nonatomic, strong) UILabel *titleLabel;

/// Minimum value of the range
@property (nonatomic, assign) CGFloat minValue;

/// Maximum value of the range
@property (nonatomic, assign) CGFloat maxValue;

/// Major progress value that fills the progress bar
@property (nonatomic, assign) CGFloat majorProgress;

/// Name for the major progress (displayed as first indicator label)
@property (nonatomic, copy, nullable) NSString *majorProgressName;

/// Color for the major progress bar
@property (nonatomic, strong) UIColor *majorProgressColor;

/// Array of CardProgressIndicator objects to display as markers
@property (nonatomic, strong) NSArray<CardProgressIndicator *> *indicators;

- (instancetype)initWithTitle:(nullable NSString *)title
                     minValue:(CGFloat)minValue
                     maxValue:(CGFloat)maxValue
                majorProgress:(CGFloat)majorProgress;

@end

NS_ASSUME_NONNULL_END
