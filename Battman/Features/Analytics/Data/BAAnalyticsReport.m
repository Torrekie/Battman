#import "BAAnalyticsReport.h"
#import <CommonCrypto/CommonDigest.h>
#import <math.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

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

// The window initializer supplies clipped intervals sorted by start and end.
// Filtering preserves that order, so each coverage union needs only one pass.
// Endpoints are relative to the window start, so subtraction remains bounded.
static NSTimeInterval BAReportUnionDuration(NSArray<BAAnalyticsHistoryInterval *> *intervals,
										 NSSet<NSString *> *metrics, NSDate *origin) {
	if (!metrics.count)
		return 0;
	NSTimeInterval total = 0, rangeStart = 0, rangeEnd = 0;
	BOOL hasRange = NO;
	for (BAAnalyticsHistoryInterval *interval in intervals) {
		if (![metrics isSubsetOfSet:interval.coveredMetricIdentifiers] || interval.duration <= 0)
			continue;
		NSTimeInterval start = [interval.startDate timeIntervalSinceDate:origin];
		NSTimeInterval end = [interval.endDate timeIntervalSinceDate:origin];
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

@interface BAAnalyticsHistoryWindow (CacheReferences)
- (void)restoreCachedIntervals:(NSArray *)intervals gaps:(NSArray *)gaps;
@end

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
		BAAnalyticsHistoryInterval *clipped = [start isEqual:interval.startDate] && [end isEqual:interval.endDate] ? interval :
			[[BAAnalyticsHistoryInterval alloc] initWithStartDate:start endDate:end startObservation:interval.startObservation
				endObservation:interval.endObservation coveredMetricIdentifiers:interval.coveredMetricIdentifiers state:interval.state];
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

- (void)restoreCachedIntervals:(NSArray *)intervals gaps:(NSArray *)gaps {
	_intervals = [intervals copy];
	_gaps = [gaps copy];
	if (_gaps.count) (void)BAHistoryIndexForGaps(_gaps);
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

- (BAAnalyticsReport *)reportByMarkingCached {
	if (self.isCached) return self;
	BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:self.sequenceNumber generatedAt:self.generatedAt
		sourceProfileIdentifier:self.sourceProfileIdentifier fieldMetadata:self.fieldMetadata familyReports:self.familyReports error:self.error];
	report->_cached = YES;
	return report;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end


// Explicit value/reference tables keep cache decoding independent of Objective-C
// class names. No archive can request an arbitrary class or selector.
static NSUInteger const BACacheMaximumBytes = 16 * 1024 * 1024;
static NSUInteger const BACacheMaximumLogicalBytes = 64 * 1024 * 1024;
static uint8_t const BACacheCompressedMagic[8] = {'B', 'A', 'H', 'C', 'A', 'C', 'H', 'E'};
static NSUInteger const BACacheMaximumContainerItems = 120000;
static NSUInteger const BACacheMaximumValueVisits = 2000000;
static NSTimeInterval const BACacheMaximumAge = 24 * 3600;

static void BACacheRequire(BOOL condition) {
    if (!condition) [NSException raise:@"BAAnalyticsInvalidCache" format:@"Invalid or excessive history cache."];
}

static NSData *BACacheCompress(NSData *data, BOOL (^cancelled)(void), NSUInteger *reason, NSInteger *ioCode) {
    NSUInteger length = data.length;
    if (!length || length > BACacheMaximumLogicalBytes) { *reason = 10; return nil; }
    uint8_t header[16] = {'B', 'A', 'H', 'C', 'A', 'C', 'H', 'E', 0, 0, 0, 1,
        (uint8_t)(length >> 24), (uint8_t)(length >> 16), (uint8_t)(length >> 8), (uint8_t)length};
    NSMutableData *result = [NSMutableData dataWithBytes:header length:sizeof header];
    z_stream stream = {0};
    int status = deflateInit(&stream, Z_DEFAULT_COMPRESSION);
    if (status != Z_OK) { *reason = 13; *ioCode = status; return nil; }
    BOOL complete = NO;
    @try {
        uint8_t output[65536];
        NSUInteger offset = 0;
        for (;;) {
            if (cancelled()) { *reason = 3; break; }
            if (!stream.avail_in && offset < length) {
                NSUInteger count = MIN(length - offset, (NSUInteger)65536);
                stream.next_in = (Bytef *)data.bytes + offset; stream.avail_in = (uInt)count;
                offset += count;
            }
            uInt previousInput = stream.avail_in;
            stream.next_out = output; stream.avail_out = sizeof output;
            status = deflate(&stream, offset == length ? Z_FINISH : Z_NO_FLUSH);
            NSUInteger produced = sizeof output - stream.avail_out;
            if (produced > BACacheMaximumBytes - result.length) { *reason = 15; break; }
            [result appendBytes:output length:produced];
            if (status == Z_STREAM_END) { complete = YES; break; }
            if (status != Z_OK) { *reason = 14; *ioCode = status; break; }
            if (!produced && stream.avail_in == previousInput) { *reason = 14; *ioCode = Z_BUF_ERROR; break; }
        }
    } @finally {
        int closed = deflateEnd(&stream);
        if (complete && closed != Z_OK) { complete = NO; *reason = 14; *ioCode = closed; }
    }
    if (complete && cancelled()) { complete = NO; *reason = 3; }
    return complete ? [result copy] : nil;
}

static NSData *BACacheInflate(NSData *data, BOOL (^cancelled)(void), NSUInteger *reason, NSInteger *ioCode) {
    if (data.length <= 16) { *reason = 11; return nil; }
    const uint8_t *header = data.bytes;
    if (memcmp(header, BACacheCompressedMagic, sizeof BACacheCompressedMagic) || header[8] || header[9] || header[10] || header[11] != 1) {
        *reason = 11; return nil;
    }
    NSUInteger declared = ((NSUInteger)header[12] << 24) | ((NSUInteger)header[13] << 16) | ((NSUInteger)header[14] << 8) | header[15];
    if (!declared || declared > BACacheMaximumLogicalBytes) { *reason = 12; return nil; }
    // Validate the declared bound before allocating, then grow only as checked
    // chunks arrive. A short corrupt stream cannot reserve its declared size.
    NSMutableData *result = [NSMutableData dataWithCapacity:MIN(declared, (NSUInteger)65536)];
    z_stream stream = {0};
    int status = inflateInit(&stream);
    if (status != Z_OK) { *reason = 16; *ioCode = status; return nil; }
    BOOL complete = NO;
    @try {
        uint8_t output[65536];
        NSUInteger offset = 16;
        for (;;) {
            if (cancelled()) { *reason = 3; break; }
            if (!stream.avail_in && offset < data.length) {
                NSUInteger count = MIN(data.length - offset, (NSUInteger)65536);
                stream.next_in = (Bytef *)data.bytes + offset; stream.avail_in = (uInt)count;
                offset += count;
            }
            uInt previousInput = stream.avail_in;
            stream.next_out = output; stream.avail_out = sizeof output;
            status = inflate(&stream, Z_NO_FLUSH);
            NSUInteger produced = sizeof output - stream.avail_out;
            if (produced > declared - result.length) { *reason = 18; break; }
            [result appendBytes:output length:produced];
            if (status == Z_STREAM_END) {
                if (result.length != declared) *reason = 18;
                else if (stream.avail_in || offset != data.length) *reason = 19;
                else complete = YES;
                break;
            }
            if (status != Z_OK && status != Z_BUF_ERROR) { *reason = 17; *ioCode = status; break; }
            if (!produced && stream.avail_in == previousInput) { *reason = 20; break; }
        }
    } @finally {
        int closed = inflateEnd(&stream);
        if (complete && closed != Z_OK) { complete = NO; *reason = 17; *ioCode = closed; }
    }
    if (complete && cancelled()) { complete = NO; *reason = 3; }
    // The private result is parsed immediately and never mutated or exposed.
    // Avoid a second allocation of the entire bounded logical buffer.
    return complete ? result : nil;
}
static BOOL BACacheString(id value) {
    return [value isKindOfClass:NSString.class] && [value length] <= 4096;
}
static BOOL BACacheNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]);
}
static BOOL BACacheInteger(id value, NSUInteger maximum) {
    return BACacheNumber(value) && [value doubleValue] >= 0 &&
        [value doubleValue] <= maximum && floor([value doubleValue]) == [value doubleValue];
}
static BOOL BACacheBoolean(id value) {
    return BACacheInteger(value, 1);
}
static void BACacheKeys(NSDictionary *value, NSArray<NSString *> *keys) {
    BACacheRequire([value isKindOfClass:NSDictionary.class] && value.count == keys.count);
    for (NSString *key in keys) BACacheRequire(value[key] != nil);
}
static NSString *BACacheKind(id value) {
    if ([value isKindOfClass:BAAnalyticsFieldMetadata.class]) return @"metadata";
    if ([value isKindOfClass:BAAnalyticsObservation.class]) return @"observation";
    if ([value isKindOfClass:BAAnalyticsHistoryInterval.class]) return @"interval";
    if ([value isKindOfClass:BAAnalyticsHistoryGap.class]) return @"gap";
    if ([value isKindOfClass:BAAnalyticsStateTransition.class]) return @"transition";
    if ([value isKindOfClass:BAAnalyticsHistorySession.class]) return @"session";
    if ([value isKindOfClass:BAAnalyticsHistoryWindow.class]) return @"window";
    if ([value isKindOfClass:BAAnalyticsFamilyReport.class]) return @"family";
    return nil;
}
static NSUInteger BACacheKindLimit(NSString *kind) {
    if ([kind isEqual:@"observation"]) return 60000;
    if ([kind isEqual:@"interval"]) return 120000;
    if ([kind isEqual:@"gap"] || [kind isEqual:@"transition"]) return 20000;
    if ([kind isEqual:@"session"]) return 8192;
    if ([kind isEqual:@"metadata"]) return 4096;
    if ([kind isEqual:@"window"]) return 64;
    if ([kind isEqual:@"family"]) return 32;
    return 0;
}
static BOOL BACacheTypedArray(id values, Class type) {
    if (![values isKindOfClass:NSArray.class] || [values count] > BACacheMaximumContainerItems) return NO;
    for (id value in values) if (![value isKindOfClass:type]) return NO;
    return YES;
}
static BOOL BACacheTypedMap(id values, Class type) {
    if (![values isKindOfClass:NSDictionary.class] || [values count] > 4096) return NO;
    for (id key in values) if (!BACacheString(key) || ![key length] || ![values[key] isKindOfClass:type]) return NO;
    return YES;
}
static BOOL BACacheMetricSet(id values) {
    if (![values isKindOfClass:NSSet.class] || [values count] > 256) return NO;
    for (id value in values) if (!BACacheString(value) || ![value length]) return NO;
    return YES;
}
static BOOL BACacheEligibleReport(BAAnalyticsReport *report) {
    if (![report isKindOfClass:BAAnalyticsReport.class] || report.error || !report.familyReports.count ||
        !BAReportValidDate(report.generatedAt) || !BACacheString(report.sourceProfileIdentifier) ||
        !report.sourceProfileIdentifier.length || report.familyReports.count > 32) return NO;
    BOOL completed = NO;
    for (NSString *key in report.familyReports) {
        BAAnalyticsFamilyReport *family = report.familyReports[key];
        if (![key isEqual:family.family] || family.availability == BAAnalyticsReportAvailabilityLoading) return NO;
        completed |= family.availability == BAAnalyticsReportAvailabilityReady || family.availability == BAAnalyticsReportAvailabilityPartial;
    }
    return completed;
}

@interface BACachedReportGraph : NSObject
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *nodes;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *encodedReferences;
@property (nonatomic, strong) NSMapTable<id, NSNumber *> *objectIndices;
@property (nonatomic, strong) NSMutableDictionary<NSData *, NSNumber *> *internedNodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *kindCounts;
@property (nonatomic, strong) NSMutableArray *decodedObjects;
@property (nonatomic, strong) NSMutableIndexSet *decodingIndices;
@property (nonatomic, copy) NSDate *generatedAt;
@property (nonatomic) NSUInteger visits;
@property (nonatomic) NSUInteger failureReason;
@property (nonatomic, copy) BOOL (^cancelled)(void);
- (id)encodeValue:(id)value depth:(NSUInteger)depth;
- (id)decodeValue:(id)value depth:(NSUInteger)depth;
- (id)decodeNode:(NSUInteger)index depth:(NSUInteger)depth;
@end

@implementation BACachedReportGraph
- (instancetype)init {
    self = [super init];
    if (self) {
        _nodes = [NSMutableArray array];
        _encodedReferences = [NSMutableArray array];
        _objectIndices = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
            valueOptions:NSPointerFunctionsStrongMemory capacity:1024];
        _internedNodes = [NSMutableDictionary dictionary];
        _kindCounts = [NSMutableDictionary dictionary];
        _decodedObjects = [NSMutableArray array];
        _decodingIndices = [NSMutableIndexSet indexSet];
    }
    return self;
}
- (void)visitDepth:(NSUInteger)depth {
    if (depth > 32) { self.failureReason = 1; BACacheRequire(NO); }
    if (++self.visits > BACacheMaximumValueVisits) { self.failureReason = 2; BACacheRequire(NO); }
    if ((self.visits & 63) == 1 && self.cancelled && self.cancelled()) { self.failureReason = 3; BACacheRequire(NO); }
}
- (void)validateDate:(id)value {
    if (!(BAReportValidDate(value) && fabs([value timeIntervalSince1970]) <= 1e12 &&
        [value compare:self.generatedAt] != NSOrderedDescending)) { self.failureReason = 4; BACacheRequire(NO); }
}
- (void)countKind:(NSString *)kind {
    NSUInteger count = [self.kindCounts[kind] unsignedIntegerValue] + 1;
    self.kindCounts[kind] = @(count);
    if (count > BACacheKindLimit(kind)) { self.failureReason = 5; BACacheRequire(NO); }
}
- (NSDictionary *)encodeNode:(id)value depth:(NSUInteger)depth {
    NSString *kind = BACacheKind(value);
    BACacheRequire(kind != nil);
    NSMutableDictionary *node = [NSMutableDictionary dictionaryWithObject:kind forKey:@"kind"];
    if ([kind isEqual:@"metadata"]) {
        BAAnalyticsFieldMetadata *field = value;
        node[@"table"] = field.sourceTable; node[@"column"] = field.sourceColumn;
        node[@"unit"] = field.unit; node[@"decoder"] = field.decoderIdentifier; node[@"valid"] = @(field.unitValidated);
        BACacheRequire(BACacheString(field.sourceTable) && BACacheString(field.sourceColumn) && BACacheString(field.unit) && BACacheString(field.decoderIdentifier));
    } else if ([kind isEqual:@"observation"]) {
        BAAnalyticsObservation *point = value;
        BACacheRequire(BACacheString(point.identifier) && point.identifier.length && isfinite(point.sourceTimestamp));
        [self validateDate:point.timestamp];
        node[@"id"] = point.identifier; node[@"date"] = point.timestamp; node[@"raw"] = @(point.sourceTimestamp); node[@"valid"] = @(point.timestampValidated);
        node[@"values"] = [self encodeValue:point.values depth:depth + 1];
        node[@"metadata"] = [self encodeValue:point.fieldMetadata depth:depth + 1];
    } else if ([kind isEqual:@"interval"]) {
        BAAnalyticsHistoryInterval *interval = value;
        [self validateDate:interval.startDate]; [self validateDate:interval.endDate];
        node[@"start"] = interval.startDate; node[@"end"] = interval.endDate;
        node[@"first"] = [self encodeValue:interval.startObservation depth:depth + 1];
        node[@"last"] = [self encodeValue:interval.endObservation depth:depth + 1];
        node[@"metrics"] = [self encodeValue:interval.coveredMetricIdentifiers depth:depth + 1]; node[@"state"] = @(interval.state);
    } else if ([kind isEqual:@"gap"]) {
        BAAnalyticsHistoryGap *gap = value;
        [self validateDate:gap.startDate]; [self validateDate:gap.endDate];
        BACacheRequire(BACacheString(gap.reason));
        node[@"start"] = gap.startDate; node[@"end"] = gap.endDate; node[@"reason"] = gap.reason;
    } else if ([kind isEqual:@"transition"]) {
        BAAnalyticsStateTransition *transition = value;
        [self validateDate:transition.earliestDate]; [self validateDate:transition.latestDate];
        BACacheRequire(BACacheString(transition.identifier) && transition.identifier.length);
        node[@"id"] = transition.identifier; node[@"start"] = transition.earliestDate; node[@"end"] = transition.latestDate;
        node[@"previous"] = @(transition.previousState); node[@"next"] = @(transition.nextState);
        node[@"reason"] = transition.reasonCode ? [self encodeValue:transition.reasonCode depth:depth + 1] : @{@"type": @"nil"};
    } else if ([kind isEqual:@"session"]) {
        BAAnalyticsHistorySession *session = value;
        [self validateDate:session.startDate]; [self validateDate:session.endDate];
        BACacheRequire(BACacheString(session.identifier) && session.identifier.length);
        node[@"id"] = session.identifier; node[@"sessionKind"] = session.kind;
        node[@"start"] = session.startDate; node[@"end"] = session.endDate;
        node[@"startKnown"] = @(session.startBoundaryKnown); node[@"endKnown"] = @(session.endBoundaryKnown);
        node[@"observations"] = [self encodeValue:session.observations depth:depth + 1];
        node[@"intervals"] = [self encodeValue:session.intervals depth:depth + 1];
        node[@"gaps"] = [self encodeValue:session.gaps depth:depth + 1];
        node[@"transitions"] = [self encodeValue:session.transitions depth:depth + 1];
    } else if ([kind isEqual:@"window"]) {
        BAAnalyticsHistoryWindow *window = value;
        [self validateDate:window.startDate]; [self validateDate:window.endDate];
        node[@"start"] = window.startDate; node[@"end"] = window.endDate;
        node[@"observations"] = [self encodeValue:window.observations depth:depth + 1];
        node[@"intervals"] = [self encodeValue:window.intervals depth:depth + 1];
        node[@"gaps"] = [self encodeValue:window.gaps depth:depth + 1];
        node[@"metrics"] = [self encodeValue:window.coverageMetricIdentifiers depth:depth + 1];
        node[@"coverage"] = [self encodeValue:window.coverageSecondsByMetric depth:depth + 1];
    } else {
        BAAnalyticsFamilyReport *family = value;
        BACacheRequire(BACacheString(family.family) && family.family.length && family.availability != BAAnalyticsReportAvailabilityLoading);
        node[@"family"] = family.family; node[@"availability"] = @(family.availability);
        node[@"window"] = [self encodeValue:family.window depth:depth + 1];
        node[@"payload"] = [self encodeValue:family.payload depth:depth + 1];
        node[@"limitations"] = [self encodeValue:family.limitations depth:depth + 1];
    }
    return [node copy];
}
- (id)encodeValue:(id)value depth:(NSUInteger)depth {
    [self visitDepth:depth];
    if (BACacheString(value) || BACacheNumber(value)) return value;
    if ([value isKindOfClass:NSDate.class]) { [self validateDate:value]; return value; }
    if ([value isKindOfClass:NSData.class]) { BACacheRequire([value length] <= 1024 * 1024); return value; }
    NSString *kind = BACacheKind(value);
    if (kind) {
        NSNumber *index = [self.objectIndices objectForKey:value];
        if (!index) {
            NSDictionary *node = [self encodeNode:value depth:depth];
            // NSDictionary hashes do not provide a useful distribution for
            // thousands of same-shaped interval nodes. A content digest keeps
            // graph interning bounded instead of introducing a quadratic pass.
            NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:node format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            if (!bytes) { self.failureReason = 6; BACacheRequire(NO); }
            if (bytes.length > BACacheMaximumBytes) { self.failureReason = 7; BACacheRequire(NO); }
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
            NSData *key = [NSData dataWithBytes:digest length:sizeof(digest)];
            index = self.internedNodes[key];
            if (index) BACacheRequire([self.nodes[index.unsignedIntegerValue] isEqual:node]);
            if (!index) {
                [self countKind:kind]; index = @(self.nodes.count);
                [self.nodes addObject:node]; self.internedNodes[key] = index;
                [self.encodedReferences addObject:@{@"type": @"reference", @"value": index}];
            }
            [self.objectIndices setObject:index forKey:value];
        }
        // Binary plists preserve container identity. Reuse each immutable
        // reference dictionary rather than serializing one per family link.
        return self.encodedReferences[index.unsignedIntegerValue];
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        BACacheRequire([value count] <= 4096);
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        for (id key in value) {
            BACacheRequire(BACacheString(key) && [key length]);
            dictionary[key] = [self encodeValue:value[key] depth:depth + 1];
        }
        return @{@"type": @"dictionary", @"value": dictionary};
    }
    BOOL set = [value isKindOfClass:NSSet.class];
    BACacheRequire(set || [value isKindOfClass:NSArray.class]);
    BACacheRequire([value count] <= BACacheMaximumContainerItems);
    if (set) BACacheRequire(BACacheMetricSet(value));
    NSArray *items = set ? [[value allObjects] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        BACacheRequire(BACacheString(a) && BACacheString(b)); return [a compare:b];
    }] : value;
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) [array addObject:[self encodeValue:item depth:depth + 1]];
    return @{@"type": set ? @"set" : @"array", @"value": array};
}
- (id)decodeValue:(id)value depth:(NSUInteger)depth {
    [self visitDepth:depth];
    if (BACacheString(value) || BACacheNumber(value)) return value;
    if ([value isKindOfClass:NSDate.class]) { [self validateDate:value]; return value; }
    if ([value isKindOfClass:NSData.class]) { BACacheRequire([value length] <= 1024 * 1024); return value; }
    BACacheKeys(value, @[@"type", @"value"]);
    NSString *type = value[@"type"]; id contents = value[@"value"];
    if ([type isEqual:@"reference"]) {
        BACacheRequire(self.nodes.count && BACacheInteger(contents, self.nodes.count - 1));
        return [self decodeNode:[contents unsignedIntegerValue] depth:depth + 1];
    }
    if ([type isEqual:@"dictionary"]) {
        BACacheRequire([contents isKindOfClass:NSDictionary.class] && [contents count] <= 4096);
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        for (id key in contents) {
            BACacheRequire(BACacheString(key) && [key length]);
            dictionary[key] = [self decodeValue:contents[key] depth:depth + 1];
        }
        return [dictionary copy];
    }
    BOOL set = [type isEqual:@"set"];
    BACacheRequire(set || [type isEqual:@"array"]);
    BACacheRequire([contents isKindOfClass:NSArray.class] && [contents count] <= BACacheMaximumContainerItems);
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[contents count]];
    for (id item in contents) [array addObject:[self decodeValue:item depth:depth + 1]];
    if (set) {
        BACacheRequire(array.count <= 256);
        for (id item in array) BACacheRequire(BACacheString(item) && [item length]);
        NSSet *result = [NSSet setWithArray:array]; BACacheRequire(result.count == array.count); return result;
    }
    return [array copy];
}
- (id)decodeNode:(NSUInteger)index depth:(NSUInteger)depth {
    // decodeValue already charges each encoded reference. Memo hits validate
    // their depth and cycle boundary without charging the same edge twice.
    if (depth > 32) { self.failureReason = 1; BACacheRequire(NO); }
    BACacheRequire(index < self.nodes.count && ![self.decodingIndices containsIndex:index]);
    id result = self.decodedObjects[index];
    if (result != NSNull.null) return result;
    // Reachable nodes are charged by their decodeValue edge, as in encoding.
    // An unreferenced tail node has no such edge and gets its own work charge.
    if (!depth) [self visitDepth:depth];
    [self.decodingIndices addIndex:index];
    NSDictionary *node = self.nodes[index]; NSString *kind = node[@"kind"];
    if ([kind isEqual:@"metadata"]) {
        BACacheKeys(node, @[@"kind", @"table", @"column", @"unit", @"decoder", @"valid"]);
        BACacheRequire(BACacheString(node[@"table"]) && BACacheString(node[@"column"]) && BACacheString(node[@"unit"]) &&
            BACacheString(node[@"decoder"]) && BACacheBoolean(node[@"valid"]));
        BAAnalyticsFieldMetadata *field = [[BAAnalyticsFieldMetadata alloc] initWithSourceTable:node[@"table"] sourceColumn:node[@"column"]
            unit:node[@"unit"] decoderIdentifier:node[@"decoder"] unitValidated:[node[@"valid"] boolValue]];
        BACacheRequire(field.unitValidated == [node[@"valid"] boolValue]); result = field;
    } else if ([kind isEqual:@"observation"]) {
        BACacheKeys(node, @[@"kind", @"id", @"date", @"raw", @"valid", @"values", @"metadata"]);
        BACacheRequire(BACacheString(node[@"id"]) && [node[@"id"] length] && BACacheNumber(node[@"raw"]) && BACacheBoolean(node[@"valid"]));
        [self validateDate:node[@"date"]];
        NSDictionary *values = [self decodeValue:node[@"values"] depth:depth + 1];
        NSDictionary *metadata = [self decodeValue:node[@"metadata"] depth:depth + 1];
        BACacheRequire(BACacheTypedMap(values, NSNumber.class) && BACacheTypedMap(metadata, BAAnalyticsFieldMetadata.class));
        for (NSNumber *number in values.allValues) BACacheRequire(BACacheNumber(number));
        BAAnalyticsObservation *point = [[BAAnalyticsObservation alloc] initWithIdentifier:node[@"id"] timestamp:node[@"date"]
            sourceTimestamp:[node[@"raw"] doubleValue] timestampValidated:[node[@"valid"] boolValue] values:values fieldMetadata:metadata];
        BACacheRequire(point && [point.values isEqual:values] && [point.fieldMetadata isEqual:metadata]); result = point;
    } else if ([kind isEqual:@"interval"]) {
        BACacheKeys(node, @[@"kind", @"start", @"end", @"first", @"last", @"metrics", @"state"]);
        [self validateDate:node[@"start"]]; [self validateDate:node[@"end"]];
        BAAnalyticsObservation *first = [self decodeValue:node[@"first"] depth:depth + 1];
        BAAnalyticsObservation *last = [self decodeValue:node[@"last"] depth:depth + 1];
        NSSet *metrics = [self decodeValue:node[@"metrics"] depth:depth + 1];
        BACacheRequire([first isKindOfClass:BAAnalyticsObservation.class] && [last isKindOfClass:BAAnalyticsObservation.class] &&
            BACacheMetricSet(metrics) && BACacheInteger(node[@"state"], BAAnalyticsObservedStateFull));
        BAAnalyticsHistoryInterval *interval = [[BAAnalyticsHistoryInterval alloc] initWithStartDate:node[@"start"] endDate:node[@"end"]
            startObservation:first endObservation:last coveredMetricIdentifiers:metrics state:[node[@"state"] integerValue]];
        BACacheRequire(interval && [interval.startDate isEqual:node[@"start"]] && [interval.endDate isEqual:node[@"end"]] &&
            [interval.coveredMetricIdentifiers isEqual:metrics] && interval.state == [node[@"state"] integerValue]); result = interval;
    } else if ([kind isEqual:@"gap"]) {
        BACacheKeys(node, @[@"kind", @"start", @"end", @"reason"]);
        [self validateDate:node[@"start"]]; [self validateDate:node[@"end"]]; BACacheRequire(BACacheString(node[@"reason"]));
        result = [[BAAnalyticsHistoryGap alloc] initWithStartDate:node[@"start"] endDate:node[@"end"] reason:node[@"reason"]];
    } else if ([kind isEqual:@"transition"]) {
        BACacheKeys(node, @[@"kind", @"id", @"start", @"end", @"previous", @"next", @"reason"]);
        [self validateDate:node[@"start"]]; [self validateDate:node[@"end"]];
        BACacheRequire(BACacheString(node[@"id"]) && [node[@"id"] length] && BACacheInteger(node[@"previous"], BAAnalyticsObservedStateFull) &&
            BACacheInteger(node[@"next"], BAAnalyticsObservedStateFull));
        id encodedReason = node[@"reason"]; NSNumber *reason = nil;
        if ([encodedReason isKindOfClass:NSDictionary.class] && [encodedReason[@"type"] isEqual:@"nil"]) BACacheKeys(encodedReason, @[@"type"]);
        else { reason = [self decodeValue:encodedReason depth:depth + 1]; BACacheRequire(BACacheNumber(reason)); }
        result = [[BAAnalyticsStateTransition alloc] initWithIdentifier:node[@"id"] earliestDate:node[@"start"] latestDate:node[@"end"]
            previousState:[node[@"previous"] integerValue] nextState:[node[@"next"] integerValue] reasonCode:reason];
    } else if ([kind isEqual:@"session"] || [kind isEqual:@"window"]) {
        BOOL session = [kind isEqual:@"session"];
        BACacheKeys(node, session ? @[@"kind", @"id", @"sessionKind", @"start", @"end", @"startKnown", @"endKnown", @"observations", @"intervals", @"gaps", @"transitions"] :
            @[@"kind", @"start", @"end", @"observations", @"intervals", @"gaps", @"metrics", @"coverage"]);
        [self validateDate:node[@"start"]]; [self validateDate:node[@"end"]];
        NSArray *points = [self decodeValue:node[@"observations"] depth:depth + 1];
        NSArray *intervals = [self decodeValue:node[@"intervals"] depth:depth + 1];
        NSArray *gaps = [self decodeValue:node[@"gaps"] depth:depth + 1];
        BACacheRequire(BACacheTypedArray(points, BAAnalyticsObservation.class) && BACacheTypedArray(intervals, BAAnalyticsHistoryInterval.class) &&
            BACacheTypedArray(gaps, BAAnalyticsHistoryGap.class));
        if (session) {
            NSArray *transitions = [self decodeValue:node[@"transitions"] depth:depth + 1];
            BACacheRequire(BACacheString(node[@"id"]) && [node[@"id"] length] && BACacheString(node[@"sessionKind"]) &&
                BACacheBoolean(node[@"startKnown"]) && BACacheBoolean(node[@"endKnown"]) && BACacheTypedArray(transitions, BAAnalyticsStateTransition.class));
            result = [[BAAnalyticsHistorySession alloc] initWithIdentifier:node[@"id"] kind:node[@"sessionKind"] startDate:node[@"start"] endDate:node[@"end"]
                startBoundaryKnown:[node[@"startKnown"] boolValue] endBoundaryKnown:[node[@"endKnown"] boolValue]
                observations:points intervals:intervals gaps:gaps transitions:transitions];
            BAAnalyticsHistorySession *restored = result;
            BACacheRequire(restored && [restored.observations isEqual:points] && [restored.intervals isEqual:intervals] &&
                [restored.gaps isEqual:gaps] && [restored.transitions isEqual:transitions]);
        } else {
            NSSet *metrics = [self decodeValue:node[@"metrics"] depth:depth + 1];
            NSDictionary *coverage = [self decodeValue:node[@"coverage"] depth:depth + 1];
            BACacheRequire(BACacheMetricSet(metrics) && BACacheTypedMap(coverage, NSNumber.class));
            for (NSNumber *seconds in coverage.allValues) BACacheRequire(BACacheNumber(seconds) && seconds.doubleValue >= 0);
            BAAnalyticsHistoryWindow *window = [[BAAnalyticsHistoryWindow alloc] initWithStartDate:node[@"start"] endDate:node[@"end"] observations:points
                intervals:intervals gaps:gaps coverageMetricIdentifiers:metrics coveredDuration:0 missingDuration:0 coverageSecondsByMetric:coverage];
            BACacheRequire(window && [window.observations isEqual:points] && window.intervals.count == intervals.count && window.gaps.count == gaps.count &&
                [window.coverageSecondsByMetric isEqual:coverage]);
            // Preserve shared graph references only after authoritative coverage
            // and clipping checks have completed in the designated initializer.
            for (NSUInteger i = 0; i < intervals.count; i++) {
                BAAnalyticsHistoryInterval *a = window.intervals[i], *b = intervals[i];
                BACacheRequire([a.startDate isEqual:b.startDate] && [a.endDate isEqual:b.endDate]);
            }
            for (NSUInteger i = 0; i < gaps.count; i++) {
                BAAnalyticsHistoryGap *a = window.gaps[i], *b = gaps[i];
                BACacheRequire([a.startDate isEqual:b.startDate] && [a.endDate isEqual:b.endDate]);
            }
            [window restoreCachedIntervals:intervals gaps:gaps];
            result = window;
        }
    } else {
        BACacheRequire([kind isEqual:@"family"]);
        BACacheKeys(node, @[@"kind", @"family", @"availability", @"window", @"payload", @"limitations"]);
        BACacheRequire(BACacheString(node[@"family"]) && [node[@"family"] length] && BACacheInteger(node[@"availability"], BAAnalyticsReportAvailabilityUnavailable) &&
            [node[@"availability"] integerValue] != BAAnalyticsReportAvailabilityLoading);
        BAAnalyticsHistoryWindow *window = [self decodeValue:node[@"window"] depth:depth + 1];
        NSDictionary *payload = [self decodeValue:node[@"payload"] depth:depth + 1];
        NSArray *limitations = [self decodeValue:node[@"limitations"] depth:depth + 1];
        BACacheRequire([window isKindOfClass:BAAnalyticsHistoryWindow.class] && [payload isKindOfClass:NSDictionary.class] && BACacheTypedArray(limitations, NSString.class));
        BAAnalyticsFamilyReport *family = [[BAAnalyticsFamilyReport alloc] initWithFamily:node[@"family"] availability:[node[@"availability"] integerValue]
            window:window payload:payload limitations:limitations];
        BACacheRequire([family.payload isEqual:payload]); result = family;
    }
    BACacheRequire(result != nil);
    self.decodedObjects[index] = result;
    [self.decodingIndices removeIndex:index];
    return result;
}
@end

// Diagnostics describe codec work only. Fixed kind keys and numeric stages do
// not reveal source paths, record identifiers, values, or exception text.
// Stages: 1 eligibility, 2 metadata, 3 families, 4 serialization, 5 logical size,
// 6 compression, 7 input size, 8 inflation, 9 parsing, 10 header, 11 graph,
// 12 restored eligibility.
// Reasons: 1 depth, 2 visits, 3 cancellation, 4 date, 5 kind count,
// 6 node serialization, 7 node size, 8 eligibility, 9 serialization, 10 size.
// 11 compression header, 12 declared size, 13/14 deflate init/stream,
// 15 compressed size, 16/17 inflate init/stream, 18 size mismatch,
// 19 trailing stream bytes, 20 incomplete stream.
static NSError *BACacheCodecError(BACachedReportGraph *graph, NSUInteger stage, NSUInteger reason, NSUInteger bytes, NSInteger ioCode) {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (NSString *kind in @[@"metadata", @"observation", @"interval", @"gap", @"transition", @"session", @"window", @"family"])
        counts[kind] = @([graph.kindCounts[kind] unsignedIntegerValue]);
    return [NSError errorWithDomain:@"BAAnalyticsHistoryCache" code:1 userInfo:@{
        NSLocalizedDescriptionKey: @"Invalid or excessive history cache.",
        @"stage": @(stage), @"reason": @(graph.failureReason ?: reason), @"bytes": @(bytes),
        @"visits": @(graph.visits), @"nodes": @(graph.nodes.count), @"counts": counts, @"ioCode": @(ioCode)
    }];
}

NSData *BAAnalyticsEncodeCachedReport(BAAnalyticsReport *report, NSError **error) {
    return BAAnalyticsEncodeCachedReportCancellable(report, error, ^BOOL { return NO; });
}
NSData *BAAnalyticsEncodeCachedReportCancellable(BAAnalyticsReport *report, NSError **error, BOOL (^cancelled)(void)) {
    if (error) *error = nil;
    BACachedReportGraph *graph = nil;
    NSUInteger stage = 1, reason = 0, encodedBytes = 0;
    NSInteger ioCode = 0;
    @try {
        if (cancelled()) { reason = 3; BACacheRequire(NO); }
        if (!BACacheEligibleReport(report)) { reason = 8; BACacheRequire(NO); }
        graph = [BACachedReportGraph new]; graph.generatedAt = report.generatedAt;
        graph.cancelled = cancelled;
        stage = 2;
        NSDictionary *metadata = [graph encodeValue:report.fieldMetadata depth:0];
        stage = 3;
        NSDictionary *families = [graph encodeValue:report.familyReports depth:0];
        NSDictionary *root = @{@"version": @1, @"generatedAt": report.generatedAt, @"sequence": @(report.sequenceNumber),
            @"profile": report.sourceProfileIdentifier, @"metadata": metadata, @"families": families, @"objects": graph.nodes};
        if (cancelled()) { reason = 3; BACacheRequire(NO); }
        stage = 4;
        NSError *serializationError = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
        ioCode = serializationError.code;
        encodedBytes = data.length;
        if (!data) { reason = 9; BACacheRequire(NO); }
        stage = 5;
        if (data.length > BACacheMaximumLogicalBytes) { reason = 10; BACacheRequire(NO); }
        if (data.length > BACacheMaximumBytes) {
            stage = 6;
            NSData *compressed = BACacheCompress(data, cancelled, &reason, &ioCode);
            BACacheRequire(compressed != nil);
            return compressed;
        }
        return data;
    } @catch (NSException *exception) {
        (void)exception; if (error) *error = BACacheCodecError(graph, stage, reason, encodedBytes, ioCode); return nil;
    }
}

BAAnalyticsReport *BAAnalyticsDecodeCachedReport(NSData *data, NSDate *now, NSError **error) {
    return BAAnalyticsDecodeCachedReportCancellable(data, now, error, ^BOOL { return NO; });
}
BAAnalyticsReport *BAAnalyticsDecodeCachedReportCancellable(NSData *data, NSDate *now, NSError **error, BOOL (^cancelled)(void)) {
    if (error) *error = nil;
    BACachedReportGraph *graph = nil;
    NSUInteger stage = 7, reason = 0, encodedBytes = [data isKindOfClass:NSData.class] ? data.length : 0;
    NSInteger ioCode = 0;
    @try {
        if (cancelled()) { reason = 3; BACacheRequire(NO); }
        if (![data isKindOfClass:NSData.class] || !data.length || data.length > BACacheMaximumBytes) { reason = 10; BACacheRequire(NO); }
        BACacheRequire(BAReportValidDate(now) && fabs(now.timeIntervalSince1970) <= 1e12);
        NSData *logical = data;
        if (data.length >= sizeof BACacheCompressedMagic && !memcmp(data.bytes, BACacheCompressedMagic, sizeof BACacheCompressedMagic)) {
            stage = 8;
            logical = BACacheInflate(data, cancelled, &reason, &ioCode);
            BACacheRequire(logical != nil);
            encodedBytes = logical.length;
        }
        stage = 9;
        NSPropertyListFormat format = 0;
        NSError *parsingError = nil;
        NSDictionary *root = [NSPropertyListSerialization propertyListWithData:logical options:NSPropertyListImmutable format:&format error:&parsingError];
        ioCode = parsingError.code;
        BACacheRequire(format == NSPropertyListBinaryFormat_v1_0);
        stage = 10;
        BACacheKeys(root, @[@"version", @"generatedAt", @"sequence", @"profile", @"metadata", @"families", @"objects"]);
        BACacheRequire(BACacheInteger(root[@"version"], 1) && [root[@"version"] integerValue] == 1 && BAReportValidDate(root[@"generatedAt"]) &&
            fabs([root[@"generatedAt"] timeIntervalSince1970]) <= 1e12 &&
            BACacheNumber(root[@"sequence"]) && [root[@"sequence"] doubleValue] >= 0 &&
            strchr("cCsSiIlLqQ", [root[@"sequence"] objCType][0]) != NULL &&
            BACacheString(root[@"profile"]) && [root[@"profile"] length]);
        NSTimeInterval age = [now timeIntervalSinceDate:root[@"generatedAt"]];
        BACacheRequire(isfinite(age) && age >= 0 && age <= BACacheMaximumAge);
        NSArray *nodes = root[@"objects"];
        BACacheRequire([nodes isKindOfClass:NSArray.class] && nodes.count <= 240000);
        graph = [BACachedReportGraph new]; graph.generatedAt = root[@"generatedAt"];
        graph.cancelled = cancelled;
        graph.nodes = [nodes mutableCopy];
        stage = 11;
        for (id node in nodes) {
            if (cancelled()) { reason = 3; BACacheRequire(NO); }
            BACacheRequire([node isKindOfClass:NSDictionary.class] && BACacheString(node[@"kind"]));
            [graph countKind:node[@"kind"]]; [graph.decodedObjects addObject:NSNull.null];
        }
        NSDictionary *metadata = [graph decodeValue:root[@"metadata"] depth:0];
        NSDictionary *families = [graph decodeValue:root[@"families"] depth:0];
        BACacheRequire(BACacheTypedMap(metadata, BAAnalyticsFieldMetadata.class) && BACacheTypedMap(families, BAAnalyticsFamilyReport.class));
        // Unreferenced nodes must also be valid; malformed tail data is not ignored.
        for (NSUInteger i = 0; i < nodes.count; i++) {
            if ((i & 63) == 0 && cancelled()) { reason = 3; BACacheRequire(NO); }
            (void)[graph decodeNode:i depth:0];
        }
        BAAnalyticsReport *report = [[BAAnalyticsReport alloc] initWithSequenceNumber:[root[@"sequence"] unsignedLongLongValue]
            generatedAt:root[@"generatedAt"] sourceProfileIdentifier:root[@"profile"] fieldMetadata:metadata familyReports:families error:nil];
        stage = 12;
        if (!BACacheEligibleReport(report)) { reason = 8; BACacheRequire(NO); }
        return [report reportByMarkingCached];
    } @catch (NSException *exception) {
        (void)exception; if (error) *error = BACacheCodecError(graph, stage, reason, encodedBytes, ioCode); return nil;
    }
}
