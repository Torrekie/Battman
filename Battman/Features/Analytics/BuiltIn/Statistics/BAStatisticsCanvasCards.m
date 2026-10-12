#import "BAStatisticsCanvasCards.h"
#import "BAStatisticsDrawing.h"

NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateStatisticalCanvasCards(void) {
    return @[BAAnalyticsCreateDwellCanvasCard(), BAAnalyticsCreateCompareCanvasCard(), BAAnalyticsCreateRhythmCanvasCard()];
}
