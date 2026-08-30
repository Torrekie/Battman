// Host/test-only construction surface. Plug-ins receive immutable instances.
#import "../Public/BAAnalyticsMetricSnapshot.h"

NS_ASSUME_NONNULL_BEGIN
@interface BAAnalyticsMetricPoint (BAAnalyticsHostConstruction)
- (instancetype)initWithTimestamp:(NSDate *)timestamp value:(double)value;
@end

@interface BAAnalyticsMetricSnapshot (BAAnalyticsHostConstruction)
// Missing/non-finite values are discarded while the host builds a snapshot.
- (instancetype)initWithSequenceNumber:(uint64_t)sequenceNumber
						  timestamp:(NSDate *)timestamp
							 values:(nullable NSDictionary<NSString *, NSNumber *> *)values
						  histories:(nullable NSDictionary<NSString *, NSArray<BAAnalyticsMetricPoint *> *> *)histories;
@end
NS_ASSUME_NONNULL_END
