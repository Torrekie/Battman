// Host-only asynchronous Powerlog acquisition; card drawing never performs I/O.
#import "BAAnalyticsReport.h"

NS_ASSUME_NONNULL_BEGIN

@class BAAnalyticsHistoryService;
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
- (instancetype)initWithDatabaseURL:(nullable NSURL *)databaseURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init;
// Main-thread entry points. Reports are delivered on the main thread to weak subscribers.
// Acquisition exists only while active and subscribed; a bounded private serial queue
// performs schema discovery, read-only queries, normalization and session segmentation.
- (void)addSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber;
- (void)removeSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber;
- (void)setApplicationActive:(BOOL)applicationActive;
- (void)refreshNow;
- (void)handleMemoryPressure;
@end

NS_ASSUME_NONNULL_END
