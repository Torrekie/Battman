#pragma once
#include "./cobjc.h"

DefineObjcMethod(void,UITableViewDeselectRow,deselectRowAtIndexPath:animated:,NSIndexPath*,BOOL);
DefineObjcMethod(void,UITableViewReloadData,reloadData);

// FIXME: Should migrate to UITableViewCell.h

typedef CF_ENUM(NSInteger, UITableViewCellStyle) {
	UITableViewCellStyleDefault,
	UITableViewCellStyleValue1,
	UITableViewCellStyleValue2,
	UITableViewCellStyleSubtitle
};

DefineObjcMethod(UITableViewCell *, UITableViewCellInit, initWithStyle:reuseIdentifier:, UITableViewCellStyle, CFStringRef);
DefineObjcMethod(UILabel *, UITableViewCellGetTextLabel, textLabel);
DefineObjcMethod(UILabel *, UITableViewCellGetDetailTextLabel, detailTextLabel);
