//
//  BTPluginTrustStore.h
//  Battman
//
//  Persistent local approvals and rollback state. Production uses the
//  Keychain implementation; tests can supply an isolated protocol fake.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginPublisherApproval : NSObject
@property (nonatomic, copy, readonly) NSString *keyIdentifier;
@property (nonatomic, copy, readonly) NSData *publicKeyData;
@property (nonatomic, copy, readonly) NSSet<NSString *> *pluginIdentifiers;
@property (nonatomic, copy, readonly) NSSet<NSString *> *extensionPointIdentifiers;
@property (nonatomic, copy, readonly) NSDate *approvedAt;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithKeyIdentifier:(NSString *)keyIdentifier
										publicKeyData:(NSData *)publicKeyData
								 pluginIdentifiers:(NSSet<NSString *> *)pluginIdentifiers
					 extensionPointIdentifiers:(NSSet<NSString *> *)extensionPointIdentifiers
										 approvedAt:(NSDate *)approvedAt
												error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@interface BTPluginExactBuildApproval : NSObject
@property (nonatomic, copy, readonly) NSString *packageSHA256;
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *publisherKeyIdentifier;
@property (nonatomic, copy, readonly) NSDate *approvedAt;
- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithPackageSHA256:(NSString *)packageSHA256
										 pluginIdentifier:(NSString *)pluginIdentifier
								 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
												approvedAt:(NSDate *)approvedAt
													 error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;
@end

@protocol BTPluginTrustStore <NSObject>

- (nullable BTPluginPublisherApproval *)publisherApprovalForKeyIdentifier:(NSString *)keyIdentifier
																		 error:(NSError * _Nullable * _Nullable)error;
- (nullable BTPluginExactBuildApproval *)exactBuildApprovalForPackageSHA256:(NSString *)packageSHA256
																			 error:(NSError * _Nullable * _Nullable)error;
- (uint64_t)highestReleaseSequenceForPluginIdentifier:(NSString *)pluginIdentifier
									 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
															 error:(NSError * _Nullable * _Nullable)error;
- (nullable NSString *)packageSHA256ForHighestReleaseOfPluginIdentifier:(NSString *)pluginIdentifier
														 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
																			 error:(NSError * _Nullable * _Nullable)error;

- (BOOL)storePublisherApproval:(BTPluginPublisherApproval *)approval
							 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)storeExactBuildApproval:(BTPluginExactBuildApproval *)approval
								 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)recordReleaseSequence:(uint64_t)releaseSequence
					 packageSHA256:(NSString *)packageSHA256
			 forPluginIdentifier:(NSString *)pluginIdentifier
	 publisherKeyIdentifier:(NSString *)publisherKeyIdentifier
							 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removePublisherApprovalForKeyIdentifier:(NSString *)keyIdentifier
																 error:(NSError * _Nullable * _Nullable)error;
- (BOOL)removeExactBuildApprovalForPackageSHA256:(NSString *)packageSHA256
																 error:(NSError * _Nullable * _Nullable)error;

@end

@interface BTPluginKeychainTrustStore : NSObject <BTPluginTrustStore>
- (instancetype)init;
- (instancetype)initWithServiceName:(NSString *)serviceName NS_DESIGNATED_INITIALIZER;
@end

NS_ASSUME_NONNULL_END
