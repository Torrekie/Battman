//
//  UIColor+compat.m
//  Battman
//
//  Created by Torrekie on 2025/11/4.
//

#import "../common.h"
#import "UIColor+compat.h"
#import "UIScreen+Auto.h"

@implementation UIColor (compat)

#ifdef DEBUG_COMPAT_COLOR
#define returnIfSystemColor(x)
#else
#define returnIfSystemColor(color) { \
	static dispatch_once_t color ## _onceToken = 0; \
	static BOOL useSystemColor = NO; \
	dispatch_once(&color ## _onceToken, ^{ \
		if ([UIColor respondsToSelector:@selector(color)]) { \
			UIColor *tmp = (UIColor *)perform_selector(@selector(color), [UIColor class], nil); \
			useSystemColor = (tmp && [tmp isKindOfClass:[UIColor class]]); \
		} \
	}); \
	if (useSystemColor) \
		return (UIColor *)perform_selector(@selector(color), [UIColor class], nil); \
}
#endif

static inline UITraitCollection *_currentTraitCollection() {
	return [UIScreen autoScreen].traitCollection;
}
static inline NSInteger _currentUserInterfaceStyle() {
	UITraitCollection *currentTrait = _currentTraitCollection();
	UIUserInterfaceStyle style = UIUserInterfaceStyleLight;

	if ([currentTrait respondsToSelector:@selector(userInterfaceStyle)]) {
		style = currentTrait.userInterfaceStyle;
	}
	return style;
}
#define currentTraitCollection _currentTraitCollection()
#define currentUserInterfaceStyle _currentUserInterfaceStyle()

#pragma mark - System Colors

+ (instancetype)compatRedColor {
	returnIfSystemColor(systemRedColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(255, 69, 58, 255);

	return UIColorWithRGBA8(255, 59, 48, 255);
}

+ (instancetype)compatGreenColor {
	returnIfSystemColor(systemGreenColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(50, 215, 75, 255);

	return UIColorWithRGBA8(40, 205, 65, 255);
}

+ (instancetype)compatBlueColor {
	returnIfSystemColor(systemBlueColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(10, 132, 255, 255);

	return UIColorWithRGBA8(0, 122, 255, 255);
}

+ (instancetype)compatGrayColor {
	returnIfSystemColor(systemGrayColor);
	
	// OS before iOS 13 has no constraint contrasts, so ignored
	// Dark SRGB High: R:0.682 G:0.682 B:0.698 A:1.000
	// Light SRGB High: R:0.424 G:0.424 B:0.439 A:1.000
	// Light SRGB: R:0.557 G:0.557 B:0.576 A:1.000
	return UIColorWithRGBA8(142, 142, 147, 255);
}

+ (instancetype)compatGray4Color {
	returnIfSystemColor(systemGray4Color);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(58, 58, 60, 255);

	return UIColorWithRGBA8(209, 209, 214, 255);
}

+ (instancetype)compatLabelColor {
	returnIfSystemColor(labelColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithWhiteA8(255, 255);

	return UIColorWithWhiteA8(0, 255);
}

+ (instancetype)compatSecondaryLabelColor {
	returnIfSystemColor(secondaryLabelColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(235, 235, 245, 153);

	return UIColorWithRGBA8(60, 60, 67, 153);
}

+ (instancetype)compatLinkColor {
	returnIfSystemColor(linkColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(9, 132, 255, 255);

	return UIColorWithRGBA8(0, 122, 255, 255);
}

+ (instancetype)compatBackgroundColor {
	returnIfSystemColor(systemBackgroundColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithWhiteA8(0, 255);
	
	return UIColorWithWhiteA8(255, 255);
}

+ (instancetype)secondaryCompatFillColor {
	returnIfSystemColor(secondarySystemFillColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(120, 120, 128, 82);

	return UIColorWithRGBA8(120, 120, 128, 41);
}

+ (instancetype)tertiaryCompatFillColor {
	returnIfSystemColor(tertiarySystemFillColor);

	if (currentUserInterfaceStyle == UIUserInterfaceStyleDark)
		return UIColorWithRGBA8(118, 118, 128, 61);

	return UIColorWithRGBA8(118, 118, 128, 31);
}

@end
