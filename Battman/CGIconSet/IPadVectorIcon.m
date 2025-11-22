#import "IPadVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define IPAD_ICON_WIDTH 94
#define IPAD_ICON_HEIGHT 128

@implementation IPadVectorIcon

+ (void)drawIPad {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, IPAD_ICON_HEIGHT);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

	CGContextSaveGState(context);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop

	CGContextBeginPath(context);
	CGContextMoveToPoint(context, -0.11, 112.49);
	CGContextAddCurveToPoint(context, -0.07, 117.52, 1.29, 121.35, 3.96, 123.99);
	CGContextAddCurveToPoint(context, 6.64, 126.62, 10.51, 127.96, 15.58, 128);
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
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 4.32, 112.07);
	CGContextAddLineToPoint(context, 4.32, 15.99);
	CGContextAddCurveToPoint(context, 4.32, 12.2, 5.3, 9.34, 7.26, 7.43);
	CGContextAddCurveToPoint(context, 9.25, 5.47, 12.15, 4.49, 15.94, 4.49);
	CGContextAddLineToPoint(context, 78.06, 4.49);
	CGContextAddCurveToPoint(context, 81.85, 4.49, 84.75, 5.47, 86.74, 7.43);
	CGContextAddCurveToPoint(context, 88.7, 9.34, 89.68, 12.2, 89.68, 15.99);
	CGContextAddLineToPoint(context, 89.68, 112.07);
	CGContextAddCurveToPoint(context, 89.68, 115.86, 88.7, 118.72, 86.74, 120.63);
	CGContextAddCurveToPoint(context, 84.75, 122.59, 81.85, 123.57, 78.06, 123.57);
	CGContextAddLineToPoint(context, 15.94, 123.57);
	CGContextAddCurveToPoint(context, 12.15, 123.57, 9.25, 122.59, 7.26, 120.63);
	CGContextAddCurveToPoint(context, 5.3, 118.72, 4.32, 115.86, 4.32, 112.07);
	CGContextAddLineToPoint(context, 4.32, 112.07);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 30.74, 119.02);
	CGContextAddLineToPoint(context, 63.26, 119.02);
	CGContextAddCurveToPoint(context, 63.78, 119.02, 64.2, 118.84, 64.52, 118.48);
	CGContextAddCurveToPoint(context, 64.88, 118.16, 65.06, 117.74, 65.06, 117.22);
	CGContextAddCurveToPoint(context, 65.06, 116.7, 64.88, 116.28, 64.52, 115.96);
	CGContextAddCurveToPoint(context, 64.2, 115.6, 63.78, 115.42, 63.26, 115.42);
	CGContextAddLineToPoint(context, 30.74, 115.42);
	CGContextAddCurveToPoint(context, 30.26, 115.42, 29.84, 115.6, 29.48, 115.96);
	CGContextAddCurveToPoint(context, 29.12, 116.28, 28.94, 116.7, 28.94, 117.22);
	CGContextAddCurveToPoint(context, 28.94, 117.74, 29.12, 118.16, 29.48, 118.48);
	CGContextAddCurveToPoint(context, 29.84, 118.84, 30.26, 119.02, 30.74, 119.02);
	CGContextAddLineToPoint(context, 30.74, 119.02);
	CGContextClosePath(context);

	CGContextSetFillColorWithColor(context, blackColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);
}

+ (CGImageRef)IPadCGImage
{
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(IPAD_ICON_WIDTH, IPAD_ICON_HEIGHT), NO, 0);
	[IPadVectorIcon drawIPad];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, IPAD_ICON_WIDTH, IPAD_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(IPAD_ICON_WIDTH, IPAD_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[IPadVectorIcon drawIPad];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
