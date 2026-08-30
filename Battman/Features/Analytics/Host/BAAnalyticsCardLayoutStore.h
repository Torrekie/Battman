//
//  BAAnalyticsCardLayoutStore.h
//  Battman
//
//  Bounded, UIKit-free Analytics layout persistence and migration.
//


#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const BAAnalyticsCardLayoutDefaultsKey;
FOUNDATION_EXPORT NSString *const BAAnalyticsLegacyCardLayoutDefaultsKey;
FOUNDATION_EXPORT NSUInteger const BAAnalyticsCardLayoutFormatVersion;

@interface BAAnalyticsCardLayoutRecord : NSObject
@property (nonatomic, copy, readonly) NSString *cardIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, readonly) NSInteger sizeValue;
@property (nonatomic, readonly) NSUInteger restorationSchemaVersion;
@property (nonatomic, copy, readonly, nullable) NSDictionary *restorationState;

- (instancetype)initWithCardIdentifier:(NSString *)cardIdentifier
						 displayName:(NSString *)displayName
						   sizeValue:(NSInteger)sizeValue
		 restorationSchemaVersion:(NSUInteger)restorationSchemaVersion
					 restorationState:(nullable NSDictionary *)restorationState NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BAAnalyticsCardLayoutStore : NSObject
+ (NSArray<BAAnalyticsCardLayoutRecord *> *)loadRecordsFromUserDefaults:(NSUserDefaults *)userDefaults;
+ (void)saveRecords:(NSArray<BAAnalyticsCardLayoutRecord *> *)records
		 toUserDefaults:(NSUserDefaults *)userDefaults;
+ (NSString *)canonicalCardIdentifierForStoredIdentifier:(NSString *)storedIdentifier;
@end

NS_ASSUME_NONNULL_END
