#import "SVG.h"
#import <dlfcn.h>

#include "common.h"

#import "ObjCExt/NSBundle+Auto.h"

#pragma mark - CoreSVG function pointer typedefs

typedef CGSVGDocument *CGSVGDocumentRef;

static CGSVGDocument *(*CGSVGDocumentRetain)(CGSVGDocumentRef) = NULL;
static void (*CGSVGDocumentRelease)(CGSVGDocumentRef) = NULL;
static CGSVGDocument *(*CGSVGDocumentCreateFromData)(CFDataRef, CFDictionaryRef) = NULL;
static void (*CGContextDrawSVGDocument)(CGContextRef, CGSVGDocumentRef) = NULL;
static CGSize (*CGSVGDocumentGetCanvasSize)(CGSVGDocumentRef) = NULL;

static void *CoreSVGHandle = NULL;

static void loadCoreSVGIfNeeded(void) {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSBundle *bundle = [NSBundle systemBundleWithName:@"CoreSVG"];
		if (bundle)
			CoreSVGHandle = dlopen(bundle.executablePath.UTF8String, RTLD_NOW);
		else
			DBGLOG(@"Cannot find com.apple.CoreSVG");
		if (CoreSVGHandle) {
			CGSVGDocumentRetain = dlsym(CoreSVGHandle, "CGSVGDocumentRetain");
			CGSVGDocumentRelease = dlsym(CoreSVGHandle, "CGSVGDocumentRelease");
			CGSVGDocumentCreateFromData = dlsym(CoreSVGHandle, "CGSVGDocumentCreateFromData");
			CGContextDrawSVGDocument = dlsym(CoreSVGHandle, "CGContextDrawSVGDocument");
			CGSVGDocumentGetCanvasSize = dlsym(CoreSVGHandle, "CGSVGDocumentGetCanvasSize");
		}
	});
}

#pragma mark - SVG

@interface SVG ()
@property (nonatomic, assign) CGSVGDocumentRef document;
@end

@implementation SVG

- (void)dealloc {
	if (self.document && CGSVGDocumentRelease) {
		CGSVGDocumentRelease(self.document);
		// niling not necessary in dealloc
	}
}

- (nullable instancetype)initWithString:(NSString *)string {
	if (!string) return nil;
	NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) return nil;
	return [self initWithData:data];
}

- (nullable instancetype)initWithData:(NSData *)data {
	if (!data) {
		DBGLOG(@"No source provided");
		return nil;
	}
	loadCoreSVGIfNeeded();
	if (!CGSVGDocumentCreateFromData || !CGSVGDocumentGetCanvasSize) {
		DBGLOG(@"Missing CGSVGDocumentCreateFromData/CGSVGDocumentGetCanvasSize");
		return nil;
	}
	
	// Create document (CoreSVG Create usually returns a retained reference)
	CGSVGDocumentRef doc = CGSVGDocumentCreateFromData((__bridge CFDataRef)data, NULL);
	if (!doc) {
		DBGLOG(@"CGSVGDocumentCreateFromData failed");
		return nil;
	}
	
	CGSize docSize = CGSVGDocumentGetCanvasSize(doc);
	if (CGSizeEqualToSize(docSize, CGSizeZero)) {
		// Release returned doc (since create returned retained)
		DBGLOG(@"Canvas size 0!");
		if (CGSVGDocumentRelease) CGSVGDocumentRelease(doc);
		return nil;
	}
	
	self = [super init];
	if (self) {
		_document = doc; // keep doc and release in dealloc
	} else {
		if (CGSVGDocumentRelease) CGSVGDocumentRelease(doc);
	}
	return self;
}

- (CGSize)size {
	if (!self.document || !CGSVGDocumentGetCanvasSize) return CGSizeZero;
	return CGSVGDocumentGetCanvasSize(self.document);
}

- (nullable UIImage *)image {
	if (!self.document) return nil;

	SEL sel = NSSelectorFromString(@"_imageWithCGSVGDocument:");
	if (![UIImage respondsToSelector:sel]) {
		// Fallback: try to call CGContextDrawSVGDocument on a new bitmap context and capture UIImage
		return [self imageByRasterizing];
	}
	
	IMP imp = [UIImage methodForSelector:sel];
	if (!imp) return [self imageByRasterizing];

	typedef UIImage *(*ImageWithCGSVGDocumentFunc)(id, SEL, CGSVGDocumentRef);
	ImageWithCGSVGDocumentFunc func = (ImageWithCGSVGDocumentFunc)imp;
	
	UIImage *result = func((id)UIImage.class, sel, self.document);
	return result;
}

- (UIImage *)imageByRasterizing {
	// Fallback rasterization using CGContextDrawSVGDocument (if available)
	if (!CGContextDrawSVGDocument) return nil;
	CGSize sz = self.size;
	if (CGSizeEqualToSize(sz, CGSizeZero)) return nil;
	
	UIGraphicsBeginImageContextWithOptions(sz, NO, 0.0);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	if (ctx) {
		CGContextTranslateCTM(ctx, 0, sz.height);
		CGContextScaleCTM(ctx, 1.0, -1.0);
		CGContextDrawSVGDocument(ctx, self.document);
	}
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

- (void)drawInContext:(CGContextRef)context {
	[self drawInContext:context size:self.size];
}

- (void)drawInContext:(CGContextRef)context size:(CGSize)targetSize {
	if (!context || !self.document || !CGContextDrawSVGDocument) return;
	
	CGSize docSize = self.size;
	if (CGSizeEqualToSize(docSize, CGSizeZero)) return;

	CGSize target = targetSize;
	
	CGFloat ratioX = target.width / docSize.width;
	CGFloat ratioY = target.height / docSize.height;

	CGFloat scaleX, scaleY;
	if (target.width <= 0.0) {
		scaleX = ratioY;
		scaleY = ratioY;
		target.width = docSize.width * scaleX;
	} else if (target.height <= 0.0) {
		scaleX = ratioX;
		scaleY = ratioX;
		target.height = docSize.height * scaleY;
	} else {
		CGFloat m = fmin(ratioX, ratioY);
		scaleX = m;
		scaleY = m;
		target.width = docSize.width * scaleX;
		target.height = docSize.height * scaleY;
	}

	CGAffineTransform scale = CGAffineTransformMakeScale(scaleX, scaleY);
	CGAffineTransform aspect = CGAffineTransformMakeTranslation((target.width / scaleX - docSize.width) / 2.0, (target.height / scaleY - docSize.height) / 2.0);

	CGContextSaveGState(context);

	CGContextTranslateCTM(context, 0, target.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	CGContextConcatCTM(context, scale);
	CGContextConcatCTM(context, aspect);
	// Draw
	CGContextDrawSVGDocument(context, self.document);
	
	CGContextRestoreGState(context);
}

@end
