#import <Foundation/Foundation.h>

#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryReader.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryService.h"

#include <math.h>
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>

// These databases contain only synthetic structural fixtures, never exported Powerlog data.
static double const FixtureEpoch = 1791690000.0;
static NSString *const BatteryTable = @"PLBatteryAgent_EventBackward_Battery";
static NSString *const BatteryUITable = @"PLBatteryAgent_EventBackward_BatteryUI";
static NSMutableArray<NSURL *> *FixtureDirectories;

static void Assert(BOOL condition, const char *message) {
	if (!condition) [NSException raise:@"HistoryTestFailure" format:@"%s", message];
}

static void AssertNear(double value, double expected, const char *message) {
	Assert(isfinite(value) && fabs(value - expected) < 0.001, message);
}

static void Execute(sqlite3 *database, NSString *sql) {
	char *error = NULL;
	int result = sqlite3_exec(database, sql.UTF8String, NULL, NULL, &error);
	NSString *description = error ? [NSString stringWithUTF8String:error] : @"unknown SQLite error";
	sqlite3_free(error);
	if (result != SQLITE_OK) [NSException raise:@"HistoryFixtureFailure" format:@"%@ (%@)", description, sql];
}

static NSString *NumberSQL(id value) {
	return [value isKindOfClass:NSNumber.class] ? [value stringValue] : @"NULL";
}

static NSString *BatteryRow(NSInteger identifier, double seconds, id level, id current, id connected, id charging, id full) {
	return [NSString stringWithFormat:
		@"INSERT INTO PLBatteryAgent_EventBackward_Battery "
		"(ID,timestamp,Level,InstantAmperage,ExternalConnected,IsCharging,FullyCharged) "
		"VALUES (%ld,%.3f,%@,%@,%@,%@,%@)", (long)identifier, FixtureEpoch + seconds,
		NumberSQL(level), NumberSQL(current), NumberSQL(connected), NumberSQL(charging), NumberSQL(full)];
}

static NSString *OffsetRow(NSInteger identifier, double seconds, double system) {
	return [NSString stringWithFormat:@"INSERT INTO PLStorageOperator_EventForward_TimeOffset VALUES (%ld,%.3f,%.3f)",
		(long)identifier, FixtureEpoch + seconds, system];
}

static NSURL *Fixture(BOOL macProfile, NSArray<NSString *> *statements) {
	NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
		URLByAppendingPathComponent:[@"battman-history-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString]
		isDirectory:YES];
	[FixtureDirectories addObject:directory];
	Assert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL],
		"created the fixture directory");
	NSURL *url = [directory URLByAppendingPathComponent:@"synthetic.sqlite"];
	sqlite3 *database = NULL;
	Assert(sqlite3_open(url.path.fileSystemRepresentation, &database) == SQLITE_OK, "created synthetic database");
	@try {
		Execute(database, @"CREATE TABLE PLStorageOperator_EventForward_TimeOffset (ID INTEGER PRIMARY KEY,timestamp REAL,system REAL)");
		NSString *schema = @"CREATE TABLE PLBatteryAgent_EventBackward_Battery ("
			"ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,InstantAmperage INTEGER,"
			"ExternalConnected INTEGER,IsCharging INTEGER,FullyCharged INTEGER,"
			"Voltage INTEGER DEFAULT 12000,AppleRawCurrentCapacity INTEGER DEFAULT 1500,"
			"AppleRawMaxCapacity INTEGER DEFAULT 6000,CurrentCapacity INTEGER DEFAULT 25,"
			"MaxCapacity INTEGER DEFAULT 100,DesignCapacity INTEGER DEFAULT 6200,"
			"CycleCount INTEGER DEFAULT 12,Temperature REAL DEFAULT 2890,"
			"AdapterPower REAL DEFAULT 1103626240,NotChargingReason INTEGER DEFAULT 99";
		Execute(database, [schema stringByAppendingString:macProfile ? @",CellVoltage0 INTEGER DEFAULT 4000)" : @")"]);
		if (!macProfile) {
			Execute(database, @"CREATE TABLE PLBatteryAgent_EventPoint_ChargingInfo ("
				"ID INTEGER PRIMARY KEY,timestamp REAL,Charging INTEGER,Connected INTEGER,"
				"RectifierCurrent INTEGER,RectifierVoltage INTEGER,PowerBudget INTEGER,PowerTarget INTEGER)");
		}
		for (NSString *statement in statements) Execute(database, statement);
	} @finally {
		sqlite3_close(database);
	}
	return url;
}

static BAAnalyticsReport *Read(NSURL *url, double seconds, uint64_t sequence) {
	BAAnalyticsReport *report = BAAnalyticsReadHistoryReport(url, [NSDate dateWithTimeIntervalSince1970:FixtureEpoch + seconds], sequence, ^BOOL { return NO; });
	Assert(report.error == nil, "synthetic database read succeeded");
	Assert(report.sequenceNumber == sequence, "report retained its requested sequence");
	return report;
}

static BOOL ObservationIsFromTable(BAAnalyticsObservation *observation, NSString *table) {
	for (BAAnalyticsFieldMetadata *field in observation.fieldMetadata.allValues)
		if ([field.sourceTable isEqual:table]) return YES;
	return NO;
}

static BAAnalyticsObservation *Observation(BAAnalyticsReport *report, NSString *table, double seconds) {
	for (BAAnalyticsObservation *observation in [report reportForFamily:BAAnalyticsFamilyDwell].window.observations)
		if (ObservationIsFromTable(observation, table) && fabs(observation.sourceTimestamp - FixtureEpoch - seconds) < 0.001) return observation;
	return nil;
}

static void AssertNonoverlappingIntervals(BAAnalyticsHistoryWindow *window) {
	NSDate *previousEnd = nil;
	NSArray *ordered = [window.intervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) {
		return [a.startDate compare:b.startDate];
	}];
	for (BAAnalyticsHistoryInterval *interval in ordered) {
		Assert(interval.duration > 0, "trusted interval has positive duration");
		Assert(!previousEnd || [interval.startDate compare:previousEnd] != NSOrderedAscending,
			"canonical family intervals never overlap");
		Assert([interval.startDate compare:window.startDate] != NSOrderedAscending && [interval.endDate compare:window.endDate] != NSOrderedDescending,
			"trusted intervals are clipped to the requested family window");
		previousEnd = interval.endDate;
	}
}

static void TestImmutableEvidence(void) {
	NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:FixtureEpoch];
	BAAnalyticsFieldMetadata *field = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:BatteryTable sourceColumn:@"Level"
		unit:@"%" decoderIdentifier:@"fixture.percent" unitValidated:YES];
	NSMutableDictionary *values = [@{BAAnalyticsHistorySOCPercent: @42} mutableCopy];
	NSMutableDictionary *metadata = [@{BAAnalyticsHistorySOCPercent: field} mutableCopy];
	BAAnalyticsObservation *observation = [[BAAnalyticsObservation alloc] initWithIdentifier:@"fixture.record" timestamp:timestamp
		sourceTimestamp:FixtureEpoch timestampValidated:YES values:values fieldMetadata:metadata];
	NSMutableArray *observations = [NSMutableArray arrayWithObject:observation];
	BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:timestamp endDate:timestamp
		observations:observations intervals:@[] gaps:@[] coverageMetricIdentifiers:[NSSet setWithObject:BAAnalyticsHistorySOCPercent]
		coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
	NSMutableArray *selectedRecords = [NSMutableArray arrayWithObject:observation];
	NSMutableDictionary *payload = [@{@"selectionEvidence": selectedRecords} mutableCopy];
	BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyDwell
		availability:BAAnalyticsReportAvailabilityPartial window:window payload:payload limitations:@[]];
	NSMutableDictionary *families = [@{BAAnalyticsFamilyDwell: family} mutableCopy];
	BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:1 generatedAt:timestamp sourceProfileIdentifier:@"fixture"
		fieldMetadata:metadata familyReports:families error:nil];
	values[BAAnalyticsHistorySOCPercent] = @99;
	[metadata removeAllObjects];
	[observations removeAllObjects];
	[selectedRecords removeAllObjects];
	[payload removeAllObjects];
	[families removeAllObjects];
	AssertNear([observation.values[BAAnalyticsHistorySOCPercent] doubleValue], 42, "observation detached mutable input values");
	Assert(observation.fieldMetadata.count == 1 && window.observations.count == 1, "immutable evidence detached its input containers");
	Assert([family.payload[@"selectionEvidence"] count] == 1, "family report froze nested selection evidence");
	Assert([report reportForFamily:BAAnalyticsFamilyDwell] == family && report.fieldMetadata.count == 1, "report detached mutable source maps");
	Assert([observation copy] == observation && [family copy] == family && [report copy] == report, "immutable models were safe to retain across refreshes");
	NSDate *end = [timestamp dateByAddingTimeInterval:60];
	BAAnalyticsObservation *last = [[BAAnalyticsObservation alloc] initWithIdentifier:@"fixture.last" timestamp:end
		sourceTimestamp:FixtureEpoch + 60 timestampValidated:YES values:observation.values fieldMetadata:observation.fieldMetadata];
	BAAnalyticsHistoryInterval *interval = [[BAAnalyticsHistoryInterval alloc] initWithStartDate:timestamp endDate:end
		startObservation:observation endObservation:last coveredMetricIdentifiers:[NSSet setWithObject:BAAnalyticsHistorySOCPercent]
		state:BAAnalyticsObservedStateUnknown];
	BAAnalyticsHistoryWindow *full = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:timestamp endDate:end
		observations:@[observation, last] intervals:@[interval] gaps:@[] coverageMetricIdentifiers:interval.coveredMetricIdentifiers
		coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
	Assert(full.intervals.firstObject == interval, "unclipped windows reuse their immutable interval evidence");
	BAAnalyticsHistoryWindow *clipped = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:[timestamp dateByAddingTimeInterval:15] endDate:end
		observations:@[observation, last] intervals:@[interval] gaps:@[] coverageMetricIdentifiers:interval.coveredMetricIdentifiers
		coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
	Assert(clipped.intervals.firstObject != interval && clipped.intervals.firstObject.startObservation == observation,
		"boundary clips create a distinct interval while retaining original sample endpoints");
	AssertNear(clipped.intervals.firstObject.duration, 45, "interval reuse retains exact clipping semantics");
	BAAnalyticsHistoryInterval *(^pair)(NSTimeInterval, NSTimeInterval) = ^(NSTimeInterval a, NSTimeInterval b) {
		return [[BAAnalyticsHistoryInterval alloc] initWithStartDate:[timestamp dateByAddingTimeInterval:a]
			endDate:[timestamp dateByAddingTimeInterval:b] startObservation:observation endObservation:last
			coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:BAAnalyticsObservedStateUnknown];
	};
	BAAnalyticsHistoryInterval *nested = pair(10, 20);
	BAAnalyticsHistoryWindow *unionWindow = [[BAAnalyticsHistoryWindow alloc]
		initWithStartDate:[timestamp dateByAddingTimeInterval:15] endDate:[timestamp dateByAddingTimeInterval:50]
		observations:@[observation, last] intervals:@[pair(40, 55), nested, pair(15, 30), nested] gaps:@[]
		coverageMetricIdentifiers:interval.coveredMetricIdentifiers coveredDuration:999 missingDuration:999
		coverageSecondsByMetric:@{BAAnalyticsHistorySOCPercent: @999}];
	AssertNear(unionWindow.coveredDuration, 25, "coverage merges shuffled, clipped and duplicate intervals without counting overlaps twice");
	AssertNear(unionWindow.missingDuration, 10, "coverage retains the real gap between disjoint interval groups");
	AssertNear([unionWindow.coverageSecondsByMetric[BAAnalyticsHistorySOCPercent] doubleValue], 25,
		"per-metric coverage remains authoritative rather than trusting cached summary values");
}

static void TestFieldsAndIndependentCoverage(void) {
	NSURL *url = Fixture(YES, @[
		OffsetRow(1, -3600, 30),
		BatteryRow(1, 0, @0, @0, @0, @0, @0),
		BatteryRow(2, 60, @10, NSNull.null, @0, @0, @0),
		BatteryRow(3, 120, NSNull.null, @-250, @0, @0, @0),
		BatteryRow(4, 180, @20, @-250, @0, @0, @0),
		@"UPDATE PLBatteryAgent_EventBackward_Battery SET AppleRawCurrentCapacity=NULL,AppleRawMaxCapacity=NULL WHERE ID=2",
	]);
	NSData *original = [NSData dataWithContentsOfURL:url];
	BAAnalyticsReport *report = Read(url, 1000, 1);
	Assert([original isEqual:[NSData dataWithContentsOfURL:url]], "history acquisition left database bytes unchanged");
	BAAnalyticsObservation *zero = Observation(report, BatteryTable, 0);
	BAAnalyticsObservation *missingCurrent = Observation(report, BatteryTable, 60);
	BAAnalyticsObservation *missingSOC = Observation(report, BatteryTable, 120);
	Assert(zero != nil && missingCurrent != nil && missingSOC != nil, "normalized Battery records are available");
	AssertNear(zero.timestamp.timeIntervalSince1970, FixtureEpoch + 30, "timestamp used its preceding TimeOffset.system");
	Assert(zero.timestampValidated, "normalized timestamp is explicitly validated");
	Assert(zero.values[BAAnalyticsHistorySOCPercent] != nil && zero.values[BAAnalyticsHistoryCurrentMilliamps] != nil,
		"valid SOC and signed current zero stayed available");
	AssertNear([zero.values[BAAnalyticsHistoryBatteryPowerWatts] doubleValue], 0, "zero signed current yielded valid zero battery power");
	Assert(missingCurrent.values[BAAnalyticsHistoryCurrentMilliamps] == nil && missingCurrent.values[BAAnalyticsHistoryBatteryPowerWatts] == nil,
		"NULL current did not become zero or derived battery power");
	Assert(missingSOC.values[BAAnalyticsHistorySOCPercent] == nil, "NULL SOC did not become zero");
	AssertNear([missingSOC.values[BAAnalyticsHistoryCurrentMilliamps] doubleValue], -250, "measured signed discharge current retained its sign");
	AssertNear([missingSOC.values[BAAnalyticsHistoryBatteryPowerWatts] doubleValue], -3, "same-record mA and mV produced signed watts");
	AssertNear([zero.values[BAAnalyticsHistoryRemainingCapacityMilliampHours] doubleValue], 1500, "raw remaining capacity was decoded as mAh");
	AssertNear([zero.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] doubleValue], 6000, "raw full-charge capacity was decoded as mAh");
	Assert(missingCurrent.values[BAAnalyticsHistoryRemainingCapacityMilliampHours] == nil && missingCurrent.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] == nil,
		"percent CurrentCapacity and MaxCapacity did not substitute for missing raw mAh");
	Assert(report.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius] != nil && !report.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius].unitValidated,
		"candidate temperature provenance remained unverified");
	BOOL foundAdapterCandidate = NO;
	for (BAAnalyticsFieldMetadata *field in report.fieldMetadata.allValues)
		if ([field.sourceColumn isEqual:@"AdapterPower"]) { foundAdapterCandidate = YES; Assert(!field.unitValidated, "adapter power encoding stayed unverified"); }
	Assert(foundAdapterCandidate, "candidate adapter power metadata was retained");
	for (BAAnalyticsObservation *observation in [report reportForFamily:BAAnalyticsFamilyDwell].window.observations) {
		Assert(observation.values[BAAnalyticsHistoryTemperatureCelsius] == nil, "unknown temperature units did not publish a reading");
		for (NSString *metric in observation.values)
			Assert(observation.fieldMetadata[metric].unitValidated, "only unit-validated fields emitted values");
	}
	BAAnalyticsHistoryWindow *window = [report reportForFamily:BAAnalyticsFamilyDwell].window;
	AssertNear([window.coverageSecondsByMetric[BAAnalyticsHistorySOCPercent] doubleValue], 60, "SOC coverage used only pairs with both endpoints present");
	AssertNear([window.coverageSecondsByMetric[BAAnalyticsHistoryCurrentMilliamps] doubleValue], 60, "current coverage was independent of SOC coverage");
	AssertNear([window.coverageSecondsByMetric[BAAnalyticsHistoryVoltageMillivolts] doubleValue], 180, "voltage retained its independent coverage");
	AssertNear([window.coverageSecondsByMetric[BAAnalyticsHistoryTemperatureCelsius] doubleValue], 0, "unvalidated units established no coverage");
	AssertNear(window.coveredDuration + window.missingDuration, [window.endDate timeIntervalSinceDate:window.startDate], "coverage plus missing spans equals requested duration");
	AssertNonoverlappingIntervals(window);
}

static void TestClockSegmentsStatesAndStableIdentifiers(void) {
	NSURL *url = Fixture(YES, @[
		OffsetRow(1, -3600, 30), OffsetRow(2, 480, 50),
		BatteryRow(1, 0, @18, @-500, @0, @0, @0), BatteryRow(2, 60, @17, @-500, @0, @0, @0),
		BatteryRow(3, 120, @18, @500, @1, @1, @0), BatteryRow(4, 180, @19, @500, @1, @1, @0),
		BatteryRow(5, 240, @19, @0, @1, @0, @0), BatteryRow(6, 300, @19, @0, @1, @0, @0),
		BatteryRow(7, 360, @100, @0, @1, @0, @1), BatteryRow(8, 420, @100, @0, @1, @0, @1),
		BatteryRow(9, 480, @100, @0, @1, @0, @1), BatteryRow(10, 540, @100, @0, @1, @0, @1),
		BatteryRow(11, 1140, @99, @-500, @0, @0, @0), BatteryRow(12, 1200, @98, @-500, @0, @0, @0),
	]);
	BAAnalyticsReport *report = Read(url, 2000, 10);
	BAAnalyticsReport *refreshed = Read(url, 2100, 11);
	AssertNear(Observation(report, BatteryTable, 480).timestamp.timeIntervalSince1970, FixtureEpoch + 530,
		"new offset applied only after its segment boundary");
	NSArray<BAAnalyticsStateTransition *> *transitions = [report reportForFamily:BAAnalyticsFamilyEvents].payload[BAAnalyticsPayloadTransitions];
	Assert(transitions.count == 3, "charging, pause and full produced three bounded transitions; long gap produced none");
	Assert(transitions[0].previousState == BAAnalyticsObservedStateUnplugged && transitions[0].nextState == BAAnalyticsObservedStateCharging,
		"observed cable connection led to charging state");
	Assert(transitions[1].previousState == BAAnalyticsObservedStateCharging && transitions[1].nextState == BAAnalyticsObservedStateConnectedNotCharging,
		"connected but not charging was retained as a distinct state");
	Assert(transitions[2].nextState == BAAnalyticsObservedStateFull, "fully charged was distinct from a pause");
	AssertNear([transitions[0].latestDate timeIntervalSinceDate:transitions[0].earliestDate], 60, "transition retained sampled earliest/latest bounds");
	AssertNear(transitions[1].reasonCode.doubleValue, 99, "uninterpreted reason retained its raw numeric code");
	NSArray<BAAnalyticsHistorySession *> *connected = [report reportForFamily:BAAnalyticsFamilySession].payload[BAAnalyticsPayloadSessions];
	NSArray<BAAnalyticsHistorySession *> *unplugged = [report reportForFamily:BAAnalyticsFamilyDischarge].payload[BAAnalyticsPayloadSessions];
	Assert(connected.count == 2 && unplugged.count == 2, "clock and source gaps split connected and unplugged sessions");
	Assert(connected[0].startBoundaryKnown && !connected[0].endBoundaryKnown && !connected[1].startBoundaryKnown && !connected[1].endBoundaryKnown,
		"clock/source gaps left session boundaries unknown");
	Assert(!unplugged[0].startBoundaryKnown && unplugged[0].endBoundaryKnown && !unplugged[1].startBoundaryKnown && !unplugged[1].endBoundaryKnown,
		"window edges and the long gap did not invent unplugging boundaries");
	for (BAAnalyticsHistoryInterval *interval in [report reportForFamily:BAAnalyticsFamilyDwell].window.intervals) {
		Assert(!(interval.startObservation.sourceTimestamp < FixtureEpoch + 480 && interval.endObservation.sourceTimestamp >= FixtureEpoch + 480),
			"no trusted interval crossed the TimeOffset discontinuity");
		Assert(interval.duration <= 180, "long source gap did not become continuous coverage");
	}
	Assert([report reportForFamily:BAAnalyticsFamilyDwell].window.gaps.count > 0, "discontinuities and missing spans were explicit gaps");
	for (BAAnalyticsObservation *observation in [report reportForFamily:BAAnalyticsFamilyDwell].window.observations) {
		BAAnalyticsObservation *same = Observation(refreshed, BatteryTable, observation.sourceTimestamp - FixtureEpoch);
		Assert([observation.identifier isEqual:same.identifier], "record identifier survived refresh and a shifted requested window");
	}
	NSArray<BAAnalyticsHistorySession *> *refreshedConnected = [refreshed reportForFamily:BAAnalyticsFamilySession].payload[BAAnalyticsPayloadSessions];
	Assert(connected.count == refreshedConnected.count, "same complete source segments survived refresh");
	for (NSUInteger i = 0; i < connected.count; i++) Assert([connected[i].identifier isEqual:refreshedConnected[i].identifier], "session identifier survived refresh");
	NSArray<BAAnalyticsStateTransition *> *refreshedTransitions = [refreshed reportForFamily:BAAnalyticsFamilyEvents].payload[BAAnalyticsPayloadTransitions];
	for (NSUInteger i = 0; i < transitions.count; i++) Assert([transitions[i].identifier isEqual:refreshedTransitions[i].identifier], "transition identifier survived refresh");
}

static void TestIndependentTablesAndWindowClipping(void) {
	NSURL *url = Fixture(YES, @[
		OffsetRow(1, -3600, 30), BatteryRow(1, 0, @30, @-100, @0, @0, @0), BatteryRow(2, 120, @29, @-100, @0, @0, @0),
		@"CREATE TABLE PLBatteryAgent_EventBackward_BatteryUI (ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,IsCharging INTEGER)",
		[NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventBackward_BatteryUI VALUES (1,%.3f,80,0),(2,%.3f,79,0)", FixtureEpoch, FixtureEpoch + 300],
	]);
	BAAnalyticsReport *report = Read(url, 330, 20);
	BAAnalyticsObservation *battery = Observation(report, BatteryTable, 0);
	BAAnalyticsObservation *ui = Observation(report, BatteryUITable, 0);
	Assert(battery != nil && ui != nil && ![battery.identifier isEqual:ui.identifier], "identical table-local IDs and timestamps stayed separate source records");
	AssertNear([battery.values[BAAnalyticsHistorySOCPercent] doubleValue], 30, "Battery retained its own SOC");
	AssertNear([ui.values[BAAnalyticsHistorySOCPercent] doubleValue], 80, "BatteryUI retained its independent SOC");
	Assert(ui.values[BAAnalyticsHistoryExternalConnected] == nil && ui.values[BAAnalyticsHistoryCurrentMilliamps] == nil,
		"BatteryUI did not acquire Battery fields by row index or timestamp");
	BAAnalyticsHistoryWindow *dwell = [report reportForFamily:BAAnalyticsFamilyDwell].window;
	AssertNear([dwell.coverageSecondsByMetric[BAAnalyticsHistorySOCPercent] doubleValue], 300, "overlapping source SOC coverage used a union");
	AssertNear([dwell.coverageSecondsByMetric[BAAnalyticsHistoryExternalConnected] doubleValue], 120, "BatteryUI did not extend connected-state coverage");
	AssertNonoverlappingIntervals(dwell);
	BAAnalyticsHistoryWindow *live = [Read(url, 430, 21) reportForFamily:BAAnalyticsFamilyLive].window;
	AssertNonoverlappingIntervals(live);
	for (BAAnalyticsHistoryInterval *interval in live.intervals)
		Assert(interval.startObservation.timestamp.timeIntervalSince1970 <= interval.startDate.timeIntervalSince1970 &&
			interval.endObservation.timestamp.timeIntervalSince1970 >= interval.endDate.timeIntervalSince1970,
			"clipped trusted intervals preserved the real source endpoint samples");
}

static void TestConfigurationEpochBoundaries(void) {
	NSMutableArray *statements = [NSMutableArray arrayWithObjects:
		OffsetRow(1, -3600, 30),
		// Powerlog IDs are not required to be unique by the reader. Reusing one
		// proves that a new epoch cannot be represented by just its last ID.
		// Two changes at the same source timestamp belong to the final epoch at
		// that instant, regardless of their equal-ID SQLite tie order.
		@"CREATE TABLE PLBatteryAgent_EventNone_BatteryConfig (ID INTEGER,timestamp REAL,AlgoChemID INTEGER,calibrationFlags INTEGER,CycleCount INTEGER)",
		[NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventNone_BatteryConfig VALUES "
			"(7,%.3f,10,0,12),(7,%.3f,20,0,12),(7,%.3f,30,0,12),(7,%.3f,10,0,12),"
			"(7,%.3f,10,1,12),(7,%.3f,10,1,11),(7,%.3f,10,1,12)",
			FixtureEpoch - 120, FixtureEpoch + 120, FixtureEpoch + 120, FixtureEpoch + 240,
			FixtureEpoch + 360, FixtureEpoch + 480, FixtureEpoch + 540], nil];
	for (NSInteger i = 0; i <= 10; i++)
		[statements addObject:BatteryRow(i + 1, i * 60, @(30 + i), @100, @1, @1, @0)];
	NSURL *url = Fixture(YES, statements);
	BAAnalyticsReport *report = Read(url, 1000, 34);
	BAAnalyticsHistoryWindow *window = [report reportForFamily:BAAnalyticsFamilyDwell].window;
	NSArray<NSNumber *> *expectedStarts = @[@0, @120, @240, @360, @480, @540];
	NSArray<NSNumber *> *expectedEnds = @[@60, @180, @300, @420, @540, @600];
	Assert(window.intervals.count == expectedStarts.count, "multiple configuration epochs retained only within-epoch intervals");
	for (NSUInteger i = 0; i < window.intervals.count; i++) {
		BAAnalyticsHistoryInterval *interval = window.intervals[i];
		AssertNear(interval.startObservation.sourceTimestamp, FixtureEpoch + expectedStarts[i].doubleValue,
			"pair before a configuration boundary did not interpolate into the boundary");
		AssertNear(interval.endObservation.sourceTimestamp, FixtureEpoch + expectedEnds[i].doubleValue,
			"sample exactly at a configuration boundary belongs to its following epoch");
		AssertNear(interval.startDate.timeIntervalSince1970, interval.startObservation.sourceTimestamp + 30,
			"configuration epoch lookup preserved wall-clock timestamp normalization");
	}
	AssertNear(window.coveredDuration, 360, "chemical reversion, calibration change and cycle reset all broke coverage");
	NSArray *sessions = [report reportForFamily:BAAnalyticsFamilySession].payload[BAAnalyticsPayloadSessions];
	Assert(sessions.count == 5, "reused configuration IDs and reverted values still split five source sessions");
	for (BAAnalyticsHistorySession *session in sessions)
		Assert(!session.startBoundaryKnown && !session.endBoundaryKnown, "configuration discontinuity did not invent a cable event");
	BAAnalyticsReport *refreshed = Read(url, 1100, 35);
	sqlite3 *database = NULL;
	Assert(sqlite3_open(url.path.fileSystemRepresentation, &database) == SQLITE_OK, "opened synthetic config fixture for mutation");
	@try { Execute(database, @"DELETE FROM PLBatteryAgent_EventNone_BatteryConfig"); }
	@finally { sqlite3_close(database); }
	BAAnalyticsReport *withoutConfiguration = Read(url, 1100, 36);
	Assert([withoutConfiguration reportForFamily:BAAnalyticsFamilyDwell].window.intervals.count == 10,
		"same Battery samples formed continuous coverage without configuration boundaries");
	for (NSInteger i = 0; i <= 10; i++) {
		BAAnalyticsObservation *original = Observation(report, BatteryTable, i * 60);
		BAAnalyticsObservation *same = Observation(refreshed, BatteryTable, i * 60);
		BAAnalyticsObservation *noConfig = Observation(withoutConfiguration, BatteryTable, i * 60);
		Assert(original != nil && [original.identifier isEqual:same.identifier] && [original.identifier isEqual:noConfig.identifier],
			"configuration tokens did not change stable Battery record identifiers");
		Assert([original.timestamp isEqual:same.timestamp] && [original.timestamp isEqual:noConfig.timestamp],
			"configuration tokens did not change normalized Battery timestamps");
	}
}

static void TestPlatformCadenceUnvalidatedTimeAndSparseCapacity(void) {
	NSArray *pair = @[OffsetRow(1, -3600, -375), BatteryRow(1, 0, @40, @-100, @0, @0, @0), BatteryRow(2, 120, @39, @-100, @0, @0, @0)];
	BAAnalyticsReport *mac = Read(Fixture(YES, pair), 1000, 30);
	BAAnalyticsReport *ios = Read(Fixture(NO, pair), 1000, 31);
	Assert(![mac.sourceProfileIdentifier isEqual:ios.sourceProfileIdentifier], "platform was detected from database schema instead of the test host");
	AssertNear([mac reportForFamily:BAAnalyticsFamilyDwell].window.coveredDuration, 120, "120-second Battery pair was trusted for the known Mac cadence");
	AssertNear([ios reportForFamily:BAAnalyticsFamilyDwell].window.coveredDuration, 0, "120-second Battery pair exceeded known iOS cadence");
	AssertNear(Observation(ios, BatteryTable, 0).timestamp.timeIntervalSince1970, FixtureEpoch - 375, "negative platform offset was added rather than treated as a timezone");
	NSURL *noOffsetURL = Fixture(YES, @[BatteryRow(1, 0, @40, @0, @1, @0, @0), BatteryRow(2, 60, @40, @0, @1, @0, @0)]);
	BAAnalyticsReport *noOffset = Read(noOffsetURL, 1000, 32);
	AssertNear([noOffset reportForFamily:BAAnalyticsFamilyDwell].window.coveredDuration, 0, "missing preceding offset established no duration");
	for (BAAnalyticsObservation *observation in [noOffset reportForFamily:BAAnalyticsFamilyDwell].window.observations)
		Assert(!observation.timestampValidated && observation.values.count == 0, "unvalidated timestamp did not publish normalized readings");
	NSURL *sparseURL = Fixture(YES, @[
		OffsetRow(1, -3600, 30),
		@"CREATE TABLE PLBatteryAgent_EventNone_BatteryConfig (ID INTEGER PRIMARY KEY,timestamp REAL,AppleRawMaxCapacity INTEGER,CycleCount INTEGER)",
		[NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventNone_BatteryConfig VALUES (1,%.3f,6000,12),(2,%.3f,5990,13)", FixtureEpoch, FixtureEpoch + 3600],
	]);
	BAAnalyticsFamilyReport *capacity = [Read(sparseURL, 4000, 33) reportForFamily:BAAnalyticsFamilyCapacity];
	Assert(capacity.payload[BAAnalyticsPayloadLatestObservation] != nil && capacity.window.observations.count == 2, "sparse capacity points remained available");
	Assert(capacity.window.intervals.count == 0, "sparse configuration points did not create trusted continuous intervals");
	AssertNear(capacity.window.coveredDuration, 0, "sparse readings did not claim continuous 30-day coverage");
}

static void TestWirelessCandidateUnits(void) {
	NSURL *url = Fixture(NO, @[
		OffsetRow(1, -3600, -375), BatteryRow(1, 0, @40, @100, @1, @1, @0),
		[NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventPoint_ChargingInfo VALUES (1,%.3f,1,1,701,702,703,704)", FixtureEpoch + 30],
	]);
	BAAnalyticsReport *report = Read(url, 1000, 40);
	Assert(report.fieldMetadata[BAAnalyticsHistoryInputCurrentMilliamps] != nil && report.fieldMetadata[BAAnalyticsHistoryInputVoltageMillivolts] != nil &&
		!report.fieldMetadata[BAAnalyticsHistoryInputCurrentMilliamps].unitValidated && !report.fieldMetadata[BAAnalyticsHistoryInputVoltageMillivolts].unitValidated,
		"wireless rectifier candidate units remained unverified");
	for (BAAnalyticsObservation *observation in [report reportForFamily:BAAnalyticsFamilyPath].window.observations)
		Assert(observation.values[BAAnalyticsHistoryInputCurrentMilliamps] == nil && observation.values[BAAnalyticsHistoryInputVoltageMillivolts] == nil &&
			observation.values[BAAnalyticsHistoryInputPowerWatts] == nil && observation.values[BAAnalyticsHistoryPowerBudgetWatts] == nil && observation.values[BAAnalyticsHistoryPowerTargetWatts] == nil,
			"unknown input and budget encodings did not publish false units");
}



static BAAnalyticsReport *ReadSources(NSArray<NSURL *> *sources, double seconds, uint64_t sequence) {
    BAAnalyticsReport *report = BAAnalyticsReadHistoryReportFromSources(sources,
        [NSDate dateWithTimeIntervalSince1970:FixtureEpoch + seconds], sequence, ^BOOL { return NO; });
    Assert(report.error == nil && report.sequenceNumber == sequence, "compatible selected sources produce a successful immutable report");
    return report;
}

static void TestRotatedHistorySources(void) {
    NSURL *current = Fixture(YES, @[
        OffsetRow(1, -3600, 30), BatteryRow(1, 120, @20, @400, @1, @1, @0),
        BatteryRow(2, 180, @21, @400, @1, @1, @0), BatteryRow(3, 240, @22, @400, @1, @1, @0),
    ]);
    NSURL *archive = Fixture(YES, @[
        OffsetRow(1, -3600, 30), BatteryRow(1, 0, @0, @400, @1, @1, @0),
        BatteryRow(2, 60, @10, @400, @1, @1, @0), BatteryRow(3, 120, @80, @400, @1, @1, @0),
        BatteryRow(4, 180, @90, @400, @1, @1, @0),
    ]);
    NSData *currentBytes = [NSData dataWithContentsOfURL:current], *archiveBytes = [NSData dataWithContentsOfURL:archive];
    BAAnalyticsReport *report = ReadSources(@[current, archive], 1000, 50);
    BAAnalyticsHistoryWindow *window = report.familyReports[BAAnalyticsFamilyDwell].window;
    Assert(window.observations.count == 5, "rotation overlap keeps only newer-source observations at and after its earliest wall-clock time");
    AssertNear([Observation(report, BatteryTable, 120).values[BAAnalyticsHistorySOCPercent] doubleValue], 20,
        "newer database is authoritative for conflicting overlap values");
    AssertNear([Observation(report, BatteryTable, 0).values[BAAnalyticsHistorySOCPercent] doubleValue], 0,
        "older observed zero remains a valid reading");
    AssertNear(window.coverageSecondsByMetric[BAAnalyticsHistorySOCPercent].doubleValue, 180,
        "source boundary contributes no invented continuous coverage");
    Assert(window.intervals.count == 3, "matching source cadence does not bridge rotated files");
    BOOL boundaryGap = NO;
    for (BAAnalyticsHistoryGap *gap in window.gaps)
        if (fabs(gap.startDate.timeIntervalSince1970 - FixtureEpoch - 90) < .001 &&
            fabs(gap.endDate.timeIntervalSince1970 - FixtureEpoch - 150) < .001) boundaryGap = YES;
    Assert(boundaryGap, "source boundary is explicitly represented as a gap");
    NSArray<BAAnalyticsHistorySession *> *sessions = report.familyReports[BAAnalyticsFamilySession].payload[BAAnalyticsPayloadSessions];
    Assert(sessions.count == 2 && !sessions[0].endBoundaryKnown && !sessions[1].startBoundaryKnown,
        "rotation splits connected sessions and keeps boundary uncertainty");
    NSArray<BAAnalyticsHistorySession *> *comparison = report.familyReports[BAAnalyticsFamilyCompare].payload[BAAnalyticsPayloadSessions];
    Assert(comparison.count == 1 && [comparison[0].identifier isEqual:sessions[1].identifier],
        "comparison excludes old-file segments whose compatibility cannot be established");
    for (BAAnalyticsObservation *point in window.observations) {
        Assert(point.values[BAAnalyticsHistoryTemperatureCelsius] == nil && !point.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius].unitValidated,
            "archive composition cannot promote unverified units");
        AssertNear(point.timestamp.timeIntervalSince1970 - point.sourceTimestamp, 30, "each source uses its own preceding time offset");
    }
    Assert([currentBytes isEqual:[NSData dataWithContentsOfURL:current]] && [archiveBytes isEqual:[NSData dataWithContentsOfURL:archive]],
        "rotated history composition remains read-only");
    BAAnalyticsReport *duplicate = ReadSources(@[current, current, archive, archive], 1000, 51);
    Assert(duplicate.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 5,
        "same database identity is acquired once");

    NSURL *missing = [archive.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"missing.sqlite"];
    NSURL *corrupt = [archive.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"corrupt.sqlite"];
    Assert([[@"synthetic invalid SQLite bytes" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:corrupt atomically:YES],
        "created a synthetic corrupt archive");
    BAAnalyticsReport *partial = ReadSources(@[current, missing, corrupt, archive], 1000, 52);
    Assert(partial.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 5 &&
        partial.familyReports[BAAnalyticsFamilyDwell].availability == BAAnalyticsReportAvailabilityPartial,
        "missing or corrupt old source retains valid current and archive evidence as partial");
    BAAnalyticsReport *fallback = ReadSources(@[missing, archive], 1000, 53);
    Assert(fallback.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 4,
        "an available archive can retain historical evidence when the current file is unavailable");
    NSURL *incompatible = Fixture(NO, @[OffsetRow(1, -3600, 30), BatteryRow(1, 0, @99, @0, @0, @0, @0)]);
    BAAnalyticsReport *excluded = ReadSources(@[current, incompatible], 1000, 54);
    Assert(excluded.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 3 &&
        [excluded.sourceProfileIdentifier isEqual:@"powerlog.mac-battery.v1"], "incompatible schema archives cannot contaminate the current profile");
    __block NSUInteger cancellationChecks = 0;
    BAAnalyticsReport *cancelled = BAAnalyticsReadHistoryReportFromSources(@[current, archive],
        [NSDate dateWithTimeIntervalSince1970:FixtureEpoch + 1000], 55, ^BOOL { return ++cancellationChecks > 10; });
    Assert(cancelled.error.code == SQLITE_INTERRUPT && cancelled.familyReports.count == 0,
        "explicit multi-source cancellation discards the incomplete generation");

    NSURLComponents *tagged = [NSURLComponents componentsWithURL:archive resolvingAgainstBaseURL:NO];
    tagged.fragment = @"ba-powerlog-source:0123456789abcdef";
    BAAnalyticsReport *taggedA = ReadSources(@[current, tagged.URL], 1000, 56);
    NSURL *copyURL = [archive.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"extracted-copy.sqlite"];
    Assert([NSFileManager.defaultManager copyItemAtURL:archive toURL:copyURL error:NULL], "copied synthetic extracted archive");
    tagged = [NSURLComponents componentsWithURL:copyURL resolvingAgainstBaseURL:NO]; tagged.fragment = @"ba-powerlog-source:0123456789abcdef";
    BAAnalyticsReport *taggedB = ReadSources(@[current, tagged.URL], 1000, 57);
    Assert([Observation(taggedA, BatteryTable, 0).identifier isEqual:Observation(taggedB, BatteryTable, 0).identifier],
        "extracted archive identity follows original source token instead of temporary inode");
}

static void TestRotatedSourceBounds(void) {
    NSMutableArray<NSURL *> *sources = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10; i++) [sources addObject:Fixture(YES, @[
        OffsetRow(1, -3600, 0), BatteryRow(1, -(double)i * 60, @(i), @0, @0, @0, @0),
    ])];
    BAAnalyticsReport *bounded = ReadSources(sources, 1000, 60);
    Assert(bounded.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 9 &&
        Observation(bounded, BatteryTable, -540) == nil, "selected source count is capped at nine databases");

    NSMutableArray *configSources = [NSMutableArray array];
    for (NSUInteger source = 0; source < 3; source++) {
        NSInteger beginning = source == 0 ? 1024 : source == 1 ? 0 : -1024;
        NSString *rows = [NSString stringWithFormat:@"WITH RECURSIVE records(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM records WHERE i<1024) "
            "INSERT INTO PLBatteryAgent_EventNone_BatteryConfig SELECT i,%.3f+(i+%ld)*60,6000,12 FROM records", FixtureEpoch, (long)beginning];
        [configSources addObject:Fixture(YES, @[OffsetRow(1, -1000000, 0),
            @"CREATE TABLE PLBatteryAgent_EventNone_BatteryConfig (ID INTEGER PRIMARY KEY,timestamp REAL,AppleRawMaxCapacity INTEGER,CycleCount INTEGER)", rows])];
    }
    BAAnalyticsReport *config = ReadSources(configSources, 300000, 61);
    BAAnalyticsFamilyReport *capacity = config.familyReports[BAAnalyticsFamilyCapacity];
    Assert(capacity.window.observations.count == 2048, "combined configuration evidence obeys total record budget across archives");
    AssertNear(capacity.window.coveredDuration, 0, "bounded sparse configuration history does not fabricate continuous coverage");
}

static NSData *CacheFixtureData(NSDictionary *propertyList) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:propertyList format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    Assert(data != nil, "serialized cache fixture");
    return data;
}

static NSMutableDictionary *MutableCacheFixture(NSData *data) {
    return [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL];
}

static BAAnalyticsObservation *CachedObservation(BAAnalyticsReport *report, NSString *identifier) {
    for (BAAnalyticsFamilyReport *family in report.familyReports.allValues)
        for (BAAnalyticsObservation *point in family.window.observations)
            if ([point.identifier isEqual:identifier]) return point;
    return nil;
}

static void TestCachedReportGraph(void) {
    NSURL *url = Fixture(YES, @[
        OffsetRow(1, -3600, 30),
        BatteryRow(1, 0, @20, @-200, @0, @0, @0), BatteryRow(2, 60, @19, @-200, @0, @0, @0),
        BatteryRow(3, 120, @20, @400, @1, @1, @0), BatteryRow(4, 180, @21, @400, @1, @1, @0),
        BatteryRow(5, 1200, @30, @400, @1, @1, @0),
    ]);
    BAAnalyticsReport *report = Read(url, 1800, UINT64_MAX);
    NSError *error = nil;
    NSData *data = BAAnalyticsEncodeCachedReport(report, &error);
    Assert(data != nil && error == nil, "completed report encoded without acquisition failure");
    Assert(data.length >= 8 && !memcmp(data.bytes, "bplist00", 8), "small caches retain the legacy raw binary-plist representation");
    Assert(BAAnalyticsEncodeCachedReportCancellable(report, &error, ^BOOL { return YES; }) == nil,
        "cancelled cache write returns before serializing a generation");
    Assert([error.userInfo[@"stage"] isEqual:@1] && [error.userInfo[@"reason"] isEqual:@3] &&
        [error.userInfo[@"visits"] isEqual:@0] && [error.userInfo[@"counts"] count] == 8,
        "cancelled encoding returns bounded numeric diagnostics without record content");
    Assert(BAAnalyticsDecodeCachedReportCancellable(data, report.generatedAt, &error, ^BOOL { return YES; }) == nil,
        "cancelled bootstrap returns before decoding a graph");
    __block NSUInteger encodeChecks = 0;
    Assert(BAAnalyticsEncodeCachedReportCancellable(report, &error, ^BOOL { return ++encodeChecks > 2; }) == nil && encodeChecks > 2,
        "cooperative cancellation interrupts a cache graph encode");
    Assert([error.userInfo[@"reason"] isEqual:@3] && [error.userInfo[@"visits"] unsignedIntegerValue] > 0,
        "cooperative cache cancellation reports its reason and work count");
    __block NSUInteger decodeChecks = 0;
    Assert(BAAnalyticsDecodeCachedReportCancellable(data, report.generatedAt, &error, ^BOOL { return ++decodeChecks > 2; }) == nil && decodeChecks > 2,
        "cooperative cancellation interrupts cache graph reconstruction");
    BAAnalyticsReport *restored = BAAnalyticsDecodeCachedReport(data, [report.generatedAt dateByAddingTimeInterval:60], &error);
    Assert(restored != nil && error == nil && restored.isCached && !report.isCached, "restored report is marked cached without mutating fresh evidence");
    Assert([restored.generatedAt isEqual:report.generatedAt] && restored.sequenceNumber == UINT64_MAX &&
        [restored.sourceProfileIdentifier isEqual:report.sourceProfileIdentifier], "cache retained original time sequence and profile");
    Assert(restored.reportByMarkingCached == restored && report.reportByMarkingCached.isCached,
        "marking immutable evidence cached is idempotent");
    for (NSString *key in report.familyReports) {
        BAAnalyticsFamilyReport *original = report.familyReports[key], *copy = restored.familyReports[key];
        Assert(copy.availability == original.availability && [copy.limitations isEqual:original.limitations] &&
            [copy.window.startDate isEqual:original.window.startDate] && [copy.window.endDate isEqual:original.window.endDate],
            "family source limitations and original windows survived cache roundtrip");
        AssertNear(copy.window.coveredDuration, original.window.coveredDuration, "roundtrip retained independently computed coverage");
        AssertNear(copy.window.missingDuration, original.window.missingDuration, "roundtrip retained missing time");
        Assert([copy.window.coverageSecondsByMetric isEqual:original.window.coverageSecondsByMetric] &&
            copy.window.observations.count == original.window.observations.count && copy.window.gaps.count == original.window.gaps.count,
            "cache did not drop dense evidence or fabricate coverage");
        for (BAAnalyticsObservation *point in copy.window.observations) {
            Assert(CachedObservation(restored, point.identifier) == point, "shared record references remain one immutable object across families");
            Assert(point.values[BAAnalyticsHistoryTemperatureCelsius] == nil && !point.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius].unitValidated,
                "cache retained unverified provenance without introducing a reading");
        }
        for (BAAnalyticsHistoryInterval *interval in copy.window.intervals) {
            Assert(CachedObservation(restored, interval.startObservation.identifier) == interval.startObservation &&
                CachedObservation(restored, interval.endObservation.identifier) == interval.endObservation,
                "trusted interval endpoints share the restored observation graph");
        }
        BAAnalyticsHistorySession *selected = copy.payload[BAAnalyticsPayloadSelectedSession];
        if (selected) {
            Assert([copy.payload[BAAnalyticsPayloadSessions] containsObject:selected], "selected session shares its restored collection object");
            BAAnalyticsHistorySession *prior = original.payload[BAAnalyticsPayloadSelectedSession];
            Assert(selected.startBoundaryKnown == prior.startBoundaryKnown && selected.endBoundaryKnown == prior.endBoundaryKnown &&
                selected.transitions.count == prior.transitions.count && [selected.kind isEqual:prior.kind],
                "session sampled boundary certainty and transitions survived roundtrip");
        }
    }
    BAAnalyticsFamilyReport *events = restored.familyReports[BAAnalyticsFamilyEvents];
    Assert([events.payload[BAAnalyticsPayloadTransitions] count] == [report.familyReports[BAAnalyticsFamilyEvents].payload[BAAnalyticsPayloadTransitions] count],
        "cached event transitions retained exact sampled bounds");
    Assert(BAAnalyticsDecodeCachedReport(data, report.generatedAt, NULL) != nil, "zero-age cache is valid");
    Assert(BAAnalyticsDecodeCachedReport(data, [report.generatedAt dateByAddingTimeInterval:24 * 3600], NULL) != nil, "24-hour age boundary is valid");
    Assert(BAAnalyticsDecodeCachedReport(data, [report.generatedAt dateByAddingTimeInterval:24 * 3600 + .001], &error) == nil && error != nil,
        "over-age cache is rejected");
    Assert(BAAnalyticsDecodeCachedReport(data, [report.generatedAt dateByAddingTimeInterval:-.001], &error) == nil && error != nil,
        "future report cannot be labelled fresh by a clock rollback");
    Assert(BAAnalyticsDecodeCachedReport([data subdataWithRange:NSMakeRange(0, data.length / 2)], report.generatedAt, &error) == nil && error != nil,
        "truncated cache is rejected");
    Assert(BAAnalyticsDecodeCachedReport([NSMutableData dataWithLength:16 * 1024 * 1024 + 1], report.generatedAt, &error) == nil && error != nil,
        "oversized cache is rejected before parsing");

    NSMutableDictionary *fixture = MutableCacheFixture(data);
    fixture[@"version"] = @2;
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "unknown cache format is rejected");
    fixture = MutableCacheFixture(data);
    fixture[@"sequence"] = @1e100;
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "sequence overflow is rejected");
    fixture = MutableCacheFixture(data);
    NSArray *nodes = fixture[@"objects"];
    NSMutableDictionary *observationNode = nil, *familyNode = nil;
    for (NSMutableDictionary *node in nodes) {
        if ([node[@"kind"] isEqual:@"observation"]) observationNode = node;
        if ([node[@"kind"] isEqual:@"family"]) familyNode = node;
    }
    Assert(observationNode != nil && familyNode != nil, "fixture has explicit typed graph objects");
    observationNode[@"date"] = [report.generatedAt dateByAddingTimeInterval:1];
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "future record date is rejected");
    fixture = MutableCacheFixture(data);
    for (NSMutableDictionary *node in fixture[@"objects"]) if ([node[@"kind"] isEqual:@"observation"]) {
        node[@"values"][@"value"][BAAnalyticsHistoryTemperatureCelsius] = @32;
        break;
    }
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil,
        "unverified unit values invalidate cache instead of bypassing normalization");
    fixture = MutableCacheFixture(data);
    for (NSMutableDictionary *node in fixture[@"objects"]) if ([node[@"kind"] isEqual:@"interval"]) {
        node[@"start"] = [node[@"end"] dateByAddingTimeInterval:1];
        break;
    }
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "reversed or clipped evidence dates are rejected");
    fixture = MutableCacheFixture(data);
    fixture[@"families"] = @{@"type": @"reference", @"value": @999999};
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "out-of-range object reference is rejected");
    fixture = MutableCacheFixture(data);
    ((NSMutableDictionary *)[fixture[@"objects"] firstObject])[@"kind"] = @"arbitrary-object-class";
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "unrecognized graph class cannot be decoded");
    fixture = MutableCacheFixture(data);
    NSMutableArray *excessive = [NSMutableArray arrayWithCapacity:60001];
    for (NSDictionary *node in fixture[@"objects"]) if ([node[@"kind"] isEqual:@"observation"]) { observationNode = [node mutableCopy]; break; }
    for (NSUInteger i = 0; i <= 60000; i++) [excessive addObject:observationNode];
    fixture[@"objects"] = excessive;
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil, "record count cap is enforced before object construction");

    fixture = MutableCacheFixture(data);
    [fixture[@"objects"] addObject:@{@"kind": @"metadata"}];
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil,
        "unreferenced malformed tail nodes are still validated after memoized references");
    fixture = MutableCacheFixture(data);
    for (NSUInteger i = 0; i < [fixture[@"objects"] count]; i++) {
        NSMutableDictionary *node = fixture[@"objects"][i];
        if (![node[@"kind"] isEqual:@"family"]) continue;
        node[@"window"] = @{@"type": @"reference", @"value": @(i)};
        break;
    }
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, NULL) == nil,
        "memoized graph decoding still rejects an active self-reference cycle");
    fixture = MutableCacheFixture(data);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:120000];
    for (NSUInteger i = 0; i < 120000; i++) [values addObject:@"budget"];
    NSDictionary *repeatedArray = @{@"type": @"array", @"value": values};
    NSMutableArray *aliases = [NSMutableArray arrayWithCapacity:17];
    for (NSUInteger i = 0; i < 17; i++) [aliases addObject:repeatedArray];
    for (NSMutableDictionary *node in fixture[@"objects"]) if ([node[@"kind"] isEqual:@"family"]) {
        node[@"payload"] = @{@"type": @"dictionary", @"value": @{@"budget": @{@"type": @"array", @"value": aliases}}};
        break;
    }
    @autoreleasepool {
        Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, &error) == nil &&
            [error.userInfo[@"reason"] isEqual:@2] && [error.userInfo[@"visits"] isEqual:@2000001],
            "aliased containers cannot bypass the unchanged two-million-value work budget");
    }
    fixture = MutableCacheFixture(data);
    NSUInteger metadataIndex = NSNotFound;
    for (NSUInteger i = 0; i < [fixture[@"objects"] count]; i++)
        if ([fixture[@"objects"][i][@"kind"] isEqual:@"metadata"]) { metadataIndex = i; break; }
    Assert(metadataIndex != NSNotFound, "depth fixture refers to metadata already decoded through the root map");
    NSDictionary *deepReference = @{@"type": @"reference", @"value": @(metadataIndex)};
    for (NSUInteger i = 0; i < 28; i++) deepReference = @{@"type": @"array", @"value": @[deepReference]};
    for (NSMutableDictionary *node in fixture[@"objects"]) if ([node[@"kind"] isEqual:@"family"]) {
        node[@"payload"] = @{@"type": @"dictionary", @"value": @{@"depth": deepReference}};
        break;
    }
    Assert(BAAnalyticsDecodeCachedReport(CacheFixtureData(fixture), report.generatedAt, &error) == nil &&
        [error.userInfo[@"reason"] isEqual:@1], "cached-node references still enforce the depth limit on every edge");

    BAAnalyticsFamilyReport *family = report.familyReports[BAAnalyticsFamilyDwell];
    BAAnalyticsFamilyReport *loading = [[BAAnalyticsFamilyReport alloc] initWithFamily:family.family availability:BAAnalyticsReportAvailabilityLoading
        window:family.window payload:family.payload limitations:family.limitations];
    BAAnalyticsReport *incomplete = [[BAAnalyticsReport alloc] initWithSequenceNumber:1 generatedAt:report.generatedAt sourceProfileIdentifier:report.sourceProfileIdentifier
        fieldMetadata:report.fieldMetadata familyReports:@{family.family: loading} error:nil];
    Assert(BAAnalyticsEncodeCachedReport(incomplete, &error) == nil && error != nil, "loading reports never overwrite completed cache");
    Assert([error.userInfo[@"stage"] isEqual:@1] && [error.userInfo[@"reason"] isEqual:@8],
        "incomplete evidence has a distinct cache eligibility diagnostic");
    BAAnalyticsReport *failed = [[BAAnalyticsReport alloc] initWithSequenceNumber:1 generatedAt:report.generatedAt sourceProfileIdentifier:report.sourceProfileIdentifier
        fieldMetadata:report.fieldMetadata familyReports:report.familyReports error:[NSError errorWithDomain:@"fixture" code:SQLITE_INTERRUPT userInfo:nil]];
    Assert(BAAnalyticsEncodeCachedReport(failed, &error) == nil && error != nil, "failed and cancelled reports cannot be cached");
}

static void AssertCompressedFixtureRejected(NSData *data, NSDate *date, NSUInteger reason, const char *message) {
    @autoreleasepool {
        NSError *error = nil;
        Assert(BAAnalyticsDecodeCachedReport(data, date, &error) == nil && error != nil &&
            (!reason || [error.userInfo[@"reason"] unsignedIntegerValue] == reason), message);
    }
}

static void TestProductionShapedCachedReport(void) {
    NSUInteger count = 33000;
    NSTimeInterval step = 12;
    NSString *rows = [NSString stringWithFormat:@"WITH RECURSIVE records(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM records WHERE i<%lu) "
        "INSERT INTO PLBatteryAgent_EventBackward_Battery (ID,timestamp,Level,InstantAmperage,ExternalConnected,IsCharging,FullyCharged,AppleRawMaxCapacity,Voltage) "
        "SELECT i+1,%.3f+i*%.3f,20+(i%%60),400,1,1,0,5900-(i%%43),12000+(i%%100) FROM records", (unsigned long)(count - 1), FixtureEpoch, step];
    NSString *ui = [NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventBackward_BatteryUI VALUES (1,%.3f,80,1)",
        FixtureEpoch + (count - 1) * step + step / 2];
    NSURL *url = Fixture(YES, @[OffsetRow(1, -3600, 0), rows,
        @"CREATE TABLE PLBatteryAgent_EventBackward_BatteryUI (ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,IsCharging INTEGER)", ui]);
    BAAnalyticsReport *report = Read(url, (count - 1) * step + step, 62);
    BAAnalyticsFamilyReport *capacity = report.familyReports[BAAnalyticsFamilyCapacity];
    BAAnalyticsObservation *last = capacity.window.observations.lastObject;
    Assert(report.familyReports.count == 10 && capacity.window.observations.count == count + 1 &&
        last.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] == nil,
        "production-shaped cache graph has many metrics and windows ending in a non-FCC source record");
    BAAnalyticsObservation *latestFCC = capacity.payload[BAAnalyticsPayloadLatestObservation];
    Assert(latestFCC.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] != nil && latestFCC != last,
        "capacity retains its latest relevant observation independently of other tables");
    BAAnalyticsHistoryWindow *rhythm = report.familyReports[BAAnalyticsFamilyRhythm].window;
    BAAnalyticsHistoryWindow *compare = report.familyReports[BAAnalyticsFamilyCompare].window;
    Assert(rhythm.intervals.count == count - 1 && rhythm.intervals.firstObject == compare.intervals.firstObject,
        "reader shares full immutable intervals between overlapping family windows");
    NSError *error = nil;
    __block NSUInteger encodeChecks = 0;
    NSData *data = nil;
    @autoreleasepool {
        data = BAAnalyticsEncodeCachedReportCancellable(report, &error, ^BOOL { encodeChecks++; return NO; });
    }
    Assert(data != nil && error == nil, "production-shaped multiwindow evidence fits the unchanged bounded cache codec");
    Assert(data.length > 16 && data.length <= 16 * 1024 * 1024 && !memcmp(data.bytes, "BAHCACHE", 8),
        "large production-shaped graph uses lossless compressed storage within the original physical file cap");
    const uint8_t *header = data.bytes;
    NSUInteger logicalSize = ((NSUInteger)header[12] << 24) | ((NSUInteger)header[13] << 16) | ((NSUInteger)header[14] << 8) | header[15];
    Assert(logicalSize > 16 * 1024 * 1024 && logicalSize <= 64 * 1024 * 1024,
        "compressed fixture exercises a logical graph exceeding the former raw storage limit");
    BAAnalyticsReport *restored = nil;
    @autoreleasepool {
        restored = BAAnalyticsDecodeCachedReport(data, report.generatedAt, &error);
    }
    Assert(restored != nil && error == nil && restored.isCached,
        "production-shaped cache restores its original completed generation");
    BAAnalyticsFamilyReport *copy = restored.familyReports[BAAnalyticsFamilyCapacity];
    BAAnalyticsObservation *cachedFCC = copy.payload[BAAnalyticsPayloadLatestObservation];
    Assert(copy.window.observations.count == count + 1 && [cachedFCC.identifier isEqual:latestFCC.identifier] &&
        copy.window.observations.lastObject.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] == nil,
        "roundtrip preserves every dense FCC record and the later independent non-FCC reading");
    Assert([restored.familyReports[BAAnalyticsFamilyRhythm].window.coverageSecondsByMetric isEqual:rhythm.coverageSecondsByMetric],
        "dense cache roundtrip preserves exact per-metric coverage");
    double minimum = INFINITY, maximum = -INFINITY;
    for (BAAnalyticsObservation *point in copy.window.observations) {
        NSNumber *value = point.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours];
        if (value) { minimum = MIN(minimum, value.doubleValue); maximum = MAX(maximum, value.doubleValue); }
    }
    AssertNear(minimum, 5858, "compression preserves the full dense capacity minimum");
    AssertNear(maximum, 5900, "compression preserves the full dense capacity maximum");
    for (NSString *key in report.familyReports) {
        BAAnalyticsFamilyReport *before = report.familyReports[key], *after = restored.familyReports[key];
        Assert(before.window.observations.count == after.window.observations.count && before.window.intervals.count == after.window.intervals.count &&
            before.window.gaps.count == after.window.gaps.count && [before.window.coverageSecondsByMetric isEqual:after.window.coverageSecondsByMetric],
            "compression retains every family's exact records intervals gaps and validated coverage");
        AssertNear(before.window.missingDuration, after.window.missingDuration, "compression retains each family's missing time");
    }
    restored = nil;

    NSMutableData *corrupt = [data mutableCopy];
    ((uint8_t *)corrupt.mutableBytes)[11] = 2;
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 11,
        "unknown compression envelope version is rejected");
    AssertCompressedFixtureRejected([data subdataWithRange:NSMakeRange(0, 12)], report.generatedAt, 11,
        "truncated compression header is rejected before inflation");
    corrupt = [data mutableCopy];
    memset((uint8_t *)corrupt.mutableBytes + 12, 0, 4);
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 12,
        "zero logical size is rejected before inflation");
    ((uint8_t *)corrupt.mutableBytes)[12] = 4; ((uint8_t *)corrupt.mutableBytes)[15] = 1;
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 12,
        "over-64-MiB size declaration is rejected before allocation");
    corrupt = [data mutableCopy];
    ((uint8_t *)corrupt.mutableBytes)[15] ^= 1;
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 18,
        "declared size must match the exact inflated byte count");
    corrupt = [data mutableCopy];
    ((uint8_t *)corrupt.mutableBytes)[corrupt.length - 1] ^= 1;
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 0, "corrupt compressed checksum is rejected");
    AssertCompressedFixtureRejected([data subdataWithRange:NSMakeRange(0, data.length - 1)], report.generatedAt, 20,
        "incomplete compressed stream must reach a validated EOF");
    corrupt = [data mutableCopy]; uint8_t tail = 0; [corrupt appendBytes:&tail length:1];
    AssertCompressedFixtureRejected(corrupt, report.generatedAt, 19,
        "trailing bytes after the zlib stream are rejected");
    __block NSUInteger decodeChecks = 0;
    Assert(BAAnalyticsDecodeCachedReportCancellable(data, report.generatedAt, &error, ^BOOL { return ++decodeChecks > 2; }) == nil &&
        [error.userInfo[@"stage"] isEqual:@8] && [error.userInfo[@"reason"] isEqual:@3], "inflation is cooperatively cancelled between bounded chunks");
    NSUInteger stopBeforeEnd = encodeChecks - 2;
    __block NSUInteger cancelledEncodeChecks = 0;
    @autoreleasepool {
        Assert(BAAnalyticsEncodeCachedReportCancellable(report, &error, ^BOOL { return ++cancelledEncodeChecks > stopBeforeEnd; }) == nil &&
            [error.userInfo[@"stage"] isEqual:@6] && [error.userInfo[@"reason"] isEqual:@3], "deflation is cooperatively cancelled between bounded chunks");
    }
}

@interface HistorySubscriber : NSObject <BAAnalyticsHistoryServiceSubscriber>
@property (nonatomic) NSUInteger deliveries;
@property (nonatomic) BOOL allDeliveriesOnMainThread;
@property (nonatomic, strong) NSMutableArray<BAAnalyticsReport *> *reports;
@end
@implementation HistorySubscriber
- (instancetype)init { self = [super init]; if (self) { _allDeliveriesOnMainThread = YES; _reports = [NSMutableArray array]; } return self; }
- (void)analyticsHistoryService:(BAAnalyticsHistoryService *)service didPublishReport:(BAAnalyticsReport *)report {
	(void)service;
	Assert(report != nil, "service published an immutable report");
	self.deliveries++;
	if (self.reports.count < 8) [self.reports addObject:report];
	self.allDeliveriesOnMainThread = self.allDeliveriesOnMainThread && NSThread.isMainThread;
}
@end

static BOOL WaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
	NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && limit.timeIntervalSinceNow > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	return condition();
}


// Test-only phase observation makes asynchronous rejection deterministic; no
// production API is added merely to expose private lifecycle implementation.
@interface BAAnalyticsHistoryService (HistoryTestPhases)
@property (nonatomic, readonly) BOOL cacheRestorePending;
@property (nonatomic, readonly) BOOL acquisitionPending;
@end

static NSURL *IsolatedHistoryCache(void) {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[@"battman-cache-fixture-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    [FixtureDirectories addObject:directory];
    Assert([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL],
        "created app-owned isolated cache fixture");
    return directory;
}

static BAAnalyticsHistoryService *InactiveCachedService(NSURL *source, NSURL *cache, HistorySubscriber *subscriber) {
    BAAnalyticsHistoryService *service = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:source cacheDirectoryURL:cache];
    [service setApplicationActive:NO];
    [service addSubscriber:subscriber];
    Assert(WaitUntil(^BOOL { return !service.cacheRestorePending; }, 5), "inactive cache bootstrap completed asynchronously");
    Assert(!service.isPolling && !service.acquisitionPending, "inactive bootstrap does not launch a SQL refresh");
    return service;
}

static NSDictionary<NSString *, BAAnalyticsObservation *> *CacheRecordMap(BAAnalyticsReport *report) {
    NSMutableDictionary *records = [NSMutableDictionary dictionary];
    for (BAAnalyticsFamilyReport *family in report.familyReports.allValues)
        for (BAAnalyticsObservation *point in family.window.observations) records[point.identifier] = point;
    return records;
}

static void TestPersistentHistoryService(void) {
    double recent = NSDate.date.timeIntervalSince1970 - FixtureEpoch - 300;
    NSURL *source = Fixture(YES, @[OffsetRow(1, recent - 3600, 30),
        BatteryRow(1, recent, @40, @100, @1, @1, @0), BatteryRow(2, recent + 60, @41, @100, @1, @1, @0)]);
    NSData *sourceBytes = [NSData dataWithContentsOfURL:source];
    NSURL *cache = IsolatedHistoryCache(), *completed = [cache URLByAppendingPathComponent:@"completed.plist"];
    HistorySubscriber *subscriber = [HistorySubscriber new];
    __weak BAAnalyticsHistoryService *weakWarm;
    BAAnalyticsReport *original = nil;
    @autoreleasepool {
        BAAnalyticsHistoryService *warm = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:source cacheDirectoryURL:cache];
        weakWarm = warm;
        [warm addSubscriber:subscriber];
        Assert(WaitUntil(^BOOL { return warm.latestReport && !warm.acquisitionPending &&
            [NSFileManager.defaultManager fileExistsAtPath:completed.path]; }, 8), "warm service completed and atomically wrote reusable evidence");
        original = warm.latestReport;
        Assert(!original.isCached && subscriber.allDeliveriesOnMainThread, "first successful SQL result is fresh and delivered on main");
        [warm removeSubscriber:subscriber];
        warm = nil;
    }
    Assert(WaitUntil(^BOOL { return weakWarm == nil; }, 3), "warm service released after unsubscribing without polling backlog");
    NSData *validEnvelope = [NSData dataWithContentsOfURL:completed];
    Assert(validEnvelope.length > 0, "completed cache is present on disk before cold bootstrap");
    HistorySubscriber *coldSubscriber = [HistorySubscriber new];
    BAAnalyticsHistoryService *cold = InactiveCachedService(source, cache, coldSubscriber);
    Assert(cold.latestReport.isCached && [cold.latestReport.generatedAt isEqual:original.generatedAt] && coldSubscriber.deliveries == 1,
        "inactive cold process restores exactly one cached generation with its original acquisition time");
    NSDictionary *records = CacheRecordMap(cold.latestReport), *prior = CacheRecordMap(original);
    Assert([NSSet setWithArray:records.allKeys].count == prior.count && [NSSet setWithArray:records.allKeys].count == 2,
        "restored service retains the complete independent source records");
    for (NSString *identifier in prior) {
        BAAnalyticsObservation *point = records[identifier], *previous = prior[identifier];
        Assert(point != nil && [point.values isEqual:previous.values] && [point.timestamp isEqual:previous.timestamp],
            "cold startup values and exact source times equal the prior completed graph");
        Assert(point.values[BAAnalyticsHistoryTemperatureCelsius] == nil && !point.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius].unitValidated,
            "service disk bootstrap preserves unverified provenance without a physical-unit reading");
        for (BAAnalyticsFamilyReport *family in cold.latestReport.familyReports.allValues)
            for (BAAnalyticsObservation *shared in family.window.observations)
                if ([shared.identifier isEqual:identifier]) Assert(shared == point, "cold restored families share one immutable source point");
    }
    AssertNear(cold.latestReport.familyReports[BAAnalyticsFamilyDwell].window.coveredDuration,
        original.familyReports[BAAnalyticsFamilyDwell].window.coveredDuration, "cold bootstrap preserves independently validated coverage");

    Assert([NSFileManager.defaultManager removeItemAtURL:source error:NULL], "temporarily removed only the owned source fixture");
    NSUInteger deliveries = coldSubscriber.deliveries;
    [cold setApplicationActive:YES];
    Assert(WaitUntil(^BOOL { return !cold.acquisitionPending && coldSubscriber.deliveries > deliveries; }, 8),
        "failed active refresh completed without replacing cached evidence with unavailable data");
    Assert(cold.latestReport.isCached && [cold.latestReport.generatedAt isEqual:original.generatedAt] && CacheRecordMap(cold.latestReport).count == 2,
        "deleted source retains the last complete cached report with honest age");
    Assert([validEnvelope isEqual:[NSData dataWithContentsOfURL:completed]], "source failure did not overwrite the good persisted cache");
    Assert([[@"synthetic invalid SQLite bytes" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:source atomically:YES],
        "replaced only the test source with malformed bytes");
    deliveries = coldSubscriber.deliveries;
    [cold refreshNow];
    Assert(WaitUntil(^BOOL { return !cold.acquisitionPending && coldSubscriber.deliveries > deliveries; }, 8), "corrupt source refresh completed");
    Assert(cold.latestReport.isCached && [cold.latestReport.generatedAt isEqual:original.generatedAt] &&
        [validEnvelope isEqual:[NSData dataWithContentsOfURL:completed]], "corrupt source cannot destroy displayed or persisted complete history");
    [cold setApplicationActive:NO]; [cold removeSubscriber:coldSubscriber]; cold = nil;
    Assert([sourceBytes writeToURL:source atomically:YES], "restored original owned fixture bytes");

    NSURL *otherSource = Fixture(YES, @[OffsetRow(1, recent - 3600, 30), BatteryRow(1, recent, @90, @0, @0, @0, @0)]);
    HistorySubscriber *rejectedSubscriber = [HistorySubscriber new];
    BAAnalyticsHistoryService *rejected = InactiveCachedService(otherSource, cache, rejectedSubscriber);
    Assert(rejected.latestReport == nil && rejectedSubscriber.deliveries == 0, "cache from a different source directory identity is rejected");
    [rejected removeSubscriber:rejectedSubscriber]; rejected = nil;

    for (NSUInteger invalidKind = 0; invalidKind < 3; invalidKind++) {
        NSMutableDictionary *envelope = MutableCacheFixture(validEnvelope);
        if (invalidKind == 2) Assert([[NSData dataWithBytes:"bad" length:3] writeToURL:completed atomically:YES], "wrote synthetic corrupt cache");
        else {
            NSMutableDictionary *report = MutableCacheFixture(envelope[@"report"]);
            report[@"generatedAt"] = [NSDate.date dateByAddingTimeInterval:invalidKind == 0 ? 3600 : -(24 * 3600 + 10)];
            envelope[@"report"] = CacheFixtureData(report);
            Assert([CacheFixtureData(envelope) writeToURL:completed atomically:YES], "wrote synthetic invalid-age cache envelope");
        }
        rejectedSubscriber = [HistorySubscriber new]; rejected = InactiveCachedService(source, cache, rejectedSubscriber);
        Assert(rejected.latestReport == nil && rejectedSubscriber.deliveries == 0, "future expired or corrupt disk cache produces no false completed state");
        [rejected removeSubscriber:rejectedSubscriber]; rejected = nil;
    }
    Assert([validEnvelope writeToURL:completed atomically:YES], "restored valid cache for memory-pressure test");
    HistorySubscriber *pressureSubscriber = [HistorySubscriber new];
    BAAnalyticsHistoryService *pressure = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:source cacheDirectoryURL:cache];
    [pressure setApplicationActive:NO]; [pressure addSubscriber:pressureSubscriber]; [pressure handleMemoryPressure];
    Assert(WaitUntil(^BOOL { return !pressure.cacheRestorePending; }, 5), "cancelled bootstrap completed its bounded task");
    Assert(pressure.latestReport == nil && pressureSubscriber.deliveries == 0 && !pressure.isPolling && !pressure.acquisitionPending,
        "memory pressure suppresses cached bootstrap publication and immediate retries");
    [pressure removeSubscriber:pressureSubscriber];
}

static void WriteGzipFixture(NSData *bytes, NSURL *url) {
    gzFile stream = gzopen(url.path.fileSystemRepresentation, "wb");
    Assert(stream != NULL, "opened synthetic archive stream");
    BOOL written = gzwrite(stream, bytes.bytes, (unsigned int)bytes.length) == (int)bytes.length;
    int closed = gzclose(stream);
    Assert(written && closed == Z_OK, "wrote complete synthetic gzip archive");
}

static void TestArchiveEnrichmentService(void) {
    double base = NSDate.date.timeIntervalSince1970 - FixtureEpoch - 630;
    NSURL *source = Fixture(YES, @[OffsetRow(1, base - 3600, 30),
        BatteryRow(1, base + 120, @20, @400, @1, @1, @0), BatteryRow(2, base + 180, @21, @400, @1, @1, @0),
        BatteryRow(3, base + 240, @22, @400, @1, @1, @0)]);
    NSURL *archiveSource = Fixture(YES, @[OffsetRow(1, base - 3600, 30),
        BatteryRow(1, base, @0, @400, @1, @1, @0), BatteryRow(2, base + 60, @10, @400, @1, @1, @0),
        BatteryRow(3, base + 120, @80, @400, @1, @1, @0), BatteryRow(4, base + 180, @90, @400, @1, @1, @0)]);
    NSURL *archives = [source.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Archives" isDirectory:YES];
    Assert([NSFileManager.defaultManager createDirectoryAtURL:archives withIntermediateDirectories:YES attributes:nil error:NULL], "created source-owned synthetic Archives directory");
    NSURL *compressed = [archives URLByAppendingPathComponent:@"older.PLSQL.gz"];
    WriteGzipFixture([NSData dataWithContentsOfURL:archiveSource], compressed);
    NSURL *bad = [archives URLByAppendingPathComponent:@"invalid.PLSQL.gz"];
    WriteGzipFixture([@"synthetic non-SQLite archive" dataUsingEncoding:NSUTF8StringEncoding], bad);
    NSURL *truncated = [archives URLByAppendingPathComponent:@"truncated.PLSQL.gz"];
    NSData *fullGzip = [NSData dataWithContentsOfURL:compressed];
    Assert([[fullGzip subdataWithRange:NSMakeRange(0, fullGzip.length / 2)] writeToURL:truncated atomically:YES], "created synthetic truncated gzip");
    NSData *sourceBytes = [NSData dataWithContentsOfURL:source], *archiveBytes = [NSData dataWithContentsOfURL:compressed];
    NSURL *cache = IsolatedHistoryCache(); HistorySubscriber *subscriber = [HistorySubscriber new];
    BAAnalyticsHistoryService *service = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:source cacheDirectoryURL:cache];
    [service addSubscriber:subscriber];
    NSURL *completed = [cache URLByAppendingPathComponent:@"completed.plist"];
    Assert(WaitUntil(^BOOL { return !service.acquisitionPending && service.latestReport.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 5 &&
        [NSFileManager.defaultManager fileExistsAtPath:completed.path]; }, 10), "service publishes archive-enriched evidence and stores it after a current-only generation");
    Assert(subscriber.reports.count >= 2 && subscriber.reports.firstObject.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 3 &&
        subscriber.reports.lastObject.familyReports[BAAnalyticsFamilyDwell].window.observations.count == 5 &&
        subscriber.reports.lastObject.sequenceNumber > subscriber.reports.firstObject.sequenceNumber,
        "current database becomes visible before archive enrichment as a separate generation");
    AssertNear([Observation(service.latestReport, BatteryTable, base + 120).values[BAAnalyticsHistorySOCPercent] doubleValue], 20,
        "compressed archive overlap cannot replace current values or double count readings");
    AssertNear(service.latestReport.familyReports[BAAnalyticsFamilyDwell].window.coverageSecondsByMetric[BAAnalyticsHistorySOCPercent].doubleValue, 180,
        "archive enrichment preserves source-discontinuity missing duration");
    Assert([sourceBytes isEqual:[NSData dataWithContentsOfURL:source]] && [archiveBytes isEqual:[NSData dataWithContentsOfURL:compressed]],
        "system-owned synthetic current and compressed archives are not modified");
    NSURL *extracted = [cache URLByAppendingPathComponent:@"Archives" isDirectory:YES];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:extracted includingPropertiesForKeys:nil options:0 error:NULL];
    NSString *actualParent = files.firstObject.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *expectedParent = extracted.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    if (files.count != 1 || ![files.firstObject.pathExtension isEqual:@"sqlite"] ||
        ![actualParent isEqual:expectedParent]) {
        NSMutableArray *extensions = [NSMutableArray array];
        for (NSURL *file in files) [extensions addObject:file.pathExtension ?: @""];
        fprintf(stderr, "Synthetic archive cache: files=%lu extensions=%s parentURLMatches=%d parentPathMatches=%d\n",
            (unsigned long)files.count, [extensions componentsJoinedByString:@","].UTF8String,
            [files.firstObject.URLByDeletingLastPathComponent isEqual:extracted],
            [actualParent isEqual:expectedParent]);
    }
    Assert(files.count == 1, "exactly one validated gzip leaves an extracted cache file; invalid and truncated archives leave none");
    Assert([files.firstObject.pathExtension isEqual:@"sqlite"], "extraction cache contains a completed SQLite rather than a partial file");
    Assert([actualParent isEqual:expectedParent], "extracted SQLite resides in exactly the app-owned archive storage");
    Assert([[NSFileManager.defaultManager contentsOfDirectoryAtURL:archives includingPropertiesForKeys:nil options:0 error:NULL] count] == 3,
        "decompression creates no database or partial file in the original archive directory");
    NSData *extractedBytes = [NSData dataWithContentsOfURL:files.firstObject];
    Assert(extractedBytes.length >= 16 && !memcmp(extractedBytes.bytes, "SQLite format 3\0", 16), "completed extraction retains a valid SQLite header");
    NSDictionary *before = CacheRecordMap(service.latestReport);
    NSUInteger oldDeliveries = subscriber.deliveries;
    uint64_t oldSequence = service.latestReport.sequenceNumber;
    [service refreshNow];
    Assert(WaitUntil(^BOOL { return !service.acquisitionPending && subscriber.deliveries > oldDeliveries &&
        service.latestReport.sequenceNumber > oldSequence; }, 10), "explicit refresh reuses archives while updating report generation");
    NSDictionary *after = CacheRecordMap(service.latestReport);
    Assert([NSSet setWithArray:before.allKeys].count == after.count, "repeated enrichment retains complete record count");
    for (NSString *identifier in before) Assert(after[identifier] != nil, "gzip source IDs remain stable across decompression cache reuse");
    NSArray<NSURL *> *reused = [NSFileManager.defaultManager contentsOfDirectoryAtURL:extracted includingPropertiesForKeys:nil options:0 error:NULL];
    Assert(reused.count == 1 && [reused.firstObject isEqual:files.firstObject] &&
        [extractedBytes isEqual:[NSData dataWithContentsOfURL:reused.firstObject]], "valid archive extraction is reused without transient-file residue");
    Assert(subscriber.allDeliveriesOnMainThread, "both current and archive generations deliver UIKit-facing state on main");
    [service removeSubscriber:subscriber];
}

static void TestVisibleActiveWeakSubscriptions(void) {
	NSURL *url = Fixture(YES, @[OffsetRow(1, -3600, 30), BatteryRow(1, 0, @40, @0, @1, @0, @0)]);
	BAAnalyticsHistoryService *service = [[BAAnalyticsHistoryService alloc] initWithDatabaseURL:url];
	Assert(!service.isPolling && service.subscriberCount == 0, "service started without polling or subscribers");
	Assert(BAAnalyticsHistoryService.sharedService == BAAnalyticsHistoryService.sharedService, "built-in cards shared one history service");
	[service setApplicationActive:NO];
	__weak HistorySubscriber *weakSubscriber;
	@autoreleasepool {
		HistorySubscriber *temporary = [HistorySubscriber new];
		weakSubscriber = temporary;
		[service addSubscriber:temporary];
		Assert(service.subscriberCount == 1 && !service.isPolling, "inactive subscription did not start acquisition");
	}
	Assert(weakSubscriber == nil && service.subscriberCount == 0, "service retained subscribers weakly");
	HistorySubscriber *subscriber = [HistorySubscriber new];
	[service addSubscriber:subscriber];
	[service setApplicationActive:YES];
	Assert(service.isPolling, "active visible subscription started acquisition");
	Assert(WaitUntil(^BOOL { return subscriber.deliveries > 0; }, 3), "visible service published its asynchronous report");
	Assert(subscriber.allDeliveriesOnMainThread && service.latestReport != nil, "report delivery and cache were available on the main thread");
	[service setApplicationActive:NO];
	Assert(!service.isPolling, "background lifecycle stopped polling");
	[service removeSubscriber:subscriber];
	Assert(service.subscriberCount == 0 && !service.isPolling, "last visible subscriber removal stopped acquisition");
	[service handleMemoryPressure];
	Assert(service.latestReport == nil, "memory pressure released the bounded report cache");
}

int main(void) {
	@autoreleasepool {
		FixtureDirectories = [NSMutableArray array];
		int status = 0;
		@try {
			TestImmutableEvidence();
			TestFieldsAndIndependentCoverage();
			TestClockSegmentsStatesAndStableIdentifiers();
			TestIndependentTablesAndWindowClipping();
			TestConfigurationEpochBoundaries();
			TestPlatformCadenceUnvalidatedTimeAndSparseCapacity();
			TestWirelessCandidateUnits();
			TestRotatedHistorySources();
			TestRotatedSourceBounds();
			TestCachedReportGraph();
			TestProductionShapedCachedReport();
			TestVisibleActiveWeakSubscriptions();
			TestPersistentHistoryService();
			TestArchiveEnrichmentService();
			printf("Analytics history synthetic SQLite and lifecycle tests passed.\n");
		} @catch (NSException *exception) {
			fprintf(stderr, "%s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
			status = 1;
		} @finally {
			for (NSURL *directory in FixtureDirectories) [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
		}
		return status;
	}
}
