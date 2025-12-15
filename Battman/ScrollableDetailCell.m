//
//  ScrollableDetailCell.m
//  Battman
//
//  Created by Torrekie on 2025/12/3.
//

#import "ScrollableDetailCell.h"
#import <objc/runtime.h>

@protocol UITableConstants <NSObject>
- (UIColor *)defaultDetailTextColorForCellStyle:(UITableViewCellStyle)style traitCollection:(UITraitCollection *)traitCollection state:(int)state;
@end

@interface UITableViewCell ()
- (id<UITableConstants>)_constants;
- (UITableViewCellStyle)_cellStyle;
- (UILabel *)_textLabel:(BOOL)retain;
- (UILabel *)_detailTextLabel:(BOOL)retain;
@end

@interface UITableViewCellLayoutManager : NSObject
- (UILabel *)defaultLabelForCell:(UITableViewCell *)cell ofClass:(Class)class;
- (BOOL)shouldApplyAccessibilityLargeTextLayoutForCell:(UITableViewCell *)cell;
- (void)layoutSubviewsOfCell:(UITableViewCell *)cell;
@end

@interface UITableViewCellLayoutManagerValue1 : UITableViewCellLayoutManager
- (UIFont *)defaultTextLabelFontForCell:(UITableViewCell *)cell;
- (UIFont *)defaultDetailTextLabelFontForCell:(UITableViewCell *)cell;
@end

@interface ScrollableDetailCellLayoutManager : UITableViewCellLayoutManagerValue1
- (UILabel *)detailTextLabelForCell:(UITableViewCell *)cell;
- (UIScrollView *)scrollViewForCell:(UITableViewCell *)cell;
@end

@interface UITableViewCell ()
- (void)setLayoutManager:(UITableViewCellLayoutManager *)layoutManager;
@end

@implementation ScrollableDetailCellLayoutManager

static const void *kScrollViewKey = &kScrollViewKey;
static const void *kCachedTextKey = &kCachedTextKey;
static const void *kCachedFontKey = &kCachedFontKey;
static const void *kCachedWidthKey = &kCachedWidthKey;
static const void *kIsSetupKey = &kIsSetupKey;

- (UIScrollView *)scrollViewForCell:(UITableViewCell *)cell {
	UIScrollView *scrollView = objc_getAssociatedObject(cell, kScrollViewKey);
	if (!scrollView) {
		scrollView = [[UIScrollView alloc] init];
		scrollView.showsHorizontalScrollIndicator = YES;
		scrollView.showsVerticalScrollIndicator = NO;
		scrollView.scrollEnabled = YES;
		scrollView.bounces = YES;
		scrollView.alwaysBounceHorizontal = NO;
		scrollView.clipsToBounds = YES;
		scrollView.indicatorStyle = UIScrollViewIndicatorStyleDefault;
		// Move scroll indicator down slightly for better visual positioning
		scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(3.0, 0, -3.0, 0);
		objc_setAssociatedObject(cell, kScrollViewKey, scrollView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return scrollView;
}

- (UILabel *)detailTextLabelForCell:(UITableViewCell *)cell {
	UILabel *defaultLabel = (UILabel *)[super defaultLabelForCell:cell ofClass:NSClassFromString(@"UILabel")];
	id<UITableConstants> constants = [cell _constants];
	UIColor *textColor = [constants defaultDetailTextColorForCellStyle:[cell _cellStyle] traitCollection:[cell traitCollection] state:0];

	defaultLabel.textColor = textColor;
	defaultLabel.font = [super defaultDetailTextLabelFontForCell:cell];
	defaultLabel.textAlignment = [super shouldApplyAccessibilityLargeTextLayoutForCell:cell] ? NSTextAlignmentNatural : NSTextAlignmentRight;

	return defaultLabel;
}

- (void)layoutSubviewsOfCell:(UITableViewCell *)cell {
	[super layoutSubviewsOfCell:cell];
	UILabel *textLabel = [cell _textLabel:NO];
	if (textLabel) {
		if (textLabel.font.pointSize == 0.0)
			textLabel.font = [self defaultTextLabelFontForCell:cell];

		if (textLabel.text && textLabel.text.length) {
			if (!textLabel.superview) {
				[cell.contentView addSubview:textLabel];
			}
		} else {
			[textLabel removeFromSuperview];
		}
	}

	UILabel *detailTextLabel = [cell _detailTextLabel:NO];
	if (detailTextLabel) {
		NSTextAlignment alignment = [self shouldApplyAccessibilityLargeTextLayoutForCell:cell] ? NSTextAlignmentNatural : NSTextAlignmentRight;
		if (detailTextLabel.textAlignment != alignment)
			detailTextLabel.textAlignment = alignment;

		if (detailTextLabel.font.pointSize == 0.0)
			detailTextLabel.font = [self defaultDetailTextLabelFontForCell:cell];
		
		if (detailTextLabel.text && detailTextLabel.text.length) {
			// Get cached values
			NSString *cachedText = objc_getAssociatedObject(cell, kCachedTextKey);
			UIFont *cachedFont = objc_getAssociatedObject(cell, kCachedFontKey);
			NSNumber *cachedWidth = objc_getAssociatedObject(cell, kCachedWidthKey);
			
			// Check if text or font changed
			BOOL textChanged = ![cachedText isEqualToString:detailTextLabel.text];
			BOOL fontChanged = ![cachedFont isEqual:detailTextLabel.font];
			BOOL needsRecalculation = textChanged || fontChanged || !cachedWidth;
			
			CGFloat contentWidth;
			if (needsRecalculation) {
				// Only calculate text size when text or font changed
				CGSize textSize = [detailTextLabel.text sizeWithAttributes:@{NSFontAttributeName: detailTextLabel.font}];
				contentWidth = ceil(textSize.width);
				
				// Cache the values
				objc_setAssociatedObject(cell, kCachedTextKey, detailTextLabel.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
				objc_setAssociatedObject(cell, kCachedFontKey, detailTextLabel.font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				objc_setAssociatedObject(cell, kCachedWidthKey, @(contentWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			} else {
				// Use cached width
				contentWidth = [cachedWidth doubleValue];
			}
			
			CGRect originalFrame = detailTextLabel.frame;
			// Add tolerance to avoid unnecessary scrolling for text that fits
			// Only use scroll view if text is significantly wider than available space
			BOOL needsScrolling = (contentWidth > originalFrame.size.width + 5.0);
			
			if (needsScrolling) {
				// Text is clipped - use scroll view
				UIScrollView *scrollView = [self scrollViewForCell:cell];
				
				// Setup scroll view hierarchy if needed
				if (detailTextLabel.superview != scrollView) {
					[detailTextLabel removeFromSuperview];
					if (!scrollView.superview) {
						[cell.contentView addSubview:scrollView];
					}
					[scrollView addSubview:detailTextLabel];
				}
				
				// Update frames
				scrollView.frame = originalFrame;
				// Add small padding to contentWidth for scroll view content
				CGFloat scrollContentWidth = contentWidth + 2.0;
				detailTextLabel.frame = CGRectMake(0, 0, scrollContentWidth, originalFrame.size.height);
				scrollView.contentSize = CGSizeMake(scrollContentWidth, originalFrame.size.height);
				
				// Reset scroll position only when content changed
				if (needsRecalculation) {
					BOOL isRTL = NO;
					NSString *text = detailTextLabel.text;
					if (text.length > 0) {
						// Check the base writing direction of the text
						NSWritingDirection direction = [NSParagraphStyle defaultWritingDirectionForLanguage:nil];
						// Also check the actual text content
						unichar firstChar = [text characterAtIndex:0];
						// Common RTL Unicode ranges (Arabic, Hebrew, etc.)
						if ((firstChar >= 0x0590 && firstChar <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana
							(firstChar >= 0xFB1D && firstChar <= 0xFDFF) || // Hebrew/Arabic presentation forms
							(firstChar >= 0xFE70 && firstChar <= 0xFEFF)) { // Arabic presentation forms
							isRTL = YES;
						}
						// Also respect the layout direction if using Natural alignment
						if (alignment == NSTextAlignmentNatural && !isRTL) {
							if (@available(iOS 9.0, *)) {
								isRTL = (detailTextLabel.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
							}
						}
					}
					
					// Set initial scroll position based on text direction
					if (isRTL) {
						// For RTL, start at the right (end of content)
						CGFloat offsetX = scrollContentWidth - originalFrame.size.width;
						scrollView.contentOffset = CGPointMake(offsetX, 0);
					} else {
						// For LTR, start at the left (beginning of content)
						scrollView.contentOffset = CGPointZero;
					}
					// Flash scroll indicators synchronously - removed dispatch_async to avoid
					// excessive main queue operations during scrolling which causes frame drops
					[scrollView flashScrollIndicators];
				}
			} else {
				// Text fits - use normal layout without scroll view
				UIScrollView *scrollView = objc_getAssociatedObject(cell, kScrollViewKey);
				
				// Remove scroll view if it exists
				if (scrollView && scrollView.superview) {
					[scrollView removeFromSuperview];
				}
				
				// Ensure label is in contentView
				if (detailTextLabel.superview != cell.contentView) {
					[detailTextLabel removeFromSuperview];
					[cell.contentView addSubview:detailTextLabel];
				}
			}
		} else {
			// Remove scroll view when there's no text
			UIScrollView *scrollView = objc_getAssociatedObject(cell, kScrollViewKey);
			if (scrollView) {
				[scrollView removeFromSuperview];
			}
			[detailTextLabel removeFromSuperview];
			// Clear cache
			objc_setAssociatedObject(cell, kCachedTextKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
			objc_setAssociatedObject(cell, kCachedFontKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(cell, kCachedWidthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}
}

@end

@implementation ScrollableDetailCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
	if (self) {
		ScrollableDetailCellLayoutManager *layoutManager = [ScrollableDetailCellLayoutManager new];
		[self setLayoutManager:layoutManager];
	}
	return self;
}

@end
