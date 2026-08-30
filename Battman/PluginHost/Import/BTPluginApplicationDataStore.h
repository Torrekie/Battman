//
//  BTPluginApplicationDataStore.h
//  Battman
//
//  Atomic, verifier-gated materialization into Battman's private PlugIns root.
//

#import <Foundation/Foundation.h>

#import "BTPluginQuarantineStore.h"
#import "../Runtime/BTPluginApplicationDataTransaction.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginApplicationDataStore : NSObject

@property (nonatomic, strong, readonly) NSURL *rootURL;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithRootURL:(NSURL *)rootURL
								 packageVerifier:(BTPluginPackageVerifier *)packageVerifier
											 error:(NSError * _Nullable * _Nullable)error NS_DESIGNATED_INITIALIZER;

// Transactional app-data path. Preparation copies and verifies the complete
// package into a deterministic private staging directory without changing the
// canonical installed name. Publication/reconciliation then performs only
// descriptor-checked atomic renames; the caller commits the matching Keychain
// journal after publication.
- (BOOL)prepareQuarantinedPackage:(BTPluginQuarantinedPackage *)quarantinedPackage
	transactionIdentifier:(NSString *)transactionIdentifier
	developerMode:(BOOL)developerMode
	error:(NSError * _Nullable * _Nullable)error;
- (nullable BTPluginVerifiedPackage *)installedPackageForPluginIdentifier:(NSString *)pluginIdentifier
	error:(NSError * _Nullable * _Nullable)error;

// Removal-only inspection for the exact canonical <ID>.battman app-data
// representation selected by the management UI. This deliberately bypasses
// trust approval and revocation, but still requires a safe owned root/path, a
// complete structural inventory, matching manifest identity, and the caller's
// exact package digest. It never maps or executes package code. Malformed or
// structurally tampered trees are intentionally outside this removal path.
- (nullable BTPluginPackageInspection *)inspectInstalledPackageForRemovalAtURL:(NSURL *)packageURL
	claimedPluginIdentifier:(NSString *)pluginIdentifier
	expectedPackageSHA256:(NSString *)expectedPackageSHA256
	error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginVerifiedPackage *)publishPreparedApplicationDataTransaction:
	(BTPluginApplicationDataTransaction *)transaction error:(NSError * _Nullable * _Nullable)error;
- (BOOL)reconcileApplicationDataTransaction:(BTPluginApplicationDataTransaction *)transaction
	committed:(BOOL * _Nullable)committed
	error:(NSError * _Nullable * _Nullable)error;
- (BOOL)discardUnjournaledPreparedTransactionsExceptIdentifier:(NSString * _Nullable)transactionIdentifier
	error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
