//
//  BTPluginSource.m
//  Battman
//

#import "BTPluginSource.h"

NSString *BTPluginSourceName(BTPluginSource source) {
	switch (source) {
		case BTPluginSourceAppBundle:
			return @"app-bundle";
		case BTPluginSourceApplicationData:
			return @"app-data";
		case BTPluginSourceRootedSystem:
			return @"rooted-system";
		case BTPluginSourceRootlessSystem:
			return @"rootless-system";
		case BTPluginSourceQuarantine:
			return @"quarantine";
		case BTPluginSourceImport:
			return @"import";
	}
	return @"unknown";
}

BOOL BTPluginSourceCanActivate(BTPluginSource source) {
	return source == BTPluginSourceAppBundle || source == BTPluginSourceApplicationData ||
		source == BTPluginSourceRootedSystem || source == BTPluginSourceRootlessSystem;
}
