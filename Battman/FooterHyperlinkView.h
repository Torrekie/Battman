//
//  FooterHyperlinkView.h
//  testhyperfoot
//
//  Created by Torrekie on 2025/10/26.
//

#import <UIKit/UIKit.h>

@interface UIView ()
- (UIColor *)_accessibilityHigherContrastTintColorForColor:(UIColor *)color;
- (void)_accessibilitySetInterfaceStyleIntent:(UIUserInterfaceStyle)style;
@end
@interface UITextView ()
- (BOOL)_isInteractiveTextSelectionDisabled;
- (void)_setInteractiveTextSelectionDisabled:(BOOL)disabled;
@end
@interface UITableView ()
- (CGFloat)_marginWidth;
- (UIEdgeInsets)_sectionContentInset;
@end
@interface UITableViewHeaderFooterView ()
@property (nonatomic, weak) UITableView *tableView;
+ (UIFont *)_defaultFontForTableViewStyle:(UITableViewStyle)style isSectionHeader:(BOOL)isSectionHeader;
@end

@interface FooterHyperlinkViewConfiguration : NSObject
@property (nonatomic, strong) NSString *text;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSString *linkRange;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

@interface FooterHyperlinkView : UITableViewHeaderFooterView <UITextViewDelegate> {
	NSString *_text;
	NSURL *_URL;
	id __weak _target;
	SEL _action;
}
@property (nonatomic, strong, readonly) NSString *text;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSLayoutConstraint *textViewLeadingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *textViewTrailingConstraint;
@property (nonatomic, assign) NSRange linkRange;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, strong) NSURL *URL;

- (CGFloat)preferredHeightForWidth:(CGFloat)width tableView:(UITableView *)tableView;
- (instancetype)initWithTableView:(UITableView *)tableView configuration:(FooterHyperlinkViewConfiguration *)configuration;
@end
