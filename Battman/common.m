#include <TargetConditionals.h>
#include <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#include <UIKit/UIKit.h>
extern UIWindow *gWindow;
#elif TARGET_OS_OSX
#include <Cocoa/Cocoa.h>
#endif

#include "common.h"
#include "intlextern.h"
#include "gtkextern.h"

/* Consider make this a standalone header */
#define SYM_EXIST(...) check_ptr(__VA_ARGS__)

#define PTR_TYPE_NAME(x, y) x ## _ptr = y; DBGLOG(@"%s_ptr (%p) = %s (%p)", #x, x, #y, y);
#define PTR_TYPE(x) PTR_TYPE_NAME(x, x)
#define PTR_TYPE_NAME_DLSYM(handle, y, x) ((y ## _ptr = (typeof(x)*)dlsym(handle, #x)) != NULL)
#define PTR_TYPE_DLSYM(handle, x) PTR_TYPE_NAME_DLSYM(handle, x, x)

typeof(gettext) *gettext_ptr;
typeof(textdomain) *textdomain_ptr;
typeof(bindtextdomain) *bindtextdomain_ptr;

typeof(gtk_dialog_get_type) *gtk_dialog_get_type_ptr;
typeof(gtk_message_dialog_new) *gtk_message_dialog_new_ptr;
typeof(gtk_dialog_add_button) *gtk_dialog_add_button_ptr;
typeof(gtk_dialog_run) *gtk_dialog_run_ptr;
typeof(gtk_widget_destroy) *gtk_widget_destroy_ptr;

static char *get_CFLocale()
{
    CFArrayRef list = CFLocaleCopyPreferredLanguages();
    
    if (list == NULL || CFArrayGetCount(list) == 0)
        return NULL;

    char *lang = (char *)malloc(256 * sizeof(char));

    if (!CFStringGetCString(CFArrayGetValueAtIndex(list, 0), lang, 256, kCFStringEncodingUTF8)) {
        CFRelease(list);
        return NULL;
    }

    CFRelease(list);
    return lang;
}

char *preferred_language (void)
{
    /* Convert new-style locale names with language tags (ISO 639 and ISO 15924)
       to Unix (ISO 639 and ISO 3166) names.  */
    typedef struct { const char langtag[10+1]; const char unixy[12+1]; }
            langtag_entry;
    static const langtag_entry langtag_table[] = {
      /* Mac OS X has "az-Arab", "az-Cyrl", "az-Latn".
         The default script for az on Unix is Latin.  */
      { "az-Latn", "az" },
      /* Mac OS X has "bs-Cyrl", "bs-Latn".
         The default script for bs on Unix is Latin.  */
      { "bs-Latn", "bs" },
      /* Mac OS X has "ga-dots".  Does not yet exist on Unix.  */
      { "ga-dots", "ga" },
      /* Mac OS X has "kk-Cyrl".
         The default script for kk on Unix is Cyrillic.  */
      { "kk-Cyrl", "kk" },
      /* Mac OS X has "mn-Cyrl", "mn-Mong".
         The default script for mn on Unix is Cyrillic.  */
      { "mn-Cyrl", "mn" },
      /* Mac OS X has "ms-Arab", "ms-Latn".
         The default script for ms on Unix is Latin.  */
      { "ms-Latn", "ms" },
      /* Mac OS X has "pa-Arab", "pa-Guru".
         Country codes are used to distinguish these on Unix.  */
      { "pa-Arab", "pa_PK" },
      { "pa-Guru", "pa_IN" },
      /* Mac OS X has "shi-Latn", "shi-Tfng".  Does not yet exist on Unix.  */
      /* Mac OS X has "sr-Cyrl", "sr-Latn".
         The default script for sr on Unix is Cyrillic.  */
      { "sr-Cyrl", "sr" },
      /* Mac OS X has "tg-Cyrl".
         The default script for tg on Unix is Cyrillic.  */
      { "tg-Cyrl", "tg" },
      /* Mac OS X has "tk-Cyrl".
         The default script for tk on Unix is Cyrillic.  */
      { "tk-Cyrl", "tk" },
      /* Mac OS X has "tt-Cyrl".
         The default script for tt on Unix is Cyrillic.  */
      { "tt-Cyrl", "tt" },
      /* Mac OS X has "uz-Arab", "uz-Cyrl", "uz-Latn".
         The default script for uz on Unix is Latin.  */
      { "uz-Latn", "uz" },
      /* Mac OS X has "vai-Latn", "vai-Vaii".  Does not yet exist on Unix.  */
      /* Mac OS X has "yue-Hans", "yue-Hant".
         The default script for yue on Unix is Simplified Han.  */
      { "yue-Hans", "yue" },
      /* Mac OS X has "zh-Hans", "zh-Hant".
         Country codes are used to distinguish these on Unix.  */
      { "zh-Hans", "zh_CN" },

      { "zh-Hant", "zh_TW" },
      { "zh-Hant-HK", "zh_HK" },
    };
    /* Convert script names (ISO 15924) to Unix conventions.
       See https://www.unicode.org/iso15924/iso15924-codes.html  */
    typedef struct { const char script[4+1]; const char unixy[9+1]; }
            script_entry;
    static const script_entry script_table[] = {
      { "Arab", "arabic" },
      { "Cyrl", "cyrillic" },
      { "Latn", "latin" },
      { "Mong", "mongolian" }
    };
    char *name = get_CFLocale();
    /* Step 2: Convert using langtag_table and script_table.  */
    if ((strlen (name) == 7 || strlen (name) == 10) && name[2] == '-')
      {
        unsigned int i1, i2;
        i1 = 0;
        i2 = sizeof (langtag_table) / sizeof (langtag_entry);
        while (i2 - i1 > 1)
          {
            /* At this point we know that if name occurs in langtag_table,
               its index must be >= i1 and < i2.  */
            unsigned int i = (i1 + i2) >> 1;
            const langtag_entry *p = &langtag_table[i];
            if (strcmp (name, p->langtag) < 0)
              i2 = i;
            else
              i1 = i;
          }
        if (strncmp (name, langtag_table[i1].langtag, strlen(langtag_table[i1].langtag)) == 0)
          {
            strcpy (name, langtag_table[i1].unixy);
            return name;
          }

        i1 = 0;
        i2 = sizeof (script_table) / sizeof (script_entry);
        while (i2 - i1 > 1)
          {
            /* At this point we know that if (name + 3) occurs in script_table,
               its index must be >= i1 and < i2.  */
            unsigned int i = (i1 + i2) >> 1;
            const script_entry *p = &script_table[i];
            if (strcmp (name + 3, p->script) < 0)
              i2 = i;
            else
              i1 = i;
          }
        if (strcmp (name + 3, script_table[i1].script) == 0)
          {
            name[2] = '@';
            strcpy (name + 3, script_table[i1].unixy);
            return name;
          }
      }

    /* Step 3: Convert new-style dash to Unix underscore. */
    {
      char *p;
      for (p = name; *p != '\0'; p++)
        if (*p == '-')
          *p = '_';
    }
    return name;
}


/* https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/Concepts/WeakLinking.html
    Note: When checking for the existence of a symbol, you must explicitly compare it to NULL or nil in your code. You cannot use the negation operator ( ! ) to negate the address of the symbol.
*/
bool check_ptr(void* ptr1, ...) {
    va_list args;
    va_start(args, ptr1);

    // Check the first pointer
    if (ptr1 == NULL) {
        return false;  // Return false if the first pointer is NULL
    }

    // Check subsequent pointers
    void* ptr;
    while ((ptr = va_arg(args, void*)) != NULL) {
        if (ptr == NULL) {
            va_end(args);
            return false;  // Return false if any pointer is NULL
        }
    }

    va_end(args);
    return true;  // Return true if all pointers are non-NULL
}

/* Conditional libintl */
bool libintl_available(void)
{
    static bool avail = false;
    static void *libintl_handle = NULL;

    if (avail) return avail;
    
    if (PTR_TYPE_DLSYM(NULL, gettext) &&
    	PTR_TYPE_DLSYM(NULL, bindtextdomain) &&
    	PTR_TYPE_DLSYM(NULL, textdomain)) {
    	avail=true;
        DBGLOG(@"Avail as direct: %p %p %p", gettext_ptr, bindtextdomain_ptr, textdomain_ptr);
    } else if (PTR_TYPE_NAME_DLSYM(NULL, gettext, libintl_gettext) &&
               PTR_TYPE_NAME_DLSYM(NULL, bindtextdomain, libintl_bindtextdomain) &&
               PTR_TYPE_NAME_DLSYM(NULL, textdomain, libintl_textdomain)) {
    	avail=true;
        DBGLOG(@"Avail as direct (libintl_*): %p %p %p", gettext_ptr, bindtextdomain_ptr, textdomain_ptr);
    }

    /*if (SYM_EXIST(gettext, bindtextdomain, textdomain)) {
        DBGLOG(@"Avail as direct: %p %p %p", gettext, bindtextdomain, textdomain);
        avail = true;
        PTR_TYPE(gettext);
        PTR_TYPE(bindtextdomain);
        PTR_TYPE(textdomain);
    } else if (SYM_EXIST(libintl_gettext, libintl_bindtextdomain, libintl_textdomain)) {
        DBGLOG(@"Avail as direct (libintl_*): %p %p %p", libintl_gettext, libintl_bindtextdomain, libintl_textdomain);
        avail = true;
        PTR_TYPE_NAME(gettext, libintl_gettext);
        PTR_TYPE_NAME(bindtextdomain, libintl_bindtextdomain);
        PTR_TYPE_NAME(textdomain, libintl_textdomain);
    }*/

    if (!avail) {
        if (!libintl_handle) {
            int i;
            for (i = 0; libintl_paths[i] != NULL; i++) {
                libintl_handle = dlopen(libintl_paths[i], RTLD_LAZY);
                if (libintl_handle) break;
            }
            DBGLOG(@"Using libintl: %s", libintl_paths[i]);
        }

        if (libintl_handle) {
            if (PTR_TYPE_DLSYM(libintl_handle, gettext) &&
                PTR_TYPE_DLSYM(libintl_handle, bindtextdomain) &&
                PTR_TYPE_DLSYM(libintl_handle, textdomain)) {
                avail = true;
                DBGLOG(@"Avail as dlsym: %p %p %p", gettext_ptr, bindtextdomain_ptr, textdomain_ptr);
            } else if (PTR_TYPE_NAME_DLSYM(libintl_handle, gettext, libintl_gettext) &&
                       PTR_TYPE_NAME_DLSYM(libintl_handle, bindtextdomain, libintl_bindtextdomain) &&
                       PTR_TYPE_NAME_DLSYM(libintl_handle, textdomain, libintl_textdomain)) {
                DBGLOG(@"Avail as dlsym (libintl_*): %p %p %p", gettext_ptr, bindtextdomain_ptr, textdomain_ptr);
                avail = true;
            }
        }
    }
    return avail;
}

/* Conditional libgtk */
bool gtk_available(void)
{
    static bool avail = false;
    static void *libgtk3_handle = NULL;

    if (avail) return avail;

    /*if (SYM_EXIST(gtk_dialog_get_type, gtk_message_dialog_new, gtk_dialog_add_button, gtk_dialog_run, gtk_widget_destroy)) {
        avail = true;
        PTR_TYPE(gtk_dialog_get_type);
        PTR_TYPE(gtk_message_dialog_new);
        PTR_TYPE(gtk_dialog_add_button);
        PTR_TYPE(gtk_dialog_run);
        PTR_TYPE(gtk_widget_destroy);
    }*/
    if (PTR_TYPE_DLSYM(NULL, gtk_dialog_get_type) &&
        PTR_TYPE_DLSYM(NULL, gtk_message_dialog_new) &&
        PTR_TYPE_DLSYM(NULL, gtk_dialog_add_button) &&
        PTR_TYPE_DLSYM(NULL, gtk_dialog_run) &&
        PTR_TYPE_DLSYM(NULL, gtk_widget_destroy)) avail = true;

    if (!avail) {
        if (!libgtk3_handle) {
            for (int i = 0; libgtk3_paths[i] != NULL; i++) {
                libgtk3_handle = dlopen(libgtk3_paths[i], RTLD_LAZY);
                if (libgtk3_handle) break;
            }
        }

        if (libgtk3_handle) {
            if (PTR_TYPE_DLSYM(libgtk3_handle, gtk_dialog_get_type) &&
                PTR_TYPE_DLSYM(libgtk3_handle, gtk_message_dialog_new) &&
                PTR_TYPE_DLSYM(libgtk3_handle, gtk_dialog_add_button) &&
                PTR_TYPE_DLSYM(libgtk3_handle, gtk_dialog_run) &&
                PTR_TYPE_DLSYM(libgtk3_handle, gtk_widget_destroy)) avail = true;
        }
    }
    return avail;
}

/* Alert for multiple scene */
/* TODO: Check if program running under SSH */
bool show_alert(const char *title, const char *message, const char *cancel_button_title) {
    DBGLOG(@"show_alert called: [%s], [%s], [%s]", title, message, cancel_button_title);

    /* Alert in GTK+ if under X Window */
    if (gtk_available() && getenv("DISPLAY")) {
        GtkWidget *dialog = gtk_message_dialog_new_ptr(NULL, GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_NONE, "%s", message);
        gtk_dialog_add_button_ptr(GTK_DIALOG(dialog), cancel_button_title, GTK_RESPONSE_CANCEL);
        // gtk_dialog_add_button(GTK_DIALOG(dialog), "OK", GTK_RESPONSE_ACCEPT);
        
        int response = gtk_dialog_run_ptr(GTK_DIALOG(dialog));
        gtk_widget_destroy_ptr(dialog);
        return response == GTK_RESPONSE_CANCEL;
    }
#if TARGET_OS_IPHONE
    /* Alert using system UIAlert */
    if (@available(iOS 9.0, *)) {
        // Use UIAlertController if iOS 10 or later
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[NSString stringWithUTF8String:title]
                                                                                 message:[NSString stringWithUTF8String:message]
                                                                          preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[NSString stringWithUTF8String:cancel_button_title] style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}];
        [alertController addAction:cancelAction];

        UIViewController *rootViewController = gWindow.rootViewController;
        [rootViewController presentViewController:alertController animated:YES completion:nil];

        /* TODO: check button */
        return true;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // Use UIAlertView for iOS 9 or earlier
        /* TODO: Add a delegate */
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSString stringWithUTF8String:title]
                                                        message:[NSString stringWithUTF8String:message]
                                                       delegate:nil
                                              cancelButtonTitle:[NSString stringWithUTF8String:cancel_button_title]
                                              otherButtonTitles:@"OK", nil];
        [alert show];
        /* TODO: check button */
        return true;
#pragma clang diagnostic pop
    }
#elif TARGET_OS_OSX
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithUTF8String:title]];
    [alert setInformativeText:[NSString stringWithUTF8String:message]];
    [alert addButtonWithTitle:[NSString stringWithUTF8String:cancel_button_title]];
    [alert runModal];
    /* TODO: check button */
    return true;
#endif
}
