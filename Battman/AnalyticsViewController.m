//
//  AnalyticsViewController.m
//  Battman
//

#import "common.h"
#import "AnalyticsViewController.h"

UIImage *imageForSFProGlyph(NSString *glyph, NSString *fontName, CGFloat fontSize, UIColor *tintColor);

@implementation AnalyticsViewController

- (NSString *)title {
	return _("Analytics");
}

- (instancetype)init {
	UITabBarItem *tabbarItem = [UITabBarItem new];
	tabbarItem.title = _("Analytics");
	if (@available(iOS 13.0, *)) {
		tabbarItem.image = [UIImage systemImageNamed:@"chart.bar.xasis"]; // I would prefer chart.bar.xaxis but that was not something iOS 14
		if (tabbarItem.image == nil)
			tabbarItem.image = [UIImage systemImageNamed:@"chart.pie.fill"];
	}
	if (tabbarItem.image == nil) {
		// U+1008C9 chart.bar.xaxis
		tabbarItem.image = imageForSFProGlyph(@"􀣉", @SFPRO, 22, [UIColor grayColor]);
	}
	tabbarItem.tag = 0;
	self.tabBarItem = tabbarItem;

	if (@available(iOS 13.0, *))
		return [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self setupEmptyStateView];
}

- (void)setupEmptyStateView {
	UILabel *emptyLabel = [[UILabel alloc] init];
	emptyLabel.text = _("Not yet implemented");
	emptyLabel.textAlignment = NSTextAlignmentCenter;
	emptyLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightMedium];
	if (@available(iOS 13.0, *)) {
		emptyLabel.textColor = [UIColor secondaryLabelColor];
	} else {
		emptyLabel.textColor = [UIColor grayColor];
	}
	emptyLabel.numberOfLines = 0;

	self.tableView.backgroundView = emptyLabel;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 0;
}

@end

