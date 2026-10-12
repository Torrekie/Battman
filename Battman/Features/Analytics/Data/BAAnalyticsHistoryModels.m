#import "BAAnalyticsHistoryModels.h"
#import <math.h>

static BOOL BAHistoryValidDate(id date) {
	return [date isKindOfClass:[NSDate class]] && isfinite([date timeIntervalSince1970]);
}

static BOOL BAHistoryValidRange(NSDate *start, NSDate *end) {
	return BAHistoryValidDate(start) && BAHistoryValidDate(end) &&
		isfinite([end timeIntervalSinceDate:start]) && [end compare:start] != NSOrderedAscending;
}

static NSString *BAHistoryString(id value) {
	return [value isKindOfClass:[NSString class]] ? [value copy] : @"";
}

static NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *BAHistoryMetadata(id metadata) {
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	if ([metadata isKindOfClass:[NSDictionary class]]) {
		[metadata enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if ([key isKindOfClass:[NSString class]] && [key length] &&
				[value isKindOfClass:[BAAnalyticsFieldMetadata class]])
				result[[key copy]] = [value copy];
		}];
	}
	return [result copy];
}

static NSArray *BAHistoryObjects(id objects, Class objectClass) {
	NSMutableArray *result = [NSMutableArray array];
	if ([objects isKindOfClass:[NSArray class]]) {
		for (id object in objects) {
			if ([object isKindOfClass:objectClass])
				[result addObject:[object copy]];
		}
	}
	return [result copy];
}

static BAAnalyticsObservedState BAHistoryState(BAAnalyticsObservedState state) {
	return state >= BAAnalyticsObservedStateUnknown && state <= BAAnalyticsObservedStateFull
		? state : BAAnalyticsObservedStateUnknown;
}

@implementation BAAnalyticsFieldMetadata

- (instancetype)initWithSourceTable:(NSString *)sourceTable sourceColumn:(NSString *)sourceColumn
							 unit:(NSString *)unit decoderIdentifier:(NSString *)decoderIdentifier
					unitValidated:(BOOL)unitValidated {
	self = [super init];
	if (!self)
		return nil;
	_sourceTable = BAHistoryString(sourceTable);
	_sourceColumn = BAHistoryString(sourceColumn);
	_unit = BAHistoryString(unit);
	_decoderIdentifier = BAHistoryString(decoderIdentifier);
	_unitValidated = unitValidated && _sourceTable.length && _sourceColumn.length &&
		_unit.length && _decoderIdentifier.length;
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsObservation

- (instancetype)initWithIdentifier:(NSString *)identifier timestamp:(NSDate *)timestamp
					 sourceTimestamp:(double)sourceTimestamp timestampValidated:(BOOL)timestampValidated
							 values:(NSDictionary<NSString *, NSNumber *> *)values
						fieldMetadata:(NSDictionary<NSString *, BAAnalyticsFieldMetadata *> *)fieldMetadata {
	self = [super init];
	if (!self)
		return nil;
	if (![identifier isKindOfClass:[NSString class]] || !identifier.length || !BAHistoryValidDate(timestamp))
		return nil;
	_identifier = [identifier copy];
	_timestamp = [timestamp copy];
	_sourceTimestamp = sourceTimestamp;
	_timestampValidated = timestampValidated && isfinite(sourceTimestamp);
	_fieldMetadata = BAHistoryMetadata(fieldMetadata);
	NSMutableDictionary *safeValues = [NSMutableDictionary dictionary];
	if (_timestampValidated && [values isKindOfClass:[NSDictionary class]]) {
		[values enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSNumber class]] ||
				!isfinite([value doubleValue]))
				return;
			BAAnalyticsFieldMetadata *metadata = self->_fieldMetadata[key];
			if (metadata.unitValidated)
				safeValues[[key copy]] = [value copy];
		}];
	}
	_values = [safeValues copy];
	return self;
}

- (NSNumber *)valueForMetricIdentifier:(NSString *)metricIdentifier {
	return [metricIdentifier isKindOfClass:[NSString class]] ? _values[metricIdentifier] : nil;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsHistoryInterval

- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate
				 startObservation:(BAAnalyticsObservation *)startObservation
				   endObservation:(BAAnalyticsObservation *)endObservation
			coveredMetricIdentifiers:(NSSet<NSString *> *)coveredMetricIdentifiers
							 state:(BAAnalyticsObservedState)state {
	self = [super init];
	if (!self)
		return nil;
	if (!BAHistoryValidRange(startDate, endDate) ||
		![startObservation isKindOfClass:[BAAnalyticsObservation class]] ||
		![endObservation isKindOfClass:[BAAnalyticsObservation class]] ||
		!BAHistoryValidRange(startObservation.timestamp, endObservation.timestamp))
		return nil;
	// A clipped sampled pair cannot assert coverage outside either sampled boundary.
	_startDate = [[startDate laterDate:startObservation.timestamp] copy];
	_endDate = [[endDate earlierDate:endObservation.timestamp] copy];
	if (!BAHistoryValidRange(_startDate, _endDate))
		return nil;
	_startObservation = [startObservation copy];
	_endObservation = [endObservation copy];
	NSMutableSet *metrics = [NSMutableSet set];
	if (startObservation.timestampValidated && endObservation.timestampValidated &&
		[coveredMetricIdentifiers isKindOfClass:[NSSet class]]) {
		for (id metric in coveredMetricIdentifiers) {
			if (![metric isKindOfClass:[NSString class]])
				continue;
			BAAnalyticsFieldMetadata *firstMetadata = startObservation.fieldMetadata[metric];
			BAAnalyticsFieldMetadata *lastMetadata = endObservation.fieldMetadata[metric];
			if ([startObservation valueForMetricIdentifier:metric] &&
				[endObservation valueForMetricIdentifier:metric] &&
				firstMetadata.unitValidated && lastMetadata.unitValidated &&
				[firstMetadata.unit isEqualToString:lastMetadata.unit] &&
				[firstMetadata.decoderIdentifier isEqualToString:lastMetadata.decoderIdentifier] &&
				[firstMetadata.sourceTable isEqualToString:lastMetadata.sourceTable] &&
				[firstMetadata.sourceColumn isEqualToString:lastMetadata.sourceColumn])
				[metrics addObject:[metric copy]];
		}
	}
	_coveredMetricIdentifiers = [metrics copy];
	_state = startObservation.timestampValidated && endObservation.timestampValidated
		? BAHistoryState(state) : BAAnalyticsObservedStateUnknown;
	_duration = [_endDate timeIntervalSinceDate:_startDate];
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsHistoryGap

- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate reason:(NSString *)reason {
	self = [super init];
	if (!self)
		return nil;
	if (!BAHistoryValidRange(startDate, endDate))
		return nil;
	_startDate = [startDate copy];
	_endDate = [endDate copy];
	_reason = BAHistoryString(reason);
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsStateTransition

- (instancetype)initWithIdentifier:(NSString *)identifier earliestDate:(NSDate *)earliestDate
						 latestDate:(NSDate *)latestDate previousState:(BAAnalyticsObservedState)previousState
							 nextState:(BAAnalyticsObservedState)nextState reasonCode:(NSNumber *)reasonCode {
	self = [super init];
	if (!self)
		return nil;
	if (![identifier isKindOfClass:[NSString class]] || !identifier.length ||
		!BAHistoryValidRange(earliestDate, latestDate))
		return nil;
	_identifier = [identifier copy];
	_earliestDate = [earliestDate copy];
	_latestDate = [latestDate copy];
	_previousState = BAHistoryState(previousState);
	_nextState = BAHistoryState(nextState);
	if ([reasonCode isKindOfClass:[NSNumber class]] && isfinite(reasonCode.doubleValue))
		_reasonCode = [reasonCode copy];
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end

@implementation BAAnalyticsHistorySession

- (instancetype)initWithIdentifier:(NSString *)identifier kind:(NSString *)kind
						 startDate:(NSDate *)startDate endDate:(NSDate *)endDate
					startBoundaryKnown:(BOOL)startBoundaryKnown endBoundaryKnown:(BOOL)endBoundaryKnown
						observations:(NSArray<BAAnalyticsObservation *> *)observations
							intervals:(NSArray<BAAnalyticsHistoryInterval *> *)intervals
								 gaps:(NSArray<BAAnalyticsHistoryGap *> *)gaps
							transitions:(NSArray<BAAnalyticsStateTransition *> *)transitions {
	self = [super init];
	if (!self)
		return nil;
	if (![identifier isKindOfClass:[NSString class]] || !identifier.length ||
		![kind isKindOfClass:[NSString class]] ||
		(![kind isEqualToString:@"connected"] && ![kind isEqualToString:@"unplugged"]) ||
		!BAHistoryValidRange(startDate, endDate))
		return nil;
	_identifier = [identifier copy];
	_kind = [kind copy];
	_startDate = [startDate copy];
	_endDate = [endDate copy];
	_startBoundaryKnown = startBoundaryKnown;
	_endBoundaryKnown = endBoundaryKnown;
	_observations = [BAHistoryObjects(observations, [BAAnalyticsObservation class])
		sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsObservation *first, BAAnalyticsObservation *last) {
			NSComparisonResult order = [first.timestamp compare:last.timestamp];
			return order == NSOrderedSame ? [first.identifier compare:last.identifier] : order;
		}];
	_intervals = BAHistoryObjects(intervals, [BAAnalyticsHistoryInterval class]);
	_gaps = BAHistoryObjects(gaps, [BAAnalyticsHistoryGap class]);
	_transitions = BAHistoryObjects(transitions, [BAAnalyticsStateTransition class]);
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	return self;
}

@end
