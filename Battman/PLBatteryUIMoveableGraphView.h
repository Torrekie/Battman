#import <UIKit/UIKit.h>

@interface PLBatteryUIMoveableGraphView : UIView {
	float maxPower;
	float minPower;
	int _errValue;
	CGFloat horizontal_label_offset;
	CGFloat vertical_label_offset;
	CGFloat rectWidth;
	CGFloat rectHeight;
	CGFloat xInterval;
	CGFloat yInterval;
	NSMutableDictionary<NSAttributedStringKey,id> *defaultTextAttributes;
	NSMutableArray *_dateChangeArray;
}
@property (nonatomic, assign) CGFloat displayRange;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, assign) CGFloat MaxDataRange;
@property (nonatomic, assign) int graphType;
@property (nonatomic, copy) NSMutableArray *inputData;
@property (nonatomic, copy) UIColor *labelColor;
@property (nonatomic, copy) UIColor *graphBackgroundColor;
@property (nonatomic, copy) UIColor *lineColor;
@property (nonatomic, copy) UIColor *gridColor;
@property (nonatomic, strong) NSDate *startDate;
@property (nonatomic, strong) NSDate *endDate;

+ (CGFloat)graphHeight;

- (void)setDefaultRange;
- (void)setRangesFromArray:(NSArray *)array;

@end
