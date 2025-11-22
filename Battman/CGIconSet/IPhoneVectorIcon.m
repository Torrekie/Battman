#import "IPhoneVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define IPHONE_ICON_WIDTH 72
#define IPHONE_ICON_HEIGHT 128

@implementation IPhoneVectorIcon

+ (void)drawIPhone {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, IPHONE_ICON_HEIGHT);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

	CGContextSaveGState(context);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop

	CGContextBeginPath(context);
	CGContextMoveToPoint(context, 16.13, 128);
	CGContextAddLineToPoint(context, 55.79, 128);
	CGContextAddCurveToPoint(context, 61.09, 128, 65.16, 126.61, 67.98, 123.84);
	CGContextAddCurveToPoint(context, 70.76, 121.06, 72.14, 117, 72.14, 111.65);
	CGContextAddLineToPoint(context, 72.14, 16.43);
	CGContextAddCurveToPoint(context, 72.14, 11.08, 70.76, 7.01, 67.98, 4.24);
	CGContextAddCurveToPoint(context, 65.16, 1.41, 61.09, 0, 55.79, 0);
	CGContextAddLineToPoint(context, 16.13, 0);
	CGContextAddCurveToPoint(context, 10.83, 0, 6.79, 1.41, 4.02, 4.24);
	CGContextAddCurveToPoint(context, 1.24, 7.01, -0.14, 11.08, -0.14, 16.43);
	CGContextAddLineToPoint(context, -0.14, 111.65);
	CGContextAddCurveToPoint(context, -0.14, 117, 1.24, 121.06, 4.02, 123.84);
	CGContextAddCurveToPoint(context, 6.79, 126.61, 10.83, 128, 16.13, 128);
	CGContextAddLineToPoint(context, 16.13, 128);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 16.51, 122.55);
	CGContextAddCurveToPoint(context, 12.62, 122.55, 9.77, 121.67, 7.95, 119.9);
	CGContextAddCurveToPoint(context, 6.19, 118.13, 5.31, 115.33, 5.31, 111.5);
	CGContextAddLineToPoint(context, 5.31, 16.58);
	CGContextAddCurveToPoint(context, 5.31, 12.74, 6.19, 9.92, 7.95, 8.1);
	CGContextAddCurveToPoint(context, 9.77, 6.33, 12.62, 5.45, 16.51, 5.45);
	CGContextAddLineToPoint(context, 23.7, 5.45);
	CGContextAddCurveToPoint(context, 23.9, 5.45, 24.05, 5.5, 24.15, 5.6);
	CGContextAddCurveToPoint(context, 24.25, 5.7, 24.3, 5.85, 24.3, 6.06);
	CGContextAddLineToPoint(context, 24.3, 6.59);
	CGContextAddCurveToPoint(context, 24.3, 7.85, 24.66, 8.86, 25.36, 9.61);
	CGContextAddCurveToPoint(context, 26.02, 10.37, 26.95, 10.75, 28.17, 10.75);
	CGContextAddLineToPoint(context, 43.76, 10.75);
	CGContextAddCurveToPoint(context, 44.97, 10.75, 45.93, 10.37, 46.63, 9.61);
	CGContextAddCurveToPoint(context, 47.39, 8.86, 47.77, 7.85, 47.77, 6.59);
	CGContextAddLineToPoint(context, 47.77, 6.06);
	CGContextAddCurveToPoint(context, 47.77, 5.85, 47.8, 5.7, 47.85, 5.6);
	CGContextAddCurveToPoint(context, 47.9, 5.5, 48.02, 5.45, 48.22, 5.45);
	CGContextAddLineToPoint(context, 55.42, 5.45);
	CGContextAddCurveToPoint(context, 59.35, 5.45, 62.23, 6.33, 64.04, 8.1);
	CGContextAddCurveToPoint(context, 65.81, 9.92, 66.69, 12.74, 66.69, 16.58);
	CGContextAddLineToPoint(context, 66.69, 111.5);
	CGContextAddCurveToPoint(context, 66.69, 115.33, 65.81, 118.13, 64.04, 119.9);
	CGContextAddCurveToPoint(context, 62.23, 121.67, 59.35, 122.55, 55.42, 122.55);
	CGContextAddLineToPoint(context, 16.51, 122.55);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 23.55, 118.76);
	CGContextAddLineToPoint(context, 48.38, 118.76);
	CGContextAddCurveToPoint(context, 49.08, 118.76, 49.66, 118.54, 50.12, 118.08);
	CGContextAddCurveToPoint(context, 50.62, 117.63, 50.87, 117.05, 50.87, 116.34);
	CGContextAddCurveToPoint(context, 50.87, 115.59, 50.62, 114.96, 50.12, 114.45);
	CGContextAddCurveToPoint(context, 49.66, 113.95, 49.08, 113.69, 48.38, 113.69);
	CGContextAddLineToPoint(context, 23.55, 113.69);
	CGContextAddCurveToPoint(context, 22.84, 113.69, 22.26, 113.95, 21.81, 114.45);
	CGContextAddCurveToPoint(context, 21.35, 114.96, 21.13, 115.59, 21.13, 116.34);
	CGContextAddCurveToPoint(context, 21.13, 117.05, 21.35, 117.63, 21.81, 118.08);
	CGContextAddCurveToPoint(context, 22.26, 118.54, 22.84, 118.76, 23.55, 118.76);
	CGContextAddLineToPoint(context, 23.55, 118.76);
	CGContextClosePath(context);

	CGContextSetFillColorWithColor(context, blackColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);
}

+ (CGImageRef)IPhoneCGImage
{
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(IPHONE_ICON_WIDTH, IPHONE_ICON_HEIGHT), NO, 0);
	[IPhoneVectorIcon drawIPhone];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, IPHONE_ICON_WIDTH, IPHONE_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(IPHONE_ICON_WIDTH, IPHONE_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[IPhoneVectorIcon drawIPhone];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
