//
//  GradientHDRView.m
//  Battman
//
//  Created by Torrekie on 2025/10/4.
//

#import "main.h"
#import "common.h"
#import <objc/message.h>
#import "ObjCExt/UIScreen+Auto.h"
#import "GradientHDRView.h"
#import "BattmanPrefs.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 140000
extern const CFStringRef kCGColorSpaceITUR_2100_PQ;
#endif

WEAK_LINK_FORCE_IMPORT(kCGColorSpaceITUR_2100_PQ);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceDisplayP3_PQ);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceDisplayP3_PQ_EOTF);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceITUR_2020_PQ_EOTF);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceExtendedSRGB);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceExtendedLinearDisplayP3);
WEAK_LINK_FORCE_IMPORT(kCGColorSpaceExtendedLinearITUR_2020);

#pragma clang diagnostic pop

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

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    // Set pixel format based on HDR support
    if (_supportsHDR) {
        BOOL pixelFormatSet = NO;
        
        // Only try BGR10A2Unorm on macCatalyst
        if (is_maccatalyst()) {
            if ([self safelySetPixelFormat:MTLPixelFormatBGR10A2Unorm forMetalLayer:_metalLayer]) {
                _metalLayer.wantsExtendedDynamicRangeContent = YES;
                [self tryHDRColorspaceWithFallbacks];
                pixelFormatSet = YES;
            }
        }
        
        // Try RGBA16Float if BGR10A2Unorm wasn't set
        if (!pixelFormatSet && [self safelySetPixelFormat:MTLPixelFormatRGBA16Float forMetalLayer:_metalLayer]) {
            _metalLayer.wantsExtendedDynamicRangeContent = YES;
            [self tryHDRColorspaceWithFallbacks];
            pixelFormatSet = YES;
        }
        
        if (!pixelFormatSet) {
            DBGLOG(@"Failed to set HDR pixel format, falling back to standard format");
            _supportsHDR = NO;
            [self safelySetPixelFormat:MTLPixelFormatBGRA8Unorm forMetalLayer:_metalLayer];
            _metalLayer.wantsExtendedDynamicRangeContent = NO;
        }
    } else {
        // Fallback to standard 8-bit format
        [self safelySetPixelFormat:MTLPixelFormatBGRA8Unorm forMetalLayer:_metalLayer];
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

- (void)tryHDRColorspaceWithFallbacks {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    BOOL (^tryColorspace)(CFStringRef, const char *) = ^BOOL(CFStringRef colorspaceRef, const char *name) {
        if (colorspaceRef == NULL) return NO;
        
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(colorspaceRef);
        if (!cs) {
            DBGLOG(@"Could not create %s colorspace", name);
            return NO;
        }
        
        if ([self safelySetColorspace:cs forMetalLayer:self->_metalLayer]) {
            DBGLOG(@"HDR colorspace enabled: %s", name);
            CGColorSpaceRelease(cs);
            return YES;
        } else {
            DBGLOG(@"HDR colorspace %s incompatible, trying next fallback", name);
            CGColorSpaceRelease(cs);
            return NO;
        }
    };

    BOOL success = NO;
    
    // Different colorspace fallbacks based on pixel format
    if (_metalLayer.pixelFormat == MTLPixelFormatRGBA16Float) {
        // RGBA16Float: Use extended linear colorspaces
        success = tryColorspace(kCGColorSpaceExtendedLinearDisplayP3, "Extended Linear Display P3") ||
                  tryColorspace(kCGColorSpaceExtendedLinearITUR_2020, "Extended Linear ITU-R 2020") ||
                  tryColorspace(kCGColorSpaceExtendedLinearSRGB, "Extended Linear sRGB") ||
                  tryColorspace(kCGColorSpaceExtendedSRGB, "Extended sRGB");
    } else if (_metalLayer.pixelFormat == MTLPixelFormatBGR10A2Unorm) {
        // BGR10A2Unorm: Use PQ (Perceptual Quantizer) colorspaces
        success = tryColorspace(kCGColorSpaceITUR_2100_PQ, "ITU-R 2100 PQ") ||
                  tryColorspace(kCGColorSpaceDisplayP3_PQ, "Display P3 PQ") ||
                  tryColorspace(kCGColorSpaceDisplayP3_PQ_EOTF, "Display P3 PQ EOTF") ||
                  tryColorspace(kCGColorSpaceITUR_2020_PQ_EOTF, "ITU-R 2020 PQ EOTF") ||
                  tryColorspace(kCGColorSpaceExtendedSRGB, "Extended sRGB");
    }

    if (success) {
        return;
    }

    DBGLOG(@"All HDR colorspaces failed, disabling HDR");
    _supportsHDR = NO;
    [self safelySetPixelFormat:MTLPixelFormatBGRA8Unorm forMetalLayer:_metalLayer];
    _metalLayer.wantsExtendedDynamicRangeContent = NO;
#pragma clang diagnostic pop
}

- (BOOL)safelySetColorspace:(CGColorSpaceRef)colorspace forMetalLayer:(CAMetalLayer *)metalLayer {
    if (!colorspace || !metalLayer) {
        return NO;
    }
    @try {
        metalLayer.colorspace = colorspace;
        DBGLOG(@"Successfully set colorspace");
        return YES;
    }
    @catch (NSException *exception) {
        DBGLOG(@"Failed to set colorspace: %@", exception.reason);
        return NO;
    }
}

- (BOOL)safelySetPixelFormat:(MTLPixelFormat)pixelFormat forMetalLayer:(CAMetalLayer *)metalLayer {
    if (!metalLayer)
        return NO;

    @try {
        metalLayer.pixelFormat = pixelFormat;
        DBGLOG(@"Successfully set pixel format %lu", (unsigned long)pixelFormat);
        return YES;
    }
    @catch (NSException *exception) {
        DBGLOG(@"Failed to set pixel format %lu: %@", (unsigned long)pixelFormat, exception.reason);
        return NO;
    }
}

BOOL metal_hdr_available(id<MTLDevice> device) {
	// Check if device supports HDR pixel formats
	BOOL support_hdr = NO;
	BOOL hasRequiredGPU = NO;
	
	if (is_maccatalyst()) {
		if ([device respondsToSelector:sel_registerName("supportsFamily:")])
			hasRequiredGPU = ((BOOL (*)(id, SEL, NSInteger))objc_msgSend)(device, sel_registerName("supportsFamily:"), 1003); // MTLGPUFamilyApple3
	} else {
		hasRequiredGPU = [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily3_v1];
	}
	
	if ([device supportsTextureSampleCount:1] && hasRequiredGPU) {
		// Check if the display supports extended dynamic range
		UIScreen *screen = [UIScreen autoScreen];
		
		// Check for EDR headroom (iOS 16+)
		if (@available(iOS 16.0, *)) {
			if ([screen respondsToSelector:sel_registerName("potentialEDRHeadroom")]) {
				CGFloat edrHeadroom = ((CGFloat (*)(id, SEL))objc_msgSend)(screen, sel_registerName("potentialEDRHeadroom"));
				if (edrHeadroom > 1.0) {
					support_hdr = YES;
					DBGLOG(@"HDR supported (EDR headroom: %.2f)", edrHeadroom);
				} else {
					DBGLOG(@"EDR headroom insufficient: %.2f", edrHeadroom);
				}
			}
		}
		
		// Fallback: Check display gamut for older iOS versions
		if (!support_hdr) {
			NSOperatingSystemVersion iOS10 = {.majorVersion = 10, .minorVersion = 0, .patchVersion = 0};
			if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:iOS10]) {
				if (screen.traitCollection.displayGamut == UIDisplayGamutP3) {
					support_hdr = YES;
					DBGLOG(@"HDR supported (P3 display, pre-iOS 16)");
				}
			}
		}

		// Verify we can actually use HDR pixel formats by testing CAMetalLayer
		if (support_hdr) {
			CAMetalLayer *testLayer = [CAMetalLayer layer];
			testLayer.device = device;
			
			BOOL canUseBGR10A2 = NO;
			BOOL canUseRGBA16Float = NO;
			
			// Test BGR10A2Unorm (only on macCatalyst)
			if (is_maccatalyst()) {
				@try {
					testLayer.pixelFormat = MTLPixelFormatBGR10A2Unorm;
					testLayer.wantsExtendedDynamicRangeContent = YES;
					canUseBGR10A2 = YES;
					DBGLOG(@"CAMetalLayer supports BGR10A2Unorm");
				}
				@catch (NSException *exception) {
					DBGLOG(@"CAMetalLayer doesn't support BGR10A2Unorm: %@", exception.reason);
				}
			}
			
			// Test RGBA16Float (all platforms)
			@try {
				testLayer.pixelFormat = MTLPixelFormatRGBA16Float;
				testLayer.wantsExtendedDynamicRangeContent = YES;
				canUseRGBA16Float = YES;
				DBGLOG(@"CAMetalLayer supports RGBA16Float");
			}
			@catch (NSException *exception) {
				DBGLOG(@"CAMetalLayer doesn't support RGBA16Float: %@", exception.reason);
			}
			
			// HDR is only supported if at least one format works
			if (!canUseBGR10A2 && !canUseRGBA16Float) {
				support_hdr = NO;
				DBGLOG(@"Device doesn't support any HDR pixel formats on CAMetalLayer - HDR disabled");
			}
		}
	} else {
		DBGLOG(@"Device doesn't support required Metal features for HDR");
	}

	return support_hdr;
}
- (void)checkHDRSupport {
    _supportsHDR = NO;

	if ([BattmanPrefs.sharedPrefs objectForKey:@kBattmanPrefs_BRIGHT_UI_HDR]) {
		if ([BattmanPrefs.sharedPrefs integerForKey:@kBattmanPrefs_BRIGHT_UI_HDR] != 0)
			goto skip_hdr_check;
	}

	_supportsHDR = metal_hdr_available(_device);
	
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
	NSUInteger bytesPerPixel = 4;
	if (_metalLayer.pixelFormat == MTLPixelFormatRGBA16Float)
		bytesPerPixel = 8;
    NSUInteger bytesPerRow = width * bytesPerPixel;
    
    // Allocate pixel data
	uint32_t *pixelData = malloc(width * height * bytesPerPixel);
    
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
			float edgeSoftness = 1.0f + (1.0f - radiusNormalized) * ((_metalLayer.pixelFormat == MTLPixelFormatRGBA16Float) ? 9.4f : 4.0f); // Range: 1.0 to 4.2
            
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

			NSUInteger pixelIndex = y * width + x;
            if (_supportsHDR) {
				if (_metalLayer.pixelFormat == MTLPixelFormatBGR10A2Unorm) {
					// Convert to 10-bit values (0-1023) for BGR10A2Unorm format
					uint32_t pixelValue10bit = (uint32_t)(intensity * 1023.0f);
					pixelValue10bit = MIN(pixelValue10bit, 1023); // Clamp to 10-bit max
					
					// Pack BGR10A2Unorm: B(10) + G(10) + R(10) + A(2) = 32 bits
					pixelData[pixelIndex] =
					(3U << 30) |							// A: 2 bits (full alpha = 3)
					(pixelValue10bit << 20) |              	// R: 10 bits
					(pixelValue10bit << 10) |              	// G: 10 bits
					pixelValue10bit;                       	// B: 10 bits
				} else if (_metalLayer.pixelFormat == MTLPixelFormatRGBA16Float) {
					// RGBA16Float requires 4 x half (16-bit float)
					uint64_t *hp = (uint64_t *)pixelData;
					uint64_t pixelValue16bit = (uint64_t)(intensity * 31743.0f * 0.4);
					pixelValue16bit = MIN(pixelValue16bit, 31743); // Clamp to half-precision float max

					// Pack RGBA16Float: B(16) + G(16) + R(16) + A(16) = 64 bits
					hp[pixelIndex] =
					((uint64_t)30720U << 48) |				// A: 16 bits (full alpha = 1.0/0x3CFF)
					(pixelValue16bit << 32) |				// B: 16 bits
					(pixelValue16bit << 16) |				// G: 16 bits
					pixelValue16bit;						// R: 16 bits
				}
            } else {
                // Convert to 8-bit values (0-255) for BGRA8Unorm format
                uint32_t pixelValue8bit = (uint32_t)(intensity * 255.0f);
                pixelValue8bit = MIN(pixelValue8bit, 255); // Clamp to 8-bit max
                
                // Pack BGRA8Unorm: B(8) + G(8) + R(8) + A(8) = 32 bits
				pixelData[pixelIndex] =
				(255U << 24) |								// A: 8 bits (full alpha)
				(pixelValue8bit << 16) |               		// R: 8 bits
				(pixelValue8bit << 8) |                		// G: 8 bits
				pixelValue8bit;                        		// B: 8 bits
            }
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

#pragma mark - App Lifecycle

- (void)appDidEnterBackground:(NSNotification *)notification {
    // Pause any ongoing animations to save resources
    if (_animationDisplayLink) {
        [_animationDisplayLink invalidate];
        _animationDisplayLink = nil;
    }
    
    // Clear the gradient texture to free GPU memory
    _gradientTexture = nil;
    
    DBGLOG(@"GradientHDRView: App entered background - resources paused");
}

- (void)appWillEnterForeground:(NSNotification *)notification {
    // Recreate gradient texture when returning from background
    dispatch_async(dispatch_get_main_queue(), ^{
        [self createGradientTexture];
        [self render];
    });
    
    DBGLOG(@"GradientHDRView: App entering foreground - resources restored");
}

- (void)dealloc {
    // Clean up notification observers
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Clean up animation display link
    if (_animationDisplayLink) {
        [_animationDisplayLink invalidate];
        _animationDisplayLink = nil;
    }
    
    // Clean up Metal resources
    _gradientTexture = nil;
    _cmdQueue = nil;
    _device = nil;
    
    DBGLOG(@"GradientHDRView: Dealloc completed");
}

@end
