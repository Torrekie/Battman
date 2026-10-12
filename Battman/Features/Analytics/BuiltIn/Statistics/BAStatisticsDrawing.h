#import "BAStatisticsCanvasCards.h"
#import "BAStatisticsAnalysis.h"
#import "../../../../ObjCExt/UIColor+compat.h"
#import "../../../../main.h"
#include <math.h>

// Small drawing and immutable-analysis facilities shared by the three cards.
FOUNDATION_EXPORT NSString *BASTime(NSTimeInterval seconds);
FOUNDATION_EXPORT NSString *BASWindow(BAAnalyticsHistoryWindow *window);
// Per-thread reuse; refreshes formatting when the locale or calendar changes.
FOUNDATION_EXPORT NSDateFormatter *BASDateFormatter(NSString *format);
FOUNDATION_EXPORT UIFont *BASFont(CGFloat size);
FOUNDATION_EXPORT CGFloat BASTextHeight(NSString *text, CGFloat width, UIFont *font);
FOUNDATION_EXPORT void BASText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment);
FOUNDATION_EXPORT void BASFill(CGRect rect, UIColor *color);
FOUNDATION_EXPORT void BASLine(CGPoint a, CGPoint b, UIColor *color, CGFloat width);
FOUNDATION_EXPORT void BASHatch(CGRect rect);
FOUNDATION_EXPORT void BASDot(CGPoint p, UIColor *color, CGFloat radius);
FOUNDATION_EXPORT NSString *BASCoverage(NSDictionary *analysis, NSString *validKey, NSString *missingKey);

@interface BASStatisticalView : BAAnalyticsCanvasView
@property (nonatomic, copy) NSDictionary *analysis;
@property (nonatomic, strong) BAAnalyticsFamilyReport *familyReport;
@property (nonatomic) BOOL preparingAnalysis;
@property (nonatomic, strong) UIScrollView *largeTextScroll;
@property (nonatomic, copy) NSArray<NSDictionary *> *largeTextRows;
- (BAAnalyticsDetailSelection *)selection:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics;
- (void)addHit:(NSMutableArray *)hits rect:(CGRect)rect kind:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics label:(NSString *)label;
- (void)drawStatistics:(NSMutableArray *)hits;
- (NSArray<NSDictionary *> *)summaryRows;
@end

@interface BASStatisticalCard : BAAnalyticsCanvasCard
// Published evidence stays paired with analysis until the next generation is ready.
@property (nonatomic, strong) BAAnalyticsReport *derivedReport;
@property (nonatomic, strong, readonly) BAAnalyticsReport *displayedReport;
@property (nonatomic, copy) NSDictionary *analysis;
@property (nonatomic, copy) NSString *calendarSignature;
- (void)deriveIfNeeded;
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family;
// Runs on the shared serial analysis queue with a captured calendar/time zone.
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family calendar:(NSCalendar *)calendar;
- (BAAnalyticsDetailSelection *)defaultDetailSelection;
- (BAAnalyticsDetailSelection *)selectionForDisplayedReport:(BAAnalyticsDetailSelection *)selection;
@end

FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateDwellCanvasCard(void);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateCompareCanvasCard(void);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateRhythmCanvasCard(void);
