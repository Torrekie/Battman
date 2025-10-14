//
//  main.m
//  Battman
//
//  Created by Torrekie on 2025/1/18.
//

#include <TargetConditionals.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#if __has_include("constants.c")
#include "constants.c"
#endif
#if __has_include("mo_verification.h") && defined(USE_GETTEXT)
#include "mo_verification.h"
#define ENABLE_MO_CHECK
#endif

#include "common.h"
#include "intlextern.h"
#include <libgen.h>
#include <dlfcn.h>
#if __has_include(<mach-o/dyld.h>)
#include <mach-o/dyld.h>
#else
extern int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
#endif

#import <UserNotifications/UserNotifications.h>

struct localization_entry {
	CFStringRef *cfstr;
	const char **pstr;
};

// Why 2 versions:
// CFString is UTF-16LE but we use UTF-8 in other cases
struct localization_arr_entry {
	const char *pstr;
	CFStringRef cfstr;
};

extern struct localization_arr_entry localization_arr[];

#define PSTRMAP_SIZE 1024
struct localization_entry pstrmap[PSTRMAP_SIZE] = {0};

#ifndef USE_GETTEXT
extern int cond_localize_cnt;
extern int cond_localize_language_cnt;

inline static int localization_simple_hash(const char *str) {
	return (((unsigned long long)str) >> 3) & 0x3ff;
}

__attribute__((destructor)) static void localization_deinit() {
	for (int i = 0; i < PSTRMAP_SIZE; i++) {
		if (pstrmap[i].pstr) {
			free(pstrmap[i].pstr);
		}
	}
}

__attribute__((constructor)) static void localization_init() {
	for(int i = 0; i < cond_localize_cnt; i++) {
		const char *cstr = localization_arr[i].pstr;
		struct localization_entry *ent = pstrmap + localization_simple_hash(cstr);
		while (ent->pstr) {
			ent++;
			if (ent == pstrmap + PSTRMAP_SIZE)
				ent = pstrmap;
		}
		ent->pstr = malloc(sizeof(void *)*(cond_localize_language_cnt<<1));
		ent->cfstr = (CFStringRef *)(ent->pstr + cond_localize_language_cnt);
		for (int j = 0; j < cond_localize_language_cnt; j++) {
			CFStringRef cfstr = localization_arr[cond_localize_cnt * j + i].cfstr;
			ent->pstr[j] = localization_arr[cond_localize_cnt * j + i].pstr;
			ent->cfstr[j] = cfstr;
		}
	}
}

struct localization_entry *cond_localize_find(const char *str) {
	struct localization_entry *ent = pstrmap + localization_simple_hash(str);
	for (; ent->pstr; ent++) {
		if (ent == pstrmap + PSTRMAP_SIZE) {
			ent = pstrmap;
			if (!ent->pstr)
				break;
		}
		if (*(ent->pstr) != str)
			continue;
		return ent;
	}
	return NULL;
}

NSString *cond_localize(const char *str) {
	int preferred_language = preferred_language_code(); // current: 0=eng 1=cn
	struct localization_entry *ent;
	if ((ent = cond_localize_find(str))) {
		return (__bridge NSString *)ent->cfstr[preferred_language];
	}
	return [NSString stringWithUTF8String:str];
}

const char *cond_localize_c(const char *str) {
	int preferred_language = preferred_language_code(); // current: 0=eng 1=cn
	struct localization_entry *ent;
	if ((ent = cond_localize_find(str))) {
		return ent->pstr[preferred_language];
	}
	return str;
}
#else
/* Use gettext i18n for App & CLI consistency */
/* While running as CLI, NSBundle is unset,
   which means we cannot use Localizables.strings
   and NSLocalizedString() at such scene. */
/* TODO: try implement void *cond_localize(void *strOrCFSTR)? */
bool use_libintl = false;
bool has_locale = true;

static void gettext_setlocale(char *locale) {
	char mainBundle[PATH_MAX];
	uint32_t size = sizeof(mainBundle);
	char binddir[PATH_MAX];

	if (_NSGetExecutablePath(mainBundle, &size) == KERN_SUCCESS) {
		char *bundledir = dirname(mainBundle);
		/* Either /Applications/Battman.app/locales or ./locales */
		sprintf(binddir, "%s/%s", bundledir ? bundledir : ".", "locales");

		// Check if locale directory for the target language exists
		char localeDir[PATH_MAX];
		snprintf(localeDir, sizeof(localeDir), "%s/%s/LC_MESSAGES", binddir, locale ? locale : "en");
		struct stat st;
		if (stat(localeDir, &st) != 0 || !S_ISDIR(st.st_mode)) {
			locale = "en";
		}
		/* For some reason, libintl's locale guess was not quite working,
		 this is a workaround to force it read correct language */
		setlocale(LC_ALL, locale);
		setenv("LANGUAGE", locale, 1);
		//setenv("LANG", lang, 1);

		DBGLOG(@"NSLocale.currentLocale: language=%@ numbering=%@", [NSLocale.currentLocale valueForKey:@"languageIdentifier"], [NSLocale.currentLocale valueForKey:@"numberingSystem"]);
		DBGLOG(@"NSLocale.currentLocale: availableNumberingSystems=%@", [NSLocale.currentLocale valueForKey:@"availableNumberingSystems"]);

		char *bindbase = bindtextdomain_ptr(BATTMAN_TEXTDOMAIN, binddir);
		if (bindbase) {
			DBGLOG(@"i18n base dir: %s", bindbase);
			char __unused *dom = textdomain_ptr(BATTMAN_TEXTDOMAIN);
			DBGLOG(@"textdomain: %s", dom);
			char __unused *enc = bind_textdomain_codeset_ptr(BATTMAN_TEXTDOMAIN, "UTF-8");
			DBGLOG(@"codeset: %s", enc);
			use_libintl = true;
		} else {
			show_alert("Error", "Failed to get i18n base", "Cancel");
		}
	} else {
		show_alert("Error", "Unable to get executable path", "Cancel");
	}
}

static void gettext_init(void) {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        if (libintl_available()) {
#ifdef DEBUG
            assert(bindtextdomain_ptr != NULL);
            assert(textdomain_ptr != NULL);
            assert(gettext_ptr != NULL);
#endif
			gettext_setlocale(preferred_language());
#ifdef _
#undef _
#endif
// Redefine _() for PO template generation
#define _(x) gettext_ptr(x)
            /* locale_name should not be "locale_name" if target language has been translated */
            char *locale_name = _("locale_name");
            DBGLOG(@"Locale Name: %s", locale_name);
            if (use_libintl && !strcmp("locale_name", locale_name)) {
				NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
				if (![defaults objectForKey:@"com.torrekie.Battman.warned_no_locale"]) {
					show_alert("Error", "Unable to match existing Gettext localization, defaulting to English", "Cancel");
					[defaults setBool:YES forKey:@"com.torrekie.Battman.warned_no_locale"];
					[defaults synchronize];
				}
				has_locale = false;
            }
#if defined(ENABLE_MO_CHECK)
            else if (use_libintl && gAppType == BATTMAN_APP) {
				char mo_fullpath[PATH_MAX];
				snprintf(mo_fullpath, sizeof(mo_fullpath), "%s/locales/%s/LC_MESSAGES/battman.mo", NSBundle.mainBundle.bundlePath.UTF8String, preferred_language());
				switch (verify_embedded_mo_by_locale_hash(preferred_language(), mo_fullpath)) {
					case 114: {
						break;
					}
					case 1919: {
						// This looks exactlly same with above, but multi-factored
						NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
						os_log_error(gLog, "1919");
#ifndef DEBUG
						if (![defaults objectForKey:@"com.torrekie.Battman.warned_no_locale"])
#endif
						{
							show_alert("Error", [NSString stringWithFormat:@"Unable to match existing Gettext localization for %s, defaulting to English", preferred_language()].UTF8String, "Cancel");
							[defaults setBool:YES forKey:@"com.torrekie.Battman.warned_no_locale"];
							[defaults synchronize];
						}
						has_locale = false;
						break;
					}
					case 810: {
						os_log_error(gLog, "810");
						NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
#ifndef DEBUG
						if (![defaults objectForKey:@"com.torrekie.Battman.warned_3rd_locale"])
#endif
						{
							show_alert(_("Unregistered Locale"), _("You are using a localization file which not officially provided by Battman, the translations may inaccurate."), _("OK"));
							[defaults setBool:YES forKey:@"com.torrekie.Battman.warned_3rd_locale"];
							[defaults synchronize];
						}
						break;
					}
					case 514:
					default: {
						// I don't like you to modify my ellegant locales
						extern void push_fatal_notif(void);
						push_fatal_notif();
						break;
					}
				}
            }
#endif

#undef _
#define _(x) cond_localize(x)
        } else {
            show_alert("Warning", "Failed to load Gettext, defaulting to English", "OK");
			has_locale = false;
        }
    });
}

NSString *cond_localize(const char *str) {
    gettext_init();
    return [NSString stringWithCString:(use_libintl ? gettext_ptr(str) : str) encoding:NSUTF8StringEncoding];
}

const char *cond_localize_c(const char *str) {
    gettext_init();
    return (const char *)(use_libintl ? gettext_ptr(str) : str);
}
#endif

CFTypeRef (*MGCopyAnswerPtr)(CFStringRef) = NULL;
SInt32 (*MGGetSInt32AnswerPtr)(CFStringRef, SInt32) = NULL;
CFPropertyListRef (*MGCopyMultipleAnswersPtr)(CFArrayRef, CFDictionaryRef) = NULL;
CFStringRef (*MGGetStringAnswerPtr)(CFStringRef) = NULL;

__attribute__((constructor))
void load_mg(void) {
#if 1
	void *mobileGestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
	if (mobileGestalt) {
		MGCopyAnswerPtr = dlsym(mobileGestalt, "MGCopyAnswer");
		MGGetSInt32AnswerPtr = dlsym(mobileGestalt, "MGGetSInt32Answer");
		MGCopyMultipleAnswersPtr = dlsym(mobileGestalt, "MGCopyMultipleAnswers");
		MGGetStringAnswerPtr = dlsym(mobileGestalt, "MGGetStringAnswer");
	}
#else
#error Before we find another way to get those info, MobileGestalt cannot be avoided
#endif
}

#ifdef DEBUG
NSMutableAttributedString *redirectedOutput;
void (^redirectedOutputListener)(void)=nil;
#endif

#include "security/selfcheck.h"
#include "security/protect.h"

os_log_t gLog;
os_log_t gLogDaemon;
battman_type_t gAppType = BATTMAN_SUBPROCESS;

int main(int argc, char * argv[]) {
	gLog = os_log_create("com.torrekie.Battman", "default");
	if (gLog == NULL) {
		os_log_error(OS_LOG_DEFAULT, "Couldn't create os log object");
	}

	pull_fatal_notif();
    // FIXME: use getopt()
	if (argc == 3 && strcmp(argv[1], "--worker") == 0) {
		extern void battman_run_worker(const char *);
		battman_run_worker(argv[2]);
		return 0;
	} else if (argc == 2 && strcmp(argv[1], "--daemon") == 0) {
		gLogDaemon = os_log_create("com.torrekie.Battman", "Daemon");
		if (gLogDaemon == NULL) {
			os_log_error(OS_LOG_DEFAULT, "Couldn't create daemon os log object");
		}
		extern void daemon_main(void);
		daemon_main();
		return 0;
	}
	gAppType = BATTMAN_APP;
#if defined(DEBUG)
#if !TARGET_OS_SIMULATOR
    // Redirecting is not needed for Simulator
    chdir(getenv("HOME"));
    char *tty = ttyname(0);
    if (tty) {
        show_alert("Current TTY", tty, "OK");
    } else {
        redirectedOutput = [[NSMutableAttributedString alloc] init];
        // Create a pipe for redirecting output
        static int pipe_fd[2];
        pipe(pipe_fd);

        // Save the original stdout and stderr file descriptors
        int __unused original_stdout = dup(STDOUT_FILENO);
        int __unused original_stderr = dup(STDERR_FILENO);

        // Redirect stdout and stderr to the pipe
        dup2(pipe_fd[1], STDOUT_FILENO);
        dup2(pipe_fd[1], STDERR_FILENO);

        // Create a new dispatch queue to read from the pipe
        dispatch_queue_t queue = dispatch_queue_create("outputRedirectQueue", NULL);
        dispatch_async(queue, ^{
            char buffer[1024];
            ssize_t bytesRead;

            while ((bytesRead = read(pipe_fd[0], buffer, sizeof(buffer))) > 0) {
                // Append output to NSMutableAttributedString
                NSString *output = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
                NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:output];
                [redirectedOutput appendAttributedString:attrString];
                if(redirectedOutput.length>50000)
                	[redirectedOutput deleteCharactersInRange:NSMakeRange(0,10000)];
                if(redirectedOutputListener) {
		        dispatch_async(dispatch_get_main_queue(),^{
		        	// (in case that our block is invalidated while we're waiting)
		        	if(redirectedOutputListener)
		        		redirectedOutputListener();
		        });
		}
            }
        });

        // Close the write end of the pipe
        close(pipe_fd[1]);
    }
#else
    redirectedOutput = [[NSMutableAttributedString alloc] initWithString:_("stdio logs not redirected in Simulator build, please check stdio in Xcode console output instead.")];
#endif // TARGET_OS_SIMULATOR
#endif // DEBUG
    // sleep(10);
    if (is_carbon()) {
#if TARGET_OS_IPHONE
		//protect_method(UIViewController,presentViewController:animated:completion:,push_fatal_notif);
		protect_method(UIWindow,alloc,NULL);
		protect_method(UIWindow,makeKeyAndVisible,push_fatal_notif);
//		protect_method(NSURLSession,dataTaskWithURL:completionHandler:,NULL);
//		protect_method(NSURLSession,dataTaskWithRequest:completionHandler:,NULL);
//		protect_method(NSURLSession,resume,NULL);
		extern NSString *battman_bootstrap(char *, int);
        return UIApplicationMain(argc, argv, nil, battman_bootstrap("", 0));
#else
        @autoreleasepool {
        }
        return NSApplicationMain(argc, argv);
#endif
    }

    /* Not running as App, CLI/Daemon code */
    {
        // TODO: cli + x11
        fprintf(stderr, "%s\n", _C("Battman CLI not implemented yet."));
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
