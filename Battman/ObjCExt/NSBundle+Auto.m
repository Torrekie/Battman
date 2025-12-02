//
//  NSBundle+Auto.m
//  Battman
//
//  Created by Torrekie on 2025/12/2.
//

#import "NSBundle+Auto.h"

@implementation NSBundle (Auto)

+ (instancetype)systemBundleWithName:(NSString *)name fallbackExecutable:(NSString *)executable {
	NSBundle *bundle = nil;

	if (name) {
		bundle = [NSBundle bundleWithIdentifier:[NSString stringWithFormat:@"com.apple.%@", name]];
		if (bundle)
			return bundle;
	}
	
	if (executable == nil)
		return nil;

	NSArray<NSString *> *systemFrameworkBases = @[
		@"/System/Library/PrivateFrameworks",
		@"/System/Library/Frameworks"
	];

	NSString *dyldRoot = nil;
	const char *dyldRootC = getenv("DYLD_ROOT_PATH");
	if (dyldRootC && dyldRootC[0] != '\0') {
		dyldRoot = [NSString stringWithUTF8String:dyldRootC];
		// Normalize: treat "/" or empty as not useful.
		if (dyldRoot.length == 0 || [dyldRoot isEqualToString:@"/"]) {
			dyldRoot = nil;
		} else {
			// Ensure absolute form and trim trailing slashes.
			if (![dyldRoot hasPrefix:@"/"]) {
				dyldRoot = [@"/" stringByAppendingString:dyldRoot];
			}
			while ([dyldRoot hasSuffix:@"/"]) {
				dyldRoot = [dyldRoot substringToIndex:dyldRoot.length - 1];
			}
		}
	}
	
	NSString *(^normalizePath)(NSString *) = ^NSString *(NSString *p) {
		if (p.length == 0) return nil;
		if ([p hasPrefix:@"/"]) {
			NSString *s = p;
			while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
			return s;
		}
		if (dyldRoot) {
			NSString *s = [dyldRoot stringByAppendingPathComponent:p];
			while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
			return s;
		}
		NSString *s = p;
		while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
		return s;
	};
	NSArray<NSString *> *(^pathsFromEnv)(const char *) = ^NSArray<NSString *> *(const char *envC) {
		if (!envC || envC[0] == '\0') return @[];
		NSString *env = [NSString stringWithUTF8String:envC];
		NSMutableArray<NSString *> *out = [NSMutableArray array];
		for (NSString *part in [env componentsSeparatedByString:@":"]) {
			NSString *n = normalizePath([part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]);
			if (n.length) [out addObject:n];
		}
		return [out copy];
	};
	
	NSArray<NSString *> *dyldFrameworkPaths = pathsFromEnv(getenv("DYLD_FRAMEWORK_PATH"));
	NSArray<NSString *> *dyldFallbackFrameworkPaths = pathsFromEnv(getenv("DYLD_FALLBACK_FRAMEWORK_PATH"));

	// Build ordered candidate base directories:
	// 1) DYLD_FRAMEWORK_PATH entries (highest priority)
	// 2) If dyldRoot provided: dyldRoot + systemFrameworkBases (preserve system order)
	// 3) systemFrameworkBases
	// 4) DYLD_FALLBACK_FRAMEWORK_PATH entries (lowest priority)
	NSMutableArray<NSString *> *candidateBases = [NSMutableArray array];
	
	// 1
	[candidateBases addObjectsFromArray:dyldFrameworkPaths];
	
	// 2
	if (dyldRoot) {
		for (NSString *sys in systemFrameworkBases) {
			// sys is absolute (e.g. "/System/Library/Frameworks"), so join will duplicate slashes if we naive append.
			// We want dyldRoot + sys (without an extra slash): e.g. "/myroot/System/Library/Frameworks"
			NSString *sysTrimmed = sys;
			while ([sysTrimmed hasPrefix:@"/"]) sysTrimmed = [sysTrimmed substringFromIndex:1];
			NSString *joined = [dyldRoot stringByAppendingPathComponent:sysTrimmed];
			[candidateBases addObject:joined];
		}
	}
	
	// 3
	[candidateBases addObjectsFromArray:systemFrameworkBases];
	
	// 4
	[candidateBases addObjectsFromArray:dyldFallbackFrameworkPaths];
	
	// Iterate candidates and return the first non-nil NSBundle created for "<base>/<executable>.framework"
	for (NSString *base in candidateBases) {
		if (base.length == 0) continue;
		NSString *frameworkPath = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework", executable]];
		NSBundle *b = [NSBundle bundleWithPath:frameworkPath];
		if (b) {
			return b;
		}
	}

	return nil;
}


+ (instancetype)systemBundleWithName:(NSString *)name {
	return [NSBundle systemBundleWithName:name fallbackExecutable:name];
}

@end
