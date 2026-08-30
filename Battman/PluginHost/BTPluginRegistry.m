//
//  BTPluginRegistry.m
//  Battman
//

#import "BTPluginRegistry.h"

#import "BTPluginIdentifiers.h"

NSErrorDomain const BTPluginRegistryErrorDomain = @"com.torrekie.battman.plugin-registry";

static BOOL BTPluginRegistrySetError(NSError **error, BTPluginRegistryErrorCode code, NSString *description) {
	if (error) {
		*error = [NSError errorWithDomain:BTPluginRegistryErrorDomain
								 code:code
							 userInfo:@{ NSLocalizedDescriptionKey: description }];
	}
	return NO;
}

static BOOL BTPluginExtensionIdentifierBelongsToPlugin(NSString *extensionIdentifier,
	NSString *pluginIdentifier) {
	if (!BTPluginIdentifierIsValid(extensionIdentifier) || !BTPluginIdentifierIsValid(pluginIdentifier))
		return NO;
	return [extensionIdentifier hasPrefix:[pluginIdentifier stringByAppendingString:@"."]];
}

@interface BTPluginExtensionPointDefinition : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) uint32_t interfaceVersion;
@property (nonatomic) Protocol *requiredProtocol;
@end

@implementation BTPluginExtensionPointDefinition
@end

@class BTPluginRegistrationTransaction;

@interface BTPluginRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, BTPluginExtensionPointDefinition *> *extensionPoints;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<BTPluginExtensionDescriptor *> *> *descriptorsByExtensionPoint;
@property (nonatomic, strong) NSMutableSet<NSString *> *committedPluginIdentifiers;
- (nullable BTPluginExtensionPointDefinition *)definitionForIdentifier:(NSString *)identifier;
- (BOOL)commitTransaction:(BTPluginRegistrationTransaction *)transaction error:(NSError **)error;
@end

@interface BTPluginRegistrationTransaction ()
@property (nonatomic, strong) BTPluginRegistry *registry;
@property (nonatomic, copy) NSString *pluginIdentifier;
@property (nonatomic, copy) NSString *pluginVersion;
@property (nonatomic, copy) NSSet<NSString *> *declaredExtensionPoints;
@property (nonatomic, strong) NSMutableArray<BTPluginExtensionDescriptor *> *stagedDescriptors;
@property (nonatomic, getter=isClosed) BOOL closed;
- (instancetype)initWithRegistry:(BTPluginRegistry *)registry
				pluginIdentifier:(NSString *)pluginIdentifier
				   pluginVersion:(NSString *)pluginVersion
	 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints;
@end

@implementation BTPluginRegistry

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;
	_extensionPoints = [NSMutableDictionary dictionary];
	_descriptorsByExtensionPoint = [NSMutableDictionary dictionary];
	_committedPluginIdentifiers = [NSMutableSet set];
	return self;
}

- (BOOL)registerExtensionPointIdentifier:(NSString *)extensionPointIdentifier
					 interfaceVersion:(uint32_t)interfaceVersion
					  requiredProtocol:(Protocol *)requiredProtocol
							 error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(extensionPointIdentifier))
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidIdentifier, @"The extension-point identifier is invalid.");
	if (interfaceVersion == 0)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidVersion, @"The extension-point interface version must be greater than zero.");
	if (!requiredProtocol)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidExtensionObject, @"The extension point requires a public protocol.");

	@synchronized (self) {
		BTPluginExtensionPointDefinition *existing = self.extensionPoints[extensionPointIdentifier];
		if (existing) {
			if (existing.interfaceVersion == interfaceVersion && existing.requiredProtocol == requiredProtocol)
				return YES;
			return BTPluginRegistrySetError(error, BTPluginRegistryErrorDuplicateExtensionPoint, @"The extension point is already registered with a different contract.");
		}

		BTPluginExtensionPointDefinition *definition = [BTPluginExtensionPointDefinition new];
		definition.identifier = extensionPointIdentifier;
		definition.interfaceVersion = interfaceVersion;
		definition.requiredProtocol = requiredProtocol;
		self.extensionPoints[extensionPointIdentifier] = definition;
		self.descriptorsByExtensionPoint[extensionPointIdentifier] = [NSMutableArray array];
	}
	return YES;
}

- (BTPluginRegistrationTransaction *)beginTransactionForPluginIdentifier:(NSString *)pluginIdentifier
												pluginVersion:(NSString *)pluginVersion
									 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
													 error:(NSError **)error {
	if (!BTPluginIdentifierIsValid(pluginIdentifier)) {
		BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidIdentifier, @"The plug-in identifier is invalid.");
		return nil;
	}
	if (![pluginVersion isKindOfClass:[NSString class]] || pluginVersion.length == 0 || pluginVersion.length > 128) {
		BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidVersion, @"The plug-in version is invalid.");
		return nil;
	}
	if (![declaredExtensionPoints isKindOfClass:[NSSet class]] || declaredExtensionPoints.count == 0) {
		BTPluginRegistrySetError(error, BTPluginRegistryErrorUndeclaredExtensionPoint, @"The plug-in must declare at least one extension point.");
		return nil;
	}

	for (NSString *identifier in declaredExtensionPoints) {
		if (!BTPluginIdentifierIsValid(identifier)) {
			BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidIdentifier, @"A declared extension-point identifier is invalid.");
			return nil;
		}
		if (![self definitionForIdentifier:identifier]) {
			BTPluginRegistrySetError(error, BTPluginRegistryErrorUnknownExtensionPoint, @"The plug-in declares an extension point the host does not support.");
			return nil;
		}
	}

	@synchronized (self) {
		if ([self.committedPluginIdentifiers containsObject:pluginIdentifier]) {
			BTPluginRegistrySetError(error, BTPluginRegistryErrorDuplicatePluginIdentifier, @"The plug-in identifier is already committed.");
			return nil;
		}
	}

	return [[BTPluginRegistrationTransaction alloc] initWithRegistry:self
											 pluginIdentifier:pluginIdentifier
												pluginVersion:pluginVersion
									 declaredExtensionPoints:declaredExtensionPoints];
}

- (BTPluginExtensionPointDefinition *)definitionForIdentifier:(NSString *)identifier {
	@synchronized (self) {
		return self.extensionPoints[identifier];
	}
}

- (BOOL)commitTransaction:(BTPluginRegistrationTransaction *)transaction error:(NSError **)error {
	@synchronized (self) {
		if ([self.committedPluginIdentifiers containsObject:transaction.pluginIdentifier])
			return BTPluginRegistrySetError(error, BTPluginRegistryErrorDuplicatePluginIdentifier, @"The plug-in identifier was committed by another transaction.");

		for (BTPluginExtensionDescriptor *candidate in transaction.stagedDescriptors) {
			NSArray<BTPluginExtensionDescriptor *> *existingDescriptors = self.descriptorsByExtensionPoint[candidate.extensionPointIdentifier];
			for (BTPluginExtensionDescriptor *existing in existingDescriptors) {
				if ([existing.extensionIdentifier isEqualToString:candidate.extensionIdentifier])
					return BTPluginRegistrySetError(error, BTPluginRegistryErrorDuplicateExtensionIdentifier, @"An extension identifier is already registered for this extension point.");
			}
		}

		for (BTPluginExtensionDescriptor *descriptor in transaction.stagedDescriptors)
			[self.descriptorsByExtensionPoint[descriptor.extensionPointIdentifier] addObject:descriptor];
		[self.committedPluginIdentifiers addObject:transaction.pluginIdentifier];
	}
	return YES;
}

- (NSArray<BTPluginExtensionDescriptor *> *)extensionDescriptorsForExtensionPointIdentifier:(NSString *)extensionPointIdentifier {
	@synchronized (self) {
		return [self.descriptorsByExtensionPoint[extensionPointIdentifier] copy] ?: @[];
	}
}

- (NSArray *)extensionObjectsForExtensionPointIdentifier:(NSString *)extensionPointIdentifier {
	NSArray<BTPluginExtensionDescriptor *> *descriptors = [self extensionDescriptorsForExtensionPointIdentifier:extensionPointIdentifier];
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:descriptors.count];
	for (BTPluginExtensionDescriptor *descriptor in descriptors)
		[objects addObject:descriptor.extensionObject];
	return objects;
}

- (NSNumber *)interfaceVersionForExtensionPointIdentifier:(NSString *)extensionPointIdentifier {
	BTPluginExtensionPointDefinition *definition = [self definitionForIdentifier:extensionPointIdentifier];
	return definition ? @(definition.interfaceVersion) : nil;
}

- (BTPluginExtensionDescriptor *)extensionDescriptorForExtensionPointIdentifier:(NSString *)extensionPointIdentifier
												extensionIdentifier:(NSString *)extensionIdentifier {
	for (BTPluginExtensionDescriptor *descriptor in [self extensionDescriptorsForExtensionPointIdentifier:extensionPointIdentifier]) {
		if ([descriptor.extensionIdentifier isEqualToString:extensionIdentifier])
			return descriptor;
	}
	return nil;
}

@end

@implementation BTPluginRegistrationTransaction

- (instancetype)initWithRegistry:(BTPluginRegistry *)registry
				pluginIdentifier:(NSString *)pluginIdentifier
				   pluginVersion:(NSString *)pluginVersion
	 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints {
	self = [super init];
	if (!self)
		return nil;
	_registry = registry;
	_pluginIdentifier = [pluginIdentifier copy];
	_pluginVersion = [pluginVersion copy];
	_declaredExtensionPoints = [declaredExtensionPoints copy];
	_stagedDescriptors = [NSMutableArray array];
	return self;
}

- (BOOL)registerExtensionObject:(id)extensionObject
		 extensionPointIdentifier:(NSString *)extensionPointIdentifier
			 extensionPointVersion:(uint32_t)extensionPointVersion
				extensionIdentifier:(NSString *)extensionIdentifier
						 error:(NSError **)error {
	if (self.closed)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorTransactionClosed, @"The registration transaction is already closed.");
	if (!extensionObject)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidExtensionObject, @"The extension object is missing.");
	if (!BTPluginIdentifierIsValid(extensionIdentifier))
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidIdentifier, @"The extension identifier is invalid.");
	if (!BTPluginExtensionIdentifierBelongsToPlugin(extensionIdentifier, self.pluginIdentifier))
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorExtensionIdentifierOutsideNamespace,
			@"The extension identifier must be namespaced beneath the plug-in identifier.");
	if (![self.declaredExtensionPoints containsObject:extensionPointIdentifier])
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorUndeclaredExtensionPoint, @"The extension point was not declared by the plug-in.");

	BTPluginExtensionPointDefinition *definition = [self.registry definitionForIdentifier:extensionPointIdentifier];
	if (!definition)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorUnknownExtensionPoint, @"The host does not support this extension point.");
	if (definition.interfaceVersion != extensionPointVersion)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorIncompatibleExtensionPointVersion, @"The extension-point interface version is incompatible.");
	if (![extensionObject conformsToProtocol:definition.requiredProtocol])
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorInvalidExtensionObject, @"The extension object does not conform to the required public protocol.");

	for (BTPluginExtensionDescriptor *existing in self.stagedDescriptors) {
		if ([existing.extensionPointIdentifier isEqualToString:extensionPointIdentifier] &&
			[existing.extensionIdentifier isEqualToString:extensionIdentifier]) {
			return BTPluginRegistrySetError(error, BTPluginRegistryErrorDuplicateExtensionIdentifier, @"The transaction contains a duplicate extension identifier.");
		}
	}

	BTPluginExtensionDescriptor *descriptor = [[BTPluginExtensionDescriptor alloc]
		initWithPluginIdentifier:self.pluginIdentifier
		pluginVersion:self.pluginVersion
		extensionPointIdentifier:extensionPointIdentifier
		extensionPointVersion:extensionPointVersion
		extensionIdentifier:extensionIdentifier
		extensionObject:extensionObject];
	[self.stagedDescriptors addObject:descriptor];
	return YES;
}

- (BOOL)commit:(NSError **)error {
	if (self.closed)
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorTransactionClosed, @"The registration transaction is already closed.");
	if (self.stagedDescriptors.count == 0) {
		self.closed = YES;
		return BTPluginRegistrySetError(error, BTPluginRegistryErrorEmptyTransaction, @"The registration transaction contains no extensions.");
	}

	BOOL committed = [self.registry commitTransaction:self error:error];
	self.closed = YES;
	if (!committed)
		[self.stagedDescriptors removeAllObjects];
	return committed;
}

- (void)rollback {
	if (self.closed)
		return;
	[self.stagedDescriptors removeAllObjects];
	self.closed = YES;
}

@end
