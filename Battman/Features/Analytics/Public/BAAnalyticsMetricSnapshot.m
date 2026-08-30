//
//  BAAnalyticsMetricSnapshot.m
//  Battman Analytics SDK
//


#import "../Data/BAAnalyticsMetricSnapshotInternal.h"

#import <math.h>

@implementation BAAnalyticsMetricPoint

- (instancetype)initWithTimestamp:(NSDate *)timestamp value:(double)value {
	self = [super init];
	if (!self)
		return nil;
	_timestamp = [timestamp copy] ?: [NSDate date];
	_value = value;
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

@end

@implementation BAAnalyticsMetricSnapshot

- (instancetype)initWithSequenceNumber:(uint64_t)sequenceNumber
						  timestamp:(NSDate *)timestamp
							 values:(NSDictionary<NSString *, NSNumber *> *)values
						  histories:(NSDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *)histories {
	self = [super init];
	if (!self)
		return nil;

	_sequenceNumber = sequenceNumber;
	_timestamp = [timestamp copy] ?: [NSDate date];

	NSMutableDictionary<NSString *, NSNumber *> *safeValues = [NSMutableDictionary dictionary];
	[values enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
		(void)stop;
		if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSNumber class]])
			return;
		double numericValue = [value doubleValue];
		if (!isfinite(numericValue))
			return;
		safeValues[[key copy]] = [value copy];
	}];
	_values = [safeValues copy];

	NSMutableDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *safeHistories = [NSMutableDictionary dictionary];
	[histories enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
		(void)stop;
		if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSArray class]])
			return;
		NSMutableArray<BAAnalyticsMetricPoint *> *safePoints = [NSMutableArray array];
		for (id point in value) {
			if (![point isKindOfClass:[BAAnalyticsMetricPoint class]])
				continue;
			BAAnalyticsMetricPoint *metricPoint = (BAAnalyticsMetricPoint *)point;
			if (!isfinite(metricPoint.value))
				continue;
			[safePoints addObject:metricPoint];
		}
		safeHistories[[key copy]] = [safePoints copy];
	}];
	_histories = [safeHistories copy];
	return self;
}

- (NSNumber *)valueForMetricIdentifier:(NSString *)metricIdentifier {
	return self.values[metricIdentifier];
}

- (NSArray<BAAnalyticsMetricPoint *> *)historyForMetricIdentifier:(NSString *)metricIdentifier {
	NSArray<BAAnalyticsMetricPoint *> *history = self.histories[metricIdentifier];
	return history ?: @[];
}

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

@end
