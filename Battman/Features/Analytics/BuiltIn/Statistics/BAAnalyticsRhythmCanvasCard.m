#import "BAStatisticsDrawing.h"
#import "../Canvas/BAAnalyticsDetailViewController.h"
static NSString *BASRhythmLabel(NSDictionary *item) {
    NSString *rate = item[@"rate"] ? [NSString stringWithFormat:_("Battery drop %.2f%% / h"), [item[@"rate"] doubleValue]] : _("No recorded unplugged battery level");
    return [NSString stringWithFormat:@"%@ · %@ · %@ %@ · %@ %@ · %@ %@",item[@"hourLabel"] ?: item[@"label"] ?: @"",rate,BASTime([item[@"validSeconds"] doubleValue]),_("unplugged"),BASTime([item[@"connectedSeconds"] doubleValue]),_("connected"),BASTime([item[@"missingSeconds"] doubleValue]),_("missing")];
}
@interface BASRhythmView : BASStatisticalView
@end

// A day expanded into actual civil-hour observations. Repeated hours remain
// distinct bars; unavailable hours are hatched, rather than presented as zero.
@interface BASRhythmDetailChart : UIView
@property (nonatomic, copy) NSDictionary *day;
@property (nonatomic, copy) NSDate *selectedStart;
@end
@implementation BASRhythmDetailChart
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 354); }
- (void)drawRect:(CGRect)rect {
    CGFloat w=self.bounds.size.width;
    UIFont *font=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[UIFont systemFontOfSize:12] maximumPointSize:16];
    CGFloat line=ceil(font.lineHeight);
    UIColor *muted=[UIColor compatSecondaryLabelColor], *blue=[UIColor compatBlueColor], *orange=[UIColor compatOrangeColor], *gray=[UIColor compatGray4Color];
    BASText(_("Battery drop / hour"),CGRectMake(16,8,w-32,line+4),font,muted,NSTextAlignmentLeft);
    NSArray<NSDictionary *> *hours=self.day[@"hours"] ?: @[];
    double scale=1; BOOL negative=NO;
    for (NSDictionary *hour in hours) if (hour[@"rate"]) { double value=[hour[@"rate"] doubleValue]; scale=MAX(scale,fabs(value)); negative|=value<0; }
    NSString *upperLabel=[NSString stringWithFormat:@"%.1f%%",scale], *lowerLabel=[NSString stringWithFormat:@"−%.1f%%",scale];
    CGFloat axisWidth=ceil([(negative?lowerLabel:upperLabel) sizeWithAttributes:@{NSFontAttributeName:font}].width);
    CGFloat left=MAX(54,axisWidth+18);
    CGRect plot=CGRectMake(left,line+26,w-left-16,MAX(40,self.bounds.size.height-line*6-72));
    if (!hours.count) { BASHatch(plot); return; }
    CGFloat zero=negative ? CGRectGetMidY(plot) : CGRectGetMaxY(plot), range=negative ? plot.size.height*.45 : plot.size.height*.9;
    BASLine(CGPointMake(plot.origin.x,plot.origin.y),CGPointMake(plot.origin.x,CGRectGetMaxY(plot)),[UIColor compatSeparatorColor],1);
    BASLine(CGPointMake(plot.origin.x,zero),CGPointMake(CGRectGetMaxX(plot),zero),[UIColor compatSeparatorColor],1);
    BASText(upperLabel,CGRectMake(4,zero-range-line/2,left-12,line+4),font,muted,NSTextAlignmentRight);
    BASText(@"0%",CGRectMake(4,zero-line/2,left-12,line+4),font,muted,NSTextAlignmentRight);
    if (negative) BASText(lowerLabel,CGRectMake(4,zero+range-line/2,left-12,line+4),font,muted,NSTextAlignmentRight);
    CGFloat column=plot.size.width/hours.count, railY=CGRectGetMaxY(plot)+10;
    NSUInteger index=0;
    for (NSDictionary *hour in hours) {
        CGFloat x=plot.origin.x+index*column, barWidth=MAX(2,column-2);
        BOOL selected=[hour[@"startDate"] isEqualToDate:self.selectedStart];
        if (selected) BASFill(CGRectMake(x-1,plot.origin.y,column+1,plot.size.height+18),[blue colorWithAlphaComponent:.1]);
        if (hour[@"rate"]) {
            double rate=[hour[@"rate"] doubleValue]; CGFloat height=fabs(rate)/scale*range;
            if (rate==0) BASLine(CGPointMake(x,zero),CGPointMake(x+barWidth,zero),blue,2);
            else BASFill(CGRectMake(x,rate<0?zero:zero-height,barWidth,MAX(2,height)),rate<0?orange:blue);
        } else BASHatch(CGRectMake(x,plot.origin.y,barWidth,MAX(4,zero-plot.origin.y)));
        double elapsed=[hour[@"endDate"] timeIntervalSinceDate:hour[@"startDate"]];
        CGRect rail=CGRectMake(x,railY,barWidth,7); BASHatch(rail);
        if (elapsed>0) {
            CGFloat observed=barWidth*[hour[@"validSeconds"] doubleValue]/elapsed, connected=barWidth*[hour[@"connectedSeconds"] doubleValue]/elapsed;
            if (observed>0) BASFill(CGRectMake(x,railY,observed,7),blue);
            if (connected>0) BASFill(CGRectMake(x+observed,railY,connected,7),gray);
        }
        if (index==0 || index==hours.count-1 || (index%6==0 && index+2<hours.count)) {
            CGFloat labelX=MIN(w-42,MAX(plot.origin.x,x-12));
            BASText([NSString stringWithFormat:@"%02lu",[hour[@"hour"] unsignedLongValue]],CGRectMake(labelX,railY+11,26,line+4),font,muted,NSTextAlignmentCenter);
        }
        index++;
    }
    CGFloat legendY=railY+line+25;
    double valid=[self.day[@"validSeconds"] doubleValue], connected=[self.day[@"connectedSeconds"] doubleValue], missing=[self.day[@"missingSeconds"] doubleValue];
    NSArray *labels=@[[NSString stringWithFormat:_("Unplugged %@"),BASTime(valid)],[NSString stringWithFormat:_("Connected %@"),BASTime(connected)],[NSString stringWithFormat:_("Missing %@"),BASTime(missing)]];
    NSArray *colors=@[blue,gray];
    for (NSUInteger i=0;i<labels.count;i++) {
        CGRect mark=CGRectMake(16,legendY+i*(line+5)+3,9,9);
        if (i<2) BASFill(mark,colors[i]); else BASHatch(mark);
        BASText(labels[i],CGRectMake(32,legendY+i*(line+5),w-48,line+4),font,muted,NSTextAlignmentLeft);
    }
}
@end

@interface BASRhythmDetailViewController : BAAnalyticsDetailViewController
@property (nonatomic, copy) NSDictionary *frozenAnalysis;
@end
@implementation BASRhythmDetailViewController
- (NSDictionary *)rhythmAnalysis { return self.frozenAnalysis ?: @{}; }
- (NSDictionary *)selectedDay:(NSDictionary *)analysis {
    NSArray *days=analysis[@"days"];
    if ([self.selection.kind isEqualToString:@"day"] || [self.selection.kind isEqualToString:@"hour"]) {
        NSDate *selected=self.selection.startDate;
        for (NSDictionary *day in days) if (selected && [selected compare:day[@"startDate"]]!=NSOrderedAscending && [selected compare:day[@"endDate"]]==NSOrderedAscending) return day;
    }
    return days.lastObject;
}
- (UIView *)makeVisualizationView {
    NSDictionary *day=[self selectedDay:[self rhythmAnalysis]];
    if (!day) return nil;
    BASRhythmDetailChart *chart=[[BASRhythmDetailChart alloc] initWithFrame:CGRectMake(0,0,320,354)];
    chart.backgroundColor=[UIColor compatBackgroundColor]; chart.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    chart.day=day; if ([self.selection.kind isEqualToString:@"hour"]) chart.selectedStart=self.selection.startDate;
    chart.isAccessibilityElement=YES;
    chart.accessibilityLabel=[NSString stringWithFormat:_("%@, hourly battery drop and recorded time"),day[@"label"]];
    return chart;
}
- (NSArray<NSDictionary *> *)summaryRows {
    NSDictionary *analysis=[self rhythmAnalysis], *day=[self selectedDay:analysis];
    NSMutableArray *rows=[NSMutableArray array];
    if (day) [rows addObject:@{@"title":_("Shown day"),@"value":day[@"label"]}];
    if ([self.selection.kind isEqualToString:@"hour"]) {
        NSDictionary *context=self.selection.context;
        if (context[@"localHour"]) [rows addObject:@{@"title":_("Selected hour"),@"value":context[@"localHour"]}];
        [rows addObject:@{@"title":_("Battery drop per hour"),@"value":context[@"ratePPPerHour"] ? [NSString stringWithFormat:_("%.2f pp/h"),[context[@"ratePPPerHour"] doubleValue]] : _("No recorded unplugged battery level")}];
        [rows addObject:@{@"title":_("Observed unplugged time"),@"value":BASTime([context[@"validUnpluggedMinutes"] doubleValue]*60)}];
        [rows addObject:@{@"title":_("Connected time"),@"value":BASTime([context[@"connectedMinutes"] doubleValue]*60)}];
        [rows addObject:@{@"title":_("Missing time"),@"value":BASTime([context[@"missingMinutes"] doubleValue]*60)}];
    } else if (day) {
        [rows addObject:@{@"title":_("Daily battery drop per hour"),@"value":day[@"rate"] ? [NSString stringWithFormat:_("%.2f pp/h"),[day[@"rate"] doubleValue]] : _("No recorded unplugged battery level")}];
    }
    [rows addObject:@{@"title":_("Window observation coverage"),@"value":BASCoverage(analysis,@"validSeconds",@"missingSeconds")}];
    [rows addObject:@{@"title":_("Method"),@"value":_("Signed SOC decline divided by trusted unplugged time. Connected and missing intervals do not enter the rate. A negative value is an observed SOC rise, not inferred charging.")}];
    [rows addObject:@{@"title":_("Time zone"),@"value":analysis[@"context"][@"timeZone"] ?: NSCalendar.currentCalendar.timeZone.name}];
    return rows;
}
@end

@interface BASRhythmCard : BASStatisticalCard
@end
@implementation BASRhythmCard
- (BOOL)supportsDetails { return YES; }
- (BAAnalyticsCanvasView *)makeCanvasView { BASRhythmView *view=[BASRhythmView new]; view.accessibilityLabel=self.analyticsCardDisplayName; return view; }
- (NSDictionary *)deriveAnalysisForFamilyReport:(BAAnalyticsFamilyReport *)family calendar:(NSCalendar *)calendar { return BAStatisticsRhythm(family.window,calendar); }
- (UIViewController *)detailViewControllerForSelection:(BAAnalyticsDetailSelection *)selection size:(BAAnalyticsCardSize)size {
    [self deriveIfNeeded];
    BAAnalyticsReport *report=self.displayedReport;
    BAAnalyticsFamilyReport *family=[report reportForFamily:self.familyIdentifier];
    if (!self.analysis && (family.availability==BAAnalyticsReportAvailabilityReady || family.availability==BAAnalyticsReportAvailabilityPartial)) return nil;
    BASRhythmDetailViewController *detail=[[BASRhythmDetailViewController alloc] initWithDisplayName:self.analyticsCardDisplayName familyIdentifier:self.familyIdentifier report:report snapshot:self.latestSnapshot selection:[self selectionForDisplayedReport:selection]];
    detail.frozenAnalysis=self.analysis;
    return detail;
}
@end

id<BAAnalyticsCard> BAAnalyticsCreateRhythmCanvasCard(void) {
    return [[BASRhythmCard alloc] initWithIdentifier:@"com.torrekie.battman.analytics.rhythm" displayName:_("Discharge rhythm") familyIdentifier:BAAnalyticsFamilyRhythm supportedSizes:BAAnalyticsCardSizeMask2x1|BAAnalyticsCardSizeMask2x2 defaultSize:BAAnalyticsCardSize2x2];
}
@implementation BASRhythmView
- (NSArray *)summaryRows {
    if (!self.analysis) return @[];
    NSMutableArray *rows=[NSMutableArray array];
    [rows addObject:@{@"text":BASCoverage(self.analysis,@"validSeconds",@"missingSeconds"),@"kind":@"coverage",@"item":@{}}];
    for (NSDictionary *day in self.analysis[@"days"]) {
        [rows addObject:@{@"text":BASRhythmLabel(day),@"kind":@"day",@"item":day,@"metrics":@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected]}];
        for (NSDictionary *hour in day[@"hours"]) [rows addObject:@{@"text":[NSString stringWithFormat:@"%@ · %@",day[@"label"],BASRhythmLabel(hour)],@"kind":@"hour",@"item":hour,@"metrics":@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected]}];
    }
    return rows;
}
- (void)drawStatistics:(NSMutableArray *)hits {
    CGFloat w=self.bounds.size.width,h=self.bounds.size.height; UIFont *font=BASFont(11);CGFloat line=ceil(font.lineHeight);
    NSArray *days=self.analysis[@"days"] ?: @[]; BOOL matrix=self.cardSize==BAAnalyticsCardSize2x2;
    UIFont *titleFont=BASFont(13);
    NSString *title=_("Battery drop / hour"), *window=BASWindow(self.familyReport.window);
    CGFloat titleHeight=BASTextHeight(title,w-24,titleFont),windowHeight=BASTextHeight(window,w-24,font);
    BASText(title,CGRectMake(12,10,w-24,titleHeight),titleFont,[UIColor compatLabelColor],NSTextAlignmentLeft);
    CGFloat windowY=14+titleHeight;
    BASText(window,CGRectMake(12,windowY,w-24,windowHeight),font,[UIColor compatSecondaryLabelColor],NSTextAlignmentLeft);
    CGFloat top=windowY+windowHeight+8,bottom=h-line*3-20;
    double scale=0; BOOL hasNegative=NO;
    for (NSDictionary *day in days) {
        if (matrix) { for (NSDictionary *hour in day[@"hours"]) if (hour[@"rate"]) { scale=MAX(scale,fabs([hour[@"rate"] doubleValue])); hasNegative |= [hour[@"rate"] doubleValue]<0; } }
        else if (day[@"rate"]) { scale=MAX(scale,fabs([day[@"rate"] doubleValue])); hasNegative |= [day[@"rate"] doubleValue]<0; }
    }
    // A zero is an observed value. A nil rate is never drawn as zero.
    scale=MAX(1,scale);
    UIColor *blue=[UIColor compatBlueColor], *gray=[UIColor compatGray4Color], *muted=[UIColor compatSecondaryLabelColor];
    if (!days.count) {
        BASHatch(CGRectMake(12,top,w-24,MAX(8,bottom-top)));
    } else if (matrix) {
        CGFloat dayLabelWidth=0;
        for (NSDictionary *day in days) dayLabelWidth=MAX(dayLabelWidth,ceil([day[@"label"] sizeWithAttributes:@{NSFontAttributeName:font}].width));
        CGFloat left=MAX(42,dayLabelWidth+14),cw=(w-left-12)/24,ch=MAX(8,(bottom-top-line-8)/days.count);
        BASText(@"00",CGRectMake(left,top,30,line+3),font,muted,NSTextAlignmentLeft);
        BASText(@"12",CGRectMake(left+12*cw-15,top,30,line+3),font,muted,NSTextAlignmentCenter);
        NSString *endHour=_("23 h");
        CGFloat endHourWidth=ceil([endHour sizeWithAttributes:@{NSFontAttributeName:font}].width)+2;
        BASText(endHour,CGRectMake(w-12-endHourWidth,top,endHourWidth,line+3),font,muted,NSTextAlignmentRight);top+=line+5;
        NSUInteger row=0;
        for (NSDictionary *day in days) {
            CGFloat y=top+row*ch;
            BASText(day[@"label"],CGRectMake(6,y+(ch-line)/2,left-12,line+3),font,muted,NSTextAlignmentRight);
            NSMutableDictionary<NSNumber *,NSMutableArray *> *hours=[NSMutableDictionary dictionary];
            for (NSDictionary *hour in day[@"hours"]) { NSNumber *key=hour[@"hour"]; if (!key) continue; if (!hours[key]) hours[key]=[NSMutableArray array]; [hours[key] addObject:hour]; }
            for (NSInteger hourIndex=0;hourIndex<24;hourIndex++) {
                NSArray *matches=hours[@(hourIndex)];
                if (!matches.count) {
                    // A skipped civil hour has no elapsed time, unlike a missing observation.
                    CGRect absent=CGRectMake(left+hourIndex*cw,y,cw-1,ch-2);
                    BASLine(CGPointMake(CGRectGetMidX(absent)-2,CGRectGetMidY(absent)-2),CGPointMake(CGRectGetMidX(absent)+2,CGRectGetMidY(absent)+2),[UIColor compatSeparatorColor],1);
                    continue;
                }
                NSUInteger part=0;
                for (NSDictionary *hour in matches) {
                    CGRect cell=CGRectMake(left+hourIndex*cw+part*cw/matches.count,y,cw/matches.count-1,ch-2);
                    double duration=[hour[@"endDate"] timeIntervalSinceDate:hour[@"startDate"]],valid=[hour[@"validSeconds"] doubleValue],connected=[hour[@"connectedSeconds"] doubleValue],missing=[hour[@"missingSeconds"] doubleValue];
                    BASFill(cell, [UIColor tertiaryCompatFillColor]);
                    CGFloat validHeight=duration>0 ? cell.size.height*valid/duration : 0,connectedHeight=duration>0 ? cell.size.height*connected/duration : 0;
                    if (valid>0 && hour[@"rate"]) {
                        double rate=[hour[@"rate"] doubleValue]; UIColor *color=rate<0 ? [UIColor compatOrangeColor] : blue;
                        CGRect observed=CGRectMake(cell.origin.x,cell.origin.y,cell.size.width,validHeight);
                        BASFill(observed,[color colorWithAlphaComponent:.09+.7*MIN(1,fabs(rate)/scale)]);
                        if (rate==0) BASLine(CGPointMake(CGRectGetMidX(observed)-1,CGRectGetMidY(observed)),CGPointMake(CGRectGetMidX(observed)+1,CGRectGetMidY(observed)),muted,1);
                        if (rate<0) {
                            CGPoint tip=CGPointMake(CGRectGetMidX(observed),CGRectGetMidY(observed)-2);
                            BASLine(CGPointMake(tip.x-2,tip.y+3),tip,muted,1); BASLine(tip,CGPointMake(tip.x+2,tip.y+3),muted,1);
                        }
                    }
                    if (connected>0) BASFill(CGRectMake(cell.origin.x,cell.origin.y+validHeight,cell.size.width,connectedHeight),gray);
                    CGFloat knownHeight = MIN(cell.size.height, validHeight + connectedHeight);
                    if (valid<=0 && connected<=0) BASHatch(cell);
                    else if (missing > 0) BASHatch(CGRectMake(cell.origin.x, cell.origin.y + knownHeight, cell.size.width, MAX(0, cell.size.height - knownHeight)));
                    NSString *label=[NSString stringWithFormat:@"%@, %@",day[@"label"],BASRhythmLabel(hour)];
                    [self addHit:hits rect:cell kind:@"hour" item:hour metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected] label:label]; part++;
                }
            }
            row++;
        }
    } else {
        CGFloat cw=(w-24)/days.count,labelY=h-line*3-22,chartEnd=labelY-6,chartHeight=MAX(8,chartEnd-top),zero=top+chartHeight*(hasNegative?.5:.8);
        BASLine(CGPointMake(12,zero),CGPointMake(w-12,zero),[UIColor compatSeparatorColor],1);
        CGFloat widestDate=0;
        for (NSDictionary *day in days) widestDate=MAX(widestDate,ceil([day[@"label"] sizeWithAttributes:@{NSFontAttributeName:font}].width));
        NSUInteger tickStride=MAX(1,(NSUInteger)ceil((widestDate+6)/cw));
        NSUInteger index=0;
        for (NSDictionary *day in days) {
            CGFloat x=12+index*cw,bw=MAX(4,cw-8);double duration=[day[@"endDate"] timeIntervalSinceDate:day[@"startDate"]];
            if (day[@"rate"]) {
                double rate=[day[@"rate"] doubleValue];CGFloat bh=fabs(rate)/scale*chartHeight*(hasNegative?.45:.75);
                if (rate==0) BASLine(CGPointMake(x,zero),CGPointMake(x+bw,zero),blue,2);
                else BASFill(CGRectMake(x,rate<0?zero:zero-bh,bw,MAX(2,bh)),rate<0?[UIColor compatOrangeColor]:blue);
            } else {
                CGRect unavailable=CGRectMake(x,top,bw,MAX(4,zero-top)); BASHatch(unavailable);
                if (duration>0 && [day[@"connectedSeconds"] doubleValue]>0) BASFill(CGRectMake(x,top,bw,unavailable.size.height*[day[@"connectedSeconds"] doubleValue]/duration),gray);
            }
            CGRect rail=CGRectMake(x,chartEnd-4,bw,4);BASHatch(rail);
            if (duration>0) {
                CGFloat validWidth=bw*[day[@"validSeconds"] doubleValue]/duration,connectedWidth=bw*[day[@"connectedSeconds"] doubleValue]/duration;
                if (validWidth>0) BASFill(CGRectMake(x,rail.origin.y,validWidth,4),blue);
                if (connectedWidth>0) BASFill(CGRectMake(x+validWidth,rail.origin.y,connectedWidth,4),gray);
            }
            if (index==0 || index+1==days.count || (index%tickStride==0 && index+tickStride<days.count)) {
                CGFloat dateWidth=MAX(cw-4,widestDate),dateX=MIN(w-12-dateWidth,MAX(12,x+(bw-dateWidth)/2));
                BASText(day[@"label"],CGRectMake(dateX,labelY,dateWidth,line+3),font,muted,NSTextAlignmentCenter);
            }
            [self addHit:hits rect:CGRectMake(x,top,bw,labelY-top+line+4) kind:@"day" item:day metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected] label:BASRhythmLabel(day)];index++;
        }
    }
    CGFloat legendY=h-line*2-17;
    NSString *range=[NSString stringWithFormat:hasNegative ? _("±%.1f%%") : _("0–%.1f%%"),scale];
    NSString *pluggedLabel=_("Plugged in"), *missingLabel=_("No data");
    CGFloat rangeWidth=ceil([range sizeWithAttributes:@{NSFontAttributeName:font}].width)+12;
    CGFloat connectedWidth=ceil([pluggedLabel sizeWithAttributes:@{NSFontAttributeName:font}].width)+18;
    CGFloat missingWidth=ceil([missingLabel sizeWithAttributes:@{NSFontAttributeName:font}].width)+16;
    CGFloat legendGap=MAX(0,(w-24-rangeWidth-connectedWidth-missingWidth)/2);
    BASFill(CGRectMake(12,legendY+3,8,8),blue);
    if (hasNegative) BASFill(CGRectMake(12,legendY+7,8,4),[UIColor compatOrangeColor]);
    BASText(range,CGRectMake(24,legendY,rangeWidth-12,line+3),font,muted,NSTextAlignmentLeft);
    CGFloat connectedX=12+rangeWidth+legendGap, missingX=connectedX+connectedWidth+legendGap;
    BASFill(CGRectMake(connectedX,legendY+2,14,12),gray);
    BAAnalyticsDrawGlyph(BAAnalyticsGlyphConnected,CGRectMake(connectedX+2,legendY+2,10,12),muted);
    BASText(pluggedLabel,CGRectMake(connectedX+18,legendY,connectedWidth-18,line+3),font,muted,NSTextAlignmentLeft);
    BASHatch(CGRectMake(missingX,legendY+3,11,10));
    BASText(missingLabel,CGRectMake(missingX+16,legendY,missingWidth-16,line+3),font,muted,NSTextAlignmentLeft);
    NSString *coverage=[NSString stringWithFormat:_("Recorded unplugged %@"),BASTime([self.analysis[@"validSeconds"] doubleValue])];
    NSString *riseLegend=_("Orange: level rose");
    CGFloat riseWidth=hasNegative ? ceil([riseLegend sizeWithAttributes:@{NSFontAttributeName:font}].width)+8 : 0;
    if ([coverage sizeWithAttributes:@{NSFontAttributeName:font}].width > w-24-riseWidth) coverage=[NSString stringWithFormat:_("Unplugged %@"),BASTime([self.analysis[@"validSeconds"] doubleValue])];
    BASText(coverage,CGRectMake(12,h-line-10,w-24-riseWidth,line+3),font,muted,NSTextAlignmentLeft);
    if (hasNegative) BASText(riseLegend,CGRectMake(w-12-riseWidth,h-line-10,riseWidth,line+3),font,[UIColor compatOrangeColor],NSTextAlignmentRight);
    [self addHit:hits rect:CGRectMake(8,legendY-4,w-16,h-legendY+4) kind:@"coverage" item:@{} metrics:@[BAAnalyticsHistorySOCPercent,BAAnalyticsHistoryExternalConnected] label:BASRhythmLabel(self.analysis)];
}
@end
