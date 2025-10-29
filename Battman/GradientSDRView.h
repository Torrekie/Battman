//
//  GradientSDRView.h
//  Battman
//
//  Created by Torrekie on 2025/10/29.
//

#import <UIKit/UIKit.h>

@interface GradientSDRView : UIView

// Method to set brightness with animation
- (void)setBrightness:(int)percentage animated:(BOOL)animated;

// Properties for accessing internal state (for debugging/customization)
@property (nonatomic, readonly) float gradientRadius;
@property (nonatomic, readonly) float gradientBrightness;

@end
