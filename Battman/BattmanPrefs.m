//
//  BattmanPrefs.m
//  Battman
//
//  Created by Torrekie on 2025/10/19.
//
#import "ObjCExt/NSBundle+Auto.h"

#import "PreferencesViewController.h"
#import "ThermAniTestViewController.h"
#import "BattmanPrefs.h"
#include "common.h"
#import <UIKit/UIKit.h>

@interface MCMContainer : NSObject
+ (instancetype)containerWithIdentifier:(NSString *)identifier createIfNecessary:(BOOL)createIfNecessary existed:(BOOL *)existed error:(NSError **)error;
- (NSURL *)url;
@end

@interface BattmanPrefs ()
@property (nonatomic, strong) NSMutableDictionary<NSString*, id> *backing;
@property (nonatomic) dispatch_queue_t queue;
@end

@implementation BattmanPrefs

static NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSString *> *> *PreferencesViewControllerKeys = nil;
static NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSString *> *> *ThermAniTestViewControllerKeys = nil;
static NSArray<NSString *> *BattmanGlobalKeys = nil;

- (instancetype)init {
	BattmanPrefs *shared = [[self class] sharedPrefs];
	if (self == shared)
		return self;
	return shared;
}

- (instancetype)_init {
	self = [super init];
	if (self) {
		_queue = dispatch_queue_create(BATTMAN_PREFS_QUEUE, DISPATCH_QUEUE_SERIAL);
		NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
		NSDictionary *std = userDefaults.dictionaryRepresentation;
		_backing = [NSMutableDictionary dictionaryWithDictionary:std ?: @{}];

		BattmanGlobalKeys = @[
			@kBattmanPrefs_Version,
		];
		ThermAniTestViewControllerKeys = @{
			@(TAT_SECT_THERM_RANGE): @{
					@(TAT_ROW_THERM_RANGE_MIN): @kBattmanPrefs_THERM_UI_MIN,
					@(TAT_ROW_THERM_RANGE_MAX): @kBattmanPrefs_THERM_UI_MAX,
			},
		};
		PreferencesViewControllerKeys = @{
			@(P_SECT_LANGUAGE) : @{
					@(P_ROW_LANGUAGE): @kBattmanPrefs_LANGUAGE,
			},
			@(P_SECT_BI_INTERVAL): @{
					@(P_ROW_BI_INTERVAL): @kBattmanPrefs_BI_INTERVAL,
			},
			@(P_SECT_APPEARANCE): @{
					// No preference key for Thermometer, see ThermAniTestViewControllerKeys
					// @(P_ROW_APPEARANCE_THERMOMETER): nil,
					@(P_ROW_APPEARANCE_BRIGHTNESS_HDR): @kBattmanPrefs_BRIGHT_UI_HDR,
			},
			@(P_SECT_WIPEALL): @{
					// No preference key for wipe all - it's an action
			},
		};
		
		// Enumerate all preference keys and set default values if not already present
		NSMutableArray<NSString *> *allPrefsKeys = [NSMutableArray array];
		NSArray *pending = @[PreferencesViewControllerKeys, ThermAniTestViewControllerKeys];
		for (NSDictionary *dict in pending) {
			[dict enumerateKeysAndObjectsUsingBlock:^(NSNumber *sectionKey, NSDictionary<NSNumber *, NSString *> *rowDict, BOOL *stop) {
				[rowDict enumerateKeysAndObjectsUsingBlock:^(NSNumber *rowKey, NSString *prefsKey, BOOL *innerStop) {
					[allPrefsKeys addObject:prefsKey];
				}];
			}];
		}
		// Globals
		for (NSString *key in BattmanGlobalKeys) {
			[allPrefsKeys addObject:key];
		}

		// Set default values for preferences that don't exist
		NSDictionary<NSString *, id> *defaultValues = @{
			@kBattmanPrefs_Version: @(BattmanPrefsVersion),
			@kBattmanPrefs_BI_INTERVAL: @(0.0), /* 0:Auto, -1:Never */
			@kBattmanPrefs_THERM_UI_MIN: @(0.0),
			@kBattmanPrefs_THERM_UI_MAX: @(45.0),
			@kBattmanPrefs_BRIGHT_UI_HDR: @(1),
		};

		BOOL need_sync = NO;
		for (NSString *key in allPrefsKeys) {
			if ([userDefaults objectForKey:key] == nil && defaultValues[key] != nil) {
				if ([key isEqualToString:@kBattmanPrefs_Version]) {
					/* Version 1 Changes:
					 * - HDR is now disabled by default
					 */
					[userDefaults removeObjectForKey:@kBattmanPrefs_BRIGHT_UI_HDR];
					[userDefaults synchronize];
				}
				NSLog(@"BattmanPrefs: Setting default value %@ for key %@", defaultValues[key], key);
				[userDefaults setObject:defaultValues[key] forKey:key];
				_backing[key] = defaultValues[key];
				need_sync = YES;
			}
		}
#ifdef DEBUG
		DBGLOG(@"BattmanPrefs: All preference keys: %@", allPrefsKeys);
		for (NSString *key in allPrefsKeys) {
			DBGLOG(@"BattmanPrefs: Key %@ = %@", key, [userDefaults objectForKey:key]);
		}
#endif
		if (need_sync)
			[userDefaults synchronize];
	}
	return self;
}

+ (instancetype)sharedPrefs {
	static BattmanPrefs *cachedPrefs = nil;
	static dispatch_once_t onceToken = 0;
	dispatch_once(&onceToken, ^{
		cachedPrefs = [[super allocWithZone:NULL] _init];
	});
	return cachedPrefs;
}

#pragma mark UITableViewController conveniences

- (NSString *)_prefsKeyForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	if (!tableView || !indexPath) return nil;

	if ([tableView.nextResponder isKindOfClass:[PreferencesViewController class]]) {
		NSDictionary *rows = PreferencesViewControllerKeys[@(indexPath.section)];
		if (!rows) return nil;
		return rows[@(indexPath.row)]; // may be nil if not mapped
	}
	if ([tableView.nextResponder isKindOfClass:[ThermAniTestViewController class]]) {
		NSDictionary *rows = ThermAniTestViewControllerKeys[@(indexPath.section)];
		if (!rows) return nil;
		return rows[@(indexPath.row)];
	}
	return nil;
}

- (id)valueForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	if (!tableView || !indexPath) return nil;
	
	NSString *key = [self _prefsKeyForTableView:tableView indexPath:indexPath];
	if (!key) return nil;

	return [[[self class] sharedPrefs] objectForKey:key];
}

- (void)setValue:(id)value forTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	if (!tableView || !indexPath) return;

	NSString *key = [self _prefsKeyForTableView:tableView indexPath:indexPath];
	if (!key) return;

	return [[[self class] sharedPrefs] setObject:value forKey:key];
}

#pragma mark - Helpers

// Prevent creating a new instance via alloc/init
+ (id)allocWithZone:(struct _NSZone *)zone {
	return [self sharedPrefs];
}

- (id)copyWithZone:(NSZone *)zone {
	return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
	return self;
}

#pragma mark - Envvar helper

- (nullable NSString *)envStringForKey:(NSString *)key {
	if (!key || key.length == 0) return nil;
	const char *c = getenv(key.UTF8String);
	if (!c) return nil;
	return [NSString stringWithUTF8String:c];
}

- (BOOL)hasEnvOverrideForKey:(NSString *)key {
	return ([self envStringForKey:key] != nil);
}

#pragma mark - Basic getters/setters

id BattmanPrefsGetObject(const char *defaultName) {
	if (!defaultName) return nil;
	return [BattmanPrefs.sharedPrefs objectForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (id)objectForKey:(NSString *)defaultName {
	if (!defaultName) return nil;
	
	// Envvar override takes precedence and must not be persisted
	NSString *env = [self envStringForKey:defaultName];
	if (env != nil) {
		return env;
	}

	__block id value = nil;
	dispatch_sync(self.queue, ^{
		value = self.backing[defaultName];
	});
	return value;
}

- (BOOL)_validateValue:(id)value forKey:(NSString *)key {
	if (!key) return NO;
	
	// Validate specific preference keys
	if ([key isEqualToString:@kBattmanPrefs_BI_INTERVAL]) {
		if (![value isKindOfClass:[NSNumber class]]) return NO;
		double interval = [(NSNumber *)value doubleValue];
		return (interval >= -1.0); // -1 = Never, 0 = Auto, >0 = Custom interval
	}
	
	if ([key isEqualToString:@kBattmanPrefs_THERM_UI_MIN] || [key isEqualToString:@kBattmanPrefs_THERM_UI_MAX]) {
		if (![value isKindOfClass:[NSNumber class]]) return NO;
		double temp = [(NSNumber *)value doubleValue];
		return (temp >= -50.0 && temp <= 150.0); // Reasonable temperature range
	}
	
	if ([key isEqualToString:@kBattmanPrefs_BRIGHT_UI_HDR]) {
		return [value isKindOfClass:[NSNumber class]]; // Should be boolean NSNumber
	}
	
	return YES;
}

void BattmanPrefsSetObject(const char *defaultName, id value) {
	return [BattmanPrefs.sharedPrefs setObject:value forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setObject:(id)value forKey:(NSString *)defaultName {
	if (!defaultName) return;
	
	// Validate the value if it's not nil
	if (value && ![self _validateValue:value forKey:defaultName]) {
		NSLog(@"BattmanPrefs: Invalid value %@ for key %@", value, defaultName);
		return;
	}

	// Update backing store synchronously to avoid race conditions
	dispatch_sync(self.queue, ^{
		if (value) {
			self.backing[defaultName] = value;
		} else {
			[self.backing removeObjectForKey:defaultName];
		}
	});

	// Also sync immediately to NSUserDefaults.standardUserDefaults
	NSUserDefaults *std = NSUserDefaults.standardUserDefaults;
	if (value) {
		[std setObject:value forKey:defaultName];
	} else {
		[std removeObjectForKey:defaultName];
	}
}

void BattmanPrefsRemove(const char *defaultName) {
	return [BattmanPrefs.sharedPrefs removeObjectForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)removeObjectForKey:(NSString *)defaultName {
	[self setObject:nil forKey:defaultName];
}

#pragma mark - Typed getters

BOOL BattmanPrefsGetBool(const char *defaultName) {
	return [BattmanPrefs.sharedPrefs boolForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (BOOL)boolForKey:(NSString *)defaultName {
	if (!defaultName) return NO;

	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		NSString *lower = [env lowercaseString];
		if ([lower boolValue] || [lower isEqualToString:@"on"]) {
			return YES;
		}
		if ([lower isEqualToString:@"off"]) {
			return NO;
		}
		return [lower boolValue];
	}

	id obj = [self objectForKey:defaultName];
	if (!obj) return NO;
	if ([obj respondsToSelector:@selector(boolValue)]) return [obj boolValue];
	return NO;
}

long BattmanPrefsGetInt(const char *defaultName) {
	return [BattmanPrefs.sharedPrefs integerForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (NSInteger)integerForKey:(NSString *)defaultName {
	if (!defaultName) return 0;
	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		return [env integerValue];
	}
	id obj = [self objectForKey:defaultName];
	if (!obj) return 0;
	if ([obj respondsToSelector:@selector(integerValue)]) return [obj integerValue];
	return 0;
}

double BattmanPrefsGetDouble(const char *defaultName) {
	return [BattmanPrefs.sharedPrefs doubleForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (double)doubleForKey:(NSString *)defaultName {
	if (!defaultName) return 0.0;
	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		return [env doubleValue];
	}
	id obj = [self objectForKey:defaultName];
	if (!obj) return 0.0;
	if ([obj respondsToSelector:@selector(doubleValue)]) return [obj doubleValue];
	return 0.0;
}

float BattmanPrefsGetFloat(const char *defaultName) {
	return [BattmanPrefs.sharedPrefs floatForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (float)floatForKey:(NSString *)defaultName {
	if (!defaultName) return 0.0f;
	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		DBGLOG(@"BattmanPrefs: Using env override for %@: %@", defaultName, env);
		return (float)[env doubleValue];
	}
	id obj = [self objectForKey:defaultName];
	if (!obj) {
		DBGLOG(@"BattmanPrefs: No value found for key %@, returning 0.0f", defaultName);
		return 0.0f;
	}
	if ([obj respondsToSelector:@selector(floatValue)]) {
		float result = [obj floatValue];
		DBGLOG(@"BattmanPrefs: Retrieved value %f for key %@", result, defaultName);
		return result;
	}
	DBGLOG(@"BattmanPrefs: Object %@ for key %@ doesn't respond to floatValue", obj, defaultName);
	return 0.0f;
}

CFArrayRef BattmanPrefsGetArray(const char *defaultName) {
	return (__bridge CFArrayRef)[BattmanPrefs.sharedPrefs arrayForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (NSArray *)arrayForKey:(NSString *)defaultName {
	// If env var exists, we'll return an array only if env value looks like JSON array.
	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		NSData *d = [env dataUsingEncoding:NSUTF8StringEncoding];
		if (d) {
			id json = nil;
			NSError *err = nil;
			json = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
			if (!err && [json isKindOfClass:[NSArray class]]) return json;
		}
		// otherwise fall back to returning the raw string (objectForKey will handle that)
		return nil;
	}
	id obj = [self objectForKey:defaultName];
	return ([obj isKindOfClass:[NSArray class]] ? obj : nil);
}

CFDictionaryRef BattmanPrefsGetDictionary(const char *defaultName) {
	return (__bridge CFDictionaryRef)[BattmanPrefs.sharedPrefs dictionaryForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (NSDictionary *)dictionaryForKey:(NSString *)defaultName {
	NSString *env = [self envStringForKey:defaultName];
	if (env) {
		NSData *d = [env dataUsingEncoding:NSUTF8StringEncoding];
		if (d) {
			id json = nil;
			NSError *err = nil;
			json = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
			if (!err && [json isKindOfClass:[NSDictionary class]]) return json;
		}
		return nil;
	}
	id obj = [self objectForKey:defaultName];
	return ([obj isKindOfClass:[NSDictionary class]] ? obj : nil);
}

CFStringRef BattmanPrefsGetString(const char *defaultName) {
	return (__bridge CFStringRef)[BattmanPrefs.sharedPrefs stringForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
const char *BattmanPrefsGetCString(const char *defaultName) {
    if (!defaultName) return NULL;
    NSString *str = [BattmanPrefs.sharedPrefs stringForKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
    if (!str) return NULL;
    return strdup(str.UTF8String);
}
- (NSString *)stringForKey:(NSString *)defaultName {
	if (!defaultName) return nil;
	NSString *env = [self envStringForKey:defaultName];
	if (env) return env;
	id obj = [self objectForKey:defaultName];
	if ([obj isKindOfClass:[NSString class]]) return obj;
	if ([obj respondsToSelector:@selector(stringValue)]) return [obj stringValue];
	return nil;
}

#pragma mark - Typed setters

void BattmanPrefsSetBoolValue(const char *defaultName, BOOL value) {
	return [BattmanPrefs.sharedPrefs setObject:@(value) forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setBool:(BOOL)value forKey:(NSString *)defaultName {
	[self setObject:@(value) forKey:defaultName];
}

void BattmanPrefsSetIntValue(const char *defaultName, long value) {
	return [BattmanPrefs.sharedPrefs setObject:@(value) forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName {
	[self setObject:@(value) forKey:defaultName];
}

void BattmanPrefsSetDoubleValue(const char *defaultName, double value) {
	return [BattmanPrefs.sharedPrefs setObject:@(value) forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setDouble:(double)value forKey:(NSString *)defaultName {
	[self setObject:@(value) forKey:defaultName];
}

void BattmanPrefsSetFloatValue(const char *defaultName, float value) {
	return [BattmanPrefs.sharedPrefs setObject:@(value) forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setFloat:(float)value forKey:(NSString *)defaultName {
	[self setObject:@(value) forKey:defaultName];
}

void BattmanPrefsSetString(const char *defaultName, CFStringRef value) {
	[BattmanPrefs.sharedPrefs setObject:(__bridge NSString *)value forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
void BattmanPrefsSetCString(const char *defaultName, const char *value) {
	[BattmanPrefs.sharedPrefs setObject:[NSString stringWithCString:value encoding:NSUTF8StringEncoding] forKey:[NSString stringWithCString:defaultName encoding:NSUTF8StringEncoding]];
}
- (void)setString:(NSString *)value forKey:(NSString *)defaultName {
	[self setObject:value forKey:defaultName];
}

#pragma mark - registerDefaults / dictionaryRepresentation

- (void)registerDefaults:(NSDictionary<NSString *,id> *)registrationDictionary {
	if (!registrationDictionary) return;
	dispatch_async(self.queue, ^{
		[registrationDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
			if (self.backing[key] == nil) {
				// Validate default values before setting them
				if ([self _validateValue:obj forKey:key]) {
					self.backing[key] = obj;
				} else {
					NSLog(@"BattmanPrefs: Invalid default value %@ for key %@", obj, key);
				}
			}
		}];
	});
}

CFDictionaryRef BattmanPrefsDictionaryRepresentation(void) {
	return (__bridge CFDictionaryRef)[BattmanPrefs.sharedPrefs dictionaryRepresentation];
}
- (NSDictionary<NSString *,id> *)dictionaryRepresentation {
	__block NSDictionary *copy = nil;
	dispatch_sync(self.queue, ^{
		copy = [self.backing copy];
	});
	return copy;
}

#pragma mark - synchronize

// Synchronize backing to NSUserDefaults.standardUserDefaults, but DO NOT write keys that have an environment variable override.
BOOL BattmanPrefsSynchronize(void) {
	return [BattmanPrefs.sharedPrefs synchronize];
}
- (BOOL)synchronize {
	__block NSDictionary *snapshot = nil;
	dispatch_sync(self.queue, ^{
		snapshot = [self.backing copy];
	});

	NSUserDefaults *std = [NSUserDefaults standardUserDefaults];

	[snapshot enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
		if ([self hasEnvOverrideForKey:key]) {
			return;
		}
		if (obj) {
			[std setObject:obj forKey:key];
		} else {
			[std removeObjectForKey:key];
		}
	}];

	return [std synchronize];
}

#pragma mark - Wipe All Data

- (void)wipeAllData {
	[self wipeAllData:NO];
}

- (void)wipeAllData:(BOOL)dryRun {
	DBGLOG(@"BattmanPrefs: %@ wipe all data operation", dryRun ? @"DRY RUN -" : @"Starting");
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Helper to delete all children inside a directory (not the directory itself)
	void (^wipeDirectoryContents)(NSURL *dirURL, NSString *label) = ^(NSURL *dirURL, NSString *label) {
		if (!dirURL.path.length) {
			return;
		}
		
		NSError *error = nil;
		NSArray *contents = [fileManager contentsOfDirectoryAtURL:dirURL includingPropertiesForKeys:nil options:0 error:&error];
		if (error) {
			NSLog(@"BattmanPrefs: Error reading %@ (%@): %@", label, dirURL.path, error.localizedDescription);
			return;
		}
		
		if (dryRun) {
#ifdef DEBUG
			DBGLOG(@"BattmanPrefs: [DRY RUN] Would delete %lu items from %@ (%@):", (unsigned long)contents.count, label, dirURL.path);
			for (NSURL *fileURL in contents) {
				DBGLOG(@"BattmanPrefs: [DRY RUN]   - %@", fileURL.path);
			}
#endif
			return;
		}
		
		DBGLOG(@"BattmanPrefs: Deleting %lu items from %@", (unsigned long)contents.count, label);
		for (NSURL *fileURL in contents) {
			NSError *deleteError = nil;
			if ([fileManager removeItemAtURL:fileURL error:&deleteError]) {
				DBGLOG(@"BattmanPrefs: Deleted %@", fileURL.path);
			} else {
				DBGLOG(@"BattmanPrefs: Failed to delete %@: %@", fileURL.path, deleteError.localizedDescription);
			}
		}
	};
	
	// Clear the backing store
	if (dryRun) {
		__block NSUInteger backingCount = 0;
		dispatch_sync(self.queue, ^{
			backingCount = self.backing.count;
			DBGLOG(@"BattmanPrefs: [DRY RUN] Would clear %lu items from backing store:", (unsigned long)backingCount);
			[self.backing enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
				DBGLOG(@"BattmanPrefs: [DRY RUN]   - %@: %@", key, obj);
			}];
		});
	} else {
		dispatch_sync(self.queue, ^{
			DBGLOG(@"BattmanPrefs: Clearing %lu items from backing store", (unsigned long)self.backing.count);
			[self.backing removeAllObjects];
		});
	}
	
	// Clear NSUserDefaults
	NSUserDefaults *std = [NSUserDefaults standardUserDefaults];
	NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
	if (dryRun) {
#ifdef DEBUG
		NSDictionary *domain = [std persistentDomainForName:bundleIdentifier];
		DBGLOG(@"BattmanPrefs: [DRY RUN] Would remove persistent domain for bundle '%@' with %lu keys:", bundleIdentifier, (unsigned long)domain.count);
		for (NSString *key in domain) {
			DBGLOG(@"BattmanPrefs: [DRY RUN]   - %@: %@", key, domain[key]);
		}
#endif
	} else {
#ifdef DEBUG
		NSDictionary *domain = [std persistentDomainForName:bundleIdentifier];
		DBGLOG(@"BattmanPrefs: Removing persistent domain for bundle '%@' with %lu keys", bundleIdentifier, (unsigned long)domain.count);
#endif
		[std removePersistentDomainForName:bundleIdentifier];
		[std synchronize];
	}
	
	// Clear Battman config directory only
	const char *configDirPath = battman_config_dir();
	NSString *configDirString = nil;
	NSURL *configURL = nil;
	if (configDirPath) {
		configDirString = [NSString stringWithUTF8String:configDirPath];
		configURL = [NSURL fileURLWithPath:configDirString];
		wipeDirectoryContents(configURL, @"Battman config directory");
	} else {
		NSLog(@"BattmanPrefs: Warning - battman_config_dir() returned NULL, cannot clean config directory");
	}
	
	// Clear MobileContainerManager AppData container if it differs from config dir
	NSURL *containerURL = nil;
	NSBundle *mcmBundle = [NSBundle systemBundleWithName:@"MobileContainerManager"];
	if (mcmBundle && [mcmBundle load]) {
		BOOL existed = NO;
		NSError *error = nil;
		MCMContainer *container = [[mcmBundle classNamed:@"MCMAppDataContainer"] containerWithIdentifier:bundleIdentifier createIfNecessary:NO existed:&existed error:&error];
		if (container && [container respondsToSelector:@selector(url)]) {
			containerURL = [container url];
		} else if (error) {
			DBGLOG(@"BattmanPrefs: Unable to get AppData container: %@", error.localizedDescription);
		}
	}
	
	if (containerURL.path.length) {
		BOOL isSamePath = (configURL && [configURL.path isEqualToString:containerURL.path]);
		if (!isSamePath) {
			wipeDirectoryContents(containerURL, @"AppData container");
		}
	}

	NSLog(@"BattmanPrefs: %@ wipe all data operation completed", dryRun ? @"DRY RUN -" : @"");
}

@end
