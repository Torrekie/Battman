#import "BAAnalyticsHistoryService.h"
#import "BAAnalyticsHistoryReader.h"
#include <math.h>

static NSTimeInterval const BAHistoryRefreshInterval = 60.0;

@interface BAHistoryReadCancellation : NSObject
@property (atomic) BOOL cancelled;
@end
@implementation BAHistoryReadCancellation
@end

@interface BAAnalyticsHistoryService ()
@property (nonatomic, copy, nullable) NSURL *databaseURL;
@property (nonatomic, strong) NSHashTable<id<BAAnalyticsHistoryServiceSubscriber>> *subscribers;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@property (nonatomic, strong, nullable) BAHistoryReadCancellation *readCancellation;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsReport *latestReport;
@property (nonatomic, getter=isPolling) BOOL polling;
@property (nonatomic) BOOL applicationActive;
@property (nonatomic) BOOL acquisitionPending;
@property (nonatomic) BOOL memoryPressureDefersRetry;
@property (nonatomic) uint64_t nextSequenceNumber;
@end

@implementation BAAnalyticsHistoryService
+ (instancetype)sharedService {
	static BAAnalyticsHistoryService *service;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ service = [[self alloc] initWithDatabaseURL:nil]; });
	return service;
}
- (instancetype)init { return [self initWithDatabaseURL:nil]; }
- (instancetype)initWithDatabaseURL:(NSURL *)databaseURL {
	self = [super init];
	if (!self) return nil;
	_databaseURL = [databaseURL copy];
	_subscribers = [NSHashTable weakObjectsHashTable];
	_workerQueue = dispatch_queue_create("com.torrekie.battman.analytics.history",
		dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
	_applicationActive = YES;
	_nextSequenceNumber = 1;
	return self;
}
- (void)dealloc {
	_readCancellation.cancelled = YES;
	if (_timer) dispatch_source_cancel(_timer);
}
- (NSUInteger)subscriberCount {
	NSAssert(NSThread.isMainThread, @"History subscriptions are main-thread only.");
	return self.subscribers.allObjects.count;
}
- (void)addSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber {
	NSParameterAssert(NSThread.isMainThread);
	if (!subscriber) return;
	[self.subscribers addObject:subscriber];
	[self updatePollingState];
	if (self.latestReport) [subscriber analyticsHistoryService:self didPublishReport:self.latestReport];
}
- (void)removeSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber {
	NSParameterAssert(NSThread.isMainThread);
	if (subscriber) [self.subscribers removeObject:subscriber];
	[self updatePollingState];
}
- (void)setApplicationActive:(BOOL)applicationActive {
	NSParameterAssert(NSThread.isMainThread);
	_applicationActive = applicationActive;
	if (applicationActive) self.memoryPressureDefersRetry = NO;
	[self updatePollingState];
}
- (NSTimeInterval)freshCacheRemainingInterval {
	if (!self.latestReport) return -1;
	NSTimeInterval age = [NSDate.date timeIntervalSinceDate:self.latestReport.generatedAt];
	// A clock rollback does not establish freshness. Explicit refreshNow below
	// always remains available even while the cached report is recent.
	return isfinite(age) && age >= 0 && age <= BAHistoryRefreshInterval ? BAHistoryRefreshInterval - age : -1;
}
- (void)updatePollingState {
	BOOL active = self.applicationActive && self.subscribers.allObjects.count > 0;
	if (active == self.polling) return;
	self.polling = active;
	if (!active) {
		self.readCancellation.cancelled = YES;
		self.readCancellation = nil;
		if (self.timer) { dispatch_source_cancel(self.timer); self.timer = nil; }
		return;
	}
	// One cached immutable report, one pending read, bounded rows and four-second I/O budget.
	// A minute-scale timer matches persistent history; live five-second polling remains separate.
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	self.timer = timer;
	NSTimeInterval remaining = [self freshCacheRemainingInterval];
	NSTimeInterval firstDelay = remaining >= 0 ? remaining : BAHistoryRefreshInterval;
	dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(firstDelay * NSEC_PER_SEC)),
		(uint64_t)(BAHistoryRefreshInterval * NSEC_PER_SEC), (uint64_t)(MIN(5.0, firstDelay / 5) * NSEC_PER_SEC));
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(timer, ^{ [weakSelf refreshNow]; });
	dispatch_resume(timer);
	if (remaining < 0) [self refreshNow];
}
- (void)refreshNow {
	NSParameterAssert(NSThread.isMainThread);
	self.memoryPressureDefersRetry = NO;
	[self updatePollingState]; // Drops the timer when the final weak subscriber has disappeared.
#if DEBUG
	NSLog(@"[AnalyticsHistory] refresh active=%d polling=%d subscribers=%lu pending=%d", self.applicationActive, self.polling, (unsigned long)self.subscriberCount, self.acquisitionPending);
#endif
	if (!self.polling || self.acquisitionPending) return;
	self.acquisitionPending = YES;
	BAHistoryReadCancellation *cancellation = [BAHistoryReadCancellation new];
	self.readCancellation = cancellation;
	uint64_t sequence = self.nextSequenceNumber++;
	NSURL *url = self.databaseURL;
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.workerQueue, ^{
		@autoreleasepool {
#if DEBUG
			NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
			NSLog(@"[AnalyticsHistory] read begin sequence=%llu cancelled=%d", (unsigned long long)sequence, cancellation.cancelled);
#endif
			BAAnalyticsReport *report = cancellation.cancelled ? nil : BAAnalyticsReadHistoryReport(url, NSDate.date, sequence, ^BOOL { return cancellation.cancelled; });
#if DEBUG
			NSLog(@"[AnalyticsHistory] read returned sequence=%llu elapsed=%.2f report=%d error=%ld", (unsigned long long)sequence, NSProcessInfo.processInfo.systemUptime - started, report != nil, (long)report.error.code);
#endif
			dispatch_async(dispatch_get_main_queue(), ^{
				BAAnalyticsHistoryService *service = weakSelf;
				if (!service) return;
				service.acquisitionPending = NO;
				[service updatePollingState];
#if DEBUG
				NSLog(@"[AnalyticsHistory] delivery sequence=%llu subscribers=%lu polling=%d cancelled=%d current=%d", (unsigned long long)sequence, (unsigned long)service.subscriberCount, service.polling, cancellation.cancelled, service.readCancellation == cancellation);
#endif
				if (cancellation.cancelled || service.readCancellation != cancellation || !service.polling) {
					// If activation changed during a cancelled read, acquire the new generation now.
					if (service.polling && !service.memoryPressureDefersRetry && service.readCancellation == nil && [service freshCacheRemainingInterval] < 0) [service refreshNow];
					return;
				}
				service.readCancellation = nil;
				service.latestReport = report;
				for (id<BAAnalyticsHistoryServiceSubscriber> subscriber in service.subscribers.allObjects)
					[subscriber analyticsHistoryService:service didPublishReport:report];
			});
		}
	});
}
- (void)handleMemoryPressure {
	NSParameterAssert(NSThread.isMainThread);
	self.latestReport = nil;
	self.memoryPressureDefersRetry = YES;
	self.readCancellation.cancelled = YES;
	self.readCancellation = nil;
	// Keep the minute-scale timer, but do not immediately recreate a large
	// report in response to low memory. A later timer or activation can retry.
}
@end
