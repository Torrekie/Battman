//
//  BTPluginExtensionDescriptor.m
//  Battman
//

#import "BTPluginExtensionDescriptor.h"

@implementation BTPluginExtensionDescriptor

- (instancetype)initWithPluginIdentifier:(NSString *)pluginIdentifier
						 pluginVersion:(NSString *)pluginVersion
				extensionPointIdentifier:(NSString *)extensionPointIdentifier
				 extensionPointVersion:(uint32_t)extensionPointVersion
					 extensionIdentifier:(NSString *)extensionIdentifier
						 extensionObject:(id)extensionObject {
	self = [super init];
	if (!self)
		return nil;

	_pluginIdentifier = [pluginIdentifier copy];
	_pluginVersion = [pluginVersion copy];
	_extensionPointIdentifier = [extensionPointIdentifier copy];
	_extensionPointVersion = extensionPointVersion;
	_extensionIdentifier = [extensionIdentifier copy];
	_extensionObject = extensionObject;
	return self;
}

@end
