// Synthetic, unit-validated observations for Simulator presentation checks only.
#import "../../Battman/Features/Analytics/Data/BAAnalyticsHistoryService.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricService.h"
@interface BAFixtureHistoryService : BAAnalyticsHistoryService
@property (nonatomic, strong) BAAnalyticsReport *fixtureReport;
- (void)publishFixture;
@end
@interface BAFixtureMetricService : BAAnalyticsMetricService
@property (nonatomic, strong) BAAnalyticsMetricSnapshot *fixtureSnapshot;
- (instancetype)init;
@end
FOUNDATION_EXPORT BAAnalyticsReport *BAFixtureReport(NSString *scenario);
FOUNDATION_EXPORT BAAnalyticsMetricSnapshot *BAFixtureSnapshot(BOOL unavailable);
