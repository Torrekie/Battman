//
//  BTEmbeddedPluginRegistration.m
//  Battman
//

#import "BTEmbeddedPluginRegistration.h"

#import "BTPluginRegistry.h"

NSErrorDomain const BTEmbeddedPluginRegistrationErrorDomain = @"com.torrekie.battman.embedded-plugin-registration";

static BOOL BTEmbeddedSetError(NSError **error, BTEmbeddedPluginRegistrationErrorCode code, NSString *description) {
	if (error) {
		*error = [NSError errorWithDomain:BTEmbeddedPluginRegistrationErrorDomain
								 code:code
							 userInfo:@{ NSLocalizedDescriptionKey: description }];
	}
	return NO;
}

@interface BTEmbeddedRegistrationContext : NSObject
@property (nonatomic, strong) BTPluginRegistrationTransaction *transaction;
@property (nonatomic, strong, nullable) NSError *firstError;
@property (nonatomic, copy, nullable) NSString *lastErrorMessage;
@end

@implementation BTEmbeddedRegistrationContext
@end

static void BTEmbeddedWriteError(BTEmbeddedRegistrationContext *context, BTPluginErrorV1 *error, int32_t code, NSString *message) {
	context.lastErrorMessage = message;
	if (!error || error->structSize < BT_PLUGIN_ERROR_V1_MINIMUM_SIZE)
		return;
	error->abiVersion = BT_PLUGIN_ABI_VERSION_1;
	error->code = code;
	error->reserved = 0;
	error->message = context.lastErrorMessage.UTF8String;
}

static BTPluginResultV1 BTEmbeddedRegisterExtension(void *rawContext,
												 const BTPluginExtensionRegistrationV1 *registration,
												 BTPluginErrorV1 *error) {
	BTEmbeddedRegistrationContext *context = (__bridge BTEmbeddedRegistrationContext *)rawContext;
	if (!registration ||
		registration->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		registration->structSize < BT_PLUGIN_EXTENSION_REGISTRATION_V1_MINIMUM_SIZE ||
		registration->flags != 0 ||
		!registration->extensionPointIdentifier ||
		!registration->extensionIdentifier ||
		!registration->extensionObject) {
		BTEmbeddedWriteError(context, error, BTPluginResultV1InvalidArgument, @"The extension registration structure is invalid.");
		return BTPluginResultV1InvalidArgument;
	}

	NSString *extensionPointIdentifier = [NSString stringWithUTF8String:registration->extensionPointIdentifier];
	NSString *extensionIdentifier = [NSString stringWithUTF8String:registration->extensionIdentifier];
	id extensionObject = (__bridge id)registration->extensionObject;
	if (!extensionPointIdentifier || !extensionIdentifier || !extensionObject) {
		BTEmbeddedWriteError(context, error, BTPluginResultV1InvalidArgument, @"An extension identifier is not valid UTF-8.");
		return BTPluginResultV1InvalidArgument;
	}

	NSError *registrationError = nil;
	BOOL accepted = [context.transaction registerExtensionObject:extensionObject
									 extensionPointIdentifier:extensionPointIdentifier
										 extensionPointVersion:registration->extensionPointVersion
											extensionIdentifier:extensionIdentifier
													 error:&registrationError];
	if (accepted)
		return BTPluginResultV1Success;

	if (!context.firstError)
		context.firstError = registrationError;
	BTPluginResultV1 result = BTPluginResultV1InvalidExtension;
	if (registrationError.code == BTPluginRegistryErrorDuplicateExtensionIdentifier)
		result = BTPluginResultV1DuplicateIdentifier;
	else if (registrationError.code == BTPluginRegistryErrorUndeclaredExtensionPoint)
		result = BTPluginResultV1UndeclaredExtensionPoint;
	BTEmbeddedWriteError(context, error, result, registrationError.localizedDescription);
	return result;
}

static void BTEmbeddedLog(void *rawContext, BTPluginLogLevelV1 level, const char *message) {
	(void)rawContext;
	if (!message)
		return;
	NSString *logMessage = [NSString stringWithUTF8String:message];
	if (!logMessage)
		return;
	if (level == BTPluginLogLevelV1Error)
		NSLog(@"[Battman plug-in] error: %@", logMessage);
#if DEBUG
	else
		NSLog(@"[Battman plug-in] %@", logMessage);
#endif
}

BOOL BTRegisterPluginDescriptorV1(const BTPluginDescriptorV1 *descriptor,
								 BTPluginRegistry *registry,
								 NSSet<NSString *> *declaredExtensionPoints,
								 NSError **error) {
	if (!descriptor || !registry ||
		(descriptor && descriptor->structSize < BT_PLUGIN_DESCRIPTOR_V1_MINIMUM_SIZE) ||
		!descriptor->pluginIdentifier || !descriptor->pluginVersion || !descriptor->registerPlugin) {
		return BTEmbeddedSetError(error, BTEmbeddedPluginRegistrationErrorInvalidDescriptor, @"The embedded plug-in descriptor is incomplete.");
	}
	if (descriptor->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		descriptor->minimumHostABIVersion > BT_PLUGIN_ABI_VERSION_1 ||
		descriptor->maximumHostABIVersion < BT_PLUGIN_ABI_VERSION_1) {
		return BTEmbeddedSetError(error, BTEmbeddedPluginRegistrationErrorIncompatibleABI, @"The embedded plug-in ABI range is incompatible with this host.");
	}

	NSString *pluginIdentifier = [NSString stringWithUTF8String:descriptor->pluginIdentifier];
	NSString *pluginVersion = [NSString stringWithUTF8String:descriptor->pluginVersion];
	if (!pluginIdentifier || !pluginVersion)
		return BTEmbeddedSetError(error, BTEmbeddedPluginRegistrationErrorInvalidDescriptor, @"The embedded plug-in identity is not valid UTF-8.");

	NSError *transactionError = nil;
	BTPluginRegistrationTransaction *transaction = [registry beginTransactionForPluginIdentifier:pluginIdentifier
																		 pluginVersion:pluginVersion
															 declaredExtensionPoints:declaredExtensionPoints
																			 error:&transactionError];
	if (!transaction) {
		if (error)
			*error = transactionError;
		return NO;
	}

	BTEmbeddedRegistrationContext *context = [BTEmbeddedRegistrationContext new];
	context.transaction = transaction;
	BTPluginHostV1 host = {
		.structSize = sizeof(BTPluginHostV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.context = (__bridge void *)context,
		.registerExtension = BTEmbeddedRegisterExtension,
		.log = BTEmbeddedLog,
	};
	BTPluginErrorV1 callbackError = {
		.structSize = sizeof(BTPluginErrorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.code = 0,
		.reserved = 0,
		.message = NULL,
	};

	BTPluginResultV1 callbackResult = BTPluginResultV1RegistrationFailed;
	@try {
		callbackResult = descriptor->registerPlugin(&host, &callbackError);
	} @catch (NSException *exception) {
		[transaction rollback];
		return BTEmbeddedSetError(error, BTEmbeddedPluginRegistrationErrorCallbackFailed,
			[NSString stringWithFormat:@"The plug-in registration callback raised %@.", exception.name]);
	}
	if (callbackResult != BTPluginResultV1Success || context.firstError) {
		[transaction rollback];
		if (context.firstError && error) {
			*error = context.firstError;
			return NO;
		}
		return BTEmbeddedSetError(error, BTEmbeddedPluginRegistrationErrorCallbackFailed,
			@"The plug-in registration callback failed.");
	}

	NSError *commitError = nil;
	if (![transaction commit:&commitError]) {
		if (error)
			*error = commitError;
		return NO;
	}
	return YES;
}

BOOL BTRegisterEmbeddedPluginDescriptor(const BTPluginDescriptorV1 *descriptor,
											BTPluginRegistry *registry,
											NSSet<NSString *> *declaredExtensionPoints,
											NSError **error) {
	return BTRegisterPluginDescriptorV1(descriptor, registry, declaredExtensionPoints, error);
}
