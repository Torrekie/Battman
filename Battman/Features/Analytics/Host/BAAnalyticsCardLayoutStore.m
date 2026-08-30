//
//  BAAnalyticsCardLayoutStore.m
//  Battman
//


#import "BAAnalyticsCardLayoutStore.h"

NSString *const BAAnalyticsCardLayoutDefaultsKey = @"AnalyticsCardLayout.v3";
NSString *const BAAnalyticsLegacyCardLayoutDefaultsKey = @"AnalyticsCardLayout.v2";
NSUInteger const BAAnalyticsCardLayoutFormatVersion = 3;

static NSUInteger const BAAnalyticsMaximumCardCount = 128;
static NSUInteger const BAAnalyticsMaximumIdentifierLength = 255;
static NSUInteger const BAAnalyticsMaximumDisplayNameLength = 128;
static NSUInteger const BAAnalyticsMaximumRestorationDepth = 8;
static NSUInteger const BAAnalyticsMaximumRestorationNodeCount = 256;
static NSUInteger const BAAnalyticsMaximumRestorationBytes = 16 * 1024;

static BOOL BAAnalyticsValidatePropertyListNode(id value, NSUInteger depth, NSUInteger *nodeCount) {
	if (!value || depth > BAAnalyticsMaximumRestorationDepth || *nodeCount >= BAAnalyticsMaximumRestorationNodeCount)
		return NO;
	*nodeCount += 1;

	if ([value isKindOfClass:[NSString class]])
		return [(NSString *)value length] <= 4096;
	if ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSDate class]])
		return YES;
	if ([value isKindOfClass:[NSData class]])
		return [(NSData *)value length] <= BAAnalyticsMaximumRestorationBytes;
	if ([value isKindOfClass:[NSArray class]]) {
		for (id child in (NSArray *)value) {
			if (!BAAnalyticsValidatePropertyListNode(child, depth + 1, nodeCount))
				return NO;
		}
		return YES;
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		for (id key in (NSDictionary *)value) {
			if (![key isKindOfClass:[NSString class]] || [(NSString *)key length] > 128)
				return NO;
			if (!BAAnalyticsValidatePropertyListNode([(NSDictionary *)value objectForKey:key], depth + 1, nodeCount))
				return NO;
		}
		return YES;
	}
	return NO;
}

static NSDictionary *BAAnalyticsBoundedRestorationState(id candidate) {
	if (![candidate isKindOfClass:[NSDictionary class]])
		return nil;
	NSUInteger nodeCount = 0;
	if (!BAAnalyticsValidatePropertyListNode(candidate, 0, &nodeCount))
		return nil;
	NSError *error = nil;
	NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:candidate
														format:NSPropertyListBinaryFormat_v1_0
													   options:0
														 error:&error];
	if (!encoded || encoded.length > BAAnalyticsMaximumRestorationBytes)
		return nil;
	id decoded = [NSPropertyListSerialization propertyListWithData:encoded
													options:NSPropertyListImmutable
													 format:NULL
													  error:&error];
	return [decoded isKindOfClass:[NSDictionary class]] ? decoded : nil;
}

@implementation BAAnalyticsCardLayoutRecord

- (instancetype)initWithCardIdentifier:(NSString *)cardIdentifier
						 displayName:(NSString *)displayName
						   sizeValue:(NSInteger)sizeValue
		 restorationSchemaVersion:(NSUInteger)restorationSchemaVersion
					 restorationState:(NSDictionary *)restorationState {
	self = [super init];
	if (!self)
		return nil;
	_cardIdentifier = [cardIdentifier copy];
	_displayName = [displayName copy];
	_sizeValue = sizeValue;
	_restorationSchemaVersion = restorationSchemaVersion;
	_restorationState = [BAAnalyticsBoundedRestorationState(restorationState) copy];
	return self;
}

@end

@implementation BAAnalyticsCardLayoutStore

+ (NSString *)canonicalCardIdentifierForStoredIdentifier:(NSString *)storedIdentifier {
	static NSDictionary<NSString *, NSString *> *legacyIdentifiers;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		legacyIdentifiers = @{
			@"battery.summary": @"com.torrekie.battman.analytics.battery.summary",
			@"temperature.average": @"com.torrekie.battman.analytics.temperature.average",
			@"power.average": @"com.torrekie.battman.analytics.power.average",
			@"cycle.summary": @"com.torrekie.battman.analytics.cycle.summary",
			@"capacity.remaining": @"com.torrekie.battman.analytics.capacity.remaining",
			@"charge.history": @"com.torrekie.battman.analytics.charging-limit",
		};
	});
	return legacyIdentifiers[storedIdentifier] ?: storedIdentifier;
}

+ (BAAnalyticsCardLayoutRecord *)recordFromDictionary:(NSDictionary *)entry legacy:(BOOL)legacy {
	id rawIdentifier = entry[@"id"];
	if (![rawIdentifier isKindOfClass:[NSString class]] || [rawIdentifier length] == 0 || [rawIdentifier length] > BAAnalyticsMaximumIdentifierLength)
		return nil;
	NSString *identifier = [self canonicalCardIdentifierForStoredIdentifier:rawIdentifier];

	id rawDisplayName = legacy ? nil : entry[@"displayName"];
	NSString *displayName = [rawDisplayName isKindOfClass:[NSString class]] ? rawDisplayName : identifier;
	if (displayName.length == 0)
		displayName = identifier;
	if (displayName.length > BAAnalyticsMaximumDisplayNameLength)
		displayName = [displayName substringToIndex:BAAnalyticsMaximumDisplayNameLength];

	id rawSize = entry[@"size"];
	if (![rawSize isKindOfClass:[NSNumber class]])
		return nil;
	NSInteger sizeValue = [rawSize integerValue];
	if (sizeValue < 0 || sizeValue > 3)
		return nil;

	NSUInteger restorationSchemaVersion = 0;
	id rawSchemaVersion = entry[@"restorationSchemaVersion"];
	if ([rawSchemaVersion isKindOfClass:[NSNumber class]] && [rawSchemaVersion integerValue] >= 0)
		restorationSchemaVersion = [rawSchemaVersion unsignedIntegerValue];
	NSDictionary *restorationState = legacy ? nil : BAAnalyticsBoundedRestorationState(entry[@"restorationState"]);
	return [[BAAnalyticsCardLayoutRecord alloc] initWithCardIdentifier:identifier
													 displayName:displayName
													   sizeValue:sizeValue
										 restorationSchemaVersion:restorationSchemaVersion
												 restorationState:restorationState];
}

+ (NSArray<BAAnalyticsCardLayoutRecord *> *)loadRecordsFromUserDefaults:(NSUserDefaults *)userDefaults {
	NSParameterAssert(userDefaults != nil);
	id storedLayout = [userDefaults objectForKey:BAAnalyticsCardLayoutDefaultsKey];
	NSArray *entries = nil;
	BOOL legacy = NO;
	if ([storedLayout isKindOfClass:[NSDictionary class]] &&
		[storedLayout[@"version"] isKindOfClass:[NSNumber class]] &&
		[storedLayout[@"version"] unsignedIntegerValue] == BAAnalyticsCardLayoutFormatVersion &&
		[storedLayout[@"cards"] isKindOfClass:[NSArray class]]) {
		entries = storedLayout[@"cards"];
	} else if (!storedLayout) {
		id legacyLayout = [userDefaults objectForKey:BAAnalyticsLegacyCardLayoutDefaultsKey];
		if ([legacyLayout isKindOfClass:[NSArray class]]) {
			entries = legacyLayout;
			legacy = YES;
		}
	}
	if (!entries)
		return @[];

	NSMutableArray<BAAnalyticsCardLayoutRecord *> *records = [NSMutableArray array];
	NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
	for (id entry in entries) {
		if (records.count >= BAAnalyticsMaximumCardCount || ![entry isKindOfClass:[NSDictionary class]])
			break;
		BAAnalyticsCardLayoutRecord *record = [self recordFromDictionary:entry legacy:legacy];
		if (!record || [seenIdentifiers containsObject:record.cardIdentifier])
			continue;
		[records addObject:record];
		[seenIdentifiers addObject:record.cardIdentifier];
	}
	return [records copy];
}

+ (void)saveRecords:(NSArray<BAAnalyticsCardLayoutRecord *> *)records toUserDefaults:(NSUserDefaults *)userDefaults {
	NSParameterAssert(userDefaults != nil);
	NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
	NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
	for (BAAnalyticsCardLayoutRecord *record in records) {
		if (entries.count >= BAAnalyticsMaximumCardCount || ![record isKindOfClass:[BAAnalyticsCardLayoutRecord class]])
			break;
		if (record.cardIdentifier.length == 0 || record.cardIdentifier.length > BAAnalyticsMaximumIdentifierLength || [seenIdentifiers containsObject:record.cardIdentifier])
			continue;
		NSMutableDictionary *entry = [@{
			@"id": record.cardIdentifier,
			@"displayName": record.displayName.length > 0 ? record.displayName : record.cardIdentifier,
			@"size": @(record.sizeValue),
			@"restorationSchemaVersion": @(record.restorationSchemaVersion),
		} mutableCopy];
		NSDictionary *restorationState = BAAnalyticsBoundedRestorationState(record.restorationState);
		if (restorationState)
			entry[@"restorationState"] = restorationState;
		[entries addObject:entry];
		[seenIdentifiers addObject:record.cardIdentifier];
	}
	[userDefaults setObject:@{
		@"version": @(BAAnalyticsCardLayoutFormatVersion),
		@"cards": entries,
	} forKey:BAAnalyticsCardLayoutDefaultsKey];
}

@end
