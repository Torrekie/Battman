// Host-only asynchronous Powerlog acquisition; card drawing never performs I/O.
#import "BAAnalyticsReport.h"

NS_ASSUME_NONNULL_BEGIN

@class BAAnalyticsHistoryService;
FOUNDATION_EXPORT NSString *const BAAnalyticsHistoryServiceDidPublishNotification;
@protocol BAAnalyticsHistoryServiceSubscriber <NSObject>
- (void)analyticsHistoryService:(BAAnalyticsHistoryService *)service
				 didPublishReport:(BAAnalyticsReport *)report;
@end

@interface BAAnalyticsHistoryService : NSObject
// Built-in canvases share one host service; do not create a reader per card.
+ (instancetype)sharedService;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsReport *latestReport;
@property (nonatomic, readonly, getter=isPolling) BOOL polling;
@property (nonatomic, readonly) NSUInteger subscriberCount;
// nil resolves the device's existing Powerlog path. A URL supports fixtures/imports.
- (instancetype)initWithDatabaseURL:(nullable NSURL *)databaseURL;
// Explicit isolated storage for importers and tests; nil disables disk caching.
- (instancetype)initWithDatabaseURL:(nullable NSURL *)databaseURL cacheDirectoryURL:(nullable NSURL *)cacheDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
// Main-thread entry points. Reports are delivered on the main thread to weak subscribers.
// Acquisition exists only while active and subscribed; a bounded private serial queue
// performs schema discovery, read-only queries, normalization and session segmentation.
- (void)addSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber;
- (void)removeSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber;
- (void)setApplicationActive:(BOOL)applicationActive;
- (void)refreshNow;
- (void)handleMemoryPressure;
// Terminal suspension for an app-data wipe. Completion runs on main only after
// every queued read/restore/write has finished; subsequent activation is ignored.
- (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion;
+ (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
