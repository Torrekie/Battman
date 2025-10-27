#pragma once
#import <UIKit/UIKit.h>

@interface BatterySubscriberViewControllerBase : UITableViewController
- (void)batteryStatusDidUpdate;
- (void)batteryStatusDidUpdate:(NSDictionary *)info;
@end

__BEGIN_DECLS

void BSVCRefreshModeDidUpdate(id self);

__END_DECLS
