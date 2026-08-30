//
//  BTPluginQuarantineStore.h
//  Battman
//
//  Content-addressed, non-activating import into Battman's private quarantine.
//

#import <Foundation/Foundation.h>

#import "../Security/BTPluginPackageVerifier.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginQuarantinedPackage : NSObject
@property (nonatomic, strong, readonly) NSURL *packageURL;
@property (nonatomic, strong, readonly) BTPluginVerifiedPackage *verification;
@property (nonatomic, readonly, getter=isApprovedForActivation) BOOL approvedForActivation;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginQuarantineStore : NSObject

@property (nonatomic, strong, readonly) NSURL *rootURL;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithRootURL:(NSURL *)rootURL
							  packageVerifier:(BTPluginPackageVerifier *)packageVerifier
										 error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginQuarantinedPackage *)quarantinePackageAtURL:(NSURL *)sourcePackageURL
													 developerMode:(BOOL)developerMode
																 error:(NSError * _Nullable * _Nullable)error;

// Bounded two-level inventory of content-addressed packages. Invalid or
// tampered entries fail closed and are not returned as approvable packages.
- (nullable NSArray<BTPluginQuarantinedPackage *> *)quarantinedPackagesWithDeveloperMode:(BOOL)developerMode
																							 error:(NSError * _Nullable * _Nullable)error;

// Removes only a named content-addressed quarantine directory after it has
// been atomically renamed inside the matching plug-in subdirectory.
- (BOOL)removeQuarantinedPluginIdentifier:(NSString *)pluginIdentifier
									 packageSHA256:(NSString *)packageSHA256
												 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
