//
//  BattmanVectorIcon.m
//  Battman
//
//  Created by Torrekie on 2025/8/16.
//  Copyright © 2025 Torrekie Network Tech. Co., Ltd. All rights reserved.
//

#import "BattmanVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define BATTMAN_ICON_WIDTH 1024
#define MIRROR(x) is_mirror ? (CGFloat)BATTMAN_ICON_WIDTH - x : x

@implementation   BattmanVectorIcon

static CGImageRef _iconCG = nil;

+ (void)drawBattman {
#if TARGET_OS_IPHONE
	CGContextRef context = UIGraphicsGetCurrentContext();
#else
	CGContextRef context = [NSGraphicsContext currentContext].CGContext;
	CGContextTranslateCTM(context, 0, BATTMAN_ICON_WIDTH);
	CGContextScaleCTM(context, 1.0, -1.0);
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	// Colors
	CGColorRef battdark       = CGColorCreateGenericRGB(46.0f / 255, 46.0f / 255, 47.0f / 255, 1.0);
	CGColorRef battwhite      = CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0);
	CGColorRef battgreen      = CGColorCreateGenericRGB(104.0f / 255, 206.0f / 255, 103.0f / 255, 1.0);
	CGColorRef gradient_start = CGColorCreateGenericRGB(229.0f / 255, 229.0f / 255, 234.0f / 255, 1.0);
	CGColorRef gradient_end   = CGColorCreateGenericRGB(142.0f / 255, 142.0f / 255, 147.0f / 255, 1.0);
#pragma clang diagnostic pop

	// Const
	CGFloat lineWidth      = 2.89;
	CGFloat miterLimit     = 4;

	CGFloat gradient_loc[] = { 0, 1 };
	void   *gradient_colors[2];
	gradient_colors[0]         = (void *)gradient_start;
	gradient_colors[1]         = (void *)gradient_end;
	CFArrayRef    gradient_arr = CFArrayCreate(kCFAllocatorDefault, (const void **)gradient_colors, 2, &kCFTypeArrayCallBacks);
	CGGradientRef gradient     = CGGradientCreateWithColors(NULL, gradient_arr, gradient_loc);

	// Background Gradient
	{
		CGContextSaveGState(context);
		CGContextClipToRect(context, CGRectMake(0, 0, BATTMAN_ICON_WIDTH, BATTMAN_ICON_WIDTH));
		CGContextDrawLinearGradient(context, gradient, CGPointMake(BATTMAN_ICON_WIDTH / 2, 0), CGPointMake(BATTMAN_ICON_WIDTH / 2, BATTMAN_ICON_WIDTH), kNilOptions);
		CGContextRestoreGState(context);
	}

	// Battman Bat Logo
	{
		// battman_frame
		{
			// wings
			for (int is_mirror = 0; is_mirror < 2; is_mirror++) {
				// top_arc
				CGMutablePathRef top_arc = CGPathCreateMutable();
				CGPathMoveToPoint(top_arc, NULL, MIRROR(650.61), 431.55);
				CGPathAddLineToPoint(top_arc, NULL, MIRROR(650.61), 431.55);
				CGPathAddCurveToPoint(top_arc, NULL, MIRROR(677.71), 424.8, MIRROR(700.44), 406.4, MIRROR(712.68), 381.29);
				CGPathAddLineToPoint(top_arc, NULL, MIRROR(712.68), 381.29);
				CGPathAddCurveToPoint(top_arc, NULL, MIRROR(724.67), 356.71, MIRROR(725.42), 328.13, MIRROR(714.73), 302.95);
				CGContextSaveGState(context);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextSetMiterLimit(context, miterLimit);
				CGContextSetLineJoin(context, kCGLineJoinRound);
				CGContextAddPath(context, top_arc);
				CGContextStrokePath(context);
				CGContextRestoreGState(context);
				CGPathRelease(top_arc);

				// large_arc
				CGMutablePathRef large_arc = CGPathCreateMutable();
				CGPathMoveToPoint(large_arc, NULL, MIRROR(920.87), 573.5);
				CGPathAddLineToPoint(large_arc, NULL, MIRROR(920.87), 573.5);
				CGPathAddCurveToPoint(large_arc, NULL, MIRROR(916.48), 447.75, MIRROR(832.77), 338.65, MIRROR(712.44), 301.86);
				CGContextSaveGState(context);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextSetMiterLimit(context, miterLimit);
				CGContextSetLineJoin(context, kCGLineJoinRound);
				CGContextAddPath(context, large_arc);
				CGContextStrokePath(context);
				CGContextRestoreGState(context);
				CGPathRelease(large_arc);

				// middle_arc
				CGMutablePathRef middle_arc = CGPathCreateMutable();
				CGPathMoveToPoint(middle_arc, NULL, MIRROR(920.73), 572.46);
				CGPathAddLineToPoint(middle_arc, NULL, MIRROR(920.87), 572.76);
				CGPathAddCurveToPoint(middle_arc, NULL, MIRROR(903.05), 534.55, MIRROR(862.08), 512.77, MIRROR(820.45), 519.37);
				CGPathAddLineToPoint(middle_arc, NULL, MIRROR(820.45), 519.37);
				CGPathAddCurveToPoint(middle_arc, NULL, MIRROR(778.82), 525.96, MIRROR(746.58), 559.34, MIRROR(741.45), 601.18);
				CGContextSaveGState(context);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextSetMiterLimit(context, miterLimit);
				CGContextSetLineJoin(context, kCGLineJoinRound);
				CGContextAddPath(context, middle_arc);
				CGContextStrokePath(context);
				CGContextRestoreGState(context);
				CGPathRelease(middle_arc);

				// little_arc
				CGMutablePathRef little_arc = CGPathCreateMutable();
				CGPathMoveToPoint(little_arc, NULL, MIRROR(742.19), 599.82);
				CGPathAddLineToPoint(little_arc, NULL, MIRROR(742), 599.61);
				CGPathAddCurveToPoint(little_arc, NULL, MIRROR(729.08), 585.26, MIRROR(709.48), 578.89, MIRROR(690.6), 582.9);
				CGPathAddLineToPoint(little_arc, NULL, MIRROR(690.6), 582.9);
				CGPathAddCurveToPoint(little_arc, NULL, MIRROR(671.71), 586.92, MIRROR(656.4), 600.7, MIRROR(650.43), 619.07);
				CGContextSaveGState(context);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextSetMiterLimit(context, miterLimit);
				CGContextSetLineJoin(context, kCGLineJoinRound);
				CGContextAddPath(context, little_arc);
				CGContextStrokePath(context);
				CGContextRestoreGState(context);
				CGPathRelease(little_arc);

				// fill
				CGMutablePathRef fill = CGPathCreateMutable();
				CGPathMoveToPoint(fill, NULL, MIRROR(717.09), 304.62);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(716.54), 307.07, MIRROR(718.63), 309.69, MIRROR(718.97), 312.27);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(722.25), 323.22, MIRROR(723.51), 334.65, MIRROR(722.62), 346.08);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(721.48), 370.85, MIRROR(709.52), 394.74, MIRROR(691.04), 411.16);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(679.66), 421.06, MIRROR(666.12), 428.26, MIRROR(651.54), 432.21);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(650.21), 434.73, MIRROR(651.37), 438.28, MIRROR(650.98), 441.19);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(650.97), 497.83, MIRROR(650.97), 554.48, MIRROR(650.96), 611.12);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(652.92), 613.29, MIRROR(654.04), 607.89, MIRROR(655.38), 606.63);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(663.84), 593.11, MIRROR(678.64), 583.5, MIRROR(694.47), 581.41);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(703.23), 581, MIRROR(712.42), 580.68, MIRROR(720.62), 584.29);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(727.7), 586.95, MIRROR(734.45), 590.96, MIRROR(740.07), 596.18);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(742.5), 596.3, MIRROR(741.61), 592.1, MIRROR(742.61), 590.4);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(749.56), 560.36, MIRROR(772.08), 534.6, MIRROR(800.97), 523.79);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(830.19), 512.23, MIRROR(865.13), 516.67, MIRROR(890.63), 535.15);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(901.93), 543.11, MIRROR(911), 553.77, MIRROR(918.25), 565.41);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(921.18), 566.08, MIRROR(918.78), 560.8, MIRROR(919.12), 558.99);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(914.79), 508.92, MIRROR(897.63), 459.96, MIRROR(869.18), 418.48);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(838.35), 372.9, MIRROR(794.36), 336.41, MIRROR(743.86), 314.54);
				CGPathAddCurveToPoint(fill, NULL, MIRROR(735.32), 310.83, MIRROR(726.7), 307.2, MIRROR(717.77), 304.51);
				CGPathAddLineToPoint(fill, NULL, MIRROR(717.26), 304.59);
				CGPathAddLineToPoint(fill, NULL, MIRROR(717.09), 304.62);
				CGPathCloseSubpath(fill);
				CGContextSaveGState(context);
				CGContextSetFillColorWithColor(context, battdark);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, 1.49);
				CGContextSetMiterLimit(context, miterLimit);
				CGContextSetLineJoin(context, kCGLineJoinRound);
				CGContextAddPath(context, fill);
				CGContextFillPath(context);
				CGContextStrokePath(context);
				CGContextRestoreGState(context);
				CGPathRelease(fill);
			}

			CGFloat cornerRadius = 30.24;

			// Frame
			{
				CGContextSaveGState(context);

				CGContextSetFillColorWithColor(context, battdark);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);

				CGPathRef path = CGPathCreateWithRoundedRect(CGRectMake(374.05, 304.51, 275.91, 417.26), cornerRadius, cornerRadius, NULL);
				CGContextAddPath(context, path);
				CGContextDrawPath(context, kCGPathFillStroke);
				CGPathRelease(path);

				CGContextRestoreGState(context);
			}

			// Frame_inner
			{
				CGContextSaveGState(context);

				CGContextSetFillColorWithColor(context, battwhite);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextFillRect(context, CGRectMake(402.39, 332.47, 219.21, 359.06));

				CGContextRestoreGState(context);
			}

			// top
			{
				CGContextSaveGState(context);

				CGContextSetFillColorWithColor(context, battdark);
				CGContextSetStrokeColorWithColor(context, battdark);
				CGContextSetLineWidth(context, lineWidth);
				CGContextFillRect(context, CGRectMake(466.18, 277.03, 91.65, 27.4));

				CGContextRestoreGState(context);
			}
		}

		// battery_levels
		{
			CGContextSaveGState(context);
			CGContextSetFillColorWithColor(context, battgreen);

			const CGFloat    ys[] = { 603.44, 517.36, 431.01, 344.97 };

			CGMutablePathRef path = CGPathCreateMutable();
			for (size_t i = 0; i < sizeof(ys) / sizeof(ys[0]); ++i)
				CGPathAddRect(path, NULL, CGRectMake(415.62, ys[i], 192.76, 75.59));

			CGContextAddPath(context, path);
			CGContextFillPath(context);
			CGPathRelease(path);

			CGContextRestoreGState(context);
		}
	}

	CGGradientRelease(gradient);
	CGContextRestoreGState(context);
}

+ (CGImageRef)BattmanCGImage {
	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(BATTMAN_ICON_WIDTH, BATTMAN_ICON_WIDTH), NO, 0);
	[BattmanVectorIcon drawBattman];
	_iconCG = UIGraphicsGetImageFromCurrentImageContext().CGImage;
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, BATTMAN_ICON_WIDTH, BATTMAN_ICON_WIDTH));
	_iconCG          = [[NSImage imageWithSize:NSMakeSize(BATTMAN_ICON_WIDTH, BATTMAN_ICON_WIDTH) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
        [BattmanVectorIcon drawBattman];
        return YES;
    }] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil];
#endif
	return _iconCG;
}

@end
