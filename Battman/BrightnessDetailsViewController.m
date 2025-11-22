//
//  BrightnessDetailsViewController.m
//  Battman
//
//  Created by Torrekie on 2025/10/15.
//

#import "common.h"
#import "brightness/libbrightness.h"
#import "hw/IOMFB_interaction.h"
#import "EXTERNAL_HEADERS/CADisplay.h"
#import "BrightnessDetailsViewController.h"
#import "BrightnessCardCell.h"
#import "VirtBriCardCell.h"

@interface BrightnessDetailsViewController ()
 
@property (nonatomic, assign) CGSize fbsPixelSize;
@property (nonatomic, assign) UIDisplayGamut fbsColorGamut;
@property (nonatomic, assign) BOOL nightShiftSupported;
@property (nonatomic, assign) BOOL trueToneSupported;
@property (nonatomic, assign) double cachedTemperature;
@property (nonatomic, assign) BOOL cachedUnknownTemperature;
@property (nonatomic, assign) VirtualBrightnessLimits cachedLimits;
@property (nonatomic, assign) DisplayBrightness cachedDisplayBrightness;
@property (nonatomic, assign) BOOL alsSupportedCached;
@property (nonatomic, assign) BOOL dcpBacklightCached;
@property (nonatomic, strong) CADisplay *cachedMainDisplay;

@end

#import <QuartzCore/QuartzCore.h>

typedef enum {
	B_SECT_BASIC,
	B_SECT_LIMITS,
	B_SECT_SPECS,
	B_SECT_COUNT,
} BrightnessSect;

typedef enum {
	B_ROW_BASIC_CARD,
	B_ROW_BASIC_COUNT,
} BrightnessRowBasic;

typedef enum {
	B_ROW_LIMITS_CARD,
	B_ROW_LIMITS_COUNT,
} BrightnessRowLimits;

typedef enum {
	B_ROW_SPECS_BACKEND,
	B_ROW_SPECS_ALS,
	B_ROW_SPECS_REFRESH_RATE,
	B_ROW_SPECS_BITDEPTH,
	B_ROW_SPECS_COUNT,
} BrightnessRowSpecs;

@implementation BrightnessDetailsViewController

- (NSString *)title {
	return _("Primary Screen");
}

- (instancetype)init {
	UITableViewStyle style = UITableViewStyleGrouped;
	if (@available(iOS 13.0, *))
		style = UITableViewStyleInsetGrouped;
	self = [super initWithStyle:style];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView registerClass:[BrightnessCardCell class] forCellReuseIdentifier:@"BRI_CARD"];
	[self.tableView registerClass:[VirtBriCardCell class] forCellReuseIdentifier:@"BRI_LIM"];
	UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
	[refreshControl addTarget:self action:@selector(_handlePullToRefresh:) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = refreshControl;
	[self _reloadBrightnessCaches];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_brightnessDidChange:) name:UIScreenBrightnessDidChangeNotification object:nil];
}

- (void)_reloadBrightnessCaches {
	id displayConfiguration = nil;
	if ([UIScreen.mainScreen respondsToSelector:sel_registerName("displayConfiguration")])
		displayConfiguration = ((id (*)(id, SEL))objc_msgSend)(UIScreen.mainScreen, sel_registerName("displayConfiguration"));
	self.fbsPixelSize = CGSizeZero;
	self.fbsColorGamut = UIDisplayGamutSRGB;
	if (displayConfiguration) {
		if ([displayConfiguration respondsToSelector:sel_registerName("colorGamut")])
			self.fbsColorGamut = ((UIDisplayGamut (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("colorGamut"));
		if ([displayConfiguration respondsToSelector:sel_registerName("pixelSize")])
			self.fbsPixelSize = ((CGSize (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("pixelSize"));
	}
	self.nightShiftSupported = blr_supported();
	self.trueToneSupported = adaption_supported();
	double temp = iomfb_primary_screen_temperature();
	self.cachedTemperature = temp;
	self.cachedUnknownTemperature = (temp == -1);
	if (!is_simulator()) {
		self.cachedLimits = brightness_limits();
		self.cachedDisplayBrightness = display_brightness();
	}
	self.dcpBacklightCached = dcp_backlight();
	self.alsSupportedCached = als_supported();
	self.cachedMainDisplay = CADisplay.mainDisplay;
}

- (void)_handlePullToRefresh:(UIRefreshControl *)refreshControl {
	[self _reloadBrightnessCaches];
	[self.tableView reloadData];
	[refreshControl endRefreshing];
}

- (void)_brightnessDidChange:(NSNotification *)notification {
	[self _reloadBrightnessCaches];
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return B_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	BrightnessSect sect = (BrightnessSect)section;
	switch (sect) {
		case B_SECT_BASIC: return nil;
		case B_SECT_LIMITS: return nil;
		case B_SECT_SPECS: return _("Specs (Basic)");
		case B_SECT_COUNT: break;
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	BrightnessSect sect = (BrightnessSect)section;
	switch (sect) {
		case B_SECT_BASIC: return nil;
		case B_SECT_LIMITS: return _("These limitations are typically determined by the hardware and returned by the Brightness system.");
		case B_SECT_SPECS: return _("These parameters are sourced from the system’s high-level graphics layer. Because the display is ultimately composed through CoreAnimation and backboardd before it reaches the screen hardware, the values shown here are estimates and may not precisely reflect the true behavior of the physical display.");
		case B_SECT_COUNT: break;
	}
	return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	BrightnessSect sect = (BrightnessSect)section;
	switch (sect) {
		case B_SECT_BASIC: return B_ROW_BASIC_COUNT;
		case B_SECT_LIMITS: return B_ROW_LIMITS_COUNT;
		case B_SECT_SPECS: return B_ROW_SPECS_COUNT;
		case B_SECT_COUNT: break;
	}
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = nil;
	BrightnessSect sect = (BrightnessSect)indexPath.section;
	NSString *reuse;
	reuse = [NSString stringWithFormat:@"BRI_BASIC_%ld_%ld", indexPath.section, indexPath.row];
	switch (sect) {
		case B_SECT_BASIC: {
			cell = [tableView dequeueReusableCellWithIdentifier:@"BRI_CARD"];
			BrightnessRowBasic row = (BrightnessRowBasic)indexPath.row;
			switch (row) {
				case B_ROW_BASIC_CARD: {
					BrightnessCardCell *card;
					if (!cell || ![cell isKindOfClass:[BrightnessCardCell class]]) {
						card = [[BrightnessCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BRI_CARD"];
						cell = (UITableViewCell *)card;
					} else {
						card = (BrightnessCardCell *)cell;
					}
					// FBS
					CGSize pixelSize = self.fbsPixelSize;
					UIDisplayGamut colorGamut = self.fbsColorGamut;
					card.resolutionText = [NSString stringWithFormat:@"%d x %d", (int)pixelSize.width, (int)pixelSize.height];
					card.displayGamut = (colorGamut == UIDisplayGamutP3) ? @"P3" : @"sRGB";
					card.isNightShiftSupported = self.nightShiftSupported;
					card.isTrueToneSupported = self.trueToneSupported;
					// FIXME: IOMFB temperature will NOT work if device not using DCP brightness
					double temp2 = self.cachedTemperature;
					if (self.cachedUnknownTemperature)
						card.unknownTemperature = YES;
					card.temperatureCelsius = temp2;
					break;
				}
				case B_ROW_BASIC_COUNT: break;
			}
			break;
		}
		case B_SECT_LIMITS: {
			BrightnessRowLimits row = (BrightnessRowLimits)indexPath.row;
			cell = [tableView dequeueReusableCellWithIdentifier:@"BRI_LIM"];
			switch (row) {
				case B_ROW_LIMITS_CARD: {
					// Simulator unsupported yet
					if (is_simulator()) {
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
						cell.textLabel.text = _("Brightness Limits (nits)");
						cell.detailTextLabel.text = _("Unsupported");
						break;
					}
					VirtBriCardCell *card;
					if (!cell || ![cell isKindOfClass:[VirtBriCardCell class]]) {
						card = [[VirtBriCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BRI_LIM"];
						cell = (UITableViewCell *)card;
					} else {
						card = (VirtBriCardCell *)cell;
					}
					VirtualBrightnessLimits limits = self.cachedLimits;
					DisplayBrightness bri = self.cachedDisplayBrightness;
					card.brightnessPercentage = bri.Brightness;
					card.currentNits = bri.Nits;
					card.currentNitsPhysical = bri.NitsPhysical;
					card.digitalDimmingSupported = limits.DigitalDimmingSupported;
					card.extrabrightEDRSupported = limits.ExtrabrightEDRSupported;
					card.hardwareAccessibleMaxNits = limits.HardwareAccessibleMaxNits;
					card.hardwareAccessibleMinNits = limits.HardwareAccessibleMinNits;
					card.minNitsAccessibleWithDigitalDimming = limits.MinNitsAccessibleWithDigitalDimming;
					card.userAccessibleMaxNits = limits.UserAccessibleMaxNits;
					break;
				}
				case B_ROW_LIMITS_COUNT: break;
			}
			break;
		}
		case B_SECT_SPECS: {
			BrightnessRowSpecs row = (BrightnessRowSpecs)indexPath.row;
			if (!cell)
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
			CADisplay *mainDisplay = self.cachedMainDisplay;
			switch (row) {
				case B_ROW_SPECS_BACKEND:
					cell.textLabel.text = _("Brightness Backend");
					cell.detailTextLabel.text = self.dcpBacklightCached ? @"DCP" : @"DFR";
					break;
				case B_ROW_SPECS_ALS:
					cell.textLabel.text = _("Ambient Light Sensor");
					cell.detailTextLabel.text = self.alsSupportedCached ? _("True") : _("False");
					break;
				case B_ROW_SPECS_REFRESH_RATE:
					cell.textLabel.text = _("Refresh Rate");
					/* This part has much confusions */
					cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f Hz", 1.0f / mainDisplay.refreshRate];
					break;
				case B_ROW_SPECS_BITDEPTH:
					cell.textLabel.text =_("Color Depth");
					cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu %@", mainDisplay.currentMode.bitDepth, _("Bits")];
					break;
				case B_ROW_SPECS_COUNT: break;
			}
			break;
		}
		case B_SECT_COUNT: break;
	}
	return cell;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
