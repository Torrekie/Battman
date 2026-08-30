//
//  BAAnalyticsMetricService.m
//  Battman
//


#import "BAAnalyticsMetricService.h"
#import "BAAnalyticsMetricSnapshotInternal.h"

static NSTimeInterval const BAAnalyticsDefaultSampleInterval = 5.0;
static NSUInteger const BAAnalyticsDefaultHistoryPointLimit = 60;

@interface BAAnalyticsMetricService ()
@property (nonatomic, strong) id<BAAnalyticsMetricSource> source;
@property (nonatomic) NSTimeInterval sampleInterval;
@property (nonatomic) NSUInteger maxHistoryPoints;
@property (nonatomic, strong) NSHashTable<id<BAAnalyticsMetricServiceSubscriber>> *subscribers;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@property (nonatomic) BOOL applicationActive;
@property (nonatomic, getter=isPolling) BOOL polling;
@property (nonatomic) uint64_t pollingGeneration;
@property (nonatomic) uint64_t nextSequenceNumber;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<BAAnalyticsMetricPoint *> *> *historyStorage;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@end

@implementation BAAnalyticsMetricService

- (instancetype)initWithSource:(id<BAAnalyticsMetricSource>)source {
	return [self initWithSource:source
				sampleInterval:BAAnalyticsDefaultSampleInterval
			 maxHistoryPoints:BAAnalyticsDefaultHistoryPointLimit];
}

- (instancetype)initWithSource:(id<BAAnalyticsMetricSource>)source
				 sampleInterval:(NSTimeInterval)sampleInterval
			 maxHistoryPoints:(NSUInteger)maxHistoryPoints {
	NSParameterAssert(source != nil);
	self = [super init];
	if (!self)
		return nil;

	_source = source;
	_sampleInterval = MAX(0.05, sampleInterval);
	_maxHistoryPoints = MAX(2, MIN(maxHistoryPoints, (NSUInteger)240));
	_subscribers = [NSHashTable weakObjectsHashTable];
	_workerQueue = dispatch_queue_create("com.torrekie.battman.analytics.metrics", DISPATCH_QUEUE_SERIAL);
	_historyStorage = [NSMutableDictionary dictionary];
	_applicationActive = YES;
	_nextSequenceNumber = 1;
	return self;
}

- (void)dealloc {
	if (_timer)
		dispatch_source_cancel(_timer);
}

- (NSUInteger)subscriberCount {
	NSAssert([NSThread isMainThread], @"Analytics subscriber state is main-thread only.");
	return self.subscribers.allObjects.count;
}

- (void)addSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber {
	NSParameterAssert([NSThread isMainThread]);
	if (!subscriber)
		return;
	[self.subscribers addObject:subscriber];
	[self updatePollingState];
	if (self.latestSnapshot)
		[subscriber analyticsMetricService:self didPublishSnapshot:self.latestSnapshot];
}

- (void)removeSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber {
	NSParameterAssert([NSThread isMainThread]);
	if (subscriber)
		[self.subscribers removeObject:subscriber];
	[self updatePollingState];
}

- (void)setApplicationActive:(BOOL)applicationActive {
	NSParameterAssert([NSThread isMainThread]);
	if (_applicationActive == applicationActive)
		return;
	_applicationActive = applicationActive;
	[self updatePollingState];
}

- (void)refreshNow {
	NSParameterAssert([NSThread isMainThread]);
	if (!self.polling)
		return;
	uint64_t generation = self.pollingGeneration;
	dispatch_async(self.workerQueue, ^{
		[self sampleOnWorkerForGeneration:generation];
	});
}

- (void)handleMemoryPressure {
	dispatch_async(self.workerQueue, ^{
		[self.historyStorage removeAllObjects];
	});
}

- (void)updatePollingState {
	BOOL shouldPoll = self.applicationActive && self.subscribers.allObjects.count > 0;
	if (shouldPoll == self.polling)
		return;
	if (shouldPoll)
		[self startPolling];
	else
		[self stopPolling];
}

- (void)startPolling {
	NSAssert([NSThread isMainThread], @"Analytics polling is coordinated on the main thread.");
	if (self.polling)
		return;

	self.polling = YES;
	self.pollingGeneration += 1;
	uint64_t generation = self.pollingGeneration;
	uint64_t intervalNanoseconds = (uint64_t)(self.sampleInterval * (NSTimeInterval)NSEC_PER_SEC);
	uint64_t leewayNanoseconds = MIN(intervalNanoseconds / 5, (uint64_t)NSEC_PER_SEC);

	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.workerQueue);
	self.timer = timer;
	dispatch_source_set_timer(timer,
						  dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNanoseconds),
						  intervalNanoseconds,
						  leewayNanoseconds);
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(timer, ^{
		[weakSelf sampleOnWorkerForGeneration:generation];
	});
	dispatch_resume(timer);

	dispatch_async(self.workerQueue, ^{
		[weakSelf sampleOnWorkerForGeneration:generation];
	});
}

- (void)stopPolling {
	NSAssert([NSThread isMainThread], @"Analytics polling is coordinated on the main thread.");
	if (!self.polling)
		return;
	self.polling = NO;
	self.pollingGeneration += 1;
	if (self.timer) {
		dispatch_source_cancel(self.timer);
		self.timer = nil;
	}
}

- (NSArray<NSString *> *)historyMetricIdentifiers {
	static NSArray<NSString *> *identifiers;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		identifiers = @[
			BAAnalyticsMetricStateOfChargePercent,
			BAAnalyticsMetricAverageTemperatureCelsius,
			BAAnalyticsMetricAveragePowerWatts,
			BAAnalyticsMetricRemainingCapacityMilliampHours,
		];
	});
	return identifiers;
}

- (void)sampleOnWorkerForGeneration:(uint64_t)generation {
	@autoreleasepool {
		NSDictionary<NSString *, NSNumber *> *values = [self.source readAnalyticsMetricValues] ?: @{};
		NSDate *timestamp = [NSDate date];
		for (NSString *metricIdentifier in [self historyMetricIdentifiers]) {
			NSNumber *value = values[metricIdentifier];
			if (![value isKindOfClass:[NSNumber class]])
				continue;
			NSMutableArray<BAAnalyticsMetricPoint *> *history = self.historyStorage[metricIdentifier];
			if (!history) {
				history = [NSMutableArray array];
				self.historyStorage[metricIdentifier] = history;
			}
			[history addObject:[[BAAnalyticsMetricPoint alloc] initWithTimestamp:timestamp value:value.doubleValue]];
			if (history.count > self.maxHistoryPoints)
				[history removeObjectsInRange:NSMakeRange(0, history.count - self.maxHistoryPoints)];
		}

		NSMutableDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *histories = [NSMutableDictionary dictionaryWithCapacity:self.historyStorage.count];
		[self.historyStorage enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableArray<BAAnalyticsMetricPoint *> *history, BOOL *stop) {
			(void)stop;
			histories[key] = [history copy];
		}];

		BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:self.nextSequenceNumber++
														 timestamp:timestamp
															values:values
														 histories:histories];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!self.polling || generation != self.pollingGeneration)
				return;
			self.latestSnapshot = snapshot;
			for (id<BAAnalyticsMetricServiceSubscriber> subscriber in self.subscribers.allObjects)
				[subscriber analyticsMetricService:self didPublishSnapshot:snapshot];
		});
	}
}

@end
