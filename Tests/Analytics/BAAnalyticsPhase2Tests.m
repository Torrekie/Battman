#import <Foundation/Foundation.h>

// Isolated services use explicitly injected fixture paths, never application data.
const char *battman_config_dir(void) { return NULL; }

#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricService.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsSystemMetricSource.h"
#import "../../Battman/Features/Analytics/Host/BAAnalyticsCardLayoutStore.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void Assert(BOOL condition, const char *message) {
	if (condition)
		return;
	fprintf(stderr, "Assertion failed: %s\n", message);
	exit(1);
}

static void PumpRunLoop(NSTimeInterval duration) {
	NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:duration];
	while ([limit timeIntervalSinceNow] > 0.0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static BOOL WaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
	NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && [limit timeIntervalSinceNow] > 0.0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	return condition();
}

@interface FakeMetricSource : NSObject <BAAnalyticsMetricSource>
@property (nonatomic) NSUInteger readCount;
- (NSUInteger)safeReadCount;
@end

@implementation FakeMetricSource

- (NSDictionary<NSString *, NSNumber *> *)readAnalyticsMetricValues {
	NSUInteger count = 0;
	@synchronized(self) {
		self.readCount += 1;
		count = self.readCount;
	}
	return @{
		BAAnalyticsMetricStateOfChargePercent: @(50 + count),
		BAAnalyticsMetricRemainingCapacityMilliampHours: @(2000 - count),
	};
}

- (NSUInteger)safeReadCount {
	@synchronized(self) {
		return self.readCount;
	}
}

@end

@interface MetricSubscriber : NSObject <BAAnalyticsMetricServiceSubscriber>
@property (nonatomic, strong) NSMutableArray<BAAnalyticsMetricSnapshot *> *snapshots;
@property (nonatomic) BOOL allDeliveriesWereOnMainThread;
@end

@implementation MetricSubscriber

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	_snapshots = [NSMutableArray array];
	_allDeliveriesWereOnMainThread = YES;
	return self;
}

- (void)analyticsMetricService:(BAAnalyticsMetricService *)service didPublishSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	self.allDeliveriesWereOnMainThread = self.allDeliveriesWereOnMainThread && [NSThread isMainThread];
	[self.snapshots addObject:snapshot];
}

@end

static void TestSnapshotImmutability(void) {
	NSMutableDictionary *values = [@{BAAnalyticsMetricStateOfChargePercent: @42} mutableCopy];
	BAAnalyticsMetricPoint *point = [[BAAnalyticsMetricPoint alloc] initWithTimestamp:[NSDate dateWithTimeIntervalSince1970:1] value:42.0];
	NSMutableArray *points = [NSMutableArray arrayWithObject:point];
	NSMutableDictionary *histories = [@{BAAnalyticsMetricStateOfChargePercent: points} mutableCopy];
	values[@"invalid.nan"] = @(NAN);

	BAAnalyticsMetricSnapshot *snapshot = [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:7
														 timestamp:[NSDate dateWithTimeIntervalSince1970:2]
															values:values
														 histories:histories];
	values[BAAnalyticsMetricStateOfChargePercent] = @99;
	[points removeAllObjects];

	Assert([[snapshot valueForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent] integerValue] == 42, "snapshot copied mutable values");
	Assert([snapshot historyForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent].count == 1, "snapshot copied mutable histories");
	Assert([snapshot valueForMetricIdentifier:@"invalid.nan"] == nil, "snapshot discarded non-finite metric");
	Assert([snapshot copy] == snapshot, "immutable snapshot copy returns itself");
	BAAnalyticsMetricSnapshot *cached = [snapshot snapshotByMarkingCached];
	Assert(!snapshot.isCached && cached.isCached, "cached provenance did not mutate the original snapshot");
	Assert([cached.timestamp isEqual:snapshot.timestamp] && [cached.values isEqual:snapshot.values], "cached provenance preserved the captured timestamp and values");
	Assert([cached historyForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent].firstObject == point, "cached provenance preserved immutable history points");
}

static void TestSystemTemperatureMetricMapping(void) {
	NSMutableDictionary<NSString *, NSNumber *> *values = [NSMutableDictionary dictionary];
	BAAnalyticsRecordTemperatureMetric(values, -1.0f);
	Assert(values[BAAnalyticsMetricAverageTemperatureCelsius] == nil, "temperature read-failure sentinel stayed unavailable");
	BAAnalyticsRecordTemperatureMetric(values, NAN);
	Assert(values[BAAnalyticsMetricAverageTemperatureCelsius] == nil, "non-finite temperature stayed unavailable");
	BAAnalyticsRecordTemperatureMetric(values, -50.01f);
	Assert(values[BAAnalyticsMetricAverageTemperatureCelsius] == nil, "out-of-range cold temperature stayed unavailable");
	BAAnalyticsRecordTemperatureMetric(values, 120.01f);
	Assert(values[BAAnalyticsMetricAverageTemperatureCelsius] == nil, "out-of-range hot temperature stayed unavailable");

	BAAnalyticsRecordTemperatureMetric(values, -2.0f);
	NSNumber *coldTemperature = values[BAAnalyticsMetricAverageTemperatureCelsius];
	Assert(coldTemperature != nil && fabs(coldTemperature.doubleValue + 2.0) < 0.001, "valid cold temperature remained available");
	BAAnalyticsRecordTemperatureMetric(values, 31.25f);
	NSNumber *normalTemperature = values[BAAnalyticsMetricAverageTemperatureCelsius];
	Assert(normalTemperature != nil && fabs(normalTemperature.doubleValue - 31.25) < 0.001, "valid temperature remained available");
	BAAnalyticsRecordTemperatureMetric(values, -1.0f);
	Assert(values[BAAnalyticsMetricAverageTemperatureCelsius] == nil, "temperature read failure did not retain a stale metric");
}

static void TestLayoutMigrationAndBounds(void) {
	NSString *suiteName = [@"com.torrekie.battman.tests.analytics." stringByAppendingString:[NSUUID UUID].UUIDString];
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
	[defaults removePersistentDomainForName:suiteName];
	[defaults setObject:@[
		@{@"id": @"battery.summary", @"size": @0},
		@{@"id": @"battery.summary", @"size": @1},
		@{@"id": @"future.vendor.card", @"size": @3},
		@{@"id": @"broken", @"size": @99},
	] forKey:BAAnalyticsLegacyCardLayoutDefaultsKey];

	NSArray<BAAnalyticsCardLayoutRecord *> *records = [BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:defaults];
	Assert(records.count == 2, "layout parser bounded invalid and duplicate entries");
	Assert([records[0].cardIdentifier isEqualToString:@"com.torrekie.battman.analytics.live"], "legacy built-in identifier migrated");
	Assert([records[1].cardIdentifier isEqualToString:@"future.vendor.card"], "unknown provider identifier preserved");

	NSMutableDictionary *mutableState = [@{@"selection": @"week"} mutableCopy];
	BAAnalyticsCardLayoutRecord *saved = [[BAAnalyticsCardLayoutRecord alloc] initWithCardIdentifier:@"future.vendor.card"
																	 displayName:@"Future Card"
																	   sizeValue:2
													 restorationSchemaVersion:4
															 restorationState:mutableState];
	mutableState[@"selection"] = @"day";
	[BAAnalyticsCardLayoutStore saveRecords:@[saved] toUserDefaults:defaults];
	records = [BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:defaults];
	Assert(records.count == 1, "v3 layout round trip");
	Assert([records[0].restorationState[@"selection"] isEqual:@"week"], "restoration state copied immutably");
	Assert(records[0].restorationSchemaVersion == 4, "restoration schema preserved");
	[defaults setObject:@{@"version": @3, @"cards": @[
		@{@"id": @"builtin.live", @"size": @0, @"restorationSchemaVersion": @9, @"restorationState": @{@"obsolete": @YES}},
		@{@"id": @"com.torrekie.battman.analytics.live", @"size": @2},
		@{@"id": @"com.torrekie.battman.analytics.temperature.average", @"size": @1},
		@{@"id": @"future.vendor.card", @"size": @3, @"restorationSchemaVersion": @4, @"restorationState": @{@"selection": @"week"}},
	]} forKey:BAAnalyticsCardLayoutDefaultsKey];
	records = [BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:defaults];
	Assert(records.count == 3, "migrated aliases deduplicated");
	Assert([records[0].cardIdentifier isEqualToString:@"com.torrekie.battman.analytics.live"] && records[0].restorationSchemaVersion == 0 && records[0].restorationState == nil, "retired template state reset during migration");
	Assert([records[1].cardIdentifier isEqualToString:@"com.torrekie.battman.analytics.session"], "old namespaced template migrated");
	Assert(records[2].restorationSchemaVersion == 4 && [records[2].restorationState[@"selection"] isEqual:@"week"], "third-party restoration preserved during migration");

	NSString *oversized = [@"x" stringByPaddingToLength:20000 withString:@"x" startingAtIndex:0];
	BAAnalyticsCardLayoutRecord *bounded = [[BAAnalyticsCardLayoutRecord alloc] initWithCardIdentifier:@"future.vendor.large"
																	   displayName:@"Large"
																		 sizeValue:0
													   restorationSchemaVersion:1
															   restorationState:@{@"payload": oversized}];
	Assert(bounded.restorationState == nil, "oversized restoration state rejected");
	[defaults removePersistentDomainForName:suiteName];
}

static void TestVisibleOnlyMetricService(void) {
	FakeMetricSource *source = [FakeMetricSource new];
	MetricSubscriber *subscriber = [MetricSubscriber new];
	BAAnalyticsMetricService *service = [[BAAnalyticsMetricService alloc] initWithSource:source sampleInterval:0.05 maxHistoryPoints:3];

	PumpRunLoop(0.10);
	Assert([source safeReadCount] == 0, "service does not sample without subscribers");
	[service addSubscriber:subscriber];
	Assert(service.isPolling, "first visible subscriber starts polling");
	Assert(WaitUntil(^BOOL{ return subscriber.snapshots.count >= 4; }, 1.0), "service published periodic snapshots");
	Assert(subscriber.allDeliveriesWereOnMainThread, "snapshot delivery stayed on main thread");
	BAAnalyticsMetricSnapshot *latest = subscriber.snapshots.lastObject;
	Assert([latest historyForMetricIdentifier:BAAnalyticsMetricRemainingCapacityMilliampHours].count == 3, "history is bounded");

	[service removeSubscriber:subscriber];
	Assert(!service.isPolling, "last visible subscriber stops polling");
	PumpRunLoop(0.08);
	NSUInteger stoppedReadCount = [source safeReadCount];
	PumpRunLoop(0.15);
	Assert([source safeReadCount] == stoppedReadCount, "sampling remains stopped while no card is visible");

	[service setApplicationActive:NO];
	[service addSubscriber:subscriber];
	Assert(!service.isPolling, "background state suppresses polling");
	PumpRunLoop(0.10);
	Assert([source safeReadCount] == stoppedReadCount, "background subscriber does not sample");
	[service setApplicationActive:YES];
	Assert(WaitUntil(^BOOL{ return [source safeReadCount] > stoppedReadCount; }, 1.0), "foreground resumes sampling");
	[service removeSubscriber:subscriber];
}

static dispatch_queue_t MetricWorkerQueue(BAAnalyticsMetricService *service) {
	return (dispatch_queue_t)[service valueForKey:@"workerQueue"];
}

static void DrainMetricWorker(BAAnalyticsMetricService *service) {
	__block BOOL complete = NO;
	dispatch_async(MetricWorkerQueue(service), ^{
		dispatch_async(dispatch_get_main_queue(), ^{ complete = YES; });
	});
	Assert(WaitUntil(^BOOL{ return complete; }, 2.0), "metric worker completed its bounded cache work");
}

static NSURL *MakeMetricCacheDirectory(void) {
	NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
		[@"BattmanMetricCacheTests." stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
	Assert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL], "created isolated metric cache fixture directory");
	return directory;
}

static void AssertCachedHistoriesMatchDocument(BAAnalyticsMetricSnapshot *snapshot, NSDictionary *document) {
	Assert([snapshot.timestamp isEqual:document[@"timestamp"]], "startup cache preserved original evidence time");
	Assert([snapshot.values isEqual:document[@"values"]], "startup cache preserved all captured values");
	NSDictionary *histories = document[@"histories"];
	Assert(snapshot.histories.count == histories.count, "startup cache preserved available history fields");
	for (NSString *identifier in histories) {
		NSArray *encoded = histories[identifier];
		NSArray<BAAnalyticsMetricPoint *> *decoded = [snapshot historyForMetricIdentifier:identifier];
		Assert(decoded.count == encoded.count, "startup cache preserved history point count");
		for (NSUInteger index = 0; index < decoded.count; index++) {
			Assert([decoded[index].timestamp isEqual:encoded[index][0]], "startup cache preserved each history timestamp");
			Assert(decoded[index].value == [encoded[index][1] doubleValue], "startup cache preserved each history value");
		}
	}
}

static void TestMetricStartupCacheLifecycle(void) {
	NSURL *directory = MakeMetricCacheDirectory();
	NSURL *file = [directory URLByAppendingPathComponent:@"instant.plist"];
	@try {
		FakeMetricSource *warmSource = [FakeMetricSource new];
		MetricSubscriber *warmSubscriber = [MetricSubscriber new];
		BAAnalyticsMetricService *warm = [[BAAnalyticsMetricService alloc] initWithSource:warmSource sampleInterval:30 maxHistoryPoints:3];
		[warm enableStartupCacheAtURL:file];
		__block BOOL writeHeartbeat = NO;
		dispatch_async(dispatch_get_main_queue(), ^{ writeHeartbeat = YES; });
		[warm addSubscriber:warmSubscriber];
		Assert(WaitUntil(^BOOL{ return warm.latestSnapshot && [NSFileManager.defaultManager fileExistsAtPath:file.path]; }, 2.0), "completed live acquisition persisted a startup snapshot");
		Assert(writeHeartbeat && warmSubscriber.allDeliveriesWereOnMainThread, "main-thread heartbeat and snapshot delivery progressed during cache write");
		Assert(!warm.latestSnapshot.isCached, "new acquisition carried live provenance");
		[warm removeSubscriber:warmSubscriber];
		DrainMetricWorker(warm);
		NSDictionary *stored = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfURL:file] options:NSPropertyListImmutable format:NULL error:NULL];
		Assert([stored isKindOfClass:NSDictionary.class] && [stored[@"values"] count] > 0, "startup cache contained the completed values");
		AssertCachedHistoriesMatchDocument(warm.latestSnapshot, stored);

		FakeMetricSource *coldSource = [FakeMetricSource new];
		MetricSubscriber *coldSubscriber = [MetricSubscriber new];
		BAAnalyticsMetricService *cold = [[BAAnalyticsMetricService alloc] initWithSource:coldSource sampleInterval:30 maxHistoryPoints:3];
		[cold setApplicationActive:NO];
		// Hold the existing worker briefly: a synchronous restore would either
		// block the heartbeat or publish before that worker can consume the file.
		dispatch_semaphore_t release = dispatch_semaphore_create(0);
		__block BOOL workerHeld = NO, readHeartbeat = NO;
		dispatch_async(MetricWorkerQueue(cold), ^{
			dispatch_async(dispatch_get_main_queue(), ^{ workerHeld = YES; });
			dispatch_semaphore_wait(release, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
		});
		Assert(WaitUntil(^BOOL{ return workerHeld; }, 1.0), "held the metric cache worker for the async lifecycle check");
		NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
		[cold enableStartupCacheAtURL:file];
		[cold addSubscriber:coldSubscriber];
		Assert(NSProcessInfo.processInfo.systemUptime - started < .25, "startup cache scheduling did not wait for disk worker");
		dispatch_async(dispatch_get_main_queue(), ^{
			readHeartbeat = YES;
			Assert(cold.latestSnapshot == nil, "cache restoration stayed behind the held worker");
			dispatch_semaphore_signal(release);
		});
		Assert(WaitUntil(^BOOL{ return readHeartbeat; }, .5), "main-thread heartbeat progressed while cache read was pending");
		Assert(WaitUntil(^BOOL{ return cold.latestSnapshot.isCached; }, 2.0), "inactive service restored completed startup evidence");
		Assert(!cold.isPolling && coldSource.safeReadCount == 0, "startup restore did not acquire hardware while inactive");
		Assert(coldSubscriber.snapshots.count == 1 && coldSubscriber.allDeliveriesWereOnMainThread, "cached snapshot was published once on the main thread");
		BAAnalyticsMetricSnapshot *cached = cold.latestSnapshot;
		AssertCachedHistoriesMatchDocument(cached, stored);

		[cold setApplicationActive:YES];
		Assert(WaitUntil(^BOOL{ return cold.latestSnapshot && !cold.latestSnapshot.isCached; }, 2.0), "activation replaced startup evidence with a new live snapshot");
		BAAnalyticsMetricSnapshot *fresh = cold.latestSnapshot;
		Assert(coldSource.safeReadCount == 1 && fresh.sequenceNumber > cached.sequenceNumber, "fresh acquisition resumed the live sequence");
		NSArray<BAAnalyticsMetricPoint *> *live = [fresh historyForMetricIdentifier:BAAnalyticsMetricStateOfChargePercent];
		Assert(live.count == 1 && [live.firstObject.timestamp isEqual:fresh.timestamp], "cached history did not join the new foreground run");
		Assert(![live.firstObject.timestamp isEqual:cached.timestamp], "new foreground run did not relabel an old cached point");
		Assert(cached.isCached && [cached.timestamp isEqual:stored[@"timestamp"]], "fresh publication did not mutate cached evidence");
		[cold removeSubscriber:coldSubscriber];
		DrainMetricWorker(cold);
	} @finally {
		[NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
	}
}

static BAAnalyticsMetricSnapshot *RestoreMetricCacheFixture(NSURL *directory, NSString *name, id document) {
	NSURL *file = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
	NSData *data = [document isKindOfClass:NSData.class] ? document : [NSPropertyListSerialization dataWithPropertyList:document format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
	Assert(data && [data writeToURL:file options:NSDataWritingAtomic error:NULL], "wrote isolated startup cache fixture");
	FakeMetricSource *source = [FakeMetricSource new];
	MetricSubscriber *subscriber = [MetricSubscriber new];
	BAAnalyticsMetricService *service = [[BAAnalyticsMetricService alloc] initWithSource:source sampleInterval:30 maxHistoryPoints:3];
	[service setApplicationActive:NO];
	[service addSubscriber:subscriber];
	[service enableStartupCacheAtURL:file];
	DrainMetricWorker(service);
	Assert(source.safeReadCount == 0 && !service.isPolling && subscriber.allDeliveriesWereOnMainThread, "fixture cache decode remained independent of hardware acquisition");
	Assert(subscriber.snapshots.count == (service.latestSnapshot ? 1 : 0), "fixture cache published only accepted evidence");
	[service removeSubscriber:subscriber];
	return service.latestSnapshot;
}

static void TestMetricStartupCacheValidation(void) {
	NSURL *directory = MakeMetricCacheDirectory();
	@try {
		NSDate *timestamp = [NSDate dateWithTimeIntervalSinceNow:-60];
		NSDate *previous = [timestamp dateByAddingTimeInterval:-30];
		NSDictionary *valid = @{@"version":@1, @"timestamp":timestamp,
			@"values":@{BAAnalyticsMetricStateOfChargePercent:@73, BAAnalyticsMetricAverageTemperatureCelsius:@31.25},
			@"histories":@{BAAnalyticsMetricStateOfChargePercent:@[@[previous,@72], @[timestamp,@73]]}};
		BAAnalyticsMetricSnapshot *restored = RestoreMetricCacheFixture(directory, @"valid", valid);
		Assert(restored.isCached, "valid synthetic startup evidence was marked cached");
		AssertCachedHistoriesMatchDocument(restored, valid);
		Assert([restored historyForMetricIdentifier:BAAnalyticsMetricAverageTemperatureCelsius].count == 0, "cache did not invent history for a value-only metric");

		NSArray<NSDictionary *> *invalid = @[
			@{@"name":@"version", @"changes":@{@"version":@2}},
			@{@"name":@"future", @"changes":@{@"timestamp":[NSDate dateWithTimeIntervalSinceNow:120]}},
			@{@"name":@"expired", @"changes":@{@"timestamp":[NSDate dateWithTimeIntervalSinceNow:-90000]}},
			@{@"name":@"invalid-value", @"changes":@{@"values":@{BAAnalyticsMetricStateOfChargePercent:@"73"}}},
			@{@"name":@"nonfinite-value", @"changes":@{@"values":@{BAAnalyticsMetricStateOfChargePercent:@(NAN)}}},
			@{@"name":@"reversed-history", @"changes":@{@"histories":@{BAAnalyticsMetricStateOfChargePercent:@[@[timestamp,@73], @[previous,@72]]}}},
			@{@"name":@"future-point", @"changes":@{@"histories":@{BAAnalyticsMetricStateOfChargePercent:@[@[[timestamp dateByAddingTimeInterval:1],@73]]}}},
			@{@"name":@"oversized", @"changes":@{@"padding":[@"x" stringByPaddingToLength:512*1024 withString:@"x" startingAtIndex:0]}},
		];
		for (NSDictionary *fixture in invalid) {
			NSMutableDictionary *document = valid.mutableCopy;
			[document addEntriesFromDictionary:fixture[@"changes"]];
			Assert(RestoreMetricCacheFixture(directory, fixture[@"name"], document) == nil, "invalid, future, expired or oversized startup cache was rejected");
		}
		Assert(RestoreMetricCacheFixture(directory, @"malformed", [@"not a property list" dataUsingEncoding:NSUTF8StringEncoding]) == nil, "malformed startup cache was rejected");
	} @finally {
		[NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
	}
}

@interface BAAnalyticsMetricService (MetricWriterTest)
- (void)storeSnapshot:(BAAnalyticsMetricSnapshot *)snapshot;
@end
@interface GatedMetricWriter : BAAnalyticsMetricService
@property (nonatomic, strong) dispatch_semaphore_t writerGate;
@property (atomic) BOOL writerEntered;
@end
@implementation GatedMetricWriter
- (void)storeSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	self.writerEntered = YES;
	dispatch_semaphore_wait(self.writerGate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
	[super storeSnapshot:snapshot];
}
@end

static void TestMetricDataWipeBarrier(void) {
	NSURL *directory = MakeMetricCacheDirectory(), *file = [directory URLByAppendingPathComponent:@"instant.plist"];
	FakeMetricSource *source = [FakeMetricSource new];
	GatedMetricWriter *service = [[GatedMetricWriter alloc] initWithSource:source sampleInterval:30 maxHistoryPoints:3];
	service.writerGate = dispatch_semaphore_create(0);
	MetricSubscriber *subscriber = [MetricSubscriber new];
	@try {
		[service enableStartupCacheAtURL:file]; [service addSubscriber:subscriber];
		Assert(WaitUntil(^BOOL { return service.writerEntered && service.latestSnapshot; }, 2),
			"metric cache write can remain pending after snapshot publication");
		__block BOOL complete = NO, heartbeat = NO;
		[BAAnalyticsMetricService prepareForDataWipeWithCompletion:^{ complete = YES; }];
		dispatch_async(dispatch_get_main_queue(), ^{ heartbeat = YES; });
		Assert(WaitUntil(^BOOL { return heartbeat; }, .5) && !complete,
			"metric wipe drains the writer without blocking main-thread cancellation");
		Assert(!service.isPolling && service.latestSnapshot == nil, "metric wipe drops old visible values and stops polling");
		dispatch_semaphore_signal(service.writerGate);
		Assert(WaitUntil(^BOOL { return complete; }, 2), "metric wipe completion follows the last old cache write");
		Assert([NSFileManager.defaultManager fileExistsAtPath:file.path], "in-flight writer finished before destructive removal");
		Assert([NSFileManager.defaultManager removeItemAtURL:directory error:NULL], "removed metric cache after the barrier");
		NSUInteger readCount = source.safeReadCount, deliveries = subscriber.snapshots.count;
		[service setApplicationActive:NO]; [service setApplicationActive:YES]; [service refreshNow];
		FakeMetricSource *lateSource = [FakeMetricSource new];
		BAAnalyticsMetricService *late = [[BAAnalyticsMetricService alloc] initWithSource:lateSource];
		[late enableStartupCacheAtURL:file]; [late addSubscriber:subscriber]; [late refreshNow];
		DrainMetricWorker(service); DrainMetricWorker(late);
		Assert(!service.isPolling && !late.isPolling && source.safeReadCount == readCount && lateSource.safeReadCount == 0 && subscriber.snapshots.count == deliveries,
			"activation and late metric services cannot resume sampling or cached publication after a wipe");
		Assert(![NSFileManager.defaultManager fileExistsAtPath:directory.path], "old metric writers cannot recreate deleted storage after barrier completion");
	} @finally {
		dispatch_semaphore_signal(service.writerGate); [service removeSubscriber:subscriber];
		[NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
	}
}

int main(void) {
	@autoreleasepool {
		TestSnapshotImmutability();
		TestSystemTemperatureMetricMapping();
		TestLayoutMigrationAndBounds();
		TestVisibleOnlyMetricService();
		TestMetricStartupCacheLifecycle();
		TestMetricStartupCacheValidation();
		TestMetricDataWipeBarrier();
		printf("Analytics snapshot, layout, visible-only metric service, and startup cache lifecycle tests passed.\n");
	}
	return 0;
}
