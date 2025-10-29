#pragma once
#include "./cobjc.h"

// FIXME: Should migrate to UITableViewCell.h
typedef enum {
    UITableViewStylePlain,          // regular table view
    UITableViewStyleGrouped,        // sections are grouped together
    UITableViewStyleInsetGrouped  API_AVAILABLE(ios(13.0)) API_UNAVAILABLE(tvos)  // grouped sections are inset with rounded corners
} UITableViewStyle;

DefineObjcMethod(UITableView *,UITableViewControllerGetTableView,tableView);
