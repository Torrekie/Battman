#pragma once
#import <UIKit/UIKit.h>

@interface ChargingLimitViewController : UITableViewController
{
	int daemon_pid;
	int daemon_fd;
	char *vals;
	
	const char *load_graph;
#if 0
	Class PSGraphViewTableCell;
#endif
}
@end
