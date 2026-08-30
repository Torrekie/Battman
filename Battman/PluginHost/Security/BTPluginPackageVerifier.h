//
//  BTPluginPackageVerifier.h
//  Battman
//
//  One non-executing hard-verification pipeline. A requires-approval trust
//  disposition is the only non-error result that is not activation-approved.
//

#import <Foundation/Foundation.h>

#import "BTPluginMachOInspector.h"
#import "BTPluginTrustEvaluator.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginVerifiedPackage : NSObject
@property (nonatomic, strong, readonly) BTPluginPackageInspection *packageInspection;
@property (nonatomic, strong, readonly) BTPluginMachOInspection *machOInspection;
@property (nonatomic, strong, readonly) BTPluginTrustEvaluation *trustEvaluation;
@property (nonatomic, readonly, getter=isApprovedForActivation) BOOL approvedForActivation;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPackageVerifier : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTrustEvaluator:(BTPluginTrustEvaluator *)trustEvaluator
							 hostIOSVersion:(NSOperatingSystemVersion)hostIOSVersion NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginVerifiedPackage *)verifyPackageAtURL:(NSURL *)packageURL
											developerMode:(BOOL)developerMode
													error:(NSError * _Nullable * _Nullable)error;

- (nullable BTPluginVerifiedPackage *)verifySealedMetadataAtURL:(NSURL *)metadataURL
														 payloadURL:(NSURL *)payloadURL
													 developerMode:(BOOL)developerMode
															 error:(NSError * _Nullable * _Nullable)error;

// Called at the one-way startup activation boundary, never during import or
// approval. This advances local anti-rollback state before code can execute.
- (BOOL)recordActivationCommitForVerifiedPackage:(BTPluginVerifiedPackage *)verifiedPackage
															 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
