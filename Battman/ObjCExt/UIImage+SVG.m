//
//  UIImage+SVG.m
//  Battman
//
//  Created by Torrekie on 2025/10/6.
//

#import "UIImage+SVG.h"
#import "SVG.h"

#include <dlfcn.h>

@implementation UIImage (SVG)

+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData {
	return [self imageWithSVGData:svgData scale:0.0];
}

+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData scale:(CGFloat)scale {
	if (!svgData || svgData.length == 0) return nil;

	SVG *svg = [[SVG alloc] initWithData:svgData];
	if (!svg) return nil;

	CGSize size = svg.size;
	if (CGSizeEqualToSize(size, CGSizeZero)) return nil;

	if (scale <= 0.0) scale = UIScreen.mainScreen.scale;

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

	CGFloat scale = UIScreen.mainScreen.scale;
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
