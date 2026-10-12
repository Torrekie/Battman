// Internal built-in canvas contract. Third-party Analytics SDK v1 is unchanged.
#import <UIKit/UIKit.h>
#import "../../Public/BAAnalyticsCard.h"
#import "BAAnalyticsDetailSelection.h"

@class BAAnalyticsReport;
@class BAAnalyticsHistoryService;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BAAnalyticsGlyph) {
    BAAnalyticsGlyphBolt, BAAnalyticsGlyphThermometer, BAAnalyticsGlyphClock,
    BAAnalyticsGlyphConnected, BAAnalyticsGlyphPause, BAAnalyticsGlyphCheck, BAAnalyticsGlyphUnplugged,
};
// Runtime vector drawing follows Battman's existing CGIconSet approach.
FOUNDATION_EXPORT void BAAnalyticsDrawGlyph(BAAnalyticsGlyph glyph, CGRect rect, UIColor *color);
// Foundation-only preparation shares one queue to bound CPU and temporary memory.
FOUNDATION_EXPORT dispatch_queue_t BAAnalyticsCanvasPreparationQueue(void);


// A canvas owns its drawing and layout. There is no required title/header.
// Submit hitRegions after laying out visual marks. Shared interaction expands
// targets to at least 44 points, resolves overlap by proximity, and provides
// equivalent VoiceOver actions. No action is dispatched while editing.
@interface BAAnalyticsCanvasView : UIControl
@property (nonatomic) BAAnalyticsCardSize cardSize;
@property (nonatomic, getter=isEditing) BOOL editing;
@property (nonatomic) BOOL detailEnabled;
@property (nonatomic, copy) NSString *familyIdentifier;
@property (nonatomic, strong, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@property (nonatomic, strong, nullable) BAAnalyticsReport *latestReport;
@property (nonatomic, copy) NSArray<BAAnalyticsCanvasHitRegion *> *hitRegions;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsDetailSelection *selectedDetail;
// Internal readiness for pending Foundation-only presentation work.
@property (nonatomic, readonly, getter=isPreparingHistory) BOOL preparingHistory;

// Sets the selection and emits UIControlEventTouchUpInside. A nil selection
// requests the whole-card detail. The host owns navigation/presentation.
- (void)requestDetailForSelection:(nullable BAAnalyticsDetailSelection *)selection;
@end

// Built-in-only base class: subscribes to shared history and receives the
// existing immutable live metric snapshots. It never polls from draw/layout.
// All rendering callbacks and updates run on the main thread.
@interface BAAnalyticsCanvasCard : NSObject <BAAnalyticsCard>
@property (nonatomic, copy, readonly) NSString *analyticsCardIdentifier;
@property (nonatomic, copy, readonly) NSString *analyticsCardDisplayName;
@property (nonatomic, copy, readonly) NSString *familyIdentifier;
@property (nonatomic, readonly) BAAnalyticsCardSizeMask supportedAnalyticsCardSizes;
@property (nonatomic, readonly) BAAnalyticsCardSize defaultAnalyticsCardSize;
// Opt-in: compact self-contained cards have no navigation action.
@property (nonatomic, readonly) BOOL supportsDetails;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsMetricSnapshot *latestSnapshot;
@property (nonatomic, strong, readonly, nullable) BAAnalyticsReport *latestReport;
// Defaults to the real shared service. The host can supply an isolated service.
@property (nonatomic, strong) BAAnalyticsHistoryService *historyService;

- (instancetype)initWithIdentifier:(NSString *)identifier
                      displayName:(NSString *)displayName
                 familyIdentifier:(NSString *)familyIdentifier
                   supportedSizes:(BAAnalyticsCardSizeMask)supportedSizes
                      defaultSize:(BAAnalyticsCardSize)defaultSize NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Override these two methods. The base class first assigns size, editing,
// family, snapshot, and report on the view, then invokes updateCanvasView:.
// An absent report/snapshot means unavailable or loading, never demo values.
- (BAAnalyticsCanvasView *)makeCanvasView;
- (void)updateCanvasView:(BAAnalyticsCanvasView *)view;

// Default implementation returns nil. A participating card opts in and owns
// its visual detail controller alongside the card implementation.
- (nullable UIViewController *)detailViewControllerForSelection:(nullable BAAnalyticsDetailSelection *)selection
                                                        size:(BAAnalyticsCardSize)size;
@end

// Each worker implements exactly one factory in its own group directory.
FOUNDATION_EXPORT NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateLiveCanvasCards(void);
FOUNDATION_EXPORT NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateProcessCanvasCards(void);
FOUNDATION_EXPORT NSArray<id<BAAnalyticsCard>> *BAAnalyticsCreateStatisticalCanvasCards(void);

NS_ASSUME_NONNULL_END
