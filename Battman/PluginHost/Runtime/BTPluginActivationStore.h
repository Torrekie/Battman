//
//  BTPluginActivationStore.h
//  Battman
//
//  Persistent, restart-only activation intent and crash-loop bookkeeping.
//  This component never discovers, verifies, copies, maps, or executes code.
//

#import <Foundation/Foundation.h>

#import "../Model/BTPluginSource.h"

NS_ASSUME_NONNULL_BEGIN

@class BTPluginApplicationDataTransaction;

typedef NS_ENUM(NSUInteger, BTPluginActivationMode) {
	BTPluginActivationModeDirect = 1,
	BTPluginActivationModeRequiresReinstall = 2,
};

@interface BTPluginActivationRecord : NSObject
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *packageSHA256;
@property (nonatomic, readonly) BTPluginSource source;
@property (nonatomic, readonly) BTPluginActivationMode activationMode;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, readonly) NSDate *updatedAt;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier
									 packageSHA256:(NSString *)packageSHA256
											  source:(BTPluginSource)source
								 activationMode:(BTPluginActivationMode)activationMode
											 enabled:(BOOL)enabled
										 updatedAt:(NSDate *)updatedAt
												error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginStartupRecovery : NSObject
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *packageSHA256;
@property (nonatomic, readonly) BTPluginSource source;
@property (nonatomic, copy, readonly) NSDate *attemptedAt;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginStartupSnapshot : NSObject
@property (nonatomic, copy, readonly) NSString *startupIdentifier;
@property (nonatomic, readonly, getter=isSafeMode) BOOL safeMode;
@property (nonatomic, readonly, getter=areThirdPartyPluginsEnabled) BOOL thirdPartyPluginsEnabled;
@property (nonatomic, copy, readonly) NSArray<BTPluginActivationRecord *> *activationRecords;
@property (nonatomic, strong, readonly, nullable) BTPluginStartupRecovery *recovery;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol BTPluginActivationStore <NSObject>

- (BOOL)thirdPartyPluginsEnabledWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)setThirdPartyPluginsEnabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<BTPluginActivationRecord *> *)activationRecordsWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)scheduleActivationRecord:(BTPluginActivationRecord *)record error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setPluginIdentifier:(NSString *)pluginIdentifier enabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removePluginIdentifier:(NSString *)pluginIdentifier error:(NSError * _Nullable * _Nullable)error;

// A snapshot is immutable for this process. Mutating the store after this call
// changes only a later launch.
- (nullable BTPluginStartupSnapshot *)beginStartupWithSafeModeRequested:(BOOL)safeModeRequested
																error:(NSError * _Nullable * _Nullable)error;

// Call immediately before the one verifier-gated loader operation for a
// non-official image. This does not itself load or otherwise touch the package.
- (BOOL)recordThirdPartyLoadAttemptForPluginIdentifier:(NSString *)pluginIdentifier
												 packageSHA256:(NSString *)packageSHA256
															 source:(BTPluginSource)source
											 startupIdentifier:(NSString *)startupIdentifier
															  error:(NSError * _Nullable * _Nullable)error;
- (BOOL)markStartupSettledWithIdentifier:(NSString *)startupIdentifier
													 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)disablePluginFromRecovery:(BTPluginStartupRecovery *)recovery
									 error:(NSError * _Nullable * _Nullable)error;

@end

// App-data bytes and restart intent live in different persistence systems.
// This optional companion protocol stores a bounded redo journal in the same
// Keychain blob as the activation records, making the intent transition one
// compare-and-swap operation. Implementations that cannot provide it must not
// claim to support direct app-data installation/update/removal.
@protocol BTPluginApplicationDataTransactionStore <NSObject>
- (nullable BTPluginApplicationDataTransaction *)pendingApplicationDataTransactionWithError:
	(NSError * _Nullable * _Nullable)error;
- (BOOL)beginApplicationDataTransaction:(BTPluginApplicationDataTransaction *)transaction
	expectedActivationRecord:(BTPluginActivationRecord * _Nullable)expectedActivationRecord
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)finishApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)abortApplicationDataTransactionWithIdentifier:(NSString *)transactionIdentifier
	error:(NSError * _Nullable * _Nullable)error;
@end

@interface BTPluginKeychainActivationStore : NSObject <BTPluginActivationStore, BTPluginApplicationDataTransactionStore>
- (instancetype)init;
- (instancetype)initWithServiceName:(NSString *)serviceName NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
