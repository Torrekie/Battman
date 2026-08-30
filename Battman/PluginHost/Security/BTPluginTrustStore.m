//
//  BTPluginTrustStore.m
//  Battman
//

#import "BTPluginTrustStore.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <math.h>

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"
#import "BTPluginP256.h"

static NSString * const BTPluginDefaultTrustStoreService = @"com.torrekie.Battman.PluginTrust.v1";
static const uint64_t BTPluginTrustStoreMaximumReleaseSequence = 9007199254740991ULL;

static NSError *BTPluginTrustStoreError(NSString *description, OSStatus status) {
	NSError *underlying = status == errSecSuccess ? nil : [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
	return BTPluginPackageMakeError(BTPluginPackageErrorTrustStore, description, nil, underlying);
}

static BOOL BTPluginTrustSetIsValid(NSSet<NSString *> *values, BOOL requireNonempty) {
	if (![values isKindOfClass:[NSSet class]] || (requireNonempty && values.count == 0) || values.count > 64)
		return NO;
	for (id value in values) {
		if (![value isKindOfClass:[NSString class]] || !BTPluginIdentifierIsValid(value))
			return NO;
	}
	return YES;
}

static BOOL BTPluginTrustStoreReleaseSequence(id value, uint64_t *output) {
	if (![value isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
		return NO;
	double number = [value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < 1.0 ||
		number > (double)BTPluginTrustStoreMaximumReleaseSequence)
		return NO;
	uint64_t sequence = [value unsignedLongLongValue];
	if ((double)sequence != number)
		return NO;
	if (output)
		*output = sequence;
	return YES;
}

@interface BTPluginPublisherApproval ()
@property (nonatomic, copy, readwrite) NSString *keyIdentifier;
@property (nonatomic, copy, readwrite) NSData *publicKeyData;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *pluginIdentifiers;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *extensionPointIdentifiers;
@property (nonatomic, copy, readwrite) NSDate *approvedAt;
@end

@implementation BTPluginPublisherApproval

- (instancetype)initWithKeyIdentifier:(NSString *)keyIdentifier
								 publicKeyData:(NSData *)publicKeyData
						  pluginIdentifiers:(NSSet<NSString *> *)pluginIdentifiers
			  extensionPointIdentifiers:(NSSet<NSString *> *)extensionPointIdentifiers
									approvedAt:(NSDate *)approvedAt
										 error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (!BTPluginP256PublicKeyMatchesIdentifier(publicKeyData, keyIdentifier) ||
		!BTPluginTrustSetIsValid(pluginIdentifiers, YES) ||
		!BTPluginTrustSetIsValid(extensionPointIdentifiers, YES) || ![approvedAt isKindOfClass:[NSDate class]]) {
		if (error)
			*error = BTPluginTrustStoreError(@"A publisher approval is malformed or has an invalid scope.", errSecSuccess);
		return nil;
	}
	_keyIdentifier = [keyIdentifier copy];
	_publicKeyData = [publicKeyData copy];
	_pluginIdentifiers = [pluginIdentifiers copy];
	_extensionPointIdentifiers = [extensionPointIdentifiers copy];
	_approvedAt = [approvedAt copy];
	return self;
}

@end

@interface BTPluginExactBuildApproval ()
@property (nonatomic, copy, readwrite) NSString *packageSHA256;
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite) NSString *publisherKeyIdentifier;
@property (nonatomic, copy, readwrite) NSDate *approvedAt;
@end

@implementation BTPluginExactBuildApproval

- (instancetype)initWithPackageSHA256:(NSString *)packageSHA256
							 pluginIdentifier:(NSString *)pluginIdentifier
					 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
								approvedAt:(NSDate *)approvedAt
									 error:(NSError **)error {
	self = [super init];
	if (!self)
		return nil;
	if (!BTPluginPackageLowercaseSHA256IsValid(packageSHA256) || !BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(publisherKeyIdentifier) || ![approvedAt isKindOfClass:[NSDate class]]) {
		if (error)
			*error = BTPluginTrustStoreError(@"An exact-build approval is malformed.", errSecSuccess);
		return nil;
	}
	_packageSHA256 = [packageSHA256 copy];
	_pluginIdentifier = [pluginIdentifier copy];
	_publisherKeyIdentifier = [publisherKeyIdentifier copy];
	_approvedAt = [approvedAt copy];
	return self;
}

@end

@interface BTPluginKeychainTrustStore ()
@property (nonatomic, copy) NSString *serviceName;
@end

@implementation BTPluginKeychainTrustStore

- (instancetype)init {
	return [self initWithServiceName:BTPluginDefaultTrustStoreService];
}

- (instancetype)initWithServiceName:(NSString *)serviceName {
	self = [super init];
	if (self)
		_serviceName = serviceName.length > 0 ? [serviceName copy] : [BTPluginDefaultTrustStoreService copy];
	return self;
}

- (NSDictionary *)baseQueryForAccount:(NSString *)account {
	return @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: self.serviceName,
		(__bridge id)kSecAttrAccount: account,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
}

- (NSData *)dataForAccount:(NSString *)account notFound:(BOOL *)notFound error:(NSError **)error {
	NSMutableDictionary *query = [[self baseQueryForAccount:account] mutableCopy];
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
			*error = BTPluginTrustStoreError(@"The plug-in trust record could not be read from Keychain.", status);
		return nil;
	}
	if (notFound)
		*notFound = NO;
	return CFBridgingRelease(result);
}

- (BOOL)storeData:(NSData *)data account:(NSString *)account error:(NSError **)error {
	NSDictionary *query = [self baseQueryForAccount:account];
	NSDictionary *update = @{ (__bridge id)kSecValueData: data };
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
	if (status == errSecItemNotFound) {
		NSMutableDictionary *addition = [query mutableCopy];
		addition[(__bridge id)kSecValueData] = data;
		addition[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = SecItemAdd((__bridge CFDictionaryRef)addition, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = BTPluginTrustStoreError(@"The plug-in trust record could not be stored in Keychain.", status);
	return NO;
}

- (NSDictionary *)propertyListForAccount:(NSString *)account notFound:(BOOL *)notFound error:(NSError **)error {
	NSData *data = [self dataForAccount:account notFound:notFound error:error];
	if (!data)
		return nil;
	NSError *propertyListError = nil;
	id propertyList = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&propertyListError];
	if (![propertyList isKindOfClass:[NSDictionary class]]) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"A Keychain plug-in trust record is malformed.", nil, propertyListError);
		return nil;
	}
	return propertyList;
}

- (BOOL)storePropertyList:(NSDictionary *)propertyList account:(NSString *)account error:(NSError **)error {
	NSError *serializationError = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:propertyList
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
	if (!data) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"A plug-in trust record could not be serialized.", nil, serializationError);
		return NO;
	}
	return [self storeData:data account:account error:error];
}

- (BTPluginPublisherApproval *)publisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The publisher approval key identifier is invalid.", errSecSuccess);
		return nil;
	}
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *record = [self propertyListForAccount:[@"publisher:" stringByAppendingString:keyIdentifier]
			notFound:&notFound error:error];
		if (notFound || !record)
			return nil;
		if (![record[@"schema"] isEqual:@1] || ![record[@"type"] isEqual:@"publisher"] ||
			![record[@"keyIdentifier"] isEqual:keyIdentifier] || ![record[@"pluginIdentifiers"] isKindOfClass:[NSArray class]] ||
			![record[@"extensionPointIdentifiers"] isKindOfClass:[NSArray class]]) {
			if (error)
				*error = BTPluginTrustStoreError(@"A publisher approval Keychain record is malformed.", errSecSuccess);
			return nil;
		}
		return [[BTPluginPublisherApproval alloc]
			initWithKeyIdentifier:keyIdentifier
			publicKeyData:record[@"publicKeyData"]
			pluginIdentifiers:[NSSet setWithArray:record[@"pluginIdentifiers"]]
			extensionPointIdentifiers:[NSSet setWithArray:record[@"extensionPointIdentifiers"]]
			approvedAt:record[@"approvedAt"] error:error];
	}
}

- (BTPluginExactBuildApproval *)exactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	if (!BTPluginPackageLowercaseSHA256IsValid(packageSHA256)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The exact-build digest is invalid.", errSecSuccess);
		return nil;
	}
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *record = [self propertyListForAccount:[@"build:" stringByAppendingString:packageSHA256]
			notFound:&notFound error:error];
		if (notFound || !record)
			return nil;
		if (![record[@"schema"] isEqual:@1] || ![record[@"type"] isEqual:@"build"] ||
			![record[@"packageSHA256"] isEqual:packageSHA256]) {
			if (error)
				*error = BTPluginTrustStoreError(@"An exact-build Keychain record is malformed.", errSecSuccess);
			return nil;
		}
		return [[BTPluginExactBuildApproval alloc]
			initWithPackageSHA256:packageSHA256
			pluginIdentifier:record[@"pluginIdentifier"]
			publisherKeyIdentifier:record[@"publisherKeyIdentifier"]
			approvedAt:record[@"approvedAt"] error:error];
	}
}

- (uint64_t)highestReleaseSequenceForPluginIdentifier:(NSString *)pluginIdentifier
							 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
												  error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier) || !BTPluginPackageLowercaseSHA256IsValid(publisherKeyIdentifier)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The rollback-state identity is invalid.", errSecSuccess);
		return 0;
	}
	NSString *account = [NSString stringWithFormat:@"rollback:%@:%@", publisherKeyIdentifier, pluginIdentifier];
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *record = [self propertyListForAccount:account notFound:&notFound error:error];
		if (notFound)
			return 0;
		id sequence = record[@"highestReleaseSequence"];
		uint64_t parsedSequence = 0;
		if (!record || ![record[@"schema"] isEqual:@1] || ![record[@"type"] isEqual:@"rollback"] ||
			![record[@"pluginIdentifier"] isEqual:pluginIdentifier] ||
			![record[@"publisherKeyIdentifier"] isEqual:publisherKeyIdentifier] ||
			!BTPluginPackageLowercaseSHA256IsValid(record[@"highestPackageSHA256"]) ||
			!BTPluginTrustStoreReleaseSequence(sequence, &parsedSequence)) {
			if (error)
				*error = BTPluginTrustStoreError(@"A rollback Keychain record is malformed.", errSecSuccess);
			return 0;
		}
		return parsedSequence;
	}
}

- (NSString *)packageSHA256ForHighestReleaseOfPluginIdentifier:(NSString *)pluginIdentifier
											 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
															  error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier) || !BTPluginPackageLowercaseSHA256IsValid(publisherKeyIdentifier)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The rollback-state identity is invalid.", errSecSuccess);
		return nil;
	}
	NSString *account = [NSString stringWithFormat:@"rollback:%@:%@", publisherKeyIdentifier, pluginIdentifier];
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *record = [self propertyListForAccount:account notFound:&notFound error:error];
		if (notFound)
			return nil;
		id sequence = record[@"highestReleaseSequence"];
		NSString *digest = record[@"highestPackageSHA256"];
		if (!record || ![record[@"schema"] isEqual:@1] || ![record[@"type"] isEqual:@"rollback"] ||
			![record[@"pluginIdentifier"] isEqual:pluginIdentifier] ||
			![record[@"publisherKeyIdentifier"] isEqual:publisherKeyIdentifier] ||
			!BTPluginTrustStoreReleaseSequence(sequence, NULL) || !BTPluginPackageLowercaseSHA256IsValid(digest)) {
			if (error)
				*error = BTPluginTrustStoreError(@"A rollback Keychain record is malformed.", errSecSuccess);
			return nil;
		}
		return digest;
	}
}

- (BOOL)storePublisherApproval:(BTPluginPublisherApproval *)approval error:(NSError **)error {
	if (![approval isKindOfClass:[BTPluginPublisherApproval class]]) {
		if (error)
			*error = BTPluginTrustStoreError(@"The publisher approval object is invalid.", errSecSuccess);
		return NO;
	}
	NSArray *plugins = [[approval.pluginIdentifiers allObjects] sortedArrayUsingSelector:@selector(compare:)];
	NSArray *extensionPoints = [[approval.extensionPointIdentifiers allObjects] sortedArrayUsingSelector:@selector(compare:)];
	NSDictionary *record = @{
		@"schema": @1,
		@"type": @"publisher",
		@"keyIdentifier": approval.keyIdentifier,
		@"publicKeyData": approval.publicKeyData,
		@"pluginIdentifiers": plugins,
		@"extensionPointIdentifiers": extensionPoints,
		@"approvedAt": approval.approvedAt,
	};
	@synchronized ([BTPluginKeychainTrustStore class]) {
		return [self storePropertyList:record account:[@"publisher:" stringByAppendingString:approval.keyIdentifier] error:error];
	}
}

- (BOOL)storeExactBuildApproval:(BTPluginExactBuildApproval *)approval error:(NSError **)error {
	if (![approval isKindOfClass:[BTPluginExactBuildApproval class]]) {
		if (error)
			*error = BTPluginTrustStoreError(@"The exact-build approval object is invalid.", errSecSuccess);
		return NO;
	}
	NSDictionary *record = @{
		@"schema": @1,
		@"type": @"build",
		@"packageSHA256": approval.packageSHA256,
		@"pluginIdentifier": approval.pluginIdentifier,
		@"publisherKeyIdentifier": approval.publisherKeyIdentifier,
		@"approvedAt": approval.approvedAt,
	};
	@synchronized ([BTPluginKeychainTrustStore class]) {
		return [self storePropertyList:record account:[@"build:" stringByAppendingString:approval.packageSHA256] error:error];
	}
}

- (BOOL)recordReleaseSequence:(uint64_t)releaseSequence
					 packageSHA256:(NSString *)packageSHA256
			 forPluginIdentifier:(NSString *)pluginIdentifier
	 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
							 error:(NSError **)error {
	if (releaseSequence == 0 || releaseSequence > BTPluginTrustStoreMaximumReleaseSequence ||
		!BTPluginPackageLowercaseSHA256IsValid(packageSHA256) || !BTPluginIdentifierIsValid(pluginIdentifier) ||
		!BTPluginPackageLowercaseSHA256IsValid(publisherKeyIdentifier)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The rollback update is invalid.", errSecSuccess);
		return NO;
	}
	@synchronized ([BTPluginKeychainTrustStore class]) {
		NSError *readError = nil;
		uint64_t current = [self highestReleaseSequenceForPluginIdentifier:pluginIdentifier
			publisherKeyIdentifier:publisherKeyIdentifier error:&readError];
		if (readError) {
			if (error)
				*error = readError;
			return NO;
		}
		if (current >= releaseSequence) {
			NSString *currentDigest = [self packageSHA256ForHighestReleaseOfPluginIdentifier:pluginIdentifier
				publisherKeyIdentifier:publisherKeyIdentifier error:error];
			if (!currentDigest)
				return NO;
			if (current == releaseSequence && [currentDigest isEqualToString:packageSHA256])
				return YES;
			if (error)
				*error = BTPluginPackageMakeError(BTPluginPackageErrorRollback,
					@"A lower or conflicting plug-in release cannot replace the recorded release state.", nil, nil);
			return NO;
		}
		NSDictionary *record = @{
			@"schema": @1,
			@"type": @"rollback",
			@"pluginIdentifier": pluginIdentifier,
			@"publisherKeyIdentifier": publisherKeyIdentifier,
			@"highestReleaseSequence": @(releaseSequence),
			@"highestPackageSHA256": packageSHA256,
		};
		NSString *account = [NSString stringWithFormat:@"rollback:%@:%@", publisherKeyIdentifier, pluginIdentifier];
		return [self storePropertyList:record account:account error:error];
	}
}

- (BOOL)removeAccount:(NSString *)account error:(NSError **)error {
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self baseQueryForAccount:account]);
	if (status == errSecSuccess || status == errSecItemNotFound)
		return YES;
	if (error)
		*error = BTPluginTrustStoreError(@"The plug-in trust record could not be removed from Keychain.", status);
	return NO;
}

- (BOOL)removePublisherApprovalForKeyIdentifier:(NSString *)keyIdentifier error:(NSError **)error {
	if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The publisher approval key identifier is invalid.", errSecSuccess);
		return NO;
	}
	@synchronized ([BTPluginKeychainTrustStore class]) {
		return [self removeAccount:[@"publisher:" stringByAppendingString:keyIdentifier] error:error];
	}
}

- (BOOL)removeExactBuildApprovalForPackageSHA256:(NSString *)packageSHA256 error:(NSError **)error {
	if (!BTPluginPackageLowercaseSHA256IsValid(packageSHA256)) {
		if (error)
			*error = BTPluginTrustStoreError(@"The exact-build digest is invalid.", errSecSuccess);
		return NO;
	}
	@synchronized ([BTPluginKeychainTrustStore class]) {
		return [self removeAccount:[@"build:" stringByAppendingString:packageSHA256] error:error];
	}
}

@end
