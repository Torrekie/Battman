//
//  BAAnalyticsBuiltInPlugin.m
//  Battman
//

#import "BAAnalyticsBuiltInPlugin.h"

#import "BAAnalyticsBuiltInCards.h"
#import "../Public/BAAnalyticsCard.h"

static BOOL BAAnalyticsABIStructureContainsField(uint32_t structSize, size_t fieldOffset, size_t fieldSize) {
	return structSize >= fieldOffset && (size_t)structSize - fieldOffset >= fieldSize;
}

static void BAAnalyticsWritePluginError(BTPluginErrorV1 *error, BTPluginResultV1 code, const char *message) {
	if (!error || !BAAnalyticsABIStructureContainsField(error->structSize, offsetof(BTPluginErrorV1, message), sizeof(error->message)))
		return;
	error->abiVersion = BT_PLUGIN_ABI_VERSION_1;
	error->code = code;
	error->reserved = 0;
	error->message = message;
}

static BTPluginResultV1 BAAnalyticsRegisterBuiltInCards(const BTPluginHostV1 *host, BTPluginErrorV1 *error) {
	if (!host ||
		host->abiVersion != BT_PLUGIN_ABI_VERSION_1 ||
		!BAAnalyticsABIStructureContainsField(host->structSize, offsetof(BTPluginHostV1, registerExtension), sizeof(host->registerExtension)) ||
		!host->registerExtension) {
		BAAnalyticsWritePluginError(error, BTPluginResultV1IncompatibleABI, "The Battman host table is incompatible.");
		return BTPluginResultV1IncompatibleABI;
	}

	for (id<BAAnalyticsCard> card in BAAnalyticsCreateBuiltInCards()) {
		BTPluginExtensionRegistrationV1 registration = {
			.structSize = sizeof(BTPluginExtensionRegistrationV1),
			.abiVersion = BT_PLUGIN_ABI_VERSION_1,
			.extensionPointIdentifier = BT_PLUGIN_EXTENSION_POINT_ANALYTICS_CARD_V1,
			.extensionPointVersion = BAAnalyticsCardExtensionPointVersion,
			.flags = 0,
			.extensionIdentifier = card.analyticsCardIdentifier.UTF8String,
			.extensionObject = (__bridge const void *)card,
		};
		BTPluginErrorV1 registrationError = {
			.structSize = sizeof(BTPluginErrorV1),
			.abiVersion = BT_PLUGIN_ABI_VERSION_1,
			.code = 0,
			.reserved = 0,
			.message = NULL,
		};
		BTPluginResultV1 result = host->registerExtension(host->context, &registration, &registrationError);
		if (result != BTPluginResultV1Success) {
			if (error && BAAnalyticsABIStructureContainsField(error->structSize, offsetof(BTPluginErrorV1, message), sizeof(error->message)))
				*error = registrationError;
			return result;
		}
	}

	return BTPluginResultV1Success;
}

const BTPluginDescriptorV1 *BAAnalyticsBuiltInPluginDescriptor(void) {
	static const BTPluginDescriptorV1 descriptor = {
		.structSize = sizeof(BTPluginDescriptorV1),
		.abiVersion = BT_PLUGIN_ABI_VERSION_1,
		.pluginIdentifier = "com.torrekie.battman.analytics",
		.pluginVersion = "1",
		.minimumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.maximumHostABIVersion = BT_PLUGIN_ABI_VERSION_1,
		.registerPlugin = BAAnalyticsRegisterBuiltInCards,
	};
	return &descriptor;
}
