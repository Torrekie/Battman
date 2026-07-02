#import "BatteryDetailsViewController.h"
#import "FullSMCViewController.h"
#import "MultilineViewCell.h"
#import "SegmentedViewCell.h"
#import "ScrollableDetailCell.h"
#import "WarnAccessoryView.h"
#import "BattmanPrefs.h"
#include "battery_utils/bin_display.h"
#include "battery_utils/iokit_connection.h"
#include "battery_utils/libsmc.h"
#include "common.h"
#include "intlextern.h"

#import "ObjCExt/UIColor+compat.h"

#import <CoreText/CoreText.h>
#include <string.h>
#include <sys/sysctl.h>

@class BDVCBatteryInfoTableSnapshot;

@interface BDVCBatteryInfoNodeSnapshot : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *stringValue;
@property(nonatomic, copy) NSString *desc;
@property(nonatomic, assign) uint32_t content;
@property(nonatomic, assign) NSUInteger sourceIndex;
@end

@implementation BDVCBatteryInfoNodeSnapshot
@end

@interface BDVCBatteryInfoSectionSnapshot : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *footer;
@property(nonatomic, strong) NSArray<BDVCBatteryInfoNodeSnapshot *> *rows;
@property(nonatomic, assign) uint64_t customIdentifier;
@end

@implementation BDVCBatteryInfoSectionSnapshot
@end

@interface BDVCBatteryInfoTableSnapshot : NSObject {
@public
	gas_gauge_t gauge;
	int timeToEmpty;
}
@property(nonatomic, strong) NSArray<BDVCBatteryInfoSectionSnapshot *> *sections;
@end

@implementation BDVCBatteryInfoTableSnapshot
@end

/* Desc */
@interface BatteryDetailsViewController () {
	hvc_menu_t *hvc_menu;
	int8_t      hvc_index;
	size_t      hvc_menu_size;
	bool        hvc_soft;
	bool        hvc_menu_owned;
	dispatch_queue_t refreshQueue;
	BOOL        refreshInFlight;
	BOOL        refreshPending;
	BOOL        refreshSuspended;
	NSUInteger  refreshGeneration;
	NSUInteger  refreshInFlightGeneration;
	BDVCBatteryInfoTableSnapshot *batteryInfoSnapshot;
}
@end

UILabel *equipCellTitle(UITableViewCell *cell, NSString *text) {
    // textLabel always exist
    cell.textLabel.text = text;
    if ([cell respondsToSelector:@selector(titleLabel)]) {
        // Suppress compiler warning about performSelector leak
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		UILabel *title = [cell performSelector:@selector(titleLabel)];
#pragma clang diagnostic pop

		if ([title isKindOfClass:[UILabel class]]) {
			title.text = text;
		}
		return title;
	}

	return cell.textLabel;
}

void equipCellHighLegit(UILabel *label) {
	static NSMutableDictionary<NSNumber *, UIFont *> *fontCache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		fontCache = [NSMutableDictionary dictionary];
	});
	
	CGFloat pointSize = label.font.pointSize;
	NSNumber *sizeKey = @(pointSize);
	UIFont *cachedFont = fontCache[sizeKey];
	
	if (!cachedFont) {
		// Create font with high legibility alternative glyph (stylistic alternative 6)
		CTFontDescriptorRef desc = CTFontDescriptorCreateCopyWithFeature(
			(__bridge CTFontDescriptorRef)label.font.fontDescriptor,
			(__bridge CFNumberRef)@(kStylisticAlternativesType),
			(__bridge CFNumberRef)@(kStylisticAltSixOnSelector));
		CTFontRef font = CTFontCreateWithFontDescriptor(desc, pointSize, NULL);
		cachedFont = (__bridge_transfer UIFont *)font;
		
		if (desc) CFRelease(desc);
		
		// Cache the font for reuse
		if (cachedFont) {
			fontCache[sizeKey] = cachedFont;
		}
	}
	
	if (cachedFont) {
		[label setFont:cachedFont];
	}
}

static NSString *BDVCStringFromUTF8(const char *str) {
	return str ? [NSString stringWithUTF8String:str] : nil;
}

static NSString *BDVCFormattedValueForContent(uint32_t content, NSString *stringValue) {
	if ((content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL)
		return bin_format_special(content) ?: @"";
	return stringValue ?: @"";
}

static void BDVCEquipDetailCellWithSnapshot(UITableViewCell *cell, BDVCBatteryInfoNodeSnapshot *node) {
	NSString *name = node.name ?: @"";
	equipCellTitle(cell, _(name.UTF8String));
	if (node.desc) {
		if (@available(iOS 13.0, *)) {
			cell.accessoryType = UITableViewCellAccessoryDetailButton;
		} else {
			WarnAccessoryView *button = [WarnAccessoryView altAccessoryView];
			[cell setAccessoryType:UITableViewCellAccessoryNone];
			[cell setAccessoryView:button];
		}
	} else {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	cell.detailTextLabel.text = BDVCFormattedValueForContent(node.content, node.stringValue);
	if ([name containsString:@"No."] || [name containsString:@"ID"]) {
		equipCellHighLegit(cell.detailTextLabel);
	}
	cell.detailTextLabel.textColor = [UIColor compatSecondaryLabelColor];
}

static BDVCBatteryInfoTableSnapshot *BDVCCopyBatteryInfoSnapshot(struct battery_info_section **batteryInfo) {
	BDVCBatteryInfoTableSnapshot *snapshot = [BDVCBatteryInfoTableSnapshot new];
	NSMutableArray<BDVCBatteryInfoSectionSnapshot *> *sections = [NSMutableArray array];

	battery_info_read_lock();
	snapshot->gauge = gGauge;
	snapshot->timeToEmpty = 0;
	for (struct battery_info_section *sect = batteryInfo ? *batteryInfo : NULL; sect; sect = sect->next) {
		BDVCBatteryInfoSectionSnapshot *sectionSnapshot = [BDVCBatteryInfoSectionSnapshot new];
		sectionSnapshot.title = BDVCStringFromUTF8(sect->data[0].name);
		sectionSnapshot.footer = BDVCStringFromUTF8(sect->data[0].desc);
		sectionSnapshot.customIdentifier = sect->context ? sect->context->custom_identifier : 0;

		NSMutableArray<BDVCBatteryInfoNodeSnapshot *> *rows = [NSMutableArray array];
		for (struct battery_info_node *i = sect->data + 1; i->name; i++) {
			if ((i->content & BIN_DETAILS_SHARED) == BIN_DETAILS_SHARED || (i->content && !((i->content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL))) {
				if ((i->content & 1) != 1 || (i->content & (1 << 5)) != (1 << 5)) {
					BDVCBatteryInfoNodeSnapshot *nodeSnapshot = [BDVCBatteryInfoNodeSnapshot new];
					nodeSnapshot.name = BDVCStringFromUTF8(i->name);
					nodeSnapshot.desc = BDVCStringFromUTF8(i->desc);
					nodeSnapshot.content = i->content;
					nodeSnapshot.sourceIndex = (NSUInteger)(i - sect->data);
					if (!((i->content & BIN_IS_SPECIAL) == BIN_IS_SPECIAL) && i->content) {
						nodeSnapshot.stringValue = BDVCStringFromUTF8(bi_node_get_string(i));
					}
					if (strcmp(i->name, "Time to Empty") == 0 && !((i->content & BIN_IS_FLOAT) == BIN_IS_FLOAT)) {
						snapshot->timeToEmpty = (int16_t)(i->content >> 16);
					}
					[rows addObject:nodeSnapshot];
				}
			}
		}
		sectionSnapshot.rows = rows;
		[sections addObject:sectionSnapshot];
	}
	battery_info_unlock();

	snapshot.sections = sections;
	return snapshot;
}

typedef enum {
	WARN_NONE,     // OK
	WARN_GENERAL,  // General warning
	WARN_UNUSUAL,  // Unusual value warning (including unusual exceeds)
	WARN_EXCEEDED, // Exceeded value warning
	WARN_EMPTYVAL, // Empty value warning
	WARN_MAX,      // max count of warn, should always be at bottom
} warn_condition_t;

/* TODO: Allow Warnings on other sections */
void equipWarningCondition_b(UITableViewCell *equippedCell, NSString *textLabel, warn_condition_t (^condition)(const char **warn)) {
	if (!equippedCell.textLabel.text) {
		DBGLOG(@"equipWarningCondition() called too early");
		return;
	}
	if (condition == nil)
		return;
	if (![equippedCell.textLabel.text isEqualToString:textLabel])
		return;

	UITableViewCellAccessoryType oldType  = [equippedCell accessoryType];
	const char                  *warnText = nil;
	warn_condition_t             number   = condition(&warnText);
	if (number == WARN_NONE) {
		[equippedCell setAccessoryType:oldType];
		[equippedCell setAccessoryView:nil];
		return; // Do nothing when condition is normal
	} else {
		WarnAccessoryView *button = [WarnAccessoryView warnAccessoryView];
		[equippedCell setAccessoryType:UITableViewCellAccessoryNone];
		[equippedCell setAccessoryView:button];
		equippedCell.detailTextLabel.textColor = [UIColor compatRedColor];

		if (warnText == NULL) {
			switch (number) {
			case WARN_EMPTYVAL:
				warnText = _C("No value returned from sensor, device should be checked by service technician.");
				break;
			case WARN_EXCEEDED:
				warnText = _C("Value exceeded the designed, device should be checked by service technician.");
				break;
			case WARN_UNUSUAL:
				warnText = _C("Unusual value, device should be checked by service technician.");
				break;
			case WARN_GENERAL:
			default:
				warnText = _C("Significant abnormal data, device should be checked by service technician.");
				break;
			}
		}
		button.warn_content = warnText;
		const char *title;
		switch (number) {
		case WARN_GENERAL:
			title = _C("Error Data");
			break;
		case WARN_UNUSUAL:
			title = _C("Unusual Data");
			break;
		case WARN_EXCEEDED:
			title = _C("Data Too Large");
			break;
		case WARN_EMPTYVAL:
			title = _C("Empty Data");
			break;
		default:
			title = _C("Wrong Data");
			break;
		}
		button.warn_title = title;
	}
}

@implementation BatteryDetailsViewController

- (BOOL)_canScheduleRefresh {
	return !refreshSuspended && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground;
}

- (NSString *)title {
	return _("Internal Battery");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Update refresh mode based on current preferences
	BSVCRefreshModeDidUpdate(self);
	[self updateTableView];
}

- (void)refreshModeDidUpdate {
	// Called when preferences change
	BSVCRefreshModeDidUpdate(self);
}

- (void)_startQueuedRefresh {
	if (![self _canScheduleRefresh]) {
		refreshPending = NO;
		[self.refreshControl endRefreshing];
		return;
	}

	if (refreshInFlight) {
		if (refreshInFlightGeneration != refreshGeneration) {
			refreshPending = YES;
		}
		return;
	}

	if (!self.refreshControl.refreshing) {
		[self.refreshControl beginRefreshing];
	}
	refreshInFlight = YES;
	NSUInteger generation = refreshGeneration;
	refreshInFlightGeneration = generation;
	dispatch_async(refreshQueue, ^{
		battery_info_update(self->batteryInfo);

		device_info_t adapter_info;
		is_charging(NULL, &adapter_info);

		hvc_menu_t *new_hvc_menu = NULL;
		size_t new_hvc_menu_size = 0;
		int8_t new_hvc_index = 0;
		bool new_hvc_soft = false;
		bool new_hvc_owned = false;

		/* Parse HVC Modes if have any */
		if (adapter_info.hvc_menu[27] != 0xFF) {
			new_hvc_menu = hvc_menu_parse(adapter_info.hvc_menu, &new_hvc_menu_size);
			new_hvc_index = adapter_info.hvc_index;
			new_hvc_soft = false;
			new_hvc_owned = false;
		} else {
			new_hvc_soft = true;
			/* Avoid IOKit includes, we only use this one */
			extern CFDictionaryRef IOPSCopyExternalPowerAdapterDetails(void);
			new_hvc_menu = convert_hvc(IOPSCopyExternalPowerAdapterDetails(), &new_hvc_menu_size, &new_hvc_index);
			new_hvc_owned = (new_hvc_menu != NULL);
		}
#if TARGET_OS_SIMULATOR
		/* Simulator builds cannot use IOPSCopyExternalPowerAdapterDetails() */
		/* We fake some hvc to test the UI instead */
		static hvc_menu_t fake_hvc[2];
		memset(fake_hvc, 0, sizeof(fake_hvc));
		fake_hvc[0].voltage = 114;
		fake_hvc[0].current = 514;
		fake_hvc[1].voltage = 1919;
		fake_hvc[1].current = 810;
		new_hvc_index = 1;
		new_hvc_menu = fake_hvc;
		new_hvc_menu_size = 2;
		new_hvc_owned = false;
#endif

		BDVCBatteryInfoTableSnapshot *newSnapshot = BDVCCopyBatteryInfoSnapshot(self->batteryInfo);
		dispatch_async(dispatch_get_main_queue(), ^{
			self->refreshInFlight = NO;
			if (generation != self->refreshGeneration || ![self _canScheduleRefresh]) {
				BOOL shouldRestart = self->refreshPending && [self _canScheduleRefresh] &&
					!(self.tableView.dragging || self.tableView.decelerating || self.tableView.tracking);
				self->refreshPending = NO;
				if (new_hvc_owned && new_hvc_menu) {
					free(new_hvc_menu);
				}
				[self.refreshControl endRefreshing];
				if (shouldRestart) {
					[self _startQueuedRefresh];
				}
				return;
			}

			self->batteryInfoSnapshot = newSnapshot;

			if (self->hvc_menu_owned && self->hvc_menu && self->hvc_menu != new_hvc_menu) {
				free(self->hvc_menu);
			}
			self->hvc_menu = new_hvc_menu;
			self->hvc_menu_size = new_hvc_menu_size;
			self->hvc_index = new_hvc_index;
			self->hvc_soft = new_hvc_soft;
			self->hvc_menu_owned = new_hvc_owned;

			if ([self isViewLoaded] && self.view.window) {
				[self.tableView reloadData];
			}
			[self.refreshControl endRefreshing];

			if (self->refreshPending) {
				if (!(self.tableView.dragging || self.tableView.decelerating || self.tableView.tracking)) {
					self->refreshPending = NO;
					[self _startQueuedRefresh];
				}
			}
		});
	});
}

- (void)batteryStatusDidUpdate:(NSDictionary *)info {
	// Check refresh preferences - only update if in auto mode (0) or manual refresh
	float interval = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_BI_INTERVAL];
	if (interval == -1.0f) {
		// Never mode - don't update automatically
		return;
	}
	
	// Only update in auto mode - in timer mode, the timer handles updates directly
	if (interval == 0.0f) {
		// TODO: reimplement IOKit method to update battery info
		DBGLOG(@"BDVC: batteryStatusDidUpdate");
		[self updateTableView];
	}
#if 0
	BOOL charging = [info[@"AppleRawExternalConnected"] boolValue];
	if(charging != last_charging) {
		last_charging = charging;
		[self updateTableView];
		return;
	}
	battery_info_update_iokit_with_data(batteryInfoStruct, (__bridge CFDictionaryRef)info, 1);
	[self.tableView reloadData];
	// DO NOT CALL updateTableView
#endif
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
	refreshSuspended = YES;
	refreshPending = NO;
	refreshGeneration++;
	if (!refreshInFlight) {
		[self.refreshControl endRefreshing];
	}
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
	refreshSuspended = NO;
	refreshGeneration++;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	UIRefreshControl *puller = [[UIRefreshControl alloc] init];
	[puller addTarget:self action:@selector(updateTableView) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = puller;

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[center addObserver:self selector:@selector(applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

	// FIXME: use preferred_language() for "Copy"
	[[UIMenuController sharedMenuController] update];

	[self.tableView registerClass:[SegmentedHVCViewCell class] forCellReuseIdentifier:@"HVC"];
	[self.tableView registerClass:[SegmentedFlagViewCell class] forCellReuseIdentifier:@"FLAGS"];
	[self.tableView registerClass:[MultilineViewCell class] forCellReuseIdentifier:@"bdvc:addt"];
	self.tableView.estimatedRowHeight = 100;
	self.tableView.rowHeight          = UITableViewAutomaticDimension;
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	return action == @selector(copy:);
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	if (action == @selector(copy:)) {
		UIPasteboard    *pasteboard;
		NSString        *pending;
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		pending               = cell.detailTextLabel.text;

		pasteboard = [UIPasteboard generalPasteboard];
		[pasteboard setString:pending];

		show_alert(_C("Copied!"), [pending UTF8String], L_OK);
	}
}

- (void)showAdvanced {
	[self.navigationController pushViewController:[FullSMCViewController new] animated:1];
}

- (instancetype)initWithBatteryInfo:(struct battery_info_section **)bi {
	if (@available(iOS 13.0, *)) {
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	} else {
		self = [super initWithStyle:UITableViewStyleGrouped];
	}

	self.tableView.allowsSelection = YES;
	refreshSuspended = [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
	refreshGeneration = 0;
	refreshInFlightGeneration = 0;
	batteryInfo = bi;
	batteryInfoSnapshot = BDVCCopyBatteryInfoSnapshot(bi);
	refreshQueue = dispatch_queue_create("com.torrekie.Battman.BDVCRefresh", DISPATCH_QUEUE_SERIAL);
	refreshInFlight = NO;
	refreshPending = NO;
	hvc_menu_owned = false;
	hvc_menu = NULL;
	hvc_menu_size = 0;
	hvc_index = -1;
	hvc_soft = false;
	if (!hasSMC)
		return self;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_("Advanced") style:UIBarButtonItemStylePlain target:self action:@selector(showAdvanced)];

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (hvc_menu_owned && hvc_menu) {
		free(hvc_menu);
		hvc_menu = NULL;
	}
}

- (void)updateTableView {
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateTableView];
		});
		return;
	}

	DBGLOG(@"BDVC: updateTableView");
	if (![self _canScheduleRefresh]) {
		refreshPending = NO;
		[self.refreshControl endRefreshing];
		return;
	}

	if (self.tableView.dragging || self.tableView.decelerating || self.tableView.tracking) {
		refreshPending = YES;
		return;
	}
	[self _startQueuedRefresh];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	if (refreshPending && !refreshInFlight) {
		refreshPending = NO;
		[self _startQueuedRefresh];
	}
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate && refreshPending && !refreshInFlight) {
		refreshPending = NO;
		[self _startQueuedRefresh];
	}
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

	//NSArray         *target_desc;
	NSString        *titleLabel;
	if ([cell respondsToSelector:@selector(titleLabel)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		UILabel *title = [cell performSelector:@selector(titleLabel)];
#pragma clang diagnostic pop

		if ([title isKindOfClass:[UILabel class]]) {
			titleLabel = title.text;
		}
	} else {
		titleLabel = cell.textLabel.text;
	}

	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	NSString *desc = nil;
	if (indexPath.section >= 0 && (NSUInteger)indexPath.section < snapshot.sections.count) {
		BDVCBatteryInfoSectionSnapshot *section = snapshot.sections[(NSUInteger)indexPath.section];
		if (indexPath.row >= 0 && (NSUInteger)indexPath.row < section.rows.count) {
			desc = section.rows[(NSUInteger)indexPath.row].desc;
		}
	}

	show_alert([titleLabel UTF8String], desc ? _C(desc.UTF8String) : "", L_OK);
	return;
	// TODO: Implement this
#if 0
    NSUInteger index = [target_desc indexOfObject:cell.textLabel.text];
    if (index != NSNotFound) {
        /* Special case: External */
        if ([cell.textLabel.text isEqualToString:_("Type")]) {
            NSString *finalstr = [target_desc objectAtIndex:(index + 1)];
            NSString *explaination_Ext = ((adapter_family & 0x20000) && (adapter_family & 0x7)) ? [NSString stringWithFormat:@"\n\n%@", _("\"External Power\" indicator may suggest that the connected adapter is a wireless charger. Most information may not be displayed because wireless chargers are handled differently by the hardware.")] : @"";
            show_alert([cell.textLabel.text UTF8String], [[NSString stringWithFormat:@"%@%@", finalstr, explaination_Ext] UTF8String], L_OK);
        } else {
            show_alert([cell.textLabel.text UTF8String], [[target_desc objectAtIndex:(index + 1)] UTF8String], L_OK);
        }
    }
    DBGLOG(@"Accessory Pressed, %@", cell.textLabel.text);
#endif
}

- (void)altAccTapped:(UIButton *)button {
	UIView          *view = button;
	UITableViewCell *cell;

	UITableView     *tv;
	NSIndexPath     *ip;
	while (view && ![view isKindOfClass:[UITableViewCell class]]) {
		view = [view superview];
	}
	if (view) {
		cell       = (UITableViewCell *)view;
		UIView *tb = view;
		while (tb && ![tb isKindOfClass:[UITableView class]]) {
			tb = [tb superview];
		}
		if (tb) {
			tv = (UITableView *)tb;
			ip = [tv indexPathForCell:cell];
			return [self tableView:tv accessoryButtonTappedForRowWithIndexPath:ip];
		}
	}
	DBGLOG(@"altAccTapped: Something goes wrong! view: %@, cell: %@, table: %@", view, cell, tv);
}

- (NSString *)tableView:(id)tv titleForHeaderInSection:(NSInteger)section {
	// if (batteryInfo[section][-1].content & (1 << 5))
	//     return nil;
	//  Doesn't matter, it will be changed by willDisplayHeaderView
	return @"This is a Title yeah";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	NSString *title = @"";
	if (section >= 0 && (NSUInteger)section < snapshot.sections.count) {
		NSString *rawTitle = snapshot.sections[(NSUInteger)section].title;
		if (rawTitle) {
			title = _(rawTitle.UTF8String);
		}
	}
	header.textLabel.text = title;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	if (section < 0 || (NSUInteger)section >= snapshot.sections.count) {
		return nil;
	}
	NSString *footer = snapshot.sections[(NSUInteger)section].footer;
	if (!footer) {
		return nil;
	}
	return _(footer.UTF8String);
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	if (section < 0 || (NSUInteger)section >= snapshot.sections.count) {
		return 0;
	}
	return snapshot.sections[(NSUInteger)section].rows.count;
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return batteryInfoSnapshot.sections.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	NSString *ident      = @"bdvc:sect0";
	id        cell_class = [ScrollableDetailCell class];
	if (ip.section != 0) {
		ident      = @"bdvc:addt";
		cell_class = [MultilineViewCell class];
	}
	UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:ident];
	if (cell) {
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessoryView = nil;
		cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	} else {
		cell = [[cell_class alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:ident];
	}
	
	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	if (ip.section < 0 || (NSUInteger)ip.section >= snapshot.sections.count) {
		return cell;
	}
	BDVCBatteryInfoSectionSnapshot *sectionSnapshot = snapshot.sections[(NSUInteger)ip.section];
	if (ip.row < 0 || (NSUInteger)ip.row >= sectionSnapshot.rows.count) {
		return cell;
	}
	BDVCBatteryInfoNodeSnapshot *pending_bi = sectionSnapshot.rows[(NSUInteger)ip.row];

	/* Flags special handler */
	if ([pending_bi.name isEqualToString:@"Flags"]) {
		SegmentedFlagViewCell *cellf = [tv dequeueReusableCellWithIdentifier:@"FLAGS"];
		if (!cellf)
			cellf = [[SegmentedFlagViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"FLAGS"];

		NSString *name = pending_bi.name ?: @"";
		NSString *detail = BDVCFormattedValueForContent(pending_bi.content, pending_bi.stringValue);
		cellf.textLabel.text       = _(name.UTF8String);
		cellf.titleLabel.text      = _(name.UTF8String);
		cellf.detailTextLabel.text = detail.length ? _(detail.UTF8String) : @"";
		[cellf selectByFlags:snapshot->gauge.Flags];
		if (strlen(snapshot->gauge.DeviceName)) {
			[cellf setBitSetByModel:[NSString stringWithFormat:@"%s", snapshot->gauge.DeviceName]];
		} else {
			[cellf setBitSetByTargetName];
		}
		return cellf;
	}

#pragma mark - Warn Conditions
	BDVCEquipDetailCellWithSnapshot(cell, pending_bi);
	
	// Workaround for too-long texts in section 0
//	if (ip.section == 0 && cell.detailTextLabel.text.length > 25) {
//		cell.detailTextLabel.numberOfLines = 0;
//		cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
//	}
	/* Warning conditions - Only evaluate for specific cells to reduce overhead during scrolling */
	if (sectionSnapshot.customIdentifier == BI_GAS_GAUGE_SECTION_ID) {
		NSString *cellLabel = cell.textLabel.text;
		gas_gauge_t gauge = snapshot->gauge;
		uint16_t remain_cap = gauge.RemainingCapacity;
		uint16_t full_cap = gauge.FullChargeCapacity;
		
		// Only call warning condition check for cells that actually need it
		if ([cellLabel isEqualToString:_("Remaining Capacity")]) {
			equipWarningCondition_b(cell, _("Remaining Capacity"), ^warn_condition_t(const char **str) {
				warn_condition_t code = WARN_NONE;
				if (remain_cap > full_cap) {
					code = WARN_UNUSUAL;
					static char errmsg[256];
					// some Shenzhen battries is spoofing this data to affect internal battery health calculations
					// But they still had to report a real SoC so that indicating actual conditions.
					sprintf(errmsg, "%s\n%s: %ld", _C("Unusual Remaining Capacity, a non-genuine battery component may be in use."), _C("Estimated Remaining"), lrintf((float)full_cap * gauge.StateOfCharge / 100.0f));
					*str = errmsg;
				} else if ((gauge.TrueRemainingCapacity != 0) && gauge.RemainingCapacity > (gauge.TrueRemainingCapacity + 10)) {
					// Battery is lying
					// TrueRemainingCapacity is calculated by device, not GGIC
					// So the diff would not exceed 1 normally, we generously allowing 10 here
					code = WARN_UNUSUAL;
					*str = _C("Unusual Remaining Capacity, a non-genuine battery component may be in use.");
				} else if (remain_cap == 0) {
					code = WARN_EMPTYVAL;
					*str = _C("Remaining Capacity not detected.");
				}
				return code;
			});
		} else if ([cellLabel isEqualToString:_("Cycle Count")]) {
			equipWarningCondition_b(cell, _("Cycle Count"), ^warn_condition_t(const char **str) {
				warn_condition_t code = WARN_NONE;
				int              count, design;
				count  = gauge.CycleCount;
				design = gauge.DesignCycleCount;

				if (gauge.DesignCycleCount == 0) {
					// according to https://www.apple.com/batteries/service-and-recycling
					// Pre-iPhone15,3: 500, otherwise 1000
					// Watch*,* iPad*,*: 1000
					// iPod*,*: 400
					// MacBook**,*: 1000
					// AppleTV/Watch/AudioAccessory has no battery so ignored
					size_t size = 0;
					char   machine[256];
					// Do not use uname()
					if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0) {
						DBGLOG(@"sysctlbyname(hw.machine) failed");
						return code;
					}
					if (sysctlbyname("hw.machine", &machine, &size, NULL, 0) != 0) {
						DBGLOG(@"sysctlbyname(&machine) failed");
						return code;
					}
					if (match_regex(machine,
					        "^(iPhone|iPad|iPod|MacBook.*)[0-9]+,[0-9]+$")) {
						if (strncmp(machine, "iPhone", 6) == 0) {
							int major = 0, minor = 0;
							if (sscanf(machine + 6, "%d,%d", &major, &minor) != 2) {
								DBGLOG(@"Unexpected iPhone model: %s", machine);
								return code;
							}
							if (major < 15 || (major == 15 && minor < 4)) {
								design = 500;
							} else {
								design = 1000;
							}
						} else if (strncmp(machine, "iPad", 4) || strncmp(machine, "Watch", 5) || strncmp(machine, "MacBook", 7))
							design = 1000;
						else if (strncmp(machine, "iPod", 4))
							design = 400;
					}
					if (design == 0)
						return code;
				}
				if (count > design) {
					code = WARN_EXCEEDED;
					*str = _C("Cycle Count exceeded designed cycle count, consider replacing with a genuine battery.");
				}
				return code;
			});
		} else if ([cellLabel isEqualToString:_("Time to Empty")]) {
			equipWarningCondition_b(cell, _("Time to Empty"), ^warn_condition_t(const char **str) {
				warn_condition_t code = WARN_NONE;
				int              tte = snapshot->timeToEmpty ?: gauge.TimeToEmpty;
				/* The most ideal TTE is TTE (Hour) = Capacity (mAh) / Current (mA),
				 * some user reported their non-genuine battries
				 * reporting a significant huge number of TTE */

				/* Battery charging, skip */
				if (gauge.AverageCurrent >= 0)
					return code;

				int ideal = ((int)remain_cap / abs(gauge.AverageCurrent)) * 60;
				/* Normally, TI's GG IC would not emulate its TTE bigger than ideal */
				/* for ensurence, we check if TTE is bigger than 1.5*ideal */
				if (tte > (ideal * 1.5)) {
					code = WARN_UNUSUAL;
					*str = _C("Unusual Time to Empty, a non-genuine battery component may be in use.");
				}
				return code;
			});
		} else if ([cellLabel isEqualToString:_("Depth of Discharge")]) {
			equipWarningCondition_b(cell, _("Depth of Discharge"), ^warn_condition_t(const char **str) {
				warn_condition_t code = WARN_NONE;
				/* Non-genuine batteries are likely spoofing some unremarkable data */
				/* DOD0 is not going to bigger than Qmax normally, but sometimes it do
				 * exceeds when discharging/charging with adapter attached */
				if (gauge.DOD0 > (gauge.Qmax * 3)) {
					code = WARN_UNUSUAL;
					*str = _C("Unusual Depth of Discharge, a non-genuine battery component may be in use.");
				}
				return code;
			});
		}
	}

	WarnAccessoryView *button = (WarnAccessoryView *)[cell accessoryView];
	if (button != nil && [button isKindOfClass:[WarnAccessoryView class]]) {
		if (button.isWarn) {
			[button addTarget:self action:@selector(warnTapped:) forControlEvents:UIControlEventTouchUpInside];
		} else {
			[button addTarget:self action:@selector(altAccTapped:) forControlEvents:UIControlEventTouchUpInside];
		}
	}
	/* TODO: record 1st-read capacity data in defaults in order to observe battery problems */
	/* HVC Mode special handler */
	if ([pending_bi.name isEqualToString:@"HVC Mode"]) {
		// Use cached HVC data instead of fetching during cell configuration
		// This prevents blocking the main thread during scrolling
		
		/* Only use SegmentedHVCViewCell when HVC exists */
		if (hvc_menu != NULL && hvc_menu_size != 0) {
			SegmentedHVCViewCell *cell_seg = [tv dequeueReusableCellWithIdentifier:@"HVC"];
			if (!cell_seg)
				cell_seg = [[SegmentedHVCViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"HVC"];
			if (@available(iOS 13.0, *)) {
				cell_seg.accessoryType = UITableViewCellAccessoryDetailButton;
			} else {
				WarnAccessoryView *button = [WarnAccessoryView altAccessoryView];
				[cell setAccessoryType:UITableViewCellAccessoryNone];
				[cell setAccessoryView:button];
				[button addTarget:self action:@selector(altAccTapped:) forControlEvents:UIControlEventTouchUpInside];
			}

			cell_seg.textLabel.text  = cell.textLabel.text; // For Accessory selection
			cell_seg.titleLabel.text = cell.textLabel.text;
			[cell_seg.segmentedControl addTarget:self action:@selector(hvcSegmentSelected:) forControlEvents:UIControlEventValueChanged];

			/* We have kept one sample seg to keep UI existence */
			// [cell_seg.segmentedControl setTitle:@"0" forSegmentAtIndex:0];
			[cell_seg.segmentedControl removeAllSegments];
			for (int i = 0; i < hvc_menu_size; i++) {
				[cell_seg.segmentedControl insertSegmentWithTitle:[NSString stringWithFormat:@"%d", i] atIndex:i animated:YES];
			}

			/* Content */
				if (!hvc_soft && (hvc_index > hvc_menu_size)) {
					cell_seg.detailTextLabel.text    = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Not HVC")];
					cell_seg.subTitleLabel.text  = @" ";
				cell_seg.subDetailLabel.text = @" ";
			} else if (hvc_soft == true) {
				cell_seg.detailTextLabel.text = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Software Controlled")];
				[cell_seg.segmentedControl setSelectedSegmentIndex:hvc_index];
				/* Why its not refreshing label after setSelectedSegmentIndex? */
				cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].voltage, L_MV];
				cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].current, L_MA];
			} else if (hvc_index == -1) {
				cell_seg.detailTextLabel.text    = [NSString stringWithFormat:@"%d (%@)", hvc_index, _("Unavailable")];
				cell_seg.subTitleLabel.text  = @" ";
				cell_seg.subDetailLabel.text = @" ";
			} else {
				cell_seg.detailTextLabel.text = [NSString stringWithFormat:@"%d", hvc_index];
				[cell_seg.segmentedControl setSelectedSegmentIndex:hvc_index];
				/* Why its not refreshing label after setSelectedSegmentIndex? */
				cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].voltage, L_MV];
					cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[hvc_index].current, L_MA];
				}

				return cell_seg;
			} else {
				cell.detailTextLabel.text = _("None");
			}
		}
		//        [cell layoutIfNeeded];
	return cell;
}

- (void)hvcSegmentSelected:(UISegmentedControl *)segment {
	UIView *view = segment;
	while (view && ![view isKindOfClass:[SegmentedHVCViewCell class]]) {
		view = [view superview];
	}
	if (view) {
		SegmentedHVCViewCell *cell_seg  = (SegmentedHVCViewCell *)view;
		// Now update the cell's title
		cell_seg.subTitleLabel.text  = [NSString stringWithFormat:@"%d %s", hvc_menu[segment.selectedSegmentIndex].voltage, L_MV];
		cell_seg.subDetailLabel.text = [NSString stringWithFormat:@"%d %s", hvc_menu[segment.selectedSegmentIndex].current, L_MA];
		return;
	}

	DBGLOG(@"FIXME: hvcSegmentSelected without cell view!");
}

- (void)warnTapped:(WarnAccessoryView *)button {
	show_alert(button.warn_title, button.warn_content, L_OK);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	BDVCBatteryInfoTableSnapshot *snapshot = batteryInfoSnapshot;
	if (indexPath.section < 0 || (NSUInteger)indexPath.section >= snapshot.sections.count) {
		return;
	}
	BDVCBatteryInfoSectionSnapshot *sectionSnapshot = snapshot.sections[(NSUInteger)indexPath.section];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= sectionSnapshot.rows.count) {
		return;
	}
	BDVCBatteryInfoNodeSnapshot *selectedNode = sectionSnapshot.rows[(NSUInteger)indexPath.row];

	battery_info_write_lock();
	struct battery_info_section *bi_section = batteryInfo ? *batteryInfo : NULL;
	for (NSInteger section = 0; bi_section && section < indexPath.section; section++) {
		bi_section = bi_section->next;
	}
	if (!bi_section) {
		battery_info_unlock();
		return;
	}
	struct battery_info_node    *pending_bi = bi_section->data;
	for (NSUInteger row = 0; pending_bi->name && row < selectedNode.sourceIndex; row++) {
		pending_bi++;
	}
	if (!pending_bi->name) {
		battery_info_unlock();
		return;
	}
	if(!(pending_bi->content&BIN_HAS_SUBCELLS)) {
		battery_info_unlock();
		return;
	}
	int rows=0;
	for(struct battery_info_node *node=pending_bi+1;node->name&&(node->content&BIN_IS_SUBCELL);node++) {
		node->content^=(1<<5);
		rows++;
	}
	if(!rows) {
		battery_info_unlock();
		return;
	}
	battery_info_unlock();
	batteryInfoSnapshot = BDVCCopyBatteryInfoSnapshot(batteryInfo);
	[tableView reloadData];
}

@end
