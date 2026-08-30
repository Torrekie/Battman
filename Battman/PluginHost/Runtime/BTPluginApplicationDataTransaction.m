//
//  BTPluginApplicationDataTransaction.m
//  Battman
//

#import "BTPluginApplicationDataTransaction.h"

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"

static BOOL BTPluginTransactionFail(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorActivationState, description, nil, nil);
	return NO;
}

static BOOL BTPluginTransactionDictionaryHasOnlyKeys(NSDictionary *dictionary, NSSet<NSString *> *allowed) {
	if (![dictionary isKindOfClass:[NSDictionary class]])
		return NO;
	for (id key in dictionary) {
		if (![key isKindOfClass:[NSString class]] || ![allowed containsObject:key])
			return NO;
	}
	return YES;
}

static NSDictionary *BTPluginTransactionPropertyListForRecord(BTPluginActivationRecord *record) {
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

static BTPluginActivationRecord *BTPluginTransactionRecordFromPropertyList(NSDictionary *value,
	NSError **error) {
	NSSet *keys = [NSSet setWithArray:@[
		@"pluginIdentifier", @"packageSHA256", @"source", @"activationMode", @"enabled", @"updatedAt"
	]];
	if (!BTPluginTransactionDictionaryHasOnlyKeys(value, keys) || value.count != keys.count ||
		![value[@"source"] isKindOfClass:[NSNumber class]] ||
		![value[@"activationMode"] isKindOfClass:[NSNumber class]] ||
		![value[@"enabled"] isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)value[@"source"]) == CFBooleanGetTypeID() ||
		CFGetTypeID((__bridge CFTypeRef)value[@"activationMode"]) == CFBooleanGetTypeID() ||
		[value[@"source"] doubleValue] != (double)[value[@"source"] unsignedLongLongValue] ||
		[value[@"activationMode"] doubleValue] !=
			(double)[value[@"activationMode"] unsignedLongLongValue] ||
		CFGetTypeID((__bridge CFTypeRef)value[@"enabled"]) != CFBooleanGetTypeID()) {
		BTPluginTransactionFail(error, @"A persisted app-data transaction record is malformed.");
		return nil;
	}
	return [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:value[@"pluginIdentifier"]
		packageSHA256:value[@"packageSHA256"]
		source:(BTPluginSource)[value[@"source"] unsignedIntegerValue]
		activationMode:(BTPluginActivationMode)[value[@"activationMode"] unsignedIntegerValue]
		enabled:[value[@"enabled"] boolValue]
		updatedAt:value[@"updatedAt"] error:error];
}

static BOOL BTPluginTransactionRecordIsDirectApplicationData(BTPluginActivationRecord *record,
	NSString *pluginIdentifier) {
	return [record isKindOfClass:[BTPluginActivationRecord class]] &&
		record.source == BTPluginSourceApplicationData &&
		record.activationMode == BTPluginActivationModeDirect &&
		[record.pluginIdentifier isEqualToString:pluginIdentifier];
}

@interface BTPluginApplicationDataTransaction ()
@property (nonatomic, copy, readwrite) NSString *transactionIdentifier;
@property (nonatomic, readwrite) BTPluginApplicationDataTransactionOperation operation;
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite, nullable) NSString *expectedPackageSHA256;
@property (nonatomic, copy, readwrite, nullable) NSString *targetPackageSHA256;
@property (nonatomic, strong, readwrite, nullable) BTPluginActivationRecord *previousActivationRecord;
@property (nonatomic, strong, readwrite, nullable) BTPluginActivationRecord *targetActivationRecord;
@property (nonatomic, copy, readwrite) NSDate *beganAt;
@end

@implementation BTPluginApplicationDataTransaction

- (instancetype)initWithTransactionIdentifier:(NSString *)transactionIdentifier
	operation:(BTPluginApplicationDataTransactionOperation)operation
	pluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString *)expectedPackageSHA256
	targetPackageSHA256:(NSString *)targetPackageSHA256
	previousActivationRecord:(BTPluginActivationRecord *)previousActivationRecord
	targetActivationRecord:(BTPluginActivationRecord *)targetActivationRecord
	 beganAt:(NSDate *)beganAt error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	BOOL validOperation = operation == BTPluginApplicationDataTransactionOperationInstall ||
		operation == BTPluginApplicationDataTransactionOperationUpdate ||
		operation == BTPluginApplicationDataTransactionOperationRemove;
	BOOL validIdentifier = [transactionIdentifier isKindOfClass:[NSString class]] &&
		transactionIdentifier.length == 36 &&
		[transactionIdentifier isEqualToString:transactionIdentifier.lowercaseString] &&
		[[NSUUID alloc] initWithUUIDString:transactionIdentifier] != nil;
	BOOL validExpected = !expectedPackageSHA256 || BTPluginPackageLowercaseSHA256IsValid(expectedPackageSHA256);
	BOOL validTarget = !targetPackageSHA256 || BTPluginPackageLowercaseSHA256IsValid(targetPackageSHA256);
	if (!validOperation || !validIdentifier || !BTPluginIdentifierIsValid(pluginIdentifier) ||
		!validExpected || !validTarget || ![beganAt isKindOfClass:[NSDate class]]) {
		BTPluginTransactionFail(error, @"An app-data transaction has invalid identity or digest fields.");
		return nil;
	}
	BOOL isRemoval = operation == BTPluginApplicationDataTransactionOperationRemove;
	BOOL isInstallOrUpdate = !isRemoval;
	if ((isRemoval && (!expectedPackageSHA256 || targetPackageSHA256 || targetActivationRecord)) ||
		(operation == BTPluginApplicationDataTransactionOperationInstall &&
			(expectedPackageSHA256 || previousActivationRecord)) ||
		(operation == BTPluginApplicationDataTransactionOperationUpdate && !expectedPackageSHA256) ||
		(isInstallOrUpdate && (!targetPackageSHA256 || !BTPluginTransactionRecordIsDirectApplicationData(
			targetActivationRecord, pluginIdentifier))) ||
		(targetActivationRecord && ![targetActivationRecord.packageSHA256 isEqualToString:targetPackageSHA256]) ||
		(previousActivationRecord && !BTPluginTransactionRecordIsDirectApplicationData(
			previousActivationRecord, pluginIdentifier)) ||
		(previousActivationRecord && expectedPackageSHA256 &&
			![previousActivationRecord.packageSHA256 isEqualToString:expectedPackageSHA256]) ||
		(previousActivationRecord && !expectedPackageSHA256 &&
			operation == BTPluginApplicationDataTransactionOperationUpdate)) {
		BTPluginTransactionFail(error, @"An app-data transaction has inconsistent operation fields.");
		return nil;
	}
	_transactionIdentifier = [transactionIdentifier copy];
	_operation = operation;
	_pluginIdentifier = [pluginIdentifier copy];
	_expectedPackageSHA256 = [expectedPackageSHA256 copy];
	_targetPackageSHA256 = [targetPackageSHA256 copy];
	_previousActivationRecord = previousActivationRecord;
	_targetActivationRecord = targetActivationRecord;
	_beganAt = [beganAt copy];
	return self;
}

- (NSDictionary *)propertyListRepresentation {
	NSMutableDictionary *value = [@{
		@"schema": @1,
		@"transactionIdentifier": self.transactionIdentifier,
		@"operation": @(self.operation),
		@"pluginIdentifier": self.pluginIdentifier,
		@"beganAt": self.beganAt,
	} mutableCopy];
	if (self.expectedPackageSHA256)
		value[@"expectedPackageSHA256"] = self.expectedPackageSHA256;
	if (self.targetPackageSHA256)
		value[@"targetPackageSHA256"] = self.targetPackageSHA256;
	if (self.previousActivationRecord)
		value[@"previousActivationRecord"] = BTPluginTransactionPropertyListForRecord(self.previousActivationRecord);
	if (self.targetActivationRecord)
		value[@"targetActivationRecord"] = BTPluginTransactionPropertyListForRecord(self.targetActivationRecord);
	return value;
}

+ (instancetype)transactionWithPropertyList:(NSDictionary *)propertyList error:(NSError **)error {
	NSSet *keys = [NSSet setWithArray:@[
		@"schema", @"transactionIdentifier", @"operation", @"pluginIdentifier", @"beganAt",
		@"expectedPackageSHA256", @"targetPackageSHA256", @"previousActivationRecord", @"targetActivationRecord"
	]];
	id schema = propertyList[@"schema"];
	id operation = propertyList[@"operation"];
	if (!BTPluginTransactionDictionaryHasOnlyKeys(propertyList, keys) ||
		![schema isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)schema) == CFBooleanGetTypeID() || ![schema isEqual:@1] ||
		![propertyList[@"transactionIdentifier"] isKindOfClass:[NSString class]] ||
		![propertyList[@"pluginIdentifier"] isKindOfClass:[NSString class]] ||
		(propertyList[@"expectedPackageSHA256"] &&
			![propertyList[@"expectedPackageSHA256"] isKindOfClass:[NSString class]]) ||
		(propertyList[@"targetPackageSHA256"] &&
			![propertyList[@"targetPackageSHA256"] isKindOfClass:[NSString class]]) ||
		(propertyList[@"previousActivationRecord"] &&
			![propertyList[@"previousActivationRecord"] isKindOfClass:[NSDictionary class]]) ||
		(propertyList[@"targetActivationRecord"] &&
			![propertyList[@"targetActivationRecord"] isKindOfClass:[NSDictionary class]]) ||
		![operation isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)operation) == CFBooleanGetTypeID() ||
		[operation doubleValue] != (double)[operation unsignedLongLongValue] ||
		![propertyList[@"beganAt"] isKindOfClass:[NSDate class]]) {
		BTPluginTransactionFail(error, @"The persisted app-data transaction journal is malformed.");
		return nil;
	}
	NSError *recordError = nil;
	BTPluginActivationRecord *previous = propertyList[@"previousActivationRecord"] ?
		BTPluginTransactionRecordFromPropertyList(propertyList[@"previousActivationRecord"], &recordError) : nil;
	BTPluginActivationRecord *target = propertyList[@"targetActivationRecord"] ?
		BTPluginTransactionRecordFromPropertyList(propertyList[@"targetActivationRecord"], &recordError) : nil;
	if ((propertyList[@"previousActivationRecord"] && !previous) ||
		(propertyList[@"targetActivationRecord"] && !target)) {
		if (error)
			*error = recordError;
		return nil;
	}
	return [[self alloc] initWithTransactionIdentifier:propertyList[@"transactionIdentifier"]
		operation:(BTPluginApplicationDataTransactionOperation)[propertyList[@"operation"] unsignedIntegerValue]
		pluginIdentifier:propertyList[@"pluginIdentifier"]
		expectedPackageSHA256:propertyList[@"expectedPackageSHA256"]
		targetPackageSHA256:propertyList[@"targetPackageSHA256"]
		previousActivationRecord:previous targetActivationRecord:target beganAt:propertyList[@"beganAt"] error:error];
}

@end
