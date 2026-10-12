#import "BAAnalyticsDetailSelection.h"
#include <math.h>

static NSArray<NSString *> *BAAnalyticsSelectionIdentifiers(NSArray<NSString *> *identifiers) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id value in identifiers) {
        if ([value isKindOfClass:[NSString class]] && [value length] > 0 && [value length] <= 255)
            [result addObject:[value copy]];
        if (result.count == 256)
            break;
    }
    return [result copy];
}

static BOOL BAAnalyticsSelectionContextIsBounded(id value, NSUInteger depth, NSUInteger *count) {
    if (!value || depth > 6 || ++*count > 256)
        return NO;
    if ([value isKindOfClass:[NSString class]])
        return [value length] <= 1024;
    if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]])
        return YES;
    if ([value isKindOfClass:[NSArray class]]) {
        for (id item in value)
            if (!BAAnalyticsSelectionContextIsBounded(item, depth + 1, count))
                return NO;
        return YES;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (id key in value) {
            if (![key isKindOfClass:[NSString class]] || [key length] > 128 ||
                !BAAnalyticsSelectionContextIsBounded(value[key], depth + 1, count))
                return NO;
        }
        return YES;
    }
    return NO;
}

@interface BAAnalyticsDetailSelection ()
- (instancetype)initPrivate;
@end

@implementation BAAnalyticsDetailSelection
- (instancetype)initPrivate { return [super init]; }

+ (instancetype)selectionForFamily:(NSString *)familyIdentifier kind:(NSString *)kind
                 recordIdentifiers:(NSArray<NSString *> *)recordIdentifiers
                 metricIdentifiers:(NSArray<NSString *> *)metricIdentifiers
                         startDate:(NSDate *)startDate endDate:(NSDate *)endDate
                           context:(NSDictionary<NSString *, id> *)context {
    BAAnalyticsDetailSelection *selection = [[self alloc] initPrivate];
    selection->_familyIdentifier = [familyIdentifier copy] ?: @"";
    selection->_kind = [kind copy] ?: @"";
    selection->_recordIdentifiers = BAAnalyticsSelectionIdentifiers(recordIdentifiers);
    selection->_metricIdentifiers = BAAnalyticsSelectionIdentifiers(metricIdentifiers);
    selection->_startDate = [startDate copy];
    selection->_endDate = [endDate copy];
    NSUInteger count = 0;
    NSData *encoded = nil;
    if (BAAnalyticsSelectionContextIsBounded(context, 0, &count))
        encoded = [NSPropertyListSerialization dataWithPropertyList:context format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    selection->_context = encoded.length > 0 && encoded.length <= 8192 ?
        [NSPropertyListSerialization propertyListWithData:encoded options:NSPropertyListImmutable format:NULL error:NULL] : @{};
    return selection;
}

+ (instancetype)selectionForFamily:(NSString *)familyIdentifier kind:(NSString *)kind context:(NSDictionary<NSString *, id> *)context {
    return [self selectionForFamily:familyIdentifier kind:kind recordIdentifiers:nil metricIdentifiers:nil startDate:nil endDate:nil context:context];
}

- (id)copyWithZone:(NSZone *)zone { (void)zone; return self; }
@end

@interface BAAnalyticsCanvasHitRegion ()
- (instancetype)initPrivate;
@end

@implementation BAAnalyticsCanvasHitRegion
- (instancetype)initPrivate { return [super init]; }

+ (instancetype)regionWithRect:(CGRect)rect selection:(BAAnalyticsDetailSelection *)selection accessibilityLabel:(NSString *)accessibilityLabel {
    BAAnalyticsCanvasHitRegion *region = [[self alloc] initPrivate];
    region->_rect = isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height) ? CGRectStandardize(rect) : CGRectZero;
    region->_selection = selection;
    region->_accessibilityLabel = [accessibilityLabel copy] ?: @"";
    return region;
}

- (id)copyWithZone:(NSZone *)zone { (void)zone; return self; }
@end
