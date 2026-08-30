//
//  BTPluginPackageStructuralVerifier.h
//  Battman
//
//  Bounded .battman directory inspection. This API never creates an NSBundle,
//  maps a Mach-O image, resolves a symbol, or executes package content.
//

#import <Foundation/Foundation.h>

#import "../Model/BTPluginPackageManifest.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const BTPluginPackageMaximumRegularFileCount;
FOUNDATION_EXPORT uint64_t const BTPluginPackageMaximumTotalByteCount;
FOUNDATION_EXPORT uint64_t const BTPluginPackageMaximumSingleFileByteCount;

FOUNDATION_EXPORT BOOL BTPluginComputeMachOCodeIdentityAtURL(
	NSURL *executableURL,
	NSString *relativePath,
	uint64_t * _Nullable unsignedByteCount,
	NSString * _Nullable * _Nullable sha256,
	NSError * _Nullable * _Nullable error);

@interface BTPluginInspectedFile : NSObject
@property (nonatomic, copy, readonly) NSString *relativePath;
@property (nonatomic, readonly) uint64_t fileSize;
@property (nonatomic, copy, readonly) NSString *modeClass;
@property (nonatomic, copy, readonly) NSString *sha256;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPackageInspection : NSObject
@property (nonatomic, strong, readonly) NSURL *packageURL;
@property (nonatomic, strong, readonly) BTPluginPackageManifest *manifest;
@property (nonatomic, copy, readonly) NSData *manifestData;
@property (nonatomic, copy, readonly) NSString *manifestSHA256;
@property (nonatomic, copy, readonly) NSString *packageSHA256;
@property (nonatomic, copy, readonly) NSDictionary *outerInfoDictionary;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BTPluginInspectedFile *> *filesByPath;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSData *> *signatureDataByKeyIdentifier;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSData *> *includedPublisherKeysByIdentifier;
@property (nonatomic, strong, readonly) NSURL *payloadURL;
@property (nonatomic, strong, readonly) NSURL *executableURL;
@property (nonatomic, readonly, getter=isSealedAppBundleRepresentation) BOOL sealedAppBundleRepresentation;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPackageStructuralVerifier : NSObject

- (nullable BTPluginPackageInspection *)inspectPackageAtURL:(NSURL *)packageURL
															  error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
