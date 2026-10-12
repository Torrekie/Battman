#import "BAAnalyticsSessionCanvasCard.h"
#import "BAAnalyticsDischargeCanvasCard.h"
#import "BAAnalyticsEventsCanvasCard.h"
#import "BAAnalyticsPathCanvasCard.h"

NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateProcessCanvasCards(void) {
    return @[[BAAnalyticsSessionCanvasCard new], [BAAnalyticsDischargeCanvasCard new],
        [BAAnalyticsEventsCanvasCard new], [BAAnalyticsPathCanvasCard new]];
}
