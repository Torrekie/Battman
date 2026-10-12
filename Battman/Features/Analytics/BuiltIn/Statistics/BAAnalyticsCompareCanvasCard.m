#import "BAStatisticsDrawing.h"
#import "../Canvas/BAAnalyticsDetailViewController.h"
static NSString *BASSampleLabel(NSDictionary *sample) {
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"M/d HH:mm";
    NSString *peak = sample[@"peakCelsius"] ? [NSString stringWithFormat:@" · %@ %.1f °C",_("observed peak"),[sample[@"peakCelsius"] doubleValue]] : [NSString stringWithFormat:@" · %@",_("temperature unavailable")];
    return [NSString stringWithFormat:_("%@ · ≈ %.1f min%@"),[f stringFromDate:sample[@"startDate"]],[sample[@"minutes"] doubleValue],peak];
}
@interface BASCompareView : BASStatisticalView
@end

@interface BASCompareDetailChart : UIView
@property (nonatomic, copy) NSArray<NSDictionary *> *samples;
@property (nonatomic, copy) NSString *selectedIdentifier;
@end
@implementation BASCompareDetailChart
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 326); }
- (void)drawRect:(CGRect)rect {
    CGFloat w=self.bounds.size.width;
    UIFont *font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12] maximumPointSize:16];
    CGFloat line=ceil(font.lineHeight), top=38, bottom=self.bounds.size.height-line*4-22;
    UIColor *muted=[UIColor compatSecondaryLabelColor], *blue=[UIColor compatBlueColor];
    BASText(_("20 → 80% · ≈ min"),CGRectMake(16,8,w-32,line+4),font,muted,NSTextAlignmentLeft);
    CGRect plot=CGRectMake(54,top,w-74,MAX(32,bottom-top));
    double maximum=0,minimum=INFINITY;
    for (NSDictionary *sample in self.samples) { double value=[sample[@"minutes"] doubleValue]; maximum=MAX(maximum,value); minimum=MIN(minimum,value); }
    if (!self.samples.count) {
        BASHatch(plot); BASText(_("No complete 20–80% crossings"),CGRectInset(plot,8,8),font,muted,NSTextAlignmentLeft); return;
    }
    double lower=MAX(0,minimum-MAX(2,(maximum-minimum)*.1)),upper=maximum+MAX(2,(maximum-minimum)*.1);
    BASLine(CGPointMake(plot.origin.x,plot.origin.y),CGPointMake(plot.origin.x,CGRectGetMaxY(plot)),[UIColor compatSeparatorColor],1);
    BASLine(CGPointMake(plot.origin.x,CGRectGetMaxY(plot)),CGPointMake(CGRectGetMaxX(plot),CGRectGetMaxY(plot)),[UIColor compatSeparatorColor],1);
    BASText([NSString stringWithFormat:@"%.0f",upper],CGRectMake(4,top-line/2,42,line+4),font,muted,NSTextAlignmentRight);
    BASText([NSString stringWithFormat:@"%.0f",lower],CGRectMake(4,bottom-line/2,42,line+4),font,muted,NSTextAlignmentRight);
    NSDate *first=self.samples.firstObject[@"startDate"], *last=self.samples.lastObject[@"startDate"];
    double elapsed=[last timeIntervalSinceDate:first];
    for (NSDictionary *sample in self.samples) {
        CGFloat x=elapsed>0 ? plot.origin.x+[sample[@"startDate"] timeIntervalSinceDate:first]/elapsed*plot.size.width : CGRectGetMidX(plot);
        CGFloat y=CGRectGetMaxY(plot)-([sample[@"minutes"] doubleValue]-lower)/(upper-lower)*plot.size.height;
        BOOL selected=[sample[@"identifier"] isEqualToString:self.selectedIdentifier];
        if (selected) { BASDot(CGPointMake(x,y),[blue colorWithAlphaComponent:.15],10); BASDot(CGPointMake(x,y),blue,5); }
        else BASDot(CGPointMake(x,y),[blue colorWithAlphaComponent:.62],3.5);
    }
    NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"M/d";
    BASText([format stringFromDate:first],CGRectMake(plot.origin.x,bottom+6,plot.size.width/2,line+4),font,muted,NSTextAlignmentLeft);
    BASText([format stringFromDate:last],CGRectMake(plot.origin.x+plot.size.width/2,bottom+6,plot.size.width/2,line+4),font,muted,NSTextAlignmentRight);
    BASText(_("Each dot is one independent session"),CGRectMake(16,bottom+line+14,w-32,line*2+4),font,muted,NSTextAlignmentLeft);
}
@end

static NSString *BASComparisonExclusionTitle(NSString *reason) {
    NSDictionary *titles=@{
        @"incomplete-20-80-crossing":_("Incomplete 20–80% range"),
        @"incomplete-session-boundaries":_("Incomplete session boundaries"),
        @"not-connected-session":_("Unplugged session"),
        @"empty-session":_("Empty session"),
        @"session-gap":_("Gap inside session"),
        @"duplicate-session":_("Duplicate session"),
        @"non-independent-overlapping-session":_("Overlapping sessions"),
        @"overlapping-source-pairs":_("Overlapping observations"),
        @"missing-trusted-pair":_("Missing trusted observations"),
        @"unavailable-SOC-or-connection":_("SOC or connection unavailable"),
        @"unplugged-or-unknown-connection":_("Unplugged or unknown connection"),
        @"incompatible-measurement-source":_("Incompatible measurement sources")
    };
    return titles[reason] ?: _("Other excluded sessions");
}

@interface BASCompareDetailViewController : BAAnalyticsDetailViewController
@property (nonatomic, copy) NSDictionary *frozenAnalysis;
@end
@implementation BASCompareDetailViewController
- (NSDictionary *)comparisonAnalysis { return self.frozenAnalysis ?: @{}; }
- (NSDictionary *)selectedSample:(NSDictionary *)analysis {
    NSString *identifier=self.selection.context[@"sessionIdentifier"] ?: self.selection.context[@"identifier"];
    for (NSDictionary *sample in analysis[@"samples"]) if ([sample[@"identifier"] isEqualToString:identifier]) return sample;
    return nil;
}
- (UIView *)makeVisualizationView {
    NSDictionary *analysis=[self comparisonAnalysis];
    BASCompareDetailChart *chart=[[BASCompareDetailChart alloc] initWithFrame:CGRectMake(0,0,320,326)];
    chart.backgroundColor=[UIColor compatBackgroundColor]; chart.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    chart.samples=analysis[@"samples"] ?: @[];
    chart.selectedIdentifier=[self selectedSample:analysis][@"identifier"];
    chart.isAccessibilityElement=YES;
    chart.accessibilityLabel=[NSString stringWithFormat:_("20–80%% charge duration, %lu independent sessions"),(unsigned long)chart.samples.count];
    return chart;
}
- (NSArray<NSDictionary *> *)summaryRows {
    NSDictionary *analysis=[self comparisonAnalysis], *selected=[self selectedSample:analysis];
    NSMutableArray *rows=[NSMutableArray array];
    if (selected) {
        NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"M/d HH:mm";
        [rows addObject:@{@"title":_("Selected session"),@"value":[NSString stringWithFormat:@"%@ – %@",[format stringFromDate:selected[@"startDate"]],[format stringFromDate:selected[@"endDate"]]]}];
        [rows addObject:@{@"title":_("20–80% duration"),@"value":[NSString stringWithFormat:_("≈ %.2f min"),[selected[@"minutes"] doubleValue]]}];
        [rows addObject:@{@"title":_("Observed peak temperature"),@"value":selected[@"peakCelsius"] ? [NSString stringWithFormat:@"%.1f °C",[selected[@"peakCelsius"] doubleValue]] : _("Temperature unavailable")}];
    }
    NSUInteger n=[analysis[@"samples"] count];
    [rows addObject:@{@"title":_("Independent sessions"),@"value":[NSString stringWithFormat:@"%lu",(unsigned long)n]}];
    if (n) [rows addObject:@{@"title":_("Estimated median"),@"value":[NSString stringWithFormat:_("≈ %.2f min"),[analysis[@"median"] doubleValue]]}];
    if ([analysis[@"hasBox"] boolValue]) [rows addObject:@{@"title":_("Middle 50%"),@"value":[NSString stringWithFormat:_("%.2f–%.2f min"),[analysis[@"q1"] doubleValue],[analysis[@"q3"] doubleValue]]}];
    if ([self.selection.kind isEqualToString:@"exclusions"]) {
        NSDictionary *counts=analysis[@"exclusionCounts"];
        for (NSString *reason in [counts.allKeys sortedArrayUsingSelector:@selector(compare:)]) [rows addObject:@{@"title":BASComparisonExclusionTitle(reason),@"value":[counts[reason] stringValue]}];
    } else {
        NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"M/d HH:mm";
        NSUInteger shown=0;
        for (NSDictionary *sample in analysis[@"samples"]) {
            if (shown++>=24) break;
            [rows addObject:@{@"title":[format stringFromDate:sample[@"startDate"]],@"value":[NSString stringWithFormat:_("≈ %.2f min"),[sample[@"minutes"] doubleValue]]}];
        }
        if (n>24) [rows addObject:@{@"title":_("Sessions shown"),@"value":[NSString stringWithFormat:@"24 / %lu",(unsigned long)n]}];
    }
    [rows addObject:@{@"title":_("Method"),@"value":_("First trusted upward 20% crossing to the first upward 80% crossing in one complete connected session. Pauses are included; temperature is an observed peak, not a predicted maximum.")}];
    return rows;
}
@end

@interface BASCompareCard : BASStatisticalCard
@end
@implementation BASCompareCard
- (BOOL)supportsDetails { return YES; }
- (BAAnalyticsCanvasView *)makeCanvasView { BASCompareView *view=[BASCompareView new]; view.accessibilityLabel=self.analyticsCardDisplayName; return view; }
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family { return BAStatisticsComparison(family); }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    [self deriveIfNeeded];
    BAAnalyticsFamilyReport *family=[self.latestReport reportForFamily:self.familyIdentifier];
    if (!self.analysis && (family.availability==BAAnalyticsReportAvailabilityReady || family.availability==BAAnalyticsReportAvailabilityPartial)) return nil;
    BASCompareDetailViewController *detail=[[BASCompareDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier report:self.latestReport snapshot:self.latestSnapshot selection:selection ?: [self defaultDetailSelection]];
    detail.frozenAnalysis=self.analysis;
    return detail;
}
@end

id<BAAnalyticsCard> BAAnalyticsCreateCompareCanvasCard(void) {
    return [[BASCompareCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.compare" displayName:_("Charging comparison") familyIdentifier:BAAnalyticsFamilyCompare supportedSizes:BAAnalyticsCardSizeMask1x2|BAAnalyticsCardSizeMask2x1|BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x1];
}
@implementation BASCompareView
- (NSArray *)summaryRows {
    if (!self.analysis) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{@"text":[NSString stringWithFormat:_("20 → 80%% · n=%lu · %@"),(unsigned long)[self.analysis[@"samples"] count],_("estimated minutes")],@"kind":@"distribution",@"item":@{}}];
    if ([self.analysis[@"hasBox"] boolValue]) [rows addObject:@{@"text":[NSString stringWithFormat:_("min %.1f · Q1 %.1f · median %.1f · Q3 %.1f · max %.1f min"),[self.analysis[@"minimum"] doubleValue],[self.analysis[@"q1"] doubleValue],[self.analysis[@"median"] doubleValue],[self.analysis[@"q3"] doubleValue],[self.analysis[@"maximum"] doubleValue]],@"kind":@"distribution",@"item":@{}}];
    for (NSDictionary *sample in self.analysis[@"samples"]) [rows addObject:@{@"text":BASSampleLabel(sample),@"kind":@"session",@"item":sample,@"metrics":@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius]}];
    [rows addObject:@{@"text":[NSString stringWithFormat:@"%@ · %lu",_("Excluded sessions"),(unsigned long)[[[self.analysis[@"exclusionCounts"] allValues] valueForKeyPath:@"@sum.self"] unsignedIntegerValue]],@"kind":@"exclusions",@"item":@{}}];
    return rows;
}
- (void)drawStatistics:(NSMutableArray *)hits {
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height; UIFont *font=BASFont(11); CGFloat line=ceil(font.lineHeight);
    NSArray *samples=self.analysis[@"samples"] ?: @[]; BOOL hasBox=[self.analysis[@"hasBox"] boolValue];
    BOOL vertical=self.cardSize == BAAnalyticsCardSize1x2;
    BASText(vertical ? @"20 → 80%" : _("20 → 80% · ≈ min"),CGRectMake(12,10,w-66,line+6),BASFont(13),[UIColor compatLabelColor],NSTextAlignmentLeft);
    BASText([NSString stringWithFormat:@"n=%lu",(unsigned long)samples.count],CGRectMake(w-60,10,48,line+6),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentRight);
    BASText(BASWindow(self.familyReport.window),CGRectMake(12,16+line,w-24,line*2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    CGFloat top=22+line*(vertical?3:2), bottom=h-line*(vertical?3:2)-16;
    NSUInteger excluded=0; for (NSNumber *count in [self.analysis[@"exclusionCounts"] allValues]) excluded += count.unsignedIntegerValue;
    NSString *definition=hasBox ? (vertical?_("Q1–Q3\nobs min/max"):_("Q1–Q3 · obs min/max")) : _("n < 3 · points");
    BASText([NSString stringWithFormat:@"%@ · %lu %@",definition,(unsigned long)excluded,_("excluded")],CGRectMake(12,bottom+5,w-24,line*(vertical?3:2)+4),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    [self addHit:hits rect:CGRectMake(8,bottom,w-16,h-bottom) kind:@"exclusions" item:@{} metrics:@[BAAnalyticsHistorySOCPercent] label:[NSString stringWithFormat:@"%@, %lu %@",definition,(unsigned long)excluded,_("excluded")]];
    if (!samples.count) {
        BASHatch(CGRectMake(12,top,w-24,MAX(8,bottom-top-8)));
        BASText(_("No complete 20–80% crossings"),CGRectMake(18,top+12,w-36,MAX(line*2,bottom-top-12)),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
        [self addHit:hits rect:CGRectMake(12,top,w-24,MAX(8,bottom-top)) kind:@"distribution" item:@{} metrics:@[BAAnalyticsHistorySOCPercent] label:_("No complete 20–80% crossings")];
        return;
    }
    double lo=[self.analysis[@"minimum"] doubleValue],hi=[self.analysis[@"maximum"] doubleValue];
    double padding=MAX(2,(hi-lo)*.12), axisLo=MAX(0,lo-padding),axisHi=hi+padding;
    BOOL scatter=self.cardSize == BAAnalyticsCardSize2x2;
    CGFloat chartBottom=scatter ? top+(bottom-top)*.47 : bottom-(vertical?line+8:8);
    CGRect chart=CGRectMake(vertical?40:24,top+12,vertical?w-56:w-48,MAX(16,chartBottom-top-line-12));
    [self addHit:hits rect:CGRectInset(chart,-8,-8) kind:@"distribution" item:@{} metrics:@[BAAnalyticsHistorySOCPercent] label:[NSString stringWithFormat:_("%@, n=%lu, %@ %.1f min"),_("20–80% charge duration distribution"),(unsigned long)samples.count,_("estimated median"),[self.analysis[@"median"] doubleValue]]];
    CGFloat (^position)(double)=^CGFloat(double value) {
        double t=(value-axisLo)/(axisHi-axisLo);
        return vertical ? CGRectGetMaxY(chart)-t*chart.size.height : chart.origin.x+t*chart.size.width;
    };
    UIColor *blue=[UIColor compatBlueColor], *muted=[UIColor compatSecondaryLabelColor];
    CGFloat center=vertical ? chart.origin.x+chart.size.width*.4 : chart.origin.y+chart.size.height*.35;
    CGFloat boxHalf=MAX(3,MIN(11,(chart.size.height-12)/2));
    if (vertical) {
        BASLine(CGPointMake(31,chart.origin.y),CGPointMake(31,CGRectGetMaxY(chart)),[UIColor compatSeparatorColor],1);
        BASText([NSString stringWithFormat:@"%.0f",hi],CGRectMake(4,position(hi)-line/2,24,line+2),font,muted,NSTextAlignmentRight);
        BASText([NSString stringWithFormat:@"%.0f",lo],CGRectMake(4,position(lo)-line/2,24,line+2),font,muted,NSTextAlignmentRight);
        BASText(_("≈ min"),CGRectMake(12,chartBottom+1,w-24,line+3),font,muted,NSTextAlignmentLeft);
    } else {
        CGFloat axis=CGRectGetMaxY(chart);
        BASLine(CGPointMake(chart.origin.x,axis),CGPointMake(CGRectGetMaxX(chart),axis),[UIColor compatSeparatorColor],1);
        BASText([NSString stringWithFormat:@"%.1f",axisLo],CGRectMake(chart.origin.x,axis+2,chart.size.width/2,line+2),font,muted,NSTextAlignmentLeft);
        BASText([NSString stringWithFormat:_("%.1f min"),axisHi],CGRectMake(chart.origin.x+chart.size.width/2,axis+2,chart.size.width/2,line+2),font,muted,NSTextAlignmentRight);
    }
    if (hasBox) {
        CGFloat a=position(lo),b=position(hi),q1=position([self.analysis[@"q1"] doubleValue]),q3=position([self.analysis[@"q3"] doubleValue]),m=position([self.analysis[@"median"] doubleValue]);
        if (vertical) {
            BASLine(CGPointMake(center,a),CGPointMake(center,b),blue,1.5);
            BASLine(CGPointMake(center-7,a),CGPointMake(center+7,a),blue,1.5); BASLine(CGPointMake(center-7,b),CGPointMake(center+7,b),blue,1.5);
            BASFill(CGRectMake(center-14,q3,28,MAX(2,q1-q3)),[blue colorWithAlphaComponent:.18]);
            BASLine(CGPointMake(center-16,m),CGPointMake(center+16,m),blue,2);
        } else {
            BASLine(CGPointMake(a,center),CGPointMake(b,center),blue,1.5);
            BASLine(CGPointMake(a,center-MIN(7,boxHalf)),CGPointMake(a,center+MIN(7,boxHalf)),blue,1.5); BASLine(CGPointMake(b,center-MIN(7,boxHalf)),CGPointMake(b,center+MIN(7,boxHalf)),blue,1.5);
            BASFill(CGRectMake(q1,center-boxHalf,MAX(2,q3-q1),boxHalf*2),[blue colorWithAlphaComponent:.18]);
            BASLine(CGPointMake(m,center-boxHalf-2),CGPointMake(m,center+boxHalf+2),blue,2);
        }
    }
    NSUInteger index=0;
    for (NSDictionary *sample in samples) {
        CGFloat v=position([sample[@"minutes"] doubleValue]);
        CGPoint p=vertical ? CGPointMake(center+22+(index%3)*7,v) : CGPointMake(v,MIN(CGRectGetMaxY(chart)-7,center+boxHalf+8)+(index%2)*3);
        BASDot(p,blue,3);
        [self addHit:hits rect:CGRectMake(p.x-4,p.y-4,8,8) kind:@"session" item:sample metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius] label:BASSampleLabel(sample)]; index++;
    }
    if (scatter) {
        CGFloat sy=chartBottom+line+20, sh=MAX(8,bottom-sy-line-8); CGRect plot=CGRectMake(48,sy,w-64,sh);
        double tlo=INFINITY,thi=-INFINITY; NSUInteger temperatureCount=0;
        for (NSDictionary *sample in samples) if (sample[@"peakCelsius"]) { double t=[sample[@"peakCelsius"] doubleValue]; tlo=MIN(tlo,t); thi=MAX(thi,t); temperatureCount++; }
        BAAnalyticsDrawGlyph(BAAnalyticsGlyphThermometer,CGRectMake(12,sy-line-8,13,line),muted);
        BASText(@"°C",CGRectMake(30,sy-line-8,w-42,line+4),font,muted,NSTextAlignmentLeft);
        if (!temperatureCount) {
            BASHatch(plot); BASText(_("Temperature unavailable"),CGRectInset(plot,6,4),font,muted,NSTextAlignmentLeft);
        } else {
            double tp=MAX(.5,(thi-tlo)*.1);tlo-=tp;thi+=tp;
            BASLine(CGPointMake(plot.origin.x,plot.origin.y),CGPointMake(plot.origin.x,CGRectGetMaxY(plot)),[UIColor compatSeparatorColor],1);
            BASLine(CGPointMake(plot.origin.x,CGRectGetMaxY(plot)),CGPointMake(CGRectGetMaxX(plot),CGRectGetMaxY(plot)),[UIColor compatSeparatorColor],1);
            BASText([NSString stringWithFormat:@"%.1f",thi],CGRectMake(4,plot.origin.y,40,line+2),font,muted,NSTextAlignmentRight);
            BASText([NSString stringWithFormat:@"%.1f",tlo],CGRectMake(4,CGRectGetMaxY(plot)-line,40,line+2),font,muted,NSTextAlignmentRight);
            BASText([NSString stringWithFormat:@"%.1f",axisLo],CGRectMake(plot.origin.x,CGRectGetMaxY(plot)+2,plot.size.width/2,line+3),font,muted,NSTextAlignmentLeft);
            BASText([NSString stringWithFormat:_("%.1f ≈ min"),axisHi],CGRectMake(plot.origin.x+plot.size.width/2,CGRectGetMaxY(plot)+2,plot.size.width/2,line+3),font,muted,NSTextAlignmentRight);
            // Sessions remain independent marks. No line or causal inference between them.
            for (NSDictionary *sample in samples) if (sample[@"peakCelsius"]) {
                CGPoint p=CGPointMake(plot.origin.x+([sample[@"minutes"] doubleValue]-axisLo)/(axisHi-axisLo)*plot.size.width,CGRectGetMaxY(plot)-([sample[@"peakCelsius"] doubleValue]-tlo)/(thi-tlo)*plot.size.height);
                BASDot(p,[UIColor compatOrangeColor],3.5);
                [self addHit:hits rect:CGRectMake(p.x-4,p.y-4,8,8) kind:@"session" item:sample metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius] label:BASSampleLabel(sample)];
            }
        }
    }
}
@end
