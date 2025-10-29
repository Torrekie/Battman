//
//  common.h
//  Battman
//
//  Created by Torrekie on 2025/1/21.
//

#ifndef common_h
#define common_h

#include <CoreFoundation/CoreFoundation.h>
#include <TargetConditionals.h>
#include <dlfcn.h>
#include <os/log.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/types.h>

#include "CompatibilityHelper.h"
#include "main.h"

#if !defined(__OBJC__)
#include "cobjc/UNNotificationContent.h"
#include "cobjc/UNUserNotificationCenter.h"
#include "cobjc/cobjc.h"
#else
#import <UserNotifications/UserNotifications.h>
#endif

#include <stdint.h>

// Bitwisers

/* mask for bit n (returns 0 if n out-of-range for the type of var) */
#define BIT_MASK_OF(var, n) \
	((unsigned)(n) < (sizeof(var) * 8) ? ((typeof(var))1 << (n)) : (typeof(var))0)

/* Set bit n to value b (b should be 0 or 1). var must be an lvalue. */
#define BIT_SET(var, n, b)                         \
	do {                                           \
		typeof(var) *_pv = &(var);                 \
		unsigned     _bn = (unsigned)(n);          \
		if (_bn < sizeof(*_pv) * 8) {              \
			if (b)                                 \
				*_pv |= ((typeof(*_pv))1 << _bn);  \
			else                                   \
				*_pv &= ~((typeof(*_pv))1 << _bn); \
		}                                          \
	} while (0)

/* Toggle bit n */
#define BIT_TOGGLE(var, n)                    \
	do {                                      \
		typeof(var) *_pv = &(var);            \
		unsigned     _bn = (unsigned)(n);     \
		if (_bn < sizeof(*_pv) * 8)           \
			*_pv ^= ((typeof(*_pv))1 << _bn); \
	} while (0)

/* Read bit n (returns 0 or 1). Note: var is evaluated twice here. */
#define BIT_GET(var, n) \
	((unsigned)(n) < (sizeof(var) * 8) ? (((var) & ((typeof(var))1 << (n))) ? 1 : 0) : 0)

#ifdef DEBUG
#define DBGLOG(...) NSLog(__VA_ARGS__)
#define DBGALT(x, y, z) show_alert(x, y, z)
#else
#define DBGLOG(...)
#define DBGALT(x, y, z)
#endif

#ifndef USE_MOBILEGESTALT
#define USE_MOBILEGESTALT 0
#endif

#define LICENSE_MIT 2
#define LICENSE_GPL 3
#define LICENSE_NONFREE 4

#ifndef LICENSE
#define LICENSE LICENSE_MIT
#endif

#if LICENSE == LICENSE_NONFREE
// Standalone packages (deb, ipa) for use in Torrekie's repo or else
#define NONFREE_TYPE_STANDALONE 0x10
// Havoc deb packages
#define NONFREE_TYPE_HAVOC 0x20
// Torrekie/Battman releases
#define NONFREE_TYPE_GITHUB 0x30

#ifndef NONFREE_TYPE
#define NONFREE_TYPE NONFREE_TYPE_STANDALONE
#endif
#endif

#if (LICENSE == LICENSE_NONFREE) && (NONFREE_TYPE == NONFREE_TYPE_HAVOC) && !__has_include("havoc-defs.h")
#error Havoc configuration is not designed for OSS Battman, please switch LICENSE to LICENSE_MIT!
#endif

#define DL_CALL(fn, ret, proto, call_args) \
	({                                     \
		static ret(*_fp) proto = NULL;     \
		if (!_fp)                          \
			_fp = (ret(*) proto)           \
			    dlsym(RTLD_DEFAULT, #fn);  \
		_fp call_args;                     \
	})

#define GET_SECT_SYMBOL(proto, x)                \
	({                                           \
		static proto _cached = NULL;             \
		if (!_cached) {                          \
			void *sym = dlsym(RTLD_DEFAULT, #x); \
			if (sym)                             \
				_cached = *(proto *)sym;         \
		}                                        \
		(proto)_cached;                          \
	})

#define IOS_CONTAINER_FMT "^/private/var/mobile/Containers/Data/Application/[0-9A-Fa-f\\-]{36}$"
#define MAC_CONTAINER_FMT "^/Users/[^/]+/Library/Containers/[^/]+/Data$"
#define SIM_CONTAINER_FMT "^/Users/[^/]+/Library/Developer/CoreSimulator/Devices/[0-9A-Fa-f\\-]{36}/data/Containers/Data/Application/[0-9A-Fa-f\\-]{36}$"
#define SIM_UNSANDBOX_FMT "^/Users/[^/]+/Library/Developer/CoreSimulator/Devices/[0-9A-Fa-f\\-]{36}/data$"
#define IOS_ROOTHIDEN_FMT "^/var/containers/Bundle/Application/\\.jbroot-[[:xdigit:]]{16}/var/mobile$"

#define SFPRO "SFProDisplay-Regular"

typedef enum {
	BATTMAN_APP,
	BATTMAN_SUBPROCESS,
} battman_type_t;

#ifdef DEBUG
#warning Remember to finalize ENABLE_BRIGHTNESS when releasing
#define ENABLE_BRIGHTNESS 1
#endif

__BEGIN_DECLS

#ifndef __OBJC__
void NSLog(CFStringRef fmt, ...);
#endif

extern CFTypeRef (*MGCopyAnswerPtr)(CFStringRef);
extern SInt32 (*MGGetSInt32AnswerPtr)(CFStringRef, SInt32);
extern CFPropertyListRef (*MGCopyMultipleAnswersPtr)(CFArrayRef, CFDictionaryRef);
extern CFStringRef (*MGGetStringAnswerPtr)(CFStringRef);
extern bool (*MGGetBoolAnswerPtr)(CFStringRef);

extern const char    *L_OK;
extern const char    *L_FAILED;
extern const char    *L_ERR;
extern const char    *L_NONE;
extern const char    *L_MA;
extern const char    *L_MAH;
extern const char    *L_MV;
extern const char    *L_TRUE;
extern const char    *L_FALSE;

extern os_log_t       gLog;
extern os_log_t       gLogDaemon;
extern battman_type_t gAppType;

extern bool use_libintl;
extern bool has_locale;

void                  show_alert(const char *title, const char *message, const char *cancel_button_title);
#ifdef __OBJC__
void show_alert_async(const char *title, const char *message, const char *button, void (^completion)(bool result));
#else
void show_alert_async(const char *title, const char *message, const char *button, void *completion);
#endif
void        show_alert_async_f(const char *title, const char *message, const char *button, void (*completion)(int));
void        show_fatal_overlay_async(const char *title, const char *message);

char       *preferred_language(void);
bool        libintl_available(void);
bool        gtk_available(void);

void        init_common_text(void);

void        app_exit(void);
bool        is_carbon(void);
void        open_url(const char *url);

bool        match_regex(const char *string, const char *pattern);

const char *second_to_datefmt(uint64_t second);

int         is_rosetta(void);

const char *battman_config_dir(void);
const char *lang_cfg_file(void);
int         open_lang_override(int flags, int mode);
int         preferred_language_code(void);

const char *target_type(void);

bool        is_debugged(void);
bool        is_platformized(void);
bool        is_main_process(void);
pid_t       get_pid_for_launchd_label(const char *label);
pid_t       get_pid_for_procname(const char *name);

int         add_notification(const char *bundleid, const char *title, const char *subtitle, const char *body);
int         add_notification_with_content(UNUserNotificationCenter *uc, UNMutableNotificationContent *content);

bool        metal_available(bool ignore_config);

id          perform_selector(SEL selector, id target, id arg1);
id          perform_selector2(SEL selector, id target, id arg1, id arg2);

__END_DECLS

#endif /* common_h */
