#import "PLGraphViewTableCell.h"
#import "ObjCExt/UIColor+compat.h"

@interface UIView ()
- (CGSize)size;
- (void)setSize:(CGSize)size;
@end
@interface UILabel ()
- (void)setColor:(UIColor *)color;
@end
@interface UIColor ()
+ (instancetype)tableCellBlueTextColor;
@end

@implementation PLGraphViewTableCell

+ (int)graphHeight {
	return [PLBatteryUIMoveableGraphView graphHeight];
}
 
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self->labelColor = [UIColor compatLabelColor];
		self->graphColor = self.backgroundColor;
		self->_graphArray = nil;
		self->waitingForData = NO;
		self->graphViewDidChange = YES;
		self.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (!self->waitingForData) {
		// Always regenerate graphs on layout changes (including rotation)
		self->graphViewDidChange = YES;
		[self generateGraphs];
	}
}

#pragma mark -- PSTableCell delegate

#if USE_PREFERENCES_FRAMEWORK
- (BOOL)canReload {
	return NO;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
	return;
}

- (void)setSpecifier:(PSSpecifier *)specifier {
	[super setSpecifier:specifier];
	// BatteryUsageQueryModule not implemented yet
	// Since we are directly using the cell's view instead of loading it in PS
	if (!self.graphArray) {
		self->waitingForData = YES;
		[self addSubview:self.activityIndicator];
		[self.activityIndicator startAnimating];
		BatteryUsageQueryModule *queryModule = [BatteryUsageQueryModule sharedModule];
		queryModule.graphNames = @[@"Battery Level"];
		[queryModule populateBatteryModelsWithCompletion:^(NSDictionary *modelQuery){
			self->waitingForData = NO;
			if (modelQuery["ModelData"]) {
				self.graphArray = modelQuery["ModelData"][0]["ModelGraphArray"];
			}
			[self.activityIndicator stopAnimating];
			[self.activityIndicator removeFromSuperview];
		}];
	}
}

#endif

#pragma mark -- PLGraphViewTableCell getter/setter

- (UIScrollView *)scrollView {
	if (!self->_scrollView) {
		self->_scrollView = [[UIScrollView alloc] init];
		UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
		[self->_scrollView addGestureRecognizer:pinch];
		self->_scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	}
	return self->_scrollView;
}

- (PLBatteryUIMoveableGraphView *)graphView {
	if (!self->_graphView)
		self->_graphView = [[PLBatteryUIMoveableGraphView alloc] init];
	return self->_graphView;
}

- (UIActivityIndicatorView *)activityIndicator {
	if (!self->_activityIndicator) {
		UIActivityIndicatorViewStyle style;
#if 0
		// For some reason, this available check was not quite linted with our GitHub CI
		// using #else block as workaround
		if (@available(iOS 13.0, macOS 10.15, macCatalyst 13.0, *)) {
			style = UIActivityIndicatorViewStyleMedium;
		} else {
			// Not sure why i cannot disable warning in macCatalyst
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
			style = UIActivityIndicatorViewStyleGray;
#pragma clang diagnostic pop
		}
#else
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
		_Static_assert(UIActivityIndicatorViewStyleMedium == 100, "UIActivityIndicatorViewStyleMedium value changed by Apple! Please patch it before continue");
		_Static_assert(UIActivityIndicatorViewStyleGray == 2, "UIActivityIndicatorViewStyleGray value changed by Apple! Please patch it before continue");
		NSOperatingSystemVersion ios13 = {
			.majorVersion = 13,
			.minorVersion = 0,
			.patchVersion = 0,
		};
		if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios13]) {
			style = 100;
		} else {
			style = 2;
		}
#pragma clang diagnostic pop
#endif
		self->_activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
		[self->_activityIndicator setSize:CGSizeMake(50, 50)];
		self->_activityIndicator.center = self.center;
	}
	return self->_activityIndicator;
}

#if USE_PREFERENCES_FRAMEWORK
// not implemented yet
- (NSMutableArray *)graphArray {
	if (!self->_graphArray) {
		if (self.specifier)
			self->_graphArray = [self.specifier propertyForKey:@"GRAPH_ARRAY"];
	}
	return self->_graphArray;
}

- (void)setGraphArray:(NSMutableArray *)graphArray {
	self->_graphArray = graphArray;
	[self.specifier setProperty:self->_graphArray forKey:@"GRAPH_ARRAY"];
}
#endif

#pragma mark -- GraphView

- (void)generateGraphs {
	if (self->graphViewDidChange) {
		// Remove existing subviews to avoid duplicates on re-layout
		for (UIView *subview in [self.subviews copy]) {
			if ([subview isKindOfClass:[UILabel class]] || subview == self->_scrollView) {
				[subview removeFromSuperview];
			}
		}
		
		// Remove graph view from scroll view if it exists
		if (self->_graphView && self->_graphView.superview) {
			[self->_graphView removeFromSuperview];
		}

		UILabel *P000, *P050, *P100;

		P000 = [[UILabel alloc] init];
		P000.text = @"000%";
		P000.font = [UIFont systemFontOfSize:11.0];
		[P000 sizeToFit];
		[P000 setText:@"0%"];
		P000.textAlignment = NSTextAlignmentRight;
		[P000 setColor:self->labelColor];

		P100 = [[UILabel alloc] init];
		P100.text = @"100%";
		P100.font = [UIFont systemFontOfSize:11.0];
		[P100 sizeToFit];
		[P100 setColor:self->labelColor];

		P050 = [[UILabel alloc] init];
		P050.text = @"000%";
		P050.font = [UIFont systemFontOfSize:11.0];
		[P050 sizeToFit];
		[P050 setText:@"50%"];
		P050.textAlignment = NSTextAlignmentRight;
		[P050 setColor:self->labelColor];

		P000.frame = CGRectMake(1.0, self.frame.size.height - 40.0, P000.size.width, P000.size.height);
		P100.frame = CGRectMake(1.0, 10.0 - P100.size.height * 0.5, P100.size.width, P100.size.height);
		P050.frame = CGRectMake(1.0, (P050.size.height + P000.frame.origin.y - P100.frame.origin.y) * 0.5, P050.size.width, P050.size.height);
		
		[self addSubview:P000];
		[self addSubview:P100];
		[self addSubview:P050];

		// Update graph view frame with current cell dimensions
		CGFloat graphWidth = self.frame.size.width - 10.0 - P100.size.width;
		CGFloat graphHeight = [PLBatteryUIMoveableGraphView graphHeight] - 20;
		self.graphView.frame = CGRectMake(0.0, 0.0, graphWidth, graphHeight);
		
		// Update graph view properties
		self.graphView.inputData = self.graphArray;
		self.graphView.backgroundColor = self.backgroundColor;
		self.graphView.graphBackgroundColor = self.backgroundColor;
		self.graphView.labelColor = self->labelColor;
		self.graphView.lineColor = [UIColor tableCellBlueTextColor];
		
		// Force the graph view to recalculate its display size
		self.graphView.displaySize = CGSizeMake(graphWidth, graphHeight);
		
#if USE_PREFERENCES_FRAMEWORK
		NSString *DisplayRange = [self.specifier propertyForKey:@"DisplayRange"];
		if (DisplayRange && [DisplayRange isEqualToString:@"PLBatteryUIQueryRangeWeekKey"])
			self.graphView.displayRange = 604800.0; // 7 days in 1x frame
#endif
		
		// Update scroll view frame with current cell dimensions
		self.scrollView.frame = CGRectMake(P100.size.width + 3.0, 10.0, self.frame.size.width - 10.0 - P100.size.width - 3.0, graphHeight);
		self.scrollView.contentSize = self.graphView.size;
		[self.scrollView addSubview:self.graphView];
		[self addSubview:self.scrollView];
		
		// Maintain scroll position relative to the right edge
		CGFloat rightOffset = self.graphView.size.width - self.scrollView.frame.size.width;
		if (rightOffset > 0) {
			[self.scrollView setContentOffset:CGPointMake(rightOffset, 0.0) animated:NO];
		} else {
			[self.scrollView setContentOffset:CGPointMake(0.0, 0.0) animated:NO];
		}
		
		self->graphViewDidChange = NO;
	}
}

- (void)pinch:(UIPinchGestureRecognizer *)pinch {
	if (pinch.numberOfTouches >= 2) {
		CGFloat finger1X = [pinch locationOfTouch:0 inView:self.graphView].x;
		CGFloat finger2X = [pinch locationOfTouch:1 inView:self.graphView].x;

		// Update the display range which will trigger a frame size change in the graph view
		self.graphView.displayRange = self.graphView.displayRange / pinch.scale;
		
		// Update scroll view content size to match the new graph view size
		self.scrollView.contentSize = self.graphView.size;
		
		// Calculate the midpoint between the two fingers and maintain focus on that point
		CGFloat distance = finger1X + (finger2X - finger1X) * 0.5;
		CGFloat newOffset = (((distance / self.graphView.size.width) * self.graphView.size.width) - (distance - self.scrollView.contentOffset.x));
		
		// Ensure the offset is within valid bounds
		CGFloat maxOffset = MAX(0, self.graphView.size.width - self.scrollView.frame.size.width);
		newOffset = MAX(0, MIN(newOffset, maxOffset));
		
		[self.scrollView setContentOffset:CGPointMake(newOffset, 0.0) animated:NO];
		pinch.scale = 1.0;
	}
}

@end
