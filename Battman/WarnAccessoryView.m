#import "ObjCExt/UIColor+compat.h"
#import "WarnAccessoryView.h"
#import "CompatibilityHelper.h"
#import "common.h"
#import "ObjCExt/UIImage+SVG.h"

@implementation WarnAccessoryView

+ (instancetype)_accessoryViewWithSystemImageNamed:(NSString *)systemName
                                          fallback:(NSString *)fallbackGlyph
{
    WarnAccessoryView *button = [super buttonWithType:UIButtonTypeSystem];
    if (!button) return nil;

    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:systemName];
        [button setImage:img forState:UIControlStateNormal];
    } else {
        UIImage *image = [UIImage legacySymbolImageForGlyph:fallbackGlyph pointSize:22 color:UIColor.blackColor];
        [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    }

    button.tintColor = [UIColor compatBlueColor];
    [button sizeToFit];
    return button;
}

+ (instancetype)warnAccessoryView {
    // U+1001FE
    WarnAccessoryView *ret = [self _accessoryViewWithSystemImageNamed:@"exclamationmark.triangle"
                                          fallback:@"􀇾"];
    ret.isWarn = YES;
    return ret;
}

+ (instancetype)altAccessoryView {
    // U+100174
    return [self _accessoryViewWithSystemImageNamed:@"info.circle"
                                          fallback:@"􀅴"];
}

@end
