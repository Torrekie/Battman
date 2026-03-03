//
//  CrashLogger.m
//  Battman
//
//  Created for crash logging and diagnostics
//

#import "CrashLogger.h"
#import "common.h"

#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

// Forward declarations for C handler functions
static void uncaughtExceptionHandler(NSException *exception);
static void signalHandler(int sig);

static NSString *crashLogFilePath = nil;
static int crashLogFD = -1;
static volatile sig_atomic_t crashModeForSignals = CrashLoggerProcessModeUnknown;
static volatile sig_atomic_t handlingSignal = 0;

static const char *crash_logger_mode_name_c(CrashLoggerProcessMode mode) {
	switch (mode) {
		case CrashLoggerProcessModeApp:
			return "app";
		case CrashLoggerProcessModeDaemon:
			return "daemon";
		case CrashLoggerProcessModeWorker:
			return "worker";
		default:
			return "unknown";
	}
}

static NSString *crash_logger_mode_name_ns(CrashLoggerProcessMode mode) {
	return [NSString stringWithUTF8String:crash_logger_mode_name_c(mode)];
}

static void signal_safe_write(int fd, const char *bytes, size_t len) {
	if (fd < 0 || bytes == NULL || len == 0)
		return;
	while (len > 0) {
		ssize_t wrote = write(fd, bytes, len);
		if (wrote > 0) {
			bytes += wrote;
			len -= (size_t)wrote;
			continue;
		}
		if (wrote == -1 && errno == EINTR)
			continue;
		break;
	}
}

#define WRITE_LITERAL(fd, lit) signal_safe_write((fd), (lit), sizeof(lit) - 1)

static void write_signal_mode(int fd) {
	switch ((CrashLoggerProcessMode)crashModeForSignals) {
		case CrashLoggerProcessModeApp:
			WRITE_LITERAL(fd, "app");
			break;
		case CrashLoggerProcessModeDaemon:
			WRITE_LITERAL(fd, "daemon");
			break;
		case CrashLoggerProcessModeWorker:
			WRITE_LITERAL(fd, "worker");
			break;
		default:
			WRITE_LITERAL(fd, "unknown");
			break;
	}
}

static void write_signal_name(int fd, int sig) {
	switch (sig) {
		case SIGSEGV:
			WRITE_LITERAL(fd, "SIGSEGV");
			break;
		case SIGABRT:
			WRITE_LITERAL(fd, "SIGABRT");
			break;
		case SIGBUS:
			WRITE_LITERAL(fd, "SIGBUS");
			break;
		case SIGILL:
			WRITE_LITERAL(fd, "SIGILL");
			break;
		case SIGFPE:
			WRITE_LITERAL(fd, "SIGFPE");
			break;
		default:
			WRITE_LITERAL(fd, "UNKNOWN");
			break;
	}
}

@implementation CrashLogger

+ (NSString *)resolvedCrashLogsDirectory {
	const char *configDir = battman_config_dir();
	if (configDir && configDir[0] != '\0') {
		return [[NSString stringWithUTF8String:configDir] stringByAppendingPathComponent:@"CrashLogs"];
	}

	NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = paths.firstObject;
	if (documentsDirectory.length > 0) {
		return [documentsDirectory stringByAppendingPathComponent:@"CrashLogs"];
	}

	NSString *tmpDir = NSTemporaryDirectory();
	if (tmpDir.length == 0) {
		tmpDir = @"/tmp";
	}
	return [tmpDir stringByAppendingPathComponent:@"BattmanCrashLogs"];
}

+ (void)configureForProcessMode:(CrashLoggerProcessMode)mode {
	@synchronized(self) {
		if (crashLogFD != -1)
			return;

		crashModeForSignals = (sig_atomic_t)mode;

		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"yyyy_MM_dd_HHmmss"];
		NSString *timestamp = [formatter stringFromDate:[NSDate date]];
		NSString *filename = [NSString stringWithFormat:@"BattmanCrash_%@_%@.log", timestamp, crash_logger_mode_name_ns(mode)];

		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSString *crashLogsDir = [self resolvedCrashLogsDirectory];
		NSError *error = nil;
		if ([fileManager createDirectoryAtPath:crashLogsDir withIntermediateDirectories:YES attributes:nil error:&error]) {
			NSString *path = [crashLogsDir stringByAppendingPathComponent:filename];
			int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
			if (fd != -1) {
				crashLogFD = fd;
				crashLogFilePath = path;
			}
		}

		if (crashLogFD == -1) {
			NSLog(@"[CrashLogger] Failed to initialize crash log file for mode %@", crash_logger_mode_name_ns(mode));
		}
	}
}

+ (NSString *)crashLogPath {
	return crashLogFilePath ?: @"";
}

+ (void)installCrashHandlers {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
		signal(SIGSEGV, signalHandler);
		signal(SIGABRT, signalHandler);
		signal(SIGBUS, signalHandler);
		signal(SIGILL, signalHandler);
		signal(SIGFPE, signalHandler);
	});
}

+ (void)logMessage:(NSString *)message {
	if (message.length == 0 || crashLogFD == -1)
		return;

	@synchronized(self) {
		NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", [self timestamp], message];
		NSData *data = [logEntry dataUsingEncoding:NSUTF8StringEncoding];
		if (data.length == 0)
			return;

		const char *bytes = data.bytes;
		size_t remaining = data.length;
		while (remaining > 0) {
			ssize_t wrote = write(crashLogFD, bytes, remaining);
			if (wrote > 0) {
				bytes += wrote;
				remaining -= (size_t)wrote;
				continue;
			}
			if (wrote == -1 && errno == EINTR)
				continue;
			break;
		}
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
	NSString *systemVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];

	return [NSString stringWithFormat:@"Device: %@, OS: %@", deviceModel, systemVersion];
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
	[crashLog appendFormat:@"Crash Type: %@\n", type ?: @"Unknown"];
	[crashLog appendFormat:@"Process Mode: %@\n", crash_logger_mode_name_ns((CrashLoggerProcessMode)crashModeForSignals)];
	[crashLog appendFormat:@"%@\n\n", [self deviceInfo]];
	if (reason.length > 0) {
		[crashLog appendFormat:@"Reason: %@\n\n", reason];
	}
	[crashLog appendFormat:@"%@\n", [self stackTrace]];
	[crashLog appendString:@"========================================\n"];
	[self logMessage:crashLog];
}

@end

#pragma mark - C Exception and Signal Handlers

static void uncaughtExceptionHandler(NSException *exception) {
	NSString *reason = [NSString stringWithFormat:@"%@ - %@", exception.name, exception.reason];
	NSMutableString *stackInfo = [NSMutableString stringWithString:reason];
	[stackInfo appendString:@"\n\nCall Stack:\n"];
	for (NSString *symbol in exception.callStackSymbols) {
		[stackInfo appendFormat:@"%@\n", symbol];
	}
	[CrashLogger logCrashWithType:@"NSException" reason:stackInfo];
}

static void signalHandler(int sig) {
	if (handlingSignal) {
		signal(sig, SIG_DFL);
		raise(sig);
		return;
	}

	handlingSignal = 1;
	if (crashLogFD != -1) {
		WRITE_LITERAL(crashLogFD, "\n========================================\n");
		WRITE_LITERAL(crashLogFD, "SIGNAL CRASH\n");
		WRITE_LITERAL(crashLogFD, "Mode: ");
		write_signal_mode(crashLogFD);
		WRITE_LITERAL(crashLogFD, "\nSignal: ");
		write_signal_name(crashLogFD, sig);
		WRITE_LITERAL(crashLogFD, "\n========================================\n");
	}

	signal(sig, SIG_DFL);
	raise(sig);
}
