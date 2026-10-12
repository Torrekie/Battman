#pragma once
#import <UIKit/UIKit.h>

@interface ChargingLimitViewController : UITableViewController
{
	int daemon_pid; // Main-thread presentation snapshot.
	int daemon_fd;  // Serial daemon queue only, except final close in dealloc.
	char *vals;
	char fallback_vals[3];
	BOOL vals_mapped;
	
	const char *powerlog_db_path;
#if 0
	Class PSGraphViewTableCell;
#endif
}
@end
