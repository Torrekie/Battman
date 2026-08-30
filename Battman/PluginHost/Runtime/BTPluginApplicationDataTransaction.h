//
//  BTPluginApplicationDataTransaction.h
//  Battman
//
//  Strict, bounded redo-journal value object for app-data plug-in updates.
//  The journal is persisted together with the activation state, so a restart
//  can finish or safely abandon a filesystem operation without guessing.
//

#import <Foundation/Foundation.h>

#import "BTPluginActivationStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginApplicationDataTransactionOperation) {
	BTPluginApplicationDataTransactionOperationInstall = 1,
	BTPluginApplicationDataTransactionOperationUpdate = 2,
	BTPluginApplicationDataTransactionOperationRemove = 3,
};

@interface BTPluginApplicationDataTransaction : NSObject

@property (nonatomic, copy, readonly) NSString *transactionIdentifier;
@property (nonatomic, readonly) BTPluginApplicationDataTransactionOperation operation;
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly, nullable) NSString *expectedPackageSHA256;
@property (nonatomic, copy, readonly, nullable) NSString *targetPackageSHA256;
@property (nonatomic, strong, readonly, nullable) BTPluginActivationRecord *previousActivationRecord;
@property (nonatomic, strong, readonly, nullable) BTPluginActivationRecord *targetActivationRecord;
@property (nonatomic, copy, readonly) NSDate *beganAt;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithTransactionIdentifier:(NSString *)transactionIdentifier
	operation:(BTPluginApplicationDataTransactionOperation)operation
	pluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString * _Nullable)expectedPackageSHA256
	targetPackageSHA256:(NSString * _Nullable)targetPackageSHA256
	previousActivationRecord:(BTPluginActivationRecord * _Nullable)previousActivationRecord
	targetActivationRecord:(BTPluginActivationRecord * _Nullable)targetActivationRecord
	 beganAt:(NSDate *)beganAt
	error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

// Only the activation store may persist this representation. Parsing is
// strict: unknown keys, NSNull placeholders, and operation-inconsistent fields
// are rejected.
- (NSDictionary *)propertyListRepresentation;
+ (nullable instancetype)transactionWithPropertyList:(NSDictionary *)propertyList
	error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
