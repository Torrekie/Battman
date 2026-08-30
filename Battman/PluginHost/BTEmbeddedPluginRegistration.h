//
//  BTEmbeddedPluginRegistration.h
//  Battman
//

#import <Foundation/Foundation.h>

#include "../../PluginSDK/include/BattmanPluginABI.h"

@class BTPluginRegistry;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const BTEmbeddedPluginRegistrationErrorDomain;

typedef NS_ERROR_ENUM(BTEmbeddedPluginRegistrationErrorDomain, BTEmbeddedPluginRegistrationErrorCode) {
	BTEmbeddedPluginRegistrationErrorInvalidDescriptor = 1,
	BTEmbeddedPluginRegistrationErrorIncompatibleABI = 2,
	BTEmbeddedPluginRegistrationErrorCallbackFailed = 3,
	BTEmbeddedPluginRegistrationErrorHostRejectedExtension = 4,
};

FOUNDATION_EXPORT BOOL BTRegisterEmbeddedPluginDescriptor(
	const BTPluginDescriptorV1 *descriptor,
	BTPluginRegistry *registry,
	NSSet<NSString *> *declaredExtensionPoints,
	NSError * _Nullable * _Nullable error);

// Host-internal common descriptor bridge. Native code reaches this function
// only after BTPluginRuntimeLoader completes package verification and mapping.
FOUNDATION_EXPORT BOOL BTRegisterPluginDescriptorV1(
	const BTPluginDescriptorV1 *descriptor,
	BTPluginRegistry *registry,
	NSSet<NSString *> *declaredExtensionPoints,
	NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
