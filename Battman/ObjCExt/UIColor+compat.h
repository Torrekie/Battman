//
//  UIColor+compat.h
//  Battman
//
//  Created by Torrekie on 2025/11/4.
//

#import <UIKit/UIKit.h>

#ifdef __OBJC__
#define UIColorWithRGBA8(r, g, b, a) [UIColor colorWithRed:(r / 255.0f) green:(g / 255.0f) blue:(b / 255.0f) alpha:(a / 255.0f)]
#define UIColorWithWhiteA8(w, a) [UIColor colorWithWhite:(w / 255.0f) alpha:(a / 255.0f)]
#endif

NS_ASSUME_NONNULL_BEGIN

@interface UIColor (compat)
@property (class, nonatomic, readonly) UIColor *compatRedColor;
@property (class, nonatomic, readonly) UIColor *compatGreenColor;
@property (class, nonatomic, readonly) UIColor *compatBlueColor;
/*
@property (class, nonatomic, readonly) UIColor *compatOrangeColor;
@property (class, nonatomic, readonly) UIColor *compatYellowColor;
@property (class, nonatomic, readonly) UIColor *compatPinkColor;
@property (class, nonatomic, readonly) UIColor *compatPurpleColor;
@property (class, nonatomic, readonly) UIColor *compatTealColor;
@property (class, nonatomic, readonly) UIColor *compatIndigoColor;
*/

@property (class, nonatomic, readonly) UIColor *compatGrayColor;
/*
@property (class, nonatomic, readonly) UIColor *compatGray2Color;
@property (class, nonatomic, readonly) UIColor *compatGray3Color;
 */
@property (class, nonatomic, readonly) UIColor *compatGray4Color;
/*
@property (class, nonatomic, readonly) UIColor *compatGray5Color;
@property (class, nonatomic, readonly) UIColor *compatGray6Color;
*/
@property (class, nonatomic, readonly) UIColor *compatLabelColor;

@property (class, nonatomic, readonly) UIColor *compatSecondaryLabelColor;
/*
@property (class, nonatomic, readonly) UIColor *compatTertiaryLabelColor;
@property (class, nonatomic, readonly) UIColor *compatQuaternaryLabelColor;
*/

@property (class, nonatomic, readonly) UIColor *compatLinkColor;
/*
@property (class, nonatomic, readonly) UIColor *compatPlaceholderTextColor;
@property (class, nonatomic, readonly) UIColor *compatSeparatorColor;
@property (class, nonatomic, readonly) UIColor *compatOpaqueSeparatorColor;
*/

@property (class, nonatomic, readonly) UIColor *compatBackgroundColor;
/*
@property (class, nonatomic, readonly) UIColor *secondaryCompatBackgroundColor;
@property (class, nonatomic, readonly) UIColor *tertiaryCompatBackgroundColor;
@property (class, nonatomic, readonly) UIColor *compatGroupedBackgroundColor;
@property (class, nonatomic, readonly) UIColor *secondaryCompatGroupedBackgroundColor;
@property (class, nonatomic, readonly) UIColor *tertiaryCompatGroupedBackgroundColor;
@property (class, nonatomic, readonly) UIColor *compatFillColor;
 */
@property (class, nonatomic, readonly) UIColor *secondaryCompatFillColor;
@property (class, nonatomic, readonly) UIColor *tertiaryCompatFillColor;
/*
@property (class, nonatomic, readonly) UIColor *quaternaryCompatFillColor;
 */
@end

NS_ASSUME_NONNULL_END
