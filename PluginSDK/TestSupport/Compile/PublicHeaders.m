#import <BAAnalyticsCard.h>

@interface BTSDKObjectiveCConsumer : NSObject <BAAnalyticsCard>
@end
@implementation BTSDKObjectiveCConsumer
- (NSString *)analyticsCardIdentifier { return @"com.example.battman.compile.objc"; }
- (BAAnalyticsCardSizeMask)supportedAnalyticsCardSizes { return BAAnalyticsCardSizeMask1x1; }
- (BAAnalyticsCardSize)defaultAnalyticsCardSize { return BAAnalyticsCardSize1x1; }
- (UIView *)makeAnalyticsCardContentView { return [UIView new]; }
- (void)configureAnalyticsCardContentView:(UIView *)view forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	(void)view; (void)size; (void)editing;
}
@end
