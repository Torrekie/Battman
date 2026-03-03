//
//  CrashLogger.h
//  Battman
//
//  Created for crash logging and diagnostics
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CrashLoggerProcessMode) {
	CrashLoggerProcessModeApp = 0,
	CrashLoggerProcessModeDaemon,
	CrashLoggerProcessModeWorker,
	CrashLoggerProcessModeUnknown,
};

@interface CrashLogger : NSObject

/// Configure crash logging destination for the current process mode.
/// This must be called before installing handlers.
+ (void)configureForProcessMode:(CrashLoggerProcessMode)mode;

/// Install crash handlers (NSException and signal handlers)
+ (void)installCrashHandlers;

/// Get path to crash log file
/// Log files are stored under a crash-specific directory and include process mode in filename.
/// Each app launch creates a new timestamped log file
+ (NSString *)crashLogPath;

/// Manually log a message to crash log
+ (void)logMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
