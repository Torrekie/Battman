//
//  BrightnessInfoTableViewCell.m
//  Battman
//
//  Created by Torrekie on 2025/10/15.
//

#import "../common.h"
#import "../BattmanPrefs.h"
#import "../GradientHDRView.h"
#import "../GradientSDRView.h"
#import "BrightnessInfoTableViewCell.h"

#include "../brightness/libbrightness.h"

#import "../ObjCExt/UIScreen+Auto.h"
#import "../ObjCExt/CALayer+smoothCorners.h"

@interface BrightnessCellView ()
@property (nonatomic, strong) UIView *gradientView;
@property (nonatomic, strong) UIView *brightnessView;
@property (nonatomic, assign) CGFloat initialPercentage;
@property (nonatomic, assign) BOOL gradientSetupComplete;
@end

@implementation BrightnessCellView

- (instancetype)initWithFrame:(CGRect)frame percentage:(CGFloat)percentage {
	self = [super initWithFrame:frame];
	UIView *brightnessView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
	brightnessView.layer.cornerRadius = 30;
	[brightnessView.layer setSmoothCorners:YES];
	brightnessView.layer.masksToBounds = YES;

	self.brightnessView = brightnessView;
	self.initialPercentage = percentage;
	self.gradientSetupComplete = NO;
	
	// Defer expensive Metal setup to avoid blocking tab switch animation
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!self.gradientSetupComplete && self.window) {  // Only if still in window
			// Check if Metal is disabled by user config
			BOOL metalDisabled = ([BattmanPrefs.sharedPrefs integerForKey:@kBattmanPrefs_BRIGHT_UI_HDR] == 2);
			self.gradientView = [[(metalDisabled ? [GradientSDRView class] : [GradientHDRView class]) alloc] initWithFrame:self.brightnessView.bounds];
			self.gradientView.center = self.brightnessView.center;
			[self.brightnessView addSubview:self.gradientView];
			[(GradientHDRView *)self.gradientView setBrightness:self.initialPercentage animated:NO];
			self.gradientSetupComplete = YES;
		}
	});
	
	[self addSubview:brightnessView];
	return self;
}

- (void)updateBrightness:(CGFloat)percentage {
	// Update the stored value in case gradient isn't set up yet
	self.initialPercentage = percentage;
	
	if ([self.gradientView respondsToSelector:@selector(setBrightness:animated:)]) {
		int percentInt = (int)round(percentage);
		if ([self.gradientView isKindOfClass:[GradientHDRView class]]) {
			[(GradientHDRView *)self.gradientView setBrightness:percentInt animated:YES];
		} else if ([self.gradientView isKindOfClass:[GradientSDRView class]]) {
			[(GradientSDRView *)self.gradientView setBrightness:percentInt animated:YES];
		}
	}
	// If gradientView not set up yet, the deferred block will use the updated initialPercentage
}

@end

@implementation BrightnessInfoTableViewCell

- (void)setupCellUI {
	BrightnessCellView *brightnessCell = [[BrightnessCellView alloc] initWithFrame:CGRectMake(0, 0, 80, 80) percentage:0.0];
	brightnessCell.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:brightnessCell];
	[brightnessCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[brightnessCell.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:20].active = 1;
	[brightnessCell.heightAnchor constraintEqualToConstant:80].active = 1;
	[brightnessCell.widthAnchor constraintEqualToAnchor:brightnessCell.heightAnchor].active = 1;

	UILabel *brightnessLabel = [UILabel new];
	brightnessLabel.lineBreakMode = NSLineBreakByWordWrapping;
	brightnessLabel.numberOfLines = 0;
	[self.contentView addSubview:brightnessLabel];
	brightnessLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[brightnessLabel.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-20].active = 1;
	[brightnessLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[brightnessLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.8].active = 1;
	[brightnessLabel.leftAnchor constraintEqualToAnchor:brightnessCell.rightAnchor constant:20].active = 1;

	_brightnessCell = brightnessCell;
	_brightnessLabel = brightnessLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (instancetype)init {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BITVC-ri"];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (void)updateBrightnessInfo {
	float percent = 0;
	if (!is_simulator()) {
		// TODO: Get mac brightness using CoreDisplay
		DisplayBrightness brightness = display_brightness();
		percent = brightness.Brightness * 100.0f;
	}
	if (percent == 0)
		percent = UIScreen.autoScreen.brightness * 100.0f; // Fallback

	[self.brightnessCell updateBrightness:percent];
	
	NSString *finalText = [NSString stringWithFormat:@"%@: %.4g %%", _("Brightness"), percent];
	id displayConfiguration = nil;
	if ([UIScreen.autoScreen respondsToSelector:sel_registerName("displayConfiguration")])
		displayConfiguration = ((id (*)(id, SEL))objc_msgSend)(UIScreen.autoScreen, sel_registerName("displayConfiguration"));
	if (displayConfiguration) {
		CGFloat refreshRate = 0;
		if ([displayConfiguration respondsToSelector:sel_registerName("refreshRate")])
			refreshRate = ((CGFloat (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("refreshRate"));
		UIDisplayGamut colorGamut = UIDisplayGamutSRGB;
		if ([displayConfiguration respondsToSelector:sel_registerName("colorGamut")])
			colorGamut = ((UIDisplayGamut (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("colorGamut"));
		id currentMode = nil;
		if ([displayConfiguration respondsToSelector:sel_registerName("currentMode")])
			currentMode = ((id (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("currentMode"));
		CGSize pixelSize = CGSizeZero;
		if ([displayConfiguration respondsToSelector:sel_registerName("pixelSize")])
			pixelSize = ((CGSize (*)(id, SEL))objc_msgSend)(displayConfiguration, sel_registerName("pixelSize"));
		// don't use IOMFB when at this page, just use the simple one
		finalText = [finalText stringByAppendingFormat:@"\n%dHz %@ %dx%d", (int)floor(refreshRate), colorGamut ? @"P3" : @"sRGB", (int)pixelSize.width, (int)pixelSize.height];
	}

	self.brightnessLabel.text = finalText;
}

@end

