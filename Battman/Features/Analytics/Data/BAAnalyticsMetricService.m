//
//  BAAnalyticsMetricService.m
//  Battman
//


#import "BAAnalyticsMetricService.h"
#import "BAAnalyticsMetricSnapshotInternal.h"
#import "../../../BattmanDataPaths.h"

static NSHashTable<BAAnalyticsMetricService *> *BAMetricServices;
static BOOL BAMetricDataWipeRequested;

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
@property (nonatomic, copy, nullable) NSURL *startupCacheURL;
@property (nonatomic) NSTimeInterval lastCacheWriteUptime;
@property (nonatomic) BOOL preparedForDataWipe;
@end

@implementation BAAnalyticsMetricService

- (void)enableStartupCache {
	[self enableStartupCacheAtURL:[BattmanAnalyticsCacheDirectoryURL() URLByAppendingPathComponent:@"instant.plist"]];
}

- (void)enableStartupCacheAtURL:(NSURL *)cacheURL {
	NSParameterAssert(NSThread.isMainThread);
	if (!cacheURL.isFileURL || self.startupCacheURL || self.preparedForDataWipe) return;
	self.startupCacheURL = cacheURL;
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.workerQueue, ^{
		@autoreleasepool {
			NSNumber *size = nil;
			[cacheURL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
			NSData *bytes = size.unsignedLongLongValue <= 512 * 1024 ? [NSData dataWithContentsOfURL:cacheURL options:0 error:NULL] : nil;
			id root = bytes ? [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:NULL] : nil;
			BAAnalyticsMetricSnapshot *snapshot = nil;
			if ([root isKindOfClass:NSDictionary.class] && [root[@"version"] isEqual:@1] && [root[@"timestamp"] isKindOfClass:NSDate.class]) {
				NSTimeInterval age = [NSDate.date timeIntervalSinceDate:root[@"timestamp"]];
				NSDictionary *values = root[@"values"], *encodedHistories = root[@"histories"];
				BOOL valid = isfinite(age) && age >= 0 && age <= 86400 && [values isKindOfClass:NSDictionary.class] && values.count <= 64 &&
					[encodedHistories isKindOfClass:NSDictionary.class] && encodedHistories.count <= 64;
				NSMutableDictionary *histories = [NSMutableDictionary dictionary];
				for (id key in valid ? values : @{}) {
					if (![key isKindOfClass:NSString.class] || [key length] > 128 || ![values[key] isKindOfClass:NSNumber.class] || !isfinite([values[key] doubleValue])) valid = NO;
				}
				for (id key in valid ? encodedHistories : @{}) {
					id points = encodedHistories[key];
					if (![key isKindOfClass:NSString.class] || [key length] > 128 || ![points isKindOfClass:NSArray.class] || [points count] > 240) { valid = NO; break; }
					NSMutableArray *decoded = [NSMutableArray array];
					NSDate *previous = nil;
					for (id point in points) {
						if (![point isKindOfClass:NSArray.class] || [point count] != 2 || ![point[0] isKindOfClass:NSDate.class] ||
							![point[1] isKindOfClass:NSNumber.class] || !isfinite([point[1] doubleValue]) ||
							!isfinite([root[@"timestamp"] timeIntervalSinceDate:point[0]]) ||
							[point[0] compare:root[@"timestamp"]] == NSOrderedDescending ||
							(previous && [point[0] compare:previous] != NSOrderedDescending) ||
							[root[@"timestamp"] timeIntervalSinceDate:point[0]] > 86400) { valid = NO; break; }
						[decoded addObject:[[BAAnalyticsMetricPoint alloc] initWithTimestamp:point[0] value:[point[1] doubleValue]]];
						previous = point[0];
					}
					histories[key] = decoded;
				}
				if (valid) snapshot = [[[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:0 timestamp:root[@"timestamp"] values:values histories:histories] snapshotByMarkingCached];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				BAAnalyticsMetricService *service = weakSelf;
				if (!snapshot || !service || service.preparedForDataWipe || service.latestSnapshot) return;
				service.latestSnapshot = snapshot;
				for (id<BAAnalyticsMetricServiceSubscriber> subscriber in service.subscribers.allObjects)
					[subscriber analyticsMetricService:service didPublishSnapshot:snapshot];
			});
		}
	});
}

- (void)storeSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSTimeInterval uptime = NSProcessInfo.processInfo.systemUptime;
	if (!self.startupCacheURL || !snapshot.values.count || (self.lastCacheWriteUptime && uptime - self.lastCacheWriteUptime < 30)) return;
	NSMutableDictionary *histories = [NSMutableDictionary dictionary];
	for (NSString *key in snapshot.histories) {
		NSMutableArray *points = [NSMutableArray array];
		for (BAAnalyticsMetricPoint *point in snapshot.histories[key]) [points addObject:@[point.timestamp, @(point.value)]];
		histories[key] = points;
	}
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"version": @1, @"timestamp": snapshot.timestamp, @"values": snapshot.values, @"histories": histories}
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	if (!data || data.length > 512 * 1024) return;
	NSURL *directory = self.startupCacheURL.URLByDeletingLastPathComponent;
	if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL]) return;
	[directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
	if ([data writeToURL:self.startupCacheURL options:NSDataWritingAtomic error:NULL]) self.lastCacheWriteUptime = uptime;
}

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
	@synchronized(BAAnalyticsMetricService.class) {
		if (!BAMetricServices) BAMetricServices = [NSHashTable weakObjectsHashTable];
		[BAMetricServices addObject:self];
		_preparedForDataWipe = BAMetricDataWipeRequested;
	}
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

- (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion {
	NSParameterAssert(NSThread.isMainThread);
	self.preparedForDataWipe = YES;
	self.latestSnapshot = nil;
	[self updatePollingState];
	dispatch_async(self.workerQueue, ^{
		[self.historyStorage removeAllObjects];
		dispatch_async(dispatch_get_main_queue(), completion);
	});
}

+ (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion {
	NSParameterAssert(NSThread.isMainThread);
	NSArray<BAAnalyticsMetricService *> *services;
	@synchronized(BAAnalyticsMetricService.class) {
		BAMetricDataWipeRequested = YES;
		services = BAMetricServices.allObjects;
	}
	dispatch_group_t pending = dispatch_group_create();
	for (BAAnalyticsMetricService *service in services) {
		dispatch_group_enter(pending);
		[service prepareForDataWipeWithCompletion:^{ dispatch_group_leave(pending); }];
	}
	dispatch_group_notify(pending, dispatch_get_main_queue(), completion);
}

- (void)updatePollingState {
	BOOL shouldPoll = !self.preparedForDataWipe && self.applicationActive && self.subscribers.allObjects.count > 0;
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
		BAAnalyticsMetricSnapshot *display = !snapshot.values.count && self.latestSnapshot.values.count ?
			[self.latestSnapshot snapshotByMarkingCached] : snapshot;
		self.latestSnapshot = display;
		for (id<BAAnalyticsMetricServiceSubscriber> subscriber in self.subscribers.allObjects)
			[subscriber analyticsMetricService:self didPublishSnapshot:display];
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
		BAAnalyticsMetricSnapshot *snapshot;
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

			snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:self.nextSequenceNumber++
															 timestamp:timestamp
																values:values
															 histories:histories];
			[self finishSample:snapshot generation:generation];
		}
		// Persistence runs outside the polling lock used by foreground lifecycle calls.
		[self storeSnapshot:snapshot];
	}
}

@end
