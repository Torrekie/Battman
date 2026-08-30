//
//  BTPluginManagementLineage.m
//  Battman
//
//  Host-internal, non-authorizing prior-version disclosure model.  Kept
//  separate from the UIKit controller so simulator evidence can link the
//  production selector without pulling in the full management service.
//

#import "BTPluginManagementService.h"

BTPluginPriorVersionComparisonStatus BTPluginPriorVersionComparisonForCandidate(
	BTPluginVerifiedPackage *candidate, NSArray<BTPluginManagedInstalledPackage *> *installedPackages,
	BTPluginPackageManifest **priorManifest) {
	if (priorManifest)
		*priorManifest = nil;
	if (![candidate respondsToSelector:@selector(packageInspection)] ||
		![installedPackages isKindOfClass:[NSArray class]] || !candidate.packageInspection.manifest)
		return BTPluginPriorVersionComparisonStatusUnavailable;
	NSString *pluginIdentifier = candidate.packageInspection.manifest.pluginIdentifier;
	NSMutableArray<BTPluginManagedInstalledPackage *> *matches = [NSMutableArray array];
	for (id value in installedPackages) {
		if (![value respondsToSelector:@selector(discoveredPackage)] ||
			![value respondsToSelector:@selector(verifiedPackage)] ||
			![value respondsToSelector:@selector(activationRecord)])
			return BTPluginPriorVersionComparisonStatusUnavailable;
		BTPluginManagedInstalledPackage *installed = value;
		if ([installed.discoveredPackage.claimedPluginIdentifier isEqualToString:pluginIdentifier])
			[matches addObject:installed];
	}
	if (matches.count == 0)
		return BTPluginPriorVersionComparisonStatusNoInstalledVersion;
	if (matches.count != 1)
		return BTPluginPriorVersionComparisonStatusAmbiguousInstalledRepresentations;
	BTPluginManagedInstalledPackage *installed = matches.firstObject;
	BTPluginVerifiedPackage *verified = installed.verifiedPackage;
	if (!verified)
		return BTPluginPriorVersionComparisonStatusPriorVerificationFailed;
	if (!verified.isApprovedForActivation)
		return BTPluginPriorVersionComparisonStatusPriorNotApproved;
	BTPluginActivationRecord *record = installed.activationRecord;
	BOOL officialWithoutRecord = verified.trustEvaluation.disposition == BTPluginTrustDispositionOfficial &&
		installed.discoveredPackage.source != BTPluginSourceApplicationData && record == nil;
	if (!officialWithoutRecord) {
		BOOL directMatch = record.activationMode == BTPluginActivationModeDirect &&
			record.source == installed.discoveredPackage.source;
		BOOL replacementMatch =
			installed.discoveredPackage.representation == BTPluginInstalledRepresentationSealedAppBundle &&
			record.activationMode == BTPluginActivationModeRequiresReinstall &&
			record.source == BTPluginSourceImport;
		if (!record || (!directMatch && !replacementMatch) ||
			![record.pluginIdentifier isEqualToString:pluginIdentifier] ||
			![record.packageSHA256 isEqualToString:verified.packageInspection.packageSHA256])
			return BTPluginPriorVersionComparisonStatusActivationMismatch;
	}
	BTPluginPackageManifest *installedManifest = verified.packageInspection.manifest;
	switch (BTPluginManifestUpdateLineageStatusFromManifests(installedManifest,
		candidate.packageInspection.manifest)) {
		case BTPluginManifestUpdateLineageStatusAvailable:
			if (priorManifest)
				*priorManifest = installedManifest;
			return BTPluginPriorVersionComparisonStatusAvailable;
		case BTPluginManifestUpdateLineageStatusPublisherChanged:
			return BTPluginPriorVersionComparisonStatusPublisherChanged;
		case BTPluginManifestUpdateLineageStatusNotNewer:
			return BTPluginPriorVersionComparisonStatusCandidateNotNewer;
		case BTPluginManifestUpdateLineageStatusNoPriorVersion:
		case BTPluginManifestUpdateLineageStatusDifferentPlugin:
			return BTPluginPriorVersionComparisonStatusUnavailable;
	}
	return BTPluginPriorVersionComparisonStatusUnavailable;
}
