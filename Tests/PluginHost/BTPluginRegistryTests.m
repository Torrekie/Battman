#import <Foundation/Foundation.h>

#include "../../PluginSDK/include/BattmanPluginABI.h"
#import "../../Battman/PluginHost/BTEmbeddedPluginRegistration.h"
#import "../../Battman/PluginHost/BTPluginIdentifiers.h"
#import "../../Battman/PluginHost/BTPluginRegistry.h"

static NSString *const BTTestExtensionPoint = @"com.torrekie.battman.tests.extension.v1";
static NSString *const BTTestOtherExtensionPoint = @"com.torrekie.battman.tests.other.v1";

static void BTTestRequire(BOOL condition, NSString *message) {
	if (condition)
		return;
	fprintf(stderr, "FAIL: %s\n", message.UTF8String);
	abort();
}

@protocol BTTestExtension <NSObject>
@property (nonatomic, copy, readonly) NSString *testIdentifier;
@end

@interface BTTestExtensionObject : NSObject <BTTestExtension>
@property (nonatomic, copy) NSString *testIdentifier;
@end

@implementation BTTestExtensionObject
@end

static BTPluginResultV1 BTTestRegisterObjectWithVersionAndFlags(const BTPluginHostV1 *host,
														 NSString *extensionPoint,
														 NSString *identifier,
														 id object,
														 uint32_t version,
														 uint32_t flags,
														 BTPluginErrorV1 *error) {
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = sizeof(BTPluginExtensionRegistrationV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = extensionPoint.UTF8String,
		.extensionPointVersion = version,
		.flags = flags,
		.extensionIdentifier = identifier.UTF8String,
		.extensionObject = (__bridge const void *)object,
	};
	return host->registerExtension(host->context, &registration, error);
}

static BTPluginResultV1 BTTestRegisterObject(const BTPluginHostV1 *host,
											 NSString *extensionPoint,
											 NSString *identifier,
											 id object,
											 BTPluginErrorV1 *error) {
	return BTTestRegisterObjectWithVersionAndFlags(host, extensionPoint, identifier, object, 1, 0, error);
}

static BTPluginResultV1 BTGoodPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"good";
	return BTTestRegisterObject(host, BTTestExtensionPoint, @"com.example.good.card", object, error);
}

static BTPluginResultV1 BTFailingPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *stagedObject = [BTTestExtensionObject new];
	stagedObject.testIdentifier = @"staged";
	BTPluginResultV1 result = BTTestRegisterObject(host, BTTestExtensionPoint, @"com.example.failing.staged", stagedObject, error);
	if (result != BTPluginResultV1Success)
		return result;
	return BTTestRegisterObject(host, BTTestExtensionPoint, @"com.example.failing.invalid", [NSObject new], error);
}

static BTPluginResultV1 BTUndeclaredPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"undeclared";
	return BTTestRegisterObject(host, BTTestOtherExtensionPoint, @"com.example.undeclared.card", object, error);
}

static BTPluginResultV1 BTBadVersionPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"bad-version";
	return BTTestRegisterObjectWithVersionAndFlags(host, BTTestExtensionPoint, @"com.example.bad-version.card", object, 2, 0, error);
}

static BTPluginResultV1 BTReservedFlagsPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"reserved-flags";
	return BTTestRegisterObjectWithVersionAndFlags(host, BTTestExtensionPoint, @"com.example.reserved-flags.card", object, 1, 1, error);
}

static BTPluginResultV1 BTDuplicateCommittedExtensionRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"duplicate";
	return BTTestRegisterObject(host, BTTestExtensionPoint, @"com.example.good.card", object, error);
}

typedef struct BTTestExtendedRegistrationV1 {
	BTPluginExtensionRegistrationV1 v1;
	uint64_t futureTail;
} BTTestExtendedRegistrationV1;

static BTPluginResultV1 BTAppendedTailPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"appended-tail";
	BTTestExtendedRegistrationV1 registration = {
		.v1 = {
			.structSize = sizeof(BTTestExtendedRegistrationV1),
			.abiVersion = BT_PLUGIN_ABI_VERSION_1,
			.extensionPointIdentifier = BTTestExtensionPoint.UTF8String,
			.extensionPointVersion = 1,
			.flags = 0,
			.extensionIdentifier = "com.example.appended-tail.card",
			.extensionObject = (__bridge const void *)object,
		},
		.futureTail = UINT64_C(0xa55aa55aa55aa55a),
	};
	return host->registerExtension(host->context, &registration.v1, error);
}

static BTPluginResultV1 BTTruncatedRegistrationPluginRegister(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	BTTestExtensionObject *object = [BTTestExtensionObject new];
	object.testIdentifier = @"truncated";
	BTPluginExtensionRegistrationV1 registration = {
		.structSize = BT_PLUGIN_EXTENSION_REGISTRATION_V1_MINIMUM_SIZE - 1,
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.extensionPointIdentifier = BTTestExtensionPoint.UTF8String,
		.extensionPointVersion = 1,
		.flags = 0,
		.extensionIdentifier = "com.example.truncated-registration.card",
		.extensionObject = (__bridge const void *)object,
	};
	return host->registerExtension(host->context, &registration, error);
}

static const BTPluginDescriptorV1 BTGoodPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.good",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTGoodPluginRegister,
};

static const BTPluginDescriptorV1 BTFailingPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.failing",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTFailingPluginRegister,
};

static const BTPluginDescriptorV1 BTUndeclaredPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.undeclared",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTUndeclaredPluginRegister,
};

static const BTPluginDescriptorV1 BTBadVersionPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.bad-version",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTBadVersionPluginRegister,
};

static const BTPluginDescriptorV1 BTReservedFlagsPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.reserved-flags",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTReservedFlagsPluginRegister,
};

static const BTPluginDescriptorV1 BTDuplicateCommittedExtensionPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTDuplicateCommittedExtensionRegister,
};

typedef struct BTTestExtendedDescriptorV1 {
	BTPluginDescriptorV1 v1;
	uint64_t futureTail;
} BTTestExtendedDescriptorV1;

static const BTTestExtendedDescriptorV1 BTAppendedTailPlugin = {
	.v1 = {
		.structSize = sizeof(BTTestExtendedDescriptorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.pluginIdentifier = "com.example.appended-tail",
		.pluginVersion = "1.0.0",
		.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.registerPlugin = BTAppendedTailPluginRegister,
	},
	.futureTail = UINT64_C(0x5aa55aa55aa55aa5),
};

static const BTPluginDescriptorV1 BTTruncatedDescriptorPlugin = {
	.structSize = BT_PLUGIN_DESCRIPTOR_V1_MINIMUM_SIZE - 1,
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.truncated-descriptor",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTGoodPluginRegister,
};

static const BTPluginDescriptorV1 BTTruncatedRegistrationPlugin = {
	.structSize = sizeof(BTPluginDescriptorV1),
	.abiVersion = BT_PLUGIN_ABI_VERSION_1,
	.pluginIdentifier = "com.example.truncated-registration",
	.pluginVersion = "1.0.0",
	.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
	.registerPlugin = BTTruncatedRegistrationPluginRegister,
};

static void BTTestIdentifiers(void) {
	BTTestRequire(BTPluginIdentifierIsValid(@"com.example.plugin"), @"reverse-DNS identifier should be valid");
	BTTestRequire(BTPluginIdentifierIsValid(@"battery.summary"), @"existing Analytics identifier should be valid");
	BTTestRequire(!BTPluginIdentifierIsValid(@"single"), @"single-component identifier should be invalid");
	BTTestRequire(!BTPluginIdentifierIsValid(@"Com.example.plugin"), @"uppercase identifier should be invalid");
	BTTestRequire(!BTPluginIdentifierIsValid(@"com..plugin"), @"empty identifier component should be invalid");
	BTTestRequire(!BTPluginIdentifierIsValid(@"com.example.-plugin"), @"edge hyphen should be invalid");
}

static void BTTestRegistryTransactions(void) {
	BTPluginRegistry *registry = [BTPluginRegistry new];
	NSError *error = nil;
	BTTestRequire([registry registerExtensionPointIdentifier:BTTestExtensionPoint interfaceVersion:1 requiredProtocol:@protocol(BTTestExtension) error:&error], error.localizedDescription);
	BTTestRequire([registry registerExtensionPointIdentifier:BTTestOtherExtensionPoint interfaceVersion:1 requiredProtocol:@protocol(BTTestExtension) error:&error], error.localizedDescription);
	BTTestRequire([[registry interfaceVersionForExtensionPointIdentifier:BTTestExtensionPoint] isEqual:@1] &&
		[registry interfaceVersionForExtensionPointIdentifier:@"com.example.unknown.v1"] == nil,
		@"extension-point interface version lookup should be exact and read-only");

	NSSet<NSString *> *declared = [NSSet setWithObject:BTTestExtensionPoint];
	BTTestRequire(BTRegisterEmbeddedPluginDescriptor(&BTGoodPlugin, registry, declared, &error), error.localizedDescription);
	NSArray<BTPluginExtensionDescriptor *> *descriptors = [registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint];
	BTTestRequire(descriptors.count == 1, @"good transaction should commit exactly one extension");
	BTTestRequire([descriptors.firstObject.extensionIdentifier isEqualToString:@"com.example.good.card"], @"committed extension identifier should be preserved");
	BTTestRequire([descriptors.firstObject.extensionObject conformsToProtocol:@protocol(BTTestExtension)], @"committed object should be retained and typed");

	error = nil;
	BTPluginRegistrationTransaction *duplicatePlugin = [registry beginTransactionForPluginIdentifier:@"com.example.good" pluginVersion:@"2" declaredExtensionPoints:declared error:&error];
	BTTestRequire(!duplicatePlugin && error.code == BTPluginRegistryErrorDuplicatePluginIdentifier, @"committed plug-in identifiers must be unique");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTFailingPlugin, registry, declared, &error), @"invalid staged extension should reject the whole callback");
	descriptors = [registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint];
	BTTestRequire(descriptors.count == 1, @"failed transaction must not leak its earlier staged extension");
	BTTestRequire(![[descriptors valueForKey:@"extensionIdentifier"] containsObject:@"com.example.failing.staged"], @"rolled-back identifier must not be visible");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTUndeclaredPlugin, registry, declared, &error), @"undeclared extension point should be rejected");
	BTTestRequire(error.code == BTPluginRegistryErrorUndeclaredExtensionPoint, @"undeclared extension should preserve the registry error");
	BTTestRequire([registry extensionDescriptorsForExtensionPointIdentifier:BTTestOtherExtensionPoint].count == 0, @"undeclared extension must not commit");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTBadVersionPlugin, registry, declared, &error), @"incompatible extension-point version should be rejected");
	BTTestRequire(error.code == BTPluginRegistryErrorIncompatibleExtensionPointVersion, @"version rejection should preserve the registry error");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTReservedFlagsPlugin, registry, declared, &error), @"unknown registration flags should fail closed");
	BTTestRequire([error.domain isEqualToString:BTEmbeddedPluginRegistrationErrorDomain], @"reserved flags should fail at the ABI bridge");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTDuplicateCommittedExtensionPlugin, registry, declared, &error), @"another plug-in cannot reuse a committed extension identifier");
	BTTestRequire(error.code == BTPluginRegistryErrorDuplicateExtensionIdentifier, @"duplicate extension should fail during atomic commit");
	BTTestRequire([registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint].count == 1, @"failed duplicate commit must leave the catalog unchanged");

	error = nil;
	BTTestRequire(BTRegisterEmbeddedPluginDescriptor(&BTAppendedTailPlugin.v1, registry, declared, &error),
		error.localizedDescription);
	BTTestRequire([registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint].count == 2,
		@"append-only descriptor and registration tails should be ignored by a v1 host");

	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTTruncatedDescriptorPlugin, registry, declared, &error) &&
		[error.domain isEqualToString:BTEmbeddedPluginRegistrationErrorDomain],
		@"a descriptor shorter than the frozen v1 prefix must fail closed");
	error = nil;
	BTTestRequire(!BTRegisterEmbeddedPluginDescriptor(&BTTruncatedRegistrationPlugin, registry, declared, &error) &&
		[error.domain isEqualToString:BTEmbeddedPluginRegistrationErrorDomain],
		@"a registration shorter than the frozen v1 prefix must fail closed");
	BTTestRequire([registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint].count == 2,
		@"truncated structures must not commit partial registry state");
}

static void BTTestRegistryContracts(void) {
	BTPluginRegistry *registry = [BTPluginRegistry new];
	NSError *error = nil;
	BTTestRequire([registry registerExtensionPointIdentifier:BTTestExtensionPoint interfaceVersion:1 requiredProtocol:@protocol(BTTestExtension) error:&error], error.localizedDescription);
	BTTestRequire([registry registerExtensionPointIdentifier:BTTestExtensionPoint interfaceVersion:1 requiredProtocol:@protocol(BTTestExtension) error:&error], @"registering the identical extension-point contract should be idempotent");
	error = nil;
	BTTestRequire(![registry registerExtensionPointIdentifier:BTTestExtensionPoint interfaceVersion:2 requiredProtocol:@protocol(BTTestExtension) error:&error], @"a conflicting extension-point contract should fail");
	BTTestRequire(error.code == BTPluginRegistryErrorDuplicateExtensionPoint, @"conflicting contract should report duplicate extension point");

	NSSet<NSString *> *declared = [NSSet setWithObject:BTTestExtensionPoint];
	BTPluginRegistrationTransaction *empty = [registry beginTransactionForPluginIdentifier:@"com.example.empty" pluginVersion:@"1" declaredExtensionPoints:declared error:&error];
	BTTestRequire(empty != nil, error.localizedDescription);
	error = nil;
	BTTestRequire(![empty commit:&error] && error.code == BTPluginRegistryErrorEmptyTransaction, @"empty transaction should be rejected");
	BTTestRequire(empty.closed, @"a rejected commit attempt must close its transaction");
	BTTestExtensionObject *lateObject = [BTTestExtensionObject new];
	lateObject.testIdentifier = @"late";
	error = nil;
	BTTestRequire(![empty registerExtensionObject:lateObject extensionPointIdentifier:BTTestExtensionPoint extensionPointVersion:1 extensionIdentifier:@"com.example.empty.late" error:&error], @"closed transaction must reject later registration");
	BTTestRequire(error.code == BTPluginRegistryErrorTransactionClosed, @"closed transaction should report its state");

	BTPluginRegistrationTransaction *ordered = [registry beginTransactionForPluginIdentifier:@"com.example.ordered" pluginVersion:@"1" declaredExtensionPoints:declared error:&error];
	BTTestExtensionObject *first = [BTTestExtensionObject new];
	first.testIdentifier = @"first";
	BTTestExtensionObject *second = [BTTestExtensionObject new];
	second.testIdentifier = @"second";
	BTTestRequire([ordered registerExtensionObject:first extensionPointIdentifier:BTTestExtensionPoint extensionPointVersion:1 extensionIdentifier:@"com.example.ordered.first" error:&error], error.localizedDescription);
	BTTestRequire([ordered registerExtensionObject:second extensionPointIdentifier:BTTestExtensionPoint extensionPointVersion:1 extensionIdentifier:@"com.example.ordered.second" error:&error], error.localizedDescription);
	BTTestRequire([ordered commit:&error], error.localizedDescription);
	NSArray<NSString *> *identifiers = [[registry extensionDescriptorsForExtensionPointIdentifier:BTTestExtensionPoint] valueForKey:@"extensionIdentifier"];
	BTTestRequire([identifiers isEqualToArray:@[ @"com.example.ordered.first", @"com.example.ordered.second" ]], @"registry lookup order must match deterministic registration order");

	error = nil;
	BTPluginRegistrationTransaction *foreignNamespace = [registry
		beginTransactionForPluginIdentifier:@"com.example.owner"
		pluginVersion:@"1" declaredExtensionPoints:declared error:&error];
	BTTestRequire(foreignNamespace != nil, error.localizedDescription);
	BTTestExtensionObject *foreignObject = [BTTestExtensionObject new];
	foreignObject.testIdentifier = @"foreign";
	BTTestRequire(![foreignNamespace registerExtensionObject:foreignObject
		extensionPointIdentifier:BTTestExtensionPoint extensionPointVersion:1
		extensionIdentifier:@"com.example.victim.card" error:&error],
		@"a plug-in must not claim an extension identifier outside its namespace");
	BTTestRequire(error.code == BTPluginRegistryErrorExtensionIdentifierOutsideNamespace,
		@"a foreign extension identifier should report the namespace error");
	[foreignNamespace rollback];
}

int main(void) {
	@autoreleasepool {
		BTTestIdentifiers();
		BTTestRegistryTransactions();
		BTTestRegistryContracts();
		puts("Plugin registry tests passed.");
	}
	return 0;
}
