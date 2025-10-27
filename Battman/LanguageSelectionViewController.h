//
//  LanguageSelectionViewController.h
//  Battman
//
//  Created by Torrekie on 2025/10/26.
//

#import "common.h"
#import <UIKit/UIKit.h>

@interface LanguageSelectionViewController : UITableViewController

@end

#ifdef USE_GETTEXT
// Utility function to get display name for locale
NSString *getDisplayNameForLocale(NSString *localeCode);

// Utility function to get localized message from specific MO file
NSString *getLocalizedMessageForLanguage(NSString *localeCode, const char *message);
#endif
