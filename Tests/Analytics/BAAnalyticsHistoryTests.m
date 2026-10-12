#import <Foundation/Foundation.h>

#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryReader.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryService.h"

#include <math.h>
#include <sqlite3.h>
#include <stdio.h>

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

@interface HistorySubscriber : NSObject <BAAnalyticsHistoryServiceSubscriber>
@property (nonatomic) NSUInteger deliveries;
@property (nonatomic) BOOL allDeliveriesOnMainThread;
@end
@implementation HistorySubscriber
- (instancetype)init { self = [super init]; if (self) _allDeliveriesOnMainThread = YES; return self; }
- (void)analyticsHistoryService:(BAAnalyticsHistoryService *)service didPublishReport:(BAAnalyticsReport *)report {
	(void)service;
	Assert(report != nil, "service published an immutable report");
	self.deliveries++;
	self.allDeliveriesOnMainThread = self.allDeliveriesOnMainThread && NSThread.isMainThread;
}
@end

static BOOL WaitUntil(BOOL (^condition)(void), NSTimeInterval timeout) {
	NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!condition() && limit.timeIntervalSinceNow > 0)
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	return condition();
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
			TestVisibleActiveWeakSubscriptions();
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
