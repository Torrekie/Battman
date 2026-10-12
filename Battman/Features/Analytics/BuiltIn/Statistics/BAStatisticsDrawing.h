#import "BAStatisticsCanvasCards.h"
#import "BAStatisticsAnalysis.h"
#import "../../../../ObjCExt/UIColor+compat.h"
#import "../../../../main.h"
#include <math.h>

// Small drawing and immutable-analysis facilities shared by the three cards.
FOUNDATION_EXPORT NSString *BASTime(NSTimeInterval seconds);
FOUNDATION_EXPORT NSString *BASWindow(BAAnalyticsHistoryWindow *window);
FOUNDATION_EXPORT UIFont *BASFont(CGFloat size);
FOUNDATION_EXPORT void BASText(NSString *text, CGRect rect, UIFont *font, UIColor *color, NSTextAlignment alignment);
FOUNDATION_EXPORT void BASFill(CGRect rect, UIColor *color);
FOUNDATION_EXPORT void BASLine(CGPoint a, CGPoint b, UIColor *color, CGFloat width);
FOUNDATION_EXPORT void BASHatch(CGRect rect);
FOUNDATION_EXPORT void BASDot(CGPoint p, UIColor *color, CGFloat radius);
FOUNDATION_EXPORT NSString *BASCoverage(NSDictionary *analysis, NSString *validKey, NSString *missingKey);

@interface BASStatisticalView : BAAnalyticsCanvasView
@property (nonatomic, copy) NSDictionary *analysis;
@property (nonatomic, strong) BAAnalyticsFamilyReport *familyReport;
@property (nonatomic, strong) UIScrollView *largeTextScroll;
@property (nonatomic, copy) NSArray<NSDictionary *> *largeTextRows;
- (BAAnalyticsDetailSelection *)selection:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics;
- (void)addHit:(NSMutableArray *)hits rect:(CGRect)rect kind:(NSString *)kind item:(NSDictionary *)item metrics:(NSArray *)metrics label:(NSString *)label;
- (void)drawStatistics:(NSMutableArray *)hits;
- (NSArray<NSDictionary *> *)summaryRows;
@end

@interface BASStatisticalCard : BAAnalyticsCanvasCard
@property (nonatomic, weak) BAAnalyticsReport *derivedReport;
@property (nonatomic, copy) NSDictionary *analysis;
@property (nonatomic, copy) NSString *calendarSignature;
- (void)deriveIfNeeded;
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family;
// Runs on the shared serial analysis queue with a captured calendar/time zone.
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family calendar:(NSCalendar *)calendar;
- (BAAnalyticsDetailSelection *)defaultDetailSelection;
@end

FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateDwellCanvasCard(void);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateCompareCanvasCard(void);
FOUNDATION_EXPORT id<BAAnalyticsCard> BAAnalyticsCreateRhythmCanvasCard(void);
