#import <Foundation/Foundation.h>

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
	Assert([records[0].cardIdentifier isEqualToString:@"com.torrekie.battman.analytics.battery.summary"], "legacy built-in identifier migrated");
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

int main(void) {
	@autoreleasepool {
		TestSnapshotImmutability();
		TestSystemTemperatureMetricMapping();
		TestLayoutMigrationAndBounds();
		TestVisibleOnlyMetricService();
		printf("Analytics snapshot, layout, and visible-only metric service tests passed.\n");
	}
	return 0;
}
