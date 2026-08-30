//
//  BTPluginPlatformLoadabilityVerifier.h
//  Battman
//
//  Final non-executing platform-signature/loadability preflight. Publisher
//  authorization remains an independent Battman P-256 decision.
//

#import <Foundation/Foundation.h>

#import "BTPluginMachOInspector.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginPlatformLoadabilityVerifier : NSObject

- (BOOL)verifyPackageInspection:(BTPluginPackageInspection *)packageInspection
					 machOInspection:(BTPluginMachOInspection *)machOInspection
								 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
