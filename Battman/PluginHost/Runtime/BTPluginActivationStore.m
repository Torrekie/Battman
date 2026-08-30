//
//  BTPluginActivationStore.m
//  Battman
//

#import "BTPluginActivationStore.h"
#import "BTPluginApplicationDataTransaction.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"

static NSString * const BTPluginDefaultActivationStoreService = @"com.torrekie.Battman.PluginActivation.v1";
static NSString * const BTPluginActivationStoreAccount = @"state";
static NSUInteger const BTPluginActivationMaximumRecords = 128;
static NSUInteger const BTPluginActivationMaximumStateBytes = 256 * 1024;
static NSNumber *BTPluginActivationCurrentSchema(void) { return @2; }

static NSError *BTPluginActivationError(NSString *description, OSStatus status) {
	NSError *underlying = status == errSecSuccess ? nil :
		[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
	return BTPluginPackageMakeError(BTPluginPackageErrorActivationState, description, nil, underlying);
}

static BOOL BTPluginActivationSetError(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginActivationError(description, errSecSuccess);
	return NO;
}

static BOOL BTPluginActivationBoolean(id value, BOOL *output) {
	if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
		return NO;
	if (output)
		*output = [value boolValue];
	return YES;
}

static BOOL BTPluginActivationDictionaryHasOnlyKeys(NSDictionary *dictionary, NSSet<NSString *> *allowedKeys) {
	if (![dictionary isKindOfClass:[NSDictionary class]])
		return NO;
	for (id key in dictionary) {
		if (![key isKindOfClass:[NSString class]] || ![allowedKeys containsObject:key])
			return NO;
	}
	return YES;
}

@interface BTPluginActivationRecord ()
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite) NSString *packageSHA256;
@property (nonatomic, readwrite) BTPluginSource source;
@property (nonatomic, readwrite) BTPluginActivationMode activationMode;
@property (nonatomic, readwrite, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, readwrite) NSDate *updatedAt;
@end

@implementation BTPluginActivationRecord

- (instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier
						 packageSHA256:(NSString *)packageSHA256
								  source:(BTPluginSource)source
						 activationMode:(BTPluginActivationMode)activationMode
								 enabled:(BOOL)enabled
							  updatedAt:(NSDate *)updatedAt
								  error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	BOOL validMode = activationMode == BTPluginActivationModeDirect ||
		activationMode == BTPluginActivationModeRequiresReinstall;
	BOOL validSource = source >= BTPluginSourceAppBundle && source <= BTPluginSourceImport;
	BOOL directSource = activationMode != BTPluginActivationModeDirect || BTPluginSourceCanActivate(source);
	if (!BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(packageSHA256) || !validMode || !validSource || !directSource ||
		![updatedAt isKindOfClass:[NSDate class]]) {
		BTPluginActivationSetError(error, @"A plug-in activation record is malformed.");
		return nil;
	}
	_pluginIdentifier = [pluginIdentifier copy];
	_packageSHA256 = [packageSHA256 copy];
	_source = source;
	_activationMode = activationMode;
	_enabled = enabled;
	_updatedAt = [updatedAt copy];
	return self;
}

@end

@interface BTPluginStartupRecovery ()
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite) NSString *packageSHA256;
@property (nonatomic, readwrite) BTPluginSource source;
@property (nonatomic, copy, readwrite) NSDate *attemptedAt;
- (instancetype)bt_init;
@end

@implementation BTPluginStartupRecovery
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginStartupSnapshot ()
@property (nonatomic, copy, readwrite) NSString *startupIdentifier;
@property (nonatomic, readwrite, getter=isSafeMode) BOOL safeMode;
@property (nonatomic, readwrite, getter=areThirdPartyPluginsEnabled) BOOL thirdPartyPluginsEnabled;
@property (nonatomic, copy, readwrite) NSArray<BTPluginActivationRecord *> *activationRecords;
@property (nonatomic, strong, readwrite, nullable) BTPluginStartupRecovery *recovery;
- (instancetype)bt_init;
@end

@implementation BTPluginStartupSnapshot
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginKeychainActivationStore ()
@property (nonatomic, copy) NSString *serviceName;
- (nullable NSDictionary *)propertyListForActivationRecord:(nullable BTPluginActivationRecord *)record;
- (nullable NSDictionary *)propertyListForRecordIdentifier:(NSString *)pluginIdentifier
	inState:(NSDictionary *)state;
@end

@implementation BTPluginKeychainActivationStore

// The host may briefly own more than one store instance during recovery or UI
// refresh.  Keychain has no compare-and-swap primitive, so every in-process
// read/modify/write sequence uses the class object as its common lock.  The
// plug-in platform is intentionally single-process; a second process sharing
// this service is outside the supported persistence contract.

- (instancetype)init {
	return [self initWithServiceName:BTPluginDefaultActivationStoreService];
}

- (instancetype)initWithServiceName:(NSString *)serviceName {
	self = [super init];
	if (!self)
		return nil;
	_serviceName = ([serviceName isKindOfClass:[NSString class]] && serviceName.length > 0 && serviceName.length <= 255) ?
		[serviceName copy] : [BTPluginDefaultActivationStoreService copy];
	return self;
}

- (NSDictionary *)baseQuery {
	return @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: self.serviceName,
		(__bridge id)kSecAttrAccount: BTPluginActivationStoreAccount,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
}

- (NSMutableDictionary *)emptyState {
	return [@{
		@"schema": BTPluginActivationCurrentSchema(),
		@"thirdPartyEnabled": @NO,
		@"records": [NSMutableArray array],
	} mutableCopy];
}

- (NSData *)dataWithNotFound:(BOOL *)notFound error:(NSError **)error {
	NSMutableDictionary *query = [[self baseQuery] mutableCopy];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) {
		if (notFound)
			*notFound = YES;
		return nil;
	}
	if (status != errSecSuccess || !result || CFGetTypeID(result) != CFDataGetTypeID()) {
		if (result)
			CFRelease(result);
		if (error)
			*error = BTPluginActivationError(@"The plug-in activation state could not be read from Keychain.", status);
		return nil;
	}
	if (notFound)
		*notFound = NO;
	NSData *data = CFBridgingRelease(result);
	if (data.length > BTPluginActivationMaximumStateBytes) {
		if (error)
			*error = BTPluginActivationError(@"The plug-in activation state exceeds its size limit.", errSecSuccess);
		return nil;
	}
	return data;
}

- (BOOL)storeState:(NSDictionary *)state error:(NSError **)error {
	NSMutableDictionary *normalizedState = [state mutableCopy];
	normalizedState[@"schema"] = BTPluginActivationCurrentSchema();
	NSError *serializationError = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:normalizedState
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
	if (!data || data.length > BTPluginActivationMaximumStateBytes) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"The plug-in activation state could not be serialized within its size limit.", nil, serializationError);
		return NO;
	}
	NSDictionary *query = [self baseQuery];
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
		(__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
	if (status == errSecItemNotFound) {
		NSMutableDictionary *addition = [query mutableCopy];
		addition[(__bridge id)kSecValueData] = data;
		addition[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = SecItemAdd((__bridge CFDictionaryRef)addition, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = BTPluginActivationError(@"The plug-in activation state could not be stored in Keychain.", status);
	return NO;
}

- (BTPluginActivationRecord *)recordFromPropertyList:(NSDictionary *)propertyList error:(NSError **)error {
	NSSet *keys = [NSSet setWithArray:@[ @"pluginIdentifier", @"packageSHA256", @"source", @"activationMode", @"enabled", @"updatedAt" ]];
	BOOL enabled = NO;
	NSNumber *source = propertyList[@"source"];
	NSNumber *activationMode = propertyList[@"activationMode"];
	if (!BTPluginActivationDictionaryHasOnlyKeys(propertyList, keys) || propertyList.count != keys.count ||
		![source isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)source) == CFBooleanGetTypeID() ||
		[source doubleValue] != (double)[source unsignedLongLongValue] ||
		![activationMode isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)activationMode) == CFBooleanGetTypeID() ||
		[activationMode doubleValue] != (double)[activationMode unsignedLongLongValue] ||
		!BTPluginActivationBoolean(propertyList[@"enabled"], &enabled)) {
		BTPluginActivationSetError(error, @"A persisted plug-in activation record is malformed.");
		return nil;
	}
	return [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:propertyList[@"pluginIdentifier"]
		packageSHA256:propertyList[@"packageSHA256"]
		source:(BTPluginSource)[source unsignedIntegerValue]
		activationMode:(BTPluginActivationMode)[activationMode unsignedIntegerValue]
		enabled:enabled updatedAt:propertyList[@"updatedAt"] error:error];
}

- (NSDictionary *)propertyListForRecord:(BTPluginActivationRecord *)record {
	if (!record)
		return nil;
	return @{
		@"pluginIdentifier": record.pluginIdentifier,
		@"packageSHA256": record.packageSHA256,
		@"source": @(record.source),
		@"activationMode": @(record.activationMode),
		@"enabled": @(record.isEnabled),
		@"updatedAt": record.updatedAt,
	};
}

- (NSMutableDictionary *)readStateWithError:(NSError **)error {
	BOOL notFound = NO;
	NSData *data = [self dataWithNotFound:&notFound error:error];
	if (notFound)
		return [self emptyState];
	if (!data)
		return nil;
	NSError *propertyListError = nil;
	id value = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListMutableContainersAndLeaves format:NULL error:&propertyListError];
	NSSet *stateKeys = [NSSet setWithArray:@[
		@"schema", @"thirdPartyEnabled", @"records", @"launch", @"applicationDataTransaction"
	]];
	BOOL thirdPartyEnabled = NO;
	if (!BTPluginActivationDictionaryHasOnlyKeys(value, stateKeys) ||
		(![value[@"schema"] isEqual:@1] && ![value[@"schema"] isEqual:BTPluginActivationCurrentSchema()]) ||
		!BTPluginActivationBoolean(value[@"thirdPartyEnabled"], &thirdPartyEnabled) ||
		![value[@"records"] isKindOfClass:[NSArray class]] || [value[@"records"] count] > BTPluginActivationMaximumRecords ||
		(value[@"launch"] && ![value[@"launch"] isKindOfClass:[NSDictionary class]]) ||
		(value[@"applicationDataTransaction"] &&
			![value[@"applicationDataTransaction"] isKindOfClass:[NSDictionary class]])) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState,
				@"The Keychain plug-in activation state is malformed.", nil, propertyListError);
		return nil;
	}
	if ([value[@"schema"] isEqual:@1] && value[@"applicationDataTransaction"]) {
		BTPluginActivationSetError(error,
			@"A legacy plug-in activation state cannot contain an app-data transaction journal.");
		return nil;
	}
	NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
	for (id recordValue in value[@"records"]) {
		BTPluginActivationRecord *record = [self recordFromPropertyList:recordValue error:error];
		if (!record || [identifiers containsObject:record.pluginIdentifier]) {
			if (record && error)
				*error = BTPluginActivationError(@"The plug-in activation state contains duplicate identifiers.", errSecSuccess);
			return nil;
		}
		[identifiers addObject:record.pluginIdentifier];
	}
	if (value[@"applicationDataTransaction"]) {
		BTPluginApplicationDataTransaction *transaction = [BTPluginApplicationDataTransaction
			transactionWithPropertyList:value[@"applicationDataTransaction"] error:error];
		if (!transaction)
			return nil;
		NSDictionary *currentValue = [self propertyListForRecordIdentifier:
			transaction.pluginIdentifier inState:value];
		NSDictionary *targetValue = [self propertyListForActivationRecord:transaction.targetActivationRecord];
		if ((currentValue || targetValue) && ![currentValue isEqual:targetValue]) {
			BTPluginActivationSetError(error,
				@"The app-data transaction journal disagrees with its target activation state.");
			return nil;
		}
	}
	(void)thirdPartyEnabled;
	return [value mutableCopy];
}

- (NSDictionary *)propertyListForActivationRecord:(BTPluginActivationRecord *)record {
	if (!record)
		return nil;
	return @{
		@"pluginIdentifier": record.pluginIdentifier,
		@"packageSHA256": record.packageSHA256,
		@"source": @(record.source),
		@"activationMode": @(record.activationMode),
		@"enabled": @(record.isEnabled),
		@"updatedAt": record.updatedAt,
	};
}

- (NSDictionary *)propertyListForRecordIdentifier:(NSString *)pluginIdentifier inState:(NSDictionary *)state {
	for (NSDictionary *value in state[@"records"])
		if ([value[@"pluginIdentifier"] isEqualToString:pluginIdentifier])
			return value;
	return nil;
}

- (void)replaceRecord:(BTPluginActivationRecord *)record inState:(NSMutableDictionary *)state {
	NSMutableArray *records = [state[@"records"] mutableCopy];
	NSIndexSet *matches = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *value, NSUInteger index, BOOL *stop) {
		(void)index; (void)stop;
		return [value[@"pluginIdentifier"] isEqualToString:record.pluginIdentifier];
	}];
	if (matches.count > 0)
		records[matches.firstIndex] = [self propertyListForActivationRecord:record];
	else
		[records addObject:[self propertyListForActivationRecord:record]];
	[records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return [left[@"pluginIdentifier"] compare:right[@"pluginIdentifier"] options:NSLiteralSearch];
	}];
	state[@"records"] = records;
}

- (void)removeRecordIdentifier:(NSString *)pluginIdentifier fromState:(NSMutableDictionary *)state {
	NSMutableArray *records = [state[@"records"] mutableCopy];
	NSIndexSet *matches = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *value, NSUInteger index, BOOL *stop) {
		(void)index; (void)stop;
		return [value[@"pluginIdentifier"] isEqualToString:pluginIdentifier];
	}];
	[records removeObjectsAtIndexes:matches];
	state[@"records"] = records;
}

- (NSArray<BTPluginActivationRecord *> *)recordsFromState:(NSDictionary *)state error:(NSError **)error {
	NSMutableArray<BTPluginActivationRecord *> *records = [NSMutableArray array];
	for (NSDictionary *recordValue in state[@"records"]) {
		BTPluginActivationRecord *record = [self recordFromPropertyList:recordValue error:error];
		if (!record)
			return nil;
		[records addObject:record];
	}
	[records sortUsingComparator:^NSComparisonResult(BTPluginActivationRecord *left, BTPluginActivationRecord *right) {
		return [left.pluginIdentifier compare:right.pluginIdentifier options:NSLiteralSearch];
	}];
	return records;
}

- (BOOL)thirdPartyPluginsEnabledWithError:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		BOOL enabled = NO;
		return BTPluginActivationBoolean(state[@"thirdPartyEnabled"], &enabled) && enabled;
	}
}

- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error,
				@"Activation policy cannot change while an app-data transaction is pending.");
		state[@"thirdPartyEnabled"] = @(enabled);
		return [self storeState:state error:error];
	}
}

- (NSArray<BTPluginActivationRecord *> *)activationRecordsWithError:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSDictionary *state = [self readStateWithError:error];
		return state ? [self recordsFromState:state error:error] : nil;
	}
}

- (BOOL)scheduleActivationRecord:(BTPluginActivationRecord *)record error:(NSError **)error {
	if (![record isKindOfClass:[BTPluginActivationRecord class]])
		return BTPluginActivationSetError(error, @"The requested plug-in activation record is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error,
				@"Activation records cannot change while an app-data transaction is pending.");
		NSMutableArray *records = [state[@"records"] mutableCopy];
		NSUInteger replacement = NSNotFound;
		for (NSUInteger index = 0; index < records.count; index++) {
			if ([records[index][@"pluginIdentifier"] isEqualToString:record.pluginIdentifier]) {
				replacement = index;
				break;
			}
		}
		NSDictionary *propertyList = [self propertyListForRecord:record];
		if (replacement == NSNotFound) {
			if (records.count >= BTPluginActivationMaximumRecords)
				return BTPluginActivationSetError(error, @"The plug-in activation record limit has been reached.");
			[records addObject:propertyList];
		} else {
			records[replacement] = propertyList;
		}
		[records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
			return [left[@"pluginIdentifier"] compare:right[@"pluginIdentifier"] options:NSLiteralSearch];
		}];
		state[@"records"] = records;
		return [self storeState:state error:error];
	}
}

- (BTPluginApplicationDataTransaction *)pendingApplicationDataTransactionWithError:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return nil;
		NSDictionary *value = state[@"applicationDataTransaction"];
		if (!value)
			return nil;
		return [BTPluginApplicationDataTransaction transactionWithPropertyList:value error:error];
	}
}

- (BOOL)beginApplicationDataTransaction:(BTPluginApplicationDataTransaction *)transaction
	expectedActivationRecord:(BTPluginActivationRecord *)expectedActivationRecord error:(NSError **)error {
	if (![transaction isKindOfClass:[BTPluginApplicationDataTransaction class]])
		return BTPluginActivationSetError(error, @"The app-data transaction is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error, @"Another app-data transaction is already pending.");
		NSDictionary *currentValue = [self propertyListForRecordIdentifier:transaction.pluginIdentifier inState:state];
		NSDictionary *expectedValue = [self propertyListForActivationRecord:expectedActivationRecord];
		NSDictionary *journalPreviousValue = [self propertyListForActivationRecord:
			transaction.previousActivationRecord];
		if ((expectedValue || journalPreviousValue) && ![expectedValue isEqual:journalPreviousValue])
			return BTPluginActivationSetError(error,
				@"The app-data transaction previous state does not match its compare-and-swap input.");
		if ((currentValue || expectedValue) && ![currentValue isEqual:expectedValue])
			return BTPluginActivationSetError(error, @"The app-data activation state changed before the transaction began.");
		if (transaction.targetActivationRecord && !currentValue &&
			[state[@"records"] count] >= BTPluginActivationMaximumRecords)
			return BTPluginActivationSetError(error, @"The plug-in activation record limit has been reached.");
		if (transaction.targetActivationRecord)
			[self replaceRecord:transaction.targetActivationRecord inState:state];
		else
			[self removeRecordIdentifier:transaction.pluginIdentifier fromState:state];
		state[@"applicationDataTransaction"] = transaction.propertyListRepresentation;
		return [self storeState:state error:error];
	}
}

- (BOOL)finishApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier error:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		BTPluginApplicationDataTransaction *transaction = [BTPluginApplicationDataTransaction
			transactionWithPropertyList:state[@"applicationDataTransaction"] error:error];
		if (!transaction || ![transaction.transactionIdentifier isEqualToString:transactionIdentifier])
			return BTPluginActivationSetError(error, @"The app-data transaction token is stale or missing.");
		NSDictionary *currentValue = [self propertyListForRecordIdentifier:transaction.pluginIdentifier inState:state];
		NSDictionary *targetValue = [self propertyListForActivationRecord:transaction.targetActivationRecord];
		if ((currentValue || targetValue) && ![currentValue isEqual:targetValue])
			return BTPluginActivationSetError(error, @"The app-data transaction target activation state changed.");
		[state removeObjectForKey:@"applicationDataTransaction"];
		return [self storeState:state error:error];
	}
}

- (BOOL)abortApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier error:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		BTPluginApplicationDataTransaction *transaction = [BTPluginApplicationDataTransaction
			transactionWithPropertyList:state[@"applicationDataTransaction"] error:error];
		if (!transaction || ![transaction.transactionIdentifier isEqualToString:transactionIdentifier])
			return BTPluginActivationSetError(error, @"The app-data transaction token is stale or missing.");
		NSDictionary *currentValue = [self propertyListForRecordIdentifier:transaction.pluginIdentifier inState:state];
		NSDictionary *targetValue = [self propertyListForActivationRecord:transaction.targetActivationRecord];
		if ((currentValue || targetValue) && ![currentValue isEqual:targetValue])
			return BTPluginActivationSetError(error,
				@"The app-data transaction target activation state changed before abort.");
		if (transaction.previousActivationRecord)
			[self replaceRecord:transaction.previousActivationRecord inState:state];
		else
			[self removeRecordIdentifier:transaction.pluginIdentifier fromState:state];
		[state removeObjectForKey:@"applicationDataTransaction"];
		return [self storeState:state error:error];
	}
}

- (BOOL)setPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier))
		return BTPluginActivationSetError(error, @"The plug-in identifier to enable or disable is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error,
				@"Activation records cannot change while an app-data transaction is pending.");
		NSMutableArray *records = [state[@"records"] mutableCopy];
		for (NSUInteger index = 0; index < records.count; index++) {
			NSDictionary *value = records[index];
			if (![value[@"pluginIdentifier"] isEqualToString:pluginIdentifier])
				continue;
			BTPluginActivationRecord *old = [self recordFromPropertyList:value error:error];
			if (!old)
				return NO;
			BTPluginActivationRecord *updated = [[BTPluginActivationRecord alloc]
				initWithPluginIdentifier:old.pluginIdentifier packageSHA256:old.packageSHA256
				source:old.source activationMode:old.activationMode enabled:enabled updatedAt:[NSDate date] error:error];
			if (!updated)
				return NO;
			records[index] = [self propertyListForRecord:updated];
			state[@"records"] = records;
			return [self storeState:state error:error];
		}
		return BTPluginActivationSetError(error, @"The plug-in activation record does not exist.");
	}
}

- (BOOL)removePluginIdentifier:(NSString *)pluginIdentifier error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier))
		return BTPluginActivationSetError(error, @"The plug-in identifier to remove is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error,
				@"Activation records cannot change while an app-data transaction is pending.");
		NSMutableArray *records = [state[@"records"] mutableCopy];
		NSIndexSet *matches = [records indexesOfObjectsPassingTest:^BOOL(NSDictionary *value, NSUInteger index, BOOL *stop) {
			(void)index; (void)stop;
			return [value[@"pluginIdentifier"] isEqualToString:pluginIdentifier];
		}];
		if (matches.count == 0)
			return YES;
		[records removeObjectsAtIndexes:matches];
		state[@"records"] = records;
		return [self storeState:state error:error];
	}
}

- (BTPluginStartupRecovery *)recoveryFromLaunch:(NSDictionary *)launch error:(NSError **)error {
	NSSet *launchKeys = [NSSet setWithArray:@[ @"startupIdentifier", @"beganAt", @"settled", @"settledAt", @"lastAttempt" ]];
	BOOL settled = NO;
	if (!BTPluginActivationDictionaryHasOnlyKeys(launch, launchKeys) ||
		![launch[@"startupIdentifier"] isKindOfClass:[NSString class]] ||
		![launch[@"beganAt"] isKindOfClass:[NSDate class]] ||
		!BTPluginActivationBoolean(launch[@"settled"], &settled) ||
		(launch[@"settledAt"] && ![launch[@"settledAt"] isKindOfClass:[NSDate class]]) ||
		(launch[@"lastAttempt"] && ![launch[@"lastAttempt"] isKindOfClass:[NSDictionary class]])) {
		BTPluginActivationSetError(error, @"The persisted plug-in startup marker is malformed.");
		return nil;
	}
	if (settled || !launch[@"lastAttempt"])
		return nil;
	NSDictionary *attempt = launch[@"lastAttempt"];
	NSSet *attemptKeys = [NSSet setWithArray:@[ @"pluginIdentifier", @"packageSHA256", @"source", @"attemptedAt" ]];
	if (!BTPluginActivationDictionaryHasOnlyKeys(attempt, attemptKeys) || attempt.count != attemptKeys.count ||
		!BTPluginIdentifierIsValid(attempt[@"pluginIdentifier"]) ||
		!BTPluginPackageLowercaseSHA256IsValid(attempt[@"packageSHA256"]) ||
		![attempt[@"source"] isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)attempt[@"source"]) == CFBooleanGetTypeID() ||
		![attempt[@"attemptedAt"] isKindOfClass:[NSDate class]]) {
		BTPluginActivationSetError(error, @"The persisted last plug-in load attempt is malformed.");
		return nil;
	}
	BTPluginSource source = (BTPluginSource)[attempt[@"source"] unsignedIntegerValue];
	if (source < BTPluginSourceAppBundle || source > BTPluginSourceImport) {
		BTPluginActivationSetError(error, @"The persisted last plug-in load source is invalid.");
		return nil;
	}
	BTPluginStartupRecovery *recovery = [[BTPluginStartupRecovery alloc] bt_init];
	recovery.pluginIdentifier = attempt[@"pluginIdentifier"];
	recovery.packageSHA256 = attempt[@"packageSHA256"];
	recovery.source = source;
	recovery.attemptedAt = attempt[@"attemptedAt"];
	return recovery;
}

- (BTPluginStartupSnapshot *)beginStartupWithSafeModeRequested:(BOOL)safeModeRequested error:(NSError **)error {
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return nil;
		if (state[@"applicationDataTransaction"]) {
			BTPluginActivationSetError(error,
				@"An app-data transaction must be reconciled before startup.");
			return nil;
		}
		BTPluginStartupRecovery *recovery = nil;
		if (state[@"launch"]) {
			NSError *recoveryError = nil;
			recovery = [self recoveryFromLaunch:state[@"launch"] error:&recoveryError];
			if (recoveryError) {
				if (error)
					*error = recoveryError;
				return nil;
			}
		}
		NSString *startupIdentifier = NSUUID.UUID.UUIDString.lowercaseString;
		state[@"launch"] = @{
			@"startupIdentifier": startupIdentifier,
			@"beganAt": [NSDate date],
			@"settled": @NO,
		};
		if (![self storeState:state error:error])
			return nil;
		BOOL storedThirdPartyEnabled = NO;
		BTPluginActivationBoolean(state[@"thirdPartyEnabled"], &storedThirdPartyEnabled);
		BTPluginStartupSnapshot *snapshot = [[BTPluginStartupSnapshot alloc] bt_init];
		snapshot.startupIdentifier = startupIdentifier;
		snapshot.safeMode = safeModeRequested || recovery != nil;
		snapshot.thirdPartyPluginsEnabled = storedThirdPartyEnabled && !snapshot.isSafeMode;
		snapshot.activationRecords = [self recordsFromState:state error:error];
		if (!snapshot.activationRecords)
			return nil;
		snapshot.recovery = recovery;
		return snapshot;
	}
}

- (BOOL)recordThirdPartyLoadAttemptForPluginIdentifier:(NSString *)pluginIdentifier
										 packageSHA256:(NSString *)packageSHA256
												 source:(BTPluginSource)source
								 startupIdentifier:(NSString *)startupIdentifier
												  error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier) || !BTPluginPackageLowercaseSHA256IsValid(packageSHA256) ||
		source < BTPluginSourceAppBundle || source > BTPluginSourceImport ||
		![startupIdentifier isKindOfClass:[NSString class]] || startupIdentifier.length == 0 || startupIdentifier.length > 64)
		return BTPluginActivationSetError(error, @"The plug-in load-attempt marker is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		NSDictionary *launch = state[@"launch"];
		BOOL settled = YES;
		if (![launch isKindOfClass:[NSDictionary class]] ||
			![launch[@"startupIdentifier"] isEqualToString:startupIdentifier] ||
			!BTPluginActivationBoolean(launch[@"settled"], &settled) || settled)
			return BTPluginActivationSetError(error, @"The plug-in load attempt does not match the active startup session.");
		NSMutableDictionary *updatedLaunch = [launch mutableCopy];
		updatedLaunch[@"lastAttempt"] = @{
			@"pluginIdentifier": pluginIdentifier,
			@"packageSHA256": packageSHA256,
			@"source": @(source),
			@"attemptedAt": [NSDate date],
		};
		state[@"launch"] = updatedLaunch;
		return [self storeState:state error:error];
	}
}

- (BOOL)markStartupSettledWithIdentifier:(NSString *)startupIdentifier error:(NSError **)error {
	if (![startupIdentifier isKindOfClass:[NSString class]] || startupIdentifier.length == 0 || startupIdentifier.length > 64)
		return BTPluginActivationSetError(error, @"The startup identifier to settle is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		NSDictionary *launch = state[@"launch"];
		if (![launch isKindOfClass:[NSDictionary class]] ||
			![launch[@"startupIdentifier"] isEqualToString:startupIdentifier])
			return BTPluginActivationSetError(error, @"The startup marker no longer matches this process.");
		NSMutableDictionary *updatedLaunch = [launch mutableCopy];
		updatedLaunch[@"settled"] = @YES;
		updatedLaunch[@"settledAt"] = [NSDate date];
		state[@"launch"] = updatedLaunch;
		return [self storeState:state error:error];
	}
}

- (BOOL)disablePluginFromRecovery:(BTPluginStartupRecovery *)recovery error:(NSError **)error {
	if (![recovery isKindOfClass:[BTPluginStartupRecovery class]])
		return BTPluginActivationSetError(error, @"The plug-in recovery selection is invalid.");
	@synchronized ([BTPluginKeychainActivationStore class]) {
		NSMutableDictionary *state = [self readStateWithError:error];
		if (!state)
			return NO;
		if (state[@"applicationDataTransaction"])
			return BTPluginActivationSetError(error,
				@"Activation records cannot change while an app-data transaction is pending.");
		NSMutableArray *records = [state[@"records"] mutableCopy];
		for (NSUInteger index = 0; index < records.count; index++) {
			BTPluginActivationRecord *record = [self recordFromPropertyList:records[index] error:error];
			if (!record)
				return NO;
			if (![record.pluginIdentifier isEqualToString:recovery.pluginIdentifier])
				continue;
			if (![record.packageSHA256 isEqualToString:recovery.packageSHA256])
				return BTPluginActivationSetError(error,
					@"The recovered plug-in was replaced by a newer build and was not disabled.");
			BTPluginActivationRecord *disabled = [[BTPluginActivationRecord alloc]
				initWithPluginIdentifier:record.pluginIdentifier packageSHA256:record.packageSHA256
				source:record.source activationMode:record.activationMode enabled:NO updatedAt:[NSDate date] error:error];
			if (!disabled)
				return NO;
			records[index] = [self propertyListForRecord:disabled];
			state[@"records"] = records;
			return [self storeState:state error:error];
		}
		return BTPluginActivationSetError(error, @"The recovered plug-in activation record no longer exists.");
	}
}

@end
