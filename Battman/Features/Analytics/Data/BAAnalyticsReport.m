#import "BAAnalyticsReport.h"
#import <math.h>
#include <stdlib.h>

static BOOL BAReportValidDate(id date) {
	return [date isKindOfClass:[NSDate class]] && isfinite([date timeIntervalSince1970]);
}

static BOOL BAReportValidRange(NSDate *start, NSDate *end) {
	return BAReportValidDate(start) && BAReportValidDate(end) &&
		isfinite([end timeIntervalSinceDate:start]) && [end compare:start] != NSOrderedAscending;
}

typedef struct {
	NSTimeInterval start;
	NSTimeInterval end;
} BAHistoryGapRange;

@interface BAHistoryGapIndex : NSObject
@property (nonatomic, copy) NSData *allRanges;
@property (nonatomic, copy) NSData *sourceRanges;
@end
@implementation BAHistoryGapIndex
@end

static int BAHistoryCompareGapRanges(const void *left, const void *right) {
	const BAHistoryGapRange *a = left, *b = right;
	if (a->start != b->start) return a->start < b->start ? -1 : 1;
	return a->end == b->end ? 0 : a->end < b->end ? -1 : 1;
}

static NSData *BAHistoryMergedGapRanges(NSMutableData *data) {
	NSUInteger count = data.length / sizeof(BAHistoryGapRange), mergedCount = 0;
	BAHistoryGapRange *ranges = data.mutableBytes;
	if (count > 1) qsort(ranges, count, sizeof(BAHistoryGapRange), BAHistoryCompareGapRanges);
	for (NSUInteger i = 0; i < count; i++) {
		BAHistoryGapRange range = ranges[i];
		if (mergedCount && range.start <= ranges[mergedCount - 1].end)
			ranges[mergedCount - 1].end = MAX(ranges[mergedCount - 1].end, range.end);
		else ranges[mergedCount++] = range;
	}
	[data setLength:mergedCount * sizeof(BAHistoryGapRange)];
	return [data copy];
}

static BAHistoryGapIndex *BAHistoryBuildGapIndex(NSArray<BAAnalyticsHistoryGap *> *gaps) {
	NSMutableData *all = [NSMutableData data], *source = [NSMutableData data];
	for (BAAnalyticsHistoryGap *gap in gaps) {
		if (![gap isKindOfClass:BAAnalyticsHistoryGap.class] || !BAReportValidRange(gap.startDate, gap.endDate)) continue;
		BAHistoryGapRange range = { gap.startDate.timeIntervalSince1970, gap.endDate.timeIntervalSince1970 };
		[all appendBytes:&range length:sizeof(range)];
		if (![gap.reason isEqualToString:@"Required fields unavailable or sampling gap"])
			[source appendBytes:&range length:sizeof(range)];
	}
	BAHistoryGapIndex *index = [BAHistoryGapIndex new];
	BOOL sameRanges = all.length == source.length;
	index.allRanges = BAHistoryMergedGapRanges(all);
	index.sourceRanges = sameRanges ? index.allRanges : BAHistoryMergedGapRanges(source);
	return index;
}

static BAHistoryGapIndex *BAHistoryIndexForGaps(NSArray<BAAnalyticsHistoryGap *> *gaps) {
	// Never retain the source array from its value: weak identity keys let an
	// obsolete report and its index disappear together. Build outside the lock.
	if ([gaps isKindOfClass:NSMutableArray.class]) return BAHistoryBuildGapIndex(gaps);
	static NSMapTable<NSArray *, BAHistoryGapIndex *> *cache;
	static NSLock *lock;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
			valueOptions:NSPointerFunctionsStrongMemory capacity:16];
		lock = [NSLock new];
	});
	[lock lock];
	BAHistoryGapIndex *index = [cache objectForKey:gaps];
	[lock unlock];
	if (index) return index;
	BAHistoryGapIndex *built = BAHistoryBuildGapIndex(gaps);
	[lock lock];
	index = [cache objectForKey:gaps];
	if (!index) { index = built; [cache setObject:index forKey:gaps]; }
	[lock unlock];
	return index;
}

BOOL BAAnalyticsHistoryHasGap(NSArray<BAAnalyticsHistoryGap *> *gaps, NSDate *start, NSDate *end, BOOL excludingCoverageGaps) {
	if (![gaps isKindOfClass:NSArray.class] || !gaps.count || !BAReportValidRange(start, end) || [end compare:start] != NSOrderedDescending)
		return NO;
	BAHistoryGapIndex *index = BAHistoryIndexForGaps(gaps);
	NSData *data = excludingCoverageGaps ? index.sourceRanges : index.allRanges;
	const BAHistoryGapRange *ranges = data.bytes;
	NSUInteger lo = 0, hi = data.length / sizeof(BAHistoryGapRange);
	NSTimeInterval a = start.timeIntervalSince1970, b = end.timeIntervalSince1970;
	// Nonoverlapping merged ranges have increasing ends. Find the first one
	// whose end is strictly later than the query's start.
	while (lo < hi) {
		NSUInteger mid = lo + (hi - lo) / 2;
		if (ranges[mid].end <= a) lo = mid + 1; else hi = mid;
	}
	return lo < data.length / sizeof(BAHistoryGapRange) && ranges[lo].start < b;
}

static NSSet<NSString *> *BAReportMetricSet(id input) {
	NSMutableSet *result = [NSMutableSet set];
	if ([input isKindOfClass:[NSSet class]]) {
		for (id metric in input) {
			if ([metric isKindOfClass:[NSString class]] && [metric length])
				[result addObject:[metric copy]];
		}
	}
	return [result copy];
}

// All model classes return themselves when copied; containers require a deep freeze.
// The depth bound also keeps malformed, cyclic extension payloads bounded.
static id BAReportImmutableValue(id value, NSUInteger depth) {
	if (!value || depth > 16)
		return nil;
	if ([value isKindOfClass:[NSNumber class]])
		return isfinite([value doubleValue]) ? [value copy] : nil;
	if ([value isKindOfClass:[NSDate class]])
		return BAReportValidDate(value) ? [value copy] : nil;
	if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSData class]] ||
		[value isKindOfClass:[NSURL class]] || [value isKindOfClass:[BAAnalyticsObservation class]] ||
		[value isKindOfClass:[BAAnalyticsHistorySession class]] || [value isKindOfClass:[BAAnalyticsHistoryInterval class]] ||
		[value isKindOfClass:[BAAnalyticsHistoryGap class]] || [value isKindOfClass:[BAAnalyticsStateTransition class]] ||
		[value isKindOfClass:[BAAnalyticsFieldMetadata class]])
		return [value copy];
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *result = [NSMutableDictionary dictionary];
		[value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
			(void)stop;
			if (![key isKindOfClass:[NSString class]])
				return;
			id immutable = BAReportImmutableValue(object, depth + 1);
			if (immutable)
				result[[key copy]] = immutable;
		}];
		return [result copy];
	}
	if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSSet class]]) {
		NSMutableArray *result = [NSMutableArray array];
		for (id object in value) {
			id immutable = BAReportImmutableValue(object, depth + 1);
			if (immutable)
				[result addObject:immutable];
		}
		return [value isKindOfClass:[NSSet class]] ? [NSSet setWithArray:result] : [result copy];
	}
	if ([value isKindOfClass:[NSError class]]) {
		NSError *error = value;
		NSDictionary *info = BAReportImmutableValue(error.userInfo, depth + 1);
		return [NSError errorWithDomain:[error.domain copy] code:error.code userInfo:info];
	}
	return nil;
}

static NSArray *BAReportTypedArray(id objects, Class objectClass) {
	NSMutableArray *result = [NSMutableArray array];
	if ([objects isKindOfClass:[NSArray class]]) {
		for (id object in objects) {
			if ([object isKindOfClass:objectClass])
				[result addObject:[object copy]];
		}
	}
	return [result copy];
}

// Endpoints are relative to the window start, so subtraction remains bounded.
static NSTimeInterval BAReportUnionDuration(NSArray<BAAnalyticsHistoryInterval *> *intervals,
										 NSSet<NSString *> *metrics, NSDate *origin) {
	if (!metrics.count)
		return 0;
	NSMutableArray<NSArray<NSNumber *> *> *ranges = [NSMutableArray array];
	for (BAAnalyticsHistoryInterval *interval in intervals) {
		if ([metrics isSubsetOfSet:interval.coveredMetricIdentifiers] && interval.duration > 0)
			[ranges addObject:@[@([interval.startDate timeIntervalSinceDate:origin]),
				@([interval.endDate timeIntervalSinceDate:origin])]];
	}
	[ranges sortUsingComparator:^NSComparisonResult(NSArray<NSNumber *> *first, NSArray<NSNumber *> *last) {
		NSComparisonResult order = [first[0] compare:last[0]];
		return order == NSOrderedSame ? [first[1] compare:last[1]] : order;
	}];
	NSTimeInterval total = 0, rangeStart = 0, rangeEnd = 0;
	BOOL hasRange = NO;
	for (NSArray<NSNumber *> *range in ranges) {
		NSTimeInterval start = range[0].doubleValue, end = range[1].doubleValue;
		if (hasRange && start <= rangeEnd) {
			rangeEnd = MAX(rangeEnd, end);
		} else {
			if (hasRange)
				total += rangeEnd - rangeStart;
			rangeStart = start;
			rangeEnd = end;
			hasRange = YES;
		}
	}
	return hasRange ? total + rangeEnd - rangeStart : 0;
}

@implementation BAAnalyticsHistoryWindow

- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
					observations:(NSArray<BAAnalyticsObservation *> *)observations
						intervals:(NSArray<BAAnalyticsHistoryInterval *> *)intervals
							 gaps:(NSArray<BAAnalyticsHistoryGap *> *)gaps
			 coverageMetricIdentifiers:(NSSet<NSString *> *)coverageMetricIdentifiers
					coveredDuration:(NSTimeInterval)coveredDuration
					missingDuration:(NSTimeInterval)missingDuration
				coverageSecondsByMetric:(NSDictionary<NSString *, NSNumber *> *)coverageSecondsByMetric {
	self = [super init];
	if (!self)
		return nil;
	if (!BAReportValidRange(startDate, endDate))
		return nil;
	_startDate = [startDate copy];
	_endDate = [endDate copy];
	_coverageMetricIdentifiers = BAReportMetricSet(coverageMetricIdentifiers);
	NSMutableArray *safeObservations = [NSMutableArray array];
	for (BAAnalyticsObservation *observation in BAReportTypedArray(observations, [BAAnalyticsObservation class])) {
		if ([observation.timestamp compare:startDate] != NSOrderedAscending &&
			[observation.timestamp compare:endDate] != NSOrderedDescending)
			[safeObservations addObject:observation];
	}
	_observations = [safeObservations sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsObservation *first,
		BAAnalyticsObservation *last) {
		NSComparisonResult order = [first.timestamp compare:last.timestamp];
		return order == NSOrderedSame ? [first.identifier compare:last.identifier] : order;
	}];
	NSMutableArray *safeIntervals = [NSMutableArray array];
	for (BAAnalyticsHistoryInterval *interval in BAReportTypedArray(intervals, [BAAnalyticsHistoryInterval class])) {
		NSDate *start = [startDate laterDate:interval.startDate];
		NSDate *end = [endDate earlierDate:interval.endDate];
		if ([end compare:start] != NSOrderedDescending)
			continue;
		BAAnalyticsHistoryInterval *clipped = [[BAAnalyticsHistoryInterval alloc]
			initWithStartDate:start endDate:end startObservation:interval.startObservation endObservation:interval.endObservation
			coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:interval.state];
		if (clipped)
			[safeIntervals addObject:clipped];
	}
	_intervals = [safeIntervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *first,
		BAAnalyticsHistoryInterval *last) {
		NSComparisonResult order = [first.startDate compare:last.startDate];
		return order == NSOrderedSame ? [first.endDate compare:last.endDate] : order;
	}];
	NSMutableArray *safeGaps = [NSMutableArray array];
	for (BAAnalyticsHistoryGap *gap in BAReportTypedArray(gaps, [BAAnalyticsHistoryGap class])) {
		NSDate *start = [startDate laterDate:gap.startDate];
		NSDate *end = [endDate earlierDate:gap.endDate];
		if ([end compare:start] == NSOrderedAscending)
			continue;
		BAAnalyticsHistoryGap *clipped = [[BAAnalyticsHistoryGap alloc] initWithStartDate:start endDate:end reason:gap.reason];
		if (clipped)
			[safeGaps addObject:clipped];
	}
	_gaps = [safeGaps sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryGap *first, BAAnalyticsHistoryGap *last) {
		NSComparisonResult order = [first.startDate compare:last.startDate];
		return order == NSOrderedSame ? [first.endDate compare:last.endDate] : order;
	}];
	// Production reports are constructed on the history worker, so the first
	// graph query on the main thread only needs the cached binary search.
	if (_gaps.count) (void)BAHistoryIndexForGaps(_gaps);
	// Supplied summaries are not evidence: verify them from the clipped trusted pairs.
	(void)coveredDuration;
	(void)missingDuration;
	NSTimeInterval windowDuration = [endDate timeIntervalSinceDate:startDate];
	_coveredDuration = MIN(windowDuration, BAReportUnionDuration(_intervals, _coverageMetricIdentifiers, _startDate));
	_missingDuration = MAX(0, windowDuration - _coveredDuration);
	NSMutableSet *metrics = [_coverageMetricIdentifiers mutableCopy];
	for (BAAnalyticsObservation *observation in _observations)
		[metrics addObjectsFromArray:observation.values.allKeys];
	for (BAAnalyticsHistoryInterval *interval in _intervals)
		[metrics unionSet:interval.coveredMetricIdentifiers];
	if ([coverageSecondsByMetric isKindOfClass:[NSDictionary class]]) {
		[coverageSecondsByMetric enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if ([key isKindOfClass:[NSString class]] && [key length] &&
				[value isKindOfClass:[NSNumber class]] && isfinite([value doubleValue]) && [value doubleValue] >= 0)
				[metrics addObject:[key copy]];
		}];
	}
	NSMutableDictionary *seconds = [NSMutableDictionary dictionary];
	for (NSString *metric in metrics) @autoreleasepool {
		seconds[metric] = @(MIN(windowDuration, BAReportUnionDuration(_intervals, [NSSet setWithObject:metric], _startDate)));
	}
	_coverageSecondsByMetric = [seconds copy];
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsFamilyReport

- (instancetype)initWithFamily:(NSString *)family availability:(BAAnalyticsReportAvailability)availability
						 window:(BAAnalyticsHistoryWindow *)window payload:(NSDictionary<NSString *, id> *)payload
					limitations:(NSArray<NSString *> *)limitations {
	self = [super init];
	if (!self)
		return nil;
	if (![family isKindOfClass:[NSString class]] || !family.length ||
		![window isKindOfClass:[BAAnalyticsHistoryWindow class]])
		return nil;
	_family = [family copy];
	_availability = availability >= BAAnalyticsReportAvailabilityLoading && availability <= BAAnalyticsReportAvailabilityUnavailable
		? availability : BAAnalyticsReportAvailabilityUnavailable;
	_window = [window copy];
	NSMutableDictionary *safePayload = [NSMutableDictionary dictionary];
	if ([payload isKindOfClass:[NSDictionary class]]) {
		[payload enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if (![key isKindOfClass:[NSString class]] || ![key length])
				return;
			if ([key isEqualToString:BAAnalyticsPayloadLatestObservation] && ![value isKindOfClass:[BAAnalyticsObservation class]])
				return;
			if ([key isEqualToString:BAAnalyticsPayloadSelectedSession] && ![value isKindOfClass:[BAAnalyticsHistorySession class]])
				return;
			if ([key isEqualToString:BAAnalyticsPayloadSessions] || [key isEqualToString:BAAnalyticsPayloadTransitions]) {
				if (![value isKindOfClass:[NSArray class]])
					return;
				Class objectClass = [key isEqualToString:BAAnalyticsPayloadSessions]
					? [BAAnalyticsHistorySession class] : [BAAnalyticsStateTransition class];
				safePayload[[key copy]] = BAReportTypedArray(value, objectClass);
				return;
			}
			id immutable = BAReportImmutableValue(value, 0);
			if (immutable)
				safePayload[[key copy]] = immutable;
		}];
	}
	_payload = [safePayload copy];
	_limitations = BAReportTypedArray(limitations, [NSString class]);
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsReport

- (instancetype)initWithSequenceNumber:(uint64_t)sequenceNumber generatedAt:(NSDate *)generatedAt
				 sourceProfileIdentifier:(NSString *)sourceProfileIdentifier
						fieldMetadata:(NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *)fieldMetadata
						familyReports:(NSDictionary<NSString *, BAAnalyticsFamilyReport *> *)familyReports error:(NSError *)error {
	self = [super init];
	if (!self)
		return nil;
	if (!BAReportValidDate(generatedAt) || ![sourceProfileIdentifier isKindOfClass:[NSString class]])
		return nil;
	_sequenceNumber = sequenceNumber;
	_generatedAt = [generatedAt copy];
	_sourceProfileIdentifier = [sourceProfileIdentifier copy];
	NSMutableDictionary *safeMetadata = [NSMutableDictionary dictionary];
	if ([fieldMetadata isKindOfClass:[NSDictionary class]]) {
		[fieldMetadata enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if ([key isKindOfClass:[NSString class]] && [key length] && [value isKindOfClass:[BAAnalyticsFieldMetadata class]])
				safeMetadata[[key copy]] = [value copy];
		}];
	}
	_fieldMetadata = [safeMetadata copy];
	NSMutableDictionary *safeReports = [NSMutableDictionary dictionary];
	if ([familyReports isKindOfClass:[NSDictionary class]]) {
		[familyReports enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if ([key isKindOfClass:[NSString class]] && [key length] && [value isKindOfClass:[BAAnalyticsFamilyReport class]])
				safeReports[[key copy]] = [value copy];
		}];
	}
	_familyReports = [safeReports copy];
	if ([error isKindOfClass:[NSError class]])
		_error = BAReportImmutableValue(error, 0);
	return self;
}

- (BAAnalyticsFamilyReport *)reportForFamily:(NSString *)family {
	return [family isKindOfClass:[NSString class]] ? _familyReports[family] : nil;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end
