//
//  BAAnalyticsMetricService.m
//  Battman
//


#import "BAAnalyticsMetricService.h"
#import "BAAnalyticsMetricSnapshotInternal.h"

#include <math.h>

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
@property (nonatomic) BOOL sampleScheduled;
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
	_sampleInterval = isfinite(sampleInterval) ? MAX(0.05, MIN(sampleInterval, 3600.0)) : BAAnalyticsDefaultSampleInterval;
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
	[self updatePollingState];
	if (!self.polling)
		return;
	[self enqueueSampleForGeneration:self.pollingGeneration];
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

	@synchronized(self) {
		self.polling = YES;
		self.pollingGeneration += 1;
	}
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
		[weakSelf enqueueSampleForGeneration:generation];
	});
	dispatch_resume(timer);

	[self enqueueSampleForGeneration:generation];
}

- (void)stopPolling {
	NSAssert([NSThread isMainThread], @"Analytics polling is coordinated on the main thread.");
	if (!self.polling)
		return;
	@synchronized(self) {
		self.polling = NO;
		self.pollingGeneration += 1;
	}
	if (self.timer) {
		dispatch_source_cancel(self.timer);
		self.timer = nil;
	}
}

- (NSArray<NSString *> *)historyMetricIdentifiers {
	static NSArray<NSString *> *identifiers;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSMutableArray<NSString *> *metrics = [NSMutableArray arrayWithArray:@[
			BAAnalyticsMetricStateOfChargePercent,
			BAAnalyticsMetricAverageTemperatureCelsius,
			BAAnalyticsMetricAverageCurrentMilliamps,
			BAAnalyticsMetricVoltageMillivolts,
			BAAnalyticsMetricAveragePowerWatts,
			BAAnalyticsMetricBatteryNetPowerWatts,
			BAAnalyticsMetricRemainingCapacityMilliampHours,
			BAAnalyticsMetricExternalConnected,
			BAAnalyticsMetricIsCharging,
			BAAnalyticsMetricFullyCharged,
			BAAnalyticsMetricInputCurrentMilliamps,
			BAAnalyticsMetricInputVoltageMillivolts,
			BAAnalyticsMetricInputPowerWatts,
		]];
		// SMC's single-character cell index supports 0...9, not a fixed three
		// cells. Missing keys never get an artificial zero in these histories.
		for (NSUInteger index = 0; index < 10; index++)
			[metrics addObject:BAAnalyticsCellVoltageMetricIdentifier(index)];
		identifiers = [metrics copy];
	});
	return identifiers;
}

- (void)enqueueSampleForGeneration:(uint64_t)generation {
	// Recheck weak subscribers on the main thread even when the last one was
	// released without an explicit unsubscribe. Collapse bursts of refreshes
	// while an acquisition is already pending.
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf enqueueSampleForGeneration:generation];
		});
		return;
	}
	[self updatePollingState];
	if (!self.polling || generation != self.pollingGeneration || self.sampleScheduled)
		return;
	self.sampleScheduled = YES;
	dispatch_async(self.workerQueue, ^{
		[self sampleOnWorkerForGeneration:generation];
	});
}

- (void)finishSample:(BAAnalyticsMetricSnapshot *)snapshot generation:(uint64_t)generation {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.sampleScheduled = NO;
		[self updatePollingState];
		if (!self.polling)
			return;
		if (generation != self.pollingGeneration) {
			[self enqueueSampleForGeneration:self.pollingGeneration];
			return;
		}
		if (!snapshot)
			return;
		self.latestSnapshot = snapshot;
		for (id<BAAnalyticsMetricServiceSubscriber> subscriber in self.subscribers.allObjects)
			[subscriber analyticsMetricService:self didPublishSnapshot:snapshot];
	});
}

- (void)sampleOnWorkerForGeneration:(uint64_t)generation {
	@autoreleasepool {
		@synchronized(self) {
			if (!self.polling || generation != self.pollingGeneration) {
				[self finishSample:nil generation:generation];
				return;
			}
		}
		NSDate *timestamp = [NSDate date];
		NSDictionary<NSString *, NSNumber *> *values = [self.source readAnalyticsMetricValues] ?: @{};
		@synchronized(self) {
			if (!self.polling || generation != self.pollingGeneration) {
				[self finishSample:nil generation:generation];
				return;
			}
			NSTimeInterval historyDuration = self.sampleInterval * (NSTimeInterval)self.maxHistoryPoints;
			NSDate *cutoff = [timestamp dateByAddingTimeInterval:-historyDuration];
			for (NSString *metricIdentifier in [self historyMetricIdentifiers]) {
				NSMutableArray<BAAnalyticsMetricPoint *> *history = self.historyStorage[metricIdentifier];
				// Prune absent metrics as well as present ones. A foreground-only
				// five-minute window must not retain yesterday's last good reading.
				while (history.count > 0 && [history.firstObject.timestamp compare:cutoff] == NSOrderedAscending)
					[history removeObjectAtIndex:0];
				if (history.count > 0 && [history.lastObject.timestamp compare:timestamp] != NSOrderedAscending)
					[history removeAllObjects]; // A wall-clock jump splits the live run.
				NSNumber *value = values[metricIdentifier];
				if (![value isKindOfClass:[NSNumber class]] || !isfinite(value.doubleValue))
					continue;
				// The v1 finite-point history has no missing-value marker. Begin a
				// new run after a missed sample instead of drawing through that gap.
				if (history.count > 0 && [timestamp timeIntervalSinceDate:history.lastObject.timestamp] > self.sampleInterval * 1.5)
					[history removeAllObjects];
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
			[self finishSample:snapshot generation:generation];
		}
	}
}

@end
