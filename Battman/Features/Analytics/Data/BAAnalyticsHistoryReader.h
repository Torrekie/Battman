// Private acquisition entry point, also exercised by synthetic SQLite tests.
#import "BAAnalyticsReport.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BAAnalyticsReport *BAAnalyticsReadHistoryReport(NSURL * _Nullable databaseURL,
	NSDate *endDate, uint64_t sequenceNumber, BOOL (^cancelled)(void));
NS_ASSUME_NONNULL_END
