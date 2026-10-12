// Host-only reports. Each card family has its own requested window and coverage.
#import "BAAnalyticsHistoryModels.h"

NS_ASSUME_NONNULL_BEGIN

#define BAAnalyticsFamilyLive @"live"
#define BAAnalyticsFamilyCapacity @"capacity"
#define BAAnalyticsFamilyCells @"cells"
#define BAAnalyticsFamilySession @"session"
#define BAAnalyticsFamilyDischarge @"discharge"
#define BAAnalyticsFamilyEvents @"events"
#define BAAnalyticsFamilyPath @"path"
#define BAAnalyticsFamilyDwell @"dwell"
#define BAAnalyticsFamilyCompare @"compare"
#define BAAnalyticsFamilyRhythm @"rhythm"

// Stable payload keys and value types. Absence means unavailable.
#define BAAnalyticsPayloadLatestObservation @"latestObservation" // BAAnalyticsObservation
#define BAAnalyticsPayloadSessions @"sessions" // NSArray<BAAnalyticsHistorySession *>
#define BAAnalyticsPayloadSelectedSession @"selectedSession" // BAAnalyticsHistorySession
#define BAAnalyticsPayloadTransitions @"transitions" // NSArray<BAAnalyticsStateTransition *>

typedef NS_ENUM(NSInteger, BAAnalyticsReportAvailability) {
	BAAnalyticsReportAvailabilityLoading = 0,
	BAAnalyticsReportAvailabilityReady,
	BAAnalyticsReportAvailabilityPartial,
	BAAnalyticsReportAvailabilityUnavailable,
};

// Strict overlap: gaps touching only the query endpoints do not intersect it.
// Immutable arrays share an identity-based index; mutable inputs are never cached.
// excludingCoverageGaps preserves the process charts' source-discontinuity rule.
FOUNDATION_EXPORT BOOL BAAnalyticsHistoryHasGap(NSArray<BAAnalyticsHistoryGap *> *gaps,
	NSDate *start, NSDate *end, BOOL excludingCoverageGaps);

@interface BAAnalyticsHistoryWindow : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSDate *startDate;
@property (nonatomic, copy, readonly) NSDate *endDate;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsObservation *> *observations;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsHistoryInterval *> *intervals;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsHistoryGap *> *gaps;
@property (nonatomic, copy, readonly) NSSet<NSString *> *coverageMetricIdentifiers;
@property (nonatomic, readonly) NSTimeInterval coveredDuration;
@property (nonatomic, readonly) NSTimeInterval missingDuration;
// Union duration for each metric; overlapping source intervals never double count.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *coverageSecondsByMetric;
- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
					observations:(NSArray<BAAnalyticsObservation *> *)observations
						intervals:(NSArray<BAAnalyticsHistoryInterval *> *)intervals
							 gaps:(NSArray<BAAnalyticsHistoryGap *> *)gaps
			 coverageMetricIdentifiers:(NSSet<NSString *> *)coverageMetricIdentifiers
					coveredDuration:(NSTimeInterval)coveredDuration
					missingDuration:(NSTimeInterval)missingDuration
				coverageSecondsByMetric:(NSDictionary<NSString *, NSNumber *> *)coverageSecondsByMetric NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsFamilyReport : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *family;
@property (nonatomic, readonly) BAAnalyticsReportAvailability availability;
@property (nonatomic, strong, readonly) BAAnalyticsHistoryWindow *window;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *payload;
@property (nonatomic, copy, readonly) NSArray<NSString *> *limitations;
- (instancetype)initWithFamily:(NSString *)family availability:(BAAnalyticsReportAvailability)availability
						 window:(BAAnalyticsHistoryWindow *)window
						payload:(NSDictionary<NSString *, id> *)payload
					limitations:(NSArray<NSString *> *)limitations NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsReport : NSObject <NSCopying>
// A restored report retains its original evidence timestamp and provenance.
@property (nonatomic, readonly, getter=isCached) BOOL cached;
@property (nonatomic, readonly) uint64_t sequenceNumber;
@property (nonatomic, copy, readonly) NSDate *generatedAt;
@property (nonatomic, copy, readonly) NSString *sourceProfileIdentifier;
// Includes candidate fields with unitValidated=NO; such values must NOT be emitted.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *fieldMetadata;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BAAnalyticsFamilyReport *> *familyReports;
@property (nonatomic, strong, readonly, nullable) NSError *error;
- (instancetype)initWithSequenceNumber:(uint64_t)sequenceNumber generatedAt:(NSDate *)generatedAt
				 sourceProfileIdentifier:(NSString *)sourceProfileIdentifier
						fieldMetadata:(NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *)fieldMetadata
						familyReports:(NSDictionary<NSString *, BAAnalyticsFamilyReport *> *)familyReports
								 error:(nullable NSError *)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (nullable BAAnalyticsFamilyReport *)reportForFamily:(NSString *)family;
- (BAAnalyticsReport *)reportByMarkingCached;
@end

// Host-only bounded binary property-list graph. Invoke off the main thread.
// A cache contains completed evidence, never a loading or failed acquisition.
FOUNDATION_EXPORT NSData * _Nullable BAAnalyticsEncodeCachedReport(BAAnalyticsReport *report, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT BAAnalyticsReport * _Nullable BAAnalyticsDecodeCachedReport(NSData *data, NSDate *now, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT NSData * _Nullable BAAnalyticsEncodeCachedReportCancellable(BAAnalyticsReport *report, NSError * _Nullable * _Nullable error, BOOL (^cancelled)(void));
FOUNDATION_EXPORT BAAnalyticsReport * _Nullable BAAnalyticsDecodeCachedReportCancellable(NSData *data, NSDate *now, NSError * _Nullable * _Nullable error, BOOL (^cancelled)(void));

NS_ASSUME_NONNULL_END
