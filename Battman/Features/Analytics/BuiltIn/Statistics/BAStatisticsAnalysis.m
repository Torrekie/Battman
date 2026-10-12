#import "BAStatisticsAnalysis.h"
#import "BAStatisticsMath.h"

static NSUInteger const BASMaximumDetailIDs = 256;
static NSUInteger const BASMaximumDetailSpans = 8;
static NSString *const BASInterpolation = @"Approximate linear crossings within a trusted adjacent sampled pair. Clipping uses original observation timestamps and values; no interpolation across an absent trusted pair.";
static NSString *const BASCoveragePolicy = @"Coverage is the union of trusted pairs for the required fields. General report gaps can concern other fields/sources; missing time is the complement of this metric-specific union, not a subtraction of unrelated source gaps.";

static id BASFreeze(id value) {
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (NSString *key in value) out[key] = BASFreeze(value[key]);
        return [out copy];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id item in value) [out addObject:BASFreeze(item)];
        return [out copy];
    }
    return [value copy];
}
static NSUInteger BASContextNodes(id value) {
    NSUInteger count=1;
    if ([value isKindOfClass:NSDictionary.class]) for (id item in [value allValues]) count+=BASContextNodes(item);
    else if ([value isKindOfClass:NSArray.class]) for (id item in value) count+=BASContextNodes(item);
    return count;
}
static id BASContextStrings(id value, BOOL *truncated) {
    if ([value isKindOfClass:NSString.class] && [value length]>1024) {*truncated=YES;return [[value substringToIndex:1023] stringByAppendingString:@"…"];}
    if ([value isKindOfClass:NSDictionary.class]) {NSMutableDictionary *out=[NSMutableDictionary dictionary];for (id key in value) out[key]=BASContextStrings(value[key],truncated);return out;}
    if ([value isKindOfClass:NSArray.class]) {NSMutableArray *out=[NSMutableArray array];for (id item in value) [out addObject:BASContextStrings(item,truncated)];return out;}
    return value;
}
NSDictionary *BAStatisticsBoundedDetailContext(NSDictionary *context) {
    BOOL truncated=NO;NSMutableDictionary *out=[BASContextStrings(context,&truncated) mutableCopy];
    if (truncated) out[@"contextPreviewTruncated"]=@YES;
    for (;;) {
        NSData *encoded=[NSPropertyListSerialization dataWithPropertyList:out format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        // Reserve room for the shared factory's own dictionary/metadata checks.
        if (encoded.length>0 && encoded.length<=7800 && BASContextNodes(out)<=240) return BASFreeze(out);
        NSString *largest=nil;NSUInteger largestNodes=0;
        for (NSString *key in @[@"intervals",@"sessionSummary",@"excludedSessions",@"hours",@"days",@"limitations"]) {
            id array=out[key];NSUInteger nodes=BASContextNodes(array);
            if ([array isKindOfClass:NSArray.class] && [array count]>0 && nodes>largestNodes) {largest=key;largestNodes=nodes;}
        }
        if (!largest) return @{@"contextPreviewTruncated":@YES,@"detail":@"Summary unavailable within the selection budget; use the selected record IDs and time range."};
        NSArray *array=out[largest];out[largest]=[array subarrayWithRange:NSMakeRange(0,array.count-1)];out[@"contextPreviewTruncated"]=@YES;
    }
}
static double BASDuration(NSDate *start, NSDate *end) {
    double duration = [end timeIntervalSinceDate:start];
    return isfinite(duration) ? MAX(0, duration) : 0;
}
static BOOL BASValue(BAAnalyticsObservation *o, NSString *metric, double *out) {
    NSNumber *number = [o valueForMetricIdentifier:metric];
    BAAnalyticsFieldMetadata *metadata = o.fieldMetadata[metric];
    if (!o.timestampValidated || !number || !metadata.unitValidated || !metadata.unit.length || [metadata.unit isEqual:@"unverified"] || !isfinite(number.doubleValue)) return NO;
    if ([metric isEqual:BAAnalyticsHistorySOCPercent] && !BAStatisticsValidSOC(number.doubleValue)) return NO;
    if ([metric isEqual:BAAnalyticsHistoryExternalConnected] && number.doubleValue != 0 && number.doubleValue != 1) return NO;
    if (out) *out = number.doubleValue;
    return YES;
}
static BOOL BASPairMetric(BAAnalyticsHistoryInterval *i, NSString *metric) {
    if (![i.coveredMetricIdentifiers containsObject:metric] || !BASValue(i.startObservation,metric,NULL) || !BASValue(i.endObservation,metric,NULL)) return NO;
    BAAnalyticsFieldMetadata *a=i.startObservation.fieldMetadata[metric], *b=i.endObservation.fieldMetadata[metric];
    return [a.unit isEqual:b.unit] && [a.decoderIdentifier isEqual:b.decoderIdentifier] && [a.sourceTable isEqual:b.sourceTable] && [a.sourceColumn isEqual:b.sourceColumn];
}
static double BASInterpolated(BAAnalyticsHistoryInterval *i, NSString *metric, NSDate *at) {
    double rawDuration = BASDuration(i.startObservation.timestamp,i.endObservation.timestamp);
    if (!(rawDuration > 0) || !BASPairMetric(i,metric)) return NAN;
    double fraction = [at timeIntervalSinceDate:i.startObservation.timestamp] / rawDuration;
    if (fraction < -1e-9 || fraction > 1+1e-9) return NAN;
    double a=[i.startObservation valueForMetricIdentifier:metric].doubleValue;
    double b=[i.endObservation valueForMetricIdentifier:metric].doubleValue;
    return a+(b-a)*MAX(0,MIN(1,fraction));
}
static BAAnalyticsObservedState BASState(BAAnalyticsHistoryInterval *i) {
    if (i.state == BAAnalyticsObservedStateUnknown || !BASPairMetric(i,BAAnalyticsHistoryExternalConnected)) return BAAnalyticsObservedStateUnknown;
    double a=[i.startObservation valueForMetricIdentifier:BAAnalyticsHistoryExternalConnected].doubleValue;
    double b=[i.endObservation valueForMetricIdentifier:BAAnalyticsHistoryExternalConnected].doubleValue;
    if (a != b || (i.state == BAAnalyticsObservedStateUnplugged ? a != 0 : a != 1)) return BAAnalyticsObservedStateUnknown;
    return i.state;
}

@interface BASIntervalSlice : NSObject
@property (nonatomic, strong) BAAnalyticsHistoryInterval *interval;
@property (nonatomic, strong) NSDate *start;
@property (nonatomic, strong) NSDate *end;
@end
@implementation BASIntervalSlice
@end

// Production family intervals are canonical and nonoverlapping. Defensively union
// eligible fields here too: earlier start, then longer pair wins any duplicate span.
static NSArray<BASIntervalSlice *> *BASSlices(NSArray<BAAnalyticsHistoryInterval *> *intervals, NSArray<NSString *> *metrics, NSDate *start, NSDate *end) {
    NSArray *ordered = [intervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) {
        NSComparisonResult order=[a.startDate compare:b.startDate];
        if (order != NSOrderedSame) return order;
        order=[b.endDate compare:a.endDate];
        return order != NSOrderedSame ? order : [a.startObservation.identifier compare:b.startObservation.identifier];
    }];
    NSDate *coveredEnd=start;
    NSMutableArray *slices=[NSMutableArray array];
    for (BAAnalyticsHistoryInterval *i in ordered) {
        BOOL valid=BASDuration(i.startObservation.timestamp,i.endObservation.timestamp)>0;
        for (NSString *metric in metrics) valid &= BASPairMetric(i,metric);
        if (!valid) continue;
        NSDate *a=[[i.startDate laterDate:start] laterDate:coveredEnd], *b=[i.endDate earlierDate:end];
        if (BASDuration(a,b)<=0) continue;
        BASIntervalSlice *slice=[BASIntervalSlice new]; slice.interval=i;slice.start=a;slice.end=b;
        [slices addObject:slice]; coveredEnd=b;
    }
    return slices;
}
static void BASAddIDs(NSMutableOrderedSet *ids, BAAnalyticsHistoryInterval *i) {
    for (NSString *identifier in @[i.startObservation.identifier,i.endObservation.identifier])
        if (ids.count < BASMaximumDetailIDs) [ids addObject:identifier];
}
static NSDictionary *BASSpan(BASIntervalSlice *slice, NSDate *start, NSDate *end) {
    BAAnalyticsHistoryInterval *i=slice.interval;
    NSMutableDictionary *span=[@{@"startDate":start,@"endDate":end,@"validMinutes":@(BASDuration(start,end)/60),
             @"startRecord":i.startObservation.identifier,@"endRecord":i.endObservation.identifier,
             @"originalStartDate":i.startObservation.timestamp,@"originalEndDate":i.endObservation.timestamp,
             @"state":@(BASState(i))} mutableCopy];
    if (BASPairMetric(i,BAAnalyticsHistorySOCPercent)) {
        span[@"startSOC"]=@(BASInterpolated(i,BAAnalyticsHistorySOCPercent,start));span[@"endSOC"]=@(BASInterpolated(i,BAAnalyticsHistorySOCPercent,end));
        span[@"observedStartSOC"]=[i.startObservation valueForMetricIdentifier:BAAnalyticsHistorySOCPercent];span[@"observedEndSOC"]=[i.endObservation valueForMetricIdentifier:BAAnalyticsHistorySOCPercent];
        BAAnalyticsFieldMetadata *source=i.startObservation.fieldMetadata[BAAnalyticsHistorySOCPercent];
        span[@"SOCSource"]=@{@"table":source.sourceTable,@"column":source.sourceColumn,@"unit":source.unit,@"decoder":source.decoderIdentifier};
    }
    if (BASPairMetric(i,BAAnalyticsHistoryTemperatureCelsius)) {
        span[@"observedStartTemperatureCelsius"]=[i.startObservation valueForMetricIdentifier:BAAnalyticsHistoryTemperatureCelsius];
        span[@"observedEndTemperatureCelsius"]=[i.endObservation valueForMetricIdentifier:BAAnalyticsHistoryTemperatureCelsius];
        span[@"interpolatedStartTemperatureCelsius"]=@(BASInterpolated(i,BAAnalyticsHistoryTemperatureCelsius,start));
        span[@"interpolatedEndTemperatureCelsius"]=@(BASInterpolated(i,BAAnalyticsHistoryTemperatureCelsius,end));
        BAAnalyticsFieldMetadata *source=i.startObservation.fieldMetadata[BAAnalyticsHistoryTemperatureCelsius];
        span[@"temperatureSource"]=@{@"table":source.sourceTable,@"column":source.sourceColumn,@"unit":source.unit,@"decoder":source.decoderIdentifier};
    }
    span[@"valueConvention"]=@"observedStart/End values belong to originalStart/EndDate. startSOC/endSOC and interpolatedTemperature values are linear estimates at the clipped startDate/endDate, not observed rows.";
    return span;
}
static NSDictionary *BASFilter(double lower, double upper, BOOL includeUpper) {
    return @{@"minimum":@(lower),@"maximum":@(upper),@"includeMaximum":@(includeUpper)};
}
static NSMutableDictionary *BASNewBin(NSString *label, NSDictionary *filters) {
    return [@{@"label":label,@"seconds":@0,@"connectedSeconds":@0,@"unpluggedSeconds":@0,@"unknownStateSeconds":@0,
              @"ids":[NSMutableOrderedSet orderedSet],@"spans":[NSMutableArray array],@"spanCount":@0,@"filters":filters} mutableCopy];
}
static void BASAddBin(NSMutableDictionary *bin, BASIntervalSlice *slice, NSDate *start, NSDate *end) {
    double seconds=BASDuration(start,end); if (!(seconds>0)) return;
    bin[@"seconds"]=@([bin[@"seconds"] doubleValue]+seconds);
    BAAnalyticsObservedState state=BASState(slice.interval);
    NSString *key=state==BAAnalyticsObservedStateUnknown ? @"unknownStateSeconds" : state==BAAnalyticsObservedStateUnplugged ? @"unpluggedSeconds" : @"connectedSeconds";
    bin[key]=@([bin[key] doubleValue]+seconds);
    BASAddIDs(bin[@"ids"],slice.interval);
    NSMutableArray *spans=bin[@"spans"]; if (spans.count<BASMaximumDetailSpans) [spans addObject:BASSpan(slice,start,end)];
    bin[@"spanCount"]=@([bin[@"spanCount"] unsignedIntegerValue]+1);
}
static NSDictionary *BASFinishBin(NSMutableDictionary *bin, BAAnalyticsHistoryWindow *window, double covered, double missing) {
    double seconds=[bin[@"seconds"] doubleValue];
    NSMutableDictionary *context=[@{@"bin":bin[@"label"],@"validMinutes":@(seconds/60),@"shareOfValidCoverage":@(covered>0?seconds/covered:0),
        @"windowMinutes":@(BASDuration(window.startDate,window.endDate)/60),@"coverageMinutes":@(covered/60),@"missingMinutes":@(missing/60),
        @"connectedMinutes":@([bin[@"connectedSeconds"] doubleValue]/60),@"unpluggedMinutes":@([bin[@"unpluggedSeconds"] doubleValue]/60),@"unknownStateMinutes":@([bin[@"unknownStateSeconds"] doubleValue]/60),
        @"interpolation":BASInterpolation,@"coveragePolicy":BASCoveragePolicy,@"filters":bin[@"filters"],@"intervals":bin[@"spans"],@"contributingIntervalCount":bin[@"spanCount"],
        @"detailIntervalLimit":@(BASMaximumDetailSpans),@"recordIDLimit":@(BASMaximumDetailIDs),@"interpretation":@"Observed dwell distribution; no damage or safety score. Missing time is excluded from all bins."} mutableCopy];
    NSMutableDictionary *result=[bin mutableCopy]; [result removeObjectsForKeys:@[@"ids",@"spans",@"spanCount",@"filters"]];
    result[@"recordIdentifiers"]=[bin[@"ids"] array];result[@"startDate"]=window.startDate;result[@"endDate"]=window.endDate;result[@"context"]=context;
    return BASFreeze(result);
}

NSDictionary *BAStatisticsDwell(BAAnalyticsHistoryWindow *window) {
    NSMutableArray *soc=[NSMutableArray array],*joint=[NSMutableArray array];
    NSArray *temperatures=@[@"<25 °C",@"[25,30) °C",@"[30,35) °C",@"≥35 °C"];
    for (NSUInteger column=0;column<5;column++) {
        NSString *label=[NSString stringWithFormat:@"%lu–%lu%%",(unsigned long)column*20,(unsigned long)(column+1)*20];
        NSMutableDictionary *bin=BASNewBin(label,@{BAAnalyticsHistorySOCPercent:BASFilter(column*20,(column+1)*20,column==4)});bin[@"index"]=@(column);[soc addObject:bin];
    }
    for (NSUInteger row=0;row<4;row++) for (NSUInteger column=0;column<5;column++) {
        NSMutableDictionary *temperatureFilter=[NSMutableDictionary dictionary];
        if (row>0) temperatureFilter[@"minimum"]=@(20+row*5);
        if (row<3) temperatureFilter[@"maximum"]=@(25+row*5);
        temperatureFilter[@"includeMaximum"]=@NO;
        NSMutableDictionary *bin=BASNewBin([NSString stringWithFormat:@"SOC %@ × %@",soc[column][@"label"],temperatures[row]],@{BAAnalyticsHistorySOCPercent:BASFilter(column*20,(column+1)*20,column==4),BAAnalyticsHistoryTemperatureCelsius:temperatureFilter});
        bin[@"socIndex"]=@(column);bin[@"tempIndex"]=@(row);[joint addObject:bin];
    }
    double socCovered=0,jointCovered=0;
    for (NSUInteger pass=0;pass<2;pass++) {
        NSArray *metrics=pass?@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius]:@[BAAnalyticsHistorySOCPercent];
        for (BASIntervalSlice *slice in BASSlices(window.intervals,metrics,window.startDate,window.endDate)) {
            double duration=BASDuration(slice.start,slice.end),a=BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,slice.start),b=BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,slice.end);
            double ta=pass?BASInterpolated(slice.interval,BAAnalyticsHistoryTemperatureCelsius,slice.start):0,tb=pass?BASInterpolated(slice.interval,BAAnalyticsHistoryTemperatureCelsius,slice.end):0;
            double splits[9]={0,1};size_t count=2;
            if (b!=a) for (NSUInteger edge=20;edge<=80;edge+=20) BAStatisticsInsertSplit(splits,&count,(edge-a)/(b-a));
            if (pass && tb!=ta) for (NSUInteger edge=25;edge<=35;edge+=5) BAStatisticsInsertSplit(splits,&count,(edge-ta)/(tb-ta));
            for (size_t index=1;index<count;index++) {
                double midpoint=(splits[index-1]+splits[index])*.5;
                NSUInteger column=BAStatisticsSOCBin(a+(b-a)*midpoint),row=pass?BAStatisticsTemperatureBin(ta+(tb-ta)*midpoint):0;
                NSDate *start=[slice.start dateByAddingTimeInterval:splits[index-1]*duration],*end=[slice.start dateByAddingTimeInterval:splits[index]*duration];
                BASAddBin(pass?joint[row*5+column]:soc[column],slice,start,end);
            }
            if (pass) jointCovered+=duration;else socCovered+=duration;
        }
    }
    double requested=BASDuration(window.startDate,window.endDate),missingSOC=MAX(0,requested-socCovered),missingJoint=MAX(0,requested-jointCovered);
    NSMutableArray *socResult=[NSMutableArray array],*jointResult=[NSMutableArray array];
    for (NSMutableDictionary *bin in soc) [socResult addObject:BASFinishBin(bin,window,socCovered,missingSOC)];
    for (NSMutableDictionary *bin in joint) [jointResult addObject:BASFinishBin(bin,window,jointCovered,missingJoint)];
    NSDictionary *context=@{@"windowMinutes":@(requested/60),@"validSOCMinutes":@(socCovered/60),@"missingSOCMinutes":@(missingSOC/60),@"validJointMinutes":@(jointCovered/60),@"missingJointMinutes":@(missingJoint/60),@"interpolation":BASInterpolation,@"coveragePolicy":BASCoveragePolicy,
        @"SOCBins":@"[0,20), [20,40), [40,60), [60,80), [80,100] percent",@"temperatureBins":@"<25, [25,30), [30,35), ≥35 Celsius",@"distribution":@"Time weighted; unavailable fields are never assigned to a bin."};
    return BASFreeze(@{@"socBins":socResult,@"jointBins":jointResult,@"socSeconds":@(socCovered),@"jointSeconds":@(jointCovered),@"missingSOCSeconds":@(missingSOC),@"missingJointSeconds":@(missingJoint),@"windowSeconds":@(requested),@"context":context});
}

static NSString *BASProvenance(BAAnalyticsObservation *o, NSString *metric) {
    BAAnalyticsFieldMetadata *m=o.fieldMetadata[metric];
    return [NSString stringWithFormat:@"%@|%@|%@|%@",m.sourceTable,m.sourceColumn,m.unit,m.decoderIdentifier];
}
static NSString *BASComparisonReason(BAAnalyticsHistorySession *session, BAAnalyticsHistoryWindow *window) {
    if (![session.kind isEqual:@"connected"]) return @"not-connected-session";
    if (!session.startBoundaryKnown || !session.endBoundaryKnown || [session.startDate compare:window.startDate]==NSOrderedAscending || [session.endDate compare:window.endDate]==NSOrderedDescending) return @"incomplete-session-boundaries";
    if (BASDuration(session.startDate,session.endDate)<=0) return @"empty-session";
    for (BAAnalyticsHistoryGap *gap in session.gaps)
        if (BASDuration([gap.startDate laterDate:session.startDate],[gap.endDate earlierDate:session.endDate])>0) return @"session-gap";
    NSArray *ordered=[session.intervals sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistoryInterval *a, BAAnalyticsHistoryInterval *b) {return [a.startDate compare:b.startDate];}];
    NSDate *cursor=session.startDate;NSString *socSource=nil,*stateSource=nil;
    for (BAAnalyticsHistoryInterval *i in ordered) {
        if (BASDuration([i.startDate laterDate:session.startDate],[i.endDate earlierDate:session.endDate])<=0) continue;
        if (!BASPairMetric(i,BAAnalyticsHistorySOCPercent) || !BASPairMetric(i,BAAnalyticsHistoryExternalConnected)) return @"unavailable-SOC-or-connection";
        if ([i.startObservation valueForMetricIdentifier:BAAnalyticsHistoryExternalConnected].doubleValue!=1 || [i.endObservation valueForMetricIdentifier:BAAnalyticsHistoryExternalConnected].doubleValue!=1) return @"unplugged-or-unknown-connection";
        if (fabs([i.startDate timeIntervalSinceDate:cursor])>1e-6) return [i.startDate compare:cursor]==NSOrderedAscending ? @"overlapping-source-pairs" : @"missing-trusted-pair";
        NSString *source=BASProvenance(i.startObservation,BAAnalyticsHistorySOCPercent),*connection=BASProvenance(i.startObservation,BAAnalyticsHistoryExternalConnected);
        if (socSource && (![socSource isEqual:source] || ![stateSource isEqual:connection])) return @"incompatible-measurement-source";
        socSource=source;stateSource=connection;cursor=i.endDate;
    }
    return fabs([cursor timeIntervalSinceDate:session.endDate])>1e-6 ? @"missing-trusted-pair" : nil;
}
static void BASExclude(NSMutableArray *exclusions, NSMutableDictionary *counts, BAAnalyticsHistorySession *session, NSString *reason) {
    counts[reason]=@([counts[reason] unsignedIntegerValue]+1);
    if (exclusions.count<8) [exclusions addObject:@{@"sessionIdentifier":session.identifier,@"startDate":session.startDate,@"endDate":session.endDate,@"reason":reason}];
}
NSDictionary *BAStatisticsComparison(BAAnalyticsFamilyReport *report) {
    BAAnalyticsHistoryWindow *window=report.window;
    NSArray<BAAnalyticsHistorySession *> *candidates=report.payload[BAAnalyticsPayloadSessions] ?: @[];
    candidates=[candidates sortedArrayUsingComparator:^NSComparisonResult(BAAnalyticsHistorySession *a,BAAnalyticsHistorySession *b) {return [a.startDate compare:b.startDate];}];
    NSMutableArray *samples=[NSMutableArray array],*exclusions=[NSMutableArray array];NSMutableDictionary *counts=[NSMutableDictionary dictionary];NSMutableSet *seen=[NSMutableSet set];
    NSDate *previousSessionEnd=nil;
    for (BAAnalyticsHistorySession *session in candidates) {
        NSString *reason=BASComparisonReason(session,window);
        if ([seen containsObject:session.identifier]) reason=@"duplicate-session";
        [seen addObject:session.identifier];
        if (!reason && previousSessionEnd && [session.startDate compare:previousSessionEnd]==NSOrderedAscending) reason=@"non-independent-overlapping-session";
        if (reason) {BASExclude(exclusions,counts,session,reason);continue;}
        NSDate *lower=nil,*upper=nil;
        NSArray *slices=BASSlices(session.intervals,@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected],session.startDate,session.endDate);
        for (BASIntervalSlice *slice in slices) {
            double a=BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,slice.start),b=BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,slice.end),fraction=0;
            if (!lower && BAStatisticsUpwardCrossingFraction(a,b,20,&fraction)) lower=[slice.start dateByAddingTimeInterval:BASDuration(slice.start,slice.end)*fraction];
            if (lower && BAStatisticsUpwardCrossingFraction(a,b,80,&fraction)) {
                NSDate *crossing=[slice.start dateByAddingTimeInterval:BASDuration(slice.start,slice.end)*fraction];
                if ([crossing compare:lower]==NSOrderedDescending) {upper=crossing;break;}
            }
        }
        if (!lower || !upper) {BASExclude(exclusions,counts,session,@"incomplete-20-80-crossing");continue;}
        double duration=BASDuration(lower,upper),temperatureSeconds=0,peak=-INFINITY;
        NSMutableOrderedSet *ids=[NSMutableOrderedSet orderedSetWithObject:session.identifier];NSMutableArray *spans=[NSMutableArray array];NSUInteger spanCount=0,temperaturePointCount=0;
        for (BASIntervalSlice *slice in BASSlices(session.intervals,@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected],lower,upper)) {
            BASAddIDs(ids,slice.interval);if (spans.count<BASMaximumDetailSpans) [spans addObject:BASSpan(slice,slice.start,slice.end)];spanCount++;
        }
        for (BASIntervalSlice *slice in BASSlices(session.intervals,@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius],lower,upper)) temperatureSeconds+=BASDuration(slice.start,slice.end);
        for (BAAnalyticsObservation *observation in session.observations) {
            if ([observation.timestamp compare:lower]==NSOrderedAscending || [observation.timestamp compare:upper]==NSOrderedDescending) continue;
            double temperature=0;
            if (BASValue(observation,BAAnalyticsHistoryTemperatureCelsius,&temperature)) {peak=MAX(peak,temperature);temperaturePointCount++;}
        }
        NSMutableDictionary *context=[@{@"sessionIdentifier":session.identifier,@"SOCInterval":@"20 → 80 percent",@"approximateMinutes":@(duration/60),@"validMinutes":@(duration/60),@"missingMinutes":@0,
            @"sessionStartDate":session.startDate,@"sessionEndDate":session.endDate,@"crossingStartDate":lower,@"crossingEndDate":upper,@"completeBoundaries":@YES,@"temperatureObservedMinutes":@(temperatureSeconds/60),@"temperatureMissingMinutes":@(MAX(0,duration-temperatureSeconds)/60),@"temperaturePointCount":@(temperaturePointCount),
            @"interpolation":BASInterpolation,@"crossingConvention":@"First trusted upward 20% crossing followed by the first trusted upward 80% crossing in one complete connected session; elapsed pauses and SOC reversals inside that range remain included.",
            @"compatibility":@"Producer-selected compatible primary measurement/configuration cohort; each complete session retains its own source and clock continuity barriers. Opaque IDs, ordinary FCC fluctuations and PMU runtime state are not interpreted as physical battery identity.",
            @"peakDefinition":@"Maximum validated temperature actually sampled inside the selected 20–80% range, not an interpolated or full-session maximum; absent temperature is unavailable.",@"intervals":spans,@"contributingIntervalCount":@(spanCount),@"detailIntervalLimit":@(BASMaximumDetailSpans),@"recordIDLimit":@(BASMaximumDetailIDs)} mutableCopy];
        NSMutableDictionary *sample=[@{@"identifier":session.identifier,@"startDate":lower,@"endDate":upper,@"minutes":@(duration/60),@"temperatureObservedMinutes":@(temperatureSeconds/60),@"recordIdentifiers":ids.array,@"context":context} mutableCopy];
        if (isfinite(peak)) {sample[@"peakCelsius"]=@(peak);context[@"observedPeakCelsius"]=@(peak);}else context[@"temperature"]=@"unavailable";
        [samples addObject:BASFreeze(sample)];previousSessionEnd=session.endDate;
    }
    NSArray *orderedMinutes=[[samples valueForKey:@"minutes"] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableData *storage=[NSMutableData dataWithLength:sizeof(double)*orderedMinutes.count];double *minutes=storage.mutableBytes;
    for (NSUInteger index=0;index<orderedMinutes.count;index++) minutes[index]=[orderedMinutes[index] doubleValue];
    BAStatisticsQuantiles quantiles=BAStatisticsQuantilesForSortedValues(minutes,orderedMinutes.count);
    NSMutableDictionary *result=[@{@"samples":samples,@"exclusions":exclusions,@"exclusionCounts":counts,@"n":@(samples.count),@"hasBox":@(quantiles.hasBox),@"windowSeconds":@(BASDuration(window.startDate,window.endDate))} mutableCopy];
    if (quantiles.count) {result[@"minimum"]=@(quantiles.minimum);result[@"maximum"]=@(quantiles.maximum);result[@"median"]=@(quantiles.median);}
    if (quantiles.hasBox) {result[@"q1"]=@(quantiles.firstQuartile);result[@"q3"]=@(quantiles.thirdQuartile);}
    NSMutableArray *sampleSummary=[NSMutableArray array];
    for (NSDictionary *sample in samples) if (sampleSummary.count<12) {
        NSMutableDictionary *row=[@{@"sessionIdentifier":sample[@"identifier"],@"startDate":sample[@"startDate"],@"endDate":sample[@"endDate"],@"approximateMinutes":sample[@"minutes"],@"temperatureObservedMinutes":sample[@"temperatureObservedMinutes"]} mutableCopy];
        if (sample[@"peakCelsius"]) row[@"observedPeakCelsius"]=sample[@"peakCelsius"];[sampleSummary addObject:row];
    }
    NSMutableDictionary *context=[@{@"SOCInterval":@"20 → 80 percent",@"validSessions":@(samples.count),@"candidateSessions":@(candidates.count),@"exclusionCounts":counts,@"excludedSessions":exclusions,@"sessionSummary":sampleSummary,
        @"quartiles":@"Q1/Q3 are medians of sorted lower/upper halves; omit the central item for odd n. Fewer than three sessions: individual points only, no box.",@"whiskers":@"Observed minimum and maximum; no 1.5×IQR rule.",@"interpolation":BASInterpolation,@"interpretation":@"Descriptive observations only; no statistical significance or causal inference.",@"producerCompatibility":@"The data producer limits candidates to the latest recognized primary measurement/configuration cohort, without crossing an observed battery/configuration/reset boundary. Independently complete sessions may use different source files or clock segments; interpolation never crosses those boundaries. Missing optional identity fields do not prove physical battery identity; excluded candidate counts are not inferred.",@"detailSessionLimit":@12,@"detailExclusionLimit":@8} mutableCopy];
    for (NSString *key in @[@"minimum",@"maximum",@"median",@"q1",@"q3"]) if (result[key]) context[[key stringByAppendingString:@"Minutes"]]=result[key];
    result[@"context"]=context;return BASFreeze(result);
}

static NSDictionary *BASRhythmCell(NSDate *start, NSDate *end, NSArray<BASIntervalSlice *> *unplugged, NSArray<BASIntervalSlice *> *connected, NSUInteger *unpluggedCursor, NSUInteger *connectedCursor, NSCalendar *calendar, NSString *label) {
    while (*unpluggedCursor<unplugged.count && [unplugged[*unpluggedCursor].end compare:start]!=NSOrderedDescending) (*unpluggedCursor)++;
    while (*connectedCursor<connected.count && [connected[*connectedCursor].end compare:start]!=NSOrderedDescending) (*connectedCursor)++;
    double valid=0,connectedSeconds=0,drop=0;NSUInteger spanCount=0;
    NSMutableOrderedSet *ids=[NSMutableOrderedSet orderedSet];NSMutableArray *spans=[NSMutableArray array];
    for (NSUInteger index=*unpluggedCursor;index<unplugged.count;index++) {
        BASIntervalSlice *slice=unplugged[index];if ([slice.start compare:end]!=NSOrderedAscending) break;
        NSDate *a=[start laterDate:slice.start],*b=[end earlierDate:slice.end];double seconds=BASDuration(a,b);if (!(seconds>0)) continue;
        valid+=seconds;drop+=BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,a)-BASInterpolated(slice.interval,BAAnalyticsHistorySOCPercent,b);
        BASAddIDs(ids,slice.interval);if (spans.count<BASMaximumDetailSpans) [spans addObject:BASSpan(slice,a,b)];spanCount++;
    }
    for (NSUInteger index=*connectedCursor;index<connected.count;index++) {
        BASIntervalSlice *slice=connected[index];if ([slice.start compare:end]!=NSOrderedAscending) break;
        NSDate *a=[start laterDate:slice.start],*b=[end earlierDate:slice.end];double seconds=BASDuration(a,b);if (!(seconds>0)) continue;
        connectedSeconds+=seconds;BASAddIDs(ids,slice.interval);
        if (spans.count<BASMaximumDetailSpans) [spans addObject:BASSpan(slice,a,b)];spanCount++;
    }
    double requested=BASDuration(start,end),missing=MAX(0,requested-valid-connectedSeconds);
    NSMutableDictionary *context=[@{@"localHour":label,@"timeZone":calendar.timeZone.name,@"UTCOffsetSeconds":@([calendar.timeZone secondsFromGMTForDate:start]),
        @"startDate":start,@"endDate":end,@"requestedMinutes":@(requested/60),@"validUnpluggedMinutes":@(valid/60),@"connectedMinutes":@(connectedSeconds/60),@"missingMinutes":@(missing/60),@"observedSOCChangePP":@(-drop),
        @"rateDefinition":@"Sum of signed SOC decline (percentage points) divided by actual trusted unplugged seconds × 3600. Connected intervals and missing/unknown state or SOC do not enter the denominator; negative rate means an observed SOC rise, not inferred charging.",
        @"interpolation":BASInterpolation,@"coveragePolicy":BASCoveragePolicy,@"intervals":spans,@"contributingIntervalCount":@(spanCount),@"detailIntervalLimit":@(BASMaximumDetailSpans),@"recordIDLimit":@(BASMaximumDetailIDs)} mutableCopy];
    NSMutableDictionary *result=[@{@"identifier":[NSString stringWithFormat:@"hour/%.6f/%.6f",start.timeIntervalSince1970,end.timeIntervalSince1970],@"startDate":start,@"endDate":end,@"hourLabel":label,@"hour":@([calendar component:NSCalendarUnitHour fromDate:start]),@"utcOffsetSeconds":@([calendar.timeZone secondsFromGMTForDate:start]),
        @"validSeconds":@(valid),@"connectedSeconds":@(connectedSeconds),@"missingSeconds":@(missing),@"declinePP":@(drop),@"recordIdentifiers":ids.array,@"context":context} mutableCopy];
    if (valid>0) {result[@"rate"]=@(drop/valid*3600);context[@"ratePPPerHour"]=result[@"rate"];}else context[@"rate"]=@"unavailable; no trusted unplugged SOC duration";
    return BASFreeze(result);
}
NSDictionary *BAStatisticsRhythm(BAAnalyticsHistoryWindow *window, NSCalendar *requestedCalendar) {
    NSCalendar *calendar=[requestedCalendar copy];
    NSMutableArray *unplugged=[NSMutableArray array],*connected=[NSMutableArray array];
    for (BASIntervalSlice *slice in BASSlices(window.intervals,@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected],window.startDate,window.endDate))
        if (BASState(slice.interval)==BAAnalyticsObservedStateUnplugged) [unplugged addObject:slice];
    for (BASIntervalSlice *slice in BASSlices(window.intervals,@[BAAnalyticsHistoryExternalConnected],window.startDate,window.endDate)) {
        BAAnalyticsObservedState state=BASState(slice.interval);
        if (state!=BAAnalyticsObservedStateUnknown && state!=BAAnalyticsObservedStateUnplugged) [connected addObject:slice];
    }
    NSDateFormatter *dayFormat=[NSDateFormatter new];dayFormat.calendar=calendar;dayFormat.timeZone=calendar.timeZone;dayFormat.dateFormat=@"M/d";
    NSDateFormatter *hourFormat=[NSDateFormatter new];hourFormat.calendar=calendar;hourFormat.timeZone=calendar.timeZone;hourFormat.dateFormat=@"HH:mm ZZZZZ";
    NSMutableArray *days=[NSMutableArray array],*daySummary=[NSMutableArray array];NSDate *cursor=window.startDate;
    NSUInteger unpluggedCursor=0,connectedCursor=0;double totalValid=0,totalConnected=0,totalDrop=0;
    // Family windows are bounded to seven elapsed days; allow a partial eighth civil
    // date plus DST/half-hour transitions. The guard prevents a malformed calendar
    // from an unbounded loop; skipped remaining time stays missing and disclosed.
    NSUInteger hourCount=0;BOOL calendarComplete=YES;
    while ([cursor compare:window.endDate]==NSOrderedAscending && hourCount<200) {
        NSDate *civilDayStart=nil;NSTimeInterval civilDaySeconds=0;
        if (![calendar rangeOfUnit:NSCalendarUnitDay startDate:&civilDayStart interval:&civilDaySeconds forDate:cursor]) {calendarComplete=NO;break;}
        NSDate *dayStart=cursor,*dayEnd=[[civilDayStart dateByAddingTimeInterval:civilDaySeconds] earlierDate:window.endDate];
        if (!dayEnd || BASDuration(cursor,dayEnd)<=0) {calendarComplete=NO;break;}
        NSMutableArray *hours=[NSMutableArray array],*hourSummary=[NSMutableArray array];NSMutableOrderedSet *dayIDs=[NSMutableOrderedSet orderedSet];
        double valid=0,connectedSeconds=0,drop=0;
        while ([cursor compare:dayEnd]==NSOrderedAscending && hourCount<200) {
            NSDate *civilHourStart=nil;NSTimeInterval civilHourSeconds=0;
            if (![calendar rangeOfUnit:NSCalendarUnitHour startDate:&civilHourStart interval:&civilHourSeconds forDate:cursor]) {calendarComplete=NO;break;}
            NSDate *hourEnd=[[civilHourStart dateByAddingTimeInterval:civilHourSeconds] earlierDate:dayEnd];
            if (!hourEnd || BASDuration(cursor,hourEnd)<=0) {calendarComplete=NO;break;}
            NSString *label=[NSString stringWithFormat:@"%@ – %@",[hourFormat stringFromDate:cursor],[hourFormat stringFromDate:hourEnd]];
            NSDictionary *hour=BASRhythmCell(cursor,hourEnd,unplugged,connected,&unpluggedCursor,&connectedCursor,calendar,label);
            [hours addObject:hour];valid+=[hour[@"validSeconds"] doubleValue];connectedSeconds+=[hour[@"connectedSeconds"] doubleValue];drop+=[hour[@"declinePP"] doubleValue];
            for (NSString *identifier in hour[@"recordIdentifiers"]) if (dayIDs.count<BASMaximumDetailIDs) [dayIDs addObject:identifier];
            NSMutableDictionary *summary=[@{@"startDate":hour[@"startDate"],@"endDate":hour[@"endDate"],@"localHour":hour[@"hourLabel"],@"validMinutes":@([hour[@"validSeconds"] doubleValue]/60),@"connectedMinutes":@([hour[@"connectedSeconds"] doubleValue]/60),@"missingMinutes":@([hour[@"missingSeconds"] doubleValue]/60)} mutableCopy];
            if (hour[@"rate"]) summary[@"ratePPPerHour"]=hour[@"rate"];[hourSummary addObject:summary];
            cursor=hourEnd;hourCount++;
        }
        NSDate *actualEnd=cursor;double elapsed=BASDuration(dayStart,actualEnd),missing=MAX(0,elapsed-valid-connectedSeconds);
        NSString *label=[dayFormat stringFromDate:dayStart];
        NSMutableDictionary *context=[@{@"localDate":label,@"timeZone":calendar.timeZone.name,@"startDate":dayStart,@"endDate":actualEnd,@"requestedMinutes":@(elapsed/60),@"validUnpluggedMinutes":@(valid/60),@"connectedMinutes":@(connectedSeconds/60),@"missingMinutes":@(missing/60),@"hours":hourSummary,
            @"aggregation":@"Daily time-weighted rate: total signed SOC decline divided by actual valid unplugged seconds; not an unweighted mean/median of hourly cells.",@"calendar":@"Local calendar boundaries. Repeated hours retain distinct absolute timestamps and UTC offsets; skipped hours have no elapsed duration, not missing observations."} mutableCopy];
        NSMutableDictionary *day=[@{@"label":label,@"startDate":dayStart,@"endDate":actualEnd,@"hours":hours,@"validSeconds":@(valid),@"connectedSeconds":@(connectedSeconds),@"missingSeconds":@(missing),@"recordIdentifiers":dayIDs.array,@"context":context} mutableCopy];
        NSMutableDictionary *summary=[@{@"localDate":label,@"elapsedMinutes":@(elapsed/60),@"validUnpluggedMinutes":@(valid/60),@"connectedMinutes":@(connectedSeconds/60),@"missingMinutes":@(missing/60)} mutableCopy];
        if (valid>0) {day[@"rate"]=@(drop/valid*3600);context[@"ratePPPerHour"]=day[@"rate"];summary[@"ratePPPerHour"]=day[@"rate"];}else context[@"rate"]=@"unavailable; no trusted unplugged SOC duration";
        [days addObject:BASFreeze(day)];[daySummary addObject:summary];totalValid+=valid;totalConnected+=connectedSeconds;totalDrop+=drop;
        if (!calendarComplete || BASDuration(dayStart,actualEnd)<=0) break;
    }
    if ([cursor compare:window.endDate]==NSOrderedAscending) calendarComplete=NO;
    double requested=BASDuration(window.startDate,window.endDate),missing=MAX(0,requested-totalValid-totalConnected);
    NSMutableDictionary *context=[@{@"timeZone":calendar.timeZone.name,@"windowMinutes":@(requested/60),@"validUnpluggedMinutes":@(totalValid/60),@"connectedMinutes":@(totalConnected/60),@"missingMinutes":@(missing/60),@"unpluggedCoverageFraction":@(requested>0?totalValid/requested:0),@"calendarComplete":@(calendarComplete),@"days":daySummary,
        @"rateDefinition":@"Time weighted net SOC decline in percentage points/hour using only actual valid unplugged seconds. A valid zero stays zero; no valid seconds means unavailable. Negative means observed SOC rise.",@"calendar":@"Requested elapsed time is the denominator, not a forced 168 hours. Local date/hour boundaries use the selected calendar and time zone including DST. Connected is grey; missing/unknown is hatched."} mutableCopy];
    NSMutableDictionary *result=[@{@"days":days,@"validSeconds":@(totalValid),@"connectedSeconds":@(totalConnected),@"missingSeconds":@(missing),@"windowSeconds":@(requested),@"context":context} mutableCopy];
    if (totalValid>0) {result[@"rate"]=@(totalDrop/totalValid*3600);context[@"ratePPPerHour"]=result[@"rate"];}
    return BASFreeze(result);
}
