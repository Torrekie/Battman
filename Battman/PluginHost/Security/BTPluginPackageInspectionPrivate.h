//
//  BTPluginPackageInspectionPrivate.h
//  Battman
//
//  Private construction surface shared by the transport and sealed installed
//  representation verifiers. Never install this header in PluginSDK.
//

#import "BTPluginPackageStructuralVerifier.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginInspectedFile (BTPluginPackageInspectionPrivate)
+ (instancetype)bt_fileWithRelativePath:(NSString *)relativePath
								 fileSize:(uint64_t)fileSize
								modeClass:(NSString *)modeClass
									sha256:(NSString *)sha256;
@end

@interface BTPluginPackageInspection (BTPluginPackageInspectionPrivate)
+ (instancetype)bt_inspectionWithPackageURL:(NSURL *)packageURL
									 manifest:(BTPluginPackageManifest *)manifest
								 manifestData:(NSData *)manifestData
							 manifestSHA256:(NSString *)manifestSHA256
								 packageSHA256:(NSString *)packageSHA256
							 outerInfoDictionary:(NSDictionary *)outerInfoDictionary
									filesByPath:(NSDictionary<NSString *, BTPluginInspectedFile *> *)filesByPath
				 signatureDataByKeyIdentifier:(NSDictionary<NSString *, NSData *> *)signatureDataByKeyIdentifier
	includedPublisherKeysByIdentifier:(NSDictionary<NSString *, NSData *> *)includedPublisherKeysByIdentifier
									 payloadURL:(NSURL *)payloadURL
								 executableURL:(NSURL *)executableURL
				 sealedAppBundleRepresentation:(BOOL)sealedAppBundleRepresentation;
@end

NS_ASSUME_NONNULL_END
