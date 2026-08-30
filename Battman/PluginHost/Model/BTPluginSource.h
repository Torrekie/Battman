//
//  BTPluginSource.h
//  Battman
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BTPluginSource) {
	BTPluginSourceAppBundle = 1,
	BTPluginSourceApplicationData = 2,
	BTPluginSourceRootedSystem = 3,
	BTPluginSourceRootlessSystem = 4,
	BTPluginSourceQuarantine = 5,
	BTPluginSourceImport = 6,
};

FOUNDATION_EXPORT NSString *BTPluginSourceName(BTPluginSource source);
FOUNDATION_EXPORT BOOL BTPluginSourceCanActivate(BTPluginSource source);

NS_ASSUME_NONNULL_END
