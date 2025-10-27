//
//  GradientHDRView.h
//  Battman
//
//  Created by Torrekie on 2025/10/4.
//

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@interface GradientHDRView : UIView

// Method to set brightness with animation
- (void)setBrightness:(int)percentage animated:(BOOL)animated;

// Properties for accessing internal state (for debugging/customization)
@property (nonatomic, readonly) float gradientRadius;
@property (nonatomic, readonly) float gradientBrightness;
@property (nonatomic, readonly) BOOL supportsHDR;

@end
