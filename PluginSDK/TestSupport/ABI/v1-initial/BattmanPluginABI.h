/*
 * Frozen initial ABI-v1 consumer fixture.
 *
 * This is deliberately not the live SDK header. Tests compile an older
 * plug-in against this snapshot and load it with the current host. Do not
 * update it when fields are appended to the live v1 structures.
 */
#ifndef BATTMAN_PLUGIN_ABI_V1_INITIAL_FIXTURE_H
#define BATTMAN_PLUGIN_ABI_V1_INITIAL_FIXTURE_H

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

typedef struct BTPluginErrorV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	int32_t code;
	uint32_t reserved;
	const char *message;
} BTPluginErrorV1;

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

/* The initial v1 fixture predates the optional log tail field. */
typedef struct BTPluginHostV1 {
	uint32_t structSize;
	uint32_t abiVersion;
	void *context;
	BTPluginHostRegisterExtensionV1 registerExtension;
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

#define BT_PLUGIN_STRUCT_SIZE_THROUGH(type, field) \
	((uint32_t)(offsetof(type, field) + sizeof(((type *)0)->field)))
#define BT_PLUGIN_HOST_V1_MINIMUM_SIZE \
	BT_PLUGIN_STRUCT_SIZE_THROUGH(BTPluginHostV1, registerExtension)

#ifdef __cplusplus
}
#endif

#endif /* BATTMAN_PLUGIN_ABI_V1_INITIAL_FIXTURE_H */
