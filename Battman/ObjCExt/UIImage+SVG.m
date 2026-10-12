//
//  UIImage+SVG.m
//  Battman
//
//  Created by Torrekie on 2025/10/6.
//

#import "UIImage+SVG.h"
#import "UIScreen+Auto.h"
#import "../SVG.h"

#include <dlfcn.h>
#include <math.h>

@implementation UIImage (SVG)

+ (UIImage *)legacySymbolImageForGlyph:(NSString *)glyph pointSize:(CGFloat)size color:(UIColor *)color {
	NSDictionary *names = @{@"􀛨": @"battery.100", @"􀣉": @"chart.bar.xaxis", @"􀈂": @"square.and.arrow.up",
		@"􀆄": @"xmark", @"􀆅": @"checkmark", @"􀎡": @"lock.fill", @"􀇾": @"exclamationmark.triangle",
		@"􀅴": @"info.circle", @"􀊛": @"pause.rectangle", @"􀣁": @"arrow.rectanglepath"};
	NSString *name = names[glyph];
	if (!name || !isfinite(size) || size <= 0) return nil;
	CGSize canvas = CGSizeMake(size * 1.2, size);
	UIGraphicsBeginImageContextWithOptions(canvas, NO, 0);
	UIImage *systemImage = nil;
	if (@available(iOS 13.0, *)) systemImage = [UIImage systemImageNamed:name];
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (systemImage) {
		CGFloat scale = MIN(canvas.width / systemImage.size.width, canvas.height / systemImage.size.height);
		CGSize scaled = CGSizeMake(systemImage.size.width * scale, systemImage.size.height * scale);
		[systemImage drawInRect:CGRectMake((canvas.width-scaled.width)/2, (canvas.height-scaled.height)/2, scaled.width, scaled.height)];
		[color setFill]; UIRectFillUsingBlendMode((CGRect){CGPointZero, canvas}, kCGBlendModeSourceIn);
	} else {
		CGContextScaleCTM(ctx, canvas.width / 24, canvas.height / 20);
		CGContextSetStrokeColorWithColor(ctx, color.CGColor);
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetLineWidth(ctx, 1.6);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		if ([name isEqual:@"battery.100"]) {
			CGContextStrokeRect(ctx, CGRectMake(2,5,18,10)); CGContextFillRect(ctx, CGRectMake(4,7,14,6));
			CGContextFillRect(ctx, CGRectMake(21,8,1.5,4));
		} else if ([name isEqual:@"chart.bar.xaxis"]) {
			CGContextMoveToPoint(ctx,2,18); CGContextAddLineToPoint(ctx,22,18); CGContextStrokePath(ctx);
			CGContextFillRect(ctx,CGRectMake(4,10,3,6)); CGContextFillRect(ctx,CGRectMake(10,3,3,13)); CGContextFillRect(ctx,CGRectMake(16,7,3,9));
		} else if ([name isEqual:@"square.and.arrow.up"]) {
			CGContextMoveToPoint(ctx,7,7); CGContextAddLineToPoint(ctx,4,7); CGContextAddLineToPoint(ctx,4,18);
			CGContextAddLineToPoint(ctx,20,18); CGContextAddLineToPoint(ctx,20,7); CGContextAddLineToPoint(ctx,17,7);
			CGContextMoveToPoint(ctx,12,12); CGContextAddLineToPoint(ctx,12,2);
			CGContextMoveToPoint(ctx,8,6); CGContextAddLineToPoint(ctx,12,2); CGContextAddLineToPoint(ctx,16,6); CGContextStrokePath(ctx);
		} else if ([name isEqual:@"xmark"] || [name isEqual:@"checkmark"]) {
			if ([name isEqual:@"xmark"]) {
				CGContextMoveToPoint(ctx,6,4); CGContextAddLineToPoint(ctx,18,16); CGContextMoveToPoint(ctx,18,4); CGContextAddLineToPoint(ctx,6,16);
			} else { CGContextMoveToPoint(ctx,4,10); CGContextAddLineToPoint(ctx,10,16); CGContextAddLineToPoint(ctx,20,4); }
			CGContextStrokePath(ctx);
		} else if ([name isEqual:@"lock.fill"]) {
			CGContextAddArc(ctx,12,7,4,M_PI,0,0); CGContextStrokePath(ctx); CGContextFillRect(ctx,CGRectMake(6,7,12,11));
		} else if ([name isEqual:@"exclamationmark.triangle"]) {
			CGContextMoveToPoint(ctx,12,2); CGContextAddLineToPoint(ctx,22,18); CGContextAddLineToPoint(ctx,2,18); CGContextClosePath(ctx); CGContextStrokePath(ctx);
			CGContextMoveToPoint(ctx,12,7); CGContextAddLineToPoint(ctx,12,12); CGContextStrokePath(ctx); CGContextFillEllipseInRect(ctx,CGRectMake(11.2,14,1.6,1.6));
		} else if ([name isEqual:@"info.circle"]) {
			CGContextStrokeEllipseInRect(ctx,CGRectMake(3,1,18,18)); CGContextFillEllipseInRect(ctx,CGRectMake(11.1,5,1.8,1.8));
			CGContextMoveToPoint(ctx,12,9); CGContextAddLineToPoint(ctx,12,15); CGContextStrokePath(ctx);
		} else if ([name isEqual:@"pause.rectangle"]) {
			CGContextStrokeRect(ctx,CGRectMake(2,3,20,14)); CGContextFillRect(ctx,CGRectMake(8,6,2.5,8)); CGContextFillRect(ctx,CGRectMake(13.5,6,2.5,8));
		} else {
			CGContextMoveToPoint(ctx,3,9); CGContextAddLineToPoint(ctx,3,4); CGContextAddLineToPoint(ctx,21,4);
			CGContextAddLineToPoint(ctx,18,1); CGContextMoveToPoint(ctx,21,4); CGContextAddLineToPoint(ctx,18,7);
			CGContextMoveToPoint(ctx,21,11); CGContextAddLineToPoint(ctx,21,16); CGContextAddLineToPoint(ctx,3,16);
			CGContextAddLineToPoint(ctx,6,13); CGContextMoveToPoint(ctx,3,16); CGContextAddLineToPoint(ctx,6,19); CGContextStrokePath(ctx);
		}
	}
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return result;
}

+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData {
	return [self imageWithSVGData:svgData scale:0.0];
}

+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData scale:(CGFloat)scale {
	if (!svgData || svgData.length == 0) return nil;

	SVG *svg = [[SVG alloc] initWithData:svgData];
	if (!svg) return nil;

	CGSize size = svg.size;
	if (CGSizeEqualToSize(size, CGSizeZero)) return nil;

	if (scale <= 0.0) {
		UIScreen *screen = UIScreen.autoScreen;
		scale = screen ? screen.scale : 2.0;
	}

	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
	format.scale = scale;
	format.opaque = NO;

	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];

	UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
		CGContextRef cgctx = ctx.CGContext;
		// svg is expected to draw correctly into the provided CGContext
		[svg drawInContext:cgctx size:size];
	}];
	
	return image;
}

+ (nullable UIImage *)presetSVGImageNamed:(NSString *)name {
	if (name.length == 0) return nil;
	
	// Simple cache keyed by name@scale
	static NSCache *sCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sCache = [NSCache new];
		sCache.countLimit = 16; // tune as needed
	});

	UIScreen *screen = UIScreen.autoScreen;
	CGFloat scale = screen ? screen.scale : 2.0;
	NSString *cacheKey = [NSString stringWithFormat:@"%@@%.2f", name, scale];
	UIImage *cached = [sCache objectForKey:cacheKey];
	if (cached) return cached;
	
	NSData *svgData = [self presetSVGDataForName:name];
	if (!svgData) return nil;

	UIImage *img = [self imageWithSVGData:svgData scale:scale];
	if (!img) return nil;

	UIImage *templ = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	[sCache setObject:templ forKey:cacheKey];
	return templ;
}

+ (nullable UIImage *)systemImageNamedOrPreset:(NSString *)name {
	if (name.length == 0) return nil;
	
	// Prefer system symbol when available (iOS 13+). If not available, fall back to preset.
	if (@available(iOS 13.0, *)) {
		UIImage *sys = [UIImage systemImageNamed:name];
		if (sys) return sys;
	}
	
	return [self presetSVGImageNamed:name];
}

#pragma mark - Helpers

+ (nullable NSData *)presetSVGDataForName:(NSString *)name {
	if (name.length == 0) return nil;

	// Cache
	static NSCache *sCache;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sCache = [NSCache new];
		sCache.countLimit = 16;
	});

	NSData *cached = [sCache objectForKey:name];
	if (cached) return cached;

	// generator: non-alnum -> '_' ; strip extension earlier; prefix '_' if first char is digit
	NSMutableString *san = [NSMutableString stringWithCapacity:name.length];
	for (NSUInteger i = 0; i < name.length; ++i) {
		unichar c = [name characterAtIndex:i];
		if ((c >= '0' && c <= '9') ||
			(c >= 'A' && c <= 'Z') ||
			(c >= 'a' && c <= 'z') ||
			c == '_') {
			[san appendFormat:@"%C", c];
		} else {
			[san appendString:@"_"];
		}
	}
	// If generator removed extension first, caller should pass "basename" (without .svg);
	// If callers pass e.g. "preset.checkmark", this becomes "preset_checkmark"
	if (san.length > 0) {
		unichar first = [san characterAtIndex:0];
		if (first >= '0' && first <= '9') {
			[san insertString:@"_" atIndex:0];
		}
	} else {
		return nil;
	}

	NSString *symDataName = [NSString stringWithFormat:@"svg_%@", san];
	NSString *symLenName = [symDataName stringByAppendingString:@"_len"];

	static void *mainHandle = NULL;
	if (!mainHandle) {
		mainHandle = dlopen(NULL, RTLD_LAZY);
		if (!mainHandle) {
			// unlikely, but bail
			return nil;
		}
	}

	const uint8_t *dataPtr = (const uint8_t *)dlsym(mainHandle, symDataName.UTF8String);
	const size_t *lenPtr = (const size_t *)dlsym(mainHandle, symLenName.UTF8String);
	
	if (!dataPtr || !lenPtr) {
		NSString *altSan = [name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
		NSString *altSymData = [NSString stringWithFormat:@"svg_%@", altSan];
		NSString *altSymLen = [altSymData stringByAppendingString:@"_len"];
		dataPtr = (const uint8_t *)dlsym(mainHandle, altSymData.UTF8String);
		lenPtr = (const size_t *)dlsym(mainHandle, altSymLen.UTF8String);
	}
	
	if (!dataPtr || !lenPtr) return nil;
	
	size_t len = *lenPtr;
	if (len == 0) return nil;

	NSData *data = [NSData dataWithBytesNoCopy:(void *)dataPtr length:len freeWhenDone:NO];
	if (data) [sCache setObject:data forKey:name];
	return data;
}


@end
