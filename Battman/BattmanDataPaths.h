// Foundation paths backed by Battman's existing HOME/container policy.
#ifndef BattmanDataPaths_h
#define BattmanDataPaths_h

#import <Foundation/Foundation.h>

// Implemented by common.c; keep this header independent of its UI helpers.
extern const char * _Nullable battman_config_dir(void);

static inline NSURL * _Nullable BattmanConfigDirectoryURL(void) {
	const char *path = battman_config_dir();
	if (!path || !path[0]) return nil;
	return [NSURL fileURLWithFileSystemRepresentation:path isDirectory:YES relativeToURL:nil];
}

static inline NSURL * _Nullable BattmanAnalyticsCacheDirectoryURL(void) {
	return [BattmanConfigDirectoryURL() URLByAppendingPathComponent:@"AnalyticsHistory" isDirectory:YES];
}

#endif
