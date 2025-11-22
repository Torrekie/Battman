#import "IPadHomeButtonVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define IPAD_HOME_ICON_WIDTH 94
#define IPAD_HOME_ICON_HEIGHT 128

@implementation IPadHomeButtonVectorIcon

+ (void)drawIPadHomeButton {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, IPAD_HOME_ICON_HEIGHT);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

	CGContextSaveGState(context);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop

	CGContextBeginPath(context);
	CGContextMoveToPoint(context, 15.58, 128);
	CGContextAddLineToPoint(context, 78.42, 128);
	CGContextAddCurveToPoint(context, 83.49, 127.96, 87.36, 126.62, 90.04, 123.99);
	CGContextAddCurveToPoint(context, 92.71, 121.35, 94.07, 117.52, 94.11, 112.49);
	CGContextAddLineToPoint(context, 94.11, 15.57);
	CGContextAddCurveToPoint(context, 94.07, 10.54, 92.71, 6.69, 90.04, 4.01);
	CGContextAddCurveToPoint(context, 87.36, 1.38, 83.49, 0.04, 78.42, 0);
	CGContextAddLineToPoint(context, 15.58, 0);
	CGContextAddCurveToPoint(context, 10.51, 0.04, 6.64, 1.38, 3.96, 4.01);
	CGContextAddCurveToPoint(context, 1.29, 6.69, -0.07, 10.54, -0.11, 15.57);
	CGContextAddLineToPoint(context, -0.11, 112.49);
	CGContextAddCurveToPoint(context, -0.07, 117.52, 1.29, 121.35, 3.96, 123.99);
	CGContextAddCurveToPoint(context, 6.64, 126.62, 10.51, 127.96, 15.58, 128);
	CGContextAddLineToPoint(context, 15.58, 128);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 47.03, 11.56);
	CGContextAddCurveToPoint(context, 46.23, 11.52, 45.57, 11.24, 45.05, 10.72);
	CGContextAddCurveToPoint(context, 44.53, 10.2, 44.25, 9.56, 44.22, 8.81);
	CGContextAddCurveToPoint(context, 44.25, 8.01, 44.53, 7.35, 45.05, 6.83);
	CGContextAddCurveToPoint(context, 45.57, 6.27, 46.23, 5.99, 47.03, 5.99);
	CGContextAddCurveToPoint(context, 47.79, 5.99, 48.43, 6.27, 48.95, 6.83);
	CGContextAddCurveToPoint(context, 49.47, 7.35, 49.75, 8.01, 49.79, 8.81);
	CGContextAddCurveToPoint(context, 49.75, 9.56, 49.47, 10.2, 48.95, 10.72);
	CGContextAddCurveToPoint(context, 48.43, 11.24, 47.79, 11.52, 47.03, 11.56);
	CGContextAddLineToPoint(context, 47.03, 11.56);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 4.32, 110.75);
	CGContextAddLineToPoint(context, 4.32, 17.25);
	CGContextAddLineToPoint(context, 89.68, 17.25);
	CGContextAddLineToPoint(context, 89.68, 110.75);
	CGContextAddLineToPoint(context, 4.32, 110.75);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 47.09, 122.97);
	CGContextAddCurveToPoint(context, 45.81, 122.93, 44.77, 122.49, 43.98, 121.65);
	CGContextAddCurveToPoint(context, 43.14, 120.85, 42.7, 119.81, 42.66, 118.54);
	CGContextAddCurveToPoint(context, 42.7, 117.3, 43.14, 116.28, 43.98, 115.48);
	CGContextAddCurveToPoint(context, 44.77, 114.68, 45.81, 114.26, 47.09, 114.22);
	CGContextAddCurveToPoint(context, 48.33, 114.26, 49.35, 114.68, 50.14, 115.48);
	CGContextAddCurveToPoint(context, 50.94, 116.28, 51.36, 117.3, 51.4, 118.54);
	CGContextAddCurveToPoint(context, 51.36, 119.81, 50.94, 120.85, 50.14, 121.65);
	CGContextAddCurveToPoint(context, 49.35, 122.49, 48.33, 122.93, 47.09, 122.97);
	CGContextAddLineToPoint(context, 47.09, 122.97);
	CGContextClosePath(context);

	CGContextSetFillColorWithColor(context, blackColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);
}

+ (CGImageRef)IPadHomeButtonCGImage
{
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(IPAD_HOME_ICON_WIDTH, IPAD_HOME_ICON_HEIGHT), NO, 0);
	[IPadHomeButtonVectorIcon drawIPadHomeButton];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, IPAD_HOME_ICON_WIDTH, IPAD_HOME_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(IPAD_HOME_ICON_WIDTH, IPAD_HOME_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[IPadHomeButtonVectorIcon drawIPadHomeButton];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
