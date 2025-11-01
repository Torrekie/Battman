//
//  PreferencesViewController.m
//  Battman
//
//  Created by Torrekie on 2025/10/16.
//

#import "common.h"
#import "BattmanPrefs.h"
#import "SegmentedTextField.h"
#import "PreferencesViewController.h"
#import "LanguageSelectionViewController.h"
#import "ThermAniTestViewController.h"
#import "UITextFieldStepper.h"
#import "FooterHyperlinkView.h"

static BOOL languageHasChanged = NO;

@interface PreferencesViewController () <UITextFieldDelegate>
@property (nonatomic, strong) FooterHyperlinkViewConfiguration *localeWarnConf;
@property (nonatomic, strong) FooterHyperlinkView *localeWarn;
@property (nonatomic, strong) FooterHyperlinkViewConfiguration *biIntervalFooterConf;
@property (nonatomic, strong) FooterHyperlinkView *biIntervalFooter;
@property (nonatomic, strong) SegmentedTextField *intervalSegmentedTextField;
@property (nonatomic, weak) UITextFieldStepper *thermMinStepper;
@property (nonatomic, weak) UITextFieldStepper *thermMaxStepper;
@property (nonatomic, assign) BOOL isUpdatingThermometerValues;
@property (nonatomic, strong) NSString *initialLanguagePreference;
@end

@interface UITableView ()
- (void)_reloadSectionHeaderFooters:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)rowAnimation;
@end

@interface MCMContainer : NSObject
+ (instancetype)containerWithIdentifier:(NSString *)identifier createIfNecessary:(BOOL)createIfNecessary existed:(BOOL *)existed error:(NSError **)error;
- (NSURL *)url;
@end

extern UITableViewCell *find_cell(UIView *view);

@implementation PreferencesViewController

- (NSString *)title {
	return _("Preferences");
}

- (instancetype)init {
	UITableViewStyle style = UITableViewStyleGrouped;
	if (@available(iOS 13.0, *))
		style = UITableViewStyleInsetGrouped;
	self = [super initWithStyle:style];
	if (self) {
		// Initialize locale warning configuration - will be updated in updateLocaleWarning
		self.localeWarnConf = [[FooterHyperlinkViewConfiguration alloc] init];
	}

	return self;
}

- (void)openIssueURL {
	open_url("https://github.com/Torrekie/Battman/issues/new");
}

- (void)updateLocaleWarning {
	// Determine what type of warning to show
	BOOL shouldShowLocaleWarning = (use_libintl && !has_locale);
	BOOL shouldShowLanguageChangeWarning = languageHasChanged;
	
	// If neither condition is met, clear the warning
	if (!shouldShowLocaleWarning && !shouldShowLanguageChangeWarning) {
		self.localeWarn = nil;
		return;
	}
	
	NSString *message;
	NSString *linkText = nil;
	NSRange linkRange = NSMakeRange(NSNotFound, 0);
	
	if (shouldShowLanguageChangeWarning) {
		// Language has changed - show restart warning (plain text, no link)
#ifdef USE_GETTEXT
		// Get the message in the newly selected language
		const char *currentLang = BattmanPrefsGetCString(kBattmanPrefs_LANGUAGE);
		if (currentLang != NULL) {
			NSString *localeCode = [NSString stringWithUTF8String:currentLang];
			message = getLocalizedMessageForLanguage(localeCode, "Language changes will take effect after restarting the app.");
		} else {
			message = _("Language changes will take effect after restarting the app.");
		}
#else
		message = _("Language changes will take effect after restarting the app.");
#endif
		self.localeWarnConf.URL = nil;
		self.localeWarnConf.target = nil;
		self.localeWarnConf.action = nil;
		self.localeWarnConf.linkRange = nil;
	} else if (shouldShowLocaleWarning) {
		// Locale not available, show GitHub issue link for now
		linkText = _("Create a new GitHub issue");
		message = [NSString stringWithFormat:_("Battman hasn't added your language yet. %@"), linkText];
		linkRange = [message rangeOfString:linkText];
		
		self.localeWarnConf.URL = nil;
		self.localeWarnConf.target = self;
		self.localeWarnConf.action = @selector(openIssueURL);
		self.localeWarnConf.linkRange = NSStringFromRange(linkRange);
	}
	
	self.localeWarnConf.text = message;
	
	if (!self.localeWarn) {
		self.localeWarn = [[FooterHyperlinkView alloc] initWithTableView:self.tableView configuration:self.localeWarnConf];
	} else {
		perform_selector(@selector(setText:), self.localeWarn, message);
		// Update link range if needed
		if (linkRange.location != NSNotFound) {
			self.localeWarn.linkRange = linkRange;
			self.localeWarn.target = self.localeWarnConf.target;
			self.localeWarn.action = self.localeWarnConf.action;
		} else {
			self.localeWarn.linkRange = NSMakeRange(NSNotFound, 0);
			self.localeWarn.target = nil;
			self.localeWarn.action = nil;
		}
	}
}

- (void)updateBIIntervalFooter {
	NSString *message = nil;
	
	if (self.intervalSegmentedTextField) {
		NSInteger selectedIndex = self.intervalSegmentedTextField.selectedSegmentIndex;
		switch (selectedIndex) {
			case 0: // Auto
				message = _("Battery information updates automatically depending on system conditions.");
				break;
			case 1: {// Custom
				int interval = [self.intervalSegmentedTextField textFieldAtIndex:1].text.intValue;
				NSString *finalStr = [NSString stringWithFormat:_("Battery information updates at the selected interval. %@"), (interval < 10) ? _("Using a shorter interval may affect performance.") : @""];
				message = finalStr;
				break;
			}
			case 2: // Never
				message = _("Battery information doesn’t update automatically. Pull down to refresh manually.");
				break;
			default:
				break;
		}
	}
	
	if (!message) {
		message = _("Configure how often battery information is refreshed.");
	}
	
	// Initialize configuration if needed
	if (!self.biIntervalFooterConf) {
		self.biIntervalFooterConf = [[FooterHyperlinkViewConfiguration alloc] init];
	}
	
	self.biIntervalFooterConf.text = message;
	self.biIntervalFooterConf.URL = nil;
	self.biIntervalFooterConf.target = nil;
	self.biIntervalFooterConf.action = nil;
	self.biIntervalFooterConf.linkRange = nil;
	
	if (!self.biIntervalFooter) {
		self.biIntervalFooter = [[FooterHyperlinkView alloc] initWithTableView:self.tableView configuration:self.biIntervalFooterConf];
	} else {
		perform_selector(@selector(setText:), self.biIntervalFooter, message);
		// Clear any link properties since this footer doesn't have links
		self.biIntervalFooter.linkRange = NSMakeRange(NSNotFound, 0);
		self.biIntervalFooter.target = nil;
		self.biIntervalFooter.action = nil;
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationNone];

	self.initialLanguagePreference = [BattmanPrefs.sharedPrefs stringForKey:@kBattmanPrefs_LANGUAGE];
	
	// Initialize locale warning
	[self updateLocaleWarning];
	
	// Initialize BI interval footer
	[self updateBIIntervalFooter];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	BattmanPrefs *prefs = BattmanPrefs.sharedPrefs;
	[prefs synchronize];

	NSString *currentLanguagePreference = [prefs stringForKey:@kBattmanPrefs_LANGUAGE];

	BOOL hasChanged = NO;
	if (self.initialLanguagePreference == nil && currentLanguagePreference != nil) {
		hasChanged = YES; // Changed from system default to specific language
	} else if (self.initialLanguagePreference != nil && currentLanguagePreference == nil) {
		hasChanged = YES; // Changed from specific language to system default
	} else if (self.initialLanguagePreference != nil && currentLanguagePreference != nil) {
		hasChanged = ![self.initialLanguagePreference isEqualToString:currentLanguagePreference];
	}
	
	if (hasChanged) {
		languageHasChanged = hasChanged;
		// Update the locale warning configuration
		[self updateLocaleWarning];
		// Refresh both the language row and the footer
		NSIndexPath *languageIndexPath = [NSIndexPath indexPathForRow:P_ROW_LANGUAGE inSection:P_SECT_LANGUAGE];
		[self.tableView reloadRowsAtIndexPaths:@[languageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
		[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_LANGUAGE] withRowAnimation:UITableViewRowAnimationNone];
	} else {
		// Just refresh the language row
		NSIndexPath *languageIndexPath = [NSIndexPath indexPathForRow:P_ROW_LANGUAGE inSection:P_SECT_LANGUAGE];
		[self.tableView reloadRowsAtIndexPaths:@[languageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return P_SECT_COUNT;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	PrefsSect sect = (PrefsSect)section;
	switch (sect) {
		case P_SECT_BI_INTERVAL: return P_ROW_BI_INTERVAL_COUNT;
		case P_SECT_LANGUAGE: return P_ROW_LANGUAGE_COUNT;
#if ENABLE_BRIGHTNESS
		case P_SECT_APPEARANCE: return P_ROW_APPEARANCE_COUNT;
#else
		case P_SECT_APPEARANCE: return P_ROW_APPEARANCE_COUNT - 1;
#endif
		case P_SECT_WIPEALL: return P_ROW_WIPEALL_COUNT;
		default:
			break;
	}
	return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == P_SECT_LANGUAGE && indexPath.row == P_ROW_LANGUAGE) {
		[self.navigationController pushViewController:[LanguageSelectionViewController new] animated:YES];
	}
	if (indexPath.section == P_SECT_APPEARANCE && indexPath.row == P_ROW_APPEARANCE_THERMOMETER) {
		[self.navigationController pushViewController:[ThermAniTestViewController new] animated:YES];
	}
	// Handle wipe all data action
	if (indexPath.section == P_SECT_WIPEALL && indexPath.row == P_ROW_WIPEALL) {
		[self showWipeAllConfirmation];
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"This is a Title yeah";
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	UITableViewHeaderFooterView *headerView = (UITableViewHeaderFooterView *)view;
	PrefsSect sect = (PrefsSect)section;
	switch (sect) {
		case P_SECT_LANGUAGE:
			headerView.textLabel.text = _("Preferred Language");
			break;
		case P_SECT_BI_INTERVAL:
			headerView.textLabel.text = _("Battery Info Refresh Rate");
			break;
		case P_SECT_APPEARANCE:
			headerView.textLabel.text = _("Appearance");
			break;
		case P_SECT_WIPEALL:
			headerView.textLabel.text = _("Data Management");
			break;
		default:
			headerView.textLabel.text = @"";
	}
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	PrefsSect sect = (PrefsSect)section;
	switch (sect) {
		case P_SECT_BI_INTERVAL:
			// Return FooterHyperlinkView for BI interval section
			if (self.biIntervalFooter) {
				return self.biIntervalFooter;
			}
			break;
		case P_SECT_LANGUAGE:
			// Return custom view for language section when we have a warning to show
			if (self.localeWarn) {
				return self.localeWarn;
			}
			break;
		default:
			break;
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	PrefsSect sect = (PrefsSect)section;
	switch (sect) {
		case P_SECT_BI_INTERVAL: {
			if (self.biIntervalFooter) {
				return nil;
			}
			return _("Configure how often battery information is refreshed.");
		}
		case P_SECT_LANGUAGE: {
			if (self.localeWarn) {
				return nil;
			}
			break;
		}
		case P_SECT_WIPEALL:
			return _("This will permanently delete all Battman data, preferences, and cached files. This action cannot be undone.");
		default:
			break;
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *reuseIdentifier = [NSString stringWithFormat:@"PREFS_%ld_%ld", indexPath.section, indexPath.row];
	id cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
	id config_value = [BattmanPrefs.sharedPrefs valueForTableView:tableView indexPath:indexPath];
	PrefsSect sect = (PrefsSect)indexPath.section;
	switch (sect) {
		case P_SECT_LANGUAGE: {
			PrefsRowLang row = (PrefsRowLang)indexPath.row;
			switch (row) {
				case P_ROW_LANGUAGE: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Language");
					[(UITableViewCell *)cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
#if defined(USE_GETTEXT)
					// Get the display name for the selected language
					NSString *detailText = _("Default");
					if (config_value != nil) {
						NSString *localeCode = [config_value stringValue];
						NSString *displayName = getDisplayNameForLocale(localeCode);
						if (displayName) {
							detailText = displayName;
						} else {
							detailText = localeCode; // Fallback to locale code
						}
					}
					[(UITableViewCell *)cell detailTextLabel].text = detailText;
#endif
					break;
				}
				default:
					break;
			}
			break;
		}
		case P_SECT_BI_INTERVAL: {
			PrefsRowBI row = (PrefsRowBI)indexPath.row;
			switch (row) {
				case P_ROW_BI_INTERVAL: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Interval (s)");
					UITextField *intervalTextField = [UITextField new];
					NSArray *items = nil;
					if (intervalTextField) {
						intervalTextField.textAlignment = NSTextAlignmentCenter;
						intervalTextField.keyboardType = UIKeyboardTypeDecimalPad;
						intervalTextField.returnKeyType = UIReturnKeyDone;
						/* TRANSLATORS: Please ensure this string won't be longer as "Custom" */
						intervalTextField.placeholder = _("Custom");
						intervalTextField.delegate = self;
						items = @[_("Auto"), intervalTextField, _("Never")];
					} else {
						items = @[_("Auto"), _("Never")];
					}
					SegmentedTextField *seg = [[SegmentedTextField alloc] initWithItems:items];
					self.intervalSegmentedTextField = seg;
					[seg addTarget:self action:@selector(segmentedControlValueChanged:) forControlEvents:UIControlEventValueChanged];
					if (config_value) {
						int interval = [config_value intValue];
						if (interval == 0)
							[seg setSelectedSegmentIndex:0];
						else if (interval == -1)
							[seg setSelectedSegmentIndex:seg.numberOfSegments - 1];
						else if (seg.numberOfSegments > 2) {
							intervalTextField.text = [config_value stringValue];
							[seg setSelectedSegmentIndex:1];
						}
					}
					[(UITableViewCell *)cell setAccessoryType:UITableViewCellAccessoryNone];
					[(UITableViewCell *)cell setAccessoryView:seg];
					// Update footer content now that we have the segmented control set up
					[self updateBIIntervalFooter];
					break;
				}
				default:
					break;
			}
			break;
		}
		case P_SECT_APPEARANCE: {
			PrefsRowAppearance row = (PrefsRowAppearance)indexPath.row;
			switch (row) {
				case P_ROW_APPEARANCE_THERMOMETER: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Thermometer Icon");
					[(UITableViewCell *)cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
					break;
				}
				case P_ROW_APPEARANCE_BRIGHTNESS_HDR: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Brightness Icon");
					UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[_("EDR"), _("SDR"), _("Quartz")]];
					unsigned int selected = [config_value unsignedIntValue];
					if (!metal_available(YES)) {
						selected = 2;
						[seg setEnabled:NO forSegmentAtIndex:0];
						[seg setEnabled:NO forSegmentAtIndex:1];
					} else {
						extern BOOL metal_hdr_available(id device);
						extern id MTLCreateSystemDefaultDevice(void);
						if (!metal_hdr_available(MTLCreateSystemDefaultDevice()))
							[seg setEnabled:NO forSegmentAtIndex:0];
						if (selected < 2)
							selected = 1;
					}
					[seg setSelectedSegmentIndex:selected];
					seg.tag = P_ROW_APPEARANCE_BRIGHTNESS_HDR;
					[seg addTarget:self action:@selector(brightnessHDRSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
					[(UITableViewCell *)cell setAccessoryView:seg];
					break;
				}
				default: break;
			}
			break;
		}
		case P_SECT_WIPEALL: {
			PrefsRowWipeAll row = (PrefsRowWipeAll)indexPath.row;
			switch (row) {
				case P_ROW_WIPEALL: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Wipe All Battman Data");
					if (@available(iOS 13.0, *))
						[(UITableViewCell *)cell textLabel].textColor = [UIColor systemRedColor];
					else
						[(UITableViewCell *)cell textLabel].textColor = [UIColor redColor];
					[(UITableViewCell *)cell setAccessoryType:UITableViewCellAccessoryNone];
					break;
				}
				default: break;
			}
			break;
		}
		default:
			break;
	}
	if (!cell) {
		cell = [UITableViewCell new];
		[(UITableViewCell *)cell textLabel].text = _("Unimplemented Yet");
	}
	return cell;
}

#pragma mark - UITextField Delegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	UITableViewCell *cell = find_cell(textField);
    NSIndexPath *indexPath = nil;
    if (cell) {
        indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for textField %@", textField);
		return YES;
	}

	if (indexPath && indexPath.section == P_SECT_BI_INTERVAL && indexPath.row == P_ROW_BI_INTERVAL) {
		NSString *proposedText = [textField.text stringByReplacingCharactersInRange:range withString:string];
		if ([proposedText length] == 0)
			return YES;
		NSCharacterSet *nonDigitCharacterSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
		if ([proposedText rangeOfCharacterFromSet:nonDigitCharacterSet].location != NSNotFound)
			return NO;
		NSInteger value = [proposedText integerValue];
		if (value < 0 || value > 64800) {
			return NO;
		}
	}
    
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	UITableViewCell *cell = find_cell(textField);
    NSIndexPath *indexPath = nil;
    if (cell) {
        indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for textField %@", textField);
		return;
	}

    if (indexPath && indexPath.section == P_SECT_BI_INTERVAL && indexPath.row == P_ROW_BI_INTERVAL) {
        SegmentedTextField *seg = (SegmentedTextField *)cell.accessoryView;
        if ([seg isKindOfClass:[SegmentedTextField class]]) {
            NSString *text = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            // Switch to "Auto" if text is empty or "0"
            if ([text length] == 0 || [text isEqualToString:@"0"]) {
				textField.text = @"";
				if (seg.selectedSegmentIndex == 1)
					seg.selectedSegmentIndex = 0;
				[self updateBIIntervalFooter];
				[BattmanPrefs.sharedPrefs setValue:@(seg.selectedSegmentIndex) forTableView:self.tableView indexPath:indexPath];
				[BattmanPrefs.sharedPrefs synchronize];
			} else {
				if ([textField.text intValue] < 5)
					textField.text = @"5";
				[self updateBIIntervalFooter];
				//[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationNone];
				[BattmanPrefs.sharedPrefs setValue:@(textField.text.intValue) forTableView:self.tableView indexPath:indexPath];
				[BattmanPrefs.sharedPrefs synchronize];
			}
        }
	}
}

#pragma mark - SegmentedTextField Action

- (void)segmentedControlValueChanged:(SegmentedTextField *)sender {
	UITableViewCell *cell = find_cell(sender);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for SegmentedTextField %@", sender);
		return;
	}

	if (sender == self.intervalSegmentedTextField) {
		if (sender.selectedSegmentIndex != 1) {
			[self updateBIIntervalFooter];
			//[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationNone];
			[BattmanPrefs.sharedPrefs setValue:@((sender.selectedSegmentIndex == 2) ? -1 : 0) forTableView:self.tableView indexPath:indexPath];
			[BattmanPrefs.sharedPrefs synchronize];
		}
	}
}

#pragma mark - Brightness HDR Segment Action

- (void)brightnessHDRSwitchValueChanged:(UISegmentedControl *)sender {
	UITableViewCell *cell = find_cell(sender);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for switch %@", sender);
		return;
	}
	
	if (!indexPath || indexPath.section != P_SECT_APPEARANCE || indexPath.row != P_ROW_APPEARANCE_BRIGHTNESS_HDR) {
		return;
	}
	
	// Save the switch state to preferences
	[BattmanPrefs.sharedPrefs setValue:@(sender.selectedSegmentIndex) forTableView:self.tableView indexPath:indexPath];
	[BattmanPrefs.sharedPrefs synchronize];
}

#pragma mark - Wipe All Data

- (void)showWipeAllConfirmation {
	BOOL exist = NO;
	NSError *err = nil;
	NSString *path = [NSString stringWithCString:battman_config_dir() encoding:NSUTF8StringEncoding];
	NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.MobileContainerManager"];
	if (bundle && [bundle load]) {
		MCMContainer *container = [[bundle classNamed:@"MCMContainer"] containerWithIdentifier:NSBundle.mainBundle.bundleIdentifier createIfNecessary:NO existed:&exist error:&err];
		if (container.url)
			path = container.url.path;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Wipe All Battman Data") message:[NSString stringWithFormat:_("This will wipe all data under %@"), path] preferredStyle:UIAlertControllerStyleActionSheet];
	
	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil];
	
#ifdef DEBUG
	UIAlertAction *dryRunAction = [UIAlertAction actionWithTitle:_("Dry Run") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
		[self performWipeAllData:YES];
	}];
#endif

	UIAlertAction *wipeAction = [UIAlertAction actionWithTitle:_("Wipe All Battman Data") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
		[self performWipeAllData:NO];
	}];

	[alert addAction:cancelAction];
#ifdef DEBUG
	[alert addAction:dryRunAction];
#endif
	[alert addAction:wipeAction];
	
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performWipeAllData {
	[self performWipeAllData:NO];
}

- (void)performWipeAllData:(BOOL)dryRun {
	// Show activity indicator
	NSString *title = dryRun ? _("Dry Run Analysis…") : _("Wiping Data…");
	NSString *message = dryRun ? _("Please wait while analyzing what would be deleted.") : _("Please wait while all data is being deleted.");
	
	UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	
	[self presentViewController:progressAlert animated:YES completion:^{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			// Perform the wipe operation on background queue
			[[BattmanPrefs sharedPrefs] wipeAllData:dryRun];

			dispatch_async(dispatch_get_main_queue(), ^{
				[progressAlert dismissViewControllerAnimated:YES completion:^{
					if (dryRun) {
						UIAlertController *completionAlert = [UIAlertController alertControllerWithTitle:_("Dry Run Complete") message:_("Analysis complete. Check the console/logs to see what would be deleted. No data was actually removed.") preferredStyle:UIAlertControllerStyleAlert];
						UIAlertAction *okAction = [UIAlertAction actionWithTitle:_("OK") style:UIAlertActionStyleDefault handler:nil];
						[completionAlert addAction:okAction];
						[self presentViewController:completionAlert animated:YES completion:nil];
					} else {
						// Show completion alert for actual wipe
						UIAlertController *completionAlert = [UIAlertController alertControllerWithTitle:_("Data Wiped") message:_("All Battman data has been successfully deleted. The app will now exit.") preferredStyle:UIAlertControllerStyleAlert];
						UIAlertAction *okAction = [UIAlertAction actionWithTitle:_("OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
							app_exit();
						}];
						[completionAlert addAction:okAction];
						[self presentViewController:completionAlert animated:YES completion:nil];
					}
				}];
			});
		});
	}];
}

@end
