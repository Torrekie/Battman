//
//  BTPluginPackageErrors.m
//  Battman
//

#import "BTPluginPackageErrors.h"

NSErrorDomain const BTPluginPackageErrorDomain = @"com.torrekie.Battman.PluginPackage";
NSString * const BTPluginPackageErrorRelativePathKey = @"BTPluginPackageRelativePath";

NSError *BTPluginPackageMakeError(BTPluginPackageErrorCode code,
								  NSString *description,
								  NSString *relativePath,
								  NSError *underlyingError) {
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description
																					 forKey:NSLocalizedDescriptionKey];
	if (relativePath.length > 0)
		userInfo[BTPluginPackageErrorRelativePathKey] = relativePath;
	if (underlyingError)
		userInfo[NSUnderlyingErrorKey] = underlyingError;
	return [NSError errorWithDomain:BTPluginPackageErrorDomain code:code userInfo:userInfo];
}
