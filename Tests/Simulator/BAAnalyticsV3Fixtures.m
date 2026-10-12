#import "BAAnalyticsV3Fixtures.h"
#import "../../Battman/Features/Analytics/Data/BAAnalyticsMetricSnapshotInternal.h"
#include <math.h>
@interface BAFixtureHistoryService ()
@property (nonatomic, strong) NSHashTable *fixtureSubscribers;
@end
@implementation BAFixtureHistoryService
- (instancetype)init { if ((self=[super initWithDatabaseURL:nil])) _fixtureSubscribers=[NSHashTable weakObjectsHashTable]; return self; }
- (BAAnalyticsReport *)latestReport { return self.fixtureReport; }
- (NSUInteger)subscriberCount { return self.fixtureSubscribers.count; }
- (BOOL)isPolling { return NO; }
- (void)addSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber { [self.fixtureSubscribers addObject:subscriber]; if(self.fixtureReport) [subscriber analyticsHistoryService:self didPublishReport:self.fixtureReport]; }
- (void)removeSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber { [self.fixtureSubscribers removeObject:subscriber]; }
- (void)setApplicationActive:(BOOL)active { (void)active; }
- (void)refreshNow { [self publishFixture]; }
- (void)handleMemoryPressure { }
- (void)publishFixture { for(id<BAAnalyticsHistoryServiceSubscriber> s in self.fixtureSubscribers.allObjects) [s analyticsHistoryService:self didPublishReport:self.fixtureReport]; }
@end
@interface BAFixtureSource : NSObject <BAAnalyticsMetricSource>
@end
@implementation BAFixtureSource
- (NSDictionary *)readAnalyticsMetricValues { NSAssert(NO,@"Fixture must never poll"); return @{}; }
@end
@interface BAFixtureMetricService ()
@property (nonatomic, strong) NSHashTable *fixtureSubscribers;
@end
@implementation BAFixtureMetricService
- (instancetype)init { if((self=[super initWithSource:[BAFixtureSource new] sampleInterval:60 maxHistoryPoints:64])) _fixtureSubscribers=[NSHashTable weakObjectsHashTable]; return self; }
- (BAAnalyticsMetricSnapshot *)latestSnapshot { return self.fixtureSnapshot; }
- (NSUInteger)subscriberCount { return self.fixtureSubscribers.count; }
- (BOOL)isPolling { return NO; }
- (void)addSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber { [self.fixtureSubscribers addObject:subscriber]; if(self.fixtureSnapshot) [subscriber analyticsMetricService:self didPublishSnapshot:self.fixtureSnapshot]; }
- (void)removeSubscriber:(id<BAAnalyticsMetricServiceSubscriber>)subscriber { [self.fixtureSubscribers removeObject:subscriber]; }
- (void)setApplicationActive:(BOOL)active { (void)active; }
- (void)refreshNow { for(id<BAAnalyticsMetricServiceSubscriber> s in self.fixtureSubscribers.allObjects) [s analyticsMetricService:self didPublishSnapshot:self.fixtureSnapshot]; }
- (void)handleMemoryPressure { }
@end
static NSString *BAFixtureUnit(NSString *key) {
    if([key hasSuffix:@"percent"])return @"%";
    if([key hasSuffix:@"celsius"])return @"°C";
    if([key hasSuffix:@"milliamps"])return @"mA";
    if([key hasSuffix:@"millivolts"])return @"mV";
    if([key hasSuffix:@"watts"])return @"W";
    if([key hasSuffix:@"milliamp-hours"])return @"mAh";
    if([key isEqualToString:BAAnalyticsHistoryExternalConnected]||[key isEqualToString:BAAnalyticsHistoryIsCharging]||[key isEqualToString:BAAnalyticsHistoryFullyCharged])return @"bool";
    return @"count";
}
static BAAnalyticsObservation *BAFixtureObservation(NSString *identifier, NSDate *date, NSDictionary *values) {
    NSMutableDictionary *metadata=[NSMutableDictionary dictionary];
    for(NSString *key in values)metadata[key]=[[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"synthetic.fixture" sourceColumn:key unit:BAFixtureUnit(key) decoderIdentifier:@"simulator.fixture.v3" unitValidated:YES];
    return [[BAAnalyticsObservation alloc] initWithIdentifier:identifier timestamp:date sourceTimestamp:date.timeIntervalSince1970 timestampValidated:YES values:values fieldMetadata:metadata];
}
static BAAnalyticsHistorySession *BAFixtureSession(NSString *identifier, NSDate *start, NSUInteger count, NSTimeInterval step, BOOL unplugged, BOOL partial) {
    NSMutableArray *observations=[NSMutableArray array], *intervals=[NSMutableArray array], *gaps=[NSMutableArray array], *transitions=[NSMutableArray array];
    for(NSUInteger i=0;i<count;i++) {
        double fraction=(double)i/(count-1),soc=unplugged?88-42*fraction:18+66*fraction;
        double current=unplugged?-600-250*sin(i*.7):2000*(1-.72*fraction);
        BAAnalyticsObservedState state=unplugged?BAAnalyticsObservedStateUnplugged:((i>=count/2&&i<count/2+2)?BAAnalyticsObservedStateConnectedNotCharging:BAAnalyticsObservedStateCharging);
        if(state==BAAnalyticsObservedStateConnectedNotCharging)current=-90;
        NSDictionary *values=@{BAAnalyticsHistorySOCPercent:@(soc),BAAnalyticsHistoryTemperatureCelsius:@(29+8*sin(fraction*3.1)),BAAnalyticsHistoryCurrentMilliamps:@(current),BAAnalyticsHistoryVoltageMillivolts:@(3750+430*fraction),BAAnalyticsHistoryBatteryPowerWatts:@(current*.004),BAAnalyticsHistoryExternalConnected:@(!unplugged),BAAnalyticsHistoryIsCharging:@(state==BAAnalyticsObservedStateCharging),BAAnalyticsHistoryFullyCharged:@NO,BAAnalyticsHistoryInputPowerWatts:@(unplugged?0:18.5-5*fraction),BAAnalyticsHistoryInputVoltageMillivolts:@(9000),BAAnalyticsHistoryInputCurrentMilliamps:@(2055-550*fraction),BAAnalyticsHistoryPowerBudgetWatts:@20,BAAnalyticsHistoryPowerTargetWatts:@18,BAAnalyticsHistoryCellVoltage0Millivolts:@(3750+430*fraction),BAAnalyticsHistoryCellVoltage1Millivolts:@(3762+426*fraction),BAAnalyticsHistoryCellVoltage2Millivolts:@(3768+423*fraction)};
        BAAnalyticsObservation *obs=BAFixtureObservation([identifier stringByAppendingFormat:@".%lu",(unsigned long)i],[start dateByAddingTimeInterval:step*i],values);
        if(i) {
            BAAnalyticsObservation *previous=observations.lastObject;
            if(partial&&i==count/3) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:previous.timestamp endDate:obs.timestamp reason:@"Synthetic sampling gap"]];
            else [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:previous.timestamp endDate:obs.timestamp startObservation:previous endObservation:obs coveredMetricIdentifiers:[NSSet setWithArray:values.allKeys] state:state]];
            BOOL previousCharging=[previous.values[BAAnalyticsHistoryIsCharging] boolValue];
            if(!unplugged&&previousCharging!=(state==BAAnalyticsObservedStateCharging)) [transitions addObject:[[BAAnalyticsStateTransition alloc] initWithIdentifier:[identifier stringByAppendingFormat:@".transition.%lu",(unsigned long)i] earliestDate:previous.timestamp latestDate:obs.timestamp previousState:previousCharging?BAAnalyticsObservedStateCharging:BAAnalyticsObservedStateConnectedNotCharging nextState:state reasonCode:@17]];
        }
        [observations addObject:obs];
    }
    return [[BAAnalyticsHistorySession alloc] initWithIdentifier:identifier kind:unplugged?@"unplugged":@"connected" startDate:start endDate:((BAAnalyticsObservation *)observations.lastObject).timestamp startBoundaryKnown:!partial endBoundaryKnown:!partial observations:observations intervals:intervals gaps:gaps transitions:transitions];
}
static BAAnalyticsHistoryWindow *BAFixtureWindow(NSArray *observations,NSArray *intervals,NSArray *gaps,NSDate *start,NSDate *end) {
    NSMutableDictionary *coverage=[NSMutableDictionary dictionary]; double total=0;
    for(BAAnalyticsHistoryInterval *interval in intervals) { total+=interval.duration; for(NSString *metric in interval.coveredMetricIdentifiers) coverage[metric]=@([coverage[metric] doubleValue]+interval.duration); }
    NSTimeInterval duration=[end timeIntervalSinceDate:start];
    return [[BAAnalyticsHistoryWindow alloc] initWithStartDate:start endDate:end observations:observations intervals:intervals gaps:gaps coverageMetricIdentifiers:[NSSet setWithArray:coverage.allKeys] coveredDuration:MIN(duration,total) missingDuration:MAX(0,duration-total) coverageSecondsByMetric:coverage];
}
BAAnalyticsReport *BAFixtureReport(NSString *scenario) {
    BOOL partial=[scenario isEqualToString:@"partial"], unavailable=[scenario isEqualToString:@"unavailable"];
    NSDate *now=[NSDate date]; NSMutableDictionary *families=[NSMutableDictionary dictionary];
    BAAnalyticsHistorySession *session=BAFixtureSession(@"charge.current",[now dateByAddingTimeInterval:-3300],23,150,NO,partial);
    BAAnalyticsHistorySession *discharge=BAFixtureSession(@"discharge.current",[now dateByAddingTimeInterval:-7200],25,300,YES,partial);
    NSMutableArray *sessions=[NSMutableArray array];
    for(NSUInteger day=0;day<12;day++) [sessions addObject:BAFixtureSession([NSString stringWithFormat:@"charge.%lu",(unsigned long)day],[now dateByAddingTimeInterval:-86400.0*(day+1)],23,130+day*7,NO,NO)];
    for(NSString *family in @[BAAnalyticsFamilyLive,BAAnalyticsFamilyCapacity,BAAnalyticsFamilyCells,BAAnalyticsFamilySession,BAAnalyticsFamilyDischarge,BAAnalyticsFamilyEvents,BAAnalyticsFamilyPath,BAAnalyticsFamilyDwell,BAAnalyticsFamilyCompare,BAAnalyticsFamilyRhythm]) {
        NSMutableArray *obs=[NSMutableArray array],*intervals=[NSMutableArray array],*gaps=[NSMutableArray array]; NSMutableDictionary *payload=[NSMutableDictionary dictionary]; NSDate *start=nil,*end=now;
        BAAnalyticsHistorySession *selected=[family isEqualToString:BAAnalyticsFamilyDischarge]?discharge:session;
        if([family isEqualToString:BAAnalyticsFamilyRhythm]||[family isEqualToString:BAAnalyticsFamilyDwell]) {
            NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; start=[[calendar startOfDayForDate:now] dateByAddingTimeInterval:-6*86400];
            for(NSUInteger i=0;i<169;i++) {
                NSDate *date=[start dateByAddingTimeInterval:3600*i]; if([date compare:now]==NSOrderedDescending)break;
                BOOL connected=(i%24<5); double soc=90-(i%24)*2.8;
                BAAnalyticsObservation *o=BAFixtureObservation([NSString stringWithFormat:@"hour.%lu",(unsigned long)i],date,@{BAAnalyticsHistorySOCPercent:@(soc),BAAnalyticsHistoryTemperatureCelsius:@(28+(i%24)*.3),BAAnalyticsHistoryExternalConnected:@(connected),BAAnalyticsHistoryIsCharging:@(connected)});
                if(obs.count) { BAAnalyticsObservation *previous=obs.lastObject; if(i%27==0||(partial&&i%9==0)) [gaps addObject:[[BAAnalyticsHistoryGap alloc] initWithStartDate:previous.timestamp endDate:date reason:@"Synthetic hourly gap"]]; else [intervals addObject:[[BAAnalyticsHistoryInterval alloc] initWithStartDate:previous.timestamp endDate:date startObservation:previous endObservation:o coveredMetricIdentifiers:[NSSet setWithArray:o.values.allKeys] state:connected?BAAnalyticsObservedStateCharging:BAAnalyticsObservedStateUnplugged]]; }
                [obs addObject:o];
            }
        } else if([family isEqualToString:BAAnalyticsFamilyCapacity]) {
            start=[now dateByAddingTimeInterval:-30*86400];
            for(NSUInteger i=0;i<=30;i++) [obs addObject:BAFixtureObservation([NSString stringWithFormat:@"capacity.%lu",(unsigned long)i],[start dateByAddingTimeInterval:i*86400],@{BAAnalyticsHistoryFullChargeCapacityMilliampHours:@(3650-i*1.4+8*sin(i)),BAAnalyticsHistoryDesignCapacityMilliampHours:@4000,BAAnalyticsHistoryCycleCount:@(310+i/3)})];
        } else if([family isEqualToString:BAAnalyticsFamilyCompare]) {
            start=[now dateByAddingTimeInterval:-30*86400]; payload[BAAnalyticsPayloadSessions]=sessions; for(BAAnalyticsHistorySession *s in sessions) [obs addObjectsFromArray:s.observations];
        } else {
            start=selected.startDate; end=selected.endDate; [obs addObjectsFromArray:selected.observations]; [intervals addObjectsFromArray:selected.intervals]; [gaps addObjectsFromArray:selected.gaps];
            payload[BAAnalyticsPayloadSelectedSession]=selected; payload[BAAnalyticsPayloadSessions]=@[selected]; payload[BAAnalyticsPayloadTransitions]=selected.transitions;
        }
        if(unavailable){[obs removeAllObjects];[intervals removeAllObjects];[gaps removeAllObjects];[payload removeAllObjects];}
        if(obs.lastObject)payload[BAAnalyticsPayloadLatestObservation]=obs.lastObject;
        BAAnalyticsHistoryWindow *window=BAFixtureWindow(obs,intervals,gaps,start,end);
        families[family]=[[BAAnalyticsFamilyReport alloc] initWithFamily:family availability:unavailable?BAAnalyticsReportAvailabilityUnavailable:(partial?BAAnalyticsReportAvailabilityPartial:BAAnalyticsReportAvailabilityReady) window:window payload:payload limitations:@[unavailable?@"Synthetic unavailable fields":@"Synthetic Simulator data; no device database or sensor access"]];
    }
    return [[BAAnalyticsReport alloc] initWithSequenceNumber:1 generatedAt:now sourceProfileIdentifier:@"synthetic.simulator.v3" fieldMetadata:session.observations.lastObject.fieldMetadata familyReports:families error:nil];
}
BAAnalyticsMetricSnapshot *BAFixtureSnapshot(BOOL unavailable) {
    NSDate *now=[NSDate date]; NSDictionary *values=unavailable?@{}:@{BAAnalyticsMetricStateOfChargePercent:@73,BAAnalyticsMetricBatteryHealthPercent:@91,BAAnalyticsMetricAverageTemperatureCelsius:@33.4,BAAnalyticsMetricAverageCurrentMilliamps:@1520,BAAnalyticsMetricVoltageMillivolts:@4075,BAAnalyticsMetricAveragePowerWatts:@6.19,BAAnalyticsMetricBatteryNetPowerWatts:@6.19,BAAnalyticsMetricCycleCount:@321,BAAnalyticsMetricFullChargeCapacityMilliampHours:@3640,BAAnalyticsMetricDesignCapacityMilliampHours:@4000,BAAnalyticsMetricRemainingCapacityMilliampHours:@2660,BAAnalyticsMetricExternalConnected:@YES,BAAnalyticsMetricIsCharging:@YES,BAAnalyticsMetricCellCount:@3,BAAnalyticsCellVoltageMetricIdentifier(0):@4075,BAAnalyticsCellVoltageMetricIdentifier(1):@4090,BAAnalyticsCellVoltageMetricIdentifier(2):@4100};
    NSMutableDictionary *histories=[NSMutableDictionary dictionary];
    for(NSString *metric in values) {NSMutableArray *points=[NSMutableArray array]; for(NSUInteger i=0;i<61;i++) { double v=[values[metric] doubleValue]; if([metric isEqualToString:BAAnalyticsMetricAverageTemperatureCelsius])v-=1.2*(1-i/60.0);else if([metric containsString:@"watts"])v+=.5*sin(i*.2);else if([metric containsString:@"milliamps"])v+=120*sin(i*.2);else if([metric containsString:@"cell-voltage"])v-=20*(1-i/60.0); [points addObject:[[BAAnalyticsMetricPoint alloc] initWithTimestamp:[now dateByAddingTimeInterval:-300.0+5*i] value:v]];} histories[metric]=points;}
    return [[BAAnalyticsMetricSnapshot alloc] initWithSequenceNumber:1 timestamp:now values:values histories:histories];
}
