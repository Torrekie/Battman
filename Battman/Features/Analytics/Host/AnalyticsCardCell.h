//
//  AnalyticsCardCell.h
//  Battman
//

#import <UIKit/UIKit.h>

#import "../Public/BAAnalyticsCard.h"

@interface BAAnalyticsCardCell : UICollectionViewCell
@property (nonatomic, readonly) UIButton *resizeButton;
@property (nonatomic, readonly) UIButton *removeButton;
@property (nonatomic, readonly) NSArray<UIButton *> *actionButtons;
@property (nonatomic, copy, readonly) NSString *mountedCardIdentifier;
- (void)configureWithCard:(id<BAAnalyticsCard>)card
						 size:(BAAnalyticsCardSize)size
					  editing:(BOOL)editing;
- (void)setAnalyticsCardDisplayed:(BOOL)displayed;
- (void)applyMetricSnapshot:(BAAnalyticsMetricSnapshot *)snapshot;
@end
