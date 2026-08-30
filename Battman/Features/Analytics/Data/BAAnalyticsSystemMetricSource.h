//
//  BAAnalyticsSystemMetricSource.h
//  Battman
//


#import <Foundation/Foundation.h>

#import "BAAnalyticsMetricService.h"

#include <math.h>

NS_ASSUME_NONNULL_BEGIN

// Internal deterministic seam shared by the system source and Phase 2 tests.
// get_temperature() reserves exactly -1.0f for read failure.
static inline void BAAnalyticsRecordTemperatureMetric(NSMutableDictionary<NSString *, NSNumber *> *values, float temperature) {
	if (temperature == -1.0f || !isfinite(temperature) || temperature < -50.0f || temperature > 120.0f) {
		[values removeObjectForKey:BAAnalyticsMetricAverageTemperatureCelsius];
		return;
	}
	values[BAAnalyticsMetricAverageTemperatureCelsius] = @(temperature);
}

@interface BAAnalyticsSystemMetricSource : NSObject <BAAnalyticsMetricSource>
@end

NS_ASSUME_NONNULL_END
