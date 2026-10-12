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

@interface PLGraphViewTableCell ()
@property (nonatomic, assign) CGSize lastGraphLayoutSize;
@property (nonatomic, assign) BOOL hasGeneratedGraph;
@property (nonatomic, assign) BOOL graphDataDidChange;
@property (nonatomic, strong) NSArray<UILabel *> *percentageLabels;
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
	if (!CGSizeEqualToSize(self.lastGraphLayoutSize, self.bounds.size))
		self->graphViewDidChange = YES;
	if (!self->waitingForData && self->graphViewDidChange)
		[self generateGraphs];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	if (@available(iOS 13.0, *)) {
		if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
			self->labelColor = [UIColor compatLabelColor];
			self->graphViewDidChange = YES;
			[self setNeedsLayout];
		}
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

- (NSMutableArray *)graphArray {
#if USE_PREFERENCES_FRAMEWORK
	if (!self->_graphArray && self.specifier)
		self->_graphArray = [self.specifier propertyForKey:@"GRAPH_ARRAY"];
#endif
	return self->_graphArray;
}

- (void)setGraphArray:(NSMutableArray *)graphArray {
	if (self->_graphArray == graphArray) return;
	self->_graphArray = graphArray;
#if USE_PREFERENCES_FRAMEWORK
	[self.specifier setProperty:self->_graphArray forKey:@"GRAPH_ARRAY"];
#endif
	self.graphDataDidChange = YES;
	self->graphViewDidChange = YES;
	[self setNeedsLayout];
}

#pragma mark -- GraphView

- (void)generateGraphs {
	if (!self->graphViewDidChange || self.bounds.size.width <= 0) return;

	// Keep the visible time, including a user's zoom range, when data or size changes.
	CGFloat oldWidth = self->_graphView.bounds.size.width;
	CGFloat oldOffset = self->_scrollView.contentOffset.x;
	CGFloat oldMaximum = MAX(0, oldWidth - self->_scrollView.bounds.size.width);
	BOOL followsLatest = !self.hasGeneratedGraph || oldOffset >= oldMaximum - 1.0;
	NSTimeInterval oldSpan = [self->_graphView.endDate timeIntervalSinceDate:self->_graphView.startDate];
	NSDate *visibleStart = oldWidth > 0 && oldSpan > 0
		? [self->_graphView.startDate dateByAddingTimeInterval:oldOffset / oldWidth * oldSpan] : nil;

	if (!self.percentageLabels) {
		NSMutableArray<UILabel *> *labels = [NSMutableArray arrayWithCapacity:3];
		for (NSString *text in @[@"0%", @"50%", @"100%"]) {
			UILabel *label = [[UILabel alloc] init];
			label.text = @"100%";
			label.font = [UIFont systemFontOfSize:11.0];
			[label sizeToFit];
			label.text = text;
			label.textAlignment = NSTextAlignmentRight;
			[self addSubview:label];
			[labels addObject:label];
		}
		self.percentageLabels = labels;
	}
	UILabel *P000 = self.percentageLabels[0];
	UILabel *P050 = self.percentageLabels[1];
	UILabel *P100 = self.percentageLabels[2];
	for (UILabel *label in self.percentageLabels) label.textColor = self->labelColor;
	P000.frame = CGRectMake(1.0, self.bounds.size.height - 40.0, P000.size.width, P000.size.height);
	P100.frame = CGRectMake(1.0, 10.0 - P100.size.height * 0.5, P100.size.width, P100.size.height);
	P050.frame = CGRectMake(1.0, (P050.size.height + P000.frame.origin.y - P100.frame.origin.y) * 0.5, P050.size.width, P050.size.height);

	CGFloat graphWidth = MAX(1, self.bounds.size.width - 10.0 - P100.size.width);
	CGFloat graphHeight = [PLBatteryUIMoveableGraphView graphHeight] - 20;
	if (self.graphDataDidChange || !self.hasGeneratedGraph) {
		self.graphView.frame = CGRectMake(0.0, 0.0, graphWidth, graphHeight);
		self.graphView.inputData = self.graphArray;
	}
	self.graphView.displaySize = CGSizeMake(graphWidth, graphHeight);
#if USE_PREFERENCES_FRAMEWORK
	NSString *displayRange = [self.specifier propertyForKey:@"DisplayRange"];
	if (!self.hasGeneratedGraph && [displayRange isEqualToString:@"PLBatteryUIQueryRangeWeekKey"])
		self.graphView.displayRange = 604800.0;
#endif
	NSTimeInterval span = [self.graphView.endDate timeIntervalSinceDate:self.graphView.startDate];
	CGFloat ratio = self.graphView.displayRange > 0 ? MAX(1, span / self.graphView.displayRange) : 1;
	self.graphView.frame = CGRectMake(0, 0, graphWidth * ratio, graphHeight);
	self.graphView.backgroundColor = self.backgroundColor;
	self.graphView.graphBackgroundColor = self.backgroundColor;
	self.graphView.labelColor = self->labelColor;
	self.graphView.lineColor = [UIColor tableCellBlueTextColor];
	[self.graphView setNeedsDisplay];

	self.scrollView.frame = CGRectMake(P100.size.width + 3.0, 10.0, MAX(1, graphWidth - 3.0), graphHeight);
	self.scrollView.contentSize = self.graphView.size;
	if (self.graphView.superview != self.scrollView) [self.scrollView addSubview:self.graphView];
	if (self.scrollView.superview != self) [self addSubview:self.scrollView];
	CGFloat maximum = MAX(0, self.graphView.bounds.size.width - self.scrollView.bounds.size.width);
	CGFloat offset = oldOffset;
	if (followsLatest) offset = maximum;
	else if (visibleStart && span > 0)
		offset = [visibleStart timeIntervalSinceDate:self.graphView.startDate] / span * self.graphView.bounds.size.width;
	CGPoint contentOffset = CGPointMake(MAX(0, MIN(offset, maximum)), 0);
	if (!CGPointEqualToPoint(self.scrollView.contentOffset, contentOffset))
		[self.scrollView setContentOffset:contentOffset animated:NO];

	self.lastGraphLayoutSize = self.bounds.size;
	self.hasGeneratedGraph = YES;
	self.graphDataDidChange = NO;
	self->graphViewDidChange = NO;
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
