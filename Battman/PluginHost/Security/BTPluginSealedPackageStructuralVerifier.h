//
//  BTPluginSealedPackageStructuralVerifier.h
//  Battman
//
//  Reconstructs the signed logical transport tree from app-sealed metadata and
//  its separately nested .bundle payload. Byte inspection only; never loads.
//

#import <Foundation/Foundation.h>

#import "BTPluginPackageStructuralVerifier.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginSealedPackageStructuralVerifier : NSObject

- (nullable BTPluginPackageInspection *)inspectMetadataAtURL:(NSURL *)metadataURL
													payloadURL:(NSURL *)payloadURL
														 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
