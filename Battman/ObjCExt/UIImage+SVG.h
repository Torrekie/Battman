//
//  UIImage+SVG.h
//  Battman
//
//  Created by Torrekie on 2025/10/6.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (SVG)

/// Create a UIImage from SVG data. If `scale` <= 0.0, device screen scale is used.
/// Returns nil on failure.
+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData scale:(CGFloat)scale API_AVAILABLE(ios(12.4));

/// Create a UIImage from SVG data.
+ (nullable UIImage *)imageWithSVGData:(NSData *)svgData API_AVAILABLE(ios(12.4));

/// Return a preset SVG image by name (faster on subsequent calls due to in-memory cache).
/// The returned image uses UIImageRenderingModeAlwaysTemplate so it tints like SF Symbols.
+ (nullable UIImage *)presetSVGImageNamed:(NSString *)name API_AVAILABLE(ios(12.4));

/// Try `[UIImage systemImageNamed:]` first (when available); fall back to a preset SVG if the system symbol is missing.
/// This mirrors the typical usage pattern for providing a "missing SF Symbol" fallback.
+ (nullable UIImage *)systemImageNamedOrPreset:(NSString *)name API_AVAILABLE(ios(12.4));

@end

NS_ASSUME_NONNULL_END
