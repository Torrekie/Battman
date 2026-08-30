//
//  BTPluginDiscovery.m
//  Battman
//

#import "BTPluginDiscovery.h"

#import <dirent.h>
#import <fcntl.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../BTPluginIdentifiers.h"
#import "../Model/BTPluginPackageErrors.h"

static NSError *BTPluginDiscoveryError(NSString *description, NSURL *url, int posixCode) {
	NSError *underlying = posixCode == 0 ? nil :
		[NSError errorWithDomain:NSPOSIXErrorDomain code:posixCode userInfo:nil];
	return BTPluginPackageMakeError(BTPluginPackageErrorUnsafePath, description,
		url.lastPathComponent, underlying);
}

static BOOL BTPluginDiscoveryNameIsCanonical(NSString *name) {
	if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 255 ||
		![name isEqualToString:[name precomposedStringWithCanonicalMapping]] ||
		[name isEqualToString:@"."] || [name isEqualToString:@".."] ||
		[name rangeOfString:@"/"].location != NSNotFound || [name rangeOfString:@"\\"].location != NSNotFound)
		return NO;
	for (NSUInteger index = 0; index < name.length; index++) {
		unichar character = [name characterAtIndex:index];
		if (character < 0x20 || character == 0x7f)
			return NO;
	}
	return YES;
}

static BOOL BTPluginDiscoveryRootPermissionsAreSafe(struct stat rootStat, BTPluginSource source) {
	if (!S_ISDIR(rootStat.st_mode) || (rootStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) != 0)
		return NO;
	if (source == BTPluginSourceRootedSystem || source == BTPluginSourceRootlessSystem)
		return rootStat.st_uid == 0;
	if (source == BTPluginSourceApplicationData || source == BTPluginSourceQuarantine)
		return rootStat.st_uid == geteuid();
	return YES;
}

static const NSUInteger BTPluginDiscoveryMaximumRoots = 16;
static const NSUInteger BTPluginDiscoveryMaximumEntriesPerRoot = 4096;
static const NSUInteger BTPluginDiscoveryMaximumCandidatesPerRoot = 256;

static BOOL BTPluginDiscoverySourceIsInstalled(BTPluginSource source) {
	return source == BTPluginSourceAppBundle || source == BTPluginSourceApplicationData ||
		source == BTPluginSourceRootedSystem || source == BTPluginSourceRootlessSystem;
}

@interface BTPluginDiscoveryRoot ()
@property (nonatomic, strong, readwrite) NSURL *rootURL;
@property (nonatomic, strong, readwrite, nullable) NSURL *metadataRootURL;
@property (nonatomic, readwrite) BTPluginSource source;
@property (nonatomic, readwrite) BTPluginInstalledRepresentation representation;
- (instancetype)bt_init;
@end

@implementation BTPluginDiscoveryRoot

- (instancetype)bt_init {
	return [super init];
}

+ (instancetype)transportPackageRootURL:(NSURL *)rootURL source:(BTPluginSource)source {
	BTPluginDiscoveryRoot *root = [[BTPluginDiscoveryRoot alloc] bt_init];
	root.rootURL = rootURL;
	root.source = source;
	root.representation = BTPluginInstalledRepresentationTransportPackage;
	return root;
}

+ (instancetype)sealedAppBundleRootURL:(NSURL *)rootURL metadataRootURL:(NSURL *)metadataRootURL {
	BTPluginDiscoveryRoot *root = [[BTPluginDiscoveryRoot alloc] bt_init];
	root.rootURL = rootURL;
	root.metadataRootURL = metadataRootURL;
	root.source = BTPluginSourceAppBundle;
	root.representation = BTPluginInstalledRepresentationSealedAppBundle;
	return root;
}

@end

@interface BTPluginDiscoveredPackage ()
@property (nonatomic, copy, readwrite) NSString *claimedPluginIdentifier;
@property (nonatomic, strong, readwrite) NSURL *packageURL;
@property (nonatomic, strong, readwrite, nullable) NSURL *payloadURL;
@property (nonatomic, strong, readwrite, nullable) NSURL *metadataURL;
@property (nonatomic, readwrite) BTPluginSource source;
@property (nonatomic, readwrite) BTPluginInstalledRepresentation representation;
@property (nonatomic, copy, readwrite) NSString *stableLocationKey;
- (instancetype)bt_init;
@end

@implementation BTPluginDiscoveredPackage
- (instancetype)bt_init {
	return [super init];
}
@end

@interface BTPluginDiscoveryDiagnostic ()
@property (nonatomic, strong, readwrite) NSURL *url;
@property (nonatomic, readwrite) BTPluginSource source;
@property (nonatomic, strong, readwrite) NSError *error;
- (instancetype)bt_init;
@end

@implementation BTPluginDiscoveryDiagnostic
- (instancetype)bt_init {
	return [super init];
}
@end

@interface BTPluginDiscoveryResult ()
@property (nonatomic, copy, readwrite) NSArray<BTPluginDiscoveredPackage *> *packages;
@property (nonatomic, copy, readwrite) NSArray<BTPluginDiscoveryDiagnostic *> *diagnostics;
- (instancetype)bt_init;
@end

@implementation BTPluginDiscoveryResult
- (instancetype)bt_init {
	return [super init];
}
@end

@implementation BTPluginDiscovery

+ (NSArray<BTPluginDiscoveryRoot *> *)defaultRootsForApplicationSupportURL:(NSURL *)applicationSupportURL
																 mainBundleURL:(NSURL *)mainBundleURL {
	NSURL *hostSupport = [applicationSupportURL URLByAppendingPathComponent:@"Battman" isDirectory:YES];
	return @[
		[BTPluginDiscoveryRoot sealedAppBundleRootURL:[mainBundleURL URLByAppendingPathComponent:@"PlugIns" isDirectory:YES]
			metadataRootURL:[mainBundleURL URLByAppendingPathComponent:@"PluginManifests" isDirectory:YES]],
		[BTPluginDiscoveryRoot transportPackageRootURL:[hostSupport URLByAppendingPathComponent:@"PlugIns" isDirectory:YES]
			source:BTPluginSourceApplicationData],
		[BTPluginDiscoveryRoot transportPackageRootURL:[NSURL fileURLWithPath:@"/Library/Battman/PlugIns" isDirectory:YES]
			source:BTPluginSourceRootedSystem],
		[BTPluginDiscoveryRoot transportPackageRootURL:[NSURL fileURLWithPath:@"/var/jb/Library/Battman/PlugIns" isDirectory:YES]
			source:BTPluginSourceRootlessSystem],
	];
}

- (BTPluginDiscoveryResult *)discoverRoots:(NSArray<BTPluginDiscoveryRoot *> *)roots {
	NSMutableArray<BTPluginDiscoveredPackage *> *packages = [NSMutableArray array];
	NSMutableArray<BTPluginDiscoveryDiagnostic *> *diagnostics = [NSMutableArray array];
	NSMutableSet<NSString *> *locationKeys = [NSMutableSet set];
	NSUInteger rootCount = 0;
	for (id value in roots) {
		if (rootCount >= BTPluginDiscoveryMaximumRoots)
			break;
		if (![value isKindOfClass:[BTPluginDiscoveryRoot class]])
			continue;
		BTPluginDiscoveryRoot *root = value;
		rootCount++;
		BOOL validRoot = root.rootURL.isFileURL && root.rootURL.path.isAbsolutePath &&
			BTPluginDiscoverySourceIsInstalled(root.source) &&
			(root.representation == BTPluginInstalledRepresentationTransportPackage ||
			 root.representation == BTPluginInstalledRepresentationSealedAppBundle) &&
			(root.representation != BTPluginInstalledRepresentationSealedAppBundle ||
			 (root.source == BTPluginSourceAppBundle && root.metadataRootURL.isFileURL &&
			  root.metadataRootURL.path.isAbsolutePath));
		if (!validRoot) {
			BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
			diagnostic.url = root.rootURL ?: [NSURL fileURLWithPath:@"/" isDirectory:YES];
			diagnostic.source = root.source;
			diagnostic.error = BTPluginDiscoveryError(@"A plug-in discovery root is invalid.", diagnostic.url, 0);
			[diagnostics addObject:diagnostic];
			continue;
		}
		int rootDescriptor = open(root.rootURL.fileSystemRepresentation,
			O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
		if (rootDescriptor < 0) {
			if (errno != ENOENT) {
				BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
				diagnostic.url = root.rootURL;
				diagnostic.source = root.source;
				diagnostic.error = BTPluginDiscoveryError(@"A plug-in discovery root could not be opened safely.", root.rootURL, errno);
				[diagnostics addObject:diagnostic];
			}
			continue;
		}
		struct stat rootStat;
		if (fstat(rootDescriptor, &rootStat) != 0 || !BTPluginDiscoveryRootPermissionsAreSafe(rootStat, root.source)) {
			BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
			diagnostic.url = root.rootURL;
			diagnostic.source = root.source;
			diagnostic.error = BTPluginDiscoveryError(@"A plug-in discovery root has unsafe ownership or permissions.", root.rootURL, 0);
			[diagnostics addObject:diagnostic];
			close(rootDescriptor);
			continue;
		}
		DIR *directory = fdopendir(rootDescriptor);
		if (!directory) {
			int savedErrno = errno;
			close(rootDescriptor);
			BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
			diagnostic.url = root.rootURL;
			diagnostic.source = root.source;
			diagnostic.error = BTPluginDiscoveryError(@"A plug-in discovery root could not be enumerated.", root.rootURL, savedErrno);
			[diagnostics addObject:diagnostic];
			continue;
		}
		int metadataRootDescriptor = -1;
		if (root.representation == BTPluginInstalledRepresentationSealedAppBundle) {
			metadataRootDescriptor = open(root.metadataRootURL.fileSystemRepresentation,
				O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
			struct stat metadataRootStat;
			if (metadataRootDescriptor < 0 || fstat(metadataRootDescriptor, &metadataRootStat) != 0 ||
				!BTPluginDiscoveryRootPermissionsAreSafe(metadataRootStat, BTPluginSourceAppBundle)) {
				int savedErrno = metadataRootDescriptor < 0 ? errno : 0;
				if (metadataRootDescriptor >= 0)
					close(metadataRootDescriptor);
				BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
				diagnostic.url = root.metadataRootURL;
				diagnostic.source = root.source;
				diagnostic.error = BTPluginDiscoveryError(@"The sealed plug-in metadata root is missing or unsafe.", root.metadataRootURL, savedErrno);
				[diagnostics addObject:diagnostic];
				closedir(directory);
				continue;
			}
		}

		NSMutableArray<NSString *> *names = [NSMutableArray array];
		NSUInteger entryCount = 0;
		int enumerationError = 0;
		while (entryCount < BTPluginDiscoveryMaximumEntriesPerRoot) {
			errno = 0;
			struct dirent *entry = readdir(directory);
			if (!entry) {
				enumerationError = errno;
				break;
			}
			entryCount++;
			NSString *name = [[NSString alloc] initWithBytes:entry->d_name length:strlen(entry->d_name)
				encoding:NSUTF8StringEncoding];
			if (!BTPluginDiscoveryNameIsCanonical(name))
				continue;
			BOOL expectedExtension = root.representation == BTPluginInstalledRepresentationTransportPackage ?
				[name.pathExtension isEqualToString:@"battman"] : [name.pathExtension isEqualToString:@"bundle"];
			if (expectedExtension && BTPluginIdentifierIsValid(name.stringByDeletingPathExtension) &&
				names.count < BTPluginDiscoveryMaximumCandidatesPerRoot)
				[names addObject:name];
		}
		if (entryCount == BTPluginDiscoveryMaximumEntriesPerRoot && enumerationError == 0)
			enumerationError = EOVERFLOW;
		[names sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
			return [left compare:right options:NSLiteralSearch];
		}];
		for (NSString *name in names) {
			struct stat childStat;
			if (fstatat(dirfd(directory), name.fileSystemRepresentation, &childStat, AT_SYMLINK_NOFOLLOW) != 0 ||
				!S_ISDIR(childStat.st_mode) || (childStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) != 0 ||
				((root.source == BTPluginSourceRootedSystem || root.source == BTPluginSourceRootlessSystem) && childStat.st_uid != 0) ||
				(root.source == BTPluginSourceApplicationData && childStat.st_uid != geteuid())) {
				BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
				diagnostic.url = [root.rootURL URLByAppendingPathComponent:name isDirectory:YES];
				diagnostic.source = root.source;
				diagnostic.error = BTPluginDiscoveryError(@"A discovered plug-in candidate has unsafe type, ownership, or permissions.", diagnostic.url, 0);
				[diagnostics addObject:diagnostic];
				continue;
			}
			NSURL *childURL = [root.rootURL URLByAppendingPathComponent:name isDirectory:YES];
			NSURL *metadataURL = nil;
			if (root.representation == BTPluginInstalledRepresentationSealedAppBundle) {
				NSString *metadataName = name.stringByDeletingPathExtension;
				metadataURL = [root.metadataRootURL URLByAppendingPathComponent:metadataName isDirectory:YES];
				struct stat metadataStat;
				if (fstatat(metadataRootDescriptor, metadataName.fileSystemRepresentation, &metadataStat, AT_SYMLINK_NOFOLLOW) != 0 ||
					!S_ISDIR(metadataStat.st_mode) ||
					(metadataStat.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) != 0) {
					BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
					diagnostic.url = childURL;
					diagnostic.source = root.source;
					diagnostic.error = BTPluginDiscoveryError(@"A sealed app-bundle plug-in has no matching safe metadata package.", metadataURL, 0);
					[diagnostics addObject:diagnostic];
					continue;
				}
			}
			NSString *locationKey = [NSString stringWithFormat:@"%@:%@:%@", BTPluginSourceName(root.source),
				root.representation == BTPluginInstalledRepresentationSealedAppBundle ? @"sealed" : @"package", childURL.path];
			if ([locationKeys containsObject:locationKey])
				continue;
			[locationKeys addObject:locationKey];
			BTPluginDiscoveredPackage *package = [[BTPluginDiscoveredPackage alloc] bt_init];
			package.claimedPluginIdentifier = name.stringByDeletingPathExtension;
			package.packageURL = root.representation == BTPluginInstalledRepresentationTransportPackage ? childURL : metadataURL;
			package.payloadURL = root.representation == BTPluginInstalledRepresentationSealedAppBundle ? childURL : nil;
			package.metadataURL = metadataURL;
			package.source = root.source;
			package.representation = root.representation;
			package.stableLocationKey = locationKey;
			[packages addObject:package];
		}
		if (metadataRootDescriptor >= 0)
			close(metadataRootDescriptor);
		closedir(directory);
		if (enumerationError != 0) {
			BTPluginDiscoveryDiagnostic *diagnostic = [[BTPluginDiscoveryDiagnostic alloc] bt_init];
			diagnostic.url = root.rootURL;
			diagnostic.source = root.source;
			diagnostic.error = BTPluginDiscoveryError(@"A plug-in discovery root changed or failed during enumeration.", root.rootURL, enumerationError);
			[diagnostics addObject:diagnostic];
		}
	}
	[packages sortUsingComparator:^NSComparisonResult(BTPluginDiscoveredPackage *left, BTPluginDiscoveredPackage *right) {
		if (left.source != right.source)
			return left.source < right.source ? NSOrderedAscending : NSOrderedDescending;
		return [left.stableLocationKey compare:right.stableLocationKey options:NSLiteralSearch];
	}];
	[diagnostics sortUsingComparator:^NSComparisonResult(BTPluginDiscoveryDiagnostic *left, BTPluginDiscoveryDiagnostic *right) {
		if (left.source != right.source)
			return left.source < right.source ? NSOrderedAscending : NSOrderedDescending;
		return [left.url.path compare:right.url.path options:NSLiteralSearch];
	}];
	BTPluginDiscoveryResult *result = [[BTPluginDiscoveryResult alloc] bt_init];
	result.packages = packages;
	result.diagnostics = diagnostics;
	return result;
}

@end
