//
//  BAAnalyticsUnavailableCard.h
//  Battman
//


#import <UIKit/UIKit.h>

#import "../Public/BAAnalyticsCard.h"

@interface BAAnalyticsUnavailableCard : NSObject <BAAnalyticsCard>
@property (nonatomic, copy, readonly) NSString *analyticsCardIdentifier;
@property (nonatomic, copy, readonly) NSString *analyticsCardDisplayName;
@property (nonatomic, readonly) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic, readonly) BAAnalyticsCardSize defaultAnalyticsCardSize;

- (instancetype)initWithIdentifier:(NSString *)identifier
						 displayName:(NSString *)displayName
		 restorationSchemaVersion:(NSUInteger)restorationSchemaVersion
					 restorationState:(NSDictionary *)restorationState;
@end
