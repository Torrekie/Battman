#import "ObjCExt/CALayer+smoothCorners.h"
#import "ColorSegProgressView.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *InterpolateRGB(UIColor *a, UIColor *b, CGFloat t) {
	t = MIN(1.0, MAX(0.0, t));
	CGFloat ra, ga, ba, aa, rb, gb, bb, ab;
	BOOL okA = [a getRed:&ra green:&ga blue:&ba alpha:&aa];
	BOOL okB = [b getRed:&rb green:&gb blue:&bb alpha:&ab];
	if (!okA) {
		CIColor *ci = [CIColor colorWithCGColor:a.CGColor];
		ra = ci.red; ga = ci.green; ba = ci.blue; aa = ci.alpha;
	}
	if (!okB) {
		CIColor *ci = [CIColor colorWithCGColor:b.CGColor];
		rb = ci.red; gb = ci.green; bb = ci.blue; ab = ci.alpha;
	}
	return [UIColor colorWithRed:ra + (rb - ra) * t green:ga + (gb - ga) * t blue:ba + (bb - ba) * t alpha:aa + (ab - aa) * t];
}

static UIColor *InterpolateHSB(UIColor *a, UIColor *b, CGFloat t, BOOL analogous) {
	t = MIN(1.0, MAX(0.0, t));
	CGFloat ha, sa, ba, aa, hb, sb, bb, ab;
	if (![a getHue:&ha saturation:&sa brightness:&ba alpha:&aa] ||
		![b getHue:&hb saturation:&sb brightness:&bb alpha:&ab]) {
		return InterpolateRGB(a, b, t);
	}
	
	CGFloat hDiff = hb - ha;
	if (hDiff > 0.5) hDiff -= 1.0;
	else if (hDiff < -0.5) hDiff += 1.0;
	
	if (!analogous && fabs(hDiff) < 0.5) {
		hDiff = hDiff > 0 ? hDiff - 1.0 : hDiff + 1.0;
	}
	
	CGFloat h = ha + hDiff * t;
	if (h < 0) h += 1.0;
	if (h > 1) h -= 1.0;
	
	return [UIColor colorWithHue:h saturation:sa + (sb - sa) * t brightness:ba + (bb - ba) * t alpha:aa + (ab - aa) * t];
}

static UIColor *InterpolateColorRGB(UIColor *a, UIColor *b, CGFloat t) {
	return InterpolateRGB(a, b, t);
}

static UIColor *InterpolateColorHSB(UIColor *a, UIColor *b, CGFloat t) {
	return InterpolateHSB(a, b, t, NO);
}

static UIColor *InterpolateColorHSBAnalogous(UIColor *a, UIColor *b, CGFloat t) {
	return InterpolateHSB(a, b, t, YES);
}

@interface ColorSegProgressView ()

@property (nonatomic) NSUInteger segmentCount;
@property (nonatomic, strong) NSArray<UIColor *> *colorStops;
@property (nonatomic, strong) NSMutableArray<CALayer *> *segmentLayers;
@property (nonatomic, strong) NSMutableArray<CALayer *> *fillLayers;
@property (nonatomic, strong) NSMutableArray<CALayer *> *separatorLayers;
@property (nonatomic, strong) NSMutableArray<UIColor *> *segmentColors;
@property (nonatomic, strong) CALayer *borderLayer;
@property (nonatomic, strong) CALayer *backgroundLayer;

@property (nonatomic) CGRect segmentsUnionFrame;

@end

@implementation ColorSegProgressView

#pragma mark - Init

- (instancetype)initWithSegmentCount:(NSUInteger)count colorTransition:(NSArray<UIColor *> *)colorTransition {
	NSParameterAssert(count >= 1);
	NSParameterAssert(colorTransition.count >= 1);
	if (self = [super initWithFrame:CGRectZero]) {
		_segmentCount = MAX(1, count);
		_colorStops = [colorTransition copy];
		
		_minimumValue = 0.0;
		_maximumValue = 1.0;
		_value = 0.0;
		
		_segmentSpacing = 6.0;
		_forceSquareSegments = YES;
		_unfilledAlpha = 0.25;
		_colorForUnfilled = nil;
		_showSeparators = YES;
		
		_separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25];
		_separatorWidth = 1.0;
		
		_borderWidth = 0.0;
		_borderColor = nil;
		
		_valueShouldFollowSegments = NO;
		_colorTransitionMode = kColorSegTransitionRGB;
		
		_segmentLayers = [NSMutableArray array];
		_fillLayers = [NSMutableArray array];
		_separatorLayers = [NSMutableArray array];
		_segmentColors = [NSMutableArray array];
		
		_borderLayer = [CALayer layer];
		_backgroundLayer = [CALayer layer];
		_progress = 0.0;
		_continuousUpdates = YES;

		[self.layer insertSublayer:_backgroundLayer atIndex:0];
		[self.layer insertSublayer:_borderLayer atIndex:1];
		
		[self commonInitCreateSegmentsAndSeparators];
		
		self.userInteractionEnabled = YES;
	}
	return self;
}

#pragma mark - Value / Progress mapping

- (void)setMinimumValue:(double)minimumValue {
	_minimumValue = minimumValue;
	self.value = MIN(MAX(self.value, _minimumValue), self.maximumValue);
	[self updateProgressFromValueAnimated:NO];
}

- (void)setMaximumValue:(double)maximumValue {
	_maximumValue = maximumValue;
	self.value = MIN(MAX(self.value, self.minimumValue), _maximumValue);
	[self updateProgressFromValueAnimated:NO];
}

- (void)setValue:(double)value {
	[self setValue:value animated:NO];
}

- (void)setValue:(double)value animated:(BOOL)animated {
	double clamped = value;
	if (clamped < self.minimumValue) clamped = self.minimumValue;
	if (clamped > self.maximumValue) clamped = self.maximumValue;
	if (clamped == _value) return;
	_value = clamped;
	[self updateProgressFromValueAnimated:animated];
}

- (void)updateProgressFromValueAnimated:(BOOL)animated {
	double range = (self.maximumValue - self.minimumValue);
	CGFloat p = (range == 0) ? 0.0 : (CGFloat)((self.value - self.minimumValue) / range);
	_progress = MIN(1.0, MAX(0.0, p));
	[self updateProgressVisualsAnimated:animated];
}

- (void)setProgress:(CGFloat)progress {
	[self setProgress:progress animated:NO];
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated {
	CGFloat clamped = MIN(1.0, MAX(0.0, progress));
	if (clamped == _progress) return;
	_progress = clamped;
	double range = (self.maximumValue - self.minimumValue);
	double v = self.minimumValue + (double)clamped * range;
	_value = v;
	[self updateProgressVisualsAnimated:animated];
}

#pragma mark - Layers creation

- (void)commonInitCreateSegmentsAndSeparators {
	for (CALayer *l in self.segmentLayers) [l removeFromSuperlayer];
	for (CALayer *s in self.separatorLayers) [s removeFromSuperlayer];
	[self.segmentLayers removeAllObjects];
	[self.fillLayers removeAllObjects];
	[self.separatorLayers removeAllObjects];
	[self.segmentColors removeAllObjects];

	[self.layer insertSublayer:self.backgroundLayer atIndex:0];
	[self.layer insertSublayer:self.borderLayer atIndex:1];
	
	for (NSUInteger i = 0; i < self.segmentCount; ++i) {
		CALayer *seg = [CALayer layer];
		[seg setSmoothCorners:YES];
		seg.masksToBounds = YES;
		[self.layer addSublayer:seg];
		
		CALayer *fill = [CALayer layer];
		[fill setSmoothCorners:YES];
		fill.masksToBounds = YES;
		[seg addSublayer:fill];
		
		[self.segmentLayers addObject:seg];
		[self.fillLayers addObject:fill];
		[self.segmentColors addObject:[UIColor clearColor]];
		
		if (i < self.segmentCount - 1) {
			CALayer *sep = [CALayer layer];
			sep.backgroundColor = self.separatorColor.CGColor;
			sep.hidden = !self.showSeparators;
			[self.layer addSublayer:sep];
			[self.separatorLayers addObject:sep];
		}
	}
	
	[self updateSegmentColors];
	[self invalidateIntrinsicContentSize];
	[self setNeedsLayout];
}

#pragma mark - Layout

- (void)layoutSubviews {
	[super layoutSubviews];
	
	CGFloat totalGap = self.segmentSpacing * (self.segmentCount - 1);
	CGFloat containerW = CGRectGetWidth(self.bounds);
	CGFloat containerH = CGRectGetHeight(self.bounds);
	CGFloat availableW = containerW - totalGap;
	if (availableW <= 0) availableW = 0;
	
	CGFloat segW = availableW / (CGFloat)self.segmentCount;
	if (self.forceSquareSegments) {
		CGFloat square = MIN(segW, containerH);
		segW = square;
	}
	segW = MAX(0, segW);
	
	CGFloat usedW = segW * self.segmentCount + totalGap;
	CGFloat startX = (containerW - usedW) / 2.0;
	if (startX < 0) startX = 0;
	
	CGFloat segH = segW;
	CGFloat y = (containerH - segH) / 2.0;
	CGFloat x = startX;
	
	for (NSUInteger i = 0; i < self.segmentCount; ++i) {
		CALayer *seg = self.segmentLayers[i];
		seg.frame = CGRectMake(x, y, segW, segH);
		
		CGFloat cornerRadius = segW * 0.225;
		seg.cornerRadius = cornerRadius;
		
		CACornerMask mask = 0;
		if (self.segmentCount == 1) {
			mask = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
		} else {
			if (i == 0) mask = (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner);
			else if (i == self.segmentCount - 1) mask = (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner);
			else mask = 0;
		}
		seg.maskedCorners = mask;
		
		CALayer *fill = self.fillLayers[i];
		fill.frame = CGRectMake(0, 0, 0, segH);
		fill.cornerRadius = cornerRadius;
		
		CACornerMask fillMask = 0;
		if (i == 0) fillMask |= (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner);
		fill.maskedCorners = fillMask;
		
		x += segW + self.segmentSpacing;
	}
	
	for (NSUInteger i = 0; i < self.separatorLayers.count; ++i) {
		CALayer *sep = self.separatorLayers[i];
		sep.hidden = !self.showSeparators;
		CALayer *left = self.segmentLayers[i];
		CGRect leftF = left.frame;
		CGFloat gapStart = CGRectGetMaxX(leftF);
		CGFloat sepX = gapStart + (self.segmentSpacing - self.separatorWidth) / 2.0;
		CGFloat sepH = segH * 0.76;
		CGFloat sepY = CGRectGetMinY(leftF) + (segH - sepH) / 2.0;
		sep.frame = CGRectMake(sepX, sepY, self.separatorWidth, sepH);
		sep.cornerRadius = self.separatorWidth / 2.0;
		sep.backgroundColor = self.separatorColor.CGColor;
	}
	
	if (self.segmentLayers.count > 0) {
		CALayer *first = self.segmentLayers.firstObject;
		CALayer *last = self.segmentLayers.lastObject;
		CGFloat minX = CGRectGetMinX(first.frame);
		CGFloat maxX = CGRectGetMaxX(last.frame);
		CGFloat fullSpacing = self.segmentSpacing;
		CGRect unionFrame = CGRectMake(minX - fullSpacing, CGRectGetMinY(first.frame) - fullSpacing, (maxX - minX) + fullSpacing * 2.0, CGRectGetHeight(first.frame) + fullSpacing * 2.0);
		self.segmentsUnionFrame = unionFrame;
		
		self.backgroundLayer.frame = unionFrame;
		self.backgroundLayer.cornerRadius = segH * 0.225;
		[self.backgroundLayer setSmoothCorners:YES];
		
		if (self.borderWidth > 0.0) {
			CGRect borderFrame = unionFrame;
			CGFloat strokeInset = self.borderWidth / 2.0;
			borderFrame = CGRectInset(borderFrame, -strokeInset, -strokeInset);
			self.borderLayer.frame = borderFrame;
			self.borderLayer.cornerRadius = CGRectGetHeight(borderFrame) * 0.225;
			[self.borderLayer setSmoothCorners:YES];
			self.borderLayer.borderWidth = self.borderWidth;
			self.borderLayer.borderColor = (self.borderColor ?: [UIColor clearColor]).CGColor;
			self.borderLayer.backgroundColor = [UIColor clearColor].CGColor;
			[self.layer insertSublayer:self.backgroundLayer atIndex:0];
			[self.layer insertSublayer:self.borderLayer atIndex:1];
		} else {
			self.borderLayer.frame = CGRectZero;
			self.borderLayer.borderWidth = 0;
			self.borderLayer.borderColor = nil;
		}
	} else {
		self.segmentsUnionFrame = CGRectZero;
		self.backgroundLayer.frame = CGRectZero;
		self.borderLayer.frame = CGRectZero;
	}
	
	[self updateProgressVisualsAnimated:NO];
}

#pragma mark - Auto Layout Support

- (CGSize)intrinsicContentSize {
	return [self calculateOptimalSize];
}

- (CGSize)sizeThatFits:(CGSize)size {
	return [self calculateOptimalSize];
}

- (CGSize)calculateOptimalSize {
	CGFloat defaultSegmentSize = 20.0;
	
	CGFloat totalSpacing = self.segmentSpacing * (self.segmentCount - 1);
	CGFloat totalWidth = (defaultSegmentSize * self.segmentCount) + totalSpacing;
	
	if (self.borderWidth > 0.0) {
		CGFloat borderPadding = (self.segmentSpacing * 2.0) + (self.borderWidth * 2.0);
		totalWidth += borderPadding;
	}
	
	CGFloat height = defaultSegmentSize;
	
	if (self.borderWidth > 0.0) {
		CGFloat borderPadding = (self.segmentSpacing * 2.0) + (self.borderWidth * 2.0);
		height += borderPadding;
	}
	
	return CGSizeMake(totalWidth, height);
}

- (void)invalidateIntrinsicContentSize {
	[super invalidateIntrinsicContentSize];
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
	[super willMoveToSuperview:newSuperview];
	if (newSuperview) {
		CGSize size = [self calculateOptimalSize];
		if (CGRectGetWidth(self.bounds) == 0 || CGRectGetHeight(self.bounds) == 0) {
			self.frame = CGRectMake(0, 0, size.width, size.height);
		}
		[self setNeedsLayout];
	}
}

#pragma mark - Color stops

- (void)updateSegmentColors {
	NSUInteger stopCount = self.colorStops.count;
	NSMutableArray<NSNumber *> *stopIndices = [NSMutableArray arrayWithCapacity:stopCount];
	
	if (stopCount == 1) {
		[stopIndices addObject:@(0)];
	} else {
		for (NSUInteger k = 0; k < stopCount; ++k) {
			CGFloat pos = (CGFloat)k * (CGFloat)(self.segmentCount - 1) / (CGFloat)(stopCount - 1);
			NSUInteger idx = (NSUInteger)round(pos);
			idx = MIN(idx, self.segmentCount - 1);
			[stopIndices addObject:@(idx)];
		}
	}
	
	for (NSUInteger segIdx = 0; segIdx < self.segmentCount; ++segIdx) {
		NSUInteger leftStop = 0;
		NSUInteger rightStop = stopCount - 1;
		for (NSUInteger s = 0; s < stopCount; ++s) {
			NSUInteger mapped = stopIndices[s].unsignedIntegerValue;
			if (mapped <= segIdx) leftStop = s;
			if (mapped >= segIdx) { rightStop = s; break; }
		}
		
		UIColor *color;
		if (leftStop == rightStop) {
			color = self.colorStops[leftStop];
		} else {
			NSUInteger leftMapped = stopIndices[leftStop].unsignedIntegerValue;
			NSUInteger rightMapped = stopIndices[rightStop].unsignedIntegerValue;
			CGFloat range = (CGFloat)(rightMapped - leftMapped);
			CGFloat localPos = range == 0 ? 0 : ((CGFloat)(segIdx - leftMapped)) / range;
			UIColor *c0 = self.colorStops[leftStop];
			UIColor *c1 = self.colorStops[rightStop];
			color = [self interpolateFromColor:c0 toColor:c1 t:localPos];
		}
		
		if (segIdx < self.segmentColors.count) self.segmentColors[segIdx] = color;
		else [self.segmentColors addObject:color];
		
		CALayer *seg = self.segmentLayers[segIdx];
		seg.backgroundColor = color.CGColor;
		CALayer *fill = self.fillLayers[segIdx];
		fill.backgroundColor = color.CGColor;
	}
	
	[self setNeedsLayout];
}

- (UIColor *)interpolateFromColor:(UIColor *)a toColor:(UIColor *)b t:(CGFloat)t {
	t = MIN(1.0, MAX(0.0, t));
	
	switch (self.colorTransitionMode) {
		case kColorSegTransitionRGB:
			return InterpolateColorRGB(a, b, t);
		case kColorSegTransitionHSB:
			return InterpolateColorHSB(a, b, t);
		case kColorSegTransitionAnalogous:
			return InterpolateColorHSBAnalogous(a, b, t);
		default:
			return InterpolateColorRGB(a, b, t);
	}
}

#pragma mark - Visual update

- (void)updateProgressVisualsAnimated:(BOOL)animated {
	CGFloat total = (CGFloat)self.segmentCount * self.progress;
	NSUInteger fully = (NSUInteger)floor(total);
	CGFloat frac = total - fully;
	
	for (NSUInteger i = 0; i < self.segmentCount; ++i) {
		CALayer *seg = self.segmentLayers[i];
		CALayer *fill = self.fillLayers[i];
		UIColor *orig = (i < self.segmentColors.count) ? self.segmentColors[i] : nil;
		
		if (i < fully) {
			if (orig) { seg.backgroundColor = orig.CGColor; fill.backgroundColor = orig.CGColor; }
			[self setFillLayer:fill toFraction:1.0 animated:animated];
			if (i == self.segmentCount - 1) {
				fill.maskedCorners = (kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner) | ((i==0)? (kCALayerMinXMinYCorner|kCALayerMinXMaxYCorner) : 0);
			} else {
				CACornerMask leftMask = (i==0) ? (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner) : 0;
				fill.maskedCorners = leftMask;
			}
			seg.opacity = 1.0;
		} else if (i == fully && frac > 0.0) {
			if (self.colorForUnfilled) {
				seg.backgroundColor = self.colorForUnfilled.CGColor;
				seg.opacity = 1.0;
			} else {
				if (orig) {
					const CGFloat *components = CGColorGetComponents(orig.CGColor);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
					seg.backgroundColor = CGColorCreateGenericRGB(components[0], components[1], components[2], components[3] * self.unfilledAlpha);
#pragma clang diagnostic pop
				}
				seg.opacity = 1.0;
			}
			
			if (orig) fill.backgroundColor = orig.CGColor;
			fill.opacity = 1.0;
			[self setFillLayer:fill toFraction:frac animated:animated];
			
			CACornerMask fillMask = 0;
			if (i == 0) fillMask |= (kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner);
			fill.maskedCorners = fillMask;
		} else {
			[self setFillLayer:fill toFraction:0.0 animated:animated];
			if (self.colorForUnfilled) {
				seg.backgroundColor = self.colorForUnfilled.CGColor;
				fill.backgroundColor = self.colorForUnfilled.CGColor;
				seg.opacity = 1.0;
			} else {
				if (orig) {
					const CGFloat *components = CGColorGetComponents(orig.CGColor);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
					seg.backgroundColor = CGColorCreateGenericRGB(components[0], components[1], components[2], components[3] * self.unfilledAlpha);
#pragma clang diagnostic pop
				}
				seg.opacity = 1.0;
			}
		}
	}
}

- (void)setFillLayer:(CALayer *)fill toFraction:(CGFloat)fraction animated:(BOOL)animated {
	fraction = MIN(1.0, MAX(0.0, fraction));
	CALayer *parent = fill.superlayer;
	if (!parent) return;
	
	CGRect target = CGRectMake(0, 0, parent.bounds.size.width * fraction, parent.bounds.size.height);
	
	if (animated) {
		CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"bounds.size.width"];
		anim.fromValue = @(fill.bounds.size.width);
		anim.toValue = @(target.size.width);
		anim.duration = 0.22;
		anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
		fill.bounds = (CGRect){.origin = CGPointZero, .size = target.size};
		[fill addAnimation:anim forKey:@"width"];
	} else {
		fill.frame = target;
	}
	fill.cornerRadius = parent.cornerRadius;
}

#pragma mark - Touch tracking

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
	BOOL inside = CGRectContainsPoint(self.bounds, [touch locationInView:self]);
	if (!inside) return NO;
	[self sendActionsForControlEvents:UIControlEventTouchDown];
	[self updateValueFromTouch:touch sendEvent:YES];
	return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(nullable UIEvent *)event {
	[self updateValueFromTouch:touch sendEvent:self.continuousUpdates];
	return YES;
}

- (void)endTrackingWithTouch:(nullable UITouch *)touch withEvent:(nullable UIEvent *)event {
	BOOL inside = touch ? CGRectContainsPoint(self.bounds, [touch locationInView:self]) : NO;
	[self updateValueFromTouch:touch sendEvent:YES];
	if (inside) {
		[self sendActionsForControlEvents:UIControlEventTouchUpInside];
	} else {
		[self sendActionsForControlEvents:UIControlEventTouchUpOutside];
	}
}

- (void)cancelTrackingWithEvent:(nullable UIEvent *)event {
	[self sendActionsForControlEvents:UIControlEventTouchCancel];
}

- (void)updateValueFromTouch:(UITouch *)touch sendEvent:(BOOL)sendEvent {
	if (!touch) return;
	CGPoint p = [touch locationInView:self];
	
	CGFloat newProgress = 0.0;
	BOOL foundSegment = NO;
	
	for (NSUInteger i = 0; i < self.segmentLayers.count; ++i) {
		CALayer *seg = self.segmentLayers[i];
		CGRect segFrame = seg.frame;
		
		CGFloat halfSpacing = self.segmentSpacing / 2.0;
		CGRect touchFrame = CGRectInset(segFrame, -halfSpacing, -halfSpacing);
		
		if (i == 0) {
			touchFrame.origin.x = segFrame.origin.x;
			touchFrame.size.width = segFrame.size.width + halfSpacing;
		} else if (i == self.segmentLayers.count - 1) {
			touchFrame.origin.x = segFrame.origin.x - halfSpacing;
			touchFrame.size.width = segFrame.size.width + halfSpacing;
		}
		
		if (CGRectContainsPoint(touchFrame, p)) {
			foundSegment = YES;
			
			if (self.valueShouldFollowSegments) {
				newProgress = (CGFloat)(i + 1) / (CGFloat)self.segmentCount;
			} else {
				CGFloat segmentStart = (CGFloat)i / (CGFloat)self.segmentCount;
				CGFloat segmentEnd = (CGFloat)(i + 1) / (CGFloat)self.segmentCount;
				CGFloat localX = (p.x - segFrame.origin.x) / segFrame.size.width;
				localX = MIN(1.0, MAX(0.0, localX));
				newProgress = segmentStart + (segmentEnd - segmentStart) * localX;
			}
			break;
		}
	}
	
	if (!foundSegment) {
		CGRect frame = self.segmentsUnionFrame;
		if (CGRectIsEmpty(frame)) frame = self.bounds;
		
		CGFloat relative = (p.x - CGRectGetMinX(frame)) / CGRectGetWidth(frame);
		relative = MIN(1.0, MAX(0.0, relative));
		
		newProgress = relative;
		if (self.valueShouldFollowSegments) {
			CGFloat step = 1.0 / (CGFloat)self.segmentCount;
			CGFloat k = round(relative / step);
			newProgress = step * k;
			newProgress = MIN(1.0, MAX(0.0, newProgress));
		}
	}
	
	newProgress = MIN(1.0, MAX(0.0, newProgress));
	
	double range = (self.maximumValue - self.minimumValue);
	double newValue = self.minimumValue + (double)newProgress * range;
	if (newValue < self.minimumValue) newValue = self.minimumValue;
	if (newValue > self.maximumValue) newValue = self.maximumValue;
	
	double oldValue = self.value;
	_value = newValue;
	_progress = newProgress;
	[self updateProgressVisualsAnimated:NO];
	
	if (sendEvent && oldValue != _value) {
		[self sendActionsForControlEvents:UIControlEventValueChanged];
	}
}

#pragma mark - Appearance setters

- (void)setSegmentSpacing:(CGFloat)segmentSpacing {
	_segmentSpacing = segmentSpacing;
	[self invalidateIntrinsicContentSize];
	[self setNeedsLayout];
}

- (void)setForceSquareSegments:(BOOL)forceSquareSegments {
	_forceSquareSegments = forceSquareSegments;
	[self setNeedsLayout];
}

- (void)setUnfilledAlpha:(CGFloat)unfilledAlpha {
	_unfilledAlpha = unfilledAlpha;
	[self updateProgressVisualsAnimated:NO];
}

- (void)setColorForUnfilled:(UIColor *)colorForUnfilled {
	_colorForUnfilled = colorForUnfilled;
	[self updateProgressVisualsAnimated:NO];
}

- (void)setShowSeparators:(BOOL)showSeparators {
	_showSeparators = showSeparators;
	for (CALayer *s in self.separatorLayers) s.hidden = !showSeparators;
	[self setNeedsLayout];
}

- (void)setSeparatorColor:(UIColor *)separatorColor {
	_separatorColor = separatorColor ?: [[UIColor whiteColor] colorWithAlphaComponent:0.25];
	for (CALayer *s in self.separatorLayers) s.backgroundColor = _separatorColor.CGColor;
}

- (void)setSeparatorWidth:(CGFloat)separatorWidth {
	_separatorWidth = separatorWidth;
	[self setNeedsLayout];
}

- (void)setBorderWidth:(CGFloat)borderWidth {
	_borderWidth = borderWidth;
	[self invalidateIntrinsicContentSize];
	[self setNeedsLayout];
}

- (void)setBorderColor:(UIColor *)borderColor {
	_borderColor = borderColor;
	[self setNeedsLayout];
}

- (void)setColorTransitionMode:(ColorSegTransitionMode)colorTransitionMode {
	_colorTransitionMode = colorTransitionMode;
	[self updateSegmentColors];
}

- (void)updateColorTransition:(NSArray<UIColor *> *)colorTransition {
	NSParameterAssert(colorTransition.count >= 1);
	_colorStops = [colorTransition copy];
	[self updateSegmentColors];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
	self.backgroundLayer.backgroundColor = (backgroundColor ?: [UIColor clearColor]).CGColor;
}

- (UIColor *)backgroundColor {
	return [UIColor colorWithCGColor:self.backgroundLayer.backgroundColor];
}

@end
