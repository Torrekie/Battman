#import "BAStatisticsDrawing.h"
#import "../Canvas/BAAnalyticsDetailViewController.h"
@interface BASDwellView : BASStatisticalView
@end

// Exact dwell values open a distribution, with the selected range highlighted.
// The chart uses only the frozen normalized report that produced the tap.
@interface BASDwellDetailChart : UIView
@property (nonatomic, copy) NSArray<NSDictionary *> *bins;
@property (nonatomic, copy) NSString *selectedBin;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic) double validSeconds;
@property (nonatomic) double missingSeconds;
@end
@implementation BASDwellDetailChart
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 360); }
- (void)drawRect:(CGRect)rect {
    UIColor *label=[UIColor compatLabelColor], *muted=[UIColor compatSecondaryLabelColor];
    UIFont *font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12] maximumPointSize:16];
    CGFloat w=self.bounds.size.width, line=ceil(font.lineHeight), top=line+24;
    BASText(self.caption ?: _("Observed dwell · h"),CGRectMake(16,8,w-32,line+4),font,muted,NSTextAlignmentLeft);
    double scale=0; for (NSDictionary *bin in self.bins) scale=MAX(scale,[bin[@"seconds"] doubleValue]);
    CGFloat row=MAX(40,MIN(48,(self.bounds.size.height-top-96)/MAX(1,self.bins.count)));
    CGFloat labelWidth=MIN(102,w*.31), valueWidth=MIN(78,w*.24), left=16+labelWidth+8;
    CGFloat chartWidth=MAX(1,w-left-valueWidth-24);
    NSUInteger index=0;
    for (NSDictionary *bin in self.bins) {
        CGFloat y=top+row*index++;
        NSString *binLabel=bin[@"displayLabel"] ?: bin[@"label"];
        BOOL selected=[bin[@"label"] isEqualToString:self.selectedBin];
        if (selected) BASFill(CGRectMake(10,y-4,w-20,row),[[UIColor compatBlueColor] colorWithAlphaComponent:.09]);
        BASText(binLabel,CGRectMake(16,y,labelWidth,line*2+4),font,selected?[UIColor compatBlueColor]:label,NSTextAlignmentLeft);
        CGRect track=CGRectMake(left,y+line*.35,chartWidth,MAX(7,line*.6));
        BASFill(track,[UIColor tertiaryCompatFillColor]);
        double seconds=[bin[@"seconds"] doubleValue];
        if (scale>0 && seconds>0) BASFill(CGRectMake(left,track.origin.y,chartWidth*seconds/scale,track.size.height),selected?[UIColor compatBlueColor]:[UIColor compatGreenColor]);
        BASText([NSString stringWithFormat:_("%.2f h"),seconds/3600],CGRectMake(w-valueWidth-16,y,valueWidth,line+4),font,label,NSTextAlignmentRight);
    }
    CGFloat y=top+row*self.bins.count+10;
    double total=self.validSeconds+self.missingSeconds;
    CGRect rail=CGRectMake(16,y,w-32,8); BASHatch(rail);
    if (total>0 && self.validSeconds>0) BASFill(CGRectMake(16,y,(w-32)*self.validSeconds/total,8),[UIColor compatGreenColor]);
    BASText([NSString stringWithFormat:_("Observed %@"),BASTime(self.validSeconds)],CGRectMake(16,y+15,w-32,line+4),font,muted,NSTextAlignmentLeft);
    BASText([NSString stringWithFormat:_("Missing %@"),BASTime(self.missingSeconds)],CGRectMake(16,y+line+21,w-32,line+4),font,muted,NSTextAlignmentLeft);
}
@end

@interface BASDwellDetailViewController : BAAnalyticsDetailViewController
@property (nonatomic, copy) NSDictionary *frozenAnalysis;
@end
@implementation BASDwellDetailViewController
- (NSDictionary *)dwellAnalysis { return self.frozenAnalysis ?: @{}; }
- (UIView *)makeVisualizationView {
    NSDictionary *analysis=[self dwellAnalysis];
    if (![analysis[@"socSeconds"] doubleValue]) return nil;
    BASDwellDetailChart *chart=[[BASDwellDetailChart alloc] initWithFrame:CGRectMake(0,0,320,360)];
    chart.backgroundColor=[UIColor compatBackgroundColor];
    chart.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    chart.selectedBin=self.selection.context[@"bin"];
    BOOL joint=[self.selection.kind isEqualToString:@"soc-temperature-bin"];
    NSMutableArray *bins=[NSMutableArray array];
    if (joint) {
        NSNumber *socIndex=nil;
        for (NSDictionary *bin in analysis[@"jointBins"]) if ([bin[@"label"] isEqualToString:chart.selectedBin]) { socIndex=bin[@"socIndex"]; break; }
        if (socIndex) chart.caption=[NSString stringWithFormat:_("SOC %@ · h"),[NSString stringWithFormat:@"%ld–%ld%%",(long)socIndex.integerValue*20,(long)(socIndex.integerValue+1)*20]];
        NSArray *temperatures=@[@"<25 °C",@"25–30 °C",@"30–35 °C",@"≥35 °C"];
        for (NSDictionary *bin in analysis[@"jointBins"]) if ([bin[@"socIndex"] isEqual:socIndex]) {
            NSMutableDictionary *display=[bin mutableCopy]; display[@"displayLabel"]=temperatures[[bin[@"tempIndex"] unsignedIntegerValue]]; [bins addObject:display];
        }
    } else [bins addObjectsFromArray:[analysis[@"socBins"] reverseObjectEnumerator].allObjects];
    chart.bins=bins;
    chart.validSeconds=[analysis[joint?@"jointSeconds":@"socSeconds"] doubleValue];
    chart.missingSeconds=[analysis[joint?@"missingJointSeconds":@"missingSOCSeconds"] doubleValue];
    chart.isAccessibilityElement=YES;
    NSMutableArray *spoken=[NSMutableArray arrayWithObject:_("Observed dwell distribution")];
    for (NSDictionary *bin in bins) [spoken addObject:[NSString stringWithFormat:@"%@, %@",bin[@"displayLabel"] ?: bin[@"label"],BASTime([bin[@"seconds"] doubleValue])]];
    chart.accessibilityLabel=[spoken componentsJoinedByString:@"; "];
    return chart;
}
- (NSArray<NSDictionary *> *)summaryRows {
    NSDictionary *analysis=[self dwellAnalysis], *context=self.selection.context;
    NSMutableArray *rows=[NSMutableArray array];
    if (context[@"bin"]) [rows addObject:@{@"title":_("Selected range"),@"value":[context[@"bin"] stringByReplacingOccurrencesOfString:@"SOC" withString:_("SOC")]}];
    if (context[@"validMinutes"]) [rows addObject:@{@"title":_("Dwell time"),@"value":BASTime([context[@"validMinutes"] doubleValue]*60)}];
    if (context[@"shareOfValidCoverage"]) [rows addObject:@{@"title":_("Share of observed time"),@"value":[NSString stringWithFormat:@"%.1f%%",[context[@"shareOfValidCoverage"] doubleValue]*100]}];
    if (context[@"connectedMinutes"]) [rows addObject:@{@"title":_("Connected time"),@"value":BASTime([context[@"connectedMinutes"] doubleValue]*60)}];
    if (context[@"unpluggedMinutes"]) [rows addObject:@{@"title":_("Unplugged time"),@"value":BASTime([context[@"unpluggedMinutes"] doubleValue]*60)}];
    if (context[@"unknownStateMinutes"]) [rows addObject:@{@"title":_("Unknown connection time"),@"value":BASTime([context[@"unknownStateMinutes"] doubleValue]*60)}];
    [rows addObject:@{@"title":_("Observed SOC"),@"value":BASTime([analysis[@"socSeconds"] doubleValue])}];
    [rows addObject:@{@"title":_("Missing SOC"),@"value":BASTime([analysis[@"missingSOCSeconds"] doubleValue])}];
    [rows addObject:@{@"title":_("Method"),@"value":_("Time weighted across trusted sample pairs. Missing time is excluded from bins; the distribution is not a battery damage score.")}];
    return rows;
}
@end

@interface BASDwellCard : BASStatisticalCard
@end
@implementation BASDwellCard
- (BOOL)supportsDetails { return YES; }
- (BAAnalyticsCanvasView *)makeCanvasView { BASDwellView *view=[BASDwellView new]; view.accessibilityLabel=self.analyticsCardDisplayName; return view; }
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family { return BAStatisticsDwell(family.window); }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    [self deriveIfNeeded];
    BAAnalyticsReport *report=self.displayedReport;
    BAAnalyticsFamilyReport *family=[report reportForFamily:self.familyIdentifier];
    if (!self.analysis && (family.availability==BAAnalyticsReportAvailabilityReady || family.availability==BAAnalyticsReportAvailabilityPartial)) return nil;
    BASDwellDetailViewController *detail=[[BASDwellDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier report:report snapshot:self.latestSnapshot selection:[self selectionForDisplayedReport:selection]];
    detail.frozenAnalysis=self.analysis;
    return detail;
}
@end

id<BAAnalyticsCard> BAAnalyticsCreateDwellCanvasCard(void) {
    return [[BASDwellCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.dwell" displayName:_("SOC dwell") familyIdentifier:BAAnalyticsFamilyDwell supportedSizes:BAAnalyticsCardSizeMask1x2|BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize1x2];
}
@implementation BASDwellView
- (NSArray *)summaryRows {
    if (!self.analysis) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    [rows addObject:@{@"text":BASCoverage(self.analysis, @"socSeconds", @"missingSOCSeconds"), @"kind":@"coverage", @"item":@{}}];
    for (NSDictionary *bin in [self.analysis[@"socBins"] reverseObjectEnumerator]) [rows addObject:@{@"text":[NSString stringWithFormat:_("SOC %@ · %@"),bin[@"label"],BASTime([bin[@"seconds"] doubleValue])],@"kind":@"soc-bin",@"item":bin,@"metrics":@[BAAnalyticsHistorySOCPercent]}];
    [rows addObject:@{@"text":[NSString stringWithFormat:_("SOC × °C · %@"), BASCoverage(self.analysis,@"jointSeconds",@"missingJointSeconds")],@"kind":@"joint-coverage",@"item":@{}}];
    for (NSDictionary *bin in self.analysis[@"jointBins"]) [rows addObject:@{@"text":[NSString stringWithFormat:@"%@ · %@",[bin[@"label"] stringByReplacingOccurrencesOfString:@"SOC" withString:_("SOC")],BASTime([bin[@"seconds"] doubleValue])],@"kind":@"soc-temperature-bin",@"item":bin,@"metrics":@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius]}];
    return rows;
}
- (void)drawStatistics:(NSMutableArray *)hits {
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    UIFont *font = BASFont(11); CGFloat line = ceil(font.lineHeight);
    BOOL matrix = self.cardSize == BAAnalyticsCardSize2x2 && [self.analysis[@"jointSeconds"] doubleValue] > 0;
    NSString *identity = matrix ? _("SOC % × °C · h") : _("SOC % · h");
    BASText(identity, CGRectMake(12,10,w-24,line+2), BASFont(13),[UIColor compatLabelColor],NSTextAlignmentLeft);
    BASText(BASWindow(self.familyReport.window),CGRectMake(12,14+line,w-24,line*2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    CGFloat top = 20+line*3, footer = line*4+26;
    if (matrix) {
        CGFloat left = 56, cw = (w-left-12)/5, ch = MAX(8,(h-top-footer-line-8)/4);
        NSArray *temps = @[@"<25",@"25–30",@"30–35",@"≥35"];
        // Full ranges remain visible; half-open boundary semantics are in detail/VO.
        for (NSInteger j=0;j<5;j++) BASText([NSString stringWithFormat:@"%ld–%ld",(long)j*20,(long)(j+1)*20],CGRectMake(left+j*cw,top,cw,line+2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentCenter);
        top += line+6;
        double max = 0; for (NSDictionary *bin in self.analysis[@"jointBins"]) max = MAX(max,[bin[@"seconds"] doubleValue]);
        for (NSInteger i=0;i<4;i++) {
            BASText(temps[i],CGRectMake(10,top+i*ch+(ch-line)/2,44,line+2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
            for (NSInteger j=0;j<5;j++) {
                NSDictionary *bin = self.analysis[@"jointBins"][(NSUInteger)(i*5+j)]; double seconds = [bin[@"seconds"] doubleValue];
                CGRect cell = CGRectMake(left+j*cw,top+i*ch,cw-3,ch-3);
                BASFill(cell, [[UIColor compatOrangeColor] colorWithAlphaComponent:max > 0 ? .08+.7*seconds/max : .08]);
                if (seconds == 0) BASLine(CGPointMake(CGRectGetMidX(cell)-2,CGRectGetMidY(cell)),CGPointMake(CGRectGetMidX(cell)+2,CGRectGetMidY(cell)),[UIColor compatSecondaryLabelColor],1);
                [self addHit:hits rect:cell kind:@"soc-temperature-bin" item:bin metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryTemperatureCelsius] label:[NSString stringWithFormat:@"%@, %@",[bin[@"label"] stringByReplacingOccurrencesOfString:@"SOC" withString:_("SOC")],BASTime(seconds)]];
            }
        }
        CGFloat y = h-footer;
        BASText([NSString stringWithFormat:_("0–%.2f h"), max/3600],CGRectMake(12,y,w-24,line+2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    } else {
        CGFloat row = MAX(20,(h-top-footer)/5); double max = 0;
        for (NSDictionary *bin in self.analysis[@"socBins"]) max = MAX(max,[bin[@"seconds"] doubleValue]);
        for (NSInteger k=0;k<5;k++) {
            NSDictionary *bin = self.analysis[@"socBins"][(NSUInteger)(4-k)]; double seconds = [bin[@"seconds"] doubleValue]; CGFloat y = top+k*row;
            BASText(bin[@"label"],CGRectMake(12,y,w-24,line+2),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
            CGRect track = CGRectMake(12,y+line+3,w-24,MAX(5,row-line-8)); if ([self.analysis[@"socSeconds"] doubleValue] > 0) BASFill(track,[UIColor tertiaryCompatFillColor]); else BASHatch(track);
            if (max > 0 && seconds > 0) BASFill(CGRectMake(track.origin.x,track.origin.y,track.size.width*seconds/max,track.size.height),[UIColor compatGreenColor]);
            [self addHit:hits rect:CGRectMake(8,y-3,w-16,row) kind:@"soc-bin" item:bin metrics:@[BAAnalyticsHistorySOCPercent] label:[NSString stringWithFormat:_("SOC %@, %@"),bin[@"label"],BASTime(seconds)]];
        }
    }
    if (!matrix) {
        double maxSOCSeconds=0; for (NSDictionary *bin in self.analysis[@"socBins"]) maxSOCSeconds=MAX(maxSOCSeconds,[bin[@"seconds"] doubleValue]);
        NSString *scale = [self.analysis[@"socSeconds"] doubleValue] > 0 ? [NSString stringWithFormat:_("0–%.2f h"),maxSOCSeconds/3600] : _("SOC unavailable");
        if (self.cardSize == BAAnalyticsCardSize2x2 && [self.analysis[@"jointSeconds"] doubleValue] <= 0) scale = [NSString stringWithFormat:@"%@ · %@",scale,_("Temperature unavailable")];
        BASText(scale,CGRectMake(12,h-footer,w-24,line+3),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    }
    CGFloat y = h-line*2-14; double total = [self.analysis[@"windowSeconds"] doubleValue];
    NSString *key = matrix ? @"jointSeconds" : @"socSeconds", *missing = matrix ? @"missingJointSeconds" : @"missingSOCSeconds";
    double valid = [self.analysis[key] doubleValue]; CGRect rail = CGRectMake(12,y-10,w-24,6); BASHatch(rail);
    if (total > 0 && valid > 0) BASFill(CGRectMake(12,y-10,(w-24)*MIN(1,valid/total),6),[UIColor compatGreenColor]);
    BASText(BASCoverage(self.analysis,key,missing),CGRectMake(12,y,w-24,line*2+4),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    [self addHit:hits rect:CGRectMake(8,y-14,w-16,h-y+10) kind:matrix?@"joint-coverage":@"coverage" item:@{} metrics:@[BAAnalyticsHistorySOCPercent] label:BASCoverage(self.analysis,key,missing)];
}
@end
