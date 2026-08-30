//
//  BTPluginRegistry.h
//  Battman
//
//  Generic in-process model and atomic registration store. Discovery, loading,
//  package verification, trust, and import deliberately live elsewhere.
//

#import <Foundation/Foundation.h>

#import "BTPluginExtensionDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const BTPluginRegistryErrorDomain;

typedef NS_ERROR_ENUM(BTPluginRegistryErrorDomain, BTPluginRegistryErrorCode) {
	BTPluginRegistryErrorInvalidIdentifier = 1,
	BTPluginRegistryErrorInvalidVersion = 2,
	BTPluginRegistryErrorDuplicateExtensionPoint = 3,
	BTPluginRegistryErrorUnknownExtensionPoint = 4,
	BTPluginRegistryErrorUndeclaredExtensionPoint = 5,
	BTPluginRegistryErrorIncompatibleExtensionPointVersion = 6,
	BTPluginRegistryErrorInvalidExtensionObject = 7,
	BTPluginRegistryErrorDuplicateExtensionIdentifier = 8,
	BTPluginRegistryErrorDuplicatePluginIdentifier = 9,
	BTPluginRegistryErrorTransactionClosed = 10,
	BTPluginRegistryErrorEmptyTransaction = 11,
	BTPluginRegistryErrorExtensionIdentifierOutsideNamespace = 12,
};

@class BTPluginRegistry;

@interface BTPluginRegistrationTransaction : NSObject

@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *pluginVersion;
@property (nonatomic, readonly, getter=isClosed) BOOL closed;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)registerExtensionObject:(id)extensionObject
		 extensionPointIdentifier:(NSString *)extensionPointIdentifier
			 extensionPointVersion:(uint32_t)extensionPointVersion
				extensionIdentifier:(NSString *)extensionIdentifier
						 error:(NSError * _Nullable * _Nullable)error;

- (BOOL)commit:(NSError * _Nullable * _Nullable)error;
- (void)rollback;

@end

@interface BTPluginRegistry : NSObject

- (BOOL)registerExtensionPointIdentifier:(NSString *)extensionPointIdentifier
					 interfaceVersion:(uint32_t)interfaceVersion
					  requiredProtocol:(Protocol *)requiredProtocol
							 error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginRegistrationTransaction *)beginTransactionForPluginIdentifier:(NSString *)pluginIdentifier
													 pluginVersion:(NSString *)pluginVersion
									 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
														 error:(NSError * _Nullable * _Nullable)error;

- (NSArray<BTPluginExtensionDescriptor *> *)extensionDescriptorsForExtensionPointIdentifier:(NSString *)extensionPointIdentifier;
- (NSArray *)extensionObjectsForExtensionPointIdentifier:(NSString *)extensionPointIdentifier;
- (nullable NSNumber *)interfaceVersionForExtensionPointIdentifier:(NSString *)extensionPointIdentifier;
- (nullable BTPluginExtensionDescriptor *)extensionDescriptorForExtensionPointIdentifier:(NSString *)extensionPointIdentifier
													 extensionIdentifier:(NSString *)extensionIdentifier;

@end

NS_ASSUME_NONNULL_END
