#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Forward declare the opaque document type (private framework).
@interface CGSVGDocument : NSObject
@end

@interface SVG : NSObject
@property (nonatomic, readonly) CGSize size;

- (nullable instancetype)initWithData:(NSData *)data;
- (nullable instancetype)initWithString:(NSString *)string;
- (nullable UIImage *)image;
- (void)drawInContext:(CGContextRef)context;
- (void)drawInContext:(CGContextRef)context size:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END
