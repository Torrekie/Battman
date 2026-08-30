//
//  BAAnalyticsCard.h
//  Battman Plugin SDK
//
//  Public Analytics card extension-point contract, version 1.
//

#import <UIKit/UIKit.h>

#include "BattmanPluginABI.h"
#import "BAAnalyticsMetricSnapshot.h"

#define BAAnalyticsCardExtensionPointIdentifier @BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1
#define BAAnalyticsCardExtensionPointVersion 1u

typedef NS_ENUM(NSInteger, BAAnalyticsCardSize) {
	BAAnalyticsCardSize1x1 = 0,
	BAAnalyticsCardSize1x2,
	BAAnalyticsCardSize2x1,
	BAAnalyticsCardSize2x2,
};

typedef NS_OPTIONS(NSUInteger, BAAnalyticsCardSizeMask) {
	BAAnalyticsCardSizeMask1x1 = 1u << BAAnalyticsCardSize1x1,
	BAAnalyticsCardSizeMask1x2 = 1u << BAAnalyticsCardSize1x2,
	BAAnalyticsCardSizeMask2x1 = 1u << BAAnalyticsCardSize2x1,
	BAAnalyticsCardSizeMask2x2 = 1u << BAAnalyticsCardSize2x2,
	BAAnalyticsCardSizeMaskAll = BAAnalyticsCardSizeMask1x1 | BAAnalyticsCardSizeMask1x2 |
		BAAnalyticsCardSizeMask2x1 | BAAnalyticsCardSizeMask2x2,
};

@protocol BAAnalyticsCardAction <NSObject>
@property (nonatomic, readonly, copy) NSString *analyticsCardActionIdentifier;

@optional
@property (nonatomic, readonly, copy) NSString *analyticsCardActionTitle;
@property (nonatomic, readonly, copy) NSString *analyticsCardActionSystemImageName;
@property (nonatomic, readonly, copy) NSString *analyticsCardActionFallbackTitle;
@end

static inline BAAnalyticsCardSizeMask BAAnalyticsCardSizeMaskForSize(BAAnalyticsCardSize size) {
	switch (size) {
		case BAAnalyticsCardSize1x1: return BAAnalyticsCardSizeMask1x1;
		case BAAnalyticsCardSize1x2: return BAAnalyticsCardSizeMask1x2;
		case BAAnalyticsCardSize2x1: return BAAnalyticsCardSizeMask2x1;
		case BAAnalyticsCardSize2x2: return BAAnalyticsCardSizeMask2x2;
	}
	return BAAnalyticsCardSizeMask1x1;
}

static inline BOOL BAAnalyticsCardSizeMaskContainsSize(BAAnalyticsCardSizeMask mask, BAAnalyticsCardSize size) {
	return (mask & BAAnalyticsCardSizeMaskForSize(size)) != 0;
}

static inline CGSize BAAnalyticsCardGridSpan(BAAnalyticsCardSize size) {
	switch (size) {
		case BAAnalyticsCardSize1x2: return CGSizeMake(1.0, 2.0);
		case BAAnalyticsCardSize2x1: return CGSizeMake(2.0, 1.0);
		case BAAnalyticsCardSize2x2: return CGSizeMake(2.0, 2.0);
		case BAAnalyticsCardSize1x1:
		default: return CGSizeMake(1.0, 1.0);
	}
}

static inline NSArray<NSNumber *> *BAAnalyticsCardOrderedSizesForMask(BAAnalyticsCardSizeMask mask) {
	NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithCapacity:4];
	if (mask & BAAnalyticsCardSizeMask1x1) [sizes addObject:@(BAAnalyticsCardSize1x1)];
	if (mask & BAAnalyticsCardSizeMask1x2) [sizes addObject:@(BAAnalyticsCardSize1x2)];
	if (mask & BAAnalyticsCardSizeMask2x1) [sizes addObject:@(BAAnalyticsCardSize2x1)];
	if (mask & BAAnalyticsCardSizeMask2x2) [sizes addObject:@(BAAnalyticsCardSize2x2)];
	return sizes;
}

static inline BAAnalyticsCardSize BAAnalyticsCardDefaultSizeForMask(BAAnalyticsCardSizeMask mask) {
	NSArray<NSNumber *> *sizes = BAAnalyticsCardOrderedSizesForMask(mask);
	return sizes.count == 0 ? BAAnalyticsCardSize1x1 : (BAAnalyticsCardSize)sizes.firstObject.integerValue;
}

static inline BAAnalyticsCardSize BAAnalyticsCardNextSize(BAAnalyticsCardSize current, BAAnalyticsCardSizeMask mask) {
	NSArray<NSNumber *> *sizes = BAAnalyticsCardOrderedSizesForMask(mask);
	if (sizes.count == 0)
		return BAAnalyticsCardSize1x1;
	NSUInteger index = [sizes indexOfObject:@(current)];
	return index == NSNotFound ? (BAAnalyticsCardSize)sizes.firstObject.integerValue :
		(BAAnalyticsCardSize)[sizes[(index + 1) % sizes.count] integerValue];
}

@protocol BAAnalyticsCard <NSObject>
@property (nonatomic, readonly, copy) NSString *analyticsCardIdentifier;
@property (nonatomic, readonly) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic, readonly) BAAnalyticsCardSize defaultAnalyticsCardSize;

- (UIView *)makeAnalyticsCardContentView;
- (void)configureAnalyticsCardContentView:(UIView *)contentView
								  forSize:(BAAnalyticsCardSize)size
								  editing:(BOOL)editing;

@optional
// Every UIKit entry point is invoked on the main thread. Sensor acquisition is
// represented only by immutable snapshots; cards must not poll hardware from
// their drawing or layout paths.
- (UIColor *)analyticsCardBackgroundColor;
- (NSString *)analyticsCardDisplayName;
- (NSString *)analyticsCardAccessibilityLabelForSize:(BAAnalyticsCardSize)size;
- (NSArray<id<BAAnalyticsCardAction>> *)analyticsCardActionsForSize:(BAAnalyticsCardSize)size;
- (void)analyticsCardPerformAction:(id<BAAnalyticsCardAction>)action
		  presentingViewController:(UIViewController *)presentingViewController;
- (UIViewController *)analyticsCardViewControllerForSize:(BAAnalyticsCardSize)size;
- (void)analyticsCardWillDisplayContentView:(UIView *)contentView;
- (void)analyticsCardDidEndDisplayingContentView:(UIView *)contentView;
- (void)analyticsCardContentView:(UIView *)contentView
		 didReceiveMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot;
- (void)analyticsCardContentView:(UIView *)contentView didChangeEditing:(BOOL)editing;
- (void)analyticsCardDidReceiveMemoryWarning;

// Restoration state must be a bounded property-list dictionary. The host owns
// validation and persists it together with the provider schema version.
- (NSUInteger)analyticsCardRestorationSchemaVersion;
- (NSDictionary *)analyticsCardRestorationState;
- (NSDictionary *)analyticsCardMigrateRestorationState:(NSDictionary *)restorationState
								fromSchemaVersion:(NSUInteger)schemaVersion;
- (void)analyticsCardRestoreState:(NSDictionary *)restorationState;

// Source-compatible fallback retained for early v1 providers.
- (void)analyticsCardWillEndDisplayingContentView:(UIView *)contentView;
@end
