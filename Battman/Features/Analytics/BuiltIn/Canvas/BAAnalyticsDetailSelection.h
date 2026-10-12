// Internal selection context for graphical Analytics details.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Immutable selection. IDs identify observed rows/sessions/bins, never screen
// indices. All ranges use the report's normalized wall-clock timestamps.
@interface BAAnalyticsDetailSelection : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *familyIdentifier;
@property (nonatomic, copy, readonly) NSString *kind;
@property (nonatomic, copy, readonly) NSArray<NSString *> *recordIdentifiers;
@property (nonatomic, copy, readonly) NSArray<NSString *> *metricIdentifiers;
@property (nonatomic, copy, readonly, nullable) NSDate *startDate;
@property (nonatomic, copy, readonly, nullable) NSDate *endDate;
// Small metadata only: property-list-compatible values, no raw database dumps.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

+ (instancetype)selectionForFamily:(NSString *)familyIdentifier
                              kind:(NSString *)kind
                 recordIdentifiers:(nullable NSArray<NSString *> *)recordIdentifiers
                 metricIdentifiers:(nullable NSArray<NSString *> *)metricIdentifiers
                         startDate:(nullable NSDate *)startDate
                           endDate:(nullable NSDate *)endDate
                           context:(nullable NSDictionary<NSString *, id> *)context;
+ (instancetype)selectionForFamily:(NSString *)familyIdentifier
                              kind:(NSString *)kind
                           context:(nullable NSDictionary<NSString *, id> *)context;
- (instancetype)init NS_UNAVAILABLE;
@end

// Rectangles describe marks in canvas-local coordinates. Shared interaction
// expands the hit target without changing the visible geometry.
@interface BAAnalyticsCanvasHitRegion : NSObject <NSCopying>
@property (nonatomic, readonly) CGRect rect;
@property (nonatomic, strong, readonly) BAAnalyticsDetailSelection *selection;
@property (nonatomic, copy, readonly) NSString *accessibilityLabel;

+ (instancetype)regionWithRect:(CGRect)rect
                    selection:(BAAnalyticsDetailSelection *)selection
           accessibilityLabel:(NSString *)accessibilityLabel;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
