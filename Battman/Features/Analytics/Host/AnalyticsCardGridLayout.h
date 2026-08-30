//
//  AnalyticsCardGridLayout.h
//  Battman
//

#import <UIKit/UIKit.h>

#import "../Public/BAAnalyticsCard.h"

@class BAAnalyticsCardGridLayout;

@protocol BAAnalyticsCardGridLayoutDelegate <UICollectionViewDelegate>
- (BAAnalyticsCardSize)collectionView:(UICollectionView *)collectionView
					cardGridLayout:(BAAnalyticsCardGridLayout *)layout
			  sizeForItemAtIndexPath:(NSIndexPath *)indexPath;
@end

@interface BAAnalyticsCardGridLayout : UICollectionViewLayout
@property (nonatomic) UIEdgeInsets sectionInset;
@property (nonatomic) CGFloat minimumInteritemSpacing;
@property (nonatomic) CGFloat minimumLineSpacing;
@property (nonatomic) CGFloat minimumColumnWidth;
@property (nonatomic) NSUInteger maximumNumberOfColumns;

- (NSUInteger)numberOfColumnsForWidth:(CGFloat)viewWidth;
@end
