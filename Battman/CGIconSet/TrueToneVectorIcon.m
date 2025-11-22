#import "TrueToneVectorIcon.h"
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#define TRUE_TONE_ICON_WIDTH 30
#define TRUE_TONE_ICON_HEIGHT 30

@implementation TrueToneVectorIcon

+ (void)drawTrueTone {
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
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}
	
	{
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			{
				CGContextSaveGState(context);
				CGContextBeginTransparencyLayer(context, NULL);
				
				CGContextBeginPath(context);
				CGContextMoveToPoint(context, 24.5, 23);
				CGContextAddLineToPoint(context, 4.96, 23);
				CGContextAddCurveToPoint(context, 4.48, 23, 4.09, 22.22, 4.09, 21.25);
				CGContextAddCurveToPoint(context, 4.09, 20.28, 4.48, 19.5, 4.96, 19.5);
				CGContextAddLineToPoint(context, 24.5, 19.5);
				CGContextAddCurveToPoint(context, 24.98, 19.5, 25.37, 20.28, 25.37, 21.25);
				CGContextAddCurveToPoint(context, 25.37, 22.22, 24.98, 23, 24.5, 23);
				CGContextClosePath(context);
				CGContextClip(context);
				{
					CGContextSaveGState(context);
					CGContextBeginTransparencyLayer(context, NULL);
					
					CGContextBeginPath(context);
					CGContextAddRect(context, CGRectMake(8, 8, 14, 14));
					CGContextClosePath(context);
					CGContextClip(context);
					CGContextSetFillColorWithColor(context, blackColor);
					CGContextFillRect(context, CGRectMake(-0.88, 14.5, 31.25, 13.5));
					
					CGContextEndTransparencyLayer(context);
					CGContextRestoreGState(context);
				}
				CGContextEndTransparencyLayer(context);
				CGContextRestoreGState(context);
			}
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}
	
	{
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			{
				CGContextSaveGState(context);
				CGContextBeginTransparencyLayer(context, NULL);
				
				CGContextBeginPath(context);
				CGContextMoveToPoint(context, 24.63, 18.5);
				CGContextAddLineToPoint(context, 5.09, 18.5);
				CGContextAddCurveToPoint(context, 4.69, 18.5, 4.37, 18.05, 4.37, 17.5);
				CGContextAddCurveToPoint(context, 4.37, 16.95, 4.69, 16.5, 5.09, 16.5);
				CGContextAddLineToPoint(context, 24.63, 16.5);
				CGContextAddCurveToPoint(context, 25.03, 16.5, 25.35, 16.95, 25.35, 17.5);
				CGContextAddCurveToPoint(context, 25.35, 18.05, 25.03, 18.5, 24.63, 18.5);
				CGContextClosePath(context);
				CGContextClip(context);
				{
					CGContextSaveGState(context);
					CGContextBeginTransparencyLayer(context, NULL);
					
					CGContextBeginPath(context);
					CGContextAddRect(context, CGRectMake(8, 8, 14, 14));
					CGContextClosePath(context);
					CGContextClip(context);
					CGContextSetFillColorWithColor(context, blackColor);
					CGContextFillRect(context, CGRectMake(-0.65, 11.5, 31, 12));
					
					CGContextEndTransparencyLayer(context);
					CGContextRestoreGState(context);
				}
				CGContextEndTransparencyLayer(context);
				CGContextRestoreGState(context);
			}
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}

	{
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			{
				CGContextSaveGState(context);
				CGContextBeginTransparencyLayer(context, NULL);
				
				CGContextBeginPath(context);
				CGContextMoveToPoint(context, 24.76, 15.25);
				CGContextAddLineToPoint(context, 5.21, 15.25);
				CGContextAddCurveToPoint(context, 4.9, 15.25, 4.64, 14.91, 4.64, 14.5);
				CGContextAddCurveToPoint(context, 4.64, 14.09, 4.9, 13.75, 5.21, 13.75);
				CGContextAddLineToPoint(context, 24.76, 13.75);
				CGContextAddCurveToPoint(context, 25.08, 13.75, 25.33, 14.09, 25.33, 14.5);
				CGContextAddCurveToPoint(context, 25.33, 14.91, 25.08, 15.25, 24.76, 15.25);
				CGContextClosePath(context);
				CGContextClip(context);
				{
					CGContextSaveGState(context);
					CGContextBeginTransparencyLayer(context, NULL);
					
					CGContextBeginPath(context);
					CGContextAddRect(context, CGRectMake(8, 8, 14, 14));
					CGContextClosePath(context);
					CGContextClip(context);
					CGContextSetFillColorWithColor(context, blackColor);
					CGContextFillRect(context, CGRectMake(-0.35, 8.75, 30.7, 11.5));
					
					CGContextEndTransparencyLayer(context);
					CGContextRestoreGState(context);
				}
				CGContextEndTransparencyLayer(context);
				CGContextRestoreGState(context);
			}
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}
	
	{
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			{
				CGContextSaveGState(context);
				CGContextBeginTransparencyLayer(context, NULL);
				
				CGContextBeginPath(context);
				CGContextMoveToPoint(context, 24.89, 12);
				CGContextAddLineToPoint(context, 5.34, 12);
				CGContextAddCurveToPoint(context, 5.11, 12, 4.92, 11.78, 4.92, 11.5);
				CGContextAddCurveToPoint(context, 4.92, 11.22, 5.11, 11, 5.34, 11);
				CGContextAddLineToPoint(context, 24.89, 11);
				CGContextAddCurveToPoint(context, 25.12, 11, 25.31, 11.22, 25.31, 11.5);
				CGContextAddCurveToPoint(context, 25.31, 11.78, 25.12, 12, 24.89, 12);
				CGContextClosePath(context);
				CGContextClip(context);
				{
					CGContextSaveGState(context);
					CGContextBeginTransparencyLayer(context, NULL);
					
					CGContextBeginPath(context);
					CGContextAddRect(context, CGRectMake(8, 8, 14, 14));
					CGContextClosePath(context);
					CGContextClip(context);
					CGContextSetFillColorWithColor(context, blackColor);
					CGContextFillRect(context, CGRectMake(-0.1, 6, 30.4, 11));
					
					CGContextEndTransparencyLayer(context);
					CGContextRestoreGState(context);
				}
				CGContextEndTransparencyLayer(context);
				CGContextRestoreGState(context);
			}
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}

	{
		CGContextSaveGState(context);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextBeginPath(context);
		CGContextAddEllipseInRect(context, CGRectMake(8, 8, 14, 14));
		CGContextClosePath(context);
		CGContextClip(context);
		
		{
			CGContextSaveGState(context);
			CGContextBeginTransparencyLayer(context, NULL);
			
			CGContextBeginPath(context);
			CGContextAddRect(context, CGRectMake(7, 8, 15, 14));
			CGContextClosePath(context);
			CGContextClip(context);
			{
				CGContextSaveGState(context);
				CGContextBeginTransparencyLayer(context, NULL);
				
				CGContextBeginPath(context);
				CGContextMoveToPoint(context, 25.02, 9);
				CGContextAddLineToPoint(context, 5.47, 9);
				CGContextAddCurveToPoint(context, 5.32, 9, 5.2, 8.55, 5.2, 8);
				CGContextAddCurveToPoint(context, 5.2, 7.45, 5.32, 7, 5.47, 7);
				CGContextAddLineToPoint(context, 25.02, 7);
				CGContextAddCurveToPoint(context, 25.17, 7, 25.29, 7.45, 25.29, 8);
				CGContextAddCurveToPoint(context, 25.29, 8.55, 25.17, 9, 25.02, 9);
				CGContextClosePath(context);
				CGContextClip(context);
				{
					CGContextSaveGState(context);
					CGContextBeginTransparencyLayer(context, NULL);
					
					CGContextBeginPath(context);
					CGContextAddRect(context, CGRectMake(8, 8, 14, 14));
					CGContextClosePath(context);
					CGContextClip(context);
					CGContextSetFillColorWithColor(context, blackColor);
					CGContextFillRect(context, CGRectMake(0.2, 2, 30.1, 12));
					
					CGContextEndTransparencyLayer(context);
					CGContextRestoreGState(context);
				}
				CGContextEndTransparencyLayer(context);
				CGContextRestoreGState(context);
			}
			CGContextEndTransparencyLayer(context);
			CGContextRestoreGState(context);
		}
		CGContextEndTransparencyLayer(context);
		CGContextRestoreGState(context);
	}

	CGContextSetStrokeColorWithColor(context, blackColor);
	CGContextSetLineCap(context, kCGLineCapRound);

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
	
	CGContextRestoreGState(context);
}

+ (CGImageRef)TrueToneCGImage {
	static CGImageRef _iconCG = nil;

	if (_iconCG)
		return _iconCG;
#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(TRUE_TONE_ICON_WIDTH, TRUE_TONE_ICON_HEIGHT), NO, 0);
	[TrueToneVectorIcon drawTrueTone];
	_iconCG = CGImageCreateCopy(UIGraphicsGetImageFromCurrentImageContext().CGImage);
	UIGraphicsEndImageContext();
#else
	NSRect imageRect = NSRectFromCGRect(CGRectMake(0, 0, TRUE_TONE_ICON_WIDTH, TRUE_TONE_ICON_HEIGHT));
	_iconCG          = CGImageCreateCopy([[NSImage imageWithSize:NSMakeSize(TRUE_TONE_ICON_WIDTH, TRUE_TONE_ICON_HEIGHT) flipped:NO drawingHandler:^(__unused NSRect dstRect) {
		[TrueToneVectorIcon drawTrueTone];
		return YES;
	}] CGImageForProposedRect:&imageRect context:[NSGraphicsContext currentContext] hints:nil]);
#endif
	return _iconCG;
}

@end
