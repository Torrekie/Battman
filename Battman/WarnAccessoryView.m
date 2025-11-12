#import "ObjCExt/UIColor+compat.h"
#import "WarnAccessoryView.h"
#import "CompatibilityHelper.h"
#import "common.h"

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
        [button setTitle:fallbackGlyph forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont fontWithName:@SFPRO size:22];
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
