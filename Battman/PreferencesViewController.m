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
#import "UITextFieldStepper.h"

static BOOL languageHasChanged = NO;

@interface PreferencesViewController () <UITextFieldDelegate>
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

@implementation PreferencesViewController

UITableViewCell *find_cell(UIView *view) {
	UIView *superview = view.superview;
    while (superview && ![superview isKindOfClass:[UITableViewCell class]]) {
        superview = superview.superview;
    }
    if (superview && [superview isKindOfClass:[UITableViewCell class]]) {
		return (UITableViewCell *)superview;
	}
	return nil;
}

- (instancetype)init {
	UITableViewStyle style = UITableViewStyleGrouped;
	if (@available(iOS 13.0, *))
		style = UITableViewStyleInsetGrouped;
	self = [super initWithStyle:style];
	if (self) {
		// Anything else?
	}

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationAutomatic];

	self.initialLanguagePreference = [BattmanPrefs.sharedPrefs stringForKey:@kBattmanPrefs_LANGUAGE];
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
		// Refresh both the language row and the footer
		NSIndexPath *languageIndexPath = [NSIndexPath indexPathForRow:P_ROW_LANGUAGE inSection:P_SECT_LANGUAGE];
		[self.tableView reloadRowsAtIndexPaths:@[languageIndexPath] withRowAnimation:UITableViewRowAnimationNone];
		[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_LANGUAGE] withRowAnimation:UITableViewRowAnimationAutomatic];
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

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	PrefsSect sect = (PrefsSect)section;
	switch (sect) {
		case P_SECT_BI_INTERVAL: {
			if (self.intervalSegmentedTextField) {
				NSInteger selectedIndex = self.intervalSegmentedTextField.selectedSegmentIndex;
				switch (selectedIndex) {
					case 0: // Auto
						return [NSString stringWithFormat:@"%@\n", _("Battery information updates automatically depending on system conditions.")];
					case 1: {// Custom
						int interval = [self.intervalSegmentedTextField textFieldAtIndex:1].text.intValue;
						NSString *finalStr = [NSString stringWithFormat:_("Battery information updates at the selected interval.\n%@"), (interval < 10) ? _("Using a shorter interval may affect performance.") : @""];
						return finalStr;
					}
					case 2: // Never
						return [NSString stringWithFormat:@"%@\n", _("Battery information doesn’t update automatically. Pull down to refresh manually.")];
					default:
						break;
				}
			}
			return _("Configure how often battery information is refreshed.\n");
		}
		case P_SECT_LANGUAGE: {
			// Only show footer if language has changed
			if (!languageHasChanged) {
				return nil;
			}
			
#ifdef USE_GETTEXT
			// Get the message in the newly selected language
			const char *currentLang = BattmanPrefsGetCString(kBattmanPrefs_LANGUAGE);
			if (currentLang != NULL) {
				NSString *localeCode = [NSString stringWithUTF8String:currentLang];
				return getLocalizedMessageForLanguage(localeCode, "Language changes will take effect after restarting the app.");
			}
			return _("Language changes will take effect after restarting the app.");
#endif
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
				case P_ROW_APPEARANCE_THERM_RANGE_MIN: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Thermometer min (℃)");
					UITextFieldStepper *st = [UITextFieldStepper new];
					st.maximumValue = 140 - 1;
					st.minimumValue = -50;
					st.value = [config_value intValue];
					st.tag = P_ROW_APPEARANCE_THERM_RANGE_MIN;
					[st addTarget:self action:@selector(thermometerStepperValueChanged:) forControlEvents:UIControlEventValueChanged];
					self.thermMinStepper = st;
					[(UITableViewCell *)cell setAccessoryView:st];
					break;
				}
				case P_ROW_APPEARANCE_THERM_RANGE_MAX: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Thermometer max (℃)");
					UITextFieldStepper *st = [UITextFieldStepper new];
					st.maximumValue = 140;
					st.minimumValue = -50 + 1;
					st.value = [config_value intValue];
					st.tag = P_ROW_APPEARANCE_THERM_RANGE_MAX;
					[st addTarget:self action:@selector(thermometerStepperValueChanged:) forControlEvents:UIControlEventValueChanged];
					self.thermMaxStepper = st;
					[(UITableViewCell *)cell setAccessoryView:st];
					break;
				}
				case P_ROW_APPEARANCE_BRIGHTNESS_HDR: {
					if (!cell)
						cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
					[(UITableViewCell *)cell textLabel].text = _("Use EDR on 'Brightness'");
					UISwitch *cs = [UISwitch new];
					cs.on = [config_value boolValue];
					cs.tag = P_ROW_APPEARANCE_BRIGHTNESS_HDR;
					[cs addTarget:self action:@selector(brightnessHDRSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
					[(UITableViewCell *)cell setAccessoryView:cs];
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
			} else {
				if ([textField.text intValue] < 5)
					textField.text = @"5";
				[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationAutomatic];
				[BattmanPrefs.sharedPrefs setValue:@(textField.text.intValue) forTableView:self.tableView indexPath:indexPath];
				[BattmanPrefs.sharedPrefs synchronize];
			}
        }
	}
}

#pragma mark - SegmentedTextField Action

- (void)segmentedControlValueChanged:(SegmentedTextField *)sender {
	if (sender == self.intervalSegmentedTextField) {
		if (sender.selectedSegmentIndex != 1)
			[self.tableView _reloadSectionHeaderFooters:[NSIndexSet indexSetWithIndex:P_SECT_BI_INTERVAL] withRowAnimation:UITableViewRowAnimationAutomatic];
	}
}

#pragma mark - Thermometer Stepper Actions

- (void)thermometerStepperValueChanged:(UITextFieldStepper *)sender {
	// Prevent recursive calls when we update the other stepper
	if (self.isUpdatingThermometerValues) {
		return;
	}
	
	UITableViewCell *cell = find_cell(sender);
	NSIndexPath *indexPath = nil;
	if (cell) {
		indexPath = [self.tableView indexPathForCell:cell];
	} else {
		DBGLOG(@"Cannot find belonging UITableViewCell for stepper %@", sender);
		return;
	}
	
	if (!indexPath || indexPath.section != P_SECT_APPEARANCE) {
		return;
	}
	
	self.isUpdatingThermometerValues = YES;
	
	// Get current values from both steppers
	double minValue = self.thermMinStepper ? self.thermMinStepper.value : -50;
	double maxValue = self.thermMaxStepper ? self.thermMaxStepper.value : 140;

	// Validate and adjust values to prevent min > max
	if (sender.tag == P_ROW_APPEARANCE_THERM_RANGE_MIN) {
		if (sender.value >= maxValue && sender.value < 140) {
			self.thermMaxStepper.value = sender.value + 1;
			// Save the adjusted max value too
			NSIndexPath *maxIndexPath = [NSIndexPath indexPathForRow:P_ROW_APPEARANCE_THERM_RANGE_MAX inSection:P_SECT_APPEARANCE];
			[BattmanPrefs.sharedPrefs setValue:@((int)self.thermMaxStepper.value) forTableView:self.tableView indexPath:maxIndexPath];
		}
	} else if (sender.tag == P_ROW_APPEARANCE_THERM_RANGE_MAX) {
		if (sender.value <= minValue && sender.value > -50) {
			self.thermMinStepper.value = sender.value - 1;
			// Save the adjusted min value too
			NSIndexPath *minIndexPath = [NSIndexPath indexPathForRow:P_ROW_APPEARANCE_THERM_RANGE_MIN inSection:P_SECT_APPEARANCE];
			[BattmanPrefs.sharedPrefs setValue:@((int)self.thermMinStepper.value) forTableView:self.tableView indexPath:minIndexPath];
		}
	}

	// Save the validated value to preferences
	[BattmanPrefs.sharedPrefs setValue:@((int)sender.value) forTableView:self.tableView indexPath:indexPath];
	[BattmanPrefs.sharedPrefs synchronize];
	
	self.isUpdatingThermometerValues = NO;
}

#pragma mark - Brightness HDR Switch Action

- (void)brightnessHDRSwitchValueChanged:(UISwitch *)sender {
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
	[BattmanPrefs.sharedPrefs setValue:@(sender.isOn) forTableView:self.tableView indexPath:indexPath];
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
	NSString *title = dryRun ? _("Dry Run Analysis...") : _("Wiping Data...");
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
