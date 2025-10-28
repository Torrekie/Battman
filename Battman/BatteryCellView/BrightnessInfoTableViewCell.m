//
//  BrightnessInfoTableViewCell.m
//  Battman
//
//  Created by Torrekie on 2025/10/15.
//

#import "../GradientHDRView.h"
#import "BrightnessInfoTableViewCell.h"

@interface CALayer ()
@property (atomic, assign, readwrite) BOOL continuousCorners;
@end

@interface BrightnessCellView ()
@property (nonatomic, strong) GradientHDRView *hdrView;
@end

@implementation BrightnessCellView

- (instancetype)initWithFrame:(CGRect)frame percentage:(CGFloat)percentage {
	self = [super initWithFrame:frame];
	UIView *brightnessView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
	brightnessView.layer.cornerRadius = 30;
	if (@available(iOS 13.0, *)) {
		[brightnessView.layer setCornerCurve:kCACornerCurveContinuous];
	}
	if ([brightnessView.layer respondsToSelector:@selector(setContinuousCorners:)])
		[brightnessView.layer setContinuousCorners:YES];
	brightnessView.layer.masksToBounds = YES;

	{
		self.hdrView = [[GradientHDRView alloc] initWithFrame:brightnessView.bounds];
		self.hdrView.center = brightnessView.center;
		[brightnessView addSubview:self.hdrView];
		
		[self.hdrView setBrightness:percentage animated:YES];
	}
	[self addSubview:brightnessView];
	return self;
}

@end

@implementation BrightnessInfoTableViewCell

- (instancetype)init {
	self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BITVC-ri"];
	BrightnessCellView *brightnessCell = [[BrightnessCellView alloc] initWithFrame:CGRectMake(0, 0, 80, 80) percentage:50.0];
	brightnessCell.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:brightnessCell];
	[brightnessCell.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[brightnessCell.leftAnchor constraintEqualToAnchor:self.leftAnchor constant:20].active = 1;
	[brightnessCell.heightAnchor constraintEqualToConstant:80].active = 1;
	[brightnessCell.widthAnchor constraintEqualToAnchor:brightnessCell.heightAnchor].active = 1;

	UILabel *temperatureLabel = [UILabel new];
	temperatureLabel.lineBreakMode = NSLineBreakByWordWrapping;
	temperatureLabel.numberOfLines = 0;
	
	NSString *finalText;
	temperatureLabel.text = finalText;
	[self.contentView addSubview:temperatureLabel];
	temperatureLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[temperatureLabel.rightAnchor constraintEqualToAnchor:self.rightAnchor constant:-20].active = 1;
	[temperatureLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = 1;
	[temperatureLabel.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.8].active = 1;
	[temperatureLabel.leftAnchor constraintEqualToAnchor:brightnessCell.rightAnchor constant:20].active = 1;

	_brightnessCell = brightnessCell;
	return self;
}

@end

