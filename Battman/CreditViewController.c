#include "cobjc/cobjc.h"
#include "common.h"

typedef UIViewController CreditVC;

CFStringRef CreditViewControllerGetTitle(void) {
    return _("Credit");
}

CreditVC *CreditViewControllerInit(CreditVC *self) {
	UITableViewStyle style = UITableViewStyleGrouped;
	if (__builtin_available(iOS 13.0, *))
		style = UITableViewStyleInsetGrouped;
	return osupercall(CreditViewControllerNew, self, initWithStyle:, style);
}

long CreditViewControllerNumRows(CreditVC *self, void *data, UITableView *tv, NSInteger sect) {
	if (sect == 0)
		return 2;
	if (sect == 1)
		return 1;
	return 0;
}

long CreditViewControllerNumSects(CreditVC *self, void *data, UITableView *tv) {
	return 2;
}

CFStringRef CreditViewControllerTableTitle(CreditVC *self, void *data, UITableView *tv, NSInteger sect) {
	if (sect == 0) return _("Battman Credit");
	if (sect == 1) return _("Localizations");
	return nil;
}

CFNumberRef CVGetRef(id self, void *ref) {
	return CFAutorelease(CFNumberCreate(NULL,kCFNumberSInt64Type,&ref));
}
CFStringRef CVGetRef1(id self, SEL sel) {
	return _(sel_getName(sel));
}

static const void *contributors[] = {
	CFSTR("therealhoodboy"), CFSTR("Deutsch (de)"), "https://github.com/therealhoodboy",
};

void CreditViewControllerDidSelectRow(CreditVC *self, void *data, UITableView *tv, NSIndexPath *indexPath) {
	if (NSIndexPathGetSection(indexPath) == 0) {
		open_url(NSIndexPathGetRow(indexPath) ? "https://github.com/LNSSPsd" : "https://github.com/Torrekie");
	}
	if (NSIndexPathGetSection(indexPath) == 1) {
		open_url(contributors[NSIndexPathGetRow(indexPath) * 3 + 2]);
	}

	UITableViewDeselectRow(tv, indexPath, 1);
}

UITableViewCell *CreditViewCellForRow(CreditVC *self, void *data, UITableView *tv, NSIndexPath *indexPath) {
	UITableViewCell *cell;
	if (NSIndexPathGetSection(indexPath) == 0) {
		cell           = NSObjectNew(UITableViewCell);
		UILabel *label = UITableViewCellGetTextLabel(cell);
		UILabelSetText(label, NSIndexPathGetRow(indexPath) ? CFSTR("Ruphane") : CFSTR("Torrekie"));
		UILabelSetTextColor(label, UIColorLinkColor());
	}
	if (NSIndexPathGetSection(indexPath) == 1) {
		cell           = UITableViewCellInit(NSObjectAllocate(UITableViewCell), UITableViewCellStyleSubtitle, nil);
		UILabel *label = UITableViewCellGetTextLabel(cell);
		UILabel *sub   = UITableViewCellGetDetailTextLabel(cell);
		UILabelSetText(label, contributors[NSIndexPathGetRow(indexPath) * 3]);
		UILabelSetText(sub, contributors[NSIndexPathGetRow(indexPath) * 3 + 1]);
		UILabelSetTextColor(label, UIColorLinkColor());
	}
	return (UITableViewCell *)CFAutorelease(cell);
}

MAKE_CLASS(CreditViewControllerNew,UITableViewController,0, \
	CVGetRef1, debugGetRefC,, \
	CreditViewControllerInit, init, \
	CreditViewControllerGetTitle, title, \
	CreditViewControllerNumRows, tableView:numberOfRowsInSection:, \
	CreditViewControllerNumSects, numberOfSectionsInTableView:, \
	CreditViewControllerTableTitle, tableView:titleForHeaderInSection:, \
	CreditViewControllerDidSelectRow, tableView:didSelectRowAtIndexPath:, \
	CreditViewCellForRow, tableView:cellForRowAtIndexPath:, \
	CVGetRef, debugGetRef);
