// Private acquisition entry point, also exercised by synthetic SQLite tests.
#import "BAAnalyticsReport.h"

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSURL * _Nullable BAAnalyticsResolveHistoryURL(BOOL (^cancelled)(void));
// Identifies the logical Powerlog directory across rotations without storing its path.
FOUNDATION_EXPORT NSString * _Nullable BAAnalyticsHistorySourceIdentity(NSURL * _Nullable databaseURL);
FOUNDATION_EXPORT BAAnalyticsReport *BAAnalyticsReadHistoryReport(NSURL * _Nullable databaseURL,
	NSDate *endDate, uint64_t sequenceNumber, BOOL (^cancelled)(void));
// Current database first, then newest-to-oldest archives (at most nine).
// Overlap is newer-source authoritative; intervals never bridge databases.
FOUNDATION_EXPORT BAAnalyticsReport *BAAnalyticsReadHistoryReportFromSources(NSArray<NSURL *> *databaseURLs,
	NSDate *endDate, uint64_t sequenceNumber, BOOL (^cancelled)(void));
NS_ASSUME_NONNULL_END
