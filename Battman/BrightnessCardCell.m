//
//  BrightnessCardCell.m
//  Battman
//
//  Created by Torrekie on 2025/11/15.
//

#import "ObjCExt/UIScreen+Auto.h"
#import "ObjCExt/UIColor+compat.h"
#import "ObjCExt/CALayer+smoothCorners.h"
#import "common.h"
#import "BrightnessCardCell.h"
#import "CGIconSet/NightShiftVectorIcon.h"
#import "CGIconSet/TrueToneVectorIcon.h"
#import "CGIconSet/IPhoneVectorIcon.h"
#import "CGIconSet/IPhoneD7VectorIcon.h"
#import "CGIconSet/IPhoneHomeButtonVectorIcon.h"
#import "CGIconSet/IPadVectorIcon.h"
#import "CGIconSet/IPadHomeButtonVectorIcon.h"
#import "CGIconSet/DesktopVectorIcon.h"

extern UIImage *imageForSFProGlyph(NSString *glyph, NSString *fontName, CGFloat fontSize, UIColor *tintColor);
extern UIImage *redrawUIImage(UIImage *image, UIColor *color, CGSize size);

@interface BrightnessCardCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *iconBackgroundView;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *resolutionLabel;
@property (nonatomic, strong) UILabel *gamutLabel;
@property (nonatomic, strong) UIView *nightShiftContainer;
@property (nonatomic, strong) UILabel *nightShiftLabel;
@property (nonatomic, strong) UIView *trueToneContainer;
@property (nonatomic, strong) UILabel *trueToneLabel;
@property (nonatomic, strong) UILabel *temperatureTitleLabel;
@property (nonatomic, strong) UILabel *temperatureValueLabel;

// Landscape labels
@property (nonatomic, strong) UILabel *resolutionTitleLabel;
@property (nonatomic, strong) UILabel *gamutTitleLabel;
@property (nonatomic, strong) UILabel *temperatureTitleLabelLandscape;

@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *portraitConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *landscapeConstraints;

@end

@implementation BrightnessCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		[self _configureView];
		[self _setupConstraints];
		[self _updateLayoutForOrientation];
	}
	return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if (self.traitCollection.verticalSizeClass != previousTraitCollection.verticalSizeClass ||
		self.traitCollection.horizontalSizeClass != previousTraitCollection.horizontalSizeClass) {
		[self _updateLayoutForOrientation];
	}

	if (@available(iOS 12.0, *)) {
		if (self.traitCollection.userInterfaceStyle != previousTraitCollection.userInterfaceStyle) {
			BOOL isLandscape = [self _isLandscapeLayout];
			[self _updateNightShiftLabelWithFontSize:isLandscape ? 14 : 15];
			[self _updateTrueToneLabelWithFontSize:isLandscape ? 14 : 15];
		}
	}
}

- (void)_configureView {
	//self.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	
	self.cardView = [[UIView alloc] init];
	self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
	self.cardView.backgroundColor = self.backgroundColor;
	self.cardView.layer.cornerRadius = 16;
	[self.cardView.layer setSmoothCorners:YES];
	self.cardView.layer.shadowColor = UIColor.blackColor.CGColor;
	self.cardView.layer.shadowOffset = CGSizeMake(0, 2);
	self.cardView.layer.shadowOpacity = 0.1;
	self.cardView.layer.shadowRadius = 8;
	[self.contentView addSubview:self.cardView];
	
	self.iconBackgroundView = [[UIView alloc] init];
	self.iconBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
	self.iconBackgroundView.backgroundColor = [UIColor tertiaryCompatFillColor];
	self.iconBackgroundView.layer.cornerRadius = 16;
	[self.iconBackgroundView.layer setSmoothCorners:YES];
	[self.cardView addSubview:self.iconBackgroundView];

	self.iconImageView = [[UIImageView alloc] init];
	self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
	self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
	self.iconImageView.tintColor = [UIColor compatGrayColor];
	CGImageRef baseCGImage = NULL;

	if (is_maccatalyst()) {
		baseCGImage = [DesktopVectorIcon DesktopCGImage];
	} else {
		if (is_ipad()) {
			if (has_homebutton())
				baseCGImage = [IPadHomeButtonVectorIcon IPadHomeButtonCGImage];
			else
				baseCGImage = [IPadVectorIcon IPadCGImage];
		} else {
			if (has_homebutton()) {
				baseCGImage = [IPhoneHomeButtonVectorIcon IPhoneHomeButtonCGImage];
			} else if (has_island_notch()) {
				baseCGImage = [IPhoneD7VectorIcon IPhoneD7CGImage];
			} else {
				baseCGImage = [IPhoneVectorIcon IPhoneCGImage];
			}
		}
	}

	if (baseCGImage) {
		UIImage *baseImage = [UIImage imageWithCGImage:baseCGImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
		CGSize intrinsicSize = baseImage.size;
		CGFloat maxSide = 32.0;
		CGFloat scale = maxSide / MAX(intrinsicSize.width, intrinsicSize.height);
		if (scale > 1.0)
			scale = 1.0;
		CGSize iconTargetSize = CGSizeMake(intrinsicSize.width * scale, intrinsicSize.height * scale);
		UIImage *tinted = redrawUIImage(baseImage, self.iconImageView.tintColor, iconTargetSize);
		self.iconImageView.image = tinted ?: baseImage;
	}
	[self.iconBackgroundView addSubview:self.iconImageView];
	
	self.resolutionLabel = [[UILabel alloc] init];
	self.resolutionLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.resolutionLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
	self.resolutionLabel.textColor = [UIColor compatLabelColor];
	[self.cardView addSubview:self.resolutionLabel];
	
	self.gamutLabel = [[UILabel alloc] init];
	self.gamutLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.gamutLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
	self.gamutLabel.textColor = [UIColor compatSecondaryLabelColor];
	[self.cardView addSubview:self.gamutLabel];
	
	self.nightShiftContainer = [[UIView alloc] init];
	self.nightShiftContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.nightShiftContainer.layer.cornerRadius = 8;
	[self.nightShiftContainer.layer setSmoothCorners:YES];
	self.nightShiftContainer.layer.borderWidth = 1.5;
	[self.cardView addSubview:self.nightShiftContainer];
	
	self.nightShiftLabel = [[UILabel alloc] init];
	self.nightShiftLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.nightShiftLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
	[self.nightShiftContainer addSubview:self.nightShiftLabel];
	
	self.trueToneContainer = [[UIView alloc] init];
	self.trueToneContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.trueToneContainer.layer.cornerRadius = 8;
	[self.trueToneContainer.layer setSmoothCorners:YES];
	self.trueToneContainer.layer.borderWidth = 1.5;
	[self.cardView addSubview:self.trueToneContainer];
	
	self.trueToneLabel = [[UILabel alloc] init];
	self.trueToneLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.trueToneLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
	[self.trueToneContainer addSubview:self.trueToneLabel];
	
	self.temperatureTitleLabel = [[UILabel alloc] init];
	self.temperatureTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.temperatureTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
	self.temperatureTitleLabel.textColor = [UIColor compatSecondaryLabelColor];
	self.temperatureTitleLabel.text = _("Screen Hardware Temperature");
	[self.cardView addSubview:self.temperatureTitleLabel];
	
	self.temperatureValueLabel = [[UILabel alloc] init];
	self.temperatureValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.temperatureValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	self.temperatureValueLabel.textColor = [UIColor compatLabelColor];
	self.temperatureValueLabel.textAlignment = NSTextAlignmentRight;
	[self.cardView addSubview:self.temperatureValueLabel];
	
	self.resolutionTitleLabel = [[UILabel alloc] init];
	self.resolutionTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.resolutionTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
	self.resolutionTitleLabel.textColor = [UIColor compatSecondaryLabelColor];
	self.resolutionTitleLabel.text = _("Resolution");
	[self.cardView addSubview:self.resolutionTitleLabel];
	
	self.gamutTitleLabel = [[UILabel alloc] init];
	self.gamutTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.gamutTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
	self.gamutTitleLabel.textColor = [UIColor compatSecondaryLabelColor];
	self.gamutTitleLabel.text = _("Color Gamut");
	[self.cardView addSubview:self.gamutTitleLabel];
	
	self.temperatureTitleLabelLandscape = [[UILabel alloc] init];
	self.temperatureTitleLabelLandscape.translatesAutoresizingMaskIntoConstraints = NO;
	self.temperatureTitleLabelLandscape.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
	self.temperatureTitleLabelLandscape.textColor = [UIColor compatSecondaryLabelColor];
	self.temperatureTitleLabelLandscape.text = _("Temperature");
	[self.cardView addSubview:self.temperatureTitleLabelLandscape];
}

- (void)_setupConstraints {
	// Common
	[NSLayoutConstraint activateConstraints:@[
		[self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
		[self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
		[self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
		[self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		
		[self.iconBackgroundView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
		[self.iconBackgroundView.widthAnchor constraintEqualToConstant:60],
		[self.iconBackgroundView.heightAnchor constraintEqualToConstant:60],

		[self.iconImageView.centerXAnchor constraintEqualToAnchor:self.iconBackgroundView.centerXAnchor],
		[self.iconImageView.centerYAnchor constraintEqualToAnchor:self.iconBackgroundView.centerYAnchor],
		[self.iconImageView.widthAnchor constraintEqualToConstant:32],
		[self.iconImageView.heightAnchor constraintEqualToConstant:32],
		
		[self.nightShiftLabel.topAnchor constraintEqualToAnchor:self.nightShiftContainer.topAnchor constant:6],
		[self.nightShiftLabel.leadingAnchor constraintEqualToAnchor:self.nightShiftContainer.leadingAnchor constant:10],
		[self.nightShiftLabel.trailingAnchor constraintEqualToAnchor:self.nightShiftContainer.trailingAnchor constant:-10],
		[self.nightShiftLabel.bottomAnchor constraintEqualToAnchor:self.nightShiftContainer.bottomAnchor constant:-6],
		
		[self.trueToneLabel.topAnchor constraintEqualToAnchor:self.trueToneContainer.topAnchor constant:6],
		[self.trueToneLabel.leadingAnchor constraintEqualToAnchor:self.trueToneContainer.leadingAnchor constant:10],
		[self.trueToneLabel.trailingAnchor constraintEqualToAnchor:self.trueToneContainer.trailingAnchor constant:-10],
		[self.trueToneLabel.bottomAnchor constraintEqualToAnchor:self.trueToneContainer.bottomAnchor constant:-6],
	]];
	
	// Portrait
	NSMutableArray *portraitConstraintsList = [NSMutableArray array];
	[portraitConstraintsList addObjectsFromArray:@[
		[self.iconBackgroundView.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:16],
		
		[self.resolutionLabel.centerYAnchor constraintEqualToAnchor:self.iconBackgroundView.centerYAnchor constant:-9],
		[self.resolutionLabel.leadingAnchor constraintEqualToAnchor:self.iconBackgroundView.trailingAnchor constant:12],
		[self.gamutLabel.topAnchor constraintEqualToAnchor:self.resolutionLabel.bottomAnchor constant:2],
		[self.gamutLabel.leadingAnchor constraintEqualToAnchor:self.resolutionLabel.leadingAnchor],
		
		[self.nightShiftContainer.topAnchor constraintEqualToAnchor:self.iconBackgroundView.bottomAnchor constant:16],
		[self.nightShiftContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
		[self.trueToneContainer.centerYAnchor constraintEqualToAnchor:self.nightShiftContainer.centerYAnchor],
		[self.trueToneContainer.leadingAnchor constraintEqualToAnchor:self.nightShiftContainer.trailingAnchor constant:12],
		
		[self.temperatureTitleLabel.topAnchor constraintEqualToAnchor:self.nightShiftContainer.bottomAnchor constant:16],
		[self.temperatureTitleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:16],
		[self.temperatureValueLabel.centerYAnchor constraintEqualToAnchor:self.temperatureTitleLabel.centerYAnchor],
		[self.temperatureValueLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-16],
	]];
	
	// Bottom constraint with lower priority to avoid conflicts during rotation
	NSLayoutConstraint *bottomConstraint = [self.temperatureTitleLabel.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-16];
	bottomConstraint.priority = UILayoutPriorityDefaultHigh;
	[portraitConstraintsList addObject:bottomConstraint];
	
	self.portraitConstraints = [portraitConstraintsList copy];
	
	// Landscape
	self.landscapeConstraints = @[
		[self.iconBackgroundView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
		
		[self.resolutionTitleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
		[self.resolutionTitleLabel.leadingAnchor constraintEqualToAnchor:self.iconBackgroundView.trailingAnchor constant:20],
		[self.resolutionLabel.topAnchor constraintEqualToAnchor:self.resolutionTitleLabel.bottomAnchor constant:4],
		[self.resolutionLabel.leadingAnchor constraintEqualToAnchor:self.resolutionTitleLabel.leadingAnchor],
		[self.resolutionLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.cardView.bottomAnchor constant:-20],
		
		[self.gamutTitleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
		[self.gamutTitleLabel.leadingAnchor constraintEqualToAnchor:self.resolutionLabel.trailingAnchor constant:20],
		[self.gamutLabel.topAnchor constraintEqualToAnchor:self.gamutTitleLabel.bottomAnchor constant:4],
		[self.gamutLabel.leadingAnchor constraintEqualToAnchor:self.gamutTitleLabel.leadingAnchor],
		
		[self.temperatureTitleLabelLandscape.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:20],
		[self.temperatureTitleLabelLandscape.leadingAnchor constraintEqualToAnchor:self.gamutTitleLabel.trailingAnchor constant:20],
		[self.temperatureValueLabel.topAnchor constraintEqualToAnchor:self.temperatureTitleLabelLandscape.bottomAnchor constant:4],
		[self.temperatureValueLabel.leadingAnchor constraintEqualToAnchor:self.temperatureTitleLabelLandscape.leadingAnchor],
		
		[self.nightShiftContainer.trailingAnchor constraintEqualToAnchor:self.trueToneContainer.leadingAnchor constant:-12],
		[self.nightShiftContainer.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
		[self.trueToneContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
		[self.trueToneContainer.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
	];
}

- (BOOL)_isLandscapeLayout {
	UIWindow *window = self.window ?: self.contentView.window;
	CGFloat width = window ? window.bounds.size.width : [UIScreen autoScreen].bounds.size.width;
	BOOL wideRegular = (width >= 700.0 && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular);
	return (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) || wideRegular;
}

- (void)_updateLayoutForOrientation {
	BOOL isLandscape = [self _isLandscapeLayout];
	
	if (isLandscape) {
		[NSLayoutConstraint deactivateConstraints:self.portraitConstraints];
		[NSLayoutConstraint activateConstraints:self.landscapeConstraints];
		
		// portrait-only
		self.temperatureTitleLabel.hidden = YES;
		
		// landscape-only
		self.resolutionTitleLabel.hidden = NO;
		self.gamutTitleLabel.hidden = NO;
		self.temperatureTitleLabelLandscape.hidden = NO;

		self.resolutionLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		self.gamutLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		self.temperatureValueLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		self.temperatureValueLabel.textAlignment = NSTextAlignmentLeft;
		
		[self _updateNightShiftLabelWithFontSize:14];
		[self _updateTrueToneLabelWithFontSize:14];
	} else {
		[NSLayoutConstraint deactivateConstraints:self.landscapeConstraints];
		[NSLayoutConstraint activateConstraints:self.portraitConstraints];
		
		// portrait-only
		self.temperatureTitleLabel.hidden = NO;
		
		// landscape-only
		self.resolutionTitleLabel.hidden = YES;
		self.gamutTitleLabel.hidden = YES;
		self.temperatureTitleLabelLandscape.hidden = YES;

		self.resolutionLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
		self.gamutLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
		self.temperatureValueLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
		self.temperatureValueLabel.textAlignment = NSTextAlignmentRight;
		
		[self _updateNightShiftLabelWithFontSize:15];
		[self _updateTrueToneLabelWithFontSize:15];
	}
}

// XXX: Flexible features?
- (void)_updateFeatureBadge:(UIView *)containerView label:(UILabel *)label isSupported:(BOOL)isSupported enabledCGImage:(CGImageRef)enabledCGImage enabledColor:(UIColor *)enabledColor labelText:(NSString *)labelText fontSize:(CGFloat)fontSize {
	UIColor *color = nil;
	UIColor *labelColor = nil;
	
	if (isSupported) {
		color = enabledColor;
		if (@available(iOS 13.0, *))
			labelColor = UIColor.whiteColor;
	} else {
		color = [UIColor tertiaryCompatFillColor];
		if (@available(iOS 13.0, *))
			labelColor = [UIColor compatLabelColor];
	}
	
	if (labelColor == nil)
		labelColor = color;
	
	// iOS 13+: fill background
	// iOS 12: stroke only
	if (@available(iOS 13.0, *))
		containerView.layer.backgroundColor = color.CGColor;
	containerView.layer.borderColor = color.CGColor;
	
	CGFloat iconSize = fontSize * 1.2;
	
	// iOS 13+: Use labelColor, since background has been filled
	// iOS 12: Use stroke color as iconColor and labelColor
	UIColor *iconColor = color;
	if (@available(iOS 13.0, *))
		iconColor = labelColor;
	
	NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];
	CGImageRef cgimg = NULL;
	if (isSupported) {
		cgimg = enabledCGImage;
	} else if (@available(iOS 13.0, *)) {
		cgimg = [UIImage systemImageNamed:@"xmark"].CGImage;
	} else {
		cgimg = imageForSFProGlyph(@"􀆄", @SFPRO, 22, iconColor).CGImage;
	}
	UIImage *iconImage = redrawUIImage([UIImage imageWithCGImage:cgimg], iconColor, CGSizeMake(iconSize, iconSize));
	
	// Create text attachment for the icon
	NSTextAttachment *iconAttachment = [[NSTextAttachment alloc] init];
	iconAttachment.image = iconImage;
	// Center the icon vertically with the text
	CGFloat offsetY = (fontSize - iconSize) / 2.0;
	iconAttachment.bounds = CGRectMake(0, offsetY - 2, iconSize, iconSize);
	
	[attributedText appendAttributedString:[NSAttributedString attributedStringWithAttachment:iconAttachment]];
	[attributedText appendAttributedString:[[NSAttributedString alloc] initWithString:labelText attributes:@{
		NSForegroundColorAttributeName: labelColor,
		NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightRegular]
	}]];
	
	label.attributedText = attributedText;
}

- (void)_updateNightShiftLabelWithFontSize:(CGFloat)fontSize {
	[self _updateFeatureBadge:self.nightShiftContainer label:self.nightShiftLabel isSupported:_isNightShiftSupported enabledCGImage:[NightShiftVectorIcon NightShiftCGImage] enabledColor:[UIColor compatOrangeColor] labelText:[NSString stringWithFormat:@" %@", _("Night Shift")] fontSize:fontSize];
}

- (void)_updateTrueToneLabelWithFontSize:(CGFloat)fontSize {
	[self _updateFeatureBadge:self.trueToneContainer label:self.trueToneLabel isSupported:_isTrueToneSupported enabledCGImage:[TrueToneVectorIcon TrueToneCGImage] enabledColor:[UIColor compatBlueColor] labelText:[NSString stringWithFormat:@" %@", _("True Tone")] fontSize:fontSize];
}

- (void)setResolutionText:(NSString *)resolutionText {
	_resolutionText = [resolutionText copy];
	self.resolutionLabel.text = resolutionText;
}

- (void)setDisplayGamut:(NSString *)displayGamut {
	_displayGamut = [displayGamut copy];
	self.gamutLabel.text = displayGamut;
}

- (void)setIsNightShiftSupported:(BOOL)isNightShiftSupported {
	_isNightShiftSupported = isNightShiftSupported;
	BOOL isLandscape = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
	[self _updateNightShiftLabelWithFontSize:isLandscape ? 14 : 15];
}

- (void)setIsTrueToneSupported:(BOOL)isTrueToneSupported {
	_isTrueToneSupported = isTrueToneSupported;
	BOOL isLandscape = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
	[self _updateTrueToneLabelWithFontSize:isLandscape ? 14 : 15];
}

- (void)setTemperatureCelsius:(CGFloat)temperatureCelsius {
	_temperatureCelsius = temperatureCelsius;
	if (_unknownTemperature) {
		self.temperatureValueLabel.text = _("Unknown");
	} else {
		self.temperatureValueLabel.text = [NSString stringWithFormat:@"%.4g ℃", temperatureCelsius];
	}
}

- (void)setUnknownTemperature:(BOOL)unknownTemperature {
	_unknownTemperature = unknownTemperature;
	if (unknownTemperature) {
		self.temperatureValueLabel.text = _("Unknown");
	} else {
		self.temperatureValueLabel.text = [NSString stringWithFormat:@"%.4g ℃", _temperatureCelsius];
	}
}

@end
