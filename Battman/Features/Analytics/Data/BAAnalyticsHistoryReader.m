#import "BAAnalyticsHistoryReader.h"
#import <TargetConditionals.h>
#include <sqlite3.h>
#include <sys/stat.h>
#include <unistd.h>
#include <math.h>

static NSString *const BABatteryTable = @"PLBatteryAgent_EventBackward_Battery";
static NSString *const BABatteryUITable = @"PLBatteryAgent_EventBackward_BatteryUI";
static NSString *const BAConfigTable = @"PLBatteryAgent_EventNone_BatteryConfig";
static NSString *const BAOffsetTable = @"PLStorageOperator_EventForward_TimeOffset";
static NSString *const BAChargingTable = @"PLBatteryAgent_EventPoint_ChargingInfo";
static NSString *const BAThermalTable = @"PLSMCAgent_EventPoint_ThermalInstantKeys";
static NSTimeInterval const BADay = 86400;
static BAAnalyticsReport *BACancelledHistoryReport(NSDate *endDate, uint64_t sequenceNumber) {
	// Cancelled generations are discarded by the service; don't construct ten
	// unused family windows or retain partially decoded evidence on this path.
	NSError *error = [NSError errorWithDomain:@"BAAnalyticsHistory" code:SQLITE_INTERRUPT
		userInfo:@{NSLocalizedDescriptionKey: @"History acquisition cancelled."}];
	return [[BAAnalyticsReport alloc] initWithSequenceNumber:sequenceNumber generatedAt:endDate sourceProfileIdentifier:@"powerlog.unknown"
		fieldMetadata:@{} familyReports:@{} error:error];
}

@interface BAHistoryRecord : NSObject
@property (nonatomic, strong) BAAnalyticsObservation *observation;
@property (nonatomic, copy) NSString *segment;
@property (nonatomic) BOOL ambiguousTimestamp;
@end
@implementation BAHistoryRecord
@end

static NSString *BAQuoted(NSString *identifier) {
	return [NSString stringWithFormat:@"\"%@\"", [identifier stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

static NSString *BAStableIdentifier(NSString *text) {
	// IDs do not depend on query order, window clipping, report sequence or array indices.
	uint64_t hash = UINT64_C(14695981039346656037);
	NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
	const uint8_t *p = bytes.bytes;
	for (NSUInteger i = 0; i < bytes.length; i++) { hash ^= p[i]; hash *= UINT64_C(1099511628211); }
	return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

static NSArray<NSDictionary *> *BAConfigurationEpochs(NSArray<NSDictionary *> *boundaries, BOOL (^cancelled)(void)) {
	NSMutableArray *epochs = [NSMutableArray arrayWithCapacity:boundaries.count];
	NSString *digest = @"";
	uint64_t generation = 0;
	for (NSDictionary *boundary in boundaries) @autoreleasepool {
		if ((generation & 63) == 0 && cancelled()) return nil;
		// Fold each boundary into a bounded token once. The generation also keeps
		// repeated IDs/timestamps in distinct epochs without retaining the prefix.
		digest = BAStableIdentifier([NSString stringWithFormat:@"%@/configuration:%@", digest, boundary[@"ID"] ?: boundary[@"timestamp"]]);
		NSString *token = [NSString stringWithFormat:@"%016llx:%@", (unsigned long long)++generation, digest];
		[epochs addObject:@{@"timestamp": boundary[@"timestamp"], @"token": token}];
	}
	return epochs;
}

static NSString *BAConfigurationEpochForTimestamp(double timestamp, NSArray<NSDictionary *> *epochs) {
	NSUInteger lo = 0, hi = epochs.count;
	while (lo < hi) {
		NSUInteger mid = lo + (hi - lo) / 2;
		if ([epochs[mid][@"timestamp"] doubleValue] <= timestamp) lo = mid + 1;
		else hi = mid;
	}
	return lo ? epochs[lo - 1][@"token"] : nil;
}

NSURL *BAAnalyticsResolveHistoryURL(BOOL (^cancelled)(void)) {
#if TARGET_OS_SIMULATOR || TARGET_OS_OSX
	// A Simulator reading the host's log must use the Mac profile, not the simulated phone.
	NSString *macPath = @"/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL";
	if (access(macPath.fileSystemRepresentation, R_OK) == 0 ||
		access([[macPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Archives"].fileSystemRepresentation, R_OK) == 0)
		return [NSURL fileURLWithPath:macPath];
#endif
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *root in @[@"/var/containers/Shared/SystemGroup", @"/private/var/containers/Shared/SystemGroup"]) {
		for (NSString *name in [fm contentsOfDirectoryAtPath:root error:NULL]) @autoreleasepool {
			if (cancelled()) return nil;
			NSString *container = [root stringByAppendingPathComponent:name];
			NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[container stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
			if (![metadata[@"MCMMetadataIdentifier"] isEqual:@"systemgroup.com.apple.powerlog"]) continue;
			NSString *path = [container stringByAppendingPathComponent:@"Library/BatteryLife/CurrentPowerlog.PLSQL"];
			if (access(path.fileSystemRepresentation, R_OK) == 0 ||
				access([[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Archives"].fileSystemRepresentation, R_OK) == 0)
				return [NSURL fileURLWithPath:path];
		}
	}
	for (NSString *path in @[@"/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL", @"/private/var/db/powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL"])
		if (access(path.fileSystemRepresentation, R_OK) == 0 ||
			access([[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Archives"].fileSystemRepresentation, R_OK) == 0)
			return [NSURL fileURLWithPath:path];
	return nil;
}

NSString *BAAnalyticsHistorySourceIdentity(NSURL *databaseURL) {
	struct stat info;
	NSURL *parent = databaseURL.URLByDeletingLastPathComponent;
	if (!databaseURL.isFileURL || stat(parent.path.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode)) return nil;
	return [NSString stringWithFormat:@"%llu:%llu:%lld", (unsigned long long)info.st_dev,
		(unsigned long long)info.st_ino, (long long)info.st_birthtimespec.tv_sec];
}

static NSSet<NSString *> *BAColumns(sqlite3 *db, NSString *table) {
	sqlite3_stmt *statement = NULL;
	NSMutableSet *columns = [NSMutableSet set];
	NSString *query = [NSString stringWithFormat:@"PRAGMA table_info(%@)", BAQuoted(table)];
	if (sqlite3_prepare_v2(db, query.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
		while (sqlite3_step(statement) == SQLITE_ROW && columns.count < 512) {
			const char *name = (const char *)sqlite3_column_text(statement, 1);
			if (name) [columns addObject:[NSString stringWithUTF8String:name]];
		}
	}
	sqlite3_finalize(statement);
	return [columns copy];
}

static NSNumber *BANumber(sqlite3_stmt *statement, int column) {
	int type = sqlite3_column_type(statement, column);
	if (type != SQLITE_INTEGER && type != SQLITE_FLOAT) return nil;
	double value = sqlite3_column_double(statement, column);
	return isfinite(value) ? @(value) : nil;
}

@interface BAHistoryReadContext : NSObject
@property (nonatomic, copy) BOOL (^cancelled)(void);
@property (nonatomic) NSTimeInterval deadline;
@end
@implementation BAHistoryReadContext
@end
static int BAReadProgress(void *pointer) {
	BAHistoryReadContext *context = (__bridge BAHistoryReadContext *)pointer;
	return context.cancelled() || NSProcessInfo.processInfo.systemUptime > context.deadline;
}

static NSArray<NSDictionary *> *BARows(sqlite3 *db, NSString *table, NSSet *schema, NSArray<NSString *> *requestedColumns,
	double start, double end, NSUInteger limit, NSMutableArray<NSString *> *limitations, BOOL (^cancelled)(void)) {
	if (cancelled()) return nil;
	if (![schema containsObject:@"timestamp"]) return @[];
	NSMutableArray *columns = [NSMutableArray arrayWithObjects:@"timestamp", nil];
	if ([schema containsObject:@"ID"]) [columns addObject:@"ID"];
	for (NSString *column in requestedColumns)
		if ([schema containsObject:column] && ![columns containsObject:column]) [columns addObject:column];
	NSMutableArray *quoted = [NSMutableArray array];
	for (NSString *column in columns) [quoted addObject:BAQuoted(column)];
	NSString *query = [NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC%@ LIMIT ?",
		[quoted componentsJoinedByString:@","], BAQuoted(table), [schema containsObject:@"ID"] ? @", ID DESC" : @""];
	sqlite3_stmt *statement = NULL;
	NSMutableArray *rows = [NSMutableArray array];
	int result = sqlite3_prepare_v2(db, query.UTF8String, -1, &statement, NULL);
	@try {
	if (result == SQLITE_OK) {
		sqlite3_bind_double(statement, 1, start);
		sqlite3_bind_double(statement, 2, end);
		sqlite3_bind_int64(statement, 3, (sqlite3_int64)limit);
		while ((result = sqlite3_step(statement)) == SQLITE_ROW) @autoreleasepool {
			if ((rows.count & 63) == 0 && cancelled()) return nil;
			NSMutableDictionary *row = [NSMutableDictionary dictionary];
			for (NSUInteger i = 0; i < columns.count; i++) {
				NSNumber *number = BANumber(statement, (int)i);
				if (number) row[columns[i]] = number;
			}
			[rows addObject:row];
		}
	}
	} @finally { sqlite3_finalize(statement); }
	if (result != SQLITE_DONE) [limitations addObject:[NSString stringWithFormat:@"%@ read incomplete (SQLite %d).", table, result]];
	if (rows.count == limit) [limitations addObject:[NSString stringWithFormat:@"%@ reached its bounded row limit; older coverage is unavailable.", table]];
	return [[rows reverseObjectEnumerator] allObjects];
}

static NSArray *BAOffsets(sqlite3 *db, NSSet *schema, double end, NSMutableArray *limitations, BOOL (^cancelled)(void)) {
	if (![schema containsObject:@"system"]) return @[];
	// Include a predecessor to every requested window; never use the newest offset for all rows.
	NSArray *rows = BARows(db, BAOffsetTable, schema, @[@"system"], 0, end + BADay, 2048, limitations, cancelled);
	NSMutableArray *segments = [NSMutableArray array];
	NSNumber *previous = nil, *segmentStart = nil;
	for (NSDictionary *row in rows) @autoreleasepool {
		if ((segments.count & 63) == 0 && cancelled()) return nil;
		NSNumber *system = row[@"system"];
		if (!previous || ![previous isEqual:system]) segmentStart = row[@"timestamp"];
		NSMutableDictionary *segment = [row mutableCopy];
		if (segmentStart) segment[@"segmentStart"] = segmentStart;
		[segments addObject:segment];
		previous = system;
	}
	return segments;
}

static NSDictionary *BAOffsetForTimestamp(double timestamp, NSArray<NSDictionary *> *offsets) {
	// Binary search keeps normalization bounded even with thousands of clock segments.
	NSUInteger lo = 0, hi = offsets.count;
	while (lo < hi) {
		NSUInteger mid = lo + (hi - lo) / 2;
		if ([offsets[mid][@"timestamp"] doubleValue] <= timestamp) lo = mid + 1; else hi = mid;
	}
	if (!lo) return nil;
	NSDictionary *offset = offsets[lo - 1];
	NSNumber *system = offset[@"system"];
	return system && fabs(system.doubleValue) <= BADay ? offset : nil;
}

static void BARegister(NSMutableDictionary *metadata, NSSet *schema, NSString *table,
	NSString *column, NSString *metric, NSString *unit, NSString *decoder, BOOL validated) {
	if (![schema containsObject:column]) return;
	metadata[metric] = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:table sourceColumn:column
		unit:unit decoderIdentifier:decoder unitValidated:validated];
}

static NSDictionary *BAFieldMap(NSString *table, NSSet<NSString *> *schema, NSString *profile) {
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
	BOOL known = ![profile isEqual:@"powerlog.unknown"];
	BARegister(metadata, schema, table, @"Level", BAAnalyticsHistorySOCPercent, @"%", @"powerlog.level.percent.v1", YES);
	BARegister(metadata, schema, table, @"ExternalConnected", BAAnalyticsHistoryExternalConnected, @"boolean", @"powerlog.boolean01.v1", YES);
	BARegister(metadata, schema, table, @"IsCharging", BAAnalyticsHistoryIsCharging, @"boolean", @"powerlog.boolean01.v1", YES);
	BARegister(metadata, schema, table, @"FullyCharged", BAAnalyticsHistoryFullyCharged, @"boolean", @"powerlog.boolean01.v1", YES);
	BARegister(metadata, schema, table, @"NotChargingReason", BAAnalyticsHistoryNotChargingReasonCode, @"code", @"powerlog.reason.raw-code.v1", YES);
	BARegister(metadata, schema, table, @"Voltage", BAAnalyticsHistoryVoltageMillivolts, @"mV", @"powerlog.battery.millivolts.v1", known);
	BARegister(metadata, schema, table, @"InstantAmperage", BAAnalyticsHistoryCurrentMilliamps, @"mA", @"powerlog.battery.signed-milliamps.v1", known);
	BARegister(metadata, schema, table, @"AppleRawCurrentCapacity", BAAnalyticsHistoryRemainingCapacityMilliampHours, @"mAh", @"powerlog.battery.raw-capacity.v1", known);
	BARegister(metadata, schema, table, @"AppleRawMaxCapacity", BAAnalyticsHistoryFullChargeCapacityMilliampHours, @"mAh", @"powerlog.battery.raw-capacity.v1", known);
	BARegister(metadata, schema, table, @"DesignCapacity", BAAnalyticsHistoryDesignCapacityMilliampHours, @"mAh", @"powerlog.battery.design-capacity.v1", known);
	BARegister(metadata, schema, table, @"CycleCount", BAAnalyticsHistoryCycleCount, @"count", @"powerlog.battery.cycle-count.v1", known);
	// Inventory explicitly leaves these table/platform encodings conditional.
	BARegister(metadata, schema, table, @"Temperature", BAAnalyticsHistoryTemperatureCelsius, @"unverified", [profile stringByAppendingString:@".temperature.candidate"], NO);
	BARegister(metadata, schema, table, @"AdapterPower", @"candidate.adapter-power", @"unverified", @"powerlog.float32-bits.candidate", NO);
	BARegister(metadata, schema, table, @"SystemPower", @"candidate.system-power", @"unverified", @"powerlog.float32-bits.candidate", NO);
	BARegister(metadata, schema, table, @"RectifierCurrent", BAAnalyticsHistoryInputCurrentMilliamps, @"unverified", @"powerlog.rectifier-current.candidate", NO);
	BARegister(metadata, schema, table, @"RectifierVoltage", BAAnalyticsHistoryInputVoltageMillivolts, @"unverified", @"powerlog.rectifier-voltage.candidate", NO);
	BARegister(metadata, schema, table, @"PowerBudget", BAAnalyticsHistoryPowerBudgetWatts, @"unverified", @"powerlog.power-budget.candidate", NO);
	BARegister(metadata, schema, table, @"PowerTarget", BAAnalyticsHistoryPowerTargetWatts, @"unverified", @"powerlog.power-target.candidate", NO);
	for (NSString *column in schema) {
		if (![column hasPrefix:@"CellVoltage"]) continue;
		NSString *suffix = [column substringFromIndex:@"CellVoltage".length];
		NSScanner *scanner = [NSScanner scannerWithString:suffix];
		NSInteger index = 0;
		if (![scanner scanInteger:&index] || !scanner.isAtEnd || index < 0 || index >= 32) continue;
		NSString *metric = [NSString stringWithFormat:@"cell-voltage.%ld.millivolts", (long)index];
		BARegister(metadata, schema, table, column, metric, @"mV", @"powerlog.battery.cell-millivolts.v1", known);
	}
	if (metadata[BAAnalyticsHistoryVoltageMillivolts] && metadata[BAAnalyticsHistoryCurrentMilliamps])
		metadata[BAAnalyticsHistoryBatteryPowerWatts] = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:table
			sourceColumn:@"InstantAmperage * Voltage / 1000000" unit:@"W" decoderIdentifier:@"powerlog.same-record.signed-battery-power.v1" unitValidated:known];
	return metadata;
}

static BOOL BAValueAllowed(NSString *metric, double value) {
	if (!isfinite(value)) return NO;
	if ([metric isEqual:BAAnalyticsHistorySOCPercent]) return value >= 0 && value <= 100;
	if ([metric isEqual:BAAnalyticsHistoryExternalConnected] || [metric isEqual:BAAnalyticsHistoryIsCharging] || [metric isEqual:BAAnalyticsHistoryFullyCharged]) return value == 0 || value == 1;
	if ([metric isEqual:BAAnalyticsHistoryCurrentMilliamps]) return fabs(value) < 32767;
	if ([metric hasPrefix:@"cell-voltage."]) return value > 0 && value < 65535;
	if ([metric isEqual:BAAnalyticsHistoryVoltageMillivolts]) return value > 0 && value < 65535;
	if ([metric isEqual:BAAnalyticsHistoryRemainingCapacityMilliampHours]) return value >= 0 && value < 65535;
	if ([metric isEqual:BAAnalyticsHistoryFullChargeCapacityMilliampHours] || [metric isEqual:BAAnalyticsHistoryDesignCapacityMilliampHours]) return value > 0 && value < 65535;
	if ([metric isEqual:BAAnalyticsHistoryCycleCount]) return value >= 0 && value < 65535 && floor(value) == value;
	if ([metric isEqual:BAAnalyticsHistoryNotChargingReasonCode]) return value >= 0 && value <= UINT32_MAX && floor(value) == value;
	return NO;
}

static NSArray<BAHistoryRecord *> *BANormalize(NSArray<NSDictionary *> *rows, NSString *table, NSDictionary *metadata,
	NSArray *offsets, NSArray<NSDictionary *> *configurationEpochs, NSString *databaseIdentity, NSDate *start, NSDate *end, NSMutableArray *limitations, BOOL (^cancelled)(void)) {
	NSMutableArray *records = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	BOOL unvalidatedTimestamp = NO;
	NSNumber *previousCycle = nil, *cycleEpoch = nil;
	NSUInteger checked = 0;
	for (NSDictionary *row in rows) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		NSNumber *rawNumber = row[@"timestamp"];
		if (!rawNumber) continue;
		double raw = rawNumber.doubleValue;
		NSNumber *cycle = row[@"CycleCount"];
		if (cycle && previousCycle && cycle.doubleValue < previousCycle.doubleValue) cycleEpoch = rawNumber;
		if (cycle) previousCycle = cycle;
		NSDictionary *offset = BAOffsetForTimestamp(raw, offsets);
		double corrected = raw + [offset[@"system"] doubleValue];
		if (!offset || corrected < 946684800 || corrected >= 4102444800) { unvalidatedTimestamp = YES; continue; }
		NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:corrected];
		if ([timestamp compare:start] == NSOrderedAscending || [timestamp compare:end] == NSOrderedDescending) continue;
		NSMutableDictionary *values = [NSMutableDictionary dictionary];
		[metadata enumerateKeysAndObjectsUsingBlock:^(NSString *metric, BAAnalyticsFieldMetadata *field, BOOL *stop) {
			(void)stop;
			NSNumber *number = row[field.sourceColumn];
			if (field.unitValidated && number && BAValueAllowed(metric, number.doubleValue)) values[metric] = number;
		}];
		NSNumber *current = values[BAAnalyticsHistoryCurrentMilliamps], *voltage = values[BAAnalyticsHistoryVoltageMillivolts];
		if (current && voltage) values[BAAnalyticsHistoryBatteryPowerWatts] = @(current.doubleValue * voltage.doubleValue / 1000000.0);
		NSMutableString *fallbackKey = [NSMutableString string];
		if (!row[@"ID"])
			for (NSString *column in [row.allKeys sortedArrayUsingSelector:@selector(compare:)]) [fallbackKey appendFormat:@"%@=%@;", column, row[column]];
		NSString *key = [NSString stringWithFormat:@"%@/%@/%@/%.9f", databaseIdentity, table, row[@"ID"] ?: BAStableIdentifier(fallbackKey), raw];
		NSString *identifier = BAStableIdentifier(key);
		if ([seen containsObject:identifier]) continue;
		[seen addObject:identifier];
		// Offset changes, gauge resets and battery/configuration changes prohibit interpolation.
		NSMutableString *segment = [NSMutableString stringWithFormat:@"source:%@/offset:%.9f@%.9f", databaseIdentity,
			[offset[@"system"] doubleValue], [offset[@"segmentStart"] doubleValue]];
		for (NSString *column in @[@"ChemID", @"PMUConfiguration", @"DesignCapacity", @"GaugeResetCounter"])
			if (row[column]) [segment appendFormat:@"/%@:%@", column, row[column]];
		if (cycleEpoch) [segment appendFormat:@"/cycle-epoch:%@", cycleEpoch];
		NSString *configurationEpoch = BAConfigurationEpochForTimestamp(raw, configurationEpochs);
		if (configurationEpoch) [segment appendFormat:@"/configuration:%@", configurationEpoch];
		BAHistoryRecord *record = [BAHistoryRecord new];
		record.segment = segment;
		record.observation = [[BAAnalyticsObservation alloc] initWithIdentifier:identifier timestamp:timestamp sourceTimestamp:raw
			timestampValidated:YES values:values fieldMetadata:metadata];
		[records addObject:record];
	}
	if (cancelled()) return nil;
	if (unvalidatedTimestamp) [limitations addObject:[NSString stringWithFormat:@"%@ has rows without a validated preceding TimeOffset/Unix segment; these rows are withheld.", table]];
	[records sortUsingComparator:^NSComparisonResult(BAHistoryRecord *a, BAHistoryRecord *b) {
		NSComparisonResult result = [a.observation.timestamp compare:b.observation.timestamp];
		return result == NSOrderedSame ? [a.observation.identifier compare:b.observation.identifier] : result;
	}];
	for (NSUInteger i = 1; i < records.count; i++) {
		if ((i & 63) == 0 && cancelled()) return nil;
		BAHistoryRecord *a = records[i - 1], *b = records[i];
		if ([a.observation.timestamp isEqual:b.observation.timestamp]) { a.ambiguousTimestamp = YES; b.ambiguousTimestamp = YES; }
	}
	return records;
}

static BAAnalyticsObservedState BAState(BAAnalyticsObservation *observation) {
	NSNumber *connected = observation.values[BAAnalyticsHistoryExternalConnected];
	NSNumber *charging = observation.values[BAAnalyticsHistoryIsCharging];
	NSNumber *full = observation.values[BAAnalyticsHistoryFullyCharged];
	if (!connected) return BAAnalyticsObservedStateUnknown;
	if (charging.boolValue && full.boolValue) return BAAnalyticsObservedStateUnknown;
	if (!connected.boolValue) return charging.boolValue ? BAAnalyticsObservedStateUnknown : BAAnalyticsObservedStateUnplugged;
	if (charging.boolValue) return BAAnalyticsObservedStateCharging;
	if (full.boolValue) return BAAnalyticsObservedStateFull;
	return charging && full ? BAAnalyticsObservedStateConnectedNotCharging : BAAnalyticsObservedStateUnknown;
}

static NSString *BAKind(BAAnalyticsObservation *observation) {
	NSNumber *connected = observation.values[BAAnalyticsHistoryExternalConnected];
	BOOL charging = [observation.values[BAAnalyticsHistoryIsCharging] boolValue], full = [observation.values[BAAnalyticsHistoryFullyCharged] boolValue];
	if (!connected || (!connected.boolValue && charging) || (charging && full)) return nil;
	return connected.boolValue ? @"connected" : @"unplugged";
}

static BOOL BAPairTrusted(BAHistoryRecord *a, BAHistoryRecord *b, NSTimeInterval maxCadence) {
	double delta = [b.observation.timestamp timeIntervalSinceDate:a.observation.timestamp];
	NSNumber *cycleA = a.observation.values[BAAnalyticsHistoryCycleCount], *cycleB = b.observation.values[BAAnalyticsHistoryCycleCount];
	return !a.ambiguousTimestamp && !b.ambiguousTimestamp && delta > 0 && delta <= maxCadence && [a.segment isEqual:b.segment]
		&& !(cycleA && cycleB && cycleB.doubleValue < cycleA.doubleValue);
}

static NSArray<BAAnalyticsHistoryInterval *> *BAIntervals(NSArray<BAHistoryRecord *> *records, NSTimeInterval maxCadence, BOOL (^cancelled)(void)) {
	NSMutableArray *intervals = [NSMutableArray array];
	for (NSUInteger i = 1; i < records.count; i++) @autoreleasepool {
		if ((i & 63) == 1 && cancelled()) return nil;
		BAHistoryRecord *a = records[i - 1], *b = records[i];
		if (!BAPairTrusted(a, b, maxCadence)) continue;
		NSMutableSet *metrics = [NSMutableSet setWithArray:a.observation.values.allKeys];
		[metrics intersectSet:[NSSet setWithArray:b.observation.values.allKeys]];
		BAAnalyticsObservedState stateA = BAState(a.observation), stateB = BAState(b.observation);
		BAAnalyticsObservedState state = stateA == stateB ? stateA : BAAnalyticsObservedStateUnknown;
		if (!BAKind(a.observation) || !BAKind(b.observation)) [metrics removeObject:BAAnalyticsHistoryExternalConnected];
		// Changed state flags are sampled boundaries, not a full interval of either state.
		for (NSString *flag in @[BAAnalyticsHistoryExternalConnected, BAAnalyticsHistoryIsCharging, BAAnalyticsHistoryFullyCharged])
			if (![a.observation.values[flag] isEqual:b.observation.values[flag]]) [metrics removeObject:flag];
		if (!metrics.count) continue;
		[intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:a.observation.timestamp endDate:b.observation.timestamp
			startObservation:a.observation endObservation:b.observation coveredMetricIdentifiers:metrics state:state]];
	}
	return intervals;
}

static NSArray<BAAnalyticsStateTransition *> *BATransitions(NSArray<BAHistoryRecord *> *records, NSTimeInterval maxCadence, BOOL (^cancelled)(void)) {
	NSMutableArray *transitions = [NSMutableArray array];
	for (NSUInteger i = 1; i < records.count; i++) @autoreleasepool {
		if ((i & 63) == 1 && cancelled()) return nil;
		BAHistoryRecord *a = records[i - 1], *b = records[i];
		if (!BAPairTrusted(a, b, maxCadence)) continue;
		BAAnalyticsObservedState previous = BAState(a.observation), next = BAState(b.observation);
		if (previous == BAAnalyticsObservedStateUnknown || next == BAAnalyticsObservedStateUnknown || previous == next) continue;
		NSString *identifier = BAStableIdentifier([NSString stringWithFormat:@"transition/%@/%@", a.observation.identifier, b.observation.identifier]);
		[transitions addObject:[[BAAnalyticsStateTransition alloc] initWithIdentifier:identifier earliestDate:a.observation.timestamp
			latestDate:b.observation.timestamp previousState:previous nextState:next reasonCode:b.observation.values[BAAnalyticsHistoryNotChargingReasonCode]]];
	}
	return transitions;
}

static NSArray<BAAnalyticsHistorySession *> *BASessions(NSArray<BAHistoryRecord *> *records, NSArray *intervals, NSArray *transitions, NSTimeInterval cadence, BOOL (^cancelled)(void)) {
	NSMutableArray *sessions = [NSMutableArray array];
	NSMutableDictionary *intervalByStart = [NSMutableDictionary dictionary], *transitionByID = [NSMutableDictionary dictionary];
	NSUInteger checked = 0;
	for (BAAnalyticsHistoryInterval *interval in intervals) {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		intervalByStart[interval.startObservation.identifier] = interval;
	}
	for (BAAnalyticsStateTransition *transition in transitions) {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		transitionByID[transition.identifier] = transition;
	}
	NSUInteger cursor = 0;
	while (cursor < records.count) @autoreleasepool {
		if (cancelled()) return nil;
		NSString *kind = BAKind(records[cursor].observation);
		if (!kind) { cursor++; continue; }
		NSUInteger first = cursor, last = first;
		while (last + 1 < records.count && BAPairTrusted(records[last], records[last + 1], cadence)
			&& [BAKind(records[last + 1].observation) isEqual:kind]) {
			if ((last & 63) == 0 && cancelled()) return nil;
			last++;
		}
		BAAnalyticsObservation *start = records[first].observation, *end = records[last].observation;
		BOOL knownStart = first > 0 && BAPairTrusted(records[first - 1], records[first], cadence) && BAKind(records[first - 1].observation) != nil;
		BOOL knownEnd = last + 1 < records.count && BAPairTrusted(records[last], records[last + 1], cadence) && BAKind(records[last + 1].observation) != nil;
		NSMutableArray *observations = [NSMutableArray array], *ownedIntervals = [NSMutableArray array], *ownedTransitions = [NSMutableArray array];
		for (NSUInteger i = first; i <= last; i++) {
			if ((i & 63) == 0 && cancelled()) return nil;
			[observations addObject:records[i].observation];
			BAAnalyticsHistoryInterval *interval = intervalByStart[records[i].observation.identifier];
			if (i < last && interval) [ownedIntervals addObject:interval];
		}
		for (NSUInteger i = first ? first - 1 : first; i <= last && i + 1 < records.count; i++) @autoreleasepool {
			if ((i & 63) == 0 && cancelled()) return nil;
			NSString *transitionID = BAStableIdentifier([NSString stringWithFormat:@"transition/%@/%@", records[i].observation.identifier, records[i + 1].observation.identifier]);
			BAAnalyticsStateTransition *transition = transitionByID[transitionID];
			if (transition) [ownedTransitions addObject:transition];
		}
		NSString *identifier = BAStableIdentifier([NSString stringWithFormat:@"session/%@/%@", kind, start.identifier]);
		[sessions addObject:[[BAAnalyticsHistorySession alloc] initWithIdentifier:identifier kind:kind startDate:start.timestamp endDate:end.timestamp
			startBoundaryKnown:knownStart endBoundaryKnown:knownEnd observations:observations intervals:ownedIntervals gaps:@[] transitions:ownedTransitions]];
		cursor = last + 1;
	}
	return sessions;
}

// Battery is the canonical synchronized source. BatteryUI fills only uncovered
// timeline spans. A clipped UI fragment keeps the original pair for interpolation.
static NSArray *BACanonicalIntervals(NSArray<BAAnalyticsHistoryInterval *> *battery, NSArray<BAAnalyticsHistoryInterval *> *ui, BOOL (^cancelled)(void)) {
	NSMutableArray *canonical = [battery mutableCopy];
	NSUInteger cursor = 0, checked = 0;
	for (BAAnalyticsHistoryInterval *interval in ui) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		NSDate *start = interval.startDate;
		while (cursor < battery.count && [battery[cursor].endDate compare:start] != NSOrderedDescending) {
			if ((cursor & 63) == 0 && cancelled()) return nil;
			cursor++;
		}
		NSUInteger index = cursor;
		while (index < battery.count && [battery[index].startDate compare:interval.endDate] == NSOrderedAscending) {
			if ((index & 63) == 0 && cancelled()) return nil;
			BAAnalyticsHistoryInterval *preferred = battery[index];
			NSDate *end = [preferred.startDate earlierDate:interval.endDate];
			if ([end compare:start] == NSOrderedDescending)
				[canonical addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:start endDate:end startObservation:interval.startObservation endObservation:interval.endObservation coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:BAAnalyticsObservedStateUnknown]];
			start = [start laterDate:preferred.endDate];
			index++;
		}
		if ([interval.endDate compare:start] == NSOrderedDescending)
			[canonical addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:start endDate:interval.endDate startObservation:interval.startObservation endObservation:interval.endObservation coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:BAAnalyticsObservedStateUnknown]];
	}
	if (cancelled()) return nil;
	[canonical sortUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) { return [a.startDate compare:b.startDate]; }];
	return canonical;
}

// Union is calculated independently for each field, or jointly for a required set.
static NSArray<NSArray<NSDate *> *> *BASpans(NSArray<BAAnalyticsHistoryInterval *> *intervals, NSSet *metrics, NSDate *start, NSDate *end, BOOL (^cancelled)(void)) {
	NSMutableArray *spans = [NSMutableArray array];
	NSUInteger checked = 0;
	for (BAAnalyticsHistoryInterval *interval in intervals) {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		if (!metrics.count || ![metrics isSubsetOfSet:interval.coveredMetricIdentifiers]) continue;
		NSDate *a = [interval.startDate laterDate:start], *b = [interval.endDate earlierDate:end];
		if ([b compare:a] == NSOrderedDescending) [spans addObject:@[a, b]];
	}
	if (cancelled()) return nil;
	[spans sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
	NSMutableArray *unionSpans = [NSMutableArray array];
	for (NSArray *span in spans) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		NSArray *previous = unionSpans.lastObject;
		if (previous && [span[0] compare:previous[1]] != NSOrderedDescending)
			unionSpans[unionSpans.count - 1] = @[previous[0], [previous[1] laterDate:span[1]]];
		else [unionSpans addObject:span];
	}
	return unionSpans;
}

static BAAnalyticsHistoryWindow *BAWindow(NSDate *start, NSDate *end, NSArray<BAAnalyticsObservation *> *observations,
	NSArray<BAAnalyticsHistoryInterval *> *intervals, NSSet *required, NSArray<BAAnalyticsHistoryGap *> *discontinuities, BOOL (^cancelled)(void)) {
	NSMutableArray *points = [NSMutableArray array], *clipped = [NSMutableArray array], *gaps = [NSMutableArray array];
	NSUInteger checked = 0;
	for (BAAnalyticsObservation *observation in observations) {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		if ([observation.timestamp compare:start] != NSOrderedAscending && [observation.timestamp compare:end] != NSOrderedDescending) [points addObject:observation];
	}
	for (BAAnalyticsHistoryInterval *interval in intervals) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		NSDate *a = [interval.startDate laterDate:start], *b = [interval.endDate earlierDate:end];
		if ([b compare:a] != NSOrderedDescending) continue;
		[clipped addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:a endDate:b startObservation:interval.startObservation
			endObservation:interval.endObservation coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:interval.state]];
	}
	NSDate *cursor = start;
	for (NSArray *span in BASpans(clipped, required, start, end, cancelled)) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		if ([span[0] compare:cursor] == NSOrderedDescending) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:cursor endDate:span[0] reason:@"Required fields unavailable or sampling gap"]];
		cursor = span[1];
	}
	if ([end compare:cursor] == NSOrderedDescending) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:cursor endDate:end reason:required.count ? @"Required fields unavailable or sampling gap" : @"Point observations do not establish continuous coverage"]];
	for (BAAnalyticsHistoryGap *gap in discontinuities) @autoreleasepool {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		NSDate *a = [gap.startDate laterDate:start], *b = [gap.endDate earlierDate:end];
		if ([b compare:a] == NSOrderedDescending) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:a endDate:b reason:gap.reason]];
	}
	if (cancelled()) return nil;
	// The immutable window verifies coverage from its clipped trusted pairs.
	// Only gap construction above needs a union here; duplicating every metric's
	// coverage pass would be discarded by the constructor.
	return [[BAAnalyticsHistoryWindow alloc] initWithStartDate:start endDate:end observations:points intervals:clipped gaps:gaps
		coverageMetricIdentifiers:required coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
}

static NSArray *BAFilterSessions(NSArray<BAAnalyticsHistorySession *> *sessions, NSString *kind, NSDate *start, NSDate *end, BOOL (^cancelled)(void)) {
	NSMutableArray *filtered = [NSMutableArray array];
	NSUInteger checked = 0;
	for (BAAnalyticsHistorySession *session in sessions) {
		if ((checked++ & 63) == 0 && cancelled()) return nil;
		if ([session.kind isEqual:kind] && [session.endDate compare:start] != NSOrderedAscending && [session.startDate compare:end] != NSOrderedDescending) [filtered addObject:session];
	}
	return filtered;
}


static NSUInteger BATableRecordLimit(NSString *table) {
    if ([table isEqual:BABatteryTable]) return 40000;
    if ([table isEqual:BAConfigTable]) return 2048;
    return 8192;
}

BAAnalyticsReport *BAAnalyticsReadHistoryReport(NSURL *databaseURL, NSDate *endDate, uint64_t sequenceNumber, BOOL (^cancelled)(void)) {
    if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
    NSURL *url = databaseURL ?: BAAnalyticsResolveHistoryURL(cancelled);
    return BAAnalyticsReadHistoryReportFromSources(url ? @[url] : @[], endDate, sequenceNumber, cancelled);
}

BAAnalyticsReport *BAAnalyticsReadHistoryReportFromSources(NSArray<NSURL *> *databaseURLs, NSDate *endDate, uint64_t sequenceNumber, BOOL (^cancelled)(void)) {
    BOOL (^sourceCancellation)(void) = cancelled;
    __block BOOL cancellationObserved = NO;
    cancelled = ^BOOL {
        if (!cancellationObserved) cancellationObserved = sourceCancellation();
        return cancellationObserved;
    };
    if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
    NSMutableArray *limitations = [NSMutableArray array];
    NSMutableDictionary *allMetadata = [NSMutableDictionary dictionary], *tableRecords = [NSMutableDictionary dictionary];
    NSMutableArray *allObservations = [NSMutableArray array], *discontinuities = [NSMutableArray array];
    NSString *profile = @"powerlog.unknown";
    NSError *error = nil, *firstSourceError = nil;
    BOOL openedCompatibleSource = NO, selectedProfile = NO, acquisitionPartial = NO;
    NSTimeInterval cadence = 90;
    NSTimeInterval totalDeadline = NSProcessInfo.processInfo.systemUptime + 12;
    NSUInteger sourceCount = [databaseURLs isKindOfClass:NSArray.class] ? MIN(databaseURLs.count, (NSUInteger)9) : 0;
    if ([databaseURLs isKindOfClass:NSArray.class] && databaseURLs.count > sourceCount) {
        [limitations addObject:@"Older databases beyond the bounded source count are not included."];
        acquisitionPartial = YES;
    }
    NSMutableSet *seenSources = [NSMutableSet set];
    for (NSUInteger sourceIndex = 0; sourceIndex < sourceCount; sourceIndex++) @autoreleasepool {
        if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
        if (NSProcessInfo.processInfo.systemUptime >= totalDeadline) {
            [limitations addObject:@"History source acquisition reached its overall time budget; older coverage is unavailable."];
            acquisitionPartial = YES; break;
        }
        NSURL *url = databaseURLs[sourceIndex];
        struct stat fileInfo;
        if (![url isKindOfClass:NSURL.class] || !url.isFileURL || stat(url.path.fileSystemRepresentation, &fileInfo) || !S_ISREG(fileInfo.st_mode)) {
            if (!firstSourceError) firstSourceError = [NSError errorWithDomain:@"BAAnalyticsHistory" code:SQLITE_CANTOPEN
                userInfo:@{NSLocalizedDescriptionKey: @"Powerlog database is unavailable."}];
            [limitations addObject:@"A selected Powerlog source is unavailable; its historical coverage is missing."];
            acquisitionPartial = YES; continue;
        }
        // Extracted archives may carry their original opaque file identity in
        // a URL fragment. SQLite uses only the decoded filesystem path.
        NSString *archiveIdentity = [url.fragment hasPrefix:@"ba-powerlog-source:"] ? [url.fragment substringFromIndex:@"ba-powerlog-source:".length] : nil;
        if (archiveIdentity && (archiveIdentity.length != 16 || [archiveIdentity rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location != NSNotFound)) {
            [limitations addObject:@"An extracted Powerlog source has an invalid identity and is excluded."];
            acquisitionPartial = YES; continue;
        }
        NSString *databaseIdentity = archiveIdentity ?:
            [NSString stringWithFormat:@"%llu:%llu:%lld", (unsigned long long)fileInfo.st_dev,
                (unsigned long long)fileInfo.st_ino, (long long)fileInfo.st_birthtimespec.tv_sec];
        if (!databaseIdentity.length || databaseIdentity.length > 256 || [seenSources containsObject:databaseIdentity]) continue;
        [seenSources addObject:databaseIdentity];
        sqlite3 *db = NULL;
        // The callback context must outlive SQLite's borrowed pointer.
        __attribute__((objc_precise_lifetime)) BAHistoryReadContext *context = [BAHistoryReadContext new];
        context.cancelled = cancelled;
        context.deadline = MIN(totalDeadline, NSProcessInfo.processInfo.systemUptime + 4);
        @try {
            int result = sqlite3_open_v2(url.path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
            if (result == SQLITE_OK) {
                sqlite3_busy_timeout(db, 250);
                sqlite3_progress_handler(db, 1000, BAReadProgress, (__bridge void *)context);
                result = sqlite3_exec(db, "PRAGMA query_only=ON; BEGIN DEFERRED", NULL, NULL, NULL);
            }
            if (result != SQLITE_OK) {
                if (!firstSourceError) firstSourceError = [NSError errorWithDomain:@"BAAnalyticsHistory" code:result
                    userInfo:@{NSLocalizedDescriptionKey: @"Powerlog read-only connection failed."}];
                [limitations addObject:@"A selected Powerlog source could not be read; other sources retain their evidence."];
                acquisitionPartial = YES; continue;
            }
            NSMutableDictionary *schemas = [NSMutableDictionary dictionary];
            for (NSString *table in @[BABatteryTable, BABatteryUITable, BAConfigTable, BAOffsetTable, BAChargingTable, BAThermalTable]) {
                if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                schemas[table] = BAColumns(db, table);
            }
            NSSet *batterySchema = schemas[BABatteryTable];
            NSString *sourceProfile = @"powerlog.unknown";
            NSTimeInterval sourceCadence = 90;
            if ([batterySchema containsObject:@"CellVoltage0"] && ([schemas[BAThermalTable] count] || ![schemas[BAChargingTable] count])) {
                sourceProfile = @"powerlog.mac-battery.v1"; sourceCadence = 180;
            } else if ([schemas[BAChargingTable] count]) sourceProfile = @"powerlog.ios-battery.v1";
            if (![batterySchema count] && ![schemas[BABatteryUITable] count] && ![schemas[BAConfigTable] count]) {
                [limitations addObject:@"A selected Powerlog source has no recognized battery tables; its coverage is unavailable."];
                acquisitionPartial = YES; continue;
            }
            if (selectedProfile && ![sourceProfile isEqual:profile]) {
                [limitations addObject:@"An older Powerlog source has an incompatible platform schema and is excluded."];
                acquisitionPartial = YES; continue;
            }
            if (!selectedProfile) { selectedProfile = YES; profile = sourceProfile; cadence = sourceCadence; }
            openedCompatibleSource = YES;
            NSArray *offsets = BAOffsets(db, schemas[BAOffsetTable], endDate.timeIntervalSince1970, limitations, cancelled);
            if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
            if (!offsets.count) {
                [limitations addObject:@"No validated TimeOffset.system segments; wall-clock observations are unavailable."];
                acquisitionPartial = YES;
            }
            NSArray *configRows = BARows(db, BAConfigTable, schemas[BAConfigTable],
                @[@"AppleRawMaxCapacity", @"CycleCount", @"BatterySerialChanged", @"AlgoChemID", @"calibrationFlags"],
                endDate.timeIntervalSince1970 - 31 * BADay, endDate.timeIntervalSince1970 + BADay, 1024, limitations, cancelled);
            if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
            NSMutableArray *boundaries = [NSMutableArray array];
            NSDictionary *previousConfig = nil;
            for (NSDictionary *row in configRows) {
                if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                BOOL changed = [row[@"BatterySerialChanged"] boolValue] && ![previousConfig[@"BatterySerialChanged"] boolValue];
                for (NSString *key in @[@"AlgoChemID", @"calibrationFlags"])
                    if (previousConfig[key] && row[key] && ![previousConfig[key] isEqual:row[key]]) changed = YES;
                if (previousConfig[@"CycleCount"] && row[@"CycleCount"] && [row[@"CycleCount"] doubleValue] < [previousConfig[@"CycleCount"] doubleValue]) changed = YES;
                if (changed) [boundaries addObject:row];
                previousConfig = row;
            }
            NSArray *configurationEpochs = BAConfigurationEpochs(boundaries, cancelled);
            for (NSString *table in @[BABatteryTable, BABatteryUITable, BAConfigTable, BAChargingTable]) @autoreleasepool {
                if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                if (NSProcessInfo.processInfo.systemUptime >= totalDeadline) {
                    [limitations addObject:@"History source acquisition reached its overall time budget; older coverage is unavailable."];
                    acquisitionPartial = YES; break;
                }
                NSDictionary *metadata = BAFieldMap(table, schemas[table], profile);
                for (NSString *metric in metadata) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", table, metric];
                    if (!allMetadata[key]) allMetadata[key] = metadata[metric];
                    if (!allMetadata[metric]) allMetadata[metric] = metadata[metric];
                }
                NSMutableArray *selected = tableRecords[table];
                if (!selected) { selected = [NSMutableArray array]; tableRecords[table] = selected; }
                NSUInteger cap = BATableRecordLimit(table);
                if (selected.count >= cap) {
                    acquisitionPartial = YES;
                    [limitations addObject:[NSString stringWithFormat:@"%@ reached its total bounded record count; older coverage is unavailable.", table]];
                    continue;
                }
                NSDate *cutoff = ((BAHistoryRecord *)selected.firstObject).observation.timestamp;
                NSMutableArray *requested = [NSMutableArray arrayWithObjects:@"ChemID", @"PMUConfiguration", @"DesignCapacity", @"GaugeResetCounter", nil];
                for (BAAnalyticsFieldMetadata *field in metadata.allValues) [requested addObject:field.sourceColumn];
                double duration = [table isEqual:BAConfigTable] ? 30 * BADay : [table isEqual:BAChargingTable] ? 6 * 3600 : 7 * BADay;
                double queryEnd = endDate.timeIntervalSince1970 + BADay;
                if (cutoff && offsets.count) {
                    double minimumOffset = INFINITY;
                    for (NSDictionary *offset in offsets) minimumOffset = MIN(minimumOffset, [offset[@"system"] doubleValue]);
                    if (isfinite(minimumOffset)) queryEnd = MIN(queryEnd, cutoff.timeIntervalSince1970 - minimumOffset);
                }
                NSArray *rows = [table isEqual:BAConfigTable] ? configRows : BARows(db, table, schemas[table], requested,
                    endDate.timeIntervalSince1970 - duration - BADay, queryEnd, cap - selected.count, limitations, cancelled);
                NSArray *normalized = BANormalize(rows, table, metadata, offsets, configurationEpochs, databaseIdentity,
                    [endDate dateByAddingTimeInterval:-duration], endDate, limitations, cancelled);
                if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                NSMutableArray *older = [NSMutableArray array];
                NSUInteger checked = 0;
                for (BAHistoryRecord *record in normalized) {
                    if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                    if (cutoff && [record.observation.timestamp compare:cutoff] != NSOrderedAscending) continue;
                    [older addObject:record];
                }
                // BANormalize orders ascending. If config rows exceed the total
                // budget, retain the newest eligible old records, not an arbitrary prefix.
                NSUInteger remaining = cap - selected.count;
                if (older.count > remaining) {
                    [older removeObjectsInRange:NSMakeRange(0, older.count - remaining)];
                    acquisitionPartial = YES;
                }
                [selected insertObjects:older atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, older.count)]];
            }
            sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        } @finally {
            if (db) { sqlite3_progress_handler(db, 0, NULL, NULL); sqlite3_close(db); }
        }
    }
    if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
    if (!openedCompatibleSource) error = firstSourceError ?: [NSError errorWithDomain:@"BAAnalyticsHistory" code:SQLITE_CANTOPEN
        userInfo:@{NSLocalizedDescriptionKey: @"Powerlog database is unavailable."}];
    if (error) [limitations addObject:error.localizedDescription];
    for (NSString *table in @[BABatteryTable, BABatteryUITable, BAConfigTable, BAChargingTable]) @autoreleasepool {
        NSArray *records = tableRecords[table] ?: @[];
        NSUInteger checked = 0;
        for (BAHistoryRecord *record in records) {
            if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
            [allObservations addObject:record.observation];
        }
        // Config/input values remain sparse points. Across a file boundary,
        // matching sampling cadence is insufficient to establish continuity.
        if ([table isEqual:BABatteryTable] || [table isEqual:BABatteryUITable]) {
            NSTimeInterval maxCadence = [table isEqual:BABatteryUITable] ? 900 : cadence;
            for (NSUInteger i = 1; i < records.count; i++) @autoreleasepool {
                if ((i & 63) == 1 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
                BAHistoryRecord *a = records[i - 1], *b = records[i];
                if (!BAPairTrusted(a, b, maxCadence) && [b.observation.timestamp compare:a.observation.timestamp] == NSOrderedDescending)
                    [discontinuities addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:a.observation.timestamp endDate:b.observation.timestamp reason:
                        [a.segment isEqual:b.segment] ? @"Source sampling gap or gauge reset" : @"Clock or source/battery/configuration discontinuity"]];
            }
        }
    }
	[limitations addObject:@"Powerlog temperature, wireless input/budgets and float-bit adapter/system power remain unverified and unavailable. Different tables retain independent records."];
	if ([profile isEqual:@"powerlog.unknown"]) [limitations addObject:@"Unrecognized platform schema; physical-unit fields are withheld."];
	[allObservations sortUsingComparator:^NSComparisonResult(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
		NSComparisonResult result = [a.timestamp compare:b.timestamp];
		return result == NSOrderedSame ? [a.identifier compare:b.identifier] : result;
	}];
	if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
	NSArray *batteryRecords = tableRecords[BABatteryTable] ?: @[];
	NSArray *batteryIntervals = BAIntervals(batteryRecords, cadence, cancelled), *transitions = BATransitions(batteryRecords, cadence, cancelled);
	NSArray *canonicalIntervals = BACanonicalIntervals(batteryIntervals, BAIntervals(tableRecords[BABatteryUITable] ?: @[], 900, cancelled), cancelled);
	NSArray *sessions = BASessions(batteryRecords, batteryIntervals, transitions, cadence, cancelled);
	NSMutableSet *compatibleStarts = [NSMutableSet set];
	NSString *currentSegment = [batteryRecords.lastObject segment];
	NSUInteger checked = 0;
	for (BAHistoryRecord *record in batteryRecords) {
		if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
		if ([record.segment isEqual:currentSegment]) [compatibleStarts addObject:record.observation.identifier];
	}
	NSMutableDictionary *families = [NSMutableDictionary dictionary];
	for (NSString *family in @[BAAnalyticsFamilyLive, BAAnalyticsFamilyCapacity, BAAnalyticsFamilyCells, BAAnalyticsFamilySession, BAAnalyticsFamilyDischarge,
		BAAnalyticsFamilyEvents, BAAnalyticsFamilyPath, BAAnalyticsFamilyDwell, BAAnalyticsFamilyCompare, BAAnalyticsFamilyRhythm]) @autoreleasepool {
		if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
		NSTimeInterval duration = [family isEqual:BAAnalyticsFamilyCapacity] ? 30 * BADay :
			[family isEqual:BAAnalyticsFamilyRhythm] || [family isEqual:BAAnalyticsFamilyCompare] ? 7 * BADay :
			[family isEqual:BAAnalyticsFamilyLive] ? 300 : [family isEqual:BAAnalyticsFamilyCells] || [family isEqual:BAAnalyticsFamilyPath] ? 6 * 3600 : 2 * BADay;
		NSDate *start = [endDate dateByAddingTimeInterval:-duration];
		BOOL capacity = [family isEqual:BAAnalyticsFamilyCapacity], cells = [family isEqual:BAAnalyticsFamilyCells], path = [family isEqual:BAAnalyticsFamilyPath];
		NSSet *required = [NSSet setWithObject:BAAnalyticsHistorySOCPercent];
		if (capacity) required = [NSSet set];
		else if (cells) required = [NSSet setWithObjects:BAAnalyticsHistoryCellVoltage0Millivolts, BAAnalyticsHistoryCellVoltage1Millivolts, nil];
		else if (path) required = [NSSet setWithObject:BAAnalyticsHistoryBatteryPowerWatts];
		else if ([family isEqual:BAAnalyticsFamilyEvents]) required = [NSSet setWithObject:BAAnalyticsHistoryExternalConnected];
		else if ([family isEqual:BAAnalyticsFamilySession] || [family isEqual:BAAnalyticsFamilyDischarge] || [family isEqual:BAAnalyticsFamilyCompare] || [family isEqual:BAAnalyticsFamilyRhythm])
			required = [NSSet setWithObjects:BAAnalyticsHistorySOCPercent, BAAnalyticsHistoryExternalConnected, nil];
		NSArray *familyIntervals = capacity ? @[] : ([family isEqual:BAAnalyticsFamilyDwell] || [family isEqual:BAAnalyticsFamilyLive]) ? canonicalIntervals : batteryIntervals;
		BAAnalyticsHistoryWindow *window = BAWindow(start, endDate, allObservations, familyIntervals, required, discontinuities, cancelled);
		if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
		NSMutableDictionary *payload = [NSMutableDictionary dictionary];
		BOOL hasValues = NO;
		for (BAAnalyticsObservation *observation in window.observations) {
			if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
			BOOL relevant = capacity ? observation.values[BAAnalyticsHistoryFullChargeCapacityMilliampHours] != nil :
				cells ? [[observation.values.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", @"cell-voltage."]] count] > 0 :
				path ? observation.values[BAAnalyticsHistoryBatteryPowerWatts] != nil : observation.values[BAAnalyticsHistorySOCPercent] != nil;
			if (relevant) {
				hasValues = YES;
				if (capacity || cells || path || [family isEqual:BAAnalyticsFamilyLive]) payload[BAAnalyticsPayloadLatestObservation] = observation;
			}
		}
		if ([family isEqual:BAAnalyticsFamilySession] || [family isEqual:BAAnalyticsFamilyDischarge] || [family isEqual:BAAnalyticsFamilyCompare]) {
			NSArray *ownedSessions = BAFilterSessions(sessions, [family isEqual:BAAnalyticsFamilyDischarge] ? @"unplugged" : @"connected", start, endDate, cancelled);
			if ([family isEqual:BAAnalyticsFamilyCompare]) {
				NSMutableArray *compatible = [NSMutableArray array];
				for (BAAnalyticsHistorySession *session in ownedSessions) {
					if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
					if ([compatibleStarts containsObject:session.observations.firstObject.identifier]) [compatible addObject:session];
				}
				ownedSessions = compatible;
			}
			payload[BAAnalyticsPayloadSessions] = ownedSessions;
			if (ownedSessions.count && ![family isEqual:BAAnalyticsFamilyCompare]) payload[BAAnalyticsPayloadSelectedSession] = ownedSessions.lastObject;
			hasValues = ownedSessions.count > 0;
		}
		if ([family isEqual:BAAnalyticsFamilyEvents]) {
			NSMutableArray *ownedTransitions = [NSMutableArray array];
			for (BAAnalyticsStateTransition *transition in transitions) {
				if ((checked++ & 63) == 0 && cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
				if ([transition.latestDate compare:start] != NSOrderedAscending) [ownedTransitions addObject:transition];
			}
			payload[BAAnalyticsPayloadTransitions] = ownedTransitions;
			hasValues = [window.coverageSecondsByMetric[BAAnalyticsHistoryExternalConnected] doubleValue] > 0;
		}
		BAAnalyticsReportAvailability availability = !hasValues ? BAAnalyticsReportAvailabilityUnavailable :
			(window.missingDuration < 1 && !error && !acquisitionPartial ? BAAnalyticsReportAvailabilityReady : BAAnalyticsReportAvailabilityPartial);
		NSMutableArray *familyLimitations = [limitations mutableCopy];
		if (capacity) [familyLimitations addObject:@"FCC/configuration records are sparse point observations, not continuous 30-day coverage."];
		if ([family isEqual:BAAnalyticsFamilyLive]) [familyLimitations addObject:@"This is a historical Powerlog window, not evidence of the current device state; use the live metric snapshot and its age."];
		if ([family isEqual:BAAnalyticsFamilyRhythm]) [familyLimitations addObject:@"BatteryUI.IsCharging does not prove unplugged state; rhythm uses only validated Battery connection intervals."];
		if ([family isEqual:BAAnalyticsFamilyCompare]) [familyLimitations addObject:@"Comparison candidates are limited to the latest recognized clock/battery/configuration segment; other segments are excluded. Schema/configuration compatibility cannot prove physical battery identity. Normal FCC fluctuations do not establish replacement."];
		if ([family isEqual:BAAnalyticsFamilySession] || [family isEqual:BAAnalyticsFamilyDischarge] || [family isEqual:BAAnalyticsFamilyCompare])
			[familyLimitations addObject:@"Sampled process boundaries are approximate. A clock/source/configuration gap starts a new partial session with unknown boundary."];
		families[family] = [[BAAnalyticsFamilyReport alloc] initWithFamily:family availability:availability window:window payload:payload limitations:familyLimitations];
	}
	if (cancelled()) return BACancelledHistoryReport(endDate, sequenceNumber);
	return [[BAAnalyticsReport alloc] initWithSequenceNumber:sequenceNumber generatedAt:endDate sourceProfileIdentifier:profile
		fieldMetadata:allMetadata familyReports:families error:error];
}
