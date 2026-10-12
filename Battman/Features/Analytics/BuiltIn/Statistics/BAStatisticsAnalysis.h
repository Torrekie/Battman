#import "../../Data/BAAnalyticsReport.h"

NS_ASSUME_NONNULL_BEGIN
// Immutable, property-list-compatible results derived only from normalized evidence.
// No database decoding, source joins or hardware acquisition occurs here.
FOUNDATION_EXPORT NSDictionary *BAStatisticsDwell(BAAnalyticsHistoryWindow *window);
FOUNDATION_EXPORT NSDictionary *BAStatisticsComparison(BAAnalyticsFamilyReport *report);
FOUNDATION_EXPORT NSDictionary *BAStatisticsRhythm(BAAnalyticsHistoryWindow *window, NSCalendar *calendar);
// Preserves scalar/filter evidence while trimming preview arrays to the shared selection budget.
FOUNDATION_EXPORT NSDictionary *BAStatisticsBoundedDetailContext(NSDictionary *context);
NS_ASSUME_NONNULL_END
