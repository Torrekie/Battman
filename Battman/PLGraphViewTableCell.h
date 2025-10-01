#import <UIKit/UIKit.h>
#import "PLBatteryUIMoveableGraphView.h"

// Change to 1 and fill rest of impl if you are going to use this in PreferenceBundles
#define USE_PREFERENCES_FRAMEWORK 0

#if USE_PREFERENCES_FRAMEWORK
@class PSSpecifier;
@interface PSTableCell : UITableViewCell
@property (nonatomic, strong) PSSpecifier *specifier;
@end
#else
#define PSTableCell UITableViewCell
#endif

@interface PLGraphViewTableCell : PSTableCell {
	BOOL waitingForData;
	BOOL graphViewDidChange;
	NSMutableArray *_graphArray;
	UIColor *labelColor;
	UIColor *graphColor;
}
@property (nonatomic, strong) NSMutableArray *graphArray;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) PLBatteryUIMoveableGraphView *graphView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

+ (int)graphHeight;

- (void)generateGraphs;
@end
