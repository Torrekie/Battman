// Helpers local to the live/capacity/cells family. No acquisition or navigation.
#import "../Canvas/BAAnalyticsCanvasCard.h"
#import "../../Data/BAAnalyticsReport.h"
#import "ObjCExt/UIColor+compat.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT UIColor *BALiveBatteryFillColor(NSNumber * _Nullable soc, BOOL lowPowerMode, BOOL charging);
FOUNDATION_EXPORT NSNumber * _Nullable BALiveFiniteNumber(id _Nullable value);
FOUNDATION_EXPORT NSNumber * _Nullable BALiveObservationValue(BAAnalyticsObservation * _Nullable observation, NSString *metric);
FOUNDATION_EXPORT BAAnalyticsFamilyReport * _Nullable BALiveFamilyReport(BAAnalyticsCanvasView *view, NSString *family);
FOUNDATION_EXPORT UIFont *BALiveFont(CGFloat size, UIFontWeight weight);
FOUNDATION_EXPORT BOOL BALiveLargeType(UIView *view);
FOUNDATION_EXPORT CGFloat BALiveTextHeight(NSString *text, CGFloat width, UIFont *font);
FOUNDATION_EXPORT void BALiveDrawText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment);
FOUNDATION_EXPORT NSString *BALiveTime(NSDate * _Nullable date);
FOUNDATION_EXPORT NSString *BALiveWindow(NSDate * _Nullable start, NSDate * _Nullable end);
FOUNDATION_EXPORT NSString *BALiveAge(NSDate * _Nullable timestamp);
FOUNDATION_EXPORT void BALiveHatch(CGRect rect);
FOUNDATION_EXPORT void BALiveLine(CGPoint start, CGPoint end, UIColor *color, CGFloat width, BOOL dashed);
FOUNDATION_EXPORT BAAnalyticsDetailSelection *BALiveSelection(BAAnalyticsCanvasView *view, NSString *kind, NSArray<NSString *> * _Nullable records, NSArray<NSString *> * _Nullable metrics, NSDate * _Nullable start, NSDate * _Nullable end, NSDictionary * _Nullable context);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateCapacityCanvasCard(void);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateCellsCanvasCard(void);

// Reflow essential graph evidence at accessibility sizes instead of clipping
// fixed chart labels. The owning canvas retains its shared detail routing.
@interface BALiveSummaryScrollView : UIScrollView
@property (nonatomic, weak) BAAnalyticsCanvasView *canvas;
@property (nonatomic, copy) NSString *summaryText;
@end
NS_ASSUME_NONNULL_END
