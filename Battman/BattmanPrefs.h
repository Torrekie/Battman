//
//  BattmanPrefs.h
//  Battman
//
//  Created by Torrekie on 2025/10/19.
//

#import <CoreFoundation/CoreFoundation.h>
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#endif

#pragma clang assume_nonnull begin

#ifdef __OBJC__

#define BATTMAN_PREFS_QUEUE "com.torrekie.Battman.prefs"

@interface BattmanPrefs : NSObject
+ (instancetype)sharedPrefs;

// TableView convenience methods
- (nullable id)valueForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath;
- (void)setValue:(nullable id)value forTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath;

// NSUserDefaults-like interface
- (id)objectForKey:(NSString *)defaultName;
- (void)setObject:(nullable id)value forKey:(NSString *)defaultName;
- (void)removeObjectForKey:(NSString *)defaultName;

// Typed getters
- (BOOL)boolForKey:(NSString *)defaultName;
- (NSInteger)integerForKey:(NSString *)defaultName;
- (double)doubleForKey:(NSString *)defaultName;
- (float)floatForKey:(NSString *)defaultName;
- (NSArray *)arrayForKey:(NSString *)defaultName;
- (NSDictionary *)dictionaryForKey:(NSString *)defaultName;
- (NSString *)stringForKey:(NSString *)defaultName;

// Typed setters
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName;
- (void)setDouble:(double)value forKey:(NSString *)defaultName;
- (void)setFloat:(float)value forKey:(NSString *)defaultName;
- (void)setString:(NSString *)value forKey:(NSString *)defaultName;

// NSUserDefaults compatibility
- (void)registerDefaults:(NSDictionary<NSString *,id> *)registrationDictionary;
- (NSDictionary<NSString *,id> *)dictionaryRepresentation;
- (BOOL)synchronize;

// Environment variable helpers
- (nullable NSString *)envStringForKey:(NSString *)key;
- (BOOL)hasEnvOverrideForKey:(NSString *)key;

// Wipe all data
- (void)wipeAllData;
- (void)wipeAllData:(BOOL)dryRun;
@end

#endif

__BEGIN_DECLS

// C helpers
id __nullable BattmanPrefsGetObject(const char *defaultName);
void BattmanPrefsSetObject(const char *defaultName, id value);
void BattmanPrefsRemove(const char *defaultName);

BOOL BattmanPrefsGetBool(const char *defaultName);
long BattmanPrefsGetInt(const char *defaultName);
double BattmanPrefsGetDouble(const char *defaultName);
float BattmanPrefsGetFloat(const char *defaultName);
CFArrayRef _Nullable BattmanPrefsGetArray(const char *defaultName);
CFDictionaryRef _Nullable BattmanPrefsGetDictionary(const char *defaultName);
CFStringRef _Nullable BattmanPrefsGetString(const char *defaultName);
const char *_Nullable BattmanPrefsGetCString(const char *defaultName);

void BattmanPrefsSetBoolValue(const char *defaultName, BOOL value);
void BattmanPrefsSetIntValue(const char *defaultName, long value);
void BattmanPrefsSetDoubleValue(const char *defaultName, double value);
void BattmanPrefsSetFloatValue(const char *defaultName, float value);
void BattmanPrefsSetString(const char *defaultName, CFStringRef value);
// Caller free!
void BattmanPrefsSetCString(const char *defaultName, const char *value);

CFDictionaryRef BattmanPrefsDictionaryRepresentation(void);

BOOL BattmanPrefsSynchronize(void);

__END_DECLS

#pragma clang assume_nonnull end

#pragma mark - PreferencesViewController

typedef enum {
	P_SECT_LANGUAGE,
	P_SECT_BI_INTERVAL,
	P_SECT_APPEARANCE,
	P_SECT_WIPEALL,
	P_SECT_COUNT,
} PrefsSect;

// P_SECT_BI_INTERVAL
typedef enum {
	P_ROW_BI_INTERVAL,
	P_ROW_BI_INTERVAL_COUNT,
} PrefsRowBI;
#define kBattmanPrefs_BI_INTERVAL "BI_REFRESH_INTERVAL"

// P_SECT_LANGUAGE
typedef enum {
	P_ROW_LANGUAGE,
	P_ROW_LANGUAGE_COUNT,
} PrefsRowLang;
#define kBattmanPrefs_LANGUAGE "PREFERRED_LANG"

// P_SECT_APPEARANCE
typedef enum {
	P_ROW_APPEARANCE_THERM_RANGE_MIN,
	P_ROW_APPEARANCE_THERM_RANGE_MAX,
	P_ROW_APPEARANCE_BRIGHTNESS_HDR,
	P_ROW_APPEARANCE_COUNT,
} PrefsRowAppearance;
#define kBattmanPrefs_THERM_UI_MIN "THERMOMETER_UI_MINVAL"
#define kBattmanPrefs_THERM_UI_MAX "THERMOMETER_UI_MAXVAL"
#define kBattmanPrefs_BRIGHT_UI_HDR "ENABLE_BRIGHTNESS_UI_HDR"

// P_SECT_WIPEALL
typedef enum {
	P_ROW_WIPEALL,
	P_ROW_WIPEALL_COUNT,
} PrefsRowWipeAll;
