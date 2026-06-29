#include "cobjc/cobjc.h"
#include "common.h"

typedef UIViewController CreditVC;

#ifndef nitems
#define nitems(x) (sizeof((x)) / sizeof((x)[0]))
#endif

typedef enum {
	CREDIT_SECTION_BATTMAN,
	CREDIT_SECTION_LOCALIZATIONS,
	CREDIT_SECTION_COUNT,
} CreditSection;

typedef struct {
	CFStringRef name;
	const char *url;
} CreditContributor;

typedef struct {
	CFStringRef name;
	CFStringRef detail;
	const char *url;
} CreditLocalizationContributor;

static const CreditContributor battman_contributors[] = {
	{ CFSTR("Torrekie"), "https://github.com/Torrekie" },
	{ CFSTR("Ruphane"), "https://github.com/LNSSPsd" },
	{ CFSTR("Lessica"), "https://github.com/Lessica" },
};

static const CreditLocalizationContributor localization_contributors[] = {
	{ CFSTR("therealhoodboy"), CFSTR("Deutsch (de)"), "https://github.com/therealhoodboy" },
	{ CFSTR("AD-iOS"), CFSTR("繁體中文 (zh_TW)"), "https://github.com/AD-iOS" },
};

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
	if (sect == CREDIT_SECTION_BATTMAN)
		return nitems(battman_contributors);
	if (sect == CREDIT_SECTION_LOCALIZATIONS)
		return nitems(localization_contributors);
	return 0;
}

long CreditViewControllerNumSects(CreditVC *self, void *data, UITableView *tv) {
	return CREDIT_SECTION_COUNT;
}

CFStringRef CreditViewControllerTableTitle(CreditVC *self, void *data, UITableView *tv, NSInteger sect) {
	if (sect == CREDIT_SECTION_BATTMAN) return _("Battman Credit");
	if (sect == CREDIT_SECTION_LOCALIZATIONS) return _("Localizations");
	return nil;
}

CFNumberRef CVGetRef(id self, void *ref) {
	return CFAutorelease(CFNumberCreate(NULL,kCFNumberSInt64Type,&ref));
}
CFStringRef CVGetRef1(id self, SEL sel) {
	return _(sel_getName(sel));
}

void CreditViewControllerDidSelectRow(CreditVC *self, void *data, UITableView *tv, NSIndexPath *indexPath) {
	NSInteger section = NSIndexPathGetSection(indexPath);
	NSInteger row     = NSIndexPathGetRow(indexPath);

	if (section == CREDIT_SECTION_BATTMAN) {
		open_url(battman_contributors[row].url);
	}
	if (section == CREDIT_SECTION_LOCALIZATIONS) {
		open_url(localization_contributors[row].url);
	}

	UITableViewDeselectRow(tv, indexPath, 1);
}

UITableViewCell *CreditViewCellForRow(CreditVC *self, void *data, UITableView *tv, NSIndexPath *indexPath) {
	UITableViewCell *cell;
	NSInteger        section = NSIndexPathGetSection(indexPath);
	NSInteger        row     = NSIndexPathGetRow(indexPath);

	if (section == CREDIT_SECTION_BATTMAN) {
		cell           = NSObjectNew(UITableViewCell);
		UILabel *label = UITableViewCellGetTextLabel(cell);
		UILabelSetText(label, battman_contributors[row].name);
		UILabelSetTextColor(label, UIColorLinkColor());
	}
	if (section == CREDIT_SECTION_LOCALIZATIONS) {
		cell           = UITableViewCellInit(NSObjectAllocate(UITableViewCell), UITableViewCellStyleSubtitle, nil);
		UILabel *label = UITableViewCellGetTextLabel(cell);
		UILabel *sub   = UITableViewCellGetDetailTextLabel(cell);
		UILabelSetText(label, localization_contributors[row].name);
		UILabelSetText(sub, localization_contributors[row].detail);
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
