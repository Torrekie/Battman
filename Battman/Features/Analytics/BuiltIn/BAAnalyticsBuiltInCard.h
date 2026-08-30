//
//  BAAnalyticsBuiltInCard.h
//  Battman
//
//  Shared rendering infrastructure for independently registered built-in cards.
//


#import <UIKit/UIKit.h>

#import "../Public/BAAnalyticsCard.h"

NS_ASSUME_NONNULL_BEGIN

@interface BAAnalyticsCardPresentation : NSObject
@property (nonatomic, copy, readonly) NSString *value;
@property (nonatomic, copy, readonly) NSString *caption;
@property (nonatomic, copy, readonly) NSArray<NSString *> *detailLines;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsMetricPoint *> *historyPoints;

+ (instancetype)presentationWithValue:(NSString *)value
							 caption:(NSString *)caption
						 detailLines:(nullable NSArray<NSString *> *)detailLines
						historyPoints:(nullable NSArray<BAAnalyticsMetricPoint *> *)historyPoints;
@end

@interface BAAnalyticsBuiltInCard : NSObject <BAAnalyticsCard>
@property (nonatomic, copy, readonly) NSString *analyticsCardIdentifier;
@property (nonatomic, copy, readonly) NSString *analyticsCardDisplayName;
@property (nonatomic, copy, readonly, nullable) NSString *cardTitle;
@property (nonatomic, copy, readonly) NSString *defaultCaption;
@property (nonatomic, copy, readonly, nullable) NSString *symbolName;
@property (nonatomic, copy, readonly, nullable) NSString *fallbackGlyph;
@property (nonatomic, strong, readonly) UIColor *tintColor;
@property (nonatomic, readonly) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic, readonly) BAAnalyticsCardSize defaultAnalyticsCardSize;
@property (nonatomic, readonly) BOOL showsGraph;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;

- (instancetype)initWithIdentifier:(NSString *)identifier
						 displayName:(NSString *)displayName
						   cardTitle:(nullable NSString *)cardTitle
					 defaultCaption:(NSString *)defaultCaption
						  symbolName:(nullable NSString *)symbolName
					 fallbackGlyph:(nullable NSString *)fallbackGlyph
						   tintColor:(UIColor *)tintColor
					 supportedSizes:(BAAnalyticsCardSizeMask)supportedSizes
						 defaultSize:(BAAnalyticsCardSize)defaultSize
						  showsGraph:(BOOL)showsGraph;

// Subclasses transform an immutable snapshot into their own UI presentation.
- (BAAnalyticsCardPresentation *)presentationForSnapshot:(nullable BAAnalyticsMetricSnapshot *)snapshot;
@end

FOUNDATION_EXPORT NSString *BAAnalyticsLabeledValue(NSString *label, NSString *value);

NS_ASSUME_NONNULL_END
