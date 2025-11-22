//
//  CardProgressView.m
//  Battman
//
//  Created by Torrekie on 2025/11/19.
//

#import "ObjCExt/UIColor+compat.h"
#import "ObjCExt/CALayer+smoothCorners.h"
#import "CardProgressView.h"

#pragma mark - CardProgressIndicator

@implementation CardProgressIndicator

+ (instancetype)indicatorWithName:(NSString *)name value:(CGFloat)value color:(UIColor *)color {
    CardProgressIndicator *indicator = [[self alloc] init];
    indicator.name = name;
    indicator.value = value;
    indicator.color = color;
    return indicator;
}

@end

#pragma mark - CardProgressView

@interface CardProgressView ()

@property (nonatomic, strong) UILabel *minLabel;
@property (nonatomic, strong) UILabel *maxLabel;
@property (nonatomic, strong) UIView *progressView;
@property (nonatomic, strong) UIView *progressTrackView;
@property (nonatomic, strong) UIView *progressFillView;
@property (nonatomic, strong) NSMutableArray<UIView *> *indicatorMarkers;
@property (nonatomic, strong) NSMutableArray<UILabel *> *indicatorLabels;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *indicatorMarkerConstraints;
@property (nonatomic, strong) NSLayoutConstraint *progressFillWidthConstraint;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *progressFullWidthConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *progressBetweenMinMaxConstraints;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *indicatorLabelConstraints;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *indicatorLabelTopConstraints;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *indicatorLabelLeadingConstraints;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *indicatorCenterXConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *minMaxBelowConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *minMaxSideConstraints;
@property (nonatomic, strong) NSLayoutConstraint *bottomConstraint;
@property (nonatomic, assign) CGRect lastKnownBounds;
@property (nonatomic, strong) NSMutableArray<UIStackView *> *indicatorRowStacks;

@end

@implementation CardProgressView

- (instancetype)initWithTitle:(nullable NSString *)title minValue:(CGFloat)minValue maxValue:(CGFloat)maxValue majorProgress:(CGFloat)majorProgress {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _title = [title copy];
        _minValue = minValue;
        _maxValue = maxValue;
        _majorProgress = majorProgress;
        _indicators = @[];
        _indicatorMarkers = [NSMutableArray array];
        _indicatorLabels = [NSMutableArray array];
        _indicatorMarkerConstraints = [NSMutableArray array];
        _indicatorLabelConstraints = [NSMutableArray array];
        _indicatorLabelTopConstraints = [NSMutableArray array];
        _indicatorLabelLeadingConstraints = [NSMutableArray array];
        _indicatorCenterXConstraints = [NSMutableArray array];
        _lastKnownBounds = CGRectZero;
        _indicatorRowStacks = [NSMutableArray array];
		_majorProgressColor = [UIColor compatBlueColor];
        
        [self _setupViews];
        [self _setupConstraints];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithTitle:nil minValue:0 maxValue:100 majorProgress:0];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _minValue = 0;
        _maxValue = 100;
        _majorProgress = 0;
        _indicators = @[];
        _indicatorMarkers = [NSMutableArray array];
        _indicatorLabels = [NSMutableArray array];
        _indicatorMarkerConstraints = [NSMutableArray array];
        _indicatorLabelConstraints = [NSMutableArray array];
        _indicatorLabelTopConstraints = [NSMutableArray array];
        _indicatorLabelLeadingConstraints = [NSMutableArray array];
        _indicatorCenterXConstraints = [NSMutableArray array];
        _lastKnownBounds = CGRectZero;
		_majorProgressColor = [UIColor compatBlueColor];
        
        [self _setupViews];
        [self _setupConstraints];
    }
    return self;
}

- (void)_setupViews {
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
	self.titleLabel.textColor = [UIColor compatSecondaryLabelColor];
    self.titleLabel.text = self.title;
    self.titleLabel.numberOfLines = 1;
    [self.titleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [self addSubview:self.titleLabel];

	self.progressView = [[UIView alloc] init];
	self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
	self.progressView.layer.shadowColor = [UIColor blackColor].CGColor;
	self.progressView.layer.shadowOpacity = 0.12;
	self.progressView.layer.shadowRadius = 3;
	[self.progressView.layer setSmoothCorners:YES];
	self.progressView.layer.shadowOffset = CGSizeMake(0, 1);
	[self addSubview:self.progressView];

	self.progressTrackView = [[UIView alloc] init];
	self.progressTrackView.translatesAutoresizingMaskIntoConstraints = NO;
	self.progressTrackView.backgroundColor = [UIColor tertiaryCompatFillColor];
	self.progressTrackView.layer.cornerRadius = 5;
	[self.progressTrackView.layer setSmoothCorners:YES];
	self.progressTrackView.clipsToBounds = YES;
	[self.progressView addSubview:self.progressTrackView];

    self.progressFillView = [[UIView alloc] init];
    self.progressFillView.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFillView.backgroundColor = self.majorProgressColor;
    [self.progressTrackView addSubview:self.progressFillView];
	
    self.minLabel = [[UILabel alloc] init];
    self.minLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.minLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.minLabel.textColor = [UIColor compatLabelColor];
    self.minLabel.text = [self _formatValue:self.minValue];
    [self addSubview:self.minLabel];
    
    self.maxLabel = [[UILabel alloc] init];
    self.maxLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.maxLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    self.maxLabel.textColor = [UIColor compatLabelColor];
    self.maxLabel.textAlignment = NSTextAlignmentRight;
    self.maxLabel.text = [self _formatValue:self.maxValue];
    [self addSubview:self.maxLabel];
}

- (void)_setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [self.progressView.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.progressView.heightAnchor constraintEqualToConstant:16],

        [self.progressTrackView.topAnchor constraintEqualToAnchor:self.progressView.topAnchor],
		[self.progressTrackView.leadingAnchor constraintEqualToAnchor:self.progressView.leadingAnchor],
		[self.progressTrackView.trailingAnchor constraintEqualToAnchor:self.progressView.trailingAnchor],
		[self.progressTrackView.heightAnchor constraintEqualToAnchor:self.progressView.heightAnchor],
		[self.progressFillView.topAnchor constraintEqualToAnchor:self.progressTrackView.topAnchor],
        [self.progressFillView.leadingAnchor constraintEqualToAnchor:self.progressTrackView.leadingAnchor],
        [self.progressFillView.bottomAnchor constraintEqualToAnchor:self.progressTrackView.bottomAnchor],
    ]];

    NSLayoutConstraint *progressLeadingFull = [self.progressView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
    NSLayoutConstraint *progressTrailingFull = [self.progressView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor];
    self.progressFullWidthConstraints = @[progressLeadingFull, progressTrailingFull];

    CGFloat sidePadding = 8.0;
    NSLayoutConstraint *progressLeadingBetween = [self.progressView.leadingAnchor constraintEqualToAnchor:self.minLabel.trailingAnchor constant:sidePadding];
    NSLayoutConstraint *progressTrailingBetween = [self.progressView.trailingAnchor constraintEqualToAnchor:self.maxLabel.leadingAnchor constant:-sidePadding];
    self.progressBetweenMinMaxConstraints = @[progressLeadingBetween, progressTrailingBetween];

	NSLayoutConstraint *minBelowTop = [self.minLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:4];
	NSLayoutConstraint *minBelowLeading = [self.minLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
	NSLayoutConstraint *maxBelowTop = [self.maxLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:4];
	NSLayoutConstraint *maxBelowTrailing = [self.maxLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor];
	self.minMaxBelowConstraints = @[minBelowTop, minBelowLeading, maxBelowTop, maxBelowTrailing];

	NSLayoutConstraint *minSideCenterY = [self.minLabel.centerYAnchor constraintEqualToAnchor:self.progressTrackView.centerYAnchor];
	NSLayoutConstraint *minSideLeading = [self.minLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
	NSLayoutConstraint *maxSideCenterY = [self.maxLabel.centerYAnchor constraintEqualToAnchor:self.progressTrackView.centerYAnchor];
	NSLayoutConstraint *maxSideTrailing = [self.maxLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor];
	self.minMaxSideConstraints = @[minSideCenterY, minSideLeading, maxSideCenterY, maxSideTrailing];

	[self _updateMinMaxLayoutForCurrentTraits];
    [self _updateProgressFill];
}

- (void)_updateProgressFill {
    CGFloat normalizedProgress = [self _normalizeValue:self.majorProgress];
    
    // Remove existing width constraint if it exists
    if (self.progressFillWidthConstraint) {
        self.progressFillWidthConstraint.active = NO;
        self.progressFillWidthConstraint = nil;
    }
    
    // Create new width constraint
    self.progressFillWidthConstraint = [self.progressFillView.widthAnchor 
        constraintEqualToAnchor:self.progressTrackView.widthAnchor 
        multiplier:normalizedProgress];
    self.progressFillWidthConstraint.active = YES;
}

- (void)_updateIndicators {
    // Remove existing constraints first
    if (self.bottomConstraint) {
        self.bottomConstraint.active = NO;
        self.bottomConstraint = nil;
    }
	for (NSLayoutConstraint *c in self.indicatorMarkerConstraints) c.active = NO;
	[self.indicatorMarkerConstraints removeAllObjects];
	for (NSLayoutConstraint *c in self.indicatorLabelConstraints) c.active = NO;
	[self.indicatorLabelConstraints removeAllObjects];
	for (NSLayoutConstraint *c in self.indicatorLabelTopConstraints) c.active = NO;
	[self.indicatorLabelTopConstraints removeAllObjects];
	for (NSLayoutConstraint *c in self.indicatorLabelLeadingConstraints) c.active = NO;
	[self.indicatorLabelLeadingConstraints removeAllObjects];
	for (NSLayoutConstraint *c in self.indicatorCenterXConstraints) c.active = NO;
	[self.indicatorCenterXConstraints removeAllObjects];

    for (UIStackView *row in self.indicatorRowStacks) {
        [row removeFromSuperview];
    }
    [self.indicatorRowStacks removeAllObjects];

    // Remove existing indicator views
    for (UIView *marker in self.indicatorMarkers) {
        [marker removeFromSuperview];
    }
    for (UILabel *label in self.indicatorLabels) {
        [label removeFromSuperview];
    }
    [self.indicatorMarkers removeAllObjects];
    [self.indicatorLabels removeAllObjects];
    
    // Add label for major progress if it has a name
    if (self.majorProgressName) {
        UILabel *majorLabel = [[UILabel alloc] init];
        majorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        majorLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        majorLabel.textAlignment = NSTextAlignmentLeft;

        NSString *valueStr = [self _formatValue:self.majorProgress];
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];

        NSAttributedString *bullet = [[NSAttributedString alloc] initWithString:@"● " attributes:@{
            NSForegroundColorAttributeName: self.majorProgressColor,
            NSFontAttributeName: [UIFont systemFontOfSize:13]
        }];
        [attributedText appendAttributedString:bullet];

        NSAttributedString *text = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %@", self.majorProgressName, valueStr] attributes:@{
			NSForegroundColorAttributeName: [UIColor compatLabelColor],
            NSFontAttributeName: [UIFont systemFontOfSize:13]
        }];
        [attributedText appendAttributedString:text];
        
        majorLabel.attributedText = attributedText;
        [self addSubview:majorLabel];
        [self.indicatorLabels addObject:majorLabel];
    }
    
    // Create new indicator views
    for (CardProgressIndicator *indicator in self.indicators) {
        UIView *marker = [[UIView alloc] init];
        marker.translatesAutoresizingMaskIntoConstraints = NO;
        marker.backgroundColor = indicator.color;
        [self.progressTrackView addSubview:marker];
        [self.indicatorMarkers addObject:marker];

        NSLayoutConstraint *leadingConstraint = [marker.leadingAnchor constraintEqualToAnchor:self.progressTrackView.leadingAnchor constant:0];
        [self.indicatorMarkerConstraints addObject:leadingConstraint];

		[NSLayoutConstraint activateConstraints:@[
			leadingConstraint,
			[marker.topAnchor constraintEqualToAnchor:self.progressTrackView.topAnchor],
			[marker.bottomAnchor constraintEqualToAnchor:self.progressTrackView.bottomAnchor],
			[marker.widthAnchor constraintEqualToConstant:2.5],
		]];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        label.textColor = indicator.color;
        label.textAlignment = NSTextAlignmentLeft;

        NSString *valueStr = [self _formatValue:indicator.value];
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] init];
        
        NSAttributedString *bullet = [[NSAttributedString alloc] initWithString:@"● " attributes:@{
            NSForegroundColorAttributeName: indicator.color,
            NSFontAttributeName: [UIFont systemFontOfSize:13]
        }];
        [attributedText appendAttributedString:bullet];

        NSAttributedString *text = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %@", indicator.name, valueStr] attributes:@{
            NSForegroundColorAttributeName: [UIColor compatLabelColor],
            NSFontAttributeName: [UIFont systemFontOfSize:13]
        }];
        [attributedText appendAttributedString:text];
        
        label.attributedText = attributedText;
        [self addSubview:label];
        [self.indicatorLabels addObject:label];
    }

    [self _layoutIndicatorLabels];
}

// Lays out indicator labels in rows using UIStackView so that labels in each
// row are evenly distributed across the available width. This keeps the layout
// stable while better utilizing horizontal space.
- (void)_layoutIndicatorLabels {
    // Clear previous label constraints
    for (NSLayoutConstraint *c in self.indicatorLabelConstraints) c.active = NO;
    [self.indicatorLabelConstraints removeAllObjects];

    // Remove previous row stack views
    for (UIStackView *row in self.indicatorRowStacks)
        [row removeFromSuperview];

    [self.indicatorRowStacks removeAllObjects];

    if (self.bottomConstraint) {
        self.bottomConstraint.active = NO;
        self.bottomConstraint = nil;
    }

    if (self.indicatorLabels.count == 0) {
        // No indicators, so bottom is anchored to min/max labels
        self.bottomConstraint = [self.bottomAnchor constraintEqualToAnchor:self.minLabel.bottomAnchor];
        self.bottomConstraint.active = YES;
        return;
    }

    // Decide how many labels per row based on vertical size class.
    // Portrait (regular vertical): up to 2 columns.
    // Landscape (compact vertical): up to 4 columns.
	// XXX: Make this more dynamic
    BOOL isCompactVertical = (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact);
    NSInteger maxPerRow = isCompactVertical ? 4 : 2;
    NSInteger labelsPerRow = MIN(MAX(1, self.indicatorLabels.count), maxPerRow);

    CGFloat topOffset = 8.0;   // Space below min/max labels
    CGFloat rowSpacing = 24.0;  // Vertical spacing between rows
    CGFloat columnSpacing = 12.0;

    NSInteger total = self.indicatorLabels.count;
    NSInteger rowCount = (total + labelsPerRow - 1) / labelsPerRow;

    UIStackView *lastRowStack = nil;

    for (NSInteger row = 0; row < rowCount; row++) {
        NSInteger startIndex = row * labelsPerRow;
        NSInteger endIndex = MIN(startIndex + labelsPerRow, total);

        UIStackView *rowStack = [[UIStackView alloc] initWithArrangedSubviews:@[]];
        rowStack.axis = UILayoutConstraintAxisHorizontal;
        rowStack.alignment = UIStackViewAlignmentFill;
        rowStack.distribution = UIStackViewDistributionFillEqually;
        rowStack.spacing = columnSpacing;
        rowStack.translatesAutoresizingMaskIntoConstraints = NO;

        for (NSInteger i = startIndex; i < endIndex; i++) {
            UILabel *label = self.indicatorLabels[i];
            [rowStack addArrangedSubview:label];
        }

        [self addSubview:rowStack];
        [self.indicatorRowStacks addObject:rowStack];

        NSLayoutConstraint *top = [rowStack.topAnchor constraintEqualToAnchor:self.minLabel.bottomAnchor constant:(topOffset + row * rowSpacing)];
        NSLayoutConstraint *leading = [rowStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor];
        NSLayoutConstraint *trailing = [rowStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor];

        top.active = YES;
        leading.active = YES;
        trailing.active = YES;

        [self.indicatorLabelConstraints addObject:top];
        [self.indicatorLabelConstraints addObject:leading];
        [self.indicatorLabelConstraints addObject:trailing];

        lastRowStack = rowStack;
    }

    if (lastRowStack) {
        self.bottomConstraint = [self.bottomAnchor constraintEqualToAnchor:lastRowStack.bottomAnchor];
        self.bottomConstraint.active = YES;
    }
}



- (void)layoutSubviews {
    [super layoutSubviews];

    if (!CGRectEqualToRect(self.bounds, self.lastKnownBounds)) {
        self.lastKnownBounds = self.bounds;
        [self _layoutIndicatorLabels];
        [self _updateMinMaxLayoutForCurrentTraits];
    }

    for (NSInteger i = 0; i < self.indicators.count && i < self.indicatorMarkerConstraints.count; i++) {
        CardProgressIndicator *indicator = self.indicators[i];
        NSLayoutConstraint *leadingConstraint = self.indicatorMarkerConstraints[i];

        CGFloat normalizedValue = [self _normalizeValue:indicator.value];
        CGFloat xPosition = normalizedValue * self.progressTrackView.bounds.size.width;

        leadingConstraint.constant = xPosition;
    }

    [self _updateProgressFill];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    BOOL verticalChanged = self.traitCollection.verticalSizeClass != previousTraitCollection.verticalSizeClass;
    BOOL horizontalChanged = self.traitCollection.horizontalSizeClass != previousTraitCollection.horizontalSizeClass;

    if (verticalChanged || horizontalChanged) {
        [self _updateMinMaxLayoutForCurrentTraits];
        [self _layoutIndicatorLabels];
    }
}

- (BOOL)_shouldPlaceMinMaxAlongSides {
    UITraitCollection *traits = self.traitCollection;
    BOOL wideHorizontal = traits.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    BOOL compactVertical = traits.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    return wideHorizontal || compactVertical;
}

- (void)_updateMinMaxLayoutForCurrentTraits {
    if (!self.minMaxBelowConstraints || !self.minMaxSideConstraints) {
        return;
    }

    [NSLayoutConstraint deactivateConstraints:self.minMaxBelowConstraints];
    [NSLayoutConstraint deactivateConstraints:self.minMaxSideConstraints];
    if (self.progressFullWidthConstraints) {
        [NSLayoutConstraint deactivateConstraints:self.progressFullWidthConstraints];
    }
    if (self.progressBetweenMinMaxConstraints) {
        [NSLayoutConstraint deactivateConstraints:self.progressBetweenMinMaxConstraints];
    }

    BOOL placeAlongSides = [self _shouldPlaceMinMaxAlongSides];

    if (placeAlongSides) {
        [NSLayoutConstraint activateConstraints:self.minMaxSideConstraints];
        if (self.progressBetweenMinMaxConstraints) {
            [NSLayoutConstraint activateConstraints:self.progressBetweenMinMaxConstraints];
        }
    } else {
        [NSLayoutConstraint activateConstraints:self.minMaxBelowConstraints];
        if (self.progressFullWidthConstraints) {
            [NSLayoutConstraint activateConstraints:self.progressFullWidthConstraints];
        }
    }
}

#pragma mark - Layout Helper Methods

- (NSInteger)_calculateOptimalColumnsForWidth:(CGFloat)availableWidth {
    if (self.indicatorLabels.count == 0) return 1;

    CGFloat maxLabelWidth = 0;
    for (UILabel *label in self.indicatorLabels) {
        CGSize labelSize = [label.attributedText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil].size;
        maxLabelWidth = MAX(maxLabelWidth, labelSize.width);
    }
    
    CGFloat columnSpacing = 12;
    CGFloat effectiveWidth = availableWidth - 40;
    
    NSInteger maxPossibleColumns = (NSInteger)floor((effectiveWidth + columnSpacing) / (maxLabelWidth + columnSpacing));
    
    NSInteger optimalColumns = MAX(1, MIN(maxPossibleColumns, 4));
    
    optimalColumns = MIN(optimalColumns, self.indicatorLabels.count);
    
    return optimalColumns;
}

- (void)_relayoutIndicatorLabelsForBoundsChange {
    if (self.indicatorLabels.count == 0) return;
    
    if (self.bottomConstraint) {
        self.bottomConstraint.active = NO;
        self.bottomConstraint = nil;
    }
    for (NSLayoutConstraint *constraint in self.indicatorLabelConstraints) constraint.active = NO;

    [self.indicatorLabelConstraints removeAllObjects];
    [self _layoutIndicatorLabels];
}

#pragma mark - Helper Methods

- (CGFloat)_normalizeValue:(CGFloat)value {
    if (self.maxValue == self.minValue) return 0.0;
    CGFloat normalized = (value - self.minValue) / (self.maxValue - self.minValue);
    return MAX(0.0, MIN(1.0, normalized));
}

- (NSString *)_formatValue:(CGFloat)value {
    if (value == (NSInteger)value) {
        return [NSString stringWithFormat:@"%.0f", value];
    } else if (fabs(value) >= 1000) {
        return [NSString stringWithFormat:@"%.0f", value];
    } else if (fabs(value) >= 100) {
        return [NSString stringWithFormat:@"%.1f", value];
    } else {
        return [NSString stringWithFormat:@"%.4g", value];
    }
}

#pragma mark - Property Setters

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    self.titleLabel.text = title;
}

- (void)setMinValue:(CGFloat)minValue {
    _minValue = minValue;
    self.minLabel.text = [self _formatValue:minValue];
    [self _updateProgressFill];
    [self _updateIndicators];
}

- (void)setMaxValue:(CGFloat)maxValue {
    _maxValue = maxValue;
    self.maxLabel.text = [self _formatValue:maxValue];
    [self _updateProgressFill];
    [self _updateIndicators];
}

- (void)setMajorProgress:(CGFloat)majorProgress {
    _majorProgress = majorProgress;
    [self _updateProgressFill];
    [self _updateIndicators];
}

- (void)setMajorProgressName:(NSString *)majorProgressName {
    _majorProgressName = [majorProgressName copy];
    [self _updateIndicators];
}

- (void)setMajorProgressColor:(UIColor *)majorProgressColor {
    _majorProgressColor = majorProgressColor;
    self.progressFillView.backgroundColor = majorProgressColor;
    [self _updateIndicators];
}

- (void)setIndicators:(NSArray<CardProgressIndicator *> *)indicators {
    _indicators = indicators;
    [self _updateIndicators];
}

@end
