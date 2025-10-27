//
//  GradientHDRView.m
//  Battman
//
//  Created by Torrekie on 2025/10/4.
//

#import "common.h"
#import "ObjCExt/UIScreen+Auto.h"
#import "GradientHDRView.h"
#import "BattmanPrefs.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CALayer ()
@property (atomic, assign) BOOL wantsExtendedDynamicRangeContent;
@end

@implementation GradientHDRView {
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _cmdQueue;
    id<MTLTexture> _gradientTexture;
    float _gradientRadius;
    float _gradientBrightness;
    BOOL _supportsHDR;

    // Animation properties
    CADisplayLink *_animationDisplayLink;
    NSTimeInterval _animationStartTime;
    NSTimeInterval _animationDuration;
    float _animationFromRadius;
    float _animationToRadius;
    float _animationFromBrightness;
    float _animationToBrightness;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupView];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    // Initialize Metal
    _device = MTLCreateSystemDefaultDevice();
    // NSAssert(_device, @"Metal not supported");
    _cmdQueue = [_device newCommandQueue];

    // Runtime check for HDR support
    [self checkHDRSupport];

    // Setup CAMetalLayer
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = _device;
    
    // Set pixel format based on HDR support
    if (_supportsHDR) {
        _metalLayer.pixelFormat = MTLPixelFormatBGR10A2Unorm;  // 10-bit + 2-bit alpha for HDR
        _metalLayer.wantsExtendedDynamicRangeContent = YES;
        
        // Try to set HDR colorspace
		// Apple always lie to us when things related with graphics.
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 120400
		extern const CFStringRef kCGColorSpaceITUR_2020_PQ_EOTF __attribute__((weak_import));
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		CGColorSpaceRef cs = NULL;
		if (@available(iOS 14.0, macOS 11.0, macCatalyst 14.0, *)) {
			cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
		} else if (@available(iOS 13.4, macOS 10.15.4, macCatalyst 13.4, *)) {
			cs = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3_PQ);
		} else if (@available(iOS 13.0, macOS 10.15, macCatalyst 13.0, *)) {
			cs = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3_PQ_EOTF);
		} else if (@available(iOS 12.6, macOS 10.14.6, macCatalyst 12.6, *)) {
			cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ_EOTF);
		} else if (@available(iOS 12.0, macOS 10.14, macCatalyst 12.0, *)) {
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
			if (kCGColorSpaceITUR_2020_PQ_EOTF != NULL)
				cs = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2020_PQ_EOTF);
		}
#pragma clang diagnostic pop

        if (cs) {
            _metalLayer.colorspace = cs;
            CGColorSpaceRelease(cs);
            DBGLOG(@"HDR colorspace enabled");
        } else {
            DBGLOG(@"Could not create ITUR_2020_PQ color space, using default");
            // Try fallback HDR colorspace
            cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
            if (cs) {
                _metalLayer.colorspace = cs;
                CGColorSpaceRelease(cs);
                DBGLOG(@"Extended sRGB colorspace enabled as fallback");
            }
        }
    } else {
        // Fallback to standard 8-bit format
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.wantsExtendedDynamicRangeContent = NO;
        DBGLOG(@"HDR not supported, using standard 8-bit format");
    }
    
    _metalLayer.framebufferOnly = NO;  // Allow blit operations to drawable texture
    
    // Match scale
    _metalLayer.contentsScale = [UIScreen autoScreen].scale;
    _metalLayer.frame = self.bounds;
    
#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
    _metalLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
#endif
    
    [self.layer addSublayer:_metalLayer];
    
    // Set initial gradient params
    _gradientRadius = 0.4f;       // relative (0…1)
    // Set initial brightness - make non-HDR brighter to compensate for 8-bit limitation
    _gradientBrightness = _supportsHDR ? 2.0f : 2.2f;   // HDR: 2.0, Non-HDR: 2.2 (brighter)
}

- (void)checkHDRSupport {
    _supportsHDR = NO;

	if ([BattmanPrefs.sharedPrefs objectForKey:@kBattmanPrefs_BRIGHT_UI_HDR]) {
		if (![BattmanPrefs.sharedPrefs boolForKey:@kBattmanPrefs_BRIGHT_UI_HDR])
			goto skip_hdr_check;
	}
		
    // Check if device supports HDR pixel formats
    if ([_device supportsTextureSampleCount:1] &&
#if TARGET_OS_MACCATALYST
		[_device supportsFamily:MTLGPUFamilyApple3]) {
#else
        [_device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v1]) {
#endif
        // Check if the display supports extended dynamic range
        UIScreen *screen = [UIScreen autoScreen];
        if (@available(iOS 10.0, *)) {
            if (screen.traitCollection.displayGamut == UIDisplayGamutP3) {
                _supportsHDR = YES;
                DBGLOG(@"HDR supported (P3 display)");
            }
        }

        // Check if we can create the HDR pixel format texture
        if (_supportsHDR) {
            MTLTextureDescriptor *testDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGR10A2Unorm width:1 height:1 mipmapped:NO];
            id<MTLTexture> testTexture = [_device newTextureWithDescriptor:testDesc];
            if (!testTexture) {
                _supportsHDR = NO;
                DBGLOG(@"Device doesn't support BGR10A2Unorm format - HDR disabled");
            }
        }
    } else {
        DBGLOG(@"Device doesn't support required Metal features for HDR");
    }

skip_hdr_check:
    if (!_supportsHDR) {
        DBGLOG(@"Falling back to standard dynamic range");
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    _metalLayer.frame = self.bounds;
    CGSize ds = [self drawableSizeForLayer:_metalLayer];
    _metalLayer.drawableSize = ds;

    [self createGradientTexture];
    [self render];
}

- (CGSize)drawableSizeForLayer:(CAMetalLayer *)layer {
    CGFloat scale = layer.contentsScale;
    CGSize s = layer.bounds.size;
    return CGSizeMake(s.width * scale, s.height * scale);
}

#pragma mark - Public Methods

- (void)setBrightness:(int)percentage animated:(BOOL)animated {
    percentage = MAX(0, MIN(100, percentage)) * 0.8;
    float normalizedValue = percentage / 100.0f;
    float newRadius = normalizedValue * 0.8f + 0.2f;

    float newBrightness;
    if (_supportsHDR) {
        newBrightness = normalizedValue * 2.5f + 0.5f;
    } else {
        // Non-HDR: Make it significantly brighter to compensate for 8-bit limitation
        newBrightness = normalizedValue * 2.0f + 1.0f;
    }

    if (animated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self animateFromRadius:self->_gradientRadius toRadius:newRadius fromBrightness:self->_gradientBrightness toBrightness:newBrightness duration:0.5];
        });
    } else {
        _gradientRadius = newRadius;
        _gradientBrightness = newBrightness;
        [self updateGradientTexture];
        [self render];
    }
}

- (void)animateFromRadius:(float)fromRadius toRadius:(float)toRadius fromBrightness:(float)fromBrightness toBrightness:(float)toBrightness duration:(NSTimeInterval)duration {
    
    NSTimeInterval startTime = CACurrentMediaTime();
    
    // Use a display link for smooth animation
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(animationStep:)];
    
    _animationStartTime = startTime;
    _animationDuration = duration;
    _animationFromRadius = fromRadius;
    _animationToRadius = toRadius;
    _animationFromBrightness = fromBrightness;
    _animationToBrightness = toBrightness;
    
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    _animationDisplayLink = displayLink;
}

- (void)animationStep:(CADisplayLink *)displayLink {
    NSTimeInterval currentTime = CACurrentMediaTime();
    NSTimeInterval elapsed = currentTime - _animationStartTime;
    
    if (elapsed >= _animationDuration) {
        _gradientRadius = _animationToRadius;
        _gradientBrightness = _animationToBrightness;
        [_animationDisplayLink invalidate];
        _animationDisplayLink = nil;
    } else {
        float progress = elapsed / _animationDuration;
        // ease-in-out
        progress = progress * progress * (3.0f - 2.0f * progress);
        
        _gradientRadius = _animationFromRadius + (_animationToRadius - _animationFromRadius) * progress;
        _gradientBrightness = _animationFromBrightness + (_animationToBrightness - _animationFromBrightness) * progress;
    }

    [self updateGradientTexture];
    [self render];
}

#pragma mark - Gradient texture creation & render

- (void)createGradientTexture {
    CGSize drawableSize = [self drawableSizeForLayer:_metalLayer];
    if (drawableSize.width <= 0 || drawableSize.height <= 0) {
        // Layer not ready yet, will be called again in layoutSubviews
        return;
    }

    MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_metalLayer.pixelFormat width:(NSUInteger)drawableSize.width height:(NSUInteger)drawableSize.height mipmapped:NO];
    textureDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    
    _gradientTexture = [_device newTextureWithDescriptor:textureDesc];
    [self updateGradientTexture];
}

- (void)updateGradientTexture {
    if (!_gradientTexture) return;
    
    NSUInteger width = _gradientTexture.width;
    NSUInteger height = _gradientTexture.height;
    NSUInteger bytesPerPixel = _supportsHDR ? 4 : 4; // Both formats use 4 bytes per pixel
    NSUInteger bytesPerRow = width * bytesPerPixel;
    
    // Allocate pixel data
    uint32_t *pixelData = (uint32_t *)malloc(width * height * sizeof(uint32_t));
    
    // Calculate center and gradient radius
    float centerX = width * 0.5f;
    float centerY = height * 0.5f;
    float maxDimension = MIN(width, height);
    float gradientRadiusPixels = maxDimension * 0.5f * _gradientRadius;
    
    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            // Calculate distance from center in pixels
            float dx = (float)x - centerX;
            float dy = (float)y - centerY;
            float distance = sqrtf(dx * dx + dy * dy);
            
            // Create smooth radial gradient with adaptive edge softness
            float normalizedDistance = distance / gradientRadiusPixels;
            
            // Calculate adaptive falloff factor based on radius size
            // Smaller radius = softer edge (mimics ambient light diffusion)
            float radiusNormalized = _gradientRadius; // 0.2 to 1.0
            float edgeSoftness = 1.0f + (1.0f - radiusNormalized) * 4.0f; // Range: 1.0 to 4.2
            
            // Apply adaptive distance scaling for softer edges on smaller radii
            float adaptiveDistance = normalizedDistance / edgeSoftness;
            float t = fmaxf(0.0f, fminf(1.0f, 1.0f - adaptiveDistance));
            
            // Apply smooth falloff with additional softening for small radii
            float smoothnessPower = 1.0f + (1.0f - radiusNormalized) * 2.0f; // Range: 1.0 to 2.6
            t = powf(t, smoothnessPower);
            
            // Apply final smoothstep for polish
            t = t * t * (3.0f - 2.0f * t); // smoothstep
            
            // Calculate intensity
            float intensity = t * _gradientBrightness;
            
            uint32_t packedPixel;
            
            if (_supportsHDR) {
                // Convert to 10-bit values (0-1023) for BGR10A2Unorm format
                uint32_t pixelValue10bit = (uint32_t)(intensity * 1023.0f);
                pixelValue10bit = MIN(pixelValue10bit, 1023); // Clamp to 10-bit max
                
                // Pack BGR10A2Unorm: B(10) + G(10) + R(10) + A(2) = 32 bits
                packedPixel = 
                    (3U << 30) |                           // A: 2 bits (full alpha = 3)
                    (pixelValue10bit << 20) |              // R: 10 bits
                    (pixelValue10bit << 10) |              // G: 10 bits
                    pixelValue10bit;                       // B: 10 bits
            } else {
                // Convert to 8-bit values (0-255) for BGRA8Unorm format
                uint32_t pixelValue8bit = (uint32_t)(intensity * 255.0f);
                pixelValue8bit = MIN(pixelValue8bit, 255); // Clamp to 8-bit max
                
                // Pack BGRA8Unorm: B(8) + G(8) + R(8) + A(8) = 32 bits
                packedPixel = 
                    (255U << 24) |                         // A: 8 bits (full alpha)
                    (pixelValue8bit << 16) |               // R: 8 bits
                    (pixelValue8bit << 8) |                // G: 8 bits
                    pixelValue8bit;                        // B: 8 bits
            }
            
            NSUInteger pixelIndex = y * width + x;
            pixelData[pixelIndex] = packedPixel;
        }
    }
    
    // Upload to texture
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [_gradientTexture replaceRegion:region mipmapLevel:0 withBytes:pixelData bytesPerRow:bytesPerRow];
    
    free(pixelData);
}

- (void)render {
    if (!_gradientTexture) return;
    
    id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
    if (!drawable) return;
    
    id<MTLCommandBuffer> cmdBuf = [_cmdQueue commandBuffer];
    
    // Use blit encoder to copy our gradient texture to the drawable
    id<MTLBlitCommandEncoder> blitEncoder = [cmdBuf blitCommandEncoder];
    
    MTLOrigin sourceOrigin = MTLOriginMake(0, 0, 0);
    MTLSize sourceSize = MTLSizeMake(_gradientTexture.width, _gradientTexture.height, 1);
    MTLOrigin destOrigin = MTLOriginMake(0, 0, 0);
    
    [blitEncoder copyFromTexture:_gradientTexture sourceSlice:0 sourceLevel:0 sourceOrigin:sourceOrigin sourceSize:sourceSize toTexture:drawable.texture destinationSlice:0 destinationLevel:0 destinationOrigin:destOrigin];
    
    [blitEncoder endEncoding];
    
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
}

#pragma mark - Property Accessors

- (float)gradientRadius {
    return _gradientRadius;
}

- (float)gradientBrightness {
    return _gradientBrightness;
}

- (BOOL)supportsHDR {
    return _supportsHDR;
}

@end
