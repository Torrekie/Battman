//
//  BTPluginImportCoordinator.h
//  Battman
//
//  Document-open boundary for .battman packages. Import means complete
//  non-executing verification followed by quarantine only.
//

#import <Foundation/Foundation.h>

#import "BTPluginQuarantineStore.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const BTPluginImportDidFinishNotification;
FOUNDATION_EXPORT NSString * const BTPluginImportResultUserInfoKey;
FOUNDATION_EXPORT NSString * const BTPluginImportErrorUserInfoKey;

@interface BTPluginImportResult : NSObject
@property (nonatomic, strong, readonly) BTPluginQuarantinedPackage *quarantinedPackage;
@property (nonatomic, strong, readonly) NSDate *importedAt;
@property (nonatomic, readonly, getter=isApprovedByExistingTrust) BOOL approvedByExistingTrust;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginImportCoordinator : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithQuarantineStore:(BTPluginQuarantineStore *)quarantineStore
	NS_DESIGNATED_INITIALIZER;

// This is a cheap routing check only. Complete package verification remains
// mandatory inside quarantineImportAtURL:developerMode:error:.
- (BOOL)canHandlePackageURL:(NSURL *)packageURL;

// Synchronous primitive used by the serial document-open worker and tests.
// It never stores approval, installs, schedules activation, or maps code.
- (nullable BTPluginImportResult *)quarantineImportAtURL:(NSURL *)packageURL
												 developerMode:(BOOL)developerMode
														 error:(NSError * _Nullable * _Nullable)error;

// Returns NO only when the URL is not a supported local package URL. Accepted
// work completes asynchronously and posts BTPluginImportDidFinishNotification
// on the main thread with either a result or an error.
- (BOOL)handleOpenPackageURL:(NSURL *)packageURL;

@end

NS_ASSUME_NONNULL_END
