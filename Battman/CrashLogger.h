//
//  CrashLogger.h
//  Battman
//
//  Created for crash logging and diagnostics
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CrashLogger : NSObject

/// Install crash handlers (NSException and signal handlers)
+ (void)installCrashHandlers;

/// Get path to crash log file
/// Log files are stored at: battman_config_dir()/CrashLogs/BattmanCrash_YYYY_MM_DD_HHMMSS.log
/// Each app launch creates a new timestamped log file
+ (NSString *)crashLogPath;

/// Manually log a message to crash log
+ (void)logMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
