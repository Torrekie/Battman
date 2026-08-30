//
//  BAAnalyticsMetricService.h
//  Battman
//


#import <Foundation/Foundation.h>

#import "../Public/BAAnalyticsMetricSnapshot.h"

NS_ASSUME_NONNULL_BEGIN

@protocol BAAnalyticsMetricSource <NSObject>
// Called serially on a private worker queue. Missing keys mean unavailable.
- (NSDictionary<NSString *, NSNumber *> *)readAnalyticsMetricValues;
@end

@class BAAnalyticsMetricService;

@protocol BAAnalyticsMetricServiceSubscriber <NSObject>
- (void)analyticsMetricService:(BAAnalyticsMetricService *)service
		 didPublishSnapshot:(BAAnalyticsMetricSnapshot *)snapshot;
@end

@interface BAAnalyticsMetricService : NSObject
@property (nonatomic, strong, readonly, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@property (nonatomic, readonly, getter=isPolling) BOOL polling;
@property (nonatomic, readonly) NSUInteger subscriberCount;

- (instancetype)initWithSource:(id<BAAnalyticsMetricSource>)source;
- (instancetype)initWithSource:(id<BAAnalyticsMetricSource>)source
				 sampleInterval:(NSTimeInterval)sampleInterval
			 maxHistoryPoints:(NSUInteger)maxHistoryPoints NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Subscription and application-state methods must be called on the main
// thread. Sampling exists only while the app is active and at least one weak
// subscriber remains registered.
- (void)addSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber;
- (void)removeSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber;
- (void)setApplicationActive:(BOOL)applicationActive;
- (void)refreshNow;
- (void)handleMemoryPressure;
@end

NS_ASSUME_NONNULL_END
