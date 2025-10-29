//
//  GradientSDRView.m
//  Battman
//
//  Created by ChatGPT on behalf of Torrekie.
//  This implements the same radial gradient visual, without Metal/HDR.
//

#import "main.h"
#import "common.h"
#import "ObjCExt/UIScreen+Auto.h"
#import "GradientSDRView.h"
#import "BattmanPrefs.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

@interface GradientSDRView () {
	// We no longer use Metal. We'll render into a CGImage and set layer.contents.
	float _gradientRadius;       // relative 0..1
	float _gradientBrightness;   // multiplier
	
	// Animation
	CADisplayLink *_animationDisplayLink;
	NSTimeInterval _animationStartTime;
	NSTimeInterval _animationDuration;
	float _animationFromRadius;
	float _animationToRadius;
	float _animationFromBrightness;
	float _animationToBrightness;
	
	// Cached last rendered size (pixels)
	CGSize _lastRenderedPixelSize;
}

@end

@implementation GradientSDRView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) [self setupView];
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) [self setupView];
	return self;
}

- (void)setupView {
	// Layer setup: we will draw into an image and set layer.contents
	self.layer.masksToBounds = YES;
	self.layer.contentsGravity = kCAGravityResizeAspectFill;
	self.layer.contentsScale = [UIScreen autoScreen].scale;
	
	// initial parameters (match original)
	_gradientRadius = 0.4f;
	_gradientBrightness = 2.2f;
	
	// Observe app lifecycle to release resources / re-render
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (_animationDisplayLink) {
		[_animationDisplayLink invalidate];
		_animationDisplayLink = nil;
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Re-render at new size
	[self renderAsyncIfNeededForce:YES];
}

#pragma mark - Public Methods

- (void)setBrightness:(int)percentage animated:(BOOL)animated {
	percentage = MAX(0, MIN(100, percentage)) * 0.8;
	float normalizedValue = percentage / 100.0f;
	float newRadius = normalizedValue * 0.8f + 0.2f;
	
	float newBrightness = normalizedValue * 2.0f + 1.0f;
	
	if (animated) {
		// animate using display link
		dispatch_async(dispatch_get_main_queue(), ^{
			[self animateFromRadius:self->_gradientRadius toRadius:newRadius fromBrightness:self->_gradientBrightness toBrightness:newBrightness duration:0.5];
		});
	} else {
		_gradientRadius = newRadius;
		_gradientBrightness = newBrightness;
		[self renderAsyncIfNeededForce:YES];
	}
}

- (void)animateFromRadius:(float)fromRadius toRadius:(float)toRadius fromBrightness:(float)fromBrightness toBrightness:(float)toBrightness duration:(NSTimeInterval)duration {
	if (_animationDisplayLink) {
		[_animationDisplayLink invalidate];
		_animationDisplayLink = nil;
	}
	
	_animationStartTime = CACurrentMediaTime();
	_animationDuration = duration;
	_animationFromRadius = fromRadius;
	_animationToRadius = toRadius;
	_animationFromBrightness = fromBrightness;
	_animationToBrightness = toBrightness;
	
	_animationDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(animationStep:)];
	[_animationDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)animationStep:(CADisplayLink *)displayLink {
	NSTimeInterval now = CACurrentMediaTime();
	NSTimeInterval elapsed = now - _animationStartTime;
	
	if (elapsed >= _animationDuration) {
		_gradientRadius = _animationToRadius;
		_gradientBrightness = _animationToBrightness;
		[_animationDisplayLink invalidate];
		_animationDisplayLink = nil;
	} else {
		float p = elapsed / _animationDuration;
		// ease-in-out
		float progress = p * p * (3.0f - 2.0f * p);
		_gradientRadius = _animationFromRadius + (_animationToRadius - _animationFromRadius) * progress;
		_gradientBrightness = _animationFromBrightness + (_animationToBrightness - _animationFromBrightness) * progress;
	}
	
	[self renderAsyncIfNeededForce:NO];
}

#pragma mark - Rendering (bitmap)

/// Returns pixel size for current layer bounds & contentsScale
- (CGSize)pixelSizeForCurrentBounds {
	CGFloat scale = self.layer.contentsScale > 0 ? self.layer.contentsScale : [UIScreen autoScreen].scale;
	CGSize s = self.bounds.size;
	if (s.width <= 0 || s.height <= 0) return CGSizeZero;
	return CGSizeMake(ceil(s.width * scale), ceil(s.height * scale));
}

/// Publicly exposed accessors
- (float)gradientRadius { return _gradientRadius; }
- (float)gradientBrightness { return _gradientBrightness; }

/// Main entry: render asynchronously to avoid blocking UI thread for large sizes.
/// If force==YES, always re-render even if size unchanged.
- (void)renderAsyncIfNeededForce:(BOOL)force {
	CGSize pixelSize = [self pixelSizeForCurrentBounds];
	if (CGSizeEqualToSize(pixelSize, CGSizeZero)) return;
	
	// If nothing changed and we already rendered for this size and parameters, skip unless forced.
	if (!force) {
		if (CGSizeEqualToSize(_lastRenderedPixelSize, pixelSize)) {
			// still re-render because gradient parameters might have changed
			// but avoid redundant re-renders if animation isn't running and parameters unchanged.
		}
	}
	
	// remember requested size now (prevents back-to-back work on main thread)
	_lastRenderedPixelSize = pixelSize;
	
	// Capture parameters for the background render job
	const float radius = _gradientRadius;
	const float brightness = _gradientBrightness;
	
	// Render on global background queue
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		CGImageRef img = [self createGradientCGImageWithPixelWidth:(int)pixelSize.width pixelHeight:(int)pixelSize.height radius:radius brightness:brightness];
		if (!img) return;
		
		// Set layer.contents on main thread
		dispatch_async(dispatch_get_main_queue(), ^{
			// Set contentsScale to match
			self.layer.contentsScale = [UIScreen autoScreen].scale;
			self.layer.contents = (__bridge id)img;
			CFRelease(img);
		});
	});
}

/// Create CGImage with same gradient algorithm as the Metal version, but 8-bit RGBA.
/// - width,height in pixels.
- (CGImageRef)createGradientCGImageWithPixelWidth:(int)width pixelHeight:(int)height radius:(float)radius brightness:(float)brightness {
	if (width <= 0 || height <= 0) return NULL;
	
	const int bytesPerPixel = 4; // RGBA 8-bit
	const size_t bytesPerRow = width * bytesPerPixel;
	size_t bufferSize = (size_t)bytesPerRow * height;
	
	uint8_t *buffer = (uint8_t *)malloc(bufferSize);
	if (!buffer) return NULL;
	memset(buffer, 0, bufferSize);
	
	// center & gradient radius in pixels (mimic original)
	float centerX = (float)width * 0.5f;
	float centerY = (float)height * 0.5f;
	float maxDim = MIN((float)width, (float)height);
	float gradientRadiusPixels = maxDim * 0.5f * radius;
	if (gradientRadiusPixels <= 0.0f) gradientRadiusPixels = 1.0f; // avoid divide-by-zero
	
	// Fill pixel buffer
	for (int y = 0; y < height; y++) {
		// pointer to row start
		uint8_t *row = buffer + (size_t)y * bytesPerRow;
		for (int x = 0; x < width; x++) {
			float dx = (float)x - centerX;
			float dy = (float)y - centerY;
			float distance = sqrtf(dx * dx + dy * dy);
			
			float normalizedDistance = distance / gradientRadiusPixels;
			
			// Adaptive edge softness
			float radiusNormalized = radius; // 0.2..1.0
			float edgeSoftness = 1.0f + (1.0f - radiusNormalized) * 4.0f; // 1.0..5.0-ish
			float adaptiveDistance = normalizedDistance / edgeSoftness;
			float t = fmaxf(0.0f, fminf(1.0f, 1.0f - adaptiveDistance));
			
			float smoothnessPower = 1.0f + (1.0f - radiusNormalized) * 2.0f; // 1.0..3.0-ish
			t = powf(t, smoothnessPower);
			
			// smoothstep
			t = t * t * (3.0f - 2.0f * t);
			
			float intensity = t * brightness;

			uint32_t chan = (uint32_t)fminf(intensity * 255.0f, 255.0f);
			
			// Set RGBA order (premultiplied alpha not required for this solid gradient)
			int pixelIndex = x * bytesPerPixel;
			row[pixelIndex + 0] = (uint8_t)chan; // R
			row[pixelIndex + 1] = (uint8_t)chan; // G
			row[pixelIndex + 2] = (uint8_t)chan; // B
			row[pixelIndex + 3] = 255;           // A
		}
	}
	
	// Create CGImage from raw buffer (RGBA8888)
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
	CGContextRef ctx = CGBitmapContextCreate(buffer, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
	CGColorSpaceRelease(colorSpace);
	
	if (!ctx) {
		free(buffer);
		return NULL;
	}
	
	CGImageRef img = CGBitmapContextCreateImage(ctx);
	CGContextRelease(ctx);
	
	// free buffer (CGImage has its own copy)
	free(buffer);
	
	return img; // caller should CFRelease
}

#pragma mark - App Lifecycle notifications

- (void)appDidEnterBackground:(NSNotification *)notification {
	// Stop animation to save CPU
	if (_animationDisplayLink) {
		[_animationDisplayLink invalidate];
		_animationDisplayLink = nil;
	}
	// Clear layer contents to free memory
	self.layer.contents = nil;
	_lastRenderedPixelSize = CGSizeZero;
	
	DBGLOG(@"GradientSDRView: App entered background - resources paused");
}

- (void)appWillEnterForeground:(NSNotification *)notification {
	// Re-render on foreground
	dispatch_async(dispatch_get_main_queue(), ^{
		[self renderAsyncIfNeededForce:YES];
	});
	DBGLOG(@"GradientSDRView: App entering foreground - resources restored");
}

@end
