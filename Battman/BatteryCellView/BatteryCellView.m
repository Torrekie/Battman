#import "BatteryCellView.h"

@implementation BatteryCellView

- (void)updateForegroundPercentage:(NSUInteger)percent {
	[foregroundView updateWithPercentCompletion:percent];
}

- (void)updateBackgroundPercentage:(NSUInteger)percent {
	[backgroundView updateWithPercentCompletion:100 - percent];
}

- (instancetype)initWithFrame:(CGRect)frame foregroundPercentage:(NSUInteger)percent backgroundPercentage:(NSUInteger)bpercent {
	self=[super initWithFrame:frame];
	UIView *batteryView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
	batteryView.layer.cornerRadius = 30;
	batteryView.layer.masksToBounds = YES;
	batteryView.backgroundColor=[UIColor secondarySystemFillColor];
	// Battery Animation -- Start
	{
		/* True Remaining */
		SPWaterProgressIndicatorView *waterViewTR = [[SPWaterProgressIndicatorView alloc] initWithFrame:batteryView.bounds];
		waterViewTR.center = batteryView.center;
		// Create the background layer that will hold the gradient
		CAGradientLayer *waterViewTRGradient = [CAGradientLayer layer];
		waterViewTRGradient.frame = batteryView.frame;
		// Create an array of CG colors from our UIColor array
		NSMutableArray *cgColors = [NSMutableArray array];
		for (UIColor *color in @[[UIColor whiteColor], [UIColor whiteColor], [UIColor lightGrayColor]]) {
			[cgColors addObject:(__bridge id)color.CGColor];
		}
		waterViewTRGradient.colors = cgColors;

		// Create an image context to render the gradient
		UIGraphicsBeginImageContext(waterViewTRGradient.bounds.size);
		[waterViewTRGradient renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *backgroundColorImage = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		waterViewTR.waveColor = [UIColor colorWithPatternImage:backgroundColorImage];
		waterViewTR.frequency = 0.5;
		waterViewTR.amplitude = 0.2;
		waterViewTR.phaseShift = 0.05;
		[batteryView addSubview:waterViewTR];
		waterViewTR.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		waterViewTR.transform = CGAffineTransformMakeRotation(M_PI);
		//TODO: FullChargeCapacity/DesignCapacity (B0FC/B0DC)
		[waterViewTR updateWithPercentCompletion:100 - bpercent];
		[waterViewTR startAnimation];
		backgroundView = waterViewTR;
	}
	{
		SPWaterProgressIndicatorView *waterViewSoC = [[SPWaterProgressIndicatorView alloc] initWithFrame:batteryView.bounds];
		waterViewSoC.center = batteryView.center;

		// Create the background layer that will hold the gradient
		CAGradientLayer *waterViewSoCGradient = [CAGradientLayer layer];
		waterViewSoCGradient.frame = batteryView.frame;

		// Create an array of CG colors from our UIColor array
		NSMutableArray *cgColors = [NSMutableArray array];
		for (UIColor *color in @[[UIColor cyanColor], [UIColor greenColor]]) {
			[cgColors addObject:(__bridge id)color.CGColor];
		}
		waterViewSoCGradient.colors = cgColors;

		// Create an image context to render the gradient
		UIGraphicsBeginImageContext(waterViewSoCGradient.bounds.size);
		[waterViewSoCGradient renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *backgroundColorImage = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		waterViewSoC.waveColor = [UIColor colorWithPatternImage:backgroundColorImage];
		waterViewSoC.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		waterViewSoC.phaseShift = 0.1;
		[batteryView addSubview:waterViewSoC];
		//TODO: StateOfCharge (BRSC)
		[waterViewSoC updateWithPercentCompletion:percent];

		[waterViewSoC startAnimation];
		foregroundView = waterViewSoC;
	}
	[self addSubview:batteryView];
	return self;
}

@end
