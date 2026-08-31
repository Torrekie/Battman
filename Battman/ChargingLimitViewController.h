#pragma once
#import <UIKit/UIKit.h>

@interface ChargingLimitViewController : UITableViewController
{
	int daemon_pid;
	int daemon_fd;
	char *vals;
	char fallback_vals[3];
	BOOL vals_mapped;
	
	const char *powerlog_db_path;
#if 0
	Class PSGraphViewTableCell;
#endif
}
@end
