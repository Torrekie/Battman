// Private drawing and evidence helpers for the four Process canvases.
#import "../Canvas/BAAnalyticsCanvasCard.h"
#import "../../Data/BAAnalyticsReport.h"
#import "ObjCExt/UIColor+compat.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNumber * _Nullable BAProcessValue(BAAnalyticsObservation * _Nullable observation, NSString *metric);
FOUNDATION_EXPORT BAAnalyticsFamilyReport * _Nullable BAProcessFamily(BAAnalyticsCanvasView *view);
FOUNDATION_EXPORT BAAnalyticsHistorySession * _Nullable BAProcessSession(BAAnalyticsFamilyReport * _Nullable report, NSString *kind);
FOUNDATION_EXPORT NSString *BAProcessClock(NSDate *date);
FOUNDATION_EXPORT NSString *BAProcessWindow(NSDate *start, NSDate *end);
FOUNDATION_EXPORT NSString *BAProcessDuration(NSTimeInterval seconds);
FOUNDATION_EXPORT NSString *BAProcessAvailability(BAAnalyticsFamilyReport * _Nullable report);
FOUNDATION_EXPORT NSString *BAProcessStateName(BAAnalyticsObservedState state);
FOUNDATION_EXPORT UIColor *BAProcessStateColor(BAAnalyticsObservedState state);
FOUNDATION_EXPORT UIFont *BAProcessFont(UIFontTextStyle style, CGFloat size, UIFontWeight weight);
FOUNDATION_EXPORT BOOL BAProcessLargeText(UIView *view);
FOUNDATION_EXPORT void BAProcessText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment);
FOUNDATION_EXPORT void BAProcessHatch(CGRect rect, UIColor *color);
FOUNDATION_EXPORT CGFloat BAProcessTimeX(NSDate *date, NSDate *start, NSDate *end, CGRect plot);
FOUNDATION_EXPORT BOOL BAProcessIntervalUsable(BAAnalyticsHistoryInterval *interval, NSArray<NSString *> *metrics, NSArray<BAAnalyticsHistoryGap *> *gaps);
FOUNDATION_EXPORT NSArray<BAAnalyticsHistoryInterval *> *BAProcessOrderedIntervals(NSArray<BAAnalyticsHistoryInterval *> *intervals);
FOUNDATION_EXPORT BAAnalyticsDetailSelection *BAProcessSelection(BAAnalyticsCanvasView *view, NSString *kind,
    NSArray<NSString *> *records, NSArray<NSString *> *metrics, NSDate * _Nullable start, NSDate * _Nullable end,
    NSDictionary<NSString *, id> * _Nullable context);
FOUNDATION_EXPORT BAAnalyticsCanvasHitRegion *BAProcessRegion(CGRect rect, BAAnalyticsDetailSelection *selection, NSString *label);
// Bounds accessibility/selection allocation for dense graphs. Time slices
// select the original records in that range; they do not downsample evidence.
FOUNDATION_EXPORT NSArray<BAAnalyticsCanvasHitRegion *> *BAProcessTimeSliceRegions(BAAnalyticsCanvasView *view,
    NSArray<NSString *> *metrics, NSDate *start, NSDate *end, CGRect plot, BOOL vertical,
    NSString * _Nullable sessionIdentifier, NSDictionary<NSString *, id> * _Nullable context);

// Draws only trusted per-metric pairs, plus observed points. Missing spans are
// hatched and never joined. Point selections retain the exact source row/time.
FOUNDATION_EXPORT NSArray<BAAnalyticsCanvasHitRegion *> *BAProcessTrace(BAAnalyticsCanvasView *view,
    NSArray<BAAnalyticsObservation *> *observations, NSArray<BAAnalyticsHistoryInterval *> *intervals,
    NSArray<BAAnalyticsHistoryGap *> *gaps, NSString *metric, NSString *unit,
    NSDate *start, NSDate *end, CGRect plot, double minimum, double maximum,
    double divisor, UIColor *color, BOOL dashed, NSString * _Nullable sessionIdentifier);

FOUNDATION_EXPORT void BAProcessStateStrip(BAAnalyticsCanvasView *view,
    NSArray<BAAnalyticsHistoryInterval *> *intervals, NSArray<BAAnalyticsHistoryGap *> *gaps,
    NSDate *start, NSDate *end, CGRect rect, NSString * _Nullable sessionIdentifier,
    NSMutableArray<BAAnalyticsCanvasHitRegion *> *regions);

NS_ASSUME_NONNULL_END
