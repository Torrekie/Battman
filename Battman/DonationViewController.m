//
//  DonationViewController.m
//  Battman
//
//  Created by Torrekie on 2025/8/10.
//

#import "ObjCExt/CALayer+smoothCorners.h"
#import "ObjCExt/UIColor+compat.h"
#import "DonationViewController.h"
#import "DonationPrompter.h"
#import "CGIconSet/BattmanVectorIcon.h"
#include "common.h"
#include "intlextern.h"
#import <MessageUI/MessageUI.h>

@interface DonationViewController () <MFMailComposeViewControllerDelegate>
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UIButton *bottomButton;
@property (nonatomic, strong) NSArray *donateButtons;
@property (nonatomic, strong) NSString *selectedDonate;
@property (nonatomic, strong) NSArray *donates;
@property (assign) BOOL manual;
@end

@implementation DonationViewController

- (NSString *)title {
	return _("Support Us");
}

- (instancetype)initWithFlag:(BOOL)manual {
	self = [super init];
	if (self) {
		_manual = manual;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	_donates = @[_("Patreon"), @"https://patreon.com/Torrekie", _("Afdian"), @"https://afdian.com/a/Torrekie", _("UniFans"), @"https://app.unifans.io/c/torrekie"];
	
	UIBarButtonSystemItem button = UIBarButtonSystemItemCancel;
	if (@available(iOS 13.0, *)) {
		[self setModalInPresentation:YES];
		button = UIBarButtonSystemItemClose;
	}
	self.view.backgroundColor = [UIColor compatBackgroundColor];
	
	// Close button
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:button target:self action:@selector(dismissSelf)];
	
	UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
	scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	scrollView.alwaysBounceVertical = YES;
	[self.view addSubview:scrollView];

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(1024, 1024), NO, 0);
	// Consider inline
	[BattmanVectorIcon drawBattman];
	self.icon = [[UIImageView alloc] initWithImage:UIGraphicsGetImageFromCurrentImageContext()];
	UIGraphicsEndImageContext();
	self.icon.contentMode = UIViewContentModeScaleAspectFit;
	self.icon.userInteractionEnabled = YES;
	[self.icon.layer setCornerRadius:120.0f * 0.225]; // App Store uses 22.5%
	[self.icon.layer setSmoothCorners:YES];
	
	// "Vivid" animations when tapping our icon
	self.icon.translatesAutoresizingMaskIntoConstraints = NO;
	[self.icon setClipsToBounds:YES];
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapImage:)];
	[self.icon addGestureRecognizer:tap];
	
	UIView *imageContainer = [[UIView alloc] init];
	imageContainer.translatesAutoresizingMaskIntoConstraints = NO;
	[imageContainer.heightAnchor constraintEqualToConstant:120].active = YES;
	
	[imageContainer addSubview:self.icon];
	[NSLayoutConstraint activateConstraints:@[
		[self.icon.centerXAnchor constraintEqualToAnchor:imageContainer.centerXAnchor],
		[self.icon.centerYAnchor constraintEqualToAnchor:imageContainer.centerYAnchor],
		[self.icon.heightAnchor constraintEqualToAnchor:imageContainer.heightAnchor],
		[self.icon.widthAnchor constraintEqualToAnchor:imageContainer.heightAnchor]
	]];
	
	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.text = _("Support Battman");
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	
	UILabel *subtitle = [[UILabel alloc] init];
	subtitle.text = _("If Battman saved you time or made your day easier, please consider a small donation. Even a few dollars make a real difference and help me keep adding improvements (also helps my living).");
	subtitle.numberOfLines = 0;
	subtitle.font = [UIFont systemFontOfSize:14];
	subtitle.translatesAutoresizingMaskIntoConstraints = NO;
	
	UILabel *note = [[UILabel alloc] init];
	// TODO: Check if manually triggered
	note.text = (_manual || donation_shown()) ? _("You can at least get Battman early accesses by donating us 🥺") : _("Don't worry about annoyance, this page only popup itself for once 🥺");
	note.numberOfLines = 0;
	note.textAlignment = NSTextAlignmentCenter;
	note.font = [UIFont systemFontOfSize:10];
	note.translatesAutoresizingMaskIntoConstraints = NO;

	UILabel *issuetitle = [[UILabel alloc] init];
	issuetitle.text = _("Having Problems?");
	issuetitle.numberOfLines = 0;
	issuetitle.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
	issuetitle.translatesAutoresizingMaskIntoConstraints = NO;
	
	UILabel *issuetext = [[UILabel alloc] init];
	issuetext.text = _("We'd love to hear from you! Let us know if you find any bugs or have suggestions to make things better.");
	issuetext.numberOfLines = 0;
	issuetext.font = [UIFont systemFontOfSize:14];
	issuetext.translatesAutoresizingMaskIntoConstraints = NO;
	
	UIButton *report = [UIButton buttonWithType:UIButtonTypeSystem];
	report.translatesAutoresizingMaskIntoConstraints = NO;
	report.layer.cornerRadius = 12;
	[report.layer setSmoothCorners:YES];
	report.clipsToBounds = YES;
	report.contentEdgeInsets = UIEdgeInsetsMake(14, 20, 14, 20);
	report.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
	[report setTitle:_("Create a new GitHub issue") forState:UIControlStateNormal];
	report.backgroundColor = [UIColor clearColor];
	report.layer.borderWidth = 1.0;
	report.layer.borderColor = [UIColor compatGray4Color].CGColor;
	[report setTitleColor:[UIColor compatLabelColor] forState:UIControlStateNormal];
	[report addTarget:self action:@selector(issueTapped:) forControlEvents:UIControlEventTouchUpInside];
	
	UIButton *email = [UIButton buttonWithType:UIButtonTypeSystem];
	email.translatesAutoresizingMaskIntoConstraints = NO;
	email.layer.cornerRadius = 12;
	[email.layer setSmoothCorners:YES];
	email.clipsToBounds = YES;
	email.contentEdgeInsets = UIEdgeInsetsMake(14, 20, 14, 20);
	email.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
	[email setTitle:_("Send an Email") forState:UIControlStateNormal];
	email.backgroundColor = [UIColor clearColor];
	email.layer.borderWidth = 1.0;
	email.layer.borderColor = [UIColor compatGray4Color].CGColor;
	[email setTitleColor:[UIColor compatLabelColor] forState:UIControlStateNormal];
	[email addTarget:self action:@selector(emailTapped:) forControlEvents:UIControlEventTouchUpInside];
	
	NSMutableArray *btns = [NSMutableArray arrayWithCapacity:_donates.count / 2];
	UIStackView *donationStack = [[UIStackView alloc] init];
	donationStack.axis = UILayoutConstraintAxisHorizontal;
	donationStack.distribution = UIStackViewDistributionFillEqually;
	donationStack.spacing = 12;
	donationStack.translatesAutoresizingMaskIntoConstraints = NO;
	for (CFIndex i = 0; i < _donates.count / 2; i++) {
		UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
		b.layer.cornerRadius = 10;
		b.layer.borderWidth = 1.0;
		b.layer.borderColor = [UIColor compatGray4Color].CGColor;
		[b setTitleColor:[UIColor compatLabelColor] forState:UIControlStateNormal];

		[b.layer setSmoothCorners:YES];
		
		b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
		[b setTitle:_donates[i * 2] forState:UIControlStateNormal];
		b.translatesAutoresizingMaskIntoConstraints = NO;
		[b addTarget:self action:@selector(donateTapped:) forControlEvents:UIControlEventTouchUpInside];
		[btns addObject:b];
		[donationStack addArrangedSubview:b];
	}
	self.donateButtons = btns;
	
	// Donate button (big pill)
	UIButton *donate = [UIButton buttonWithType:UIButtonTypeSystem];
	donate.translatesAutoresizingMaskIntoConstraints = NO;
	donate.layer.cornerRadius = 12;
	[donate.layer setSmoothCorners:YES];
	donate.clipsToBounds = YES;
	donate.contentEdgeInsets = UIEdgeInsetsMake(14, 20, 14, 20);
	donate.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
	[donate setTitle:_("No, thanks") forState:UIControlStateNormal];
	donate.backgroundColor = [UIColor compatRedColor];
	[donate setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[donate addTarget:self action:@selector(bottomTapped:) forControlEvents:UIControlEventTouchUpInside];
	self.bottomButton = donate;
	
	// Layout container
	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[imageContainer, titleLabel, subtitle, donationStack, note, issuetitle, issuetext, report, email]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 16;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[scrollView addSubview:stack];
	[self.view addSubview:donate];
	
	UILayoutGuide *g = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		// scrollView anchors
		[scrollView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
		[scrollView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
		[scrollView.topAnchor constraintEqualToAnchor:g.topAnchor],
		// bottom of scrollView is above donate button
		[scrollView.bottomAnchor constraintEqualToAnchor:donate.topAnchor constant:-12],
		
		// stack inside scrollView contentLayoutGuide
		[stack.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor constant:24],
		[stack.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor constant:20],
		[stack.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor constant:-20],
		[stack.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor constant:-12],
		
		// ensure stack width is tied to visible scroll view width (so arranged subviews get a width)
		[stack.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor constant:-40],
		
		[donationStack.heightAnchor constraintEqualToConstant:44],
		
		// donate button pinned to bottom
		[donate.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
		[donate.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
		[donate.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-24],
		[donate.heightAnchor constraintGreaterThanOrEqualToConstant:50]
	]];
}

- (void)selectDonate:(UIButton *)selected link:(id)link {
	for (UIButton *b in self.donateButtons) {
		b.backgroundColor = [UIColor clearColor];
	}
	selected.backgroundColor = [UIColor compatGray4Color];
	selected.layer.borderColor = [UIColor grayColor].CGColor;
	
	self.selectedDonate = link;
	NSString *donateTitle = [NSString stringWithFormat:_("Goto %@"), selected.titleLabel.text];
	[self.bottomButton setTitle:donateTitle forState:UIControlStateNormal];
}

- (void)didTapImage:(UITapGestureRecognizer *)g {
	UIImageView *img = (UIImageView *)g.view;
	
	// XXX: Add more animations?
	[self vividKeyframeRotation:img];
}

- (void)vividKeyframeRotation:(UIImageView *)imageView {
	if (!imageView) return;
	
	// remove any existing animation so we can start clean
	[imageView.layer removeAnimationForKey:@"vividKeyframeRotation"];
	
	// Random direction: +1 = forward, -1 = backward
	int dir = (arc4random_uniform(2) == 0) ? 1 : -1;
	
	// Random degrees between 60 and 1140 (inclusive)
	uint32_t minDeg = 60;
	uint32_t maxDeg = 1140; // 3*360 + 60
	uint32_t range = maxDeg - minDeg + 1;
	uint32_t deg = arc4random_uniform(range) + minDeg;
	
	// Convert to radians and apply direction
	CGFloat angle = ((CGFloat)deg * M_PI) / 180.0f;
	angle *= dir;
	
	// Duration scaling (so large rotations don't feel instant)
	CGFloat baseDuration = 0.9;
	CGFloat duration = baseDuration * sqrt((CGFloat)deg / (CGFloat)minDeg);
	duration = MAX(0.35, MIN(duration, 4.5)); // clamp to [0.35, 4.5] seconds
	
	// Disable interactions while animating
	imageView.userInteractionEnabled = NO;
	
	// Build dynamic keyframe value list
	NSMutableArray *values = [NSMutableArray arrayWithObjects:
							  @(0),
							  @(angle),                      // rotate forward/backward
							  @(-angle * 0.25),              // overshoot back a bit
							  @(angle * 0.08),               // first small rebound
							  nil];
	
	// Decide if rebound-on-rebound is necessary
	// thresholdDeg controls when we consider the rebound "too big"
	CGFloat thresholdDeg = 25.0;
	CGFloat reboundDeg = fabs((angle * 0.08) * 180.0 / M_PI);
	BOOL needsReboundOnRebound = (reboundDeg > thresholdDeg);
	
	if (needsReboundOnRebound) {
		// make a smaller opposite-direction rebound
		// factor controls how big the rebound-on-rebound is relative to the first rebound
		CGFloat secondaryFactor = 0.35; // 35% of first rebound
		NSNumber *secondRebound = @(-angle * 0.08 * secondaryFactor);
		[values addObject:secondRebound];
		
		// tiny settle forward again before final settle to zero
		NSNumber *tinySettle = @(angle * 0.02);
		[values addObject:tinySettle];
	}
	
	// final settle to identity
	[values addObject:@(0)];
	
	// Build matching keyTimes (non-linear distribution)
	// create a base timeline and then spread it across the number of keyframes.
	NSUInteger count = values.count;
	NSMutableArray *keyTimes = [NSMutableArray arrayWithCapacity:count];
	
	// A handcrafted distribution:
	// 0: start
	// ~0.45: main peak
	// ~0.75: overshoot back
	// ~0.92: first rebound
	// optionally ~0.97: second rebound/tiny settle
	// 1.0: final
	if (!needsReboundOnRebound) {
		// 5 keyframes: 0, peak, overshoot, rebound, final
		NSArray *preset = @[@0.0, @0.45, @0.75, @0.92, @1.0];
		for (NSUInteger i = 0; i < count; ++i) {
			// if counts differ (unlikely here), interpolate linearly
			CGFloat t = (i < preset.count) ? [preset[i] doubleValue] : ((double)i / (count - 1));
			[keyTimes addObject:@(t)];
		}
	} else {
		// 7 keyframes: 0, peak, overshoot, rebound, secondRebound, tinySettle, final
		NSArray *preset = @[@0.0, @0.40, @0.70, @0.86, @0.94, @0.97, @1.0];
		for (NSUInteger i = 0; i < count; ++i) {
			CGFloat t = (i < preset.count) ? [preset[i] doubleValue] : ((double)i / (count - 1));
			[keyTimes addObject:@(t)];
		}
	}
	
	// Build timing functions array sized
	NSMutableArray *timingFunctions = [NSMutableArray arrayWithCapacity:count - 1];
	for (NSUInteger i = 0; i < count - 1; ++i) {
		// choose easing per segment for a lively feel
		if (i == 0) {
			[timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
		} else if (i == count - 2) {
			[timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
		} else {
			[timingFunctions addObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
		}
	}
	
	// Create keyframe animation (I actually wish it to be function based, terrible maths)
	CAKeyframeAnimation *kf = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
	kf.values = values;
	kf.keyTimes = keyTimes;
	kf.timingFunctions = timingFunctions;
	kf.duration = duration;
	kf.fillMode = kCAFillModeRemoved;
	kf.removedOnCompletion = YES;
	kf.calculationMode = kCAAnimationCubic;
	
	// re-enable interaction when done
	[CATransaction begin];
	[CATransaction setCompletionBlock:^{
		imageView.userInteractionEnabled = YES;
	}];
	[imageView.layer addAnimation:kf forKey:@"vividKeyframeRotation"];
	[CATransaction commit];
}



- (void)donateTapped:(UIButton *)sender {
	NSUInteger idx = [self.donateButtons indexOfObject:sender];
	if (idx != NSNotFound) {
		[self selectDonate:sender link:_donates[idx * 2 + 1]];
	}
}

- (void)bottomTapped:(id)sender {
	if (self.selectedDonate) {
		// XXX: add open_url_async?
		NSURL *url = [[NSURL alloc] initWithString:self.selectedDonate];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		if (!url || ![[UIApplication sharedApplication] openURL:url]) {
			NSString *msg = [NSString stringWithFormat:_("Error when opening URL: %@"), self.selectedDonate];
			show_alert_async(L_ERR, msg.UTF8String, L_OK, ^(bool idk) {
				[self dismissViewControllerAnimated:YES completion:nil];
			});
			return;
		}
#pragma clang diagnostic pop
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)issueTapped:(UIButton *)sender {
	open_url("https://github.com/Torrekie/Battman/issues/new");
}

- (void)emailTapped:(UIButton *)sender {
	// I really don't want link against a new framework, can we just open "mailto:" url?
	if (MFMailComposeViewController.canSendMail) {
		MFMailComposeViewController *mailvc = [[MFMailComposeViewController alloc] init];
		mailvc.mailComposeDelegate = self;
		[mailvc setToRecipients:@[@"me@torrekie.dev"]];
		[mailvc setSubject:@"Battman: "];
		// TODO: Consider add some attached logs here
		[self presentViewController:mailvc animated:YES completion:nil];
	} else {
		show_alert(L_ERR, _C("Your device does not support sending Emails."), L_OK);
	}
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
	[controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissSelf {
	// XXX: Add something to show my sadness?
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
