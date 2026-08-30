#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <dispatch/dispatch.h>
#import <math.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Security/BTPluginP256.h"
#import "../../Battman/PluginHost/Security/BTPluginTrustStore.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static NSData *BTCreatePublicKey(void) {
	NSDictionary *attributes = @{
		(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
		(__bridge id)kSecAttrKeySizeInBits: @256,
	};
	CFErrorRef createError = NULL;
	SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &createError);
	if (!privateKey) {
		NSError *underlying = CFBridgingRelease(createError);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
	CFRelease(privateKey);
	CFErrorRef exportError = NULL;
	CFDataRef bytes = SecKeyCopyExternalRepresentation(publicKey, &exportError);
	CFRelease(publicKey);
	if (!bytes) {
		NSError *underlying = CFBridgingRelease(exportError);
		BTAssert(NO, underlying.localizedDescription.UTF8String);
	}
	return CFBridgingRelease(bytes);
}

static void BTCleanupService(NSString *serviceName) {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
	BTAssert(status == errSecSuccess || status == errSecItemNotFound,
		"isolated Keychain test records could not be deleted");
}

static NSString *BTRollbackAccount(NSString *pluginIdentifier, NSString *publisherKeyIdentifier) {
	return [NSString stringWithFormat:@"rollback:%@:%@", publisherKeyIdentifier, pluginIdentifier];
}

static void BTStoreRawRollbackRecord(NSString *serviceName,
	NSString *pluginIdentifier,
	NSString *publisherKeyIdentifier,
	id releaseSequence,
	NSString *packageDigest) {
	NSDictionary *record = @{
		@"schema": @1,
		@"type": @"rollback",
		@"pluginIdentifier": pluginIdentifier,
		@"publisherKeyIdentifier": publisherKeyIdentifier,
		@"highestReleaseSequence": releaseSequence,
		@"highestPackageSHA256": packageDigest,
	};
	NSError *serializationError = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:record
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
	BTAssert(data != nil, serializationError.localizedDescription.UTF8String);
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrAccount: BTRollbackAccount(pluginIdentifier, publisherKeyIdentifier),
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
	BTAssert(status == errSecSuccess || status == errSecItemNotFound,
		"raw rollback fixture could not replace its Keychain record");
	NSMutableDictionary *addition = [query mutableCopy];
	addition[(__bridge id)kSecValueData] = data;
	addition[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
	status = SecItemAdd((__bridge CFDictionaryRef)addition, NULL);
	BTAssert(status == errSecSuccess, "raw rollback fixture could not be stored in Keychain");
}

@interface BTPluginKeychainTrustStore (BTPluginKeychainTrustStoreTests)
- (BOOL)storePropertyList:(NSDictionary *)propertyList account:(NSString *)account error:(NSError **)error;
@end

@interface BTBlockingKeychainTrustStore : BTPluginKeychainTrustStore {
	dispatch_semaphore_t _rollbackWriteReached;
	dispatch_semaphore_t _continueRollbackWrite;
	BOOL _blockNextRollbackWrite;
}
- (void)blockNextRollbackWrite;
- (BOOL)waitForBlockedRollbackWrite;
- (void)continueBlockedRollbackWrite;
@end

@implementation BTBlockingKeychainTrustStore

- (instancetype)initWithServiceName:(NSString *)serviceName {
	self = [super initWithServiceName:serviceName];
	if (self) {
		_rollbackWriteReached = dispatch_semaphore_create(0);
		_continueRollbackWrite = dispatch_semaphore_create(0);
	}
	return self;
}

- (void)blockNextRollbackWrite {
	_blockNextRollbackWrite = YES;
}

- (BOOL)waitForBlockedRollbackWrite {
	return dispatch_semaphore_wait(_rollbackWriteReached,
		dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
}

- (void)continueBlockedRollbackWrite {
	dispatch_semaphore_signal(_continueRollbackWrite);
}

- (BOOL)storePropertyList:(NSDictionary *)propertyList account:(NSString *)account error:(NSError **)error {
	if (_blockNextRollbackWrite && [account hasPrefix:@"rollback:"]) {
		_blockNextRollbackWrite = NO;
		dispatch_semaphore_signal(_rollbackWriteReached);
		dispatch_semaphore_wait(_continueRollbackWrite, DISPATCH_TIME_FOREVER);
	}
	return [super storePropertyList:propertyList account:account error:error];
}

@end

int main(void) {
	@autoreleasepool {
		NSString *serviceName = [@"com.torrekie.Battman.PluginTrust.tests."
			stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
		BTCleanupService(serviceName);
		BTPluginKeychainTrustStore *store = [[BTPluginKeychainTrustStore alloc]
			initWithServiceName:serviceName];
		NSData *publicKeyData = BTCreatePublicKey();
		NSString *keyIdentifier = BTPluginP256KeyIdentifier(publicKeyData);
		NSMutableData *invalidCurvePoint = [NSMutableData dataWithLength:65];
		memset(invalidCurvePoint.mutableBytes, 0xff, invalidCurvePoint.length);
		((uint8_t *)invalidCurvePoint.mutableBytes)[0] = 0x04;
		NSString *invalidKeyIdentifier = BTPluginP256KeyIdentifier(invalidCurvePoint);
		NSString *pluginIdentifier = @"com.example.battman.keychain";
		NSString *extensionPointIdentifier = @"com.torrekie.battman.analytics.card.v1";
		NSString *packageDigest = [@"1" stringByPaddingToLength:64 withString:@"1" startingAtIndex:0];
		NSString *conflictingDigest = [@"2" stringByPaddingToLength:64 withString:@"2" startingAtIndex:0];
		NSError *error = nil;
		BTAssert([[BTPluginPublisherApproval alloc]
			initWithKeyIdentifier:invalidKeyIdentifier
			publicKeyData:invalidCurvePoint
			pluginIdentifiers:[NSSet setWithObject:pluginIdentifier]
			extensionPointIdentifiers:[NSSet setWithObject:extensionPointIdentifier]
			approvedAt:[NSDate date]
			error:&error] == nil, "an invalid P-256 curve point was accepted");
		error = nil;

		BTPluginPublisherApproval *publisher = [[BTPluginPublisherApproval alloc]
			initWithKeyIdentifier:keyIdentifier
			publicKeyData:publicKeyData
			pluginIdentifiers:[NSSet setWithObject:pluginIdentifier]
			extensionPointIdentifiers:[NSSet setWithObject:extensionPointIdentifier]
			approvedAt:[NSDate dateWithTimeIntervalSince1970:123]
			error:&error];
		BTAssert(publisher != nil && [store storePublisherApproval:publisher error:&error],
			error.localizedDescription.UTF8String);
		BTPluginPublisherApproval *storedPublisher = [store publisherApprovalForKeyIdentifier:keyIdentifier error:&error];
		BTAssert(storedPublisher != nil && [storedPublisher.publicKeyData isEqualToData:publicKeyData] &&
			[storedPublisher.pluginIdentifiers containsObject:pluginIdentifier] &&
			[storedPublisher.extensionPointIdentifiers containsObject:extensionPointIdentifier],
			"publisher approval did not round-trip through Keychain");

		BTPluginExactBuildApproval *build = [[BTPluginExactBuildApproval alloc]
			initWithPackageSHA256:packageDigest
			pluginIdentifier:pluginIdentifier
			publisherKeyIdentifier:keyIdentifier
			approvedAt:[NSDate dateWithTimeIntervalSince1970:456]
			error:&error];
		BTAssert(build != nil && [store storeExactBuildApproval:build error:&error],
			error.localizedDescription.UTF8String);
		BTPluginExactBuildApproval *storedBuild = [store exactBuildApprovalForPackageSHA256:packageDigest error:&error];
		BTAssert(storedBuild != nil && [storedBuild.pluginIdentifier isEqualToString:pluginIdentifier] &&
			[storedBuild.publisherKeyIdentifier isEqualToString:keyIdentifier],
			"exact-build approval did not round-trip through Keychain");

		BTAssert([store recordReleaseSequence:7 packageSHA256:packageDigest
			forPluginIdentifier:pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error],
			error.localizedDescription.UTF8String);
		BTAssert([store highestReleaseSequenceForPluginIdentifier:pluginIdentifier
			publisherKeyIdentifier:keyIdentifier error:&error] == 7,
			"rollback sequence did not round-trip through Keychain");
		BTAssert([[store packageSHA256ForHighestReleaseOfPluginIdentifier:pluginIdentifier
			publisherKeyIdentifier:keyIdentifier error:&error] isEqualToString:packageDigest],
			"rollback digest did not round-trip through Keychain");
		BTAssert([store recordReleaseSequence:7 packageSHA256:packageDigest
			forPluginIdentifier:pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error],
			"idempotent rollback update failed");
		error = nil;
		BTAssert(![store recordReleaseSequence:6 packageSHA256:packageDigest
			forPluginIdentifier:pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error] &&
			error.code == BTPluginPackageErrorRollback, "lower release sequence was accepted");
		error = nil;
		BTAssert(![store recordReleaseSequence:7 packageSHA256:conflictingDigest
			forPluginIdentifier:pluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error] &&
			error.code == BTPluginPackageErrorRollback, "same-sequence equivocation was accepted");

		NSString *malformedPluginIdentifier = @"com.example.battman.keychain.malformed";
		NSArray<NSNumber *> *malformedSequences = @[
			@YES,
			@0,
			@1.5,
			@-1,
			[NSNumber numberWithDouble:NAN],
			[NSNumber numberWithDouble:INFINITY],
			@9007199254740992ULL,
		];
		for (NSNumber *malformedSequence in malformedSequences) {
			BTStoreRawRollbackRecord(serviceName, malformedPluginIdentifier, keyIdentifier,
				malformedSequence, packageDigest);
			error = nil;
			BTAssert([store highestReleaseSequenceForPluginIdentifier:malformedPluginIdentifier
				publisherKeyIdentifier:keyIdentifier error:&error] == 0 &&
				error.code == BTPluginPackageErrorTrustStore,
				"a malformed raw Keychain release sequence was accepted");
			error = nil;
			BTAssert([store packageSHA256ForHighestReleaseOfPluginIdentifier:malformedPluginIdentifier
				publisherKeyIdentifier:keyIdentifier error:&error] == nil &&
				error.code == BTPluginPackageErrorTrustStore,
				"a digest was returned for a malformed raw Keychain release sequence");
		}
		error = nil;
		BTAssert(![store recordReleaseSequence:9007199254740992ULL packageSHA256:packageDigest
			forPluginIdentifier:malformedPluginIdentifier publisherKeyIdentifier:keyIdentifier error:&error] &&
			error.code == BTPluginPackageErrorTrustStore,
			"an out-of-range release sequence was persisted through the public API");

		NSString *concurrentPluginIdentifier = @"com.example.battman.keychain.concurrent";
		BTBlockingKeychainTrustStore *lowerStore = [[BTBlockingKeychainTrustStore alloc]
			initWithServiceName:serviceName];
		BTPluginKeychainTrustStore *higherStore = [[BTPluginKeychainTrustStore alloc]
			initWithServiceName:serviceName];
		[lowerStore blockNextRollbackWrite];
		dispatch_queue_t queue = dispatch_queue_create("com.torrekie.Battman.PluginTrust.tests", DISPATCH_QUEUE_CONCURRENT);
		dispatch_group_t group = dispatch_group_create();
		dispatch_semaphore_t higherAttemptStarted = dispatch_semaphore_create(0);
		dispatch_semaphore_t higherAttemptFinished = dispatch_semaphore_create(0);
		__block BOOL lowerStored = NO;
		__block BOOL higherStored = NO;
		dispatch_group_async(group, queue, ^{
			NSError *writeError = nil;
			lowerStored = [lowerStore recordReleaseSequence:9 packageSHA256:packageDigest
				forPluginIdentifier:concurrentPluginIdentifier publisherKeyIdentifier:keyIdentifier error:&writeError];
		});
		BTAssert([lowerStore waitForBlockedRollbackWrite],
			"the deterministic lower-sequence write did not reach its test barrier");
		dispatch_group_async(group, queue, ^{
			dispatch_semaphore_signal(higherAttemptStarted);
			NSError *writeError = nil;
			higherStored = [higherStore recordReleaseSequence:10 packageSHA256:conflictingDigest
				forPluginIdentifier:concurrentPluginIdentifier publisherKeyIdentifier:keyIdentifier error:&writeError];
			dispatch_semaphore_signal(higherAttemptFinished);
		});
		BTAssert(dispatch_semaphore_wait(higherAttemptStarted,
			dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
			"the concurrent higher-sequence write did not start");
		BTAssert(dispatch_semaphore_wait(higherAttemptFinished,
			dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0,
			"a second trust-store instance bypassed the class-wide mutation lock");
		[lowerStore continueBlockedRollbackWrite];
		BTAssert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
			"the deterministic multi-instance rollback updates did not finish");
		BTAssert(lowerStored && higherStored, "serialized multi-instance rollback updates failed");
		error = nil;
		BTAssert([store highestReleaseSequenceForPluginIdentifier:concurrentPluginIdentifier
			publisherKeyIdentifier:keyIdentifier error:&error] == 10 && !error,
			"a lower concurrent update regressed the shared rollback sequence");
		BTAssert([[store packageSHA256ForHighestReleaseOfPluginIdentifier:concurrentPluginIdentifier
			publisherKeyIdentifier:keyIdentifier error:&error] isEqualToString:conflictingDigest],
			"the shared rollback digest does not match the highest concurrent sequence");

		error = nil;
		BTAssert([store removePublisherApprovalForKeyIdentifier:keyIdentifier error:&error] &&
			[store publisherApprovalForKeyIdentifier:keyIdentifier error:&error] == nil && !error,
			"publisher approval removal failed");
		BTAssert([store removeExactBuildApprovalForPackageSHA256:packageDigest error:&error] &&
			[store exactBuildApprovalForPackageSHA256:packageDigest error:&error] == nil && !error,
			"exact-build approval removal failed");
		BTCleanupService(serviceName);
		printf("Isolated Keychain approval and rollback persistence tests passed.\n");
	}
	return 0;
}
