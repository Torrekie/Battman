//
//  BAAnalyticsChargingLimitCard.m
//  Battman
//


#import "common.h"
#import "BAAnalyticsBuiltInCard.h"
#import "BAAnalyticsBuiltInCards.h"

#import "ChargingLimitViewController.h"
#import "ObjCExt/UIColor+compat.h"

static NSString *const BAAnalyticsChargingLimitOpenActionIdentifier = @"open";

@interface BAAnalyticsChargingLimitAction : NSObject <BAAnalyticsCardAction>
@property (nonatomic, copy) NSString *analyticsCardActionIdentifier;
@property (nonatomic, copy) NSString *analyticsCardActionTitle;
@property (nonatomic, copy) NSString *analyticsCardActionSystemImageName;
@property (nonatomic, copy) NSString *analyticsCardActionFallbackTitle;
@end

@implementation BAAnalyticsChargingLimitAction
@end

@interface BAAnalyticsChargingLimitCard : BAAnalyticsBuiltInCard
@end

@implementation BAAnalyticsChargingLimitCard

- (instancetype)init {
	return [super initWithIdentifier:BAAnalyticsChargingLimitCardIdentifier
							 displayName:_("Charging Limit")
							   cardTitle:_("Charging Limit")
						 defaultCaption:_("Status")
							  symbolName:@"bolt.fill"
						 fallbackGlyph:@"L"
							   tintColor:[UIColor compatBlueColor]
						 supportedSizes:BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2
							 defaultSize:BAAnalyticsCardSize2x1
							  showsGraph:YES];
}

- (BAAnalyticsCardPresentation *)presentationForSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSNumber *serviceActive = [snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingLimitServiceActive];
	NSNumber *limit = [snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingLimitPercent];
	NSString *value = _("Unavailable");
	if (serviceActive)
		value = serviceActive.boolValue ? (limit ? [NSString stringWithFormat:@"%.0f%%", limit.doubleValue] : _("Unavailable")) : _("Inactive");
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	if (serviceActive)
		[details addObject:BAAnalyticsLabeledValue(_("Status"), serviceActive.boolValue ? _("Active") : _("Inactive"))];
	if (limit)
		[details addObject:BAAnalyticsLabeledValue(_("Limit charging at (%)"), [NSString stringWithFormat:@"%.0f%%", limit.doubleValue])];
	if ([[snapshot valueForMetricIdentifier:BAAnalyticsMetricChargingLimitReached] boolValue])
		[details addObject:_("Charging Limit Reached")];
	return [BAAnalyticsCardPresentation presentationWithValue:value
													 caption:_("Status")
											   detailLines:details
											  historyPoints:[snapshot historyForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent]];
}

- (NSArray<id<BAAnalyticsCardAction>> *)analyticsCardActionsForSize:(BAAnalyticsCardSize)size {
	BAAnalyticsChargingLimitAction *action = [BAAnalyticsChargingLimitAction new];
	action.analyticsCardActionIdentifier = BAAnalyticsChargingLimitOpenActionIdentifier;
	action.analyticsCardActionTitle = _("Open");
	action.analyticsCardActionSystemImageName = @"arrow.up.forward.app";
	action.analyticsCardActionFallbackTitle = @">";
	return @[action];
}

- (UIViewController *)analyticsCardViewControllerForSize:(BAAnalyticsCardSize)size {
	return [ChargingLimitViewController new];
}

- (void)analyticsCardPerformAction:(id<BAAnalyticsCardAction>)action presentingViewController:(UIViewController *)presentingViewController {
	if (![action.analyticsCardActionIdentifier isEqualToString:BAAnalyticsChargingLimitOpenActionIdentifier])
		return;
	UIViewController *viewController = [self analyticsCardViewControllerForSize:self.defaultAnalyticsCardSize];
	if (presentingViewController.navigationController)
		[presentingViewController.navigationController pushViewController:viewController animated:YES];
	else
		[presentingViewController presentViewController:viewController animated:YES completion:nil];
}

@end

id<BAAnalyticsCard> BAAnalyticsCreateChargingLimitCard(void) {
	return [BAAnalyticsChargingLimitCard new];
}
