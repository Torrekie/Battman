//
//  CALayer+smoothCorners.m
//  Battman
//
//  Created by Torrekie on 2025/11/4.
//

#import "CALayer+smoothCorners.h"

// Privates
@interface CALayer ()
@property (atomic, assign) BOOL continuousCorners;
@end

@implementation CALayer (smoothCorners)

- (void)setSmoothCorners:(BOOL)smoothCorners {
	if (@available(iOS 13.0, *)) {
		[self setCornerCurve:smoothCorners ? kCACornerCurveContinuous : kCACornerCurveCircular];
	}
	if ([self respondsToSelector:@selector(setContinuousCorners:)])
		[self setContinuousCorners:smoothCorners];
}

@end
