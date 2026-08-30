//
//  BTPluginExtensionDescriptor.h
//  Battman
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginExtensionDescriptor : NSObject

@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *pluginVersion;
@property (nonatomic, copy, readonly) NSString *extensionPointIdentifier;
@property (nonatomic, readonly) uint32_t extensionPointVersion;
@property (nonatomic, copy, readonly) NSString *extensionIdentifier;
@property (nonatomic, strong, readonly) id extensionObject;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier
						 pluginVersion:(NSString *)pluginVersion
				extensionPointIdentifier:(NSString *)extensionPointIdentifier
				 extensionPointVersion:(uint32_t)extensionPointVersion
					 extensionIdentifier:(NSString *)extensionIdentifier
						 extensionObject:(id)extensionObject NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
