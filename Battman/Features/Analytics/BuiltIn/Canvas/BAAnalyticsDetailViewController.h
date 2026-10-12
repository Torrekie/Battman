#import <UIKit/UIKit.h>
#import "BAAnalyticsDetailSelection.h"

@class BAAnalyticsReport;
@class BAAnalyticsMetricSnapshot;
@class BAAnalyticsFamilyReport;
@class BAAnalyticsObservation;

NS_ASSUME_NONNULL_BEGIN

// A fixed evidence view: acquisition updates never silently replace the
// report/snapshot that produced the selected graphical mark.
@interface BAAnalyticsDetailViewController : UITableViewController
@property (nonatomic, strong, readonly, nullable) BAAnalyticsReport *report;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsMetricSnapshot *snapshot;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsDetailSelection *selection;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsFamilyReport *familyReport;
@property (nonatomic, copy, readonly) NSArray<BAAnalyticsObservation *> *selectedObservations;
// Card-specific subclasses live with their card and supply its visualization.
- (nullable UIView *)makeVisualizationView;
- (BOOL)allowsVisualizationInteraction;
- (CGFloat)visualizationHeight;
- (NSArray<NSDictionary *> *)summaryRows;
- (instancetype)initWithDisplayName:(NSString *)displayName
                   familyIdentifier:(NSString *)familyIdentifier
                             report:(nullable BAAnalyticsReport *)report
                           snapshot:(nullable BAAnalyticsMetricSnapshot *)snapshot
                          selection:(nullable BAAnalyticsDetailSelection *)selection NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
