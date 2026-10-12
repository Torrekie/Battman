#import <Foundation/Foundation.h>
#import "../BAStatisticsAnalysis.h"
#import "BAAnalyticsHistoryReader.h"
#include <assert.h>
#include <math.h>
#include <sqlite3.h>

static void near(double a,double b) {assert(fabs(a-b)<1e-6*MAX(1,fabs(b)));}
static NSDate *at(double seconds) {return [NSDate dateWithTimeIntervalSince1970:seconds];}
static NSDictionary *metadata(void) {
    NSMutableDictionary *fields=[NSMutableDictionary dictionary];
    for (NSString *key in @[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius,BAAnalyticsHistoryExternalConnected,BAAnalyticsHistoryFullChargeCapacityMilliampHours]) {
        NSString *unit=[key isEqual:BAAnalyticsHistorySOCPercent]?@"%":[key isEqual:BAAnalyticsHistoryTemperatureCelsius]?@"°C":[key isEqual:BAAnalyticsHistoryExternalConnected]?@"boolean":@"mAh";
        fields[key]=[[BAAnalyticsFieldMetadata alloc] initWithSourceTable:@"fixture" sourceColumn:key unit:unit decoderIdentifier:@"validated.fixture" unitValidated:YES];
    }
    return fields;
}
static BAAnalyticsObservation *observation(NSString *identifier,double time,NSDictionary *values) {
    return [[BAAnalyticsObservation alloc] initWithIdentifier:identifier timestamp:at(time) sourceTimestamp:time timestampValidated:YES values:values fieldMetadata:metadata()];
}
static BAAnalyticsHistoryInterval *pair(BAAnalyticsObservation *a,BAAnalyticsObservation *b,double start,double end,BAAnalyticsObservedState state) {
    NSMutableSet *fields=[NSMutableSet setWithArray:a.values.allKeys];[fields intersectSet:[NSSet setWithArray:b.values.allKeys]];
    return [[BAAnalyticsHistoryInterval alloc] initWithStartDate:at(start) endDate:at(end) startObservation:a endObservation:b coveredMetricIdentifiers:fields state:state];
}
static BAAnalyticsHistoryWindow *window(double start,double end,NSArray *observations,NSArray *intervals,NSArray *gaps) {
    return [[BAAnalyticsHistoryWindow alloc] initWithStartDate:at(start) endDate:at(end) observations:observations intervals:intervals gaps:gaps coverageMetricIdentifiers:[NSSet setWithObject:BAAnalyticsHistorySOCPercent] coveredDuration:0 missingDuration:0 coverageSecondsByMetric:@{}];
}
static void propertyList(NSDictionary *value) {
    NSError *error=nil;NSData *data=[NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    assert(data && !error);
}
static NSUInteger contextNodes(id value) {NSUInteger n=1;if ([value isKindOfClass:NSDictionary.class]) for (id item in [value allValues]) n+=contextNodes(item);else if ([value isKindOfClass:NSArray.class]) for (id item in value) n+=contextNodes(item);return n;}
static void boundedContextTest(void) {
    NSMutableArray *rows=[NSMutableArray array];NSString *longText=[@"x" stringByPaddingToLength:1500 withString:@"x" startingAtIndex:0];
    for (NSUInteger i=0;i<64;i++) [rows addObject:@{@"record":longText,@"minutes":@(i)}];
    NSDictionary *filters=@{BAAnalyticsHistorySOCPercent:@{@"minimum":@80,@"maximum":@100,@"includeMaximum":@YES}};
    NSDictionary *context=BAStatisticsBoundedDetailContext(@{@"validMinutes":@123,@"filters":filters,@"intervals":rows,@"limitations":@[longText]});
    assert(contextNodes(context)<=240);near([context[@"validMinutes"] doubleValue],123);assert([context[@"filters"] isEqual:filters]);assert([context[@"contextPreviewTruncated"] boolValue]);
    NSData *encoded=[NSPropertyListSerialization dataWithPropertyList:context format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];assert(encoded.length<=7800);
}
static void dwellTests(void) {
    BAAnalyticsObservation *a=observation(@"a",0,@{BAAnalyticsHistorySOCPercent:@0,BAAnalyticsHistoryTemperatureCelsius:@20,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *b=observation(@"b",100,@{BAAnalyticsHistorySOCPercent:@100,BAAnalyticsHistoryTemperatureCelsius:@40,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsHistoryInterval *interval=pair(a,b,20,80,BAAnalyticsObservedStateUnplugged);
    NSDictionary *result=BAStatisticsDwell(window(20,80,@[],@[interval,interval],@[]));
    near([result[@"socSeconds"] doubleValue],60);near([result[@"jointSeconds"] doubleValue],60);
    NSArray *bins=result[@"socBins"];
    near([bins[0][@"seconds"] doubleValue],0);near([bins[1][@"seconds"] doubleValue],20);near([bins[2][@"seconds"] doubleValue],20);near([bins[3][@"seconds"] doubleValue],20);near([bins[4][@"seconds"] doubleValue],0);
    assert([bins[4][@"context"][@"filters"][BAAnalyticsHistorySOCPercent][@"includeMaximum"] boolValue]);
    NSDictionary *span=[bins[1][@"context"][@"intervals"] firstObject];
    near([span[@"observedStartSOC"] doubleValue],0);near([span[@"observedEndSOC"] doubleValue],100);
    near([span[@"startSOC"] doubleValue],20);near([span[@"endSOC"] doubleValue],40);
    near([span[@"observedStartTemperatureCelsius"] doubleValue],20);near([span[@"observedEndTemperatureCelsius"] doubleValue],40);
    near([span[@"interpolatedStartTemperatureCelsius"] doubleValue],24);near([span[@"interpolatedEndTemperatureCelsius"] doubleValue],28);
    assert([span[@"SOCSource"][@"unit"] isEqual:@"%"] && [span[@"temperatureSource"][@"unit"] isEqual:@"°C"]);
    propertyList(result);
    BAAnalyticsObservation *c=observation(@"c",120,@{BAAnalyticsHistorySOCPercent:@100,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *d=observation(@"d",660,@{BAAnalyticsHistorySOCPercent:@100,BAAnalyticsHistoryExternalConnected:@0});
    result=BAStatisticsDwell(window(0,660,@[a,b,c,d],@[pair(a,b,0,100,BAAnalyticsObservedStateUnplugged),pair(c,d,120,660,BAAnalyticsObservedStateUnplugged)],@[[[BAAnalyticsHistoryGap alloc] initWithStartDate:at(100) endDate:at(120) reason:@"missing pair"]]));
    near([result[@"socSeconds"] doubleValue],640);near([result[@"missingSOCSeconds"] doubleValue],20);near([result[@"jointSeconds"] doubleValue],100);near([result[@"missingJointSeconds"] doubleValue],560);
    near([result[@"socBins"][4][@"seconds"] doubleValue],560);propertyList(result);
}
static BAAnalyticsHistorySession *session(NSString *identifier,double start,double minutes,BOOL complete) {
    // Exactly 3/4 of this trusted 10->90 pair crosses 20->80.
    double end=start+minutes*60/.75;
    BAAnalyticsObservation *a=observation([identifier stringByAppendingString:@"a"],start,@{BAAnalyticsHistorySOCPercent:@10,BAAnalyticsHistoryExternalConnected:@1,BAAnalyticsHistoryTemperatureCelsius:@20,BAAnalyticsHistoryFullChargeCapacityMilliampHours:@2000});
    BAAnalyticsObservation *b=observation([identifier stringByAppendingString:@"b"],(start+end)/2,@{BAAnalyticsHistorySOCPercent:@50,BAAnalyticsHistoryExternalConnected:@1,BAAnalyticsHistoryTemperatureCelsius:@32,BAAnalyticsHistoryFullChargeCapacityMilliampHours:@2100});
    BAAnalyticsObservation *c=observation([identifier stringByAppendingString:@"c"],end,@{BAAnalyticsHistorySOCPercent:@90,BAAnalyticsHistoryExternalConnected:@1,BAAnalyticsHistoryTemperatureCelsius:@40,BAAnalyticsHistoryFullChargeCapacityMilliampHours:@2050});
    return [[BAAnalyticsHistorySession alloc] initWithIdentifier:identifier kind:@"connected" startDate:a.timestamp endDate:c.timestamp startBoundaryKnown:complete endBoundaryKnown:complete observations:@[a,b,c] intervals:@[pair(a,b,start,(start+end)/2,BAAnalyticsObservedStateCharging),pair(b,c,(start+end)/2,end,BAAnalyticsObservedStateCharging)] gaps:@[] transitions:@[]];
}
static BAAnalyticsFamilyReport *comparisonReport(NSArray *sessions) {
    return [[BAAnalyticsFamilyReport alloc] initWithFamily:BAAnalyticsFamilyCompare availability:BAAnalyticsReportAvailabilityReady window:window(0,20000,@[],@[],@[]) payload:@{BAAnalyticsPayloadSessions:sessions} limitations:@[@"Candidates already limited to a recognized compatible segment"]];
}
static void comparisonTests(void) {
    NSMutableArray *sessions=[NSMutableArray array];double start=0;NSUInteger index=0;
    for (NSNumber *minutes in @[@1,@2,@3,@4,@10]) {BAAnalyticsHistorySession *s=session([NSString stringWithFormat:@"opaque-%lu",(unsigned long)index++],start,minutes.doubleValue,YES);[sessions addObject:s];start=s.endDate.timeIntervalSince1970+100;}
    [sessions addObject:session(@"partial",10000,2,NO)];
    NSDictionary *result=BAStatisticsComparison(comparisonReport(sessions));
    assert([result[@"n"] unsignedIntegerValue]==5 && [result[@"hasBox"] boolValue]);near([result[@"minimum"] doubleValue],1);near([result[@"median"] doubleValue],3);near([result[@"q1"] doubleValue],1.5);near([result[@"q3"] doubleValue],7);near([result[@"maximum"] doubleValue],10);
    assert([result[@"exclusionCounts"][@"incomplete-session-boundaries"] integerValue]==1);
    near([result[@"samples"][0][@"peakCelsius"] doubleValue],32); // 40°C lies outside the shared SOC range.
    propertyList(result);
    result=BAStatisticsComparison(comparisonReport([sessions subarrayWithRange:NSMakeRange(0,2)]));
    assert(![result[@"hasBox"] boolValue] && !result[@"q1"] && !result[@"q3"]);near([result[@"n"] doubleValue],2);
    BAAnalyticsHistorySession *good=sessions[0];BAAnalyticsHistoryInterval *first=good.intervals[0],*second=good.intervals[1];
    BAAnalyticsHistoryInterval *shortened=[[BAAnalyticsHistoryInterval alloc] initWithStartDate:[second.startDate dateByAddingTimeInterval:1] endDate:second.endDate startObservation:second.startObservation endObservation:second.endObservation coveredMetricIdentifiers:second.coveredMetricIdentifiers state:second.state];
    BAAnalyticsHistorySession *gapped=[[BAAnalyticsHistorySession alloc] initWithIdentifier:@"gap" kind:@"connected" startDate:good.startDate endDate:good.endDate startBoundaryKnown:YES endBoundaryKnown:YES observations:good.observations intervals:@[first,shortened] gaps:@[] transitions:@[]];
    result=BAStatisticsComparison(comparisonReport(@[gapped]));assert([result[@"n"] unsignedIntegerValue]==0);assert([result[@"exclusionCounts"][@"missing-trusted-pair"] integerValue]==1);
    result=BAStatisticsComparison(comparisonReport(@[good,good]));assert([result[@"n"] integerValue]==1);assert([result[@"exclusionCounts"][@"duplicate-session"] integerValue]==1);
}
static void readerComparisonTest(NSURL *directory) {
    NSURL *source=[directory URLByAppendingPathComponent:@"synthetic-reader.sqlite"];
    sqlite3 *database=NULL;
    assert(sqlite3_open(source.path.fileSystemRepresentation,&database)==SQLITE_OK);
    const double epoch=1700000000;
    @try {
        NSArray *schema=@[
            @"CREATE TABLE PLStorageOperator_EventForward_TimeOffset (ID INTEGER PRIMARY KEY,timestamp REAL,system REAL)",
            @"CREATE TABLE PLBatteryAgent_EventBackward_Battery (ID INTEGER PRIMARY KEY,timestamp REAL,Level REAL,ExternalConnected INTEGER,IsCharging INTEGER,FullyCharged INTEGER,PMUConfiguration INTEGER,DesignCapacity INTEGER DEFAULT 2200,ChemID INTEGER DEFAULT 10,GaugeResetCounter INTEGER DEFAULT 2,Voltage INTEGER DEFAULT 4000,InstantAmperage INTEGER,AppleRawMaxCapacity INTEGER,CycleCount INTEGER DEFAULT 12)",
            @"CREATE TABLE PLBatteryAgent_EventPoint_ChargingInfo (ID INTEGER PRIMARY KEY,timestamp REAL)",
            [NSString stringWithFormat:@"INSERT INTO PLStorageOperator_EventForward_TimeOffset VALUES (1,%.0f,0)",epoch-3600],
        ];
        for (NSString *statement in schema) assert(sqlite3_exec(database,statement.UTF8String,NULL,NULL,NULL)==SQLITE_OK);
        NSMutableArray *rows=[NSMutableArray array];
        [rows addObject:@[@0,@18,@0]];
        [rows addObject:@[@20,@18,@1]];
        for (NSUInteger index=0;index<=12;index++) [rows addObject:@[@(80+index*60),@(20+index*5),@1]];
        [rows addObjectsFromArray:@[@[@860,@85,@1],@[@880,@84,@0],@[@900,@83,@0],@[@920,@19,@1]]];
        NSUInteger identifier=0;
        for (NSArray<NSNumber *> *row in rows) {
            identifier++;
            BOOL connected=row[2].boolValue;
            NSString *statement=[NSString stringWithFormat:@"INSERT INTO PLBatteryAgent_EventBackward_Battery (ID,timestamp,Level,ExternalConnected,IsCharging,FullyCharged,PMUConfiguration,InstantAmperage,AppleRawMaxCapacity) VALUES (%lu,%.0f,%@,%d,%d,0,%lu,%d,%lu)",
                (unsigned long)identifier,epoch+row[0].doubleValue,row[1],connected,connected,
                (unsigned long)(identifier*200),connected?1200:-100,(unsigned long)(2100+identifier%2)];
            assert(sqlite3_exec(database,statement.UTF8String,NULL,NULL,NULL)==SQLITE_OK);
        }
    } @finally {sqlite3_close(database);}
    @try {
        BAAnalyticsReport *report=BAAnalyticsReadHistoryReport(source,at(epoch+1000),1,^BOOL{return NO;});
        assert(!report.error && [report.sourceProfileIdentifier isEqual:@"powerlog.ios-battery.v1"]);
        BAAnalyticsFamilyReport *family=report.familyReports[BAAnalyticsFamilyCompare];
        NSDictionary *result=BAStatisticsComparison(family);
        assert([result[@"n"] unsignedIntegerValue]==1 && ![result[@"hasBox"] boolValue]);
        near([result[@"median"] doubleValue],12);
        NSDictionary *sample=[result[@"samples"] firstObject];
        near([sample[@"startDate"] timeIntervalSince1970],epoch+80);
        near([sample[@"endDate"] timeIntervalSince1970],epoch+800);
        assert([sample[@"context"][@"completeBoundaries"] boolValue]);
        assert([result[@"exclusionCounts"][@"incomplete-session-boundaries"] unsignedIntegerValue]==1);
        assert(!sample[@"peakCelsius"]); // No historical temperature units were verified.
        propertyList(result);
    } @finally {assert([NSFileManager.defaultManager removeItemAtURL:source error:NULL]);}
}
static NSDate *date(NSString *text) {NSDateFormatter *f=[NSDateFormatter new];f.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];f.dateFormat=@"yyyy-MM-dd HH:mm:ss Z";return [f dateFromString:text];}
static void calendarTest(NSString *startText,NSString *endText,double elapsed,NSUInteger expectedHours,NSUInteger expectedLastDayHours) {
    NSDate *start=date(startText),*end=date(endText);double aTime=start.timeIntervalSince1970,bTime=end.timeIntervalSince1970;
    BAAnalyticsObservation *a=observation(@"start",aTime,@{BAAnalyticsHistorySOCPercent:@80,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *b=observation(@"end",bTime,@{BAAnalyticsHistorySOCPercent:@80,BAAnalyticsHistoryExternalConnected:@0});
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"America/New_York"];
    NSDictionary *result=BAStatisticsRhythm(window(aTime,bTime,@[a,b],@[pair(a,b,aTime,bTime,BAAnalyticsObservedStateUnplugged)],@[]),calendar);
    near([result[@"windowSeconds"] doubleValue],elapsed*3600);near([result[@"validSeconds"] doubleValue],elapsed*3600);near([result[@"missingSeconds"] doubleValue],0);near([result[@"rate"] doubleValue],0);
    NSUInteger hours=0;for (NSDictionary *day in result[@"days"]) hours += [day[@"hours"] count];assert(hours==expectedHours);
    NSDictionary *last=[result[@"days"] lastObject];assert([last[@"hours"] count]==expectedLastDayHours);
    if (expectedLastDayHours==25) {NSMutableArray *ones=[NSMutableArray array];for (NSDictionary *hour in last[@"hours"]) if ([hour[@"hour"] integerValue]==1) [ones addObject:hour];assert(ones.count==2);assert(![ones[0][@"utcOffsetSeconds"] isEqual:ones[1][@"utcOffsetSeconds"]]);}
    propertyList(result);
}
static void rhythmTests(void) {
    calendarTest(@"2026-03-02 00:00:00 -0500",@"2026-03-09 00:00:00 -0400",167,167,23);
    calendarTest(@"2026-10-26 00:00:00 -0400",@"2026-11-02 00:00:00 -0500",169,169,25);
    BAAnalyticsObservation *a=observation(@"a",0,@{BAAnalyticsHistorySOCPercent:@80,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *b=observation(@"b",60,@{BAAnalyticsHistorySOCPercent:@70,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *c=observation(@"c",600,@{BAAnalyticsHistorySOCPercent:@70,BAAnalyticsHistoryExternalConnected:@0});
    BAAnalyticsObservation *d=observation(@"d",600,@{BAAnalyticsHistoryExternalConnected:@1});
    BAAnalyticsObservation *e=observation(@"e",1200,@{BAAnalyticsHistoryExternalConnected:@1});
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
    BAAnalyticsHistoryWindow *w=window(0,3600,@[a,b,c,d,e],@[pair(a,b,0,60,BAAnalyticsObservedStateUnplugged),pair(b,c,60,600,BAAnalyticsObservedStateUnplugged),pair(d,e,600,1200,BAAnalyticsObservedStateConnectedNotCharging)],@[]);
    NSDictionary *result=BAStatisticsRhythm(w,calendar);
    near([result[@"validSeconds"] doubleValue],600);near([result[@"connectedSeconds"] doubleValue],600);near([result[@"missingSeconds"] doubleValue],2400);near([result[@"rate"] doubleValue],60);propertyList(result);
    result=BAStatisticsRhythm(window(0,60,@[a,b],@[pair(a,b,0,60,BAAnalyticsObservedStateUnknown)],@[]),calendar);near([result[@"validSeconds"] doubleValue],0);near([result[@"missingSeconds"] doubleValue],60);assert(!result[@"rate"]);
}
int main(int argc,const char *argv[]) {@autoreleasepool {assert(argc==2);dwellTests();comparisonTests();readerComparisonTest([NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]] isDirectory:YES]);rhythmTests();boundedContextTest();puts("BAStatisticsAnalysisTests: clipped time weighting, field unions, gaps, complete reader crossings, observed peaks, quartiles, DST, zero/unknown states and property-list details passed");}return 0;}
