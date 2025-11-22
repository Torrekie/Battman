#import "DesktopVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define DESKTOP_ICON_WIDTH 128
#define DESKTOP_ICON_HEIGHT 108

@implementation DesktopVectorIcon

+ (void)drawDesktop {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, DESKTOP_ICON_HEIGHT);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

	CGContextSaveGState(context);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	CGColorRef blackColor = CGColorGetConstantColor(kCGColorBlack);
#pragma clang diagnostic pop

	CGContextBeginPath(context);
	CGContextMoveToPoint(context, 44.29, 108.02);
	CGContextAddLineToPoint(context, 83.53, 108.02);
	CGContextAddCurveToPoint(context, 84.85, 108.02, 85.99, 107.54, 86.95, 106.58);
	CGContextAddCurveToPoint(context, 87.79, 105.62, 88.21, 104.48, 88.21, 103.16);
	CGContextAddCurveToPoint(context, 88.21, 101.84, 87.73, 100.7, 86.77, 99.74);
	CGContextAddCurveToPoint(context, 85.93, 98.9, 84.85, 98.48, 83.53, 98.48);
	CGContextAddLineToPoint(context, 81.01, 98.48);
	CGContextAddLineToPoint(context, 81.01, 88.93);
	CGContextAddLineToPoint(context, 117.74, 88.93);
	CGContextAddCurveToPoint(context, 120.86, 88.93, 123.32, 88.03, 125.12, 86.23);
	CGContextAddCurveToPoint(context, 127.04, 84.43, 128, 81.97, 128, 78.85);
	CGContextAddLineToPoint(context, 128, 10.08);
	CGContextAddCurveToPoint(context, 128, 6.96, 127.1, 4.5, 125.3, 2.7);
	CGContextAddCurveToPoint(context, 123.5, 0.9, 120.98, 0, 117.74, 0);
	CGContextAddLineToPoint(context, 10.08, 0);
	CGContextAddCurveToPoint(context, 6.96, 0, 4.5, 0.9, 2.7, 2.7);
	CGContextAddCurveToPoint(context, 0.9, 4.5, 0, 6.96, 0, 10.08);
	CGContextAddLineToPoint(context, 0, 78.85);
	CGContextAddCurveToPoint(context, 0, 81.97, 0.9, 84.43, 2.7, 86.23);
	CGContextAddCurveToPoint(context, 4.5, 88.03, 6.96, 88.93, 10.08, 88.93);
	CGContextAddLineToPoint(context, 46.81, 88.93);
	CGContextAddLineToPoint(context, 46.81, 98.48);
	CGContextAddLineToPoint(context, 44.29, 98.48);
	CGContextAddCurveToPoint(context, 42.97, 98.48, 41.89, 98.9, 41.05, 99.74);
	CGContextAddCurveToPoint(context, 40.21, 100.7, 39.79, 101.84, 39.79, 103.16);
	CGContextAddCurveToPoint(context, 39.79, 104.48, 40.21, 105.62, 41.05, 106.58);
	CGContextAddCurveToPoint(context, 41.89, 107.54, 42.97, 108.02, 44.29, 108.02);
	CGContextAddLineToPoint(context, 44.29, 108.02);
	CGContextClosePath(context);
	CGContextMoveToPoint(context, 11.7, 65.71);
	CGContextAddCurveToPoint(context, 10.86, 65.71, 10.26, 65.53, 9.9, 65.17);
	CGContextAddCurveToPoint(context, 9.54, 64.93, 9.36, 64.45, 9.36, 63.73);
	CGContextAddLineToPoint(context, 9.36, 12.6);
	CGContextAddCurveToPoint(context, 9.36, 11.64, 9.66, 10.86, 10.26, 10.26);
	CGContextAddCurveToPoint(context, 10.74, 9.66, 11.52, 9.36, 12.6, 9.36);
	CGContextAddLineToPoint(context, 115.22, 9.36);
	CGContextAddCurveToPoint(context, 116.3, 9.36, 117.14, 9.66, 117.74, 10.26);
	CGContextAddCurveToPoint(context, 118.34, 10.86, 118.64, 11.64, 118.64, 12.6);
	CGContextAddLineToPoint(context, 118.64, 63.73);
	CGContextAddCurveToPoint(context, 118.64, 64.45, 118.46, 64.93, 118.1, 65.17);
	CGContextAddCurveToPoint(context, 117.62, 65.53, 116.96, 65.71, 116.12, 65.71);
	CGContextAddLineToPoint(context, 11.7, 65.71);
	CGContextClosePath(context);

	CGContextSetFillColorWithColor(context, blackColor);
	CGContextFillPath(context);

	CGContextRestoreGState(context);
}

+ (CGImageRef)DesktopCGImage
{
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(DESKTOP_ICON_WIDTH, DESKTOP_ICON_HEIGHT), NO, 0);
	[DesktopVectorIcon drawDesktop];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, DESKTOP_ICON_WIDTH, DESKTOP_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(DESKTOP_ICON_WIDTH, DESKTOP_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[DesktopVectorIcon drawDesktop];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
