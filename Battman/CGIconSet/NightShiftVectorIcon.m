#import "NightShiftVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define NIGHT_SHIFT_ICON_WIDTH 30
#define NIGHT_SHIFT_ICON_HEIGHT 30

@implementation NightShiftVectorIcon

+ (void)drawNightShift {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, BATTMAN_ICON_WIDTH);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif
	
	CGContextSaveGState(context);
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop
	
	{
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextMoveToPoint(context, 15, 8);
			CGContextAddCurveToPoint(context, 18.87, 8, 22, 11.13, 22, 15);
			CGContextAddCurveToPoint(context, 22, 18.87, 18.87, 22, 15, 22);
			CGContextAddCurveToPoint(context, 11.13, 22, 8, 18.87, 8, 15);
			CGContextAddCurveToPoint(context, 8, 11.13, 11.13, 8, 15, 8);
			CGContextClosePath(context);
			
			CGContextMoveToPoint(context, 20.3, 16.42);
			CGContextAddLineToPoint(context, 20.3, 16.42);
			CGContextAddCurveToPoint(context, 19.55, 16.88, 18.68, 17.15, 17.73, 17.15);
			CGContextAddCurveToPoint(context, 15.04, 17.15, 12.85, 14.96, 12.85, 12.26);
			CGContextAddCurveToPoint(context, 12.85, 11.32, 13.12, 10.45, 13.58, 9.7);
			CGContextAddCurveToPoint(context, 11.5, 10.41, 10, 12.39, 10, 14.71);
			CGContextAddCurveToPoint(context, 10, 17.63, 12.37, 20, 15.29, 20);
			CGContextAddCurveToPoint(context, 17.61, 20, 19.59, 18.5, 20.3, 16.42);
			CGContextClosePath(context);
			
			CGContextClip(context);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(3, 3, 24, 24));
			CGContextClosePath(context);
			CGContextSetFillColorWithColor(context, blackColor);
			CGContextFillRect(context, CGRectMake(3, 3, 24, 24));
			
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
#define STROKE_LINE(x1,y1,x2,y2) do {			\
	CGContextBeginPath(context); 				\
	CGContextMoveToPoint(context, x1, y1); 		\
	CGContextAddLineToPoint(context, x2, y2); 	\
	CGContextSetLineWidth(context, 2.0); 		\
	CGContextStrokePath(context); 				\
} while(0)
		
		STROKE_LINE(15, 3, 15, 5);
		STROKE_LINE(15, 25, 15, 27);
		STROKE_LINE(23.49, 6.51, 22.07, 7.93);
		STROKE_LINE(7.93, 22.07, 6.51, 23.49);
		STROKE_LINE(27, 15, 25, 15);
		STROKE_LINE(5, 15, 3, 15);
		STROKE_LINE(23.49, 23.49, 22.07, 22.07);
		STROKE_LINE(7.93, 7.93, 6.51, 6.51);
		
#undef STROKE_LINE
	}
	
	CGContextRestoreGState(context);
}

+ (CGImageRef)NightShiftCGImage {
	static CGImageRef _iconCG = nil;
	
	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(NIGHT_SHIFT_ICON_WIDTH, NIGHT_SHIFT_ICON_HEIGHT), NO, 0);
	[NightShiftVectorIcon drawNightShift];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, NIGHT_SHIFT_ICON_WIDTH, NIGHT_SHIFT_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(NIGHT_SHIFT_ICON_WIDTH, NIGHT_SHIFT_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[NightShiftVectorIcon drawNightShift];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
