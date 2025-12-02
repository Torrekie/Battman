//
//  UIScreen+Auto.m
//  Battman
//
//  Created by Torrekie on 2025/10/8.
//

#import "UIScreen+Auto.h"

@implementation UIScreen (Auto)

+ (UIScreen *)autoScreen {
	UIScreen *screen = nil;
	
	// iOS 15+: Try UIWindowScene.keyWindow first (most accurate for multi-window)
	if (@available(iOS 15.0, *)) {
		screen = [self _screenFromSceneKeyWindow];
		if (screen) return screen;
	}
	
	// iOS 13+: Try UIWindowScene.windows (scene-based approach)
	if (@available(iOS 13.0, *)) {
		screen = [self _screenFromSceneWindows];
		if (screen) return screen;
	}
	
	// iOS 12+: Try UIApplication.keyWindow (deprecated in iOS 13)
	screen = [self _screenFromApplicationKeyWindow];
	if (screen) return screen;
	
	// iOS 12+: Try UIApplication.windows (deprecated in iOS 15)
	screen = [self _screenFromApplicationWindows];
	if (screen) return screen;
	
	// fallback
	return UIScreen.mainScreen;
}

+ (UIScreen *)autoScreenForWindow:(nullable UIWindow *)window {
	if (window && window.screen) return window.screen;
	return [self autoScreen];
}

+ (UIScreen *)autoScreenForView:(nullable UIView *)view {
	if (view) {
		if (view.window && view.window.screen) {
			return view.window.screen;
		}
		// view might not be attached yet — fall back to autoScreen
	}
	return [self autoScreen];
}

#pragma mark - Helpers

/// iOS 15+: Get screen from UIWindowScene.keyWindow
+ (UIScreen *)_screenFromSceneKeyWindow {
	Class appClass = NSClassFromString(@"UIApplication");
	if (!appClass) return nil;
	
	SEL sharedSel = NSSelectorFromString(@"sharedApplication");
	if (![appClass respondsToSelector:sharedSel]) return nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	id app = [appClass performSelector:sharedSel];
#pragma clang diagnostic pop
	if (!app) return nil;
	
	if ([app respondsToSelector:NSSelectorFromString(@"connectedScenes")]) {
		id scenesSet = [app valueForKey:@"connectedScenes"];
		if (scenesSet && [scenesSet respondsToSelector:@selector(allObjects)]) {
			Class windowSceneClass = NSClassFromString(@"UIWindowScene");
			if (!windowSceneClass) return nil;

			// Single pass: prioritize active scenes, but collect inactive as fallback
			UIWindow *fallbackKeyWindow = nil;
			for (id scene in [scenesSet allObjects]) {
				if ([scene isKindOfClass:windowSceneClass]) {
					BOOL isActive = YES;
					if ([scene respondsToSelector:NSSelectorFromString(@"activationState")]) {
						NSInteger state = [[scene valueForKey:@"activationState"] integerValue];
						isActive = (state == 0); // UISceneActivationStateForegroundActive
						if (state > 1) continue; // Skip background scenes
					}

					// Get keyWindow from scene (iOS 15+)
					if ([scene respondsToSelector:NSSelectorFromString(@"keyWindow")]) {
						UIWindow *keyWindow = [scene valueForKey:@"keyWindow"];
						if (keyWindow && keyWindow.screen) {
							if (isActive) {
								return keyWindow.screen; // Immediately return active scene
							} else if (!fallbackKeyWindow) {
								fallbackKeyWindow = keyWindow; // Save as fallback
							}
						}
					}
				}
			}
			
			// Use fallback if no active scene found
			if (fallbackKeyWindow && fallbackKeyWindow.screen) {
				return fallbackKeyWindow.screen;
			}
		}
	}
	
	return nil;
}

/// iOS 13+: Get screen from UIWindowScene.windows
+ (UIScreen *)_screenFromSceneWindows {
	Class appClass = NSClassFromString(@"UIApplication");
	if (!appClass) return nil;
	
	SEL sharedSel = NSSelectorFromString(@"sharedApplication");
	if (![appClass respondsToSelector:sharedSel]) return nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	id app = [appClass performSelector:sharedSel];
#pragma clang diagnostic pop
	if (!app) return nil;
	
	if ([app respondsToSelector:NSSelectorFromString(@"connectedScenes")]) {
		id scenesSet = [app valueForKey:@"connectedScenes"];
		if (scenesSet && [scenesSet respondsToSelector:@selector(allObjects)]) {
			Class windowSceneClass = NSClassFromString(@"UIWindowScene");
			if (!windowSceneClass) return nil;

			// Single pass: prioritize active scenes, but collect inactive as fallback
			UIWindow *fallbackKeyWindow = nil;
			UIWindow *fallbackFirstWindow = nil;
			
			for (id scene in [scenesSet allObjects]) {
				if ([scene isKindOfClass:windowSceneClass]) {
					BOOL isActive = YES;
					if ([scene respondsToSelector:NSSelectorFromString(@"activationState")]) {
						NSInteger state = [[scene valueForKey:@"activationState"] integerValue];
						isActive = (state == 0); // UISceneActivationStateForegroundActive
						if (state > 1) continue; // Skip background scenes
					}

					// Get windows from scene
					if ([scene respondsToSelector:NSSelectorFromString(@"windows")]) {
						id windows = [scene valueForKey:@"windows"];
						if (windows && [windows respondsToSelector:@selector(firstObject)]) {
							// Look for key window first
							for (UIWindow *window in windows) {
								if (window.isKeyWindow && window.screen) {
									if (isActive) {
										return window.screen; // Immediately return from active scene
									} else if (!fallbackKeyWindow) {
										fallbackKeyWindow = window; // Save as fallback
									}
								}
							}
							// Check first window
							UIWindow *firstWindow = [windows firstObject];
							if (firstWindow && firstWindow.screen) {
								if (isActive) {
									return firstWindow.screen; // Immediately return from active scene
								} else if (!fallbackFirstWindow) {
									fallbackFirstWindow = firstWindow; // Save as fallback
								}
							}
						}
					}
				}
			}
			
			// Use fallback if no active scene found
			if (fallbackKeyWindow && fallbackKeyWindow.screen) {
				return fallbackKeyWindow.screen;
			}
			if (fallbackFirstWindow && fallbackFirstWindow.screen) {
				return fallbackFirstWindow.screen;
			}
		}
	}
	
	return nil;
}

/// iOS 12+: Get screen from UIApplication.keyWindow (deprecated in iOS 13)
+ (UIScreen *)_screenFromApplicationKeyWindow {
	Class appClass = NSClassFromString(@"UIApplication");
	if (!appClass) return nil;
	
	SEL sharedSel = NSSelectorFromString(@"sharedApplication");
	if (![appClass respondsToSelector:sharedSel]) return nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	id app = [appClass performSelector:sharedSel];
#pragma clang diagnostic pop
	if (!app) return nil;
	
	__block UIWindow *keyWindow = nil;
	
	// Access UI values on main thread to be safe
	if ([NSThread isMainThread]) {
		keyWindow = [self _keyWindowFromApplication:app];
	} else {
		dispatch_sync(dispatch_get_main_queue(), ^{
			keyWindow = [self _keyWindowFromApplication:app];
		});
	}
	
	return keyWindow ? keyWindow.screen : nil;
}

/// iOS 12+: Get screen from UIApplication.windows (deprecated in iOS 15)
+ (UIScreen *)_screenFromApplicationWindows {
	Class appClass = NSClassFromString(@"UIApplication");
	if (!appClass) return nil;
	
	SEL sharedSel = NSSelectorFromString(@"sharedApplication");
	if (![appClass respondsToSelector:sharedSel]) return nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	id app = [appClass performSelector:sharedSel];
#pragma clang diagnostic pop
	if (!app) return nil;
	
	// Try application windows
	if ([app respondsToSelector:NSSelectorFromString(@"windows")]) {
		id appWindows = [app valueForKey:@"windows"];
		if (appWindows && [appWindows respondsToSelector:@selector(count)]) {
			// Look for key window first
			for (UIWindow *w in appWindows) {
				if (w.isKeyWindow && w.screen) return w.screen;
			}
			// Fallback to first window
			if ([appWindows respondsToSelector:@selector(firstObject)]) {
				UIWindow *first = [appWindows firstObject];
				if (first && first.screen) return first.screen;
			}
		}
	}
	
	return nil;
}


/// Extract key window from UIApplication in a single-thread-safe call (must be executed on main thread).
+ (UIWindow *)_keyWindowFromApplication:(id)app {
	// Try valueForKey:@"keyWindow" first (works on iOS 12)
	if ([app respondsToSelector:NSSelectorFromString(@"keyWindow")]) {
		UIWindow *kw = [app valueForKey:@"keyWindow"];
		if (kw) return kw;
	}
	
	// fallback to application.keyWindow (if available)
	if ([app respondsToSelector:NSSelectorFromString(@"windows")]) {
		id windows = [app valueForKey:@"windows"];
		if (windows && [windows respondsToSelector:@selector(count)]) {
			for (UIWindow *w in windows) {
				if (w.isKeyWindow) return w;
			}
			// no keyWindow -> return first window if present
			if ([windows respondsToSelector:@selector(firstObject)]) {
				UIWindow *first = [windows firstObject];
				if (first) return first;
			}
		}
	}
	return nil;
}


@end
