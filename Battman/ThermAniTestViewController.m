//
//  ThermAniTestViewController.m
//  Battman
//
//  Created by Torrekie on 2025/10/30.
//

#import "common.h"
#import "battery_utils/libsmc.h"
#import "ObjCExt/UIScreen+Auto.h"
#import "ObjCExt/CALayer+smoothCorners.h"
#import "ThermAniTestViewController.h"
#import "GradientArcView.h"
#import "BattmanPrefs.h"
#import "UITextFieldStepper.h"

@interface ThermAniTestCell ()
@property (nonatomic, strong) CAGradientLayer *borderGradient;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) GradientArcView *arcView;
@property (nonatomic, strong) UIView *borderView;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) UILabel *leftLabel;
@property (nonatomic, strong) UILabel *rightLabel;
@end

extern UITableViewCell *find_cell(UIView *view);

@implementation ThermAniTestCell

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

- (void)updateColors {
	if (@available(iOS 12.0, *)) {
		// We already have a non published darkmode in iOS 12, some tweaks may be able to enforce it
		if ([(id)UIScreen.autoScreen.traitCollection userInterfaceStyle] == UIUserInterfaceStyleDark) {
			self.borderGradient.colors = @[
				(id)[UIColor darkGrayColor].CGColor,
				(id)[UIColor blackColor].CGColor,
			];
			self.gradient.colors = @[
				(id)[UIColor colorWithWhite:0.40 alpha:1.0].CGColor,
				(id)[UIColor colorWithWhite:0.05 alpha:1.0].CGColor
			];
			
			// Dark mode label colors
			self.leftLabel.textColor = [UIColor whiteColor];
			self.rightLabel.textColor = [UIColor whiteColor];
			
			return;
		}
	}
	// Default
	self.borderGradient.colors = @[
		(id)[UIColor lightGrayColor].CGColor,
		(id)[UIColor darkGrayColor].CGColor,
	];
	self.gradient.colors = @[
		(id)[UIColor colorWithWhite:0.5 alpha:1.0].CGColor,
		(id)[UIColor colorWithWhite:0.1 alpha:1.0].CGColor
	];
	
	// Light mode label colors
	self.leftLabel.textColor = [UIColor blackColor];
	self.rightLabel.textColor = [UIColor blackColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	// Handle dark mode switches
	[self updateColors];
}

- (void)updateDynamicValues {
	CGFloat width = self.borderView.bounds.size.width;
	if (width <= 0) return; // Don't update if view hasn't been laid out yet
	
	// Update corner radius (width * 0.375)
	CGFloat cornerRadius = width * 0.375;
	self.borderView.layer.cornerRadius = cornerRadius;
	
	// Update mask layer path and line width
	CGFloat lineWidth = width * 0.0625;
	self.maskLayer.lineWidth = lineWidth;
	self.maskLayer.path = CGPathCreateWithRoundedRect(CGRectMake(0, 0, width, width), cornerRadius, cornerRadius, nil);
	
	// Update gradient layer frames
	self.borderGradient.frame = self.borderView.bounds;
	self.gradient.frame = self.borderView.bounds;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	[self updateDynamicValues];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.borderView = [[UIView alloc] initWithFrame:CGRectZero];
		[self.borderView.layer setSmoothCorners:YES];
		self.borderView.layer.masksToBounds = YES;
		self.borderView.translatesAutoresizingMaskIntoConstraints = NO;

		self.borderGradient = [CAGradientLayer layer];
		self.gradient = [CAGradientLayer layer];
		
		// gradients
		self.borderGradient.startPoint = CGPointMake(0.5, 0.0);
		self.borderGradient.endPoint   = CGPointMake(0.5, 1.0);
		self.gradient.startPoint = CGPointMake(0.5, 0.0);
		self.gradient.endPoint   = CGPointMake(0.5, 1.0);
		
		// colors
		[self updateColors];
		
		// Create mask layer for border gradient
		self.maskLayer = [CAShapeLayer layer];
		self.maskLayer.fillColor = [UIColor clearColor].CGColor;
		self.maskLayer.strokeColor = [UIColor blackColor].CGColor; // the actual color doesn't matter; it's just a mask
		
		self.borderGradient.mask = self.maskLayer;
		[self.borderView.layer addSublayer:self.borderGradient];
		[self.borderView.layer insertSublayer:self.gradient atIndex:0];
		
		{
			self.arcView = [[GradientArcView alloc] initWithFrame:CGRectZero];
			self.arcView.translatesAutoresizingMaskIntoConstraints = NO;
			[self.borderView addSubview:self.arcView];
			
			// Center arcView within borderView
			[NSLayoutConstraint activateConstraints:@[
				[self.arcView.centerXAnchor constraintEqualToAnchor:self.borderView.centerXAnchor],
				[self.arcView.centerYAnchor constraintEqualToAnchor:self.borderView.centerYAnchor],
				[self.arcView.widthAnchor constraintEqualToAnchor:self.borderView.widthAnchor],
				[self.arcView.heightAnchor constraintEqualToAnchor:self.borderView.heightAnchor],
			]];
			
			[self.arcView rotatePointerToPercentage:0];
		}
		
		// Create custom labels
		self.leftLabel = [[UILabel alloc] init];
		self.leftLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.leftLabel.textAlignment = NSTextAlignmentRight;
		self.leftLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
		
		self.rightLabel = [[UILabel alloc] init];
		self.rightLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.rightLabel.textAlignment = NSTextAlignmentLeft;
		self.rightLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
		
		[self.contentView addSubview:self.borderView];
		[self.contentView addSubview:self.leftLabel];
		[self.contentView addSubview:self.rightLabel];

		// Center borderView in contentView with proper sizing
		[NSLayoutConstraint activateConstraints:@[
			[self.borderView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:25],
			[self.borderView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-25],
			[self.borderView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
			[self.borderView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
			[self.borderView.widthAnchor constraintEqualToAnchor:self.borderView.heightAnchor],
			//[self.borderView.heightAnchor constraintEqualToConstant:125], // Set a reasonable default size
		]];
		
		// Position labels to the left and right of the thermometer
		[NSLayoutConstraint activateConstraints:@[
			// Left label constraints
			[self.leftLabel.trailingAnchor constraintEqualToAnchor:self.borderView.leadingAnchor constant:-16],
			[self.leftLabel.centerYAnchor constraintEqualToAnchor:self.borderView.centerYAnchor],
			[self.leftLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.leadingAnchor constant:16],
			
			// Right label constraints
			[self.rightLabel.leadingAnchor constraintEqualToAnchor:self.borderView.trailingAnchor constant:16],
			[self.rightLabel.centerYAnchor constraintEqualToAnchor:self.borderView.centerYAnchor],
			[self.rightLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-16],
		]];
		return self;
	}
	return self;
}

@end

@interface ThermAniTestViewController ()
@property (nonatomic, strong) ThermAniTestCell *temperatureCell;
@property (nonatomic, weak) UIStepper *thermMinStepper;
@property (nonatomic, weak) UIStepper *thermMaxStepper;

@property (nonatomic, assign) BOOL isUpdatingThermometerValues;
@end

@implementation ThermAniTestViewController

float get_current_temp_percentage(void) {
	typedef enum {
		TEMP_NULL = 0,
		TEMP_BATT = (1 << 0),
		TEMP_SNSR = (1 << 1),
		TEMP_SCRN = (1 << 2),
	} tempbit;
	tempbit got_temp = 0;
	float *btemps = get_temperature_per_cell();
	float batttemp = -1;
	if (btemps != NULL && *btemps) {
		got_temp |= TEMP_BATT;
		float total = 0;
		int num = batt_cell_num();
		for (int i = 0; i < num; i++) {
			total += btemps[i];
		}
		// Embedded designed operating temp: 0º to 35º C
		batttemp = total / num;
		free(btemps);
	}
	
	extern float getSensorAvgTemperature(void);
	float snsrtemp = getSensorAvgTemperature();
	if (snsrtemp != -1) {
		got_temp |= TEMP_SNSR;
	}
	
	// I've seen a broken screen that not reporting this, so this could also be a way to check screen sanity
	extern double iomfb_primary_screen_temperature(void);
	double scrntemp = iomfb_primary_screen_temperature();
	if (scrntemp != -1) {
		got_temp |= TEMP_SCRN;
	}
	
	float minVal = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_THERM_UI_MIN];
	float maxVal = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_THERM_UI_MAX];
	if (minVal <= 0.0f) minVal = 0.0f;
	if (maxVal <= 0.0f) maxVal = 45.0f;
	
#define TEMP_TO_PERCENTAGE(x) (x > maxVal) ? 1.0 : (x < minVal ? 0.0 : (x - minVal) / (maxVal - minVal))
	float ret = 0;
	if (got_temp & TEMP_BATT) {
		ret = TEMP_TO_PERCENTAGE(batttemp);
	} else if (got_temp & TEMP_SNSR) {
		ret = TEMP_TO_PERCENTAGE(snsrtemp);
	} else if (got_temp & TEMP_SCRN) {
		ret = TEMP_TO_PERCENTAGE(scrntemp);
	}
	NSLog(@"get_current_temp_percentage: %f (%f / %f)", ret, minVal, maxVal);
	return ret;
}

- (NSString *)title {
	return _("Thermometer Icon");
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
	self.tableView.allowsSelection = NO;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return TAT_SECT_COUNT;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return (section == TAT_SECT_THERM_RANGE) ? _("Temperature Range") : _("Thermometer Preview");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return (section == TAT_SECT_THERM_RANGE) ? _("Set the temperature range shown in Thermometer.") : _("This preview shows how the pointer adjusts to match the current temperature based on your selected range.");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	ThermAniSect sect = (ThermAniSect)section;
	switch (sect) {
		case TAT_SECT_THERM_RANGE: return TAT_ROW_THERM_RANGE_COUNT;
		case TAT_SECT_THERM_PREVIEW: return TAT_ROW_THERM_PREVIEW_COUNT;
		default: break;
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == TAT_SECT_THERM_PREVIEW)
		return 175;
	return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell;
	id config_value = [BattmanPrefs.sharedPrefs valueForTableView:tableView indexPath:indexPath];
	ThermAniSect sect = (ThermAniSect)indexPath.section;
	switch (sect) {
		case TAT_SECT_THERM_RANGE: {
			cell = [UITableViewCell new];
			UIStepper *st = nil;
			if (@available(iOS 17.0, *)) {
				// FIXME: UITextFieldStepper crashes on iOS 17+
				st = [UIStepper new];
			} else {
				st = (UIStepper *)[UITextFieldStepper new];
			}
			ThermAniRowRange row = (ThermAniRowRange)indexPath.row;
			switch (row) {
				case TAT_ROW_THERM_RANGE_MIN: {
					cell.textLabel.text = _("Min Temperature");
					st.maximumValue = 140 - 1;
					st.minimumValue = -50;
					st.value = [config_value intValue];
					st.tag = TAT_ROW_THERM_RANGE_MIN;
					[st addTarget:self action:@selector(thermometerStepperValueChanged:) forControlEvents:UIControlEventValueChanged];
					self.thermMinStepper = st;
					break;
				}
				case TAT_ROW_THERM_RANGE_MAX: {
					cell.textLabel.text = _("Max Temperature");
					st.maximumValue = 140;
					st.minimumValue = -50 + 1;
					st.value = [config_value intValue];
					st.tag = TAT_ROW_THERM_RANGE_MAX;
					[st addTarget:self action:@selector(thermometerStepperValueChanged:) forControlEvents:UIControlEventValueChanged];
					self.thermMaxStepper = st;
					break;
				}
				case TAT_ROW_THERM_RANGE_COUNT: break;
			}
			cell.accessoryView = st;
			break;
		}
		case TAT_SECT_THERM_PREVIEW: {
			ThermAniRowPreview row = (ThermAniRowPreview)indexPath.row;
			switch (row) {
				case TAT_ROW_THERM_PREVIEW: {
					_temperatureCell = [[ThermAniTestCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
					_temperatureCell.leftLabel.text = [NSString stringWithFormat:@"%@ ℃", [BattmanPrefs.sharedPrefs stringForKey:@kBattmanPrefs_THERM_UI_MIN]];
					_temperatureCell.rightLabel.text = [NSString stringWithFormat:@"%@ ℃", [BattmanPrefs.sharedPrefs stringForKey:@kBattmanPrefs_THERM_UI_MAX]];
					[_temperatureCell.arcView rotatePointerToPercentage:get_current_temp_percentage()];
					cell = (UITableViewCell *)_temperatureCell;
					break;
				}
				default: break;
			}
			break;
		}
		case TAT_SECT_COUNT: break;
	}

	return cell;
}

- (void)thermometerStepperValueChanged:(UITextFieldStepper *)sender {
	// Prevent recursive calls when we update the other stepper
	if (self.isUpdatingThermometerValues) {
		return;
	}

	UITableViewCell *cell = find_cell(sender);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for UITextFieldStepper %@", sender);
		return;
	}
	
	self.isUpdatingThermometerValues = YES;
	
	// Get current values from both steppers
	double minValue = self.thermMinStepper ? self.thermMinStepper.value : -50;
	double maxValue = self.thermMaxStepper ? self.thermMaxStepper.value : 140;
	
	// Validate and adjust values to prevent min > max
	if (sender.tag == TAT_ROW_THERM_RANGE_MIN) {
		if (sender.value >= maxValue && sender.value < 140) {
			self.thermMaxStepper.value = sender.value + 1;
			[BattmanPrefs.sharedPrefs setInteger:(int)self.thermMaxStepper.value forKey:@kBattmanPrefs_THERM_UI_MAX];
		}
	} else if (sender.tag == TAT_ROW_THERM_RANGE_MAX) {
		if (sender.value <= minValue && sender.value > -50) {
			self.thermMinStepper.value = sender.value - 1;
			[BattmanPrefs.sharedPrefs setInteger:(int)self.thermMinStepper.value forKey:@kBattmanPrefs_THERM_UI_MIN];
		}
	}
	
	// Save the validated value to preferences
	[BattmanPrefs.sharedPrefs setValue:@(sender.value) forTableView:self.tableView indexPath:indexPath];
	[BattmanPrefs.sharedPrefs synchronize];
	dispatch_async(dispatch_get_main_queue(), ^{
		// XXX: consider use NSRange instead
		NSInteger minTemp = [BattmanPrefs.sharedPrefs integerForKey:@kBattmanPrefs_THERM_UI_MIN];
		NSInteger maxTemp = [BattmanPrefs.sharedPrefs integerForKey:@kBattmanPrefs_THERM_UI_MAX];
		self.temperatureCell.leftLabel.text = [NSString stringWithFormat:@"%ld ℃", (long)minTemp];
		self.temperatureCell.rightLabel.text = [NSString stringWithFormat:@"%ld ℃", (long)maxTemp];
	});
	[self.temperatureCell.arcView rotatePointerToPercentage:get_current_temp_percentage()];

	self.isUpdatingThermometerValues = NO;
}

@end
