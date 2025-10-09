//
//  UIScreen+Auto.h
//  Battman
//
//  Created by Torrekie on 2025/10/8.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIScreen (Auto)

/// Returns the most appropriate screen for the current context.
/// This is a drop-in replacement for UIScreen.mainScreen that works across iOS 12-17+
/// and handles deprecated APIs gracefully.
///
/// Detection priority (newest to oldest):
/// 1. iOS 15+: UIWindowScene.keyWindow.screen
/// 2. iOS 13+: UIWindowScene.windows (active scenes)
/// 3. iOS 12+: UIApplication.keyWindow.screen (deprecated in iOS 13)
/// 4. iOS 12+: UIApplication.windows (deprecated in iOS 15)
/// 5. Fallback: UIScreen.mainScreen
+ (UIScreen *)autoScreen;

/// Returns the screen for a specific window, falling back to autoScreen if needed.
+ (UIScreen *)autoScreenForWindow:(nullable UIWindow *)window;

/// Returns the screen for a specific view, falling back to autoScreen if needed.
+ (UIScreen *)autoScreenForView:(nullable UIView *)view;

@end

NS_ASSUME_NONNULL_END
