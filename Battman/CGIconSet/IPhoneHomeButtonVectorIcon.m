#import "IPhoneHomeButtonVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define IPHONE_HOME_ICON_WIDTH 72
#define IPHONE_HOME_ICON_HEIGHT 128

@implementation IPhoneHomeButtonVectorIcon

+ (void)drawIPhoneHomeButton {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, IPHONE_HOME_ICON_HEIGHT);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

	CGContextSaveGState(context);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop

	CGContextBeginPath(context);
	CGContextMoveToPoint(context, -0.14, 111.8);
	CGContextAddCurveToPoint(context, -0.14, 117.1, 1.22, 121.11, 3.94, 123.84);
	CGContextAddCurveToPoint(context, 6.62, 126.61, 10.65, 128, 16.05, 128);
	CGContextAddLineToPoint(context, 56.02, 128);
	CGContextAddCurveToPoint(context, 61.37, 128, 65.38, 126.61, 68.06, 123.84);
	CGContextAddCurveToPoint(context, 70.78, 121.11, 72.14, 117.1, 72.14, 111.8);
	CGContextAddLineToPoint(context, 72.14, 16.2);
	CGContextAddCurveToPoint(context, 72.14, 10.9, 70.78, 6.89, 68.06, 4.16);
	CGContextAddCurveToPoint(context, 65.38, 1.39, 61.37, 0, 56.02, 0);
	CGContextAddLineToPoint(context, 16.05, 0);
	CGContextAddCurveToPoint(context, 10.65, 0, 6.62, 1.39, 3.94, 4.16);
	CGContextAddCurveToPoint(context, 1.22, 6.89, -0.14, 10.9, -0.14, 16.2);
	CGContextAddLineToPoint(context, -0.14, 111.8);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 25.9, 9.76);
	CGContextAddCurveToPoint(context, 25.9, 9.06, 26.15, 8.48, 26.65, 8.02);
	CGContextAddCurveToPoint(context, 27.11, 7.57, 27.69, 7.34, 28.39, 7.34);
	CGContextAddLineToPoint(context, 43.61, 7.34);
	CGContextAddCurveToPoint(context, 44.36, 7.34, 44.97, 7.57, 45.42, 8.02);
	CGContextAddCurveToPoint(context, 45.88, 8.48, 46.11, 9.06, 46.11, 9.76);
	CGContextAddCurveToPoint(context, 46.11, 10.42, 45.88, 11, 45.42, 11.51);
	CGContextAddCurveToPoint(context, 44.97, 12.01, 44.36, 12.26, 43.61, 12.26);
	CGContextAddLineToPoint(context, 28.39, 12.26);
	CGContextAddCurveToPoint(context, 27.69, 12.26, 27.11, 12.01, 26.65, 11.51);
	CGContextAddCurveToPoint(context, 26.15, 11, 25.89, 10.42, 25.89, 9.76);
	CGContextAddLineToPoint(context, 25.9, 9.76);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 5.31, 108.93);
	CGContextAddLineToPoint(context, 5.31, 19.08);
	CGContextAddLineToPoint(context, 66.69, 19.08);
	CGContextAddLineToPoint(context, 66.69, 108.93);
	CGContextAddLineToPoint(context, 5.31, 108.93);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 36.04, 121.87);
	CGContextAddCurveToPoint(context, 34.88, 121.82, 33.87, 121.39, 33.01, 120.58);
	CGContextAddCurveToPoint(context, 32.2, 119.82, 31.77, 118.82, 31.72, 117.55);
	CGContextAddCurveToPoint(context, 31.77, 116.34, 32.2, 115.33, 33.01, 114.53);
	CGContextAddCurveToPoint(context, 33.87, 113.72, 34.88, 113.29, 36.04, 113.24);
	CGContextAddCurveToPoint(context, 37.3, 113.29, 38.33, 113.72, 39.14, 114.53);
	CGContextAddCurveToPoint(context, 39.9, 115.33, 40.3, 116.34, 40.35, 117.55);
	CGContextAddCurveToPoint(context, 40.3, 118.82, 39.9, 119.82, 39.14, 120.58);
	CGContextAddCurveToPoint(context, 38.33, 121.39, 37.3, 121.82, 36.04, 121.87);
	CGContextAddLineToPoint(context, 36.04, 121.87);
	CGContextClosePath(context);

	CGContextSetFillColorWithColor(context, blackColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);
}

+ (CGImageRef)IPhoneHomeButtonCGImage
{
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(IPHONE_HOME_ICON_WIDTH, IPHONE_HOME_ICON_HEIGHT), NO, 0);
	[IPhoneHomeButtonVectorIcon drawIPhoneHomeButton];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, IPHONE_HOME_ICON_WIDTH, IPHONE_HOME_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(IPHONE_HOME_ICON_WIDTH, IPHONE_HOME_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[IPhoneHomeButtonVectorIcon drawIPhoneHomeButton];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
