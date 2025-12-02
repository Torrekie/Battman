//
//  CrashLogger.m
//  Battman
//
//  Created for crash logging and diagnostics
//

#import "CrashLogger.h"
#import "common.h"
#include <execinfo.h>
#include <signal.h>
#include <UIKit/UIKit.h>
#include <sys/utsname.h>
#include <sys/stat.h>

// Forward declarations for C handler functions
static void uncaughtExceptionHandler(NSException *exception);
static void signalHandler(int sig);

static NSString *crashLogFilePath = nil;

@implementation CrashLogger

+ (void)initialize {
    if (self == [CrashLogger class]) {
        // Set up crash log file path using battman_config_dir()/CrashLogs/
        const char *configDir = battman_config_dir();
        if (configDir) {
            NSString *crashLogsDir = [[NSString stringWithUTF8String:configDir] stringByAppendingPathComponent:@"CrashLogs"];
            
            // Create CrashLogs directory if it doesn't exist
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *error = nil;
            [fileManager createDirectoryAtPath:crashLogsDir withIntermediateDirectories:YES attributes:nil error:&error];
            
            if (error) {
                NSLog(@"[CrashLogger] Failed to create crash logs directory: %@", error);
            }
            
            // Generate timestamped filename: BattmanCrash_YYYY_MM_DD_HHMMSS.log
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"yyyy_MM_dd_HHmmss"];
            NSString *timestamp = [formatter stringFromDate:[NSDate date]];
            NSString *filename = [NSString stringWithFormat:@"BattmanCrash_%@.log", timestamp];
            
            crashLogFilePath = [crashLogsDir stringByAppendingPathComponent:filename];
        } else {
            NSLog(@"[CrashLogger] Warning: battman_config_dir() returned NULL, falling back to Documents directory");
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths firstObject];
            crashLogFilePath = [documentsDirectory stringByAppendingPathComponent:@"Battman_Crash.log"];
        }
    }
}

+ (NSString *)crashLogPath {
    return crashLogFilePath;
}

+ (void)installCrashHandlers {
    NSLog(@"[CrashLogger] Installing crash handlers. Log file: %@", crashLogFilePath);
    
    // Install NSException handler
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    // Install signal handlers for common crashes
    signal(SIGSEGV, signalHandler);  // Segmentation fault
    signal(SIGABRT, signalHandler);  // Abort
    signal(SIGBUS, signalHandler);   // Bus error
    signal(SIGILL, signalHandler);   // Illegal instruction
    signal(SIGFPE, signalHandler);   // Floating point exception
    signal(SIGTRAP, signalHandler);  // Trap
}

+ (void)logMessage:(NSString *)message {
    if (!crashLogFilePath) return;
    
    NSString *timestamp = [self timestamp];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:crashLogFilePath]) {
        [logEntry writeToFile:crashLogFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:crashLogFilePath];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

+ (NSString *)timestamp {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    return [formatter stringFromDate:[NSDate date]];
}

+ (NSString *)deviceInfo {
    struct utsname systemInfo;
    uname(&systemInfo);
    
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    
    return [NSString stringWithFormat:@"Device: %@, iOS: %@", deviceModel, systemVersion];
}

+ (NSString *)stackTrace {
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    char **symbols = backtrace_symbols(callstack, frames);
    
    NSMutableString *stackTrace = [NSMutableString stringWithString:@"Stack Trace:\n"];
    for (int i = 0; i < frames; i++) {
        [stackTrace appendFormat:@"%s\n", symbols[i]];
    }
    free(symbols);
    
    return stackTrace;
}

+ (void)logCrashWithType:(NSString *)type reason:(NSString *)reason {
    NSMutableString *crashLog = [NSMutableString string];
    
    [crashLog appendString:@"\n========================================\n"];
    [crashLog appendFormat:@"CRASH REPORT - %@\n", [self timestamp]];
    [crashLog appendString:@"========================================\n\n"];
    
    [crashLog appendFormat:@"Crash Type: %@\n", type];
	[crashLog appendFormat:@"Battman working type: %@\n", (gAppType == BATTMAN_APP) ? @"App" : @"Subprocess"];
    [crashLog appendFormat:@"%@\n\n", [self deviceInfo]];
    
    if (reason) {
        [crashLog appendFormat:@"Reason: %@\n\n", reason];
    }
    
    [crashLog appendFormat:@"%@\n", [self stackTrace]];
    
    [crashLog appendString:@"========================================\n\n"];
    
    // Write to file
    [self logMessage:crashLog];
    
    // Also log to console
    NSLog(@"%@", crashLog);
}

@end

#pragma mark - C Exception and Signal Handlers

static void uncaughtExceptionHandler(NSException *exception) {
    NSString *reason = [NSString stringWithFormat:@"%@ - %@", 
                        exception.name, exception.reason];
    
    NSMutableString *stackInfo = [NSMutableString stringWithString:reason];
    [stackInfo appendString:@"\n\nCall Stack:\n"];
    
    for (NSString *symbol in exception.callStackSymbols) {
        [stackInfo appendFormat:@"%@\n", symbol];
    }
    
    [CrashLogger logCrashWithType:@"NSException" reason:stackInfo];
    
    // Let the system handle the exception after logging
}

static void signalHandler(int sig) {
    NSString *signalName = @"UNKNOWN";
    switch (sig) {
        case SIGSEGV: signalName = @"SIGSEGV (Segmentation Fault)"; break;
        case SIGABRT: signalName = @"SIGABRT (Abort)"; break;
        case SIGBUS: signalName = @"SIGBUS (Bus Error)"; break;
        case SIGILL: signalName = @"SIGILL (Illegal Instruction)"; break;
        case SIGFPE: signalName = @"SIGFPE (Floating Point Exception)"; break;
        case SIGTRAP: signalName = @"SIGTRAP (Trap)"; break;
    }
    
    NSString *reason = [NSString stringWithFormat:@"Signal %d received: %@", sig, signalName];
    [CrashLogger logCrashWithType:@"Signal" reason:reason];
    
    // Reset to default handler and re-raise
    signal(sig, SIG_DFL);
    raise(sig);
}
