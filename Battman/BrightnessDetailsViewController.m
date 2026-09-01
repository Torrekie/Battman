//
//  BrightnessDetailsViewController.m
//  Battman
//
//  Created by Torrekie on 2025/10/15.
//

#import "ObjCExt/UIColor+compat.h"

#import "common.h"
#import "intlextern.h"
#import <CoreText/CoreText.h>
#import "brightness/libbrightness.h"
#import "hw/IOMFB_interaction.h"
#import "EXTERNAL_HEADERS/CADisplay.h"
#import "BrightnessDetailsViewController.h"
#import "BrightnessCardCell.h"
#import "VirtBriCardCell.h"
#import "WarnAccessoryView.h"
#import "BrightnessAdvancedViewController.h"
#import "ScrollableDetailCell.h"
#include <math.h>

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
@property (nonatomic, strong) UITableViewCell *nitsControlCell;
@property (nonatomic, strong) UILabel *nitsControlValueLabel;
@property (nonatomic, strong) UILabel *nitsControlRangeLabel;
@property (nonatomic, strong) UISlider *nitsControlSlider;
@property (nonatomic, assign) BOOL nitsControlTracking;

@end

#import <QuartzCore/QuartzCore.h>

typedef enum {
	B_SECT_BASIC,
	B_SECT_LIMITS,
	B_SECT_CONTROL,
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
	B_ROW_CONTROL_NITS,
	B_ROW_CONTROL_COUNT,
} BrightnessRowControl;

typedef enum {
	B_ROW_SPECS_BACKEND,
	B_ROW_SPECS_PANEL_ID,
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
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_("Advanced") style:UIBarButtonItemStylePlain target:self action:@selector(showAdvanced)];
	// Allow selection for long-press copy menu
	self.tableView.allowsSelection = YES;
}

- (void)showAdvanced {
	[self.navigationController pushViewController:[BrightnessAdvancedViewController new] animated:YES];
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
	if (self.nitsControlCell)
		[self _configureNitsControlCell];
}

- (UITableViewCell *)_newNitsControlCell {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;

	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	titleLabel.text = _("Manual High Brightness");
	[cell.contentView addSubview:titleLabel];

	UILabel *valueLabel = [[UILabel alloc] init];
	valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
	valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
	valueLabel.textAlignment = NSTextAlignmentRight;
	[cell.contentView addSubview:valueLabel];

	UISlider *slider = [[UISlider alloc] init];
	slider.translatesAutoresizingMaskIntoConstraints = NO;
	slider.continuous = YES;
	slider.accessibilityLabel = _("Manual brightness in nits");
	[slider addTarget:self action:@selector(_nitsSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(_nitsSliderChanged:) forControlEvents:UIControlEventValueChanged];
	[slider addTarget:self action:@selector(_nitsSliderCommitted:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
	[slider addTarget:self action:@selector(_nitsSliderCancelled:) forControlEvents:UIControlEventTouchCancel];
	[cell.contentView addSubview:slider];

	UILabel *rangeLabel = [[UILabel alloc] init];
	rangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
	rangeLabel.font = [UIFont systemFontOfSize:12];
	rangeLabel.textColor = [UIColor compatSecondaryLabelColor];
	rangeLabel.numberOfLines = 0;
	[cell.contentView addSubview:rangeLabel];

	UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[titleLabel.topAnchor constraintEqualToAnchor:margins.topAnchor],
		[titleLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:valueLabel.leadingAnchor constant:-12],
		[valueLabel.firstBaselineAnchor constraintEqualToAnchor:titleLabel.firstBaselineAnchor],
		[valueLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[slider.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
		[slider.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[slider.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[rangeLabel.topAnchor constraintEqualToAnchor:slider.bottomAnchor constant:4],
		[rangeLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[rangeLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[rangeLabel.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
	]];

	self.nitsControlCell = cell;
	self.nitsControlValueLabel = valueLabel;
	self.nitsControlRangeLabel = rangeLabel;
	self.nitsControlSlider = slider;
	[self _configureNitsControlCell];
	return cell;
}

- (void)_configureNitsControlCell {
	if (!self.nitsControlSlider)
		return;

	VirtualBrightnessLimits limits = self.cachedLimits;
	double minNits = limits.HardwareAccessibleMinNits;
	double maxNits = limits.HardwareAccessibleMaxNits;
	double sliderMaxNits = limits.UserAccessibleMaxNits;
	BOOL validRange = !is_simulator() && limits.ExtrabrightEDRSupported && minNits >= 0 && maxNits > minNits && maxNits > sliderMaxNits;

	self.nitsControlSlider.enabled = validRange;
	if (!validRange) {
		self.nitsControlValueLabel.text = _("Unavailable");
		self.nitsControlRangeLabel.text = _("This display does not report a manual high-brightness range.");
		self.nitsControlSlider.minimumValue = 0;
		self.nitsControlSlider.maximumValue = 1;
		self.nitsControlSlider.value = 0;
		self.nitsControlSlider.accessibilityValue = self.nitsControlValueLabel.text;
		return;
	}

	self.nitsControlSlider.minimumValue = minNits;
	self.nitsControlSlider.maximumValue = maxNits;
	double currentNits = self.cachedDisplayBrightness.Nits;
	if (currentNits <= 0)
		currentNits = self.cachedDisplayBrightness.NitsPhysical;
	currentNits = MIN(MAX(currentNits, minNits), maxNits);
	if (!self.nitsControlTracking)
		self.nitsControlSlider.value = currentNits;
	[self _updateNitsControlValue:self.nitsControlSlider.value];
	self.nitsControlRangeLabel.text = [NSString stringWithFormat:_("System slider max: %.0f nits · Hardware max: %.0f nits"), sliderMaxNits, maxNits];
	self.nitsControlSlider.accessibilityHint = _("Values above the system slider maximum use the display's high-brightness range.");
}

- (void)_updateNitsControlValue:(double)nits {
	double roundedNits = round(nits);
	self.nitsControlValueLabel.text = [NSString stringWithFormat:_("%.0f nits"), roundedNits];
	self.nitsControlSlider.accessibilityValue = self.nitsControlValueLabel.text;
}

- (void)_nitsSliderTouchDown:(UISlider *)slider {
	self.nitsControlTracking = YES;
}

- (void)_nitsSliderChanged:(UISlider *)slider {
	double roundedNits = round(slider.value);
	[self _updateNitsControlValue:roundedNits];
	set_display_brightness(false, roundedNits, !self.nitsControlTracking);
}

- (void)_nitsSliderCommitted:(UISlider *)slider {
	double roundedNits = round(slider.value);
	self.nitsControlTracking = NO;
	slider.value = roundedNits;
	[self _updateNitsControlValue:roundedNits];
	if (!set_display_brightness(false, roundedNits, true)) {
		show_alert(_C("Brightness Unavailable"), _C("The system brightness service could not apply this value."), L_OK);
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reloadBrightnessSection) object:nil];
	[self performSelector:@selector(_reloadBrightnessSection) withObject:nil afterDelay:0.2];
}

- (void)_nitsSliderCancelled:(UISlider *)slider {
	self.nitsControlTracking = NO;
	[self _reloadBrightnessSection];
}

- (void)_handlePullToRefresh:(UIRefreshControl *)refreshControl {
	[self _reloadBrightnessCaches];
	[self.tableView reloadData];
	[refreshControl endRefreshing];
}

- (void)_brightnessDidChange:(NSNotification *)notification {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_reloadBrightnessSection) object:nil];
	[self performSelector:@selector(_reloadBrightnessSection) withObject:nil afterDelay:0.2];
}

- (void)_reloadBrightnessSection {
	[self _reloadBrightnessCaches];
	NSIndexSet *sections = [NSIndexSet indexSetWithIndex:B_SECT_LIMITS];
	[self.tableView reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return B_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	BrightnessSect sect = (BrightnessSect)section;
	switch (sect) {
		case B_SECT_BASIC: return nil;
		case B_SECT_LIMITS: return nil;
		case B_SECT_CONTROL: return _("High Brightness Override");
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
		case B_SECT_CONTROL: return _("Brightness above the system slider maximum increases power use and heat. iOS may reduce it to protect the display.");
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
		case B_SECT_CONTROL: return B_ROW_CONTROL_COUNT;
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
		case B_SECT_CONTROL: {
			BrightnessRowControl row = (BrightnessRowControl)indexPath.row;
			switch (row) {
				case B_ROW_CONTROL_NITS:
					cell = self.nitsControlCell ?: [self _newNitsControlCell];
					[self _configureNitsControlCell];
					break;
				case B_ROW_CONTROL_COUNT: break;
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
					cell.detailTextLabel.text = self.dcpBacklightCached ? @"DCP" : _("Standard");
					break;
				case B_ROW_SPECS_PANEL_ID: {
					cell = (UITableViewCell *)[[ScrollableDetailCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuse];
					cell.textLabel.text = _("ID");
					BOOL possibly_malformed = NO;
					const char *panel_id = iomfb_primary_screen_panel_id();
					if (panel_id == NULL) {
						cell.detailTextLabel.text = is_simulator() ? _("Simulator") : _("Unknown");
						possibly_malformed = !is_simulator();
					} else {
						cell.detailTextLabel.text = [NSString stringWithUTF8String:panel_id];
						for (int i = 0; i < strlen(panel_id); i++) {
							if (!isalpha(panel_id[i]) && !isdigit(panel_id[i]) && !(panel_id[i] == '+')) {
								possibly_malformed = YES;
								break;
							}
						}
					}

					if (possibly_malformed) {
						WarnAccessoryView *button = [WarnAccessoryView warnAccessoryView];
						[cell setAccessoryType:UITableViewCellAccessoryNone];
						[cell setAccessoryView:button];
						[button addTarget:self action:@selector(warnForWeirdPanelID) forControlEvents:UIControlEventTouchUpInside];
						cell.detailTextLabel.textColor = [UIColor compatRedColor];
					}

					CTFontDescriptorRef desc = CTFontDescriptorCreateCopyWithFeature((__bridge CTFontDescriptorRef)cell.detailTextLabel.font.fontDescriptor, (__bridge CFNumberRef)@(kStylisticAlternativesType), (__bridge CFNumberRef)@(kStylisticAltSixOnSelector));
					CTFontRef font = CTFontCreateWithFontDescriptor(desc, cell.detailTextLabel.font.pointSize, NULL);
					[cell.detailTextLabel setFont:(__bridge UIFont *)font];
					if (desc) CFRelease(desc);
					if (font) CFRelease(font);

					break;
				}
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

	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewAutomaticDimension;
}

- (void)warnForWeirdPanelID {
	show_alert(_C("Unusual Panel ID"), _C("Current part might not be genuine."), L_OK);
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
	// Only enable copy menu for the "ID" row
	return (indexPath.section == B_SECT_SPECS && indexPath.row == B_ROW_SPECS_PANEL_ID);
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	// Only enable copy menu for the "ID" row
	if (indexPath.section == B_SECT_SPECS && indexPath.row == B_ROW_SPECS_PANEL_ID) {
		return action == @selector(copy:);
	}
	return NO;
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	if (action == @selector(copy:)) {
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		NSString *textToCopy = cell.detailTextLabel.text;
		
		if (textToCopy && textToCopy.length > 0) {
			UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
			[pasteboard setString:textToCopy];
			show_alert(_C("Copied!"), [textToCopy UTF8String], L_OK);
		}
	}
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
