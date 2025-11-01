//
//  FooterHyperlinkView.m
//  testhyperfoot
//
//  Created by Torrekie on 2025/10/26.
//

#include "common.h"
#import "FooterHyperlinkView.h"

@implementation FooterHyperlinkViewConfiguration

- (instancetype)init {
	self = [super init];
	return self;
}

@end

@implementation FooterHyperlinkView

- (instancetype)initWithTableView:(UITableView *)tableView configuration:(FooterHyperlinkViewConfiguration *)configuration {
	self = [super initWithFrame:CGRectZero];
	if (self) {
		self.tableView = tableView;
		[self setupSubviewsAndContstraints];
		NSString *text = configuration.text;
		if (text)
			[self setText:text];

		NSURL *URL = configuration.URL;
		if (URL)
			self.URL = configuration.URL;

		NSString *linkRange = configuration.linkRange;
		if (linkRange)
			self.linkRange = NSRangeFromString(linkRange);

		SEL action = configuration.action;
		if (action) {
			self.action = action;
			self.target = configuration.target;
		}

		[self _linkify];
	}
	return self;
}

- (void)setupSubviewsAndContstraints {
	self.textView = [[UITextView alloc] init];
	self.textView.translatesAutoresizingMaskIntoConstraints = NO;
	self.textView.backgroundColor = UIColor.clearColor;
	self.textView.showsVerticalScrollIndicator = NO;
	self.textView.editable = NO;
	self.textView.selectable = YES;
	self.textView.scrollEnabled = NO;
	self.textView.textContainer.lineFragmentPadding = 0.0;
	[self.textView _setInteractiveTextSelectionDisabled:YES];
	self.textView.delegate = self;
	[self.contentView addSubview:self.textView];

	NSMutableArray *constraints = [NSMutableArray array];
	self.textViewLeadingConstraint = [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.safeAreaLayoutGuide.leadingAnchor constant:[self.tableView _marginWidth]];
	[constraints addObject:self.textViewLeadingConstraint];

	self.textViewTrailingConstraint = [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.safeAreaLayoutGuide.trailingAnchor constant:-[self.tableView _marginWidth]];
	[constraints addObject:self.textViewTrailingConstraint];

	NSLayoutConstraint *topAnchor = [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor];
	[constraints addObject:topAnchor];

	NSLayoutConstraint *bottomAnchor = [self.textView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor];
	[constraints addObject:bottomAnchor];

	[NSLayoutConstraint activateConstraints:constraints];
}

- (void)setText:(NSString *)text {
	if (![self->_text isEqualToString:text]) {
		NSString *oldText = self->_text;
		self->_text = text;

		if (oldText && oldText.length > 0) {
			[UIView transitionWithView:self.textView duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
				self.textView.text = self->_text;
				[self _linkify];
								// Force the table view to recalculate footer height
				if (self.tableView) {
					[self.tableView beginUpdates];
					[self.tableView endUpdates];
				}
			} completion:^(BOOL finished) {
				[self setNeedsUpdateConstraints];
				[self setNeedsLayout];
				[self layoutIfNeeded];
			}];
		} else {
			self.textView.text = self->_text;
			[self _linkify];
			[self setNeedsUpdateConstraints];
			[self setNeedsLayout];
		}
	}
}

- (void)setURL:(NSURL *)URL {
	if (![self->_URL isEqual:URL]) {
		self->_URL = URL;
		[self setNeedsUpdateConstraints];
		[self _linkify];
	}
}

- (void)setLinkRange:(NSRange)linkRange {
	if (!NSEqualRanges(self->_linkRange, linkRange)) {
		self->_linkRange = linkRange;
		if (self.text)
			[self _linkify];
	}
}

- (void)setTableView:(UITableView *)tableView {
	[super setTableView:tableView];
	[self setNeedsUpdateConstraints];
}

- (void)updateConstraints {
	if (self.textViewTrailingConstraint.constant != -self.tableView._marginWidth)
		self.textViewTrailingConstraint.constant = -self.tableView._marginWidth;
	if (self.textViewLeadingConstraint.constant != self.tableView._marginWidth)
		self.textViewLeadingConstraint.constant = self.tableView._marginWidth;

	[super updateConstraints];
}

- (BOOL)isValidLinkRange {
	NSRange linkRange = self.linkRange;
	if (linkRange.location == NSNotFound)
		return NO;

	return NSMaxRange(linkRange) <= self.text.length;
}

- (void)_linkify {
	if (self.text) {
		NSUInteger length = self.text.length;
		NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:self.text];

		if (UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory)) {
			NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
			paragraphStyle.hyphenationFactor = 0.45;
			[attributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, length)];
		}

		UIFont *footerFont;
		if ([UITableViewHeaderFooterView respondsToSelector:@selector(_defaultFontForTableViewStyle:isSectionHeader:)]) {
			footerFont = [UITableViewHeaderFooterView _defaultFontForTableViewStyle:UITableViewStyleGrouped isSectionHeader:NO];
		} else {
			UIFontDescriptor *fontDesc = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleFootnote] fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitTightLeading];
			footerFont = [UIFont fontWithDescriptor:fontDesc size:0.0];
		}
		[attributedString addAttribute:NSFontAttributeName value:footerFont range:NSMakeRange(0, length)];

		UIColor *footerColor;
		UIColor *footerHyperlinkColor;
		if (@available(iOS 13.0, *)) {
			footerColor = (UIColor *)perform_selector(sel_registerName("_groupTableHeaderFooterTextColor"), [UIColor class], nil);
			footerHyperlinkColor = UIColor.linkColor;
		} else {
			footerColor = [UIColor colorWithRed:(109.0f / 255) green:(109.0f / 255) blue:(114.0f / 255) alpha:1.0];
			footerHyperlinkColor = [UIColor colorWithRed:0 green:(122.0f / 255) blue:1 alpha:1];
		}
		
		UIColor *foregroundColor = [self _accessibilityHigherContrastTintColorForColor:footerColor];
		[attributedString addAttribute:NSForegroundColorAttributeName value:foregroundColor range:NSMakeRange(0, length)];

		if (self.linkRange.length && [self isValidLinkRange]) {
			foregroundColor = [self _accessibilityHigherContrastTintColorForColor:footerHyperlinkColor];
			[attributedString addAttribute:NSForegroundColorAttributeName value:foregroundColor range:self.linkRange];
			if (self.URL) {
				[attributedString addAttribute:NSLinkAttributeName value:self.URL range:self.linkRange];
			} else {
				[attributedString addAttribute:NSLinkAttributeName value:[NSURL URLWithString:@""] range:self.linkRange];
			}
			[attributedString addAttribute:NSUnderlineStyleAttributeName value:(id)kCFBooleanFalse range:self.linkRange];
		}

		self.textView.attributedText = attributedString;
		if (self.linkRange.length && footerHyperlinkColor) {
			self.textView.linkTextAttributes = @{
				NSForegroundColorAttributeName: [self _accessibilityHigherContrastTintColorForColor:footerHyperlinkColor],
			};
		}
	}
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width tableView:(UITableView *)tableView {
	[self setTableView:tableView];
	return [self systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
}

- (void)_accessibilitySetInterfaceStyleIntent:(UIUserInterfaceStyle)style {
	[super _accessibilitySetInterfaceStyleIntent:style];
	[self _linkify];
}

#pragma mark - UITextView Delegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction {
	if (!self.target)
		return YES;
	// XXX: Why not just ocall?
	perform_selector(self.action, self.target, self);
	return NO;
}

@end
