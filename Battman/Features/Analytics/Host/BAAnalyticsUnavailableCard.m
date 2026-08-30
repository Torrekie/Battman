//
//  BAAnalyticsUnavailableCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsUnavailableCard.h"

#import "ObjCExt/UIColor+compat.h"

@interface BAAnalyticsUnavailableContentView : UIView
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation BAAnalyticsUnavailableContentView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (!self)
		return nil;
	self.isAccessibilityElement = YES;
	_nameLabel = [UILabel new];
	_nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	_nameLabel.adjustsFontForContentSizeCategory = YES;
	_nameLabel.textColor = [UIColor compatLabelColor];
	_nameLabel.numberOfLines = 2;
	[self addSubview:_nameLabel];
	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_statusLabel.adjustsFontForContentSizeCategory = YES;
	_statusLabel.textColor = [UIColor compatSecondaryLabelColor];
	_statusLabel.numberOfLines = 2;
	[self addSubview:_statusLabel];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect contentBounds = CGRectInset(self.bounds, 14.0, 14.0);
	CGFloat statusHeight = MIN(48.0, CGRectGetHeight(contentBounds) * 0.42);
	self.nameLabel.frame = CGRectMake(CGRectGetMinX(contentBounds), CGRectGetMinY(contentBounds), CGRectGetWidth(contentBounds), MAX(0.0, CGRectGetHeight(contentBounds) - statusHeight - 6.0));
	self.statusLabel.frame = CGRectMake(CGRectGetMinX(contentBounds), CGRectGetMaxY(contentBounds) - statusHeight, CGRectGetWidth(contentBounds), statusHeight);
}

@end

@interface BAAnalyticsUnavailableCard ()
@property (nonatomic, copy) NSString *analyticsCardIdentifier;
@property (nonatomic, copy) NSString *analyticsCardDisplayName;
@property (nonatomic) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic) BAAnalyticsCardSize defaultAnalyticsCardSize;
@property (nonatomic) NSUInteger savedRestorationSchemaVersion;
@property (nonatomic, copy) NSDictionary *savedRestorationState;
@end

@implementation BAAnalyticsUnavailableCard

- (instancetype)initWithIdentifier:(NSString *)identifier
						 displayName:(NSString *)displayName
		 restorationSchemaVersion:(NSUInteger)restorationSchemaVersion
					 restorationState:(NSDictionary *)restorationState {
	self = [super init];
	if (!self)
		return nil;
	_analyticsCardIdentifier = [identifier copy];
	_analyticsCardDisplayName = [displayName copy];
	_supportedAnalyticsCardSizes = BAAnalyticsCardSizeMaskAll;
	_defaultAnalyticsCardSize = BAAnalyticsCardSize1x1;
	_savedRestorationSchemaVersion = restorationSchemaVersion;
	_savedRestorationState = [restorationState copy] ?: @{};
	return self;
}

- (UIView *)makeAnalyticsCardContentView {
	return [BAAnalyticsUnavailableContentView new];
}

- (void)configureAnalyticsCardContentView:(UIView *)contentView forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	BAAnalyticsUnavailableContentView *view = (BAAnalyticsUnavailableContentView *)contentView;
	view.nameLabel.text = self.analyticsCardDisplayName;
	view.statusLabel.text = _("Unavailable");
	view.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", self.analyticsCardDisplayName, _("Unavailable")];
	[view setNeedsLayout];
}

- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size {
	return [NSString stringWithFormat:@"%@, %@", self.analyticsCardDisplayName, _("Unavailable")];
}

- (NSUInteger)analyticsCardRestorationSchemaVersion {
	return self.savedRestorationSchemaVersion;
}

- (NSDictionary *)analyticsCardRestorationState {
	return self.savedRestorationState;
}

@end
