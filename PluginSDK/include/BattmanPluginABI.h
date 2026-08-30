//
//  BattmanPluginABI.h
//  Battman Plugin SDK
//
//  Stable C entry boundary shared by embedded and native plug-ins.
//  This header intentionally has no Foundation, Objective-C, or host-private
//  dependencies and is valid in C, Objective-C, C++, and Objective-C++.
//

#ifndef BATTMAN_PLUGIN_ABI_H
#define BATTMAN_PLUGIN_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BT_PLUGIN_FORMAT_VERSION_1 1u
#define BT_PLUGIN_ABI_VERSION_1 1u
#define BT_PLUGIN_ENTRY_POINT_SYMBOL_V1 "BattmanPluginEntryPointV1"
#define BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1 "com.torrekie.battman.analytics.card.v1"

#if defined(__GNUC__)
#define BT_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define BT_PLUGIN_EXPORT
#endif

typedef int32_t BTPluginResultV1;

enum {
	BTPluginResultV1Success = 0,
	BTPluginResultV1InvalidArgument = 1,
	BTPluginResultV1IncompatibleABI = 2,
	BTPluginResultV1UndeclaredExtensionPoint = 3,
	BTPluginResultV1InvalidExtension = 4,
	BTPluginResultV1DuplicateIdentifier = 5,
	BTPluginResultV1RegistrationFailed = 6,
};

typedef uint32_t BTPluginLogLevelV1;

enum {
	BTPluginLogLevelV1Debug = 0,
	BTPluginLogLevelV1Information = 1,
	BTPluginLogLevelV1Error = 2,
};

/*
 * Error strings are UTF-8 and borrowed. A producer keeps the pointed-to bytes
 * valid until the callback that receives this structure returns. A consumer
 * copies strings it needs beyond that callback.
 */
typedef struct BTPluginErrorV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	int32_t code;
	uint32_t reserved;
	const char *message;
} BTPluginErrorV1;

/*
 * extensionObject is an unretained Objective-C object pointer when the
 * extension point uses an Objective-C protocol. It is valid for the duration
 * of registerExtension. The host retains it only if the complete plug-in
 * registration transaction commits.
 */
typedef struct BTPluginExtensionRegistrationV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	const char *extensionPointIdentifier;
	uint32_t extensionPointVersion;
	uint32_t flags;
	const char *extensionIdentifier;
	const void *extensionObject;
} BTPluginExtensionRegistrationV1;

typedef BTPluginResultV1 (*BTPluginHostRegisterExtensionV1)(
	void *context,
	const BTPluginExtensionRegistrationV1 *registration,
	BTPluginErrorV1 *error);

typedef void (*BTPluginHostLogV1)(
	void *context,
	BTPluginLogLevelV1 level,
	const char *message);

typedef struct BTPluginHostV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	void *context;
	BTPluginHostRegisterExtensionV1 registerExtension;
	/* Optional for v1 callers. Check structSize and the pointer before use. */
	BTPluginHostLogV1 log;
} BTPluginHostV1;

typedef BTPluginResultV1 (*BTPluginRegisterV1)(
	const BTPluginHostV1 *host,
	BTPluginErrorV1 *error);

typedef struct BTPluginDescriptorV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	const char *pluginIdentifier;
	const char *pluginVersion;
	uint32_t minimumHostABIVersion;
	uint32_t maximumHostABIVersion;
	BTPluginRegisterV1 registerPlugin;
} BTPluginDescriptorV1;

typedef const BTPluginDescriptorV1 *(*BTPluginEntryPointV1)(void);

/*
 * Frozen v1 prefix sizes. A producer may append fields without changing the
 * ABI version. Consumers must require only the prefix they actually use and
 * ignore a larger structSize. BTPluginHostV1.log is the first optional host
 * tail field; the required v1 host prefix ends at registerExtension.
 */
#define BT_PLUGIN_STRUCT_SIZE_THROUGH(type, field) \
	((uint32_t)(offsetof(type, field) + sizeof(((type *)0)->field)))
#define BT_PLUGIN_ERROR_V1_MINIMUM_SIZE \
	BT_PLUGIN_STRUCT_SIZE_THROUGH(BTPluginErrorV1, message)
#define BT_PLUGIN_EXTENSION_REGISTRATION_V1_MINIMUM_SIZE \
	BT_PLUGIN_STRUCT_SIZE_THROUGH(BTPluginExtensionRegistrationV1, extensionObject)
#define BT_PLUGIN_HOST_V1_MINIMUM_SIZE \
	BT_PLUGIN_STRUCT_SIZE_THROUGH(BTPluginHostV1, registerExtension)
#define BT_PLUGIN_DESCRIPTOR_V1_MINIMUM_SIZE \
	BT_PLUGIN_STRUCT_SIZE_THROUGH(BTPluginDescriptorV1, registerPlugin)

#ifdef __cplusplus
}
#endif

#endif /* BATTMAN_PLUGIN_ABI_H */
