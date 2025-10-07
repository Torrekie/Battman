//
//  selfcheck.h
//  Battman
//
//  Created by Torrekie on 2025/5/20.
//

#ifndef selfcheck_h
#define selfcheck_h

#include <mach-o/dyld.h>
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <notify.h>

#include "../common.h"

#if !defined(LICENSE) || LICENSE != LICENSE_NONFREE
#define kBattmanFatalNotifyKey "com.torrekie.Battman.fatal"
#elif __has_include("../nonfree-defs.h")
#include "../nonfree-defs.h"
#endif

__attribute__((always_inline))
inline static char *get_main_executable_path(void) {
	CFBundleRef mainBundle = CFBundleGetMainBundle();
	if (!mainBundle) return NULL;
	
	CFURLRef execURL = CFBundleCopyExecutableURL(mainBundle);
	if (!execURL) return NULL;
	
	char buf[PATH_MAX];
	Boolean ok = CFURLGetFileSystemRepresentation(execURL, true,
												  (UInt8*)buf, sizeof(buf));
	CFRelease(execURL);
	if (!ok) return NULL;
	
	return strdup(buf);
}

// ----- Suspicious‑finder function -----

// Scans all loaded dyld images.  Returns a malloc’d array of
// char* paths that lie under bundlePath but are NOT equal to
// the real main executable path
// On success: returns the array, and *outCount is the number of entries.
// On failure (e.g. OOM): returns NULL and *outCount is zero.
// Caller must free each string in the returned array and then free() the array itself.
__attribute__((always_inline))
inline char **find_suspicious_images_under_app(const char *bundlePath, size_t *outCount) {
	if (!bundlePath || !outCount) return NULL;
	*outCount = 0;
	
	// Build whitelist paths
	char *mainExec = get_main_executable_path();
	if (!mainExec) return NULL;
	
	const char *intlRel = "/Frameworks/intl.framework/intl";
	size_t bpLen = strlen(bundlePath),
	iLen  = strlen(intlRel);
	char *intlPath = malloc(bpLen + iLen + 1);
	if (!intlPath) { free(mainExec); return NULL; }
	memcpy(intlPath, bundlePath, bpLen);
	memcpy(intlPath + bpLen, intlRel, iLen + 1);
	
	uint32_t imageCount = _dyld_image_count();
	
	// Prepare dynamic array
	size_t capacity = 16;
	char **list = malloc(capacity * sizeof(char*));
	if (!list) { free(mainExec); free(intlPath); return NULL; }
	
	for (uint32_t i = 0; i < imageCount; i++) {
		const char *img = _dyld_get_image_name(i);
		
		// Must be under our bundle path
		if (strncmp(img, bundlePath, bpLen) != 0)
			continue;
		
		// Skip whitelisted paths
		if (strcmp(img, mainExec) == 0 ||
			strcmp(img, intlPath) == 0)
		{
			continue;
		}
		
		// Add to suspicious list
		if (*outCount >= capacity) {
			size_t newCap = capacity * 2;
			char **tmp = realloc(list, newCap * sizeof(char*));
			if (!tmp) break;  // OOM: stop adding but keep what we have
			list = tmp;
			capacity = newCap;
		}
		list[*outCount] = strdup(img);
		if (!list[*outCount]) break;  // OOM
		(*outCount)++;
	}
	
	free(mainExec);
	free(intlPath);
	return list;
}

/*__attribute__((always_inline))
inline void push_fatal_notif(void) {
	notify_post(kBattmanFatalNotifyKey);
}*/
extern void push_fatal_notif(void);

// Get the ASLR slide for the main executable
extern intptr_t get_main_executable_aslr_slide(void);

__attribute__((always_inline))
inline void pull_fatal_notif(void) {
	int token = 0;
	notify_register_dispatch(kBattmanFatalNotifyKey, &token, dispatch_get_main_queue(), ^(int t) {
		extern void removeAllViews(void);
		removeAllViews();
	});
}


#endif /* selfcheck_h */
