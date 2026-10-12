#import "BAAnalyticsDetailViewController.h"
#import "BAAnalyticsCanvasCard.h"
#import "../../Data/BAAnalyticsReport.h"
#import "../../Public/BAAnalyticsMetricSnapshot.h"
#import "ObjCExt/UIColor+compat.h"
#import "main.h"
#include <math.h>

// Reusable evidence support, not a required destination. Each participating
// card owns its VC, graphic and summary in that card's source file.
static NSString *BADetailMetricTitle(NSString *metric) {
    if ([metric isEqual:BAAnalyticsHistorySOCPercent]) return _("Charge");
    if ([metric isEqual:BAAnalyticsHistoryTemperatureCelsius]) return _("Temperature");
    if ([metric isEqual:BAAnalyticsHistoryCurrentMilliamps]) return _("Signed current");
    if ([metric isEqual:BAAnalyticsHistoryBatteryPowerWatts]) return _("Signed battery power");
    if ([metric isEqual:BAAnalyticsHistoryFullChargeCapacityMilliampHours]) return _("Full charge capacity");
    if ([metric isEqual:BAAnalyticsHistoryDesignCapacityMilliampHours]) return _("Design capacity");
    if ([metric isEqual:BAAnalyticsHistoryCycleCount]) return _("Cycle count");
    if ([metric hasPrefix:@"cell-voltage."]) {
        NSArray *parts = [metric componentsSeparatedByString:@"."];
        return [NSString stringWithFormat:_("Cell %ld"), (long)[parts[1] integerValue] + 1];
    }
    return metric;
}

static BOOL BADetailObservationMatchesSelection(BAAnalyticsObservation *observation, BAAnalyticsDetailSelection *selection, NSSet<NSString *> *selectedIDs) {
    if (!selection)
        return YES;
    id validatedMetrics = selection.context[@"validatedMetricIdentifiers"];
    if ([validatedMetrics isKindOfClass:NSArray.class]) {
        if (!observation.timestampValidated) return NO;
        for (NSString *metric in validatedMetrics) {
            NSNumber *value = observation.values[metric];
            if (!observation.fieldMetadata[metric].unitValidated || !value || !isfinite(value.doubleValue)) return NO;
        }
    }
    if (selectedIDs.count > 0 && ![selectedIDs containsObject:observation.identifier])
        return NO;
    if (selection.startDate && [observation.timestamp compare:selection.startDate] == NSOrderedAscending)
        return NO;
    if (selection.endDate && [observation.timestamp compare:selection.endDate] == NSOrderedDescending)
        return NO;
    id filters = selection.context[@"filters"];
    if ([filters isKindOfClass:[NSDictionary class]]) {
        for (NSString *metric in filters) {
            id bounds = filters[metric];
            if (![bounds isKindOfClass:[NSDictionary class]])
                continue;
            NSNumber *value = [observation valueForMetricIdentifier:metric];
            if (!value)
                return NO;
            NSNumber *minimum = bounds[@"minimum"];
            NSNumber *maximum = bounds[@"maximum"];
            if ([minimum isKindOfClass:[NSNumber class]] && value.doubleValue < minimum.doubleValue)
                return NO;
            if ([maximum isKindOfClass:[NSNumber class]] &&
                ([bounds[@"includeMaximum"] boolValue] ? value.doubleValue > maximum.doubleValue : value.doubleValue >= maximum.doubleValue))
                return NO;
        }
    }
    return YES;
}

static NSDictionary *BADetailSelectedEvidence(BAAnalyticsFamilyReport *family, BAAnalyticsDetailSelection *selection, BOOL (^cancelled)(void)) {
    if (cancelled && cancelled()) return nil;
    NSUInteger examined = 0;
    NSSet<NSString *> *requested = [NSSet setWithArray:selection.recordIdentifiers ?: @[]];
    NSMutableSet<NSString *> *selectedIDs = [requested mutableCopy];
    NSMutableArray<BAAnalyticsObservation *> *candidates = [family.window.observations mutableCopy] ?: [NSMutableArray array];
    id rawSessions = family.payload[BAAnalyticsPayloadSessions];
    if ([rawSessions isKindOfClass:[NSArray class]]) {
        for (BAAnalyticsHistorySession *session in rawSessions) {
            if (![session isKindOfClass:[BAAnalyticsHistorySession class]] || ![requested containsObject:session.identifier])
                continue;
            [candidates addObjectsFromArray:session.observations];
            for (BAAnalyticsObservation *observation in session.observations)
                [selectedIDs addObject:observation.identifier];
        }
    }
    BAAnalyticsHistorySession *selectedSession = family.payload[BAAnalyticsPayloadSelectedSession];
    if ([selectedSession isKindOfClass:[BAAnalyticsHistorySession class]] && [requested containsObject:selectedSession.identifier]) {
        [candidates addObjectsFromArray:selectedSession.observations];
        for (BAAnalyticsObservation *observation in selectedSession.observations)
            [selectedIDs addObject:observation.identifier];
    }
    NSMutableArray<BAAnalyticsObservation *> *selected = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (BAAnalyticsObservation *observation in candidates) {
        if ((++examined % 256) == 0 && cancelled && cancelled()) return nil;
        if (![observation isKindOfClass:[BAAnalyticsObservation class]] || [seen containsObject:observation.identifier] ||
            !BADetailObservationMatchesSelection(observation, selection, selectedIDs))
            continue;
        [seen addObject:observation.identifier];
        [selected addObject:observation];
    }
    NSMutableArray<BAAnalyticsStateTransition *> *transitions = [NSMutableArray array];
    id rawTransitions = family.payload[BAAnalyticsPayloadTransitions];
    if ([rawTransitions isKindOfClass:[NSArray class]]) {
        for (BAAnalyticsStateTransition *transition in rawTransitions) {
            if (![transition isKindOfClass:[BAAnalyticsStateTransition class]])
                continue;
            if (requested.count > 0 && ![requested containsObject:transition.identifier])
                continue;
            if (selection.startDate && [transition.latestDate compare:selection.startDate] == NSOrderedAscending)
                continue;
            if (selection.endDate && [transition.earliestDate compare:selection.endDate] == NSOrderedDescending)
                continue;
            [transitions addObject:transition];
            if ([requested containsObject:transition.identifier]) {
                for (BAAnalyticsObservation *observation in family.window.observations) {
                    if ((++examined % 256) == 0 && cancelled && cancelled()) return nil;
                    if ([seen containsObject:observation.identifier] ||
                        [observation.timestamp compare:transition.earliestDate] == NSOrderedAscending ||
                        [observation.timestamp compare:transition.latestDate] == NSOrderedDescending)
                        continue;
                    [seen addObject:observation.identifier];
                    [selected addObject:observation];
                }
            }
        }
    }
    BOOL ordered = YES;
    for (NSUInteger i = 1; i < selected.count; i++) {
        if ([selected[i - 1].timestamp compare:selected[i].timestamp] == NSOrderedDescending) { ordered = NO; break; }
    }
    if (!ordered) [selected sortUsingComparator:^NSComparisonResult(BAAnalyticsObservation *a, BAAnalyticsObservation *b) {
        return [a.timestamp compare:b.timestamp];
    }];
    NSMutableArray *sources = [NSMutableArray array];
    NSMutableSet *sourceKeys = [NSMutableSet set];
    NSMutableSet *seenMetadata = [NSMutableSet set];
    for (BAAnalyticsObservation *observation in selected) {
        if ((++examined % 256) == 0 && cancelled && cancelled()) return nil;
        for (NSString *metric in observation.fieldMetadata) {
            BAAnalyticsFieldMetadata *metadata = observation.fieldMetadata[metric];
            if ([seenMetadata containsObject:metadata]) continue;
            [seenMetadata addObject:metadata];
            NSString *key = [NSString stringWithFormat:@"%@.%@", metadata.sourceTable, metadata.sourceColumn];
            if ([sourceKeys containsObject:key]) continue;
            [sourceKeys addObject:key];
            [sources addObject:@{ @"metric": metric, @"key": key, @"metadata": metadata }];
        }
    }
    return @{ @"observations": [selected copy], @"transitions": [transitions copy], @"sources": [sources copy] };
}

@interface BADetailEvidenceCancellation : NSObject
@property (atomic) BOOL cancelled;
@end
@implementation BADetailEvidenceCancellation
@end

@interface BAAnalyticsDetailViewController ()
@property (nonatomic, copy) NSString *familyIdentifier;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsReport *report;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsMetricSnapshot *snapshot;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsDetailSelection *selection;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsFamilyReport *familyReport;
@property (nonatomic, copy, readwrite) NSArray<BAAnalyticsObservation *> *selectedObservations;
@property (nonatomic, copy) NSArray<BAAnalyticsStateTransition *> *selectedTransitions;
@property (nonatomic, copy) NSArray<NSDictionary *> *selectedSources;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *formattedObservationRows;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic) NSUInteger observationDisplayLimit;
@property (nonatomic) BOOL showsSourceDetails;
@property (nonatomic) BOOL showsObservations;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) UIView *visualization;
@property (nonatomic) BOOL selectingEvidence;
@property (nonatomic, strong) BADetailEvidenceCancellation *evidenceCancellation;
@end

@implementation BAAnalyticsDetailViewController
- (instancetype)initWithDisplayName:(NSString *)displayName familyIdentifier:(NSString *)familyIdentifier
                             report:(BAAnalyticsReport *)report snapshot:(BAAnalyticsMetricSnapshot *)snapshot
                          selection:(BAAnalyticsDetailSelection *)selection {
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) style = UITableViewStyleInsetGrouped;
    self = [super initWithStyle:style];
    if (!self) return nil;
    self.title = displayName; _familyIdentifier = [familyIdentifier copy];
    _report = report; _snapshot = snapshot; _selection = selection;
    _familyReport = [report reportForFamily:familyIdentifier];
    _observationDisplayLimit = 25;
    _showsObservations = selection.recordIdentifiers.count == 1 && [selection.kind isEqual:@"record"];
    _dateFormatter = [NSDateFormatter new];
    _dateFormatter.locale = [NSLocale currentLocale];
    [_dateFormatter setLocalizedDateFormatFromTemplate:@"yyyyMMddHHmmss"];
    [self selectEvidence];
    return self;
}

- (void)dealloc { _evidenceCancellation.cancelled = YES; }

- (void)applySelectedEvidence:(NSDictionary *)evidence {
    self.selectedObservations = evidence[@"observations"] ?: @[];
    self.selectedTransitions = evidence[@"transitions"] ?: @[];
    self.selectedSources = evidence[@"sources"] ?: @[];
    self.formattedObservationRows = [NSMutableArray array];
    self.selectingEvidence = NO;
    if (self.isViewLoaded) { [self buildSections]; [self.tableView reloadData]; }
}

- (void)selectEvidence {
    BAAnalyticsFamilyReport *family = self.familyReport;
    BAAnalyticsDetailSelection *selection = self.selection;
    NSUInteger candidates = family.window.observations.count;
    BAAnalyticsHistorySession *session = family.payload[BAAnalyticsPayloadSelectedSession];
    candidates += session.observations.count;
    if (candidates <= 256) {
        [self applySelectedEvidence:BADetailSelectedEvidence(family, selection, nil)];
        return;
    }
    self.selectedObservations = @[]; self.selectedTransitions = @[]; self.selectingEvidence = YES;
    BADetailEvidenceCancellation *token = [BADetailEvidenceCancellation new]; self.evidenceCancellation = token;
    __weak typeof(self) weakSelf = self;
    dispatch_async(BAAnalyticsCanvasPreparationQueue(), ^{
        @autoreleasepool {
            NSDictionary *evidence = BADetailSelectedEvidence(family, selection, ^BOOL { return token.cancelled; });
            if (!evidence || token.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                BAAnalyticsDetailViewController *controller = weakSelf;
                if (controller && controller.evidenceCancellation == token && !token.cancelled)
                    [controller applySelectedEvidence:evidence];
            });
        }
    });
}

- (UIView *)makeVisualizationView { return nil; }
- (BOOL)allowsVisualizationInteraction { return NO; }
- (CGFloat)visualizationHeight {
    CGFloat height = [self.visualization sizeThatFits:CGSizeMake(self.tableView.bounds.size.width - 32, CGFLOAT_MAX)].height;
    return height >= 200 && height <= 900 ? height : 330;
}
- (NSArray<NSDictionary *> *)summaryRows { return @[]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildSections];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68;
    self.visualization = [self makeVisualizationView];
    if (self.visualization) {
        self.visualization.userInteractionEnabled = [self allowsVisualizationInteraction];
        self.visualization.backgroundColor = UIColor.compatBackgroundColor;
        self.visualization.layer.cornerRadius = 18;
        self.visualization.clipsToBounds = YES;
        UIView *header = [UIView new]; [header addSubview:self.visualization];
        self.tableView.tableHeaderView = header;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.visualization) return;
    CGFloat height = [self visualizationHeight];
    UIView *header = self.tableView.tableHeaderView;
    CGSize size = CGSizeMake(self.tableView.bounds.size.width, height + 24);
    if (!CGSizeEqualToSize(header.frame.size, size)) {
        header.frame = (CGRect){CGPointZero, size}; self.tableView.tableHeaderView = header;
    }
    CGRect frame = CGRectMake(16, 12, MAX(0, size.width - 32), height);
    if (!CGRectEqualToRect(self.visualization.frame, frame)) {
        self.visualization.frame = frame;
        [self.visualization setNeedsLayout]; [self.visualization setNeedsDisplay];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController.presentingViewController && self.navigationController.viewControllers.firstObject == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeDetail:)];
}
- (void)closeDetail:(id)sender { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSString *)dateText:(NSDate *)date { return date ? [self.dateFormatter stringFromDate:date] : _("Unavailable"); }
- (NSDictionary *)row:(NSString *)title value:(NSString *)value {
    return @{@"title":title ?: @"", @"value":value ?: _("Unavailable")};
}
- (void)buildSections {
    if (self.selectingEvidence) {
        self.sections = @[@{ @"title": @"", @"rows": @[[self row:_("Loading history…") value:@""]] }];
        return;
    }
    NSMutableArray *sections = [NSMutableArray array];
    NSArray *summary = [self summaryRows];
    if (summary.count) [sections addObject:@{@"title":_("Summary"), @"rows":summary}];
    NSDate *start = self.selection.startDate ?: self.familyReport.window.startDate;
    NSDate *end = self.selection.endDate ?: self.familyReport.window.endDate;
    NSMutableArray *timeRows = [NSMutableArray array];
    if (start) [timeRows addObject:[self row:_("Observed window") value:[NSString stringWithFormat:@"%@ – %@", [self dateText:start], [self dateText:end]]]];
    [timeRows addObject:[self row:_("Source records") value:[NSString stringWithFormat:@"%lu", (unsigned long)self.selectedObservations.count]]];
    if (timeRows.count) [sections addObject:@{@"title":_("Sampling"), @"rows":timeRows, @"footer":_("Gaps are not interpolated. Values are frozen when this view opens.")}];
    if (self.selectedObservations.count) {
        [sections addObject:@{@"title":@"", @"rows":@[@{@"title":self.showsObservations ? _("Hide exact readings") : _("Show exact readings"), @"value":[NSString stringWithFormat:_("%lu source records"), (unsigned long)self.selectedObservations.count], @"observations":@YES}]}];
        if (self.showsObservations) {
            NSNumberFormatter *format = [NSNumberFormatter new]; format.maximumFractionDigits = 3;
            NSUInteger limit = MIN(self.observationDisplayLimit, self.selectedObservations.count);
            for (NSUInteger i = self.formattedObservationRows.count; i < limit; i++) {
                BAAnalyticsObservation *observation = self.selectedObservations[i];
                NSMutableArray *readings = [NSMutableArray array];
                NSArray *metrics = self.selection.metricIdentifiers.count ? self.selection.metricIdentifiers : observation.values.allKeys;
                for (NSString *metric in metrics) {
                    NSNumber *number = observation.values[metric]; BAAnalyticsFieldMetadata *metadata = observation.fieldMetadata[metric];
                    if (!number || !isfinite(number.doubleValue) || !metadata.unitValidated || !observation.timestampValidated) continue;
                    [readings addObject:[NSString stringWithFormat:@"%@: %@ %@", BADetailMetricTitle(metric), [format stringFromNumber:number], metadata.unit]];
                }
                [self.formattedObservationRows addObject:[self row:[self dateText:observation.timestamp] value:readings.count ? [readings componentsJoinedByString:@"\n"] : _("Required fields unavailable")]];
            }
            NSMutableArray *rows = [[self.formattedObservationRows subarrayWithRange:NSMakeRange(0, limit)] mutableCopy];
            if (self.observationDisplayLimit < self.selectedObservations.count) [rows addObject:@{@"title":_("More readings"), @"value":@"", @"more":@YES}];
            [sections addObject:@{@"title":_("Exact readings"), @"rows":rows}];
        }
    }
    [sections addObject:@{@"title":@"", @"rows":@[@{@"title":self.showsSourceDetails ? _("Hide sources and definitions") : _("Sources and definitions"), @"value":_("Field units, sampling and statistical scope"), @"sources":@YES}]}];
    if (self.showsSourceDetails) {
        NSMutableArray *rows = [NSMutableArray array];
        if ([self.selection.context[@"source"] isEqual:@"metricSnapshot"]) [rows addObject:[self row:_("Live snapshot") value:[self dateText:self.snapshot.timestamp]]];
        if (self.report) [rows addObject:[self row:_("Data updated") value:[self dateText:self.report.generatedAt]]];
        if (self.selection.recordIdentifiers.count) [rows addObject:[self row:_("Selected record IDs") value:[self.selection.recordIdentifiers componentsJoinedByString:@", "]]];
        for (NSDictionary *source in self.selectedSources) {
            BAAnalyticsFieldMetadata *metadata = source[@"metadata"];
            [rows addObject:[self row:BADetailMetricTitle(source[@"metric"]) value:[NSString stringWithFormat:@"%@ · %@ · %@", source[@"key"], metadata.unit, metadata.decoderIdentifier]]];
        }
        if (rows.count == 0) [rows addObject:[self row:_("History") value:_("Unavailable")]];
        [sections addObject:@{@"title":_("Sources"), @"rows":rows}];
    }
    self.sections = sections;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return (NSInteger)self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return (NSInteger)[self.sections[(NSUInteger)section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return self.sections[(NSUInteger)section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { (void)tableView; return self.sections[(NSUInteger)section][@"footer"]; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Evidence"];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Evidence"];
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    cell.textLabel.text = row[@"title"];
    cell.detailTextLabel.text = row[@"value"];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = ([row[@"more"] boolValue] || [row[@"sources"] boolValue] || [row[@"observations"] boolValue]) ? [UIColor compatBlueColor] : [UIColor compatLabelColor];
    cell.detailTextLabel.textColor = [UIColor compatSecondaryLabelColor];
    cell.selectionStyle = ([row[@"more"] boolValue] || [row[@"sources"] boolValue] || [row[@"observations"] boolValue]) ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessoryType = ([row[@"more"] boolValue] || [row[@"sources"] boolValue] || [row[@"observations"] boolValue]) ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[(NSUInteger)indexPath.section][@"rows"][(NSUInteger)indexPath.row];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([row[@"sources"] boolValue]) {
        self.showsSourceDetails = !self.showsSourceDetails;
        [self buildSections]; [tableView reloadData]; return;
    }
    if ([row[@"observations"] boolValue]) {
        self.showsObservations = !self.showsObservations;
        [self buildSections]; [tableView reloadData]; return;
    }
    if (![row[@"more"] boolValue]) return;
    self.observationDisplayLimit = MIN(self.selectedObservations.count, self.observationDisplayLimit + 25);
    [self buildSections];
    [tableView reloadData];
}
@end
