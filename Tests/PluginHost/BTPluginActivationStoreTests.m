#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "../../Battman/PluginHost/Model/BTPluginPackageErrors.h"
#import "../../Battman/PluginHost/Runtime/BTPluginActivationStore.h"
#import "../../Battman/PluginHost/Runtime/BTPluginApplicationDataTransaction.h"

#define BTAssert(condition, message) do { \
	if (!(condition)) { \
		fprintf(stderr, "Assertion failed: %s\n", (message)); \
		exit(1); \
	} \
} while (0)

static NSString *BTDigest(char character) {
	return [@"" stringByPaddingToLength:64 withString:[NSString stringWithFormat:@"%c", character]
		startingAtIndex:0];
}

static void BTCleanupService(NSString *serviceName) {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
	OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
	BTAssert(status == errSecSuccess || status == errSecItemNotFound,
		"isolated activation Keychain records could not be deleted");
}

static void BTReplaceState(NSString *serviceName, NSDictionary *state) {
	NSError *serializationError = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
	BTAssert(data != nil, serializationError.localizedDescription.UTF8String);
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: serviceName,
		(__bridge id)kSecAttrAccount: @"state",
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
		(__bridge CFDictionaryRef)@{ (__bridge id)kSecValueData: data });
	if (status == errSecItemNotFound) {
		NSMutableDictionary *addition = [query mutableCopy];
		addition[(__bridge id)kSecValueData] = data;
		addition[(__bridge id)kSecAttrAccessible] =
			(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = SecItemAdd((__bridge CFDictionaryRef)addition, NULL);
	}
	BTAssert(status == errSecSuccess, "malformed-state fixture could not be written to Keychain");
}

static BTPluginActivationRecord *BTRecord(NSString *pluginIdentifier, NSString *digest,
	BTPluginSource source, BTPluginActivationMode mode, BOOL enabled) {
	NSError *error = nil;
	BTPluginActivationRecord *record = [[BTPluginActivationRecord alloc]
		initWithPluginIdentifier:pluginIdentifier packageSHA256:digest source:source
		activationMode:mode enabled:enabled updatedAt:[NSDate dateWithTimeIntervalSince1970:100]
		error:&error];
	BTAssert(record != nil, error.localizedDescription.UTF8String);
	return record;
}

int main(void) {
	@autoreleasepool {
		NSString *serviceName = [@"com.torrekie.Battman.PluginActivation.tests."
			stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
		BTCleanupService(serviceName);
		BTPluginKeychainActivationStore *store = [[BTPluginKeychainActivationStore alloc]
			initWithServiceName:serviceName];
		NSString *thirdPartyIdentifier = @"com.example.battman.activation";
		NSString *officialIdentifier = @"com.torrekie.battman.official.activation";
		NSString *thirdPartyDigest = BTDigest('1');
		NSString *newerDigest = BTDigest('2');
		NSError *error = nil;

		BTAssert(![store thirdPartyPluginsEnabledWithError:&error] && !error,
			"third-party native plug-ins were not disabled by default");
		BTAssert([store setThirdPartyPluginsEnabled:YES error:&error], error.localizedDescription.UTF8String);
		BTAssert([store thirdPartyPluginsEnabledWithError:&error], error.localizedDescription.UTF8String);

		BTPluginActivationRecord *thirdParty = BTRecord(thirdPartyIdentifier, thirdPartyDigest,
			BTPluginSourceApplicationData, BTPluginActivationModeDirect, YES);
		BTPluginActivationRecord *official = BTRecord(officialIdentifier, BTDigest('a'),
			BTPluginSourceAppBundle, BTPluginActivationModeDirect, YES);
		BTAssert([store scheduleActivationRecord:thirdParty error:&error] &&
			[store scheduleActivationRecord:official error:&error], error.localizedDescription.UTF8String);
		NSArray<BTPluginActivationRecord *> *records = [store activationRecordsWithError:&error];
		BTAssert(records.count == 2 && [records[0].pluginIdentifier isEqualToString:thirdPartyIdentifier] &&
			[records[1].pluginIdentifier isEqualToString:officialIdentifier],
			"activation records did not persist in deterministic identifier order");

		BTPluginStartupSnapshot *first = [store beginStartupWithSafeModeRequested:NO error:&error];
		BTAssert(first != nil && !first.isSafeMode && first.areThirdPartyPluginsEnabled &&
			first.recovery == nil && first.activationRecords.count == 2,
			"normal startup snapshot was not created from persisted activation intent");
		BTAssert([store recordThirdPartyLoadAttemptForPluginIdentifier:thirdPartyIdentifier
			packageSHA256:thirdPartyDigest source:BTPluginSourceApplicationData
			startupIdentifier:first.startupIdentifier error:&error], error.localizedDescription.UTF8String);

		BTPluginStartupSnapshot *second = [store beginStartupWithSafeModeRequested:NO error:&error];
		BTAssert(second != nil && second.isSafeMode && !second.areThirdPartyPluginsEnabled &&
			[second.recovery.pluginIdentifier isEqualToString:thirdPartyIdentifier] &&
			[second.recovery.packageSHA256 isEqualToString:thirdPartyDigest],
			"an unsettled third-party load did not force the next launch into safe mode");
		BTAssert([store disablePluginFromRecovery:second.recovery error:&error], error.localizedDescription.UTF8String);
		records = [store activationRecordsWithError:&error];
		BTPluginActivationRecord *disabled = [records filteredArrayUsingPredicate:
			[NSPredicate predicateWithFormat:@"pluginIdentifier == %@", thirdPartyIdentifier]].firstObject;
		BTAssert(disabled && !disabled.isEnabled, "recovery did not disable the exact crashing build");
		BTAssert([store markStartupSettledWithIdentifier:second.startupIdentifier error:&error],
			error.localizedDescription.UTF8String);

		BTPluginStartupSnapshot *manualSafeMode = [store beginStartupWithSafeModeRequested:YES error:&error];
		BTAssert(manualSafeMode.isSafeMode && !manualSafeMode.areThirdPartyPluginsEnabled &&
			manualSafeMode.recovery == nil, "explicit safe mode was not honored independently of recovery");
		BTAssert([store markStartupSettledWithIdentifier:manualSafeMode.startupIdentifier error:&error],
			error.localizedDescription.UTF8String);

		BTPluginActivationRecord *reenabled = BTRecord(thirdPartyIdentifier, thirdPartyDigest,
			BTPluginSourceApplicationData, BTPluginActivationModeDirect, YES);
		BTAssert([store scheduleActivationRecord:reenabled error:&error], error.localizedDescription.UTF8String);
		BTPluginStartupSnapshot *third = [store beginStartupWithSafeModeRequested:NO error:&error];
		BTAssert([store recordThirdPartyLoadAttemptForPluginIdentifier:thirdPartyIdentifier
			packageSHA256:thirdPartyDigest source:BTPluginSourceApplicationData
			startupIdentifier:third.startupIdentifier error:&error], error.localizedDescription.UTF8String);
		BTPluginStartupSnapshot *fourth = [store beginStartupWithSafeModeRequested:NO error:&error];
		BTAssert(fourth.recovery != nil, "second crash-recovery fixture was not retained");
		BTPluginActivationRecord *replacement = BTRecord(thirdPartyIdentifier, newerDigest,
			BTPluginSourceApplicationData, BTPluginActivationModeDirect, YES);
		BTAssert([store scheduleActivationRecord:replacement error:&error], error.localizedDescription.UTF8String);
		error = nil;
		BTAssert(![store disablePluginFromRecovery:fourth.recovery error:&error] &&
			error.code == BTPluginPackageErrorActivationState,
			"recovery disabled a newer replacement instead of failing closed on digest mismatch");
		records = [store activationRecordsWithError:&error];
		BTPluginActivationRecord *preserved = [records filteredArrayUsingPredicate:
			[NSPredicate predicateWithFormat:@"pluginIdentifier == %@", thirdPartyIdentifier]].firstObject;
		BTAssert(preserved.isEnabled && [preserved.packageSHA256 isEqualToString:newerDigest],
			"newer activation state changed after stale recovery rejection");

		error = nil;
		BTPluginActivationRecord *requiresReinstall = BTRecord(@"com.example.battman.reinstall", BTDigest('3'),
			BTPluginSourceImport, BTPluginActivationModeRequiresReinstall, YES);
		BTAssert([store scheduleActivationRecord:requiresReinstall error:&error], error.localizedDescription.UTF8String);
		BTAssert([store setPluginIdentifier:requiresReinstall.pluginIdentifier enabled:NO error:&error],
			error.localizedDescription.UTF8String);
			BTAssert([store removePluginIdentifier:requiresReinstall.pluginIdentifier error:&error],
				error.localizedDescription.UTF8String);

			NSString *transactionPluginIdentifier = @"com.example.battman.transaction";
			BTPluginActivationRecord *transactionTarget = BTRecord(transactionPluginIdentifier, BTDigest('4'),
				BTPluginSourceApplicationData, BTPluginActivationModeDirect, YES);
			NSString *transactionIdentifier = NSUUID.UUID.UUIDString.lowercaseString;
			BTPluginApplicationDataTransaction *installTransaction = [[BTPluginApplicationDataTransaction alloc]
				initWithTransactionIdentifier:transactionIdentifier
				operation:BTPluginApplicationDataTransactionOperationInstall
				pluginIdentifier:transactionPluginIdentifier expectedPackageSHA256:nil
				targetPackageSHA256:transactionTarget.packageSHA256 previousActivationRecord:nil
				targetActivationRecord:transactionTarget beganAt:[NSDate dateWithTimeIntervalSince1970:200]
				error:&error];
			BTAssert(installTransaction != nil &&
				[store beginApplicationDataTransaction:installTransaction expectedActivationRecord:nil error:&error],
				error.localizedDescription.UTF8String);
			BTPluginKeychainActivationStore *reopened = [[BTPluginKeychainActivationStore alloc]
				initWithServiceName:serviceName];
			BTPluginApplicationDataTransaction *persisted =
				[reopened pendingApplicationDataTransactionWithError:&error];
			records = [reopened activationRecordsWithError:&error];
			BTPluginActivationRecord *persistedTarget = [records filteredArrayUsingPredicate:
				[NSPredicate predicateWithFormat:@"pluginIdentifier == %@", transactionPluginIdentifier]].firstObject;
			BTAssert([persisted.transactionIdentifier isEqualToString:transactionIdentifier] &&
				[persistedTarget.packageSHA256 isEqualToString:transactionTarget.packageSHA256],
				"transaction target and journal were not stored atomically");
			error = nil;
			BTAssert(![reopened scheduleActivationRecord:transactionTarget error:&error] &&
				error.code == BTPluginPackageErrorActivationState,
				"ordinary activation mutation was allowed while a transaction was pending");
			error = nil;
			BTAssert(![reopened setThirdPartyPluginsEnabled:NO error:&error] &&
				error.code == BTPluginPackageErrorActivationState,
				"global third-party activation policy changed while a transaction was pending");
			error = nil;
			BTAssert(![reopened beginStartupWithSafeModeRequested:NO error:&error] &&
				error.code == BTPluginPackageErrorActivationState,
				"startup snapshot was created before transaction reconciliation");
			error = nil;
			BTAssert(![reopened finishApplicationDataTransactionWithIdentifier:
				NSUUID.UUID.UUIDString.lowercaseString error:&error],
				"a stale transaction token was accepted");
			error = nil;
			BTAssert([reopened abortApplicationDataTransactionWithIdentifier:transactionIdentifier error:&error] &&
				[reopened pendingApplicationDataTransactionWithError:&error] == nil,
				error.localizedDescription.UTF8String);
			records = [reopened activationRecordsWithError:&error];
		BTAssert(([[records filteredArrayUsingPredicate:
				[NSPredicate predicateWithFormat:@"pluginIdentifier == %@", transactionPluginIdentifier]] count] == 0),
				"transaction abort did not restore the absent activation record");

			error = nil;
			BTAssert([reopened beginApplicationDataTransaction:installTransaction
				expectedActivationRecord:nil error:&error] &&
				[reopened finishApplicationDataTransactionWithIdentifier:transactionIdentifier error:&error],
				error.localizedDescription.UTF8String);
			BTPluginActivationRecord *updatedTarget = BTRecord(transactionPluginIdentifier, BTDigest('5'),
				BTPluginSourceApplicationData, BTPluginActivationModeDirect, NO);
			error = nil;
			BTPluginApplicationDataTransaction *missingExpectedUpdate =
				[[BTPluginApplicationDataTransaction alloc]
					initWithTransactionIdentifier:NSUUID.UUID.UUIDString.lowercaseString
					operation:BTPluginApplicationDataTransactionOperationUpdate
					pluginIdentifier:transactionPluginIdentifier expectedPackageSHA256:nil
					targetPackageSHA256:updatedTarget.packageSHA256 previousActivationRecord:nil
					targetActivationRecord:updatedTarget beganAt:[NSDate date] error:&error];
			BTAssert(missingExpectedUpdate == nil && error.code == BTPluginPackageErrorActivationState,
				"update transaction without an expected installed digest was accepted");
			error = nil;
			BTPluginApplicationDataTransaction *updateTransaction = [[BTPluginApplicationDataTransaction alloc]
				initWithTransactionIdentifier:NSUUID.UUID.UUIDString.lowercaseString
				operation:BTPluginApplicationDataTransactionOperationUpdate
				pluginIdentifier:transactionPluginIdentifier
				expectedPackageSHA256:transactionTarget.packageSHA256
				targetPackageSHA256:updatedTarget.packageSHA256
				previousActivationRecord:transactionTarget targetActivationRecord:updatedTarget
				beganAt:[NSDate dateWithTimeIntervalSince1970:300] error:&error];
			BTAssert(updateTransaction != nil &&
				[reopened beginApplicationDataTransaction:updateTransaction
					expectedActivationRecord:transactionTarget error:&error], error.localizedDescription.UTF8String);
			BTPluginKeychainActivationStore *reopenedAgain = [[BTPluginKeychainActivationStore alloc]
				initWithServiceName:serviceName];
			BTAssert([reopenedAgain finishApplicationDataTransactionWithIdentifier:
				updateTransaction.transactionIdentifier error:&error], error.localizedDescription.UTF8String);
			records = [reopenedAgain activationRecordsWithError:&error];
			BTPluginActivationRecord *updatedPersisted = [records filteredArrayUsingPredicate:
				[NSPredicate predicateWithFormat:@"pluginIdentifier == %@", transactionPluginIdentifier]].firstObject;
			BTAssert(!updatedPersisted.isEnabled &&
				[updatedPersisted.packageSHA256 isEqualToString:updatedTarget.packageSHA256],
				"transaction finish did not retain its exact target activation state");

			error = nil;
			NSDictionary *malformedJournal = @{
				@"schema": @1, @"transactionIdentifier": @7,
				@"operation": @1, @"pluginIdentifier": transactionPluginIdentifier,
				@"targetPackageSHA256": updatedTarget.packageSHA256,
				@"targetActivationRecord": installTransaction.targetActivationRecord ?
					installTransaction.propertyListRepresentation[@"targetActivationRecord"] : @{},
				@"beganAt": [NSDate date],
			};
			BTAssert([BTPluginApplicationDataTransaction transactionWithPropertyList:malformedJournal
				error:&error] == nil && error.code == BTPluginPackageErrorActivationState,
				"malformed transaction journal was accepted or did not fail safely");
			error = nil;
			NSMutableDictionary *fractionalRecordJournal =
				[installTransaction.propertyListRepresentation mutableCopy];
			NSMutableDictionary *fractionalTarget =
				[fractionalRecordJournal[@"targetActivationRecord"] mutableCopy];
			fractionalTarget[@"source"] = @1.5;
			fractionalRecordJournal[@"targetActivationRecord"] = fractionalTarget;
			BTAssert([BTPluginApplicationDataTransaction transactionWithPropertyList:
				fractionalRecordJournal error:&error] == nil &&
				error.code == BTPluginPackageErrorActivationState,
				"fractional transaction record enums were truncated and accepted");

			NSString *malformedRecordService = [serviceName stringByAppendingString:@".malformed-record"];
			NSDictionary *validRecord = @{
				@"pluginIdentifier": @"com.example.battman.malformed-record",
				@"packageSHA256": BTDigest('7'),
				@"source": @(BTPluginSourceApplicationData),
				@"activationMode": @(BTPluginActivationModeDirect),
				@"enabled": @YES,
				@"updatedAt": [NSDate dateWithTimeIntervalSince1970:400],
			};
			NSMutableDictionary *fractionalSourceRecord = [validRecord mutableCopy];
			fractionalSourceRecord[@"source"] = @1.5;
			BTReplaceState(malformedRecordService, @{
				@"schema": @2, @"thirdPartyEnabled": @NO,
				@"records": @[ fractionalSourceRecord ],
			});
			BTPluginKeychainActivationStore *malformedRecordStore =
				[[BTPluginKeychainActivationStore alloc] initWithServiceName:malformedRecordService];
			error = nil;
			BTAssert([malformedRecordStore activationRecordsWithError:&error] == nil &&
				error.code == BTPluginPackageErrorActivationState,
				"fractional persisted activation source was truncated and accepted");
			NSMutableDictionary *fractionalModeRecord = [validRecord mutableCopy];
			fractionalModeRecord[@"activationMode"] = @0.5;
			BTReplaceState(malformedRecordService, @{
				@"schema": @2, @"thirdPartyEnabled": @NO,
				@"records": @[ fractionalModeRecord ],
			});
			error = nil;
			BTAssert([malformedRecordStore activationRecordsWithError:&error] == nil &&
				error.code == BTPluginPackageErrorActivationState,
				"fractional persisted activation mode was truncated and accepted");
			BTCleanupService(malformedRecordService);

			BTCleanupService(serviceName);
		puts("Restart-only activation and crash-loop recovery Keychain tests passed.");
	}
	return 0;
}
