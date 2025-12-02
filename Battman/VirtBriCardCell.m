//
//  VirtBriCardCell.m
//  Battman
//
//  Created by Torrekie on 2025/11/19.
//

#import "ObjCExt/UIColor+compat.h"
#import "ObjCExt/UIScreen+Auto.h"
#import "ObjCExt/CALayer+smoothCorners.h"
#import "common.h"
#import "VirtBriCardCell.h"
#import "CardProgressView.h"

@interface VirtBriCardCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UILabel *brightnessTitleLabel;
@property (nonatomic, strong) UILabel *brightnessPercentageLabel;
@property (nonatomic, strong) UIProgressView *brightnessProgressView;
@property (nonatomic, strong) UIView *separator1;
@property (nonatomic, strong) CardProgressView *nitsProgressView;
@property (nonatomic, strong) UIView *separator2;
@property (nonatomic, strong) UIView *dimmingContainer;
@property (nonatomic, strong) UILabel *dimmingLabel;
@property (nonatomic, strong) UIView *edrContainer;
@property (nonatomic, strong) UILabel *edrLabel;

@end

@implementation VirtBriCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self _configureView];
        [self _setupConstraints];
        [self _updateLayoutForOrientation];
    }
    return self;
}

- (void)_configureView {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    
    // Card container view
    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = self.backgroundColor;
    self.cardView.layer.cornerRadius = 16;
	[self.cardView.layer setSmoothCorners:YES];
    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 2);
    self.cardView.layer.shadowOpacity = 0.1;
    self.cardView.layer.shadowRadius = 8;
    [self.contentView addSubview:self.cardView];
    
    // Brightness title label
    self.brightnessTitleLabel = [[UILabel alloc] init];
    self.brightnessTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.brightnessTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightLight];
    self.brightnessTitleLabel.textColor = [UIColor compatLabelColor];
    self.brightnessTitleLabel.text = _("Brightness Slider");
    [self.brightnessTitleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.brightnessTitleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [self.cardView addSubview:self.brightnessTitleLabel];
    
    // Brightness percentage label
    self.brightnessPercentageLabel = [[UILabel alloc] init];
    self.brightnessPercentageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.brightnessPercentageLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    self.brightnessPercentageLabel.textColor = [UIColor compatLabelColor];
    self.brightnessPercentageLabel.textAlignment = NSTextAlignmentRight;
    [self.brightnessPercentageLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.brightnessPercentageLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.cardView addSubview:self.brightnessPercentageLabel];
    
    // Brightness progress view
    self.brightnessProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.brightnessProgressView.translatesAutoresizingMaskIntoConstraints = NO;
	self.brightnessProgressView.progressTintColor = [UIColor compatBlueColor];
	self.brightnessProgressView.trackTintColor = [UIColor tertiaryCompatFillColor];
    self.brightnessProgressView.layer.cornerRadius = 4;
	[self.brightnessProgressView.layer setSmoothCorners:YES];
	
    self.brightnessProgressView.clipsToBounds = YES;
    self.brightnessProgressView.layer.sublayers[0].cornerRadius = 4;
	[self.brightnessProgressView.layer.sublayers[0] setSmoothCorners:YES];
    [self.brightnessProgressView.layer.sublayers[0] setMasksToBounds:YES];
    [self.cardView addSubview:self.brightnessProgressView];
    
    // Separator 1
    self.separator1 = [[UIView alloc] init];
    self.separator1.translatesAutoresizingMaskIntoConstraints = NO;
	self.separator1.backgroundColor = [UIColor compatSeparatorColor];
    [self.cardView addSubview:self.separator1];

    self.nitsProgressView = [[CardProgressView alloc] initWithTitle:_("Brightness Limits (nits)") minValue:0 maxValue:100 majorProgress:50];
	self.nitsProgressView.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightLight];
    self.nitsProgressView.translatesAutoresizingMaskIntoConstraints = NO;
    self.nitsProgressView.majorProgressName = _("Slider Max");
	self.nitsProgressView.majorProgressColor = [[UIColor compatBlueColor] colorWithAlphaComponent:0.5];
    [self.cardView addSubview:self.nitsProgressView];

    self.separator2 = [[UIView alloc] init];
    self.separator2.translatesAutoresizingMaskIntoConstraints = NO;
	self.separator2.backgroundColor = [[UIColor compatSeparatorColor] colorWithAlphaComponent:0.2];
    [self.cardView addSubview:self.separator2];

    self.dimmingContainer = [[UIView alloc] init];
    self.dimmingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingContainer.layer.cornerRadius = 8;
	[self.dimmingContainer.layer setSmoothCorners:YES];
	self.dimmingContainer.backgroundColor = [[UIColor compatGreenColor] colorWithAlphaComponent:0.15];
    [self.cardView addSubview:self.dimmingContainer];
    
    self.dimmingLabel = [[UILabel alloc] init];
    self.dimmingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.dimmingLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
	self.dimmingLabel.textColor = [UIColor compatGreenColor];
    self.dimmingLabel.textAlignment = NSTextAlignmentCenter;
    [self.dimmingContainer addSubview:self.dimmingLabel];

    self.edrContainer = [[UIView alloc] init];
    self.edrContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.edrContainer.layer.cornerRadius = 8;
	[self.edrContainer.layer setSmoothCorners:YES];
	self.edrContainer.backgroundColor = [[UIColor compatGreenColor] colorWithAlphaComponent:0.15];
    [self.cardView addSubview:self.edrContainer];
    
    self.edrLabel = [[UILabel alloc] init];
    self.edrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.edrLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
	self.edrLabel.textColor = [UIColor compatGreenColor];
    self.edrLabel.textAlignment = NSTextAlignmentCenter;
    [self.edrContainer addSubview:self.edrLabel];
    
    [self _updateDimmingBadge];
    [self _updateEDRBadge];
}

- (void)_setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

        [self.brightnessPercentageLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:12],
        [self.brightnessPercentageLabel.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],

        [self.brightnessTitleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.brightnessTitleLabel.firstBaselineAnchor constraintEqualToAnchor:self.brightnessPercentageLabel.firstBaselineAnchor],
        [self.brightnessTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.brightnessPercentageLabel.leadingAnchor constant:-12],

        [self.brightnessProgressView.topAnchor constraintEqualToAnchor:self.brightnessPercentageLabel.bottomAnchor constant:4],
        [self.brightnessProgressView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.brightnessProgressView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.brightnessProgressView.heightAnchor constraintEqualToConstant:6],
        
        [self.separator1.topAnchor constraintEqualToAnchor:self.brightnessProgressView.bottomAnchor constant:8],
        [self.separator1.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.separator1.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.separator1.heightAnchor constraintEqualToConstant:0.5],
        
        [self.nitsProgressView.topAnchor constraintEqualToAnchor:self.separator1.bottomAnchor constant:8],
        [self.nitsProgressView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.nitsProgressView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        
        [self.separator2.topAnchor constraintEqualToAnchor:self.nitsProgressView.bottomAnchor constant:8],
        [self.separator2.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.separator2.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.separator2.heightAnchor constraintEqualToConstant:0.5],

        [self.dimmingContainer.topAnchor constraintEqualToAnchor:self.separator2.bottomAnchor constant:8],
        [self.dimmingContainer.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:20],
        [self.dimmingContainer.trailingAnchor constraintEqualToAnchor:self.cardView.centerXAnchor constant:-4],
        [self.dimmingContainer.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-12],
        [self.dimmingContainer.heightAnchor constraintEqualToConstant:36],
        
        [self.edrContainer.topAnchor constraintEqualToAnchor:self.separator2.bottomAnchor constant:8],
        [self.edrContainer.leadingAnchor constraintEqualToAnchor:self.cardView.centerXAnchor constant:4],
        [self.edrContainer.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-20],
        [self.edrContainer.bottomAnchor constraintEqualToAnchor:self.cardView.bottomAnchor constant:-12],
        [self.edrContainer.heightAnchor constraintEqualToConstant:36],

        [self.dimmingLabel.centerXAnchor constraintEqualToAnchor:self.dimmingContainer.centerXAnchor],
        [self.dimmingLabel.centerYAnchor constraintEqualToAnchor:self.dimmingContainer.centerYAnchor],
        
        [self.edrLabel.centerXAnchor constraintEqualToAnchor:self.edrContainer.centerXAnchor],
        [self.edrLabel.centerYAnchor constraintEqualToAnchor:self.edrContainer.centerYAnchor],
    ]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if (self.traitCollection.verticalSizeClass != previousTraitCollection.verticalSizeClass ||
		self.traitCollection.horizontalSizeClass != previousTraitCollection.horizontalSizeClass) {
		[self _updateLayoutForOrientation];
	}
}

- (void)_updateLayoutForOrientation {
	UIWindow *window = self.window ?: self.contentView.window;
	CGFloat width = 0;
	if (window) {
		width = window.bounds.size.width;
	} else {
		UIScreen *screen = [UIScreen autoScreen];
		width = screen ? screen.bounds.size.width : 375.0; // Default to iPhone width if screen unavailable
	}
	BOOL wideRegular = (width >= 700.0 && self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular);
	BOOL isLandscape = (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) || wideRegular;

	if (isLandscape) {
		self.brightnessTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightLight];
		self.brightnessPercentageLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
		self.nitsProgressView.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightLight];
		self.dimmingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
		self.edrLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
	} else {
		self.brightnessTitleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightLight];
		self.brightnessPercentageLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
		self.nitsProgressView.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightLight];
		self.dimmingLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
		self.edrLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
	}
}

- (void)_updateDimmingBadge {
    NSString *iconText = self.digitalDimmingSupported ? @"✓ " : @"✗ ";
    NSString *labelText = _("Dimming");
    
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];
    
    UIColor *iconColor, *bgColor;
    if (self.digitalDimmingSupported) {
		iconColor = [UIColor compatGreenColor];
		bgColor = [[UIColor compatGreenColor] colorWithAlphaComponent:0.15];
    } else {
		iconColor = [UIColor compatGrayColor];
		bgColor = [UIColor tertiaryCompatFillColor];
    }
    
    NSAttributedString *icon = [[NSAttributedString alloc] initWithString:iconText attributes:@{
        NSForegroundColorAttributeName: iconColor,
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightBold]
    }];
    [attributedText appendAttributedString:icon];
    
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:labelText attributes:@{
        NSForegroundColorAttributeName: iconColor,
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]
    }];
    [attributedText appendAttributedString:text];
    
    self.dimmingLabel.attributedText = attributedText;
    self.dimmingContainer.backgroundColor = bgColor;
}

- (void)_updateEDRBadge {
    NSString *iconText = self.extrabrightEDRSupported ? @"✓ " : @"✗ ";
    NSString *labelText = _("EDR");
    
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];
    
    UIColor *iconColor, *bgColor;
    if (self.extrabrightEDRSupported) {
		iconColor = [UIColor compatGreenColor];
		bgColor = [[UIColor compatGreenColor] colorWithAlphaComponent:0.15];
	} else {
		iconColor = [UIColor compatGrayColor];
		bgColor = [UIColor tertiaryCompatFillColor];
    }
    
    NSAttributedString *icon = [[NSAttributedString alloc] initWithString:iconText attributes:@{
        NSForegroundColorAttributeName: iconColor,
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightBold]
    }];
    [attributedText appendAttributedString:icon];
    
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:labelText attributes:@{
        NSForegroundColorAttributeName: iconColor,
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightMedium]
    }];
    [attributedText appendAttributedString:text];
    
    self.edrLabel.attributedText = attributedText;
    self.edrContainer.backgroundColor = bgColor;
}

- (void)_updateNitsProgressView {
    self.nitsProgressView.minValue = self.hardwareAccessibleMinNits;
    self.nitsProgressView.maxValue = self.hardwareAccessibleMaxNits;
    self.nitsProgressView.majorProgress = self.userAccessibleMaxNits;

    NSMutableArray<CardProgressIndicator *> *indicators = [NSMutableArray array];

	[indicators addObject:[CardProgressIndicator indicatorWithName:_("Present") value:self.currentNits color:[UIColor compatBlueColor]]];
	[indicators addObject:[CardProgressIndicator indicatorWithName:_("Physical") value:self.currentNitsPhysical color:[UIColor compatGrayColor]]];
    if (self.digitalDimmingSupported) {
		[indicators addObject:[CardProgressIndicator indicatorWithName:_("Min (Dimming)") value:self.minNitsAccessibleWithDigitalDimming color:[UIColor compatGray4Color]]];
    }

    self.nitsProgressView.indicators = indicators;
}

#pragma mark - Property Setters

- (void)setDigitalDimmingSupported:(BOOL)digitalDimmingSupported {
    _digitalDimmingSupported = digitalDimmingSupported;
    [self _updateDimmingBadge];
    [self _updateNitsProgressView];
}

- (void)setExtrabrightEDRSupported:(BOOL)extrabrightEDRSupported {
    _extrabrightEDRSupported = extrabrightEDRSupported;
    [self _updateEDRBadge];
}

- (void)setHardwareAccessibleMaxNits:(NSInteger)hardwareAccessibleMaxNits {
    _hardwareAccessibleMaxNits = hardwareAccessibleMaxNits;
    [self _updateNitsProgressView];
}

- (void)setHardwareAccessibleMinNits:(NSInteger)hardwareAccessibleMinNits {
    _hardwareAccessibleMinNits = hardwareAccessibleMinNits;
    [self _updateNitsProgressView];
}

- (void)setMinNitsAccessibleWithDigitalDimming:(NSInteger)minNitsAccessibleWithDigitalDimming {
    _minNitsAccessibleWithDigitalDimming = minNitsAccessibleWithDigitalDimming;
    [self _updateNitsProgressView];
}

- (void)setUserAccessibleMaxNits:(NSInteger)userAccessibleMaxNits {
    _userAccessibleMaxNits = userAccessibleMaxNits;
    [self _updateNitsProgressView];
}

- (void)setBrightnessPercentage:(CGFloat)brightnessPercentage {
    _brightnessPercentage = brightnessPercentage;
    self.brightnessPercentageLabel.text = [NSString stringWithFormat:@"%.1f%%", brightnessPercentage * 100.0];
    self.brightnessProgressView.progress = brightnessPercentage;
}

- (void)setCurrentNits:(CGFloat)currentNits {
    _currentNits = currentNits;
    [self _updateNitsProgressView];
}

- (void)setCurrentNitsPhysical:(CGFloat)currentNitsPhysical {
    _currentNitsPhysical = currentNitsPhysical;
    [self _updateNitsProgressView];
}

@end
