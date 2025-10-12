#import "UberSegmentedControl.h"
#import "DividerView.h"
#import "SegmentButton.h"
#import "Constants.h"
#import "StackViewGestureHandler.h"
#import "UIView+Fill.h"
#import "../CompatibilityHelper.h"

// Privates
@interface CALayer ()
@property (atomic, assign) BOOL continuousCorners;
@end

@interface UberSegmentedControl () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIStackView *dividersStackView;
@property (nonatomic, strong) UIStackView *segmentsStackView;
@property (nonatomic, strong) StackViewGestureHandler *gestureHandler;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGestureRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property (nonatomic, strong) NSMapTable<SegmentButton *, id> *buttonObservers;
@property (nonatomic, strong) SegmentButton *selectionButton;
@property (nonatomic, strong) UberSegmentedControlConfig *config;

@end

@implementation UberSegmentedControl

#pragma mark - Class Properties

+ (NSInteger)noSegment {
    return -1;
}

#pragma mark - Properties

- (BOOL)allowsMultipleSelection {
    return self.config.allowsMultipleSelection;
}

- (void)setIsMomentary:(BOOL)isMomentary {
    if (_isMomentary != isMomentary) {
        _isMomentary = isMomentary;
        self.gestureHandler.isMomentary = isMomentary;
        
        if (isMomentary && self.allowsMultipleSelection) {
            self.config.allowsMultipleSelection = NO;
        }
        
        UIColor *color = isMomentary || self.allowsMultipleSelection ? self.selectedSegmentTintColor : nil;
        
        for (SegmentButton *segment in [self segments]) {
            segment.selectedBackgroundColor = color;
        }
    }
}

- (NSInteger)numberOfSegments {
    return self.segmentsStackView.arrangedSubviews.count;
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(UIViewNoIntrinsicMetric, [ConstantsMeasure segmentHeight]);
}

- (NSArray<SegmentButton *> *)segments {
    NSMutableArray<SegmentButton *> *segments = [NSMutableArray array];
    for (UIView *view in self.segmentsStackView.arrangedSubviews) {
        if ([view isKindOfClass:[SegmentButton class]]) {
            [segments addObject:(SegmentButton *)view];
        }
    }
    return segments;
}

- (UIColor *)selectedSegmentTintColor {
    return [ConstantsColor selectedSegmentTint];
}

- (NSIndexSet *)selectedSegmentIndexes {
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    NSArray<SegmentButton *> *segments = [self segments];
    
    for (NSInteger i = 0; i < segments.count; i++) {
        if (segments[i].isSelected) {
            [indexSet addIndex:i];
        }
    }
    
    return indexSet;
}
- (void)dealloc {
    // Remove any KVO observers
    NSArray *observedSegments = [self.buttonObservers keyEnumerator].allObjects;
    for (SegmentButton *segment in observedSegments) {
        @try {
            [segment removeObserver:self forKeyPath:@"highlighted"];
        } @catch (NSException *exception) {
            // Observer might not have been added
        }
    }
}
- (void)setSelectedSegmentIndexes:(NSIndexSet *)selectedSegmentIndexes {
    if (self.isMomentary) {
        return;
    }
    
    BOOL shouldDeselectOtherSegments = NO;
    
    if (selectedSegmentIndexes.count == 0) {
            if (self.selectionButton) {
                self.selectionButton.alpha = 0;
            }
        }
    
    NSArray<SegmentButton *> *segments = [self segments];
    
    for (NSInteger i = 0; i < segments.count; i++) {
        SegmentButton *segment = segments[i];
        
        if (shouldDeselectOtherSegments) {
            segment.selected = NO;
        } else {
            segment.selected = [selectedSegmentIndexes containsIndex:i];
        }
        
        if (!self.allowsMultipleSelection && segment.isSelected) {
            shouldDeselectOtherSegments = YES;
            [self updateSelectionButtonUsing:segment];
        }
    }
    
    [self updateDividers];
}

- (NSInteger)selectedSegmentIndex {
    if (self.allowsMultipleSelection) {
        return [UberSegmentedControl noSegment];
    }
    
    NSIndexSet *indexes = self.selectedSegmentIndexes;
    if (indexes.count > 0) {
        return [indexes firstIndex];
    } else {
        return [UberSegmentedControl noSegment];
    }
}

- (void)setSelectedSegmentIndex:(NSInteger)selectedSegmentIndex {
    if (self.allowsMultipleSelection ||
        selectedSegmentIndex < [UberSegmentedControl noSegment] ||
        selectedSegmentIndex >= self.numberOfSegments) {
        return;
    }
    
    if (selectedSegmentIndex == [UberSegmentedControl noSegment]) {
        self.selectedSegmentIndexes = [NSIndexSet indexSet];
    } else {
        self.selectedSegmentIndexes = [NSIndexSet indexSetWithIndex:selectedSegmentIndex];
    }
}

#pragma mark - Initialization

- (instancetype)initWithItems:(NSArray *)items config:(UberSegmentedControlConfig *)config {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        if (config) {
            _config = config;
        } else {
            _config = [[UberSegmentedControlConfig alloc] initWithFont:nil tintColor:nil allowsMultipleSelection:NO];
        }
        
        [self setup];
        
        if (items) {
            for (NSInteger idx = 0; idx < items.count; idx++) {
                id item = items[idx];
                if ([item isKindOfClass:[NSString class]]) {
                    [self insertSegmentWithTitle:item atIndex:idx animated:NO];
                } else if ([item isKindOfClass:[UIImage class]]) {
                    [self insertSegmentWithImage:item atIndex:idx animated:NO];
                }
            }
        }
    }
    return self;
}

#pragma mark - View Lifecycle

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (!self.allowsMultipleSelection && !self.isMomentary) {
        // Ensure selectionButton is setup when single selection mode is used and a segment is selected.
        if (!self.selectionButton) {
            NSIndexSet *selectedIndexes = self.selectedSegmentIndexes;
            if (selectedIndexes.count > 0) {
                NSInteger segmentIndex = [selectedIndexes firstIndex];
                SegmentButton *segment = [self segments][segmentIndex];
                
                if (segment.isSelected) {
                    [self updateSelectionButtonUsing:segment];
                }
            }
        }
    }
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    
    [self addGestureRecognizer:self.longPressGestureRecognizer];
    [self addGestureRecognizer:self.panGestureRecognizer];
    
    if (!self.allowsMultipleSelection) {
        [self.buttonObservers removeAllObjects];
        
        // Keep isHighlighted state synchronized between selectionButton and button when using
        // single selection mode.
        for (SegmentButton *segment in [self segments]) {
            // In Objective-C, we need to use the older KVO API
            // We'll track which segments we've added observers to
            [segment addObserver:self forKeyPath:@"highlighted" options:NSKeyValueObservingOptionNew context:NULL];
            [self.buttonObservers setObject:@YES forKey:segment]; // Mark that we've added an observer
        }
    }
}

- (void)removeFromSuperview {
    [super removeFromSuperview];
    
    [self removeGestureRecognizer:self.longPressGestureRecognizer];
    [self removeGestureRecognizer:self.panGestureRecognizer];
    
    // Only remove observers from segments that have them
    NSArray *observedSegments = [self.buttonObservers keyEnumerator].allObjects;
    for (SegmentButton *segment in observedSegments) {
        @try {
            [segment removeObserver:self forKeyPath:@"highlighted"];
        } @catch (NSException *exception) {
            // Observer might not have been added
        }
    }
    
    [self.buttonObservers removeAllObjects];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"highlighted"] && [object isKindOfClass:[SegmentButton class]]) {
        SegmentButton *button = (SegmentButton *)object;
        if (self.selectionButton.center.x == button.center.x && self.selectionButton.center.y == button.center.y) {
            self.selectionButton.highlighted = button.highlighted;
        }
    }
}

#pragma mark - Public Methods

- (void)insertSegmentWithTitle:(NSString *)title atIndex:(NSInteger)segment animated:(BOOL)animated {
    SegmentButton *button = [[SegmentButton alloc] initWithFont:self.config.font tintColor:self.config.tintColor];
    
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = title;
    
    [self insertSegmentWithButton:button atIndex:segment animated:animated];
}

- (void)insertSegmentWithImage:(UIImage *)image atIndex:(NSInteger)segment animated:(BOOL)animated {
    SegmentButton *button = [[SegmentButton alloc] initWithFont:self.config.font tintColor:self.config.tintColor];
    
    [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateHighlighted];
    
    [self insertSegmentWithButton:button atIndex:segment animated:animated];
}

- (void)removeSegmentAtIndex:(NSInteger)segment animated:(BOOL)animated {
    if (segment >= self.segmentsStackView.arrangedSubviews.count) {
        return;
    }
    
    UIView *view = self.segmentsStackView.arrangedSubviews[segment];
    
    if (self.dividersStackView.arrangedSubviews.count > 0) {
        UIView *dividerView = [self.dividersStackView.arrangedSubviews lastObject];
        [dividerView removeFromSuperview];
        [self.dividersStackView removeArrangedSubview:dividerView];
    }
    
    void (^onCompletion)(void) = ^{
        [view removeFromSuperview];
        [self.segmentsStackView removeArrangedSubview:view];
    };
    
    if (animated) {
        [UIView animateWithDuration:[ConstantsDuration regular] animations:^{
            view.hidden = YES;
        } completion:^(BOOL finished) {
            onCompletion();
        }];
    } else {
        onCompletion();
    }
}

- (void)removeAllSegments {
    while (self.numberOfSegments > 0) {
        [self removeSegmentAtIndex:self.numberOfSegments - 1 animated:NO];
    }
}

- (void)setTitle:(NSString *)title forSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return;
    }
    
    SegmentButton *button = [self segments][segment];
    
    [button setTitle:title forState:UIControlStateNormal];
    button.accessibilityLabel = title;
    
    [self updateSegmentInsetsFor:button];
}

- (NSString *)titleForSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return nil;
    }
    
    return [[self segments][segment] titleForState:UIControlStateNormal];
}

- (void)setImage:(UIImage *)image forSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return;
    }
    
    SegmentButton *button = [self segments][segment];
    
    [button setImage:image forState:UIControlStateNormal];
    
    [self updateSegmentInsetsFor:button];
}

- (UIImage *)imageForSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return nil;
    }
    
    return [[self segments][segment] imageForState:UIControlStateNormal];
}

- (void)setEnabled:(BOOL)enabled forSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return;
    }
    
    [self segments][segment].enabled = enabled;
}

- (BOOL)isEnabledForSegmentAtIndex:(NSInteger)segment {
    if (segment >= [self segments].count) {
        return NO;
    }
    
    return [self segments][segment].enabled;
}

- (void)setSegmentSemanticContentAttributeAtIndex:(NSInteger)segment attribute:(UISemanticContentAttribute)attribute {
    if (segment >= [self segments].count) {
        return;
    }
    
    [self segments][segment].semanticContentAttribute = attribute;
}

- (void)setSegmentImageEdgeInsetsAtIndex:(NSInteger)segment insets:(UIEdgeInsets)insets {
    if (segment >= [self segments].count) {
        return;
    }
    
    [self segments][segment].imageEdgeInsets = insets;
}

- (void)setSegmentTitleEdgeInsetsAtIndex:(NSInteger)segment insets:(UIEdgeInsets)insets {
    if (segment >= [self segments].count) {
        return;
    }
    
    [self segments][segment].titleEdgeInsets = insets;
}

#pragma mark - Private Methods

- (void)updateSegmentInsetsFor:(SegmentButton *)segment {
    if (segment.currentImage && segment.currentTitle) {
        segment.titleEdgeInsets = [ConstantsMargins titleEdgeInsets];
    } else {
        segment.titleEdgeInsets = UIEdgeInsetsZero;
    }
    
    segment.contentEdgeInsets = [self suggestedContentEdgeInsetsFor:segment];
}

- (UIEdgeInsets)suggestedContentEdgeInsetsFor:(SegmentButton *)segment {
    if (segment.currentTitle && segment.currentImage) {
        UIEdgeInsets insets = [ConstantsMargins segmentContentEdgeInsets];
        insets.right = segment.titleEdgeInsets.left - (segment.titleEdgeInsets.right * 2);
        return insets;
    } else {
        return [ConstantsMargins segmentContentEdgeInsets];
    }
}

- (void)insertSegmentWithButton:(SegmentButton *)button atIndex:(NSInteger)segment animated:(BOOL)animated {
    button.userInteractionEnabled = NO;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self updateSegmentInsetsFor:button];
    
    if (self.allowsMultipleSelection || self.isMomentary) {
        button.selectedBackgroundColor = self.selectedSegmentTintColor;
    }
    
    if (animated) {
        button.hidden = YES;
    }
    
    [self.segmentsStackView insertArrangedSubview:button atIndex:segment];
    [self.dividersStackView addArrangedSubview:[[DividerView alloc] init]];
    [self updateDividers];
    
    if (animated) {
        [UIView animateWithDuration:[ConstantsDuration regular] animations:^{
            button.hidden = NO;
        }];
    }
}

- (void)setup {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [ConstantsColor background];
    self.layer.cornerRadius = [ConstantsMeasure cornerRadius];
	if (@available(iOS 13.0, *)) {
		[self.layer setCornerCurve:kCACornerCurveContinuous];
	}
	if ([self.layer respondsToSelector:@selector(setContinuousCorners:)])
		[self.layer setContinuousCorners:YES];
    
    // Initialize stack views
    _dividersStackView = [[UIStackView alloc] init];
    _dividersStackView.axis = UILayoutConstraintAxisHorizontal;
    _dividersStackView.distribution = UIStackViewDistributionFillEqually;
    _dividersStackView.layoutMargins = [ConstantsMargins dividerInsets];
    [_dividersStackView setLayoutMarginsRelativeArrangement:YES];
    
    _segmentsStackView = [[UIStackView alloc] init];
    _segmentsStackView.axis = UILayoutConstraintAxisHorizontal;
    _segmentsStackView.distribution = UIStackViewDistributionFillEqually;
    _segmentsStackView.spacing = [ConstantsMeasure spacingBetweenSegments];
    _segmentsStackView.layoutMargins = [ConstantsMargins segmentInsets];
    [_segmentsStackView setLayoutMarginsRelativeArrangement:YES];
    
    [self fillWithView:self.dividersStackView constant:0 usingGuide:nil shouldAutoActivate:YES];
    [self fillWithView:self.segmentsStackView constant:0 usingGuide:nil shouldAutoActivate:YES];
    
    // Initialize gesture recognizers
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] init];
    _longPressGestureRecognizer.delegate = self;
    _longPressGestureRecognizer.minimumPressDuration = 0;
    [_longPressGestureRecognizer addTarget:self action:@selector(handleGestureWithRecognizer:)];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] init];
    _panGestureRecognizer.delegate = self;
    [_panGestureRecognizer addTarget:self action:@selector(handleGestureWithRecognizer:)];
    
    // Initialize gesture handler
    _gestureHandler = [[StackViewGestureHandler alloc] initWithStackView:self.segmentsStackView
                                                          tracksMultiple:self.allowsMultipleSelection
                                                             isMomentary:self.isMomentary];
    
    // Initialize button observers
    _buttonObservers = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                            valueOptions:NSPointerFunctionsStrongMemory];
}

- (void)updateDividers {
    NSArray<SegmentButton *> *buttons = [self segments];
    
    for (NSInteger idx = 0; idx < self.dividersStackView.arrangedSubviews.count; idx++) {
        UIView *separator = self.dividersStackView.arrangedSubviews[idx];
        UIButton *nextButton = nil;
        
        if (idx + 1 < self.segmentsStackView.arrangedSubviews.count) {
            nextButton = (UIButton *)self.segmentsStackView.arrangedSubviews[idx + 1];
        }
        
        if (separator == [self.dividersStackView.arrangedSubviews lastObject]) {
            separator.alpha = 0;
        } else if (buttons[idx].isSelected || nextButton.isSelected) {
            separator.alpha = 0;
        } else {
            separator.alpha = 1;
        }
    }
}

- (void)handleMultipleSelectionButtonTapUsing:(UIButton *)button {
    button.selected = !button.isSelected;
}

- (void)handleSingleSelectionButtonTapUsing:(UIButton *)button {
    if (self.isMomentary) {
        return;
    }
    
    [self updateSelectionButtonUsing:button];
    
    for (SegmentButton *segment in [self segments]) {
        segment.selected = (button == segment);
    }
}

- (void)handleMomentarySelectionButtonTapUsing:(UIButton *)button {
    BOOL previousSelectedState = button.isSelected;
    BOOL previousUserInteractionEnabled = self.segmentsStackView.userInteractionEnabled;
    
    self.segmentsStackView.userInteractionEnabled = NO;
    button.selected = !previousSelectedState;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([ConstantsDuration snappy] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        button.selected = previousSelectedState;
        self.segmentsStackView.userInteractionEnabled = previousUserInteractionEnabled;
        
        [UIView animateWithDuration:[ConstantsDuration regular] animations:^{
            [self updateDividers];
        }];
    });
}

- (void)updateSelectionButtonUsing:(UIButton *)button {
    if (CGSizeEqualToSize(button.bounds.size, CGSizeZero)) {
        // Layout segment subviews
        [self.segmentsStackView layoutSubviews];
    }
    
    // Ensure button has a size.
    if (CGSizeEqualToSize(button.bounds.size, CGSizeZero)) {
        return;
    }
    
    if (!self.selectionButton) {
        [UIView setAnimationsEnabled:NO];
        
        SegmentButton *selectionButton = [[SegmentButton alloc] initWithFont:self.config.font tintColor:self.config.tintColor];
        
        selectionButton.userInteractionEnabled = NO;
        selectionButton.selectedBackgroundColor = self.selectedSegmentTintColor;
        selectionButton.selected = YES;
        selectionButton.center = button.center;
        selectionButton.bounds = button.bounds;
        selectionButton.alpha = 0;
        
        [self insertSubview:selectionButton belowSubview:self.segmentsStackView];
        
        [UIView setAnimationsEnabled:YES];
        
        self.selectionButton = selectionButton;
    }
    
    self.selectionButton.center = button.center;
    self.selectionButton.bounds = button.bounds;
    self.selectionButton.alpha = 1;
}

#pragma mark - Button Actions

- (void)buttonTapped:(UIButton *)button {
    if (!button.isEnabled) {
        return;
    }
    
    [self willChangeValueForKey:@"selectedSegmentIndexes"];
    
    if (!self.allowsMultipleSelection) {
        [self willChangeValueForKey:@"selectedSegmentIndex"];
    }
    
    if (self.isMomentary) {
        [UIView animateWithDuration:[ConstantsDuration snappy] animations:^{
            [self handleMomentarySelectionButtonTapUsing:button];
        }];
    } else if (self.allowsMultipleSelection) {
        [UIView animateWithDuration:[ConstantsDuration snappy] animations:^{
            [self handleMultipleSelectionButtonTapUsing:button];
        }];
    } else {
        [UIView animateWithDuration:[ConstantsDuration regular]
                              delay:0
             usingSpringWithDamping:0.85
              initialSpringVelocity:0.1
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            [self handleSingleSelectionButtonTapUsing:button];
        } completion:^(BOOL finished) {
            // NO-OP
        }];
    }
    
    [self didChangeValueForKey:@"selectedSegmentIndexes"];
    
    if (!self.allowsMultipleSelection) {
        [self didChangeValueForKey:@"selectedSegmentIndex"];
    }
    
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    
    [UIView animateWithDuration:[ConstantsDuration regular] animations:^{
        [self updateDividers];
    }];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - Gesture Recognizer Actions

- (void)handleGestureWithRecognizer:(UIGestureRecognizer *)recognizer {
    UIButton *button = [self.gestureHandler handleGesture:recognizer];
    if (button) {
        [self buttonTapped:button];
    }
}

@end

#pragma mark - UberSegmentedControlConfig Implementation

@implementation UberSegmentedControlConfig

+ (UIFont *)defaultFont {
    return [ConstantsFont segmentTitleLabel];
}

+ (UIColor *)defaultTintColor {
    return [ConstantsColor label];
}

- (instancetype)initWithFont:(UIFont *)font tintColor:(UIColor *)tintColor allowsMultipleSelection:(BOOL)allowsMultipleSelection {
    self = [super init];
    if (self) {
        _font = font ?: [UberSegmentedControlConfig defaultFont];
        _tintColor = tintColor ?: [UberSegmentedControlConfig defaultTintColor];
        _allowsMultipleSelection = allowsMultipleSelection;
    }
    return self;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[UberSegmentedControlConfig class]]) {
        return NO;
    }
    
    UberSegmentedControlConfig *other = (UberSegmentedControlConfig *)object;
    return [self.font isEqual:other.font] &&
           [self.tintColor isEqual:other.tintColor] &&
           self.allowsMultipleSelection == other.allowsMultipleSelection;
}

@end

