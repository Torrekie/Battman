#import "PLBatteryUIMoveableGraphView.h"

@implementation PLBatteryUIMoveableGraphView

+ (CGFloat)graphHeight {
	return 150;
}

- (instancetype)init {
	self = [super init];
	if (self)
		[self initGraphAttributes];
	return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		[self initGraphAttributes];
		self->_displaySize.width = frame.size.width;
		self->_displaySize.height = frame.size.height;
	}
	return self;
}

- (void)initGraphAttributes {
	self.inputData = NULL;
	[self setDefaultRange];
	self->_displayRange = 86400.0;
	self->_displaySize = CGSizeMake(-1.0, -1.0);
	self->horizontal_label_offset = 0;
	self->vertical_label_offset = 15;
	self->_MaxDataRange = -1;
	self->_lineColor = [UIColor whiteColor];
	self->_gridColor = [UIColor grayColor];
	self->_labelColor = [UIColor grayColor];
	self->_graphBackgroundColor = [UIColor blackColor];
	self->defaultTextAttributes = [NSMutableDictionary dictionary];
	self->defaultTextAttributes[NSFontAttributeName] = [UIFont systemFontOfSize:10.0];
	self->defaultTextAttributes[NSForegroundColorAttributeName] = self.labelColor;
	self->_dateChangeArray = [NSMutableArray array];
}

- (void)setDefaultRange {
	self->minPower = 0.0;
	self->maxPower = 100.0;
	self->_endDate = [NSDate date];
	self->_startDate = [self->_endDate dateByAddingTimeInterval:-86400.0];
}

- (CGFloat)setGridRange:(CGFloat)displayRange {
	if (displayRange >= 259200.0)
		return 43200.0;
	if (displayRange >= 86400.0)
		return 14400.0;
	if (displayRange >= 57600.0)
		return 7200.0;
	if (displayRange >= 28800.0)
		return 3600.0;
	if (displayRange >= 14400.0)
		return 1800.0;
	if (displayRange >= 7200.0)
		return 900.0;
	if (displayRange >= 3600.0)
		return 600.0;
	if (displayRange < 1800.0)
		return 120.0;
	return 300.0;
}

- (void)setRangesFromArray:(NSArray *)array {
	self->_startDate = nil;
    self->_endDate = nil;
	// unit: [date, number]
	for (NSArray *unit in array) {
		NSDate *date = unit[0];
		if (self->_startDate == nil) self->_startDate = date;
		if (self->_endDate == nil) self->_endDate = date;
		
		if ([date timeIntervalSinceDate:self->_startDate] < 0.0)
			self->_startDate = date;
		else if ([date timeIntervalSinceDate:self->_endDate] > 0.0)
			self->_endDate = date;
	}
	if ([self->_endDate timeIntervalSinceDate:self->_startDate] == 0.0) {
		self->_startDate = [NSDate dateWithTimeInterval:-3600.0 sinceDate:self->_startDate];
		self->_endDate = [NSDate dateWithTimeInterval:3600.0 sinceDate:self->_endDate];
	}
	
	NSTimeInterval span = [self->_endDate timeIntervalSinceDate:self->_startDate];
	double ratio = span / self.displayRange;
	if (ratio <= 1.0) {
		self->_displayRange = span;
	} else {
		CGRect f = self.frame;
		f.size.width = f.size.width * ratio;
		self.frame = f;
	}
	
	[self setNeedsDisplay];
}

- (void)setFrame:(CGRect)frame {
	[super setFrame:frame];
	if (self.displaySize.height == -1.0)
		self.displaySize = CGSizeMake(frame.size.width, frame.size.height);
}

- (void)setDisplayRange:(CGFloat)displayRange {
	if (displayRange < 3600.0)
		return;

	if ([self.endDate timeIntervalSinceDate:self.startDate] < displayRange)
		displayRange = [self.endDate timeIntervalSinceDate:self.startDate];

	if (displayRange != self->_displayRange) {
		double ratio = self->_displayRange / displayRange;
		CGRect frame = self.frame;

		CGFloat newWidth = frame.size.width * ratio;
		if (self.displaySize.width <= newWidth) {
			frame.size.width = newWidth;
			self.frame = frame;
			self->_displayRange = displayRange;
			[self setNeedsDisplay];
		}
	}
}

- (void)setInputData:(NSMutableArray *)inputData {
	self->_errValue = 0;
	self->_inputData = [inputData mutableCopy];

	if (!self->_inputData || self->_inputData.count <= 1) {
		self->_errValue = 2;
		return;
	}

	[self->_inputData sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
		return [obj1[0] compare:obj2[0]];
	}];

	if (self->_MaxDataRange != -1.0) {
		NSMutableArray *trimmed = [self->_inputData mutableCopy];
		NSDate *earliestAllowed = [[self->_inputData lastObject][0] dateByAddingTimeInterval:-self->_MaxDataRange];

		for (NSUInteger i = 0; i < self->_inputData.count; ++i) {
			NSDate *date = self->_inputData[i][0];
			if ([earliestAllowed timeIntervalSinceDate:date] <= 0)
				break;

			[trimmed removeObjectAtIndex:0];

			if (self->_inputData.count <= i + 1)
				break;
		}
		self->_inputData = trimmed;
	}

	[self setRangesFromArray:self->_inputData];
}

- (void)setLabelColor:(UIColor *)labelColor {
	self->_labelColor = [labelColor copy];
	self->defaultTextAttributes[NSForegroundColorAttributeName] = self->_labelColor;
}

- (void)drawRect:(CGRect)rect {
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, UIColor.clearColor.CGColor);
	CGContextFillRect(ctx, rect);
	if (self->_errValue) {
		[self setDefaultRange];
		[self drawErrorText:ctx andRect:rect];
		[self drawGrid:ctx andRect:rect];
	} else {
		[self drawGrid:ctx andRect:rect];
		[self drawLine:ctx andRect:rect];
		[self drawFill:ctx andRect:rect];
	}
}

- (void)drawErrorText:(CGContextRef)ctx andRect:(CGRect)rect {
	NSString *errString = nil;
	if (self->_errValue == 1)
		errString = @"Negative Power Value";
	if (self->_errValue == 2)
		errString = @"Not Enough Data Points";
	
	CGSize textSize = [errString sizeWithAttributes:self->defaultTextAttributes];
	[errString drawInRect:CGRectMake((rect.size.width - textSize.width) * 0.5, (rect.size.height - textSize.height) * 0.5, textSize.width, textSize.height) withAttributes:self->defaultTextAttributes];
}

- (void)drawGrid:(CGContextRef)ctx andRect:(CGRect)rect {
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.dateFormat = @"MM/dd";
	NSString *startDateStr = [formatter stringFromDate:self.startDate];
	CGSize dateSize = [startDateStr sizeWithAttributes:self->defaultTextAttributes];

	formatter.dateFormat = @"HH:mm";
	NSString *startTimeStr = [formatter stringFromDate:self.startDate];
	CGSize timeSize = [startTimeStr sizeWithAttributes:self->defaultTextAttributes];

	// Use the maximum height for vertical offset
	CGFloat maxTextHeight = MAX(dateSize.height, timeSize.height);
	self->vertical_label_offset = maxTextHeight * 2;

	NSTimeInterval duration = [self.endDate timeIntervalSinceDate:self.startDate];
	self->rectWidth = rect.size.width - self->horizontal_label_offset;
	self->rectHeight = rect.size.height - self->vertical_label_offset;
	self->xInterval = self->rectWidth / duration;
	self->yInterval = self->rectHeight / (float)((float)(self->maxPower - self->minPower) + 1.0);

	CGContextSetFillColorWithColor(ctx, self.graphBackgroundColor.CGColor);
	CGContextFillRect(ctx, CGRectMake(self->horizontal_label_offset, 0, self->rectWidth, self->rectHeight));
	CGContextSetLineWidth(ctx, 0.6);
	CGContextSetStrokeColorWithColor(ctx, self.gridColor.CGColor);
	CGFloat lengths[] = {2.0, 2.0};
	CGContextSetLineDash(ctx, 0.0, lengths, 2);

	double gridRange = [self setGridRange:self.displayRange];
	NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:self.endDate];
	NSInteger minute = components.minute;
	NSInteger second = components.second;
	CGFloat seconds_offset = self->xInterval * (CGFloat)((int)(second + 60 * minute) % (int)gridRange);
	CGFloat grid_per_x = gridRange * self->xInterval;
	for (CGFloat gx = self->rectWidth + self->horizontal_label_offset - seconds_offset; gx >= self->horizontal_label_offset; gx -= grid_per_x) {
		CGContextMoveToPoint(ctx, gx, 0);
		CGContextAddLineToPoint(ctx, gx, self->rectHeight);
	}
	if (self->rectHeight >= 0.0) {
		CGFloat gridStep = self->rectHeight / 10.0;
		for (CGFloat gy = 0; gy <= self->rectHeight; gy += gridStep) {
			CGContextMoveToPoint(ctx, self->horizontal_label_offset, self->rectHeight - gy);
			CGContextAddLineToPoint(ctx, self->horizontal_label_offset + self->rectWidth, self->rectHeight - gy);
		}
	}
	CGContextStrokePath(ctx);
	CGContextSetLineDash(ctx, 0, 0, 0);
	CGContextSetLineWidth(ctx, 1.0);
	CGContextSetStrokeColorWithColor(ctx, self.lineColor.CGColor);

	double displayRange = self.displayRange;
	double leftOffset = self->horizontal_label_offset;
	double startx = self->rectWidth + leftOffset - seconds_offset;
	if (startx >= leftOffset) {
		double step = grid_per_x * (int)(displayRange * self->xInterval / grid_per_x * 0.5);

		for (CGFloat x = startx; x >= leftOffset; x -= step) {
			NSTimeInterval interval = (x - leftOffset) / self->xInterval;
			NSDate *tickDate  = [NSDate dateWithTimeInterval:interval sinceDate:self.startDate];

			formatter.dateFormat = @"MM/dd";
			NSString *dateString = [formatter stringFromDate:tickDate];
			formatter.dateFormat = @"HH:mm";
			NSString *timeString = [formatter stringFromDate:tickDate];

			// Calculate sizes for each string individually
			CGSize actualTimeSize = [timeString sizeWithAttributes:self->defaultTextAttributes];
			CGSize actualDateSize = [dateString sizeWithAttributes:self->defaultTextAttributes];
			
			// Use the larger width for positioning to avoid overlap
			CGFloat maxWidth = MAX(actualTimeSize.width, actualDateSize.width);
			
			// Calculate label position based on the maximum width needed
			CGFloat labelX = fmax(x - maxWidth * 0.5, self->horizontal_label_offset);
			if (maxWidth + labelX > self->horizontal_label_offset + self->rectWidth) {
				labelX = self->horizontal_label_offset + self->rectWidth - maxWidth;
			}

			CGFloat timeX = labelX + (maxWidth - actualTimeSize.width) * 0.5;
			CGFloat dateX = labelX + (maxWidth - actualDateSize.width) * 0.5;

			CGRect timeRect = CGRectMake(timeX, rect.size.height - (maxTextHeight * 2), actualTimeSize.width, actualTimeSize.height);
			CGRect dateRect = CGRectMake(dateX, rect.size.height - maxTextHeight, actualDateSize.width, actualDateSize.height);
			
			[timeString drawInRect:timeRect withAttributes:self->defaultTextAttributes];
			[dateString drawInRect:dateRect withAttributes:self->defaultTextAttributes];

			CGContextMoveToPoint(ctx, x, self->rectHeight - 2.0);
			CGContextAddLineToPoint(ctx, x, self->rectHeight + 2.0);
		}
	}
	CGContextStrokePath(ctx);
	[self drawDayLines:ctx andRect:rect];
}

- (void)drawDayLines:(CGContextRef)ctx andRect:(CGRect)rect {
    [self->_dateChangeArray removeAllObjects];

    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitDay) fromDate:self.endDate];
	NSDate *alignedDay = [NSDate dateWithTimeInterval:-(components.second + (components.minute * 60) + (components.hour * 3600)) sinceDate:self.endDate];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM/dd";

    CGContextSetLineWidth(ctx, 1.5);
    CGContextSetStrokeColorWithColor(ctx, self.gridColor.CGColor);

    NSDate *startDate = self.startDate;
    NSTimeInterval checkInterval = [startDate timeIntervalSinceDate:alignedDay];
    
    if (checkInterval >= 0.0) {
        // Do nothing - alignedDay is already past startDate
    } else {
        for (NSDate *iterDate = alignedDay; [self.startDate timeIntervalSinceDate:iterDate] < 0.0; iterDate = [NSDate dateWithTimeInterval:-86400.0 sinceDate:iterDate]) {
            NSTimeInterval timeInterval = [iterDate timeIntervalSinceDate:startDate];
            double xPos = timeInterval * self->xInterval;
            double xDraw = xPos + self->horizontal_label_offset;
            
            CGContextMoveToPoint(ctx, xDraw, 0.0);
            CGContextAddLineToPoint(ctx, xDraw, self->rectHeight);

            NSNumber *xNum = [NSNumber numberWithDouble:xDraw];
            NSString *dateString = [formatter stringFromDate:iterDate];
            [self->_dateChangeArray addObject:@[xNum, dateString]];
        }
    }

    CGContextStrokePath(ctx);
}

- (void)drawLine:(CGContextRef)ctx andRect:(CGRect)rect {
    if (self->_inputData == nil)
        return;

    CGContextSetLineWidth(ctx, 1.0);
    CGContextSetStrokeColorWithColor(ctx, self.lineColor.CGColor);

    NSTimeInterval interval = [self.endDate timeIntervalSinceDate:self.startDate];
    double scaleY = (rect.size.height - self->vertical_label_offset) / ((double)(self->maxPower - self->minPower) + 1.0);
    double scaleX = (rect.size.width - self->horizontal_label_offset) / interval;
    
    BOOL movedOnce = NO;
    double prevCoord = -1.0;  // This tracks different coordinates based on graph type
    
    for (NSArray *unit in self.inputData) {
        NSDate *date = unit[0];
        NSNumber *percent = unit[1];
		NSInteger graphType = self.graphType;
        
        double value = [percent floatValue];
        double yOffset = scaleY * (value - self->minPower);
        NSTimeInterval secondsFromStart = [date timeIntervalSinceDate:self.startDate];
        double x = self->horizontal_label_offset + scaleX * secondsFromStart;
        double y = rect.size.height - self->vertical_label_offset - yOffset;
        
        if (!movedOnce) {
            CGContextMoveToPoint(ctx, x, y);
            movedOnce = YES;
        } else {
            // Conditional line drawing based on graph type
            if (graphType == 2) {
                CGContextAddLineToPoint(ctx, prevCoord, y);  // horizontal first
            } else if (graphType == 1) {
                CGContextAddLineToPoint(ctx, x, prevCoord);  // vertical first
            }
            
            // Always add line to current point
            CGContextAddLineToPoint(ctx, x, y);
        }
        
        // Update prevCoord based on graph type for next iteration
        if (graphType == 2) {
            prevCoord = x;  // track X coordinate
        } else if (graphType == 1) {
            prevCoord = y;  // track Y coordinate  
        }
    }

    CGContextStrokePath(ctx);
}

- (void)drawFill:(CGContextRef)ctx andRect:(CGRect)rect {
	if (!self->_inputData) return;
	
	CGContextSetLineWidth(ctx, 0.5);
	CGContextSetStrokeColorWithColor(ctx, self.lineColor.CGColor);
	
	// baseline start X and baseline Y
	double baseX = self->horizontal_label_offset;
	double baseY = self->rectHeight;
	
	// Use explicit lastX/lastY so we don't accidentally reuse other locals
	double lastX = baseX;
	double lastY = baseY;
	
	// Precomputed per-view intervals (decompiled referenced xInterval/yInterval)
	double xInterval = self->xInterval; // pixels per second (or precomputed)
	double yInterval = self->yInterval; // pixels per value unit
	
	CGContextBeginPath(ctx);
	CGContextMoveToPoint(ctx, baseX, baseY);
	
	NSInteger graphType = self.graphType;

	for (NSArray *unit in self.inputData) {
		NSDate   *date    = unit[0];
		NSNumber *percent = unit[1];

		double value = [percent floatValue];

		// compute coords
		NSTimeInterval secondsFromStart = [date timeIntervalSinceDate:[self startDate]];
		double x = secondsFromStart * xInterval + self->horizontal_label_offset;
		double y = self->rectHeight - (value - self->minPower) * yInterval;

		if (graphType == 2) {
			// horizontal-first
			CGContextAddLineToPoint(ctx, x, lastY); // horizontal to new x at old Y
			CGContextAddLineToPoint(ctx, x, y);     // vertical to new Y
		}
		else if (graphType == 1) {
			// vertical-first
			CGContextAddLineToPoint(ctx, lastX, y); // vertical at old X to new Y
			CGContextAddLineToPoint(ctx, x, y);     // horizontal to new X
		}
		else {
			// straight
			CGContextAddLineToPoint(ctx, x, y);
		}

		lastX = x;
		lastY = y;
	}
	
	// Close polygon down to baseline at lastX
	CGContextAddLineToPoint(ctx, lastX, baseY);
	CGContextClosePath(ctx);

	const CGFloat *c = CGColorGetComponents(self.lineColor.CGColor);

	CGFloat comps[8];
	CGFloat locs[2] = {0.0f, 1.0f};

	comps[0] = c[0]; comps[1] = c[1]; comps[2] = c[2]; comps[3] = 0.2f;
	comps[4] = c[0]; comps[5] = c[1]; comps[6] = c[2]; comps[7] = 1.0f;
	
	CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
	CGGradientRef grad = CGGradientCreateWithColorComponents(rgb, comps, locs, 2);

	CGContextSaveGState(ctx);
	CGContextClip(ctx);
	
	CGPoint startPt = CGPointMake(baseX, rect.origin.y + rect.size.height); // bottom
	CGPoint endPt   = CGPointMake(baseX, rect.origin.y);                    // top
	CGContextDrawLinearGradient(ctx, grad, startPt, endPt, 0);
	
	CGContextRestoreGState(ctx);

	CGGradientRelease(grad);
	CGColorSpaceRelease(rgb);
}


@end
