//
//  AnalyticsViewController.h
//  Battman — Analytics Host
//

#import <UIKit/UIKit.h>
#import "../Public/BAAnalyticsCard.h"

@class BAAnalyticsMetricService, BAAnalyticsHistoryService;

@interface AnalyticsViewController : UIViewController
// The normal initializer supplies production providers. This boundary also
// permits Simulator fixtures without putting demo values in production code.
- (instancetype)initWithCards:(NSArray<id<BAAnalyticsCard>> *)cards
                metricService:(BAAnalyticsMetricService *)metricService
               historyService:(BAAnalyticsHistoryService *)historyService
                 userDefaults:(NSUserDefaults *)userDefaults;
@end
