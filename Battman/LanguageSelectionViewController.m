//
//  LanguageSelectionViewController.m
//  Battman
//
//  Created by Torrekie on 2025/10/26.
//

#import "LanguageSelectionViewController.h"
#import "common.h"
#import "intlextern.h"
#import "BattmanPrefs.h"
#import "main.h"
#include <libgen.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef USE_GETTEXT
#pragma mark - Gettext MO Parsing

/* Torrekie: Wait...Why we still using libintl to load MO files
 * when we already implemented our own parsing logics? */

// Available locales cache
static NSArray<NSString *> *availableLocales = nil;

// Helper function to get MO file path for a locale
static NSString *getMOFilePathForLocale(NSString *localeCode) {
    char mainBundle[PATH_MAX];
    uint32_t size = sizeof(mainBundle);
    if (_NSGetExecutablePath(mainBundle, &size) != KERN_SUCCESS) {
        return nil;
    }
    
    char *bundledir = dirname(mainBundle);
    char moFilePath[PATH_MAX];
    snprintf(moFilePath, sizeof(moFilePath), "%s/locales/%s/LC_MESSAGES/%s.mo", 
             bundledir ? bundledir : ".", localeCode.UTF8String, BATTMAN_TEXTDOMAIN);
    
    return [NSString stringWithUTF8String:moFilePath];
}

// Function to get available locales from the locales directory
static NSArray<NSString *> *getAvailableLocales(void) {
    if (availableLocales != nil) {
        return availableLocales;
    }
    
    NSMutableArray<NSString *> *locales = [NSMutableArray array];
    
    // Get the locales directory path
    char mainBundle[PATH_MAX];
    uint32_t size = sizeof(mainBundle);
    if (_NSGetExecutablePath(mainBundle, &size) == KERN_SUCCESS) {
        char *bundledir = dirname(mainBundle);
        char binddir[PATH_MAX];
        sprintf(binddir, "%s/%s", bundledir ? bundledir : ".", "locales");
        
        NSString *localesDir = [NSString stringWithUTF8String:binddir];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error;
        
        NSArray<NSString *> *contents = [fileManager contentsOfDirectoryAtPath:localesDir error:&error];
        if (contents && !error) {
            for (NSString *item in contents) {
                NSString *fullPath = [localesDir stringByAppendingPathComponent:item];
                BOOL isDirectory;
                if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory] && isDirectory) {
                    // Use shared MO file path logic
                    NSString *moPath = getMOFilePathForLocale(item);
                    if (moPath && [fileManager fileExistsAtPath:moPath]) {
                        [locales addObject:item];
                    }
                }
            }
        }
    }

    [locales sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    availableLocales = [locales copy];
    return availableLocales;
}

// MO file format constants
#define MO_MAGIC_LITTLE_ENDIAN 0x950412de
#define MO_MAGIC_BIG_ENDIAN    0xde120495

// MO file header structure
typedef struct {
    uint32_t magic;
    uint32_t version;
    uint32_t num_strings;
    uint32_t orig_table_offset;
    uint32_t trans_table_offset;
    uint32_t hash_table_size;
    uint32_t hash_table_offset;
} mo_header_t;

// String table entry
typedef struct {
    uint32_t length;
    uint32_t offset;
} mo_string_entry_t;

#define swap_bytes(value) ((value & 0xFF) << 24) | (((value >> 8) & 0xFF) << 16) | (((value >> 16) & 0xFF) << 8) | ((value >> 24) & 0xFF)

// Function to get localized message in specific language (with inlined MO parsing)
NSString *getLocalizedMessageForLanguage(NSString *localeCode, const char *message) {
    if (!localeCode) {
        return _(message);
    }
    
    // Get the MO file path for this locale
    NSString *moFilePathString = getMOFilePathForLocale(localeCode);
    if (!moFilePathString) {
        return _(message);
    }
    
    // Check if MO file exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:moFilePathString]) {
        return _(message);
    }
    
    // Inline MO file parsing logic
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:moFilePathString];
    if (!fileHandle) {
        return _(message);
    }
    
    @try {
        NSData *headerData = [fileHandle readDataOfLength:sizeof(mo_header_t)];
        if (headerData.length < sizeof(mo_header_t)) {
            return _(message);
        }
        
        mo_header_t header;
        memcpy(&header, headerData.bytes, sizeof(mo_header_t));
        
        bool swap_endian = false;
        if (header.magic == MO_MAGIC_BIG_ENDIAN) {
            swap_endian = true;
        } else if (header.magic != MO_MAGIC_LITTLE_ENDIAN) {
            return _(message); // Invalid MO file
        }
        
        if (swap_endian) {
            header.version = swap_bytes(header.version);
            header.num_strings = swap_bytes(header.num_strings);
            header.orig_table_offset = swap_bytes(header.orig_table_offset);
            header.trans_table_offset = swap_bytes(header.trans_table_offset);
        }

        [fileHandle seekToFileOffset:header.orig_table_offset];
        NSData *origTableData = [fileHandle readDataOfLength:header.num_strings * sizeof(mo_string_entry_t)];
        if (origTableData.length < header.num_strings * sizeof(mo_string_entry_t)) {
            return _(message);
        }

        [fileHandle seekToFileOffset:header.trans_table_offset];
        NSData *transTableData = [fileHandle readDataOfLength:header.num_strings * sizeof(mo_string_entry_t)];
        if (transTableData.length < header.num_strings * sizeof(mo_string_entry_t)) {
            return _(message);
        }
        
        mo_string_entry_t *origTable = (mo_string_entry_t *)origTableData.bytes;
        mo_string_entry_t *transTable = (mo_string_entry_t *)transTableData.bytes;
        
        size_t messageLen = strlen(message);

        for (uint32_t i = 0; i < header.num_strings; i++) {
            mo_string_entry_t origEntry = origTable[i];
            mo_string_entry_t transEntry = transTable[i];
            
            if (swap_endian) {
                origEntry.length = swap_bytes(origEntry.length);
                origEntry.offset = swap_bytes(origEntry.offset);
                transEntry.length = swap_bytes(transEntry.length);
                transEntry.offset = swap_bytes(transEntry.offset);
            }

            [fileHandle seekToFileOffset:origEntry.offset];
            NSData *origStringData = [fileHandle readDataOfLength:origEntry.length];
            if (origStringData.length < origEntry.length) {
                continue;
            }
            
            if (origEntry.length == messageLen && memcmp(origStringData.bytes, message, messageLen) == 0) {
                [fileHandle seekToFileOffset:transEntry.offset];
                NSData *transStringData = [fileHandle readDataOfLength:transEntry.length];
                if (transStringData.length >= transEntry.length && transEntry.length > 0) {
                    char *transString = malloc(transEntry.length + 1);
                    memcpy(transString, transStringData.bytes, transEntry.length);
                    transString[transEntry.length] = '\0';
                    
                    NSString *result = [NSString stringWithUTF8String:transString];
                    free(transString);
                    return result;
                }
            }
        }
        
        return _(message); // Message not found
        
    } @finally {
        [fileHandle closeFile];
    }
}

// Function to get display name for locale
NSString *getDisplayNameForLocale(NSString *localeCode) {
    // First try to get the native name from the mo file
    NSString *moName = getLocalizedMessageForLanguage(localeCode, "locale_name");
    if (moName && ![moName isEqualToString:@"locale_name"]) {
        return [NSString stringWithFormat:@"%@ (%@)", moName, localeCode];
    }
    
    // Fallback to NSLocale
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSString *displayName = [currentLocale displayNameForKey:NSLocaleIdentifier value:localeCode];
    
    if (displayName && ![displayName isEqualToString:localeCode]) {
        return [NSString stringWithFormat:@"%@ (%@)", displayName, localeCode];
    }

    NSDictionary *fallbackNames = @{
        @"en": @"English (en)",
        @"zh_CN": @"中文 (zh_CN)",
    };
    
    NSString *fallback = fallbackNames[localeCode];
    return fallback ? fallback : localeCode;
}
#else
extern int cond_localize_cnt;
extern int cond_localize_language_cnt;
extern CFStringRef **cond_localize_find(const char *str);
#endif
extern void preferred_language_code_clear(void);

@implementation LanguageSelectionViewController;

- (NSString *)title {
	return _("Preferred Language");
}

- (NSInteger)tableView:(id)tv numberOfRowsInSection:(NSInteger)section {
#ifdef USE_GETTEXT
	return getAvailableLocales().count + 1;
#else
	return cond_localize_language_cnt + 1;
#endif
}

- (NSInteger)numberOfSectionsInTableView:(id)tv {
	return 1;
}

- (UITableViewCell *)tableView:(id)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [UITableViewCell new];
#if !defined(USE_GETTEXT)
	if (indexPath.row == 0) {
		cell.textLabel.text = _("Clear");
		return cell;
	}

	cell.textLabel.text = (__bridge NSString *)(*cond_localize_find("English"))[indexPath.row - 1];
	if (preferred_language_code() + 1 == indexPath.row) {
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	}
#else
	if (indexPath.row == 0) {
		cell.textLabel.text = _("Default");
		// Check if no language override is set (system default)
		if ([BattmanPrefs.sharedPrefs objectForKey:@kBattmanPrefs_LANGUAGE] == nil) {
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		}
	} else {
		NSArray<NSString *> *locales = getAvailableLocales();
		NSInteger localeIndex = indexPath.row - 1;
		
		if (localeIndex < locales.count) {
			NSString *localeCode = locales[localeIndex];
			cell.textLabel.text = getDisplayNameForLocale(localeCode);
			
			NSString *currentLang = [BattmanPrefs.sharedPrefs objectForKey:@kBattmanPrefs_LANGUAGE];
			if (currentLang != nil && [localeCode isEqualToString:currentLang]) {
				cell.accessoryType = UITableViewCellAccessoryCheckmark;
			}
		}
	}
#endif
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
#if !defined(USE_GETTEXT)
	if (indexPath.row == 0) {
		remove(lang_cfg_file());
		preferred_language_code_clear();
		[tv reloadData];
		return;
	} else {
		int fd = open_lang_override(O_RDWR | O_CREAT, 0600);
		int n = (int)indexPath.row - 1;
		write(fd, &n, 4);
		close(fd);
		preferred_language_code_clear();
		[tv reloadData];
	}
#else
	BattmanPrefs *prefs = BattmanPrefs.sharedPrefs;
	if (indexPath.row == 0) {
		[prefs removeObjectForKey:@kBattmanPrefs_LANGUAGE];
		[prefs synchronize];
	} else {
		NSArray<NSString *> *locales = getAvailableLocales();
		NSInteger localeIndex = indexPath.row - 1;
		
		if (localeIndex < locales.count) {
			NSString *localeCode = locales[localeIndex];
			[prefs setString:localeCode forKey:@kBattmanPrefs_LANGUAGE];
			[prefs synchronize];
		}
	}

	[tv reloadData];
#endif
	[tv deselectRowAtIndexPath:indexPath animated:YES];
}

@end
