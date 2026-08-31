#import "../ObjCExt/UIScreen+Auto.h"
#import "../ObjCExt/CALayer+smoothCorners.h"
#import "../common.h"
#import "TemperatureInfoTableViewCell.h"
#import "../GradientArcView.h"
#import "../CompatibilityHelper.h"

#include "../battery_utils/bin_display.h"
#include "../battery_utils/libsmc.h"
#include <math.h>
// Temporary ^

#import "../BattmanPrefs.h"


@interface TemperatureCellView ()
@property (nonatomic, strong) CAGradientLayer *borderGradient;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) GradientArcView *arcView;
@end

@implementation TemperatureCellView

/* Apple lied to us, CGColorCreateGenericRGB is already a thing
 */
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
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    // Handle dark mode switches
    [self updateColors];
}

- (instancetype)initWithFrame:(CGRect)frame percentage:(CGFloat)percentage {
    self = [super initWithFrame:frame];
    UIView *temperatureView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
    temperatureView.layer.cornerRadius = 30;
	[temperatureView.layer setSmoothCorners:YES];
    temperatureView.layer.masksToBounds = YES;

    self.borderGradient = [CAGradientLayer layer];
    self.borderGradient.frame = temperatureView.bounds;
    self.gradient = [CAGradientLayer layer];
    self.gradient.frame = temperatureView.bounds;

    // gradients
    self.borderGradient.startPoint = CGPointMake(0.5, 0.0);
    self.borderGradient.endPoint   = CGPointMake(0.5, 1.0);
    self.gradient.startPoint = CGPointMake(0.5, 0.0);
    self.gradient.endPoint   = CGPointMake(0.5, 1.0);

    // colors
    [self updateColors];

    // border
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    // match the same corner radius and bounds
    maskLayer.path = CGPathCreateWithRoundedRect(CGRectMake(0, 0, frame.size.width, frame.size.height), 30, 30, nil);

    // stroke only, no fill
    maskLayer.fillColor   = [UIColor clearColor].CGColor;
    maskLayer.strokeColor = [UIColor blackColor].CGColor; // the actual color doesn't matter; it's just a mask
    maskLayer.lineWidth   = 5;

    self.borderGradient.mask = maskLayer;
    [temperatureView.layer addSublayer:self.borderGradient];
    [temperatureView.layer insertSublayer:self.gradient atIndex:0];

    {
        self.arcView = [[GradientArcView alloc] initWithFrame:temperatureView.bounds];
		self.arcView.center = temperatureView.center;
        [temperatureView addSubview:self.arcView];

        [self.arcView rotatePointerToPercentage:percentage];
    }
    [self addSubview:temperatureView];
    return self;
}

- (void)updatePercentage:(CGFloat)percentage {
    [self.arcView rotatePointerToPercentage:percentage];
}

- (void)updatePercentage:(CGFloat)percentage duration:(NSTimeInterval)duration {
    [self.arcView rotatePointerToPercentage:percentage duration:duration];
}

#pragma clang diagnostic pop

@end

@interface TemperatureInfoTableViewCell ()
@property (nonatomic) dispatch_source_t timerSource;
@end

static BOOL BTTemperatureReadingIsValid(double temperature) {
	return isfinite(temperature) && temperature != -1.0 &&
	       temperature >= -50.0 && temperature <= 120.0;
}

@implementation TemperatureInfoTableViewCell

- (void)setupCellUI {
	TemperatureCellView *temperatureCell =
		[[TemperatureCellView alloc] initWithFrame:CGRectMake(0, 0, 80, 80) percentage:0.0];
	temperatureCell.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:temperatureCell];
	[temperatureCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[temperatureCell.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:20].active = 1;
	[temperatureCell.heightAnchor constraintEqualToConstant:80].active = 1;
	[temperatureCell.widthAnchor constraintEqualToAnchor:temperatureCell.heightAnchor].active = 1;
    
	UILabel *temperatureLabel = [UILabel new];
	temperatureLabel.lineBreakMode = NSLineBreakByWordWrapping;
	temperatureLabel.numberOfLines = 0;
	[self.contentView addSubview:temperatureLabel];
	temperatureLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[temperatureLabel.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-20].active = 1;
	[temperatureLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[temperatureLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.8].active = 1;
	[temperatureLabel.leftAnchor constraintEqualToAnchor:temperatureCell.rightAnchor constant:20].active = 1;

	_temperatureCell = temperatureCell;
	_temperatureLabel = temperatureLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (instancetype)init {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TITVC-ri"];
	if (self) {
		[self setupCellUI];
	}
	return self;
}

- (void)updateTemperatureInfo {
	NSString *finalText = @"";
	typedef enum {
		TEMP_BATT = (1 << 0),
		TEMP_SNSR = (1 << 1),
		TEMP_SCRN = (1 << 2),
	} tempbit;
	tempbit got_temp = 0;
	size_t cellCount = 0;
	float *btemps = get_temperature_per_cell_with_count(&cellCount);
	float batttemp = -1;
	if (btemps != NULL && cellCount > 0) {
		BOOL allCellsValid = YES;
		float total = 0.0f;
		for (size_t i = 0; i < cellCount; i++) {
			if (!battman_temperature_is_valid(btemps[i])) {
				allCellsValid = NO;
				break;
			}
			total += btemps[i];
		}
		if (allCellsValid) {
			got_temp |= TEMP_BATT;
			finalText = [NSString stringWithFormat:@"%@: %@", _("Battery Avg."), battman_temp_display_string(total / (float)cellCount)];
			// Embedded designed operating temp: 0º to 35º C
			batttemp = total / (float)cellCount;
		}
		free(btemps);
	}

	extern float getSensorAvgTemperature(void);
	float snsrtemp = getSensorAvgTemperature();
	if (BTTemperatureReadingIsValid(snsrtemp)) {
		got_temp |= TEMP_SNSR;
		if (finalText.length > 0) {
			finalText = [finalText stringByAppendingFormat:@"\n%@: %@", _("Sensors Avg."), battman_temp_display_string(snsrtemp)];
		} else {
			finalText = [NSString stringWithFormat:@"%@: %@", _("Sensors Avg."), battman_temp_display_string(snsrtemp)];
		}
	}

	// I've seen a broken screen that not reporting this, so this could also be a way to check screen sanity
	extern double iomfb_primary_screen_temperature(void);
	double scrntemp = iomfb_primary_screen_temperature();
	if (BTTemperatureReadingIsValid(scrntemp)) {
		got_temp |= TEMP_SCRN;
		if (finalText.length > 0) {
			finalText = [finalText stringByAppendingFormat:@"\n%@: %@", _("Main Screen"), battman_temp_display_string(scrntemp)];
		} else {
			finalText = [NSString stringWithFormat:@"%@: %@", _("Main Screen"), battman_temp_display_string(scrntemp)];
		}
	}

	float minVal = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_THERM_UI_MIN];
	float maxVal = [BattmanPrefs.sharedPrefs floatForKey:@kBattmanPrefs_THERM_UI_MAX];
	if (!isfinite(minVal) || minVal <= 0.0f) minVal = 0.0f;
	if (!isfinite(maxVal) || maxVal <= minVal)
		maxVal = minVal + 45.0f;

#define TEMP_TO_PERCENTAGE(x) (x > maxVal) ? 1.0 : (x < minVal ? 0.0 : (x - minVal) / (maxVal - minVal))
	
	// Cancel existing timer if any
	if (self.timerSource) {
		dispatch_source_cancel(self.timerSource);
		self.timerSource = nil;
	}
	
	if (got_temp & TEMP_BATT) {
		[self.temperatureCell updatePercentage:TEMP_TO_PERCENTAGE(batttemp)];
	} else if (got_temp & TEMP_SNSR) {
		[self.temperatureCell updatePercentage:TEMP_TO_PERCENTAGE(snsrtemp)];
	} else if (got_temp & TEMP_SCRN) {
		[self.temperatureCell updatePercentage:TEMP_TO_PERCENTAGE(scrntemp)];
	} else {
		/* A missing reading must not be disguised by the old random animation:
		 * keep the gauge neutral, stop spending a timer tick every second, and
		 * tell the user why no value is shown. */
		finalText = [NSString stringWithFormat:@"%@\n%@", _("Unavailable"), _("Temperature is unavailable because no valid hardware reading was returned.")];
		[self.temperatureCell updatePercentage:0.0];
	}

	// We need a better UI for representing temperatures ig
	self.temperatureLabel.text = finalText;
}

- (void)dealloc {
	if (self.timerSource) {
		dispatch_source_cancel(self.timerSource);
	}
}

@end
