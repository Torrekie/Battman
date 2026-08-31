//
//  BTPluginManagementViewController.m
//  Battman
//

#import "BTPluginManagementViewController.h"
#import "BTPluginManagementViewControllerInternal.h"

#import "../Application/BTPluginPlatform.h"
#import "../Management/BTPluginManagementService.h"
#import "../Model/BTPluginPackageManifest.h"
#import "../Model/BTPluginSource.h"
#include "../../common.h"

typedef NS_ENUM(NSInteger, BTPluginManagementSection) {
	BTPluginManagementSectionSecurity = 0,
	BTPluginManagementSectionRecovery,
	BTPluginManagementSectionInstalled,
	BTPluginManagementSectionQuarantine,
	BTPluginManagementSectionDiagnostics,
	BTPluginManagementSectionCount,
};

typedef NS_ENUM(NSInteger, BTPluginDetailAction) {
	BTPluginDetailActionAllowExactBuild = 1,
	BTPluginDetailActionTrustPublisher,
	BTPluginDetailActionInstall,
	BTPluginDetailActionEnable,
	BTPluginDetailActionDisable,
	BTPluginDetailActionRevokeExactBuild,
	BTPluginDetailActionRevokePublisher,
	BTPluginDetailActionRemoveQuarantine,
	BTPluginDetailActionRemoveInstalled,
};

typedef NS_ENUM(NSInteger, BTPluginPackageDetailSection) {
	BTPluginPackageDetailSectionIdentity = 0,
	BTPluginPackageDetailSectionAuthor,
	BTPluginPackageDetailSectionExtensionPoints,
	BTPluginPackageDetailSectionTechnical,
	BTPluginPackageDetailSectionActions,
	BTPluginPackageDetailSectionCount,
};

static NSString *BTPluginDetailActionTitle(BTPluginDetailAction action) {
	switch (action) {
		case BTPluginDetailActionAllowExactBuild: return _("Allow This Version");
		case BTPluginDetailActionTrustPublisher: return _("Trust This Publisher");
		case BTPluginDetailActionInstall: return _("Install for Next Launch");
		case BTPluginDetailActionEnable: return _("Enable Next Launch");
		case BTPluginDetailActionDisable: return _("Disable Next Launch");
		case BTPluginDetailActionRevokeExactBuild: return _("Revoke Version Approval");
		case BTPluginDetailActionRevokePublisher: return _("Revoke Publisher Trust");
		case BTPluginDetailActionRemoveQuarantine: return _("Remove from Quarantine");
		case BTPluginDetailActionRemoveInstalled: return _("Remove Plug-in");
	}
	return @"";
}

static NSString *BTPluginTrustDescription(BTPluginTrustDisposition disposition) {
	switch (disposition) {
		case BTPluginTrustDispositionOfficial: return _("Official");
		case BTPluginTrustDispositionTrustedPublisher: return _("Trusted Publisher");
		case BTPluginTrustDispositionExactBuild: return _("Allowed Version");
		case BTPluginTrustDispositionDeveloper: return _("Developer Mode");
		case BTPluginTrustDispositionRequiresApproval: return _("Approval Required");
	}
	return _("Unavailable");
}

static NSString *BTPluginTrustDiagnosticValue(BTPluginTrustDisposition disposition) {
	switch (disposition) {
		case BTPluginTrustDispositionOfficial: return @"official";
		case BTPluginTrustDispositionTrustedPublisher: return @"trusted-publisher";
		case BTPluginTrustDispositionExactBuild: return @"exact-build";
		case BTPluginTrustDispositionDeveloper: return @"developer-mode";
		case BTPluginTrustDispositionRequiresApproval: return @"approval-required";
	}
	return @"unavailable";
}

static NSString *BTPluginDiagnosticErrorValue(NSError *error) {
	if (!error)
		return @"none";
	return [NSString stringWithFormat:@"%@/%ld", error.domain ?: @"unknown",
		(long)error.code];
}

/*
 * Keep distribution guidance next to the import/recovery UI. The package
 * manager and TrollStore paths have different architecture and activation
 * rules; presenting them together prevents a user from treating a .deb,
 * .tipa, and .battman transport as interchangeable files.
 */
static NSString *BTPluginDownloadGuideMessage(void) {
	return [@[
		_("Use the package that matches how Battman is installed."),
		_("Rooted jailbreak (iOS 12+): install the matching host or plug-in iphoneos-arm .deb with APT/dpkg; do not use iphoneos-arm64."),
		_("Rootless jailbreak (iOS 15+): install the matching host or plug-in iphoneos-arm64 .deb with APT/dpkg; do not use iphoneos-arm."),
		_("TrollStore (iOS 14+): install the replacement Battman.tipa. Native plug-ins must be embedded in that replacement app; newly imported native code is not loaded directly from the app data directory."),
		_("A .battman file is an import transport. Battman verifies it before approval; it is not a direct installer."),
		_("Havoc is a manually selected Debian-only channel. GitHub Releases is the canonical place for reviewed artifacts. Never install a package for another architecture.")
	] componentsJoinedByString:@"\n\n"];
}

static void BTPluginOpenExternalURL(NSString *URLString) {
	NSURL *URL = [NSURL URLWithString:URLString];
	if (!URL)
		return;
	[[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
}

static NSString *BTPluginShortDigest(NSString *digest) {
	return digest.length > 16 ? [NSString stringWithFormat:@"%@…%@",
		[digest substringToIndex:8], [digest substringFromIndex:digest.length - 8]] : digest;
}

static NSString *BTPluginExtensionPointSummary(BTPluginVerifiedPackage *verified,
	BTPluginPackageManifest *priorManifest, NSString *comparisonMessage) {
	NSMutableArray<NSString *> *values = [NSMutableArray array];
	NSArray<BTPluginManifestExtensionPoint *> *extensionPoints =
		[verified.packageInspection.manifest.extensionPoints sortedArrayUsingComparator:
			^NSComparisonResult(BTPluginManifestExtensionPoint *left, BTPluginManifestExtensionPoint *right) {
				return [left.identifier compare:right.identifier options:NSLiteralSearch];
			}];
	for (BTPluginManifestExtensionPoint *extensionPoint in extensionPoints)
		[values addObject:[NSString stringWithFormat:@"%@ (v%u)", extensionPoint.identifier,
			extensionPoint.interfaceVersion]];
	NSMutableString *summary = [[values componentsJoinedByString:@"\n"] mutableCopy];
	NSString *changeLabel = _("Extension-point changes since prior version");
	if (!priorManifest && comparisonMessage.length == 0)
		return summary;
	[summary appendFormat:@"\n\n%@: ", changeLabel];
	if (!priorManifest) {
		[summary appendString:comparisonMessage];
		return summary;
	}
	NSArray<BTPluginExtensionPointChange *> *changes =
		BTPluginExtensionPointChangesFromManifests(priorManifest, verified.packageInspection.manifest);
	if (changes.count == 0) {
		[summary appendString:@"—"];
		return summary;
	}
	NSMutableArray<NSString *> *changeValues = [NSMutableArray arrayWithCapacity:changes.count];
	for (BTPluginExtensionPointChange *change in changes) {
		NSString *prefix = @"~";
		NSString *version = [NSString stringWithFormat:@"v%@ → v%@",
			change.previousInterfaceVersion ?: @"—", change.currentInterfaceVersion ?: @"—"];
		switch (change.kind) {
			case BTPluginExtensionPointChangeKindAdded:
				prefix = @"+";
				version = [NSString stringWithFormat:@"v%@", change.currentInterfaceVersion];
				break;
			case BTPluginExtensionPointChangeKindRemoved:
				prefix = @"−";
				version = [NSString stringWithFormat:@"v%@", change.previousInterfaceVersion];
				break;
			case BTPluginExtensionPointChangeKindVersionChanged:
				break;
		}
		[changeValues addObject:[NSString stringWithFormat:@"%@ %@ (%@)", prefix, change.identifier, version]];
	}
	[summary appendString:[changeValues componentsJoinedByString:@"\n"]];
	return summary;
}

static NSString *BTPluginPriorComparisonMessage(BTPluginPriorVersionComparisonStatus status) {
	switch (status) {
		case BTPluginPriorVersionComparisonStatusNoInstalledVersion:
			return _("No prior installed version");
		case BTPluginPriorVersionComparisonStatusAmbiguousInstalledRepresentations:
			return _("Comparison unavailable: multiple installed representations");
		case BTPluginPriorVersionComparisonStatusPriorVerificationFailed:
			return _("Comparison unavailable: installed version failed verification");
		case BTPluginPriorVersionComparisonStatusPriorNotApproved:
			return _("Comparison unavailable: installed version is not approved");
		case BTPluginPriorVersionComparisonStatusActivationMismatch:
			return _("Comparison unavailable: activation state does not match installed bytes");
		case BTPluginPriorVersionComparisonStatusPublisherChanged:
			return _("Comparison unavailable: publisher key changed");
		case BTPluginPriorVersionComparisonStatusCandidateNotNewer:
			return _("Comparison unavailable: candidate is not a newer release");
		case BTPluginPriorVersionComparisonStatusAvailable:
			return nil;
		case BTPluginPriorVersionComparisonStatusUnavailable:
			return _("Prior-version comparison unavailable");
	}
	return _("Prior-version comparison unavailable");
}

static NSString *BTPluginDangerousLoadMessage(BTPluginVerifiedPackage *verified,
	BTPluginPackageManifest *priorManifest, NSString *comparisonMessage, BOOL publisherTrust) {
	BTPluginPackageManifest *manifest = verified.packageInspection.manifest;
	NSString *scope = publisherTrust ?
		_("Trusting this publisher also allows future versions signed by this key for the same plug-in ID and requested extension points. Future versions still must pass offline signature, revocation, release-sequence rollback, and extension-point scope checks.") :
		_("This approval applies only to these exact package bytes. Any update requires approval again.");
	return [NSString stringWithFormat:
		_("Native plug-ins are not isolated from Battman. They can use its data, entitlements, and network access, replace UI, and compromise the app. Open source and valid signatures do not make code safe.\n\nName: %@\nAuthor: %@\nID: %@\nVersion: %@ (%@)\nRelease sequence: %llu\nPublisher fingerprint: %@\nPackage digest: %@\nExtension points:\n%@\n\n%@\n\nNothing loads until Battman restarts."),
		manifest.displayName, manifest.author.name ?: _("Not Provided"), manifest.pluginIdentifier,
		manifest.displayVersion, manifest.buildVersion, (unsigned long long)manifest.releaseSequence,
		BTPluginShortDigest(manifest.publisher.primaryKeyIdentifier),
		BTPluginShortDigest(verified.packageInspection.packageSHA256),
		BTPluginExtensionPointSummary(verified, priorManifest, comparisonMessage), scope];
}

UIAlertController *BTPluginCreateDangerousLoadConsentAlert(BTPluginVerifiedPackage *verifiedPackage,
	BOOL publisherTrust, dispatch_block_t approvalHandler) {
	return BTPluginCreateDangerousLoadConsentAlertWithPriorManifest(verifiedPackage, nil, nil,
		publisherTrust, approvalHandler);
}

UIAlertController *BTPluginCreateDangerousLoadConsentAlertWithPriorManifest(
	BTPluginVerifiedPackage *verifiedPackage, BTPluginPackageManifest *priorManifest,
	NSString *comparisonMessage, BOOL publisherTrust, dispatch_block_t approvalHandler) {
	NSString *title = publisherTrust ? _("Trust This Publisher?") : _("Allow This Version?");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
		message:BTPluginDangerousLoadMessage(verifiedPackage, priorManifest, comparisonMessage,
			publisherTrust)
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:publisherTrust ? _("Trust Publisher and Schedule") : _("Allow Version and Schedule")
		style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			(void)action;
			if (approvalHandler)
				approvalHandler();
		}]];
	return alert;
}

UIAlertController *BTPluginCreateThirdPartyEnableConsentAlert(dispatch_block_t enableHandler) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Enable Third-Party Plug-ins?")
		message:_("Third-party native plug-ins run inside Battman without isolation. They can access Battman's data and entitlements, use the network, replace UI, and crash or compromise the app. Signatures identify package bytes; they do not make code safe. Only continue if you understand and accept these risks.")
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_("I Understand, Enable")
		style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			(void)action;
			if (enableHandler)
				enableHandler();
		}]];
	return alert;
}

UIAlertController *BTPluginCreateSafeModeScheduledAlert(void) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Safe Mode Scheduled")
		message:_("The next Battman launch will skip all third-party plug-ins once. Quit and reopen Battman when you are ready.")
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("OK") style:UIAlertActionStyleCancel handler:nil]];
	return alert;
}

UIAlertController *BTPluginCreateDiagnosticDisclosureAlert(dispatch_block_t continueHandler) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:
		_("Review Diagnostics Before Sharing")
		message:_("The report contains Battman version, generation time, plug-in identifiers, package hashes, source, trust and activation state, and error domain/code values. It excludes plug-in files, private keys, battery measurements, device identifiers, and filesystem paths. Review the report and recipient before sharing.")
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel")
		style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_("Continue")
		style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			(void)action;
			if (continueHandler)
				continueHandler();
		}]];
	return alert;
}

static void BTPluginPresentError(UIViewController *presenter, NSString *title, NSError *error) {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
		message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("OK") style:UIAlertActionStyleCancel handler:nil]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

static void BTPluginPresentActionResult(UIViewController *presenter, BTPluginManagementActionResult *result) {
	NSString *title = nil;
	NSString *message = nil;
	if (result.outcome == BTPluginManagementActionOutcomeRequiresReplacementApp) {
		title = _("Requires Battman Reinstall");
		message = _("This Battman installation cannot load newly imported native code directly. The approved package remains quarantined and must be embedded in a replacement Battman app, then installed explicitly.");
	} else {
		title = _("Scheduled for Next Launch");
		message = _("The verified plug-in is installed and scheduled. It can load only after Battman restarts, and third-party loading must also be enabled.");
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("OK") style:UIAlertActionStyleCancel handler:nil]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

@interface BTPluginTechnicalDetailsViewController : UITableViewController
@property (nonatomic, strong) BTPluginVerifiedPackage *verifiedPackage;
- (instancetype)initWithVerifiedPackage:(BTPluginVerifiedPackage *)verifiedPackage;
@end

@implementation BTPluginTechnicalDetailsViewController

- (instancetype)initWithVerifiedPackage:(BTPluginVerifiedPackage *)verifiedPackage {
	NSParameterAssert(verifiedPackage);
	if (@available(iOS 13.0, *))
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = _("Technical Details");
		_verifiedPackage = verifiedPackage;
	}
	return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return _("These identifiers verify the signing key and exact package bytes. Tap a value to copy its full form.");
}

- (NSString *)fullValueForRow:(NSInteger)row {
	return row == 0 ? self.verifiedPackage.packageInspection.manifest.publisher.primaryKeyIdentifier :
		self.verifiedPackage.packageInspection.packageSHA256;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView;
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = indexPath.row == 0 ? _("Publisher Fingerprint") : _("Package Digest");
	cell.detailTextLabel.text = BTPluginShortDigest([self fullValueForRow:indexPath.row]);
	cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:
		[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote].pointSize weight:UIFontWeightRegular];
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[UIPasteboard generalPasteboard].string = [self fullValueForRow:indexPath.row];
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	cell.accessoryType = UITableViewCellAccessoryCheckmark;
	UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, _("Copied"));
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		UITableViewCell *visibleCell = [tableView cellForRowAtIndexPath:indexPath];
		visibleCell.accessoryType = UITableViewCellAccessoryNone;
	});
}

@end

@interface BTPluginPackageDetailViewController : UITableViewController
@property (nonatomic, strong) BTPluginManagementService *service;
@property (nonatomic, strong, nullable) BTPluginManagedInstalledPackage *installedItem;
@property (nonatomic, strong, nullable) BTPluginQuarantinedPackage *quarantinedPackage;
@property (nonatomic, strong, nullable) BTPluginPackageManifest *priorManifest;
@property (nonatomic, copy, nullable) NSString *priorComparisonMessage;
@property (nonatomic, copy) dispatch_block_t changeHandler;
@end

@implementation BTPluginPackageDetailViewController

- (instancetype)init {
	if (@available(iOS 13.0, *))
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		self = [super initWithStyle:UITableViewStyleGrouped];
	if (self)
		self.title = _("Plug-in Details");
	return self;
}

- (BTPluginVerifiedPackage *)verifiedPackage {
	return self.installedItem ? self.installedItem.verifiedPackage : self.quarantinedPackage.verification;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return BTPluginPackageDetailSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	BTPluginVerifiedPackage *verified = [self verifiedPackage];
	if (section == BTPluginPackageDetailSectionIdentity)
		return verified ? 6 : 2;
	if (section == BTPluginPackageDetailSectionAuthor) {
		if (!verified)
			return 0;
		BTPluginManifestAuthor *author = verified.packageInspection.manifest.author;
		return author ? 1 + (author.homepageURL != nil) + (author.supportEmail != nil) : 1;
	}
	if (section == BTPluginPackageDetailSectionExtensionPoints)
		return 1;
	if (section == BTPluginPackageDetailSectionTechnical)
		return verified ? 1 : 0;
	return section == BTPluginPackageDetailSectionActions ? self.detailActions.count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self tableView:tableView numberOfRowsInSection:section] == 0)
		return nil;
	if (section == BTPluginPackageDetailSectionIdentity) return _("Identity");
	if (section == BTPluginPackageDetailSectionAuthor) return _("Author & Support");
	if (section == BTPluginPackageDetailSectionExtensionPoints) return _("Requested Extension Points");
	if (section == BTPluginPackageDetailSectionTechnical) return _("Technical Details");
	return section == BTPluginPackageDetailSectionActions ? _("Actions") : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section != BTPluginPackageDetailSectionAuthor || ![self verifiedPackage])
		return nil;
	return [self verifiedPackage].packageInspection.manifest.author ?
		_("Author and contact details are supplied by the signed package. The verification status above determines whether Battman recognizes its publisher.") :
		_("This package does not provide author or support information.");
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title value:(NSString *)value {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = value;
	cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (NSArray<NSNumber *> *)detailActions {
	BTPluginVerifiedPackage *verified = [self verifiedPackage];
	if (!verified)
		return self.installedItem.discoveredPackage.source == BTPluginSourceApplicationData ?
			@[ @(BTPluginDetailActionRemoveInstalled) ] : @[];
	NSMutableArray<NSNumber *> *actions = [NSMutableArray array];
	BOOL quarantine = self.quarantinedPackage != nil;
	BTPluginTrustDisposition disposition = verified.trustEvaluation.disposition;
	if (disposition == BTPluginTrustDispositionRequiresApproval) {
		[actions addObject:@(BTPluginDetailActionAllowExactBuild)];
		[actions addObject:@(BTPluginDetailActionTrustPublisher)];
	} else if (quarantine) {
		[actions addObject:@(BTPluginDetailActionInstall)];
	} else {
		BOOL enabled = self.installedItem.activationRecord ? self.installedItem.activationRecord.isEnabled :
			disposition == BTPluginTrustDispositionOfficial;
		[actions addObject:@(enabled ? BTPluginDetailActionDisable : BTPluginDetailActionEnable)];
	}
	if (disposition == BTPluginTrustDispositionExactBuild)
		[actions addObject:@(BTPluginDetailActionRevokeExactBuild)];
	if (disposition == BTPluginTrustDispositionTrustedPublisher)
		[actions addObject:@(BTPluginDetailActionRevokePublisher)];
	if (quarantine)
		[actions addObject:@(BTPluginDetailActionRemoveQuarantine)];
	else if (self.installedItem.discoveredPackage.source == BTPluginSourceApplicationData)
		[actions addObject:@(BTPluginDetailActionRemoveInstalled)];
	return actions;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView;
	BTPluginVerifiedPackage *verified = [self verifiedPackage];
	if (indexPath.section == BTPluginPackageDetailSectionIdentity) {
		if (!verified) {
			if (indexPath.row == 0)
				return [self valueCellWithTitle:_("ID") value:self.installedItem.discoveredPackage.claimedPluginIdentifier];
			return [self valueCellWithTitle:_("Status") value:_("Verification Failed")];
		}
		BTPluginPackageManifest *manifest = verified.packageInspection.manifest;
			switch (indexPath.row) {
				case 0: return [self valueCellWithTitle:_("Name") value:manifest.displayName];
				case 1: return [self valueCellWithTitle:_("ID") value:manifest.pluginIdentifier];
				case 2: return [self valueCellWithTitle:_("Version") value:[NSString stringWithFormat:@"%@ (%@)", manifest.displayVersion, manifest.buildVersion]];
				case 3: return [self valueCellWithTitle:_("Release Sequence")
					value:[NSString stringWithFormat:@"%llu", (unsigned long long)manifest.releaseSequence]];
				case 4: return [self valueCellWithTitle:_("Source") value:self.quarantinedPackage ? _("Quarantine") : BTPluginSourceName(self.installedItem.discoveredPackage.source)];
				default: return [self valueCellWithTitle:_("Verification") value:BTPluginTrustDescription(verified.trustEvaluation.disposition)];
		}
	}
	if (indexPath.section == BTPluginPackageDetailSectionAuthor) {
		BTPluginManifestAuthor *author = verified.packageInspection.manifest.author;
		if (!author)
			return [self valueCellWithTitle:_("Author") value:_("Not Provided")];
		if (indexPath.row == 0)
			return [self valueCellWithTitle:_("Author") value:author.name];
		BOOL homepageRow = author.homepageURL && indexPath.row == 1;
		NSString *title = homepageRow ? _("Homepage") : _("Support Email");
		NSString *value = homepageRow ? [author.homepageURL substringFromIndex:@"https://".length] : author.supportEmail;
		UITableViewCell *cell = [self valueCellWithTitle:title value:value];
		cell.selectionStyle = UITableViewCellSelectionStyleDefault;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (indexPath.section == BTPluginPackageDetailSectionExtensionPoints) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.numberOfLines = 0;
		cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
		cell.textLabel.text = verified ? BTPluginExtensionPointSummary(verified, self.priorManifest,
			self.priorComparisonMessage) :
			(self.installedItem.verificationError.localizedDescription ?: _("Unavailable"));
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	if (indexPath.section == BTPluginPackageDetailSectionTechnical) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = _("View Verification Details");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	BTPluginDetailAction action = (BTPluginDetailAction)self.detailActions[indexPath.row].integerValue;
	NSString *title = BTPluginDetailActionTitle(action);
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.text = title;
	if (action == BTPluginDetailActionRemoveInstalled || action == BTPluginDetailActionRemoveQuarantine ||
		action == BTPluginDetailActionRevokeExactBuild || action == BTPluginDetailActionRevokePublisher)
		cell.textLabel.textColor = [UIColor redColor];
	else
		cell.textLabel.textColor = self.view.tintColor;
	return cell;
}

- (void)finishChange {
	if (self.changeHandler)
		self.changeHandler();
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)performApprovalPublisherWide:(BOOL)publisherWide {
	BTPluginVerifiedPackage *verified = [self verifiedPackage];
	if (!verified)
		return;
	BTPluginPackageManifest *priorManifest = self.priorManifest;
	NSString *comparisonMessage = self.priorComparisonMessage;
	if (self.quarantinedPackage) {
		NSError *snapshotError = nil;
		verified = [self.service refreshQuarantinedPackage:self.quarantinedPackage error:&snapshotError];
		BTPluginManagementSnapshot *snapshot = verified ?
			[self.service managementSnapshotWithStartupSnapshot:nil error:&snapshotError] : nil;
		if (!verified || !snapshot) {
			BTPluginPresentError(self, _("Plug-in Approval Failed"), snapshotError);
			return;
		}
		BTPluginPriorVersionComparisonStatus status =
			BTPluginPriorVersionComparisonForCandidate(verified, snapshot.installedPackages, &priorManifest);
		comparisonMessage = BTPluginPriorComparisonMessage(status);
	}
	__weak typeof(self) weakSelf = self;
	UIAlertController *alert = BTPluginCreateDangerousLoadConsentAlertWithPriorManifest(verified,
		priorManifest, comparisonMessage, publisherWide, ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self) return;
			NSError *error = nil;
			BTPluginManagementActionResult *result = nil;
			if (self.quarantinedPackage) {
				result = publisherWide ?
					[self.service trustPublisherAndScheduleQuarantinedPackage:self.quarantinedPackage error:&error] :
					[self.service allowExactBuildAndScheduleQuarantinedPackage:self.quarantinedPackage error:&error];
			} else {
				result = publisherWide ?
					[self.service trustPublisherAndScheduleDiscoveredPackage:self.installedItem.discoveredPackage error:&error] :
					[self.service allowExactBuildAndScheduleDiscoveredPackage:self.installedItem.discoveredPackage error:&error];
			}
			if (!result) {
				BTPluginPresentError(self, _("Plug-in Approval Failed"), error);
				return;
			}
			BTPluginPresentActionResult(self, result);
			if (self.changeHandler) self.changeHandler();
		});
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDestructiveTitle:(NSString *)title message:(NSString *)message handler:(dispatch_block_t)handler {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive
		handler:^(UIAlertAction *action) { (void)action; handler(); }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == BTPluginPackageDetailSectionAuthor) {
		BTPluginManifestAuthor *author = [self verifiedPackage].packageInspection.manifest.author;
		if (!author || indexPath.row == 0)
			return;
		NSURL *URL = nil;
		if (author.homepageURL && indexPath.row == 1) {
			URL = [NSURL URLWithString:author.homepageURL];
		} else if (author.supportEmail) {
			NSURLComponents *components = [NSURLComponents new];
			components.scheme = @"mailto";
			components.path = author.supportEmail;
			URL = components.URL;
		}
		if (URL)
			[[UIApplication sharedApplication] openURL:URL options:@{} completionHandler:nil];
		return;
	}
	if (indexPath.section == BTPluginPackageDetailSectionTechnical) {
		BTPluginVerifiedPackage *verified = [self verifiedPackage];
		if (verified)
			[self.navigationController pushViewController:[[BTPluginTechnicalDetailsViewController alloc]
				initWithVerifiedPackage:verified] animated:YES];
		return;
	}
	if (indexPath.section != BTPluginPackageDetailSectionActions)
		return;
	BTPluginDetailAction action = (BTPluginDetailAction)self.detailActions[indexPath.row].integerValue;
	NSString *title = BTPluginDetailActionTitle(action);
	if (action == BTPluginDetailActionAllowExactBuild) {
		[self performApprovalPublisherWide:NO];
		return;
	}
	if (action == BTPluginDetailActionTrustPublisher) {
		[self performApprovalPublisherWide:YES];
		return;
	}
	NSError *error = nil;
	if (action == BTPluginDetailActionInstall) {
		BTPluginManagementActionResult *result = [self.service
			installAlreadyTrustedQuarantinedPackage:self.quarantinedPackage error:&error];
		if (result) {
			BTPluginPresentActionResult(self, result);
			if (self.changeHandler) self.changeHandler();
		} else {
			BTPluginPresentError(self, _("Plug-in Installation Failed"), error);
		}
		return;
	}
	if (action == BTPluginDetailActionEnable || action == BTPluginDetailActionDisable) {
		BOOL enable = action == BTPluginDetailActionEnable;
		if (![self.service setDiscoveredPackage:self.installedItem.discoveredPackage enabled:enable error:&error]) {
			BTPluginPresentError(self, _("Plug-in Change Failed"), error);
			return;
		}
		[self finishChange];
		return;
	}
	__weak typeof(self) weakSelf = self;
	if (action == BTPluginDetailActionRevokeExactBuild) {
		[self confirmDestructiveTitle:title message:_("This version will be rejected the next time Battman starts. Already loaded code cannot be unloaded safely.") handler:^{
			__strong typeof(weakSelf) self = weakSelf; if (!self) return;
			NSError *actionError = nil;
			if (![self.service revokeExactBuildForPackageSHA256:self.verifiedPackage.packageInspection.packageSHA256 error:&actionError])
				BTPluginPresentError(self, _("Trust Change Failed"), actionError);
			else [self finishChange];
		}];
		return;
	}
	if (action == BTPluginDetailActionRevokePublisher) {
		[self confirmDestructiveTitle:title message:_("Plug-ins relying on this publisher approval will be rejected the next time Battman starts. Already loaded code cannot be unloaded safely.") handler:^{
			__strong typeof(weakSelf) self = weakSelf; if (!self) return;
			NSError *actionError = nil;
			if (![self.service revokePublisherKeyIdentifier:self.verifiedPackage.packageInspection.manifest.publisher.primaryKeyIdentifier error:&actionError])
				BTPluginPresentError(self, _("Trust Change Failed"), actionError);
			else [self finishChange];
		}];
		return;
	}
	if (action == BTPluginDetailActionRemoveQuarantine) {
		[self confirmDestructiveTitle:title message:_("Remove this verified package from Battman's private quarantine?") handler:^{
			__strong typeof(weakSelf) self = weakSelf; if (!self) return;
			NSError *actionError = nil;
			if (![self.service removeQuarantinedPackage:self.quarantinedPackage error:&actionError])
				BTPluginPresentError(self, _("Plug-in Removal Failed"), actionError);
			else [self finishChange];
		}];
		return;
	}
	if (action == BTPluginDetailActionRemoveInstalled) {
		[self confirmDestructiveTitle:title message:_("Remove this exact plug-in from Battman's private app-data directory? App-bundle and package-manager files are never removed here.") handler:^{
			__strong typeof(weakSelf) self = weakSelf; if (!self) return;
			NSError *actionError = nil;
			// Revocation can make the trust-gated verified package unavailable, but
			// the persisted activation record still names the exact bytes that the
			// user saw and confirmed. The service independently re-hashes them and
			// checks record/source/path consistency before journaling removal.
			NSString *digest = self.verifiedPackage.packageInspection.packageSHA256 ?:
				self.installedItem.activationRecord.packageSHA256;
			if (!digest || ![self.service removeDiscoveredPackage:self.installedItem.discoveredPackage
				expectedPackageSHA256:digest error:&actionError])
				BTPluginPresentError(self, _("Plug-in Removal Failed"), actionError);
			else [self finishChange];
		}];
	}
}

@end

@interface BTPluginManagementViewController ()
@property (nonatomic, strong) BTPluginManagementSnapshot *snapshot;
@property (nonatomic, strong) id<BTPluginManagementPlatformProviding> platformProvider;
@property (nonatomic) dispatch_queue_t snapshotQueue;
@property (nonatomic) NSUInteger refreshGeneration;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic) BOOL suppressInitialRefresh;
- (void)presentDownloadGuide;
@end

@implementation BTPluginManagementViewController

- (void)closePresentedManagement {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (instancetype)init {
	return [self initWithPlatformProvider:(id<BTPluginManagementPlatformProviding>)[BTPluginPlatform sharedPlatform]];
}

- (instancetype)initWithPlatformProvider:(id<BTPluginManagementPlatformProviding>)platformProvider {
	return [self initWithPlatformProvider:platformProvider initialSnapshot:nil];
}

- (instancetype)initWithPlatformProvider:(id<BTPluginManagementPlatformProviding>)platformProvider
	initialSnapshot:(BTPluginManagementSnapshot *)initialSnapshot {
	NSParameterAssert(platformProvider);
	if (@available(iOS 13.0, *))
		self = [super initWithStyle:UITableViewStyleInsetGrouped];
	else
		self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = _("Plug-ins");
		_platformProvider = platformProvider;
		_snapshot = initialSnapshot;
		_suppressInitialRefresh = initialSnapshot != nil;
		_snapshotQueue = dispatch_queue_create("com.torrekie.Battman.PluginManagementSnapshot", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.estimatedRowHeight = 52.0;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	UIBarButtonItem *refreshItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshSnapshot)];
	UIBarButtonItem *guideItem = [[UIBarButtonItem alloc]
		initWithTitle:_("Download Guide") style:UIBarButtonItemStylePlain target:self
		action:@selector(presentDownloadGuide)];
	guideItem.accessibilityLabel = _("Download Guide");
	self.navigationItem.rightBarButtonItems = @[ refreshItem, guideItem ];
	self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
}

- (void)presentDownloadGuide {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Download Guide")
		message:BTPluginDownloadGuideMessage() preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_("Open GitHub Releases")
		style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			(void)action;
			BTPluginOpenExternalURL(@"https://github.com/Torrekie/Battman/releases/latest");
		}]];
	[alert addAction:[UIAlertAction actionWithTitle:_("Open Installation Guide")
		style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			(void)action;
			BTPluginOpenExternalURL([NSString stringWithFormat:@"%s/installation/", BATTMAN_DOC_URL]);
		}]];
	[alert addAction:[UIAlertAction actionWithTitle:_("Open Havoc")
		style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			(void)action;
			BTPluginOpenExternalURL(@"https://havoc.app/package/battman");
		}]];
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel")
		style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.suppressInitialRefresh) {
		self.suppressInitialRefresh = NO;
		return;
	}
	[self refreshSnapshot];
}

- (void)refreshSnapshot {
	NSUInteger generation = ++self.refreshGeneration;
	[self.activityIndicator startAnimating];
	self.navigationItem.titleView = self.activityIndicator;
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.snapshotQueue, ^{
		NSError *error = nil;
		BTPluginManagementSnapshot *snapshot = [self.platformProvider
			currentManagementSnapshotWithError:&error];
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || generation != self.refreshGeneration) return;
			[self.activityIndicator stopAnimating];
			self.navigationItem.titleView = nil;
			if (!snapshot) {
				BTPluginPresentError(self, _("Plug-in Inventory Failed"), error);
				return;
			}
			self.snapshot = snapshot;
			[self.tableView reloadData];
		});
	});
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return BTPluginManagementSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section == BTPluginManagementSectionSecurity) return 2;
	if (section == BTPluginManagementSectionRecovery) return self.snapshot.recovery ? 1 : 0;
	if (section == BTPluginManagementSectionInstalled) return MAX((NSInteger)self.snapshot.installedPackages.count, 1);
	if (section == BTPluginManagementSectionQuarantine) return MAX((NSInteger)self.snapshot.quarantinedPackages.count, 1);
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	switch (section) {
		case BTPluginManagementSectionSecurity: return _("Native Plug-ins");
		case BTPluginManagementSectionRecovery: return _("Recovery");
		case BTPluginManagementSectionInstalled: return _("Installed");
		case BTPluginManagementSectionQuarantine: return _("Quarantine");
		case BTPluginManagementSectionDiagnostics: return _("Diagnostics");
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == BTPluginManagementSectionSecurity)
		return [NSString stringWithFormat:@"%@\n\n%@",
			_("Third-party native plug-ins run inside Battman and are not sandboxed from it. Changes take effect only after restart; loaded images are never unloaded."),
			_("Use Download Guide for architecture-specific package instructions.")];
	if (section == BTPluginManagementSectionQuarantine)
		return _("Opening a .battman file only verifies it and saves a private quarantine copy. It never approves or loads code.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView;
	if (indexPath.section == BTPluginManagementSectionSecurity) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		if (indexPath.row == 0) {
			cell.textLabel.text = _("Third-Party Plug-ins");
			cell.detailTextLabel.text = self.snapshot.areThirdPartyPluginsEnabled ? _("Enabled Next Launch") : _("Disabled");
			UISwitch *toggle = [UISwitch new];
			toggle.on = self.snapshot.areThirdPartyPluginsEnabled;
			[toggle addTarget:self action:@selector(thirdPartySwitchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		} else {
			cell.textLabel.text = _("Start Without Third-Party Plug-ins");
			cell.detailTextLabel.text = _("Schedule one safe-mode launch");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		return cell;
	}
	if (indexPath.section == BTPluginManagementSectionRecovery) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = _("Disable Last Plug-in");
		cell.detailTextLabel.text = self.snapshot.recovery.pluginIdentifier;
		cell.textLabel.textColor = [UIColor redColor];
		return cell;
	}
	if (indexPath.section == BTPluginManagementSectionInstalled) {
		if (self.snapshot.installedPackages.count == 0) {
			UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
			cell.textLabel.text = _("No Installed Plug-ins");
			cell.textLabel.textColor = [UIColor grayColor];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			return cell;
		}
		BTPluginManagedInstalledPackage *item = self.snapshot.installedPackages[indexPath.row];
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = item.verifiedPackage.packageInspection.manifest.displayName ?:
			item.discoveredPackage.claimedPluginIdentifier;
		if (item.verifiedPackage) {
			BOOL enabled = item.activationRecord ? item.activationRecord.isEnabled :
				item.verifiedPackage.trustEvaluation.disposition == BTPluginTrustDispositionOfficial;
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ • %@",
				BTPluginTrustDescription(item.verifiedPackage.trustEvaluation.disposition),
				enabled ? _("Enabled") : _("Disabled")];
		} else {
			cell.detailTextLabel.text = _("Verification Failed");
			cell.detailTextLabel.textColor = [UIColor redColor];
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (indexPath.section == BTPluginManagementSectionQuarantine) {
		if (self.snapshot.quarantinedPackages.count == 0) {
			UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
			cell.textLabel.text = _("No Quarantined Plug-ins");
			cell.textLabel.textColor = [UIColor grayColor];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			return cell;
		}
		BTPluginQuarantinedPackage *package = self.snapshot.quarantinedPackages[indexPath.row];
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = package.verification.packageInspection.manifest.displayName;
		cell.detailTextLabel.text = BTPluginTrustDescription(package.verification.trustEvaluation.disposition);
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = _("Export Diagnostics");
	cell.detailTextLabel.text = [NSString stringWithFormat:_("%lu recorded issue(s)"),
		(unsigned long)self.snapshot.diagnostics.count];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)thirdPartySwitchChanged:(UISwitch *)toggle {
	if (!toggle.isOn) {
		NSError *error = nil;
		if (![self.platformProvider.managementService setThirdPartyPluginsEnabled:NO error:&error]) {
			toggle.on = YES;
			BTPluginPresentError(self, _("Plug-in Change Failed"), error);
			return;
		}
		[self refreshSnapshot];
		return;
	}
	toggle.on = NO;
	__weak typeof(self) weakSelf = self;
	UIAlertController *alert = BTPluginCreateThirdPartyEnableConsentAlert(^{
			__strong typeof(weakSelf) self = weakSelf; if (!self) return;
			NSError *error = nil;
			if (![self.platformProvider.managementService setThirdPartyPluginsEnabled:YES error:&error])
				BTPluginPresentError(self, _("Plug-in Change Failed"), error);
			[self refreshSnapshot];
		});
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)diagnosticText {
	NSDictionary *info = NSBundle.mainBundle.infoDictionary;
	NSMutableString *text = [NSMutableString stringWithFormat:
		@"Battman plug-in diagnostics v1\n"
		 @"host-version=%@\n"
		 @"host-build=%@\n"
		 @"generated-unix=%.0f\n"
		 @"safe-mode=%@\n"
		 @"third-party-enabled-next-launch=%@\n\n",
		info[@"CFBundleShortVersionString"] ?: @"unknown",
		info[@"CFBundleVersion"] ?: @"unknown",
		self.snapshot.generatedAt.timeIntervalSince1970,
		self.snapshot.isSafeMode ? @"yes" : @"no",
		self.snapshot.areThirdPartyPluginsEnabled ? @"yes" : @"no"];
	for (BTPluginManagedInstalledPackage *item in self.snapshot.installedPackages) {
		BTPluginVerifiedPackage *verified = item.verifiedPackage;
		[text appendFormat:@"installed %@ source=%@ digest=%@ trust=%@ enabled=%@ error=%@\n",
			item.discoveredPackage.claimedPluginIdentifier ?: @"unknown",
			BTPluginSourceName(item.discoveredPackage.source),
			verified.packageInspection.packageSHA256 ?: @"unverified",
			verified ? BTPluginTrustDiagnosticValue(verified.trustEvaluation.disposition) : @"unverified",
			item.activationRecord.isEnabled ? @"yes" : @"no",
			BTPluginDiagnosticErrorValue(item.verificationError)];
	}
	for (BTPluginQuarantinedPackage *package in self.snapshot.quarantinedPackages)
		[text appendFormat:@"quarantine %@ digest=%@ trust=%@\n",
			package.verification.packageInspection.manifest.pluginIdentifier,
			package.verification.packageInspection.packageSHA256,
			BTPluginTrustDiagnosticValue(package.verification.trustEvaluation.disposition)];
	for (NSError *error in self.snapshot.diagnostics)
		[text appendFormat:@"diagnostic error=%@\n", BTPluginDiagnosticErrorValue(error)];
	return text;
}

- (void)presentDiagnosticShareFromSourceView:(UIView *)sourceView sourceRect:(CGRect)sourceRect {
	UIActivityViewController *activity = [[UIActivityViewController alloc]
		initWithActivityItems:@[[self diagnosticText]] applicationActivities:nil];
	activity.popoverPresentationController.sourceView = sourceView;
	activity.popoverPresentationController.sourceRect = sourceRect;
	[self presentViewController:activity animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == BTPluginManagementSectionSecurity && indexPath.row == 1) {
		NSError *error = nil;
		if (![self.platformProvider requestSafeModeForNextLaunchWithError:&error])
			BTPluginPresentError(self, _("Safe Mode Could Not Be Scheduled"), error);
		else {
			UIAlertController *alert = BTPluginCreateSafeModeScheduledAlert();
			[self presentViewController:alert animated:YES completion:nil];
		}
		return;
	}
	if (indexPath.section == BTPluginManagementSectionRecovery) {
		NSError *error = nil;
		if (![self.platformProvider.managementService disableRecoveredPlugin:self.snapshot.recovery error:&error])
			BTPluginPresentError(self, _("Recovery Change Failed"), error);
		else [self refreshSnapshot];
		return;
	}
	if (indexPath.section == BTPluginManagementSectionInstalled && self.snapshot.installedPackages.count > 0) {
		BTPluginPackageDetailViewController *detail = [BTPluginPackageDetailViewController new];
		detail.service = self.platformProvider.managementService;
		detail.installedItem = self.snapshot.installedPackages[indexPath.row];
		__weak typeof(self) weakSelf = self;
		detail.changeHandler = ^{ [weakSelf refreshSnapshot]; };
		[self.navigationController pushViewController:detail animated:YES];
		return;
	}
	if (indexPath.section == BTPluginManagementSectionQuarantine && self.snapshot.quarantinedPackages.count > 0) {
		BTPluginPackageDetailViewController *detail = [BTPluginPackageDetailViewController new];
		detail.service = self.platformProvider.managementService;
		detail.quarantinedPackage = self.snapshot.quarantinedPackages[indexPath.row];
		BTPluginPackageManifest *priorManifest = nil;
		BTPluginPriorVersionComparisonStatus comparisonStatus =
			BTPluginPriorVersionComparisonForCandidate(detail.quarantinedPackage.verification,
				self.snapshot.installedPackages, &priorManifest);
		detail.priorManifest = priorManifest;
		detail.priorComparisonMessage = BTPluginPriorComparisonMessage(comparisonStatus);
		__weak typeof(self) weakSelf = self;
		detail.changeHandler = ^{ [weakSelf refreshSnapshot]; };
		[self.navigationController pushViewController:detail animated:YES];
		return;
	}
	if (indexPath.section == BTPluginManagementSectionDiagnostics) {
		CGRect sourceRect = [tableView rectForRowAtIndexPath:indexPath];
		__weak typeof(self) weakSelf = self;
		UIAlertController *alert = BTPluginCreateDiagnosticDisclosureAlert(^{
				__strong typeof(weakSelf) self = weakSelf;
				if (self)
					[self presentDiagnosticShareFromSourceView:tableView sourceRect:sourceRect];
			});
		[self presentViewController:alert animated:YES completion:nil];
	}
}

@end
