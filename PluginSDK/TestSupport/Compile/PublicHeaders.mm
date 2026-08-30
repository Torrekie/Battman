#import <BAAnalyticsCard.h>

#include <type_traits>

static_assert(std::is_standard_layout<BTPluginDescriptorV1>::value,
	"the C descriptor must remain standard-layout in Objective-C++");

@interface BTSDKObjectiveCXXConsumer : NSObject <BAAnalyticsCard>
@end
@implementation BTSDKObjectiveCXXConsumer
- (NSString *)analyticsCardIdentifier { return @"com.example.battman.compile.objcxx"; }
- (BAAnalyticsCardSizeMask)supportedAnalyticsCardSizes { return BAAnalyticsCardSizeMaskAll; }
- (BAAnalyticsCardSize)defaultAnalyticsCardSize { return BAAnalyticsCardSize2x2; }
- (UIView *)makeAnalyticsCardContentView { return [UIView new]; }
- (void)configureAnalyticsCardContentView:(UIView *)view forSize:(BAAnalyticsCardSize)size editing:(BOOL)editing {
	(void)view; (void)size; (void)editing;
}
@end
