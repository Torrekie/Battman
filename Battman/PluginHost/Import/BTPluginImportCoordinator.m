//
//  BTPluginImportCoordinator.m
//  Battman
//

#import "BTPluginImportCoordinator.h"

#import <sys/stat.h>

#import "../Model/BTPluginPackageErrors.h"

NSNotificationName const BTPluginImportDidFinishNotification = @"BTPluginImportDidFinishNotification";
NSString * const BTPluginImportResultUserInfoKey = @"BTPluginImportResult";
NSString * const BTPluginImportErrorUserInfoKey = @"BTPluginImportError";

static NSError *BTPluginImportError(NSString *description, NSError *underlyingError) {
	return BTPluginPackageMakeError(BTPluginPackageErrorImport, description, nil, underlyingError);
}

@interface BTPluginImportResult ()
@property (nonatomic, strong, readwrite) BTPluginQuarantinedPackage *quarantinedPackage;
@property (nonatomic, strong, readwrite) NSDate *importedAt;
- (instancetype)bt_init;
@end

@implementation BTPluginImportResult
- (instancetype)bt_init { return [super init]; }
- (BOOL)isApprovedByExistingTrust { return self.quarantinedPackage.isApprovedForActivation; }
@end

@interface BTPluginImportCoordinator ()
@property (nonatomic, strong) BTPluginQuarantineStore *quarantineStore;
@property (nonatomic) dispatch_queue_t importQueue;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingCanonicalPaths;
@end

@implementation BTPluginImportCoordinator

- (instancetype)initWithQuarantineStore:(BTPluginQuarantineStore *)quarantineStore {
	self = [super init];
	if (!self)
		return nil;
	if (![quarantineStore isKindOfClass:[BTPluginQuarantineStore class]])
		return nil;
	_quarantineStore = quarantineStore;
	_importQueue = dispatch_queue_create("com.torrekie.Battman.PluginImport", DISPATCH_QUEUE_SERIAL);
	_pendingCanonicalPaths = [NSMutableSet set];
	return self;
}

- (BOOL)canHandlePackageURL:(NSURL *)packageURL {
	if (![packageURL isKindOfClass:[NSURL class]] || !packageURL.isFileURL ||
		![packageURL.pathExtension isEqualToString:@"battman"])
		return NO;
	NSString *name = packageURL.lastPathComponent;
	return name.length > @".battman".length &&
		[name isEqualToString:[name precomposedStringWithCanonicalMapping]];
}

- (BTPluginImportResult *)quarantineImportAtURL:(NSURL *)packageURL
											 developerMode:(BOOL)developerMode
													 error:(NSError **)error {
	if (![self canHandlePackageURL:packageURL]) {
		if (error)
			*error = BTPluginImportError(@"Battman can import only local .battman package directories.", nil);
		return nil;
	}
	struct stat packageStat;
	if (lstat(packageURL.fileSystemRepresentation, &packageStat) != 0 || !S_ISDIR(packageStat.st_mode) ||
		S_ISLNK(packageStat.st_mode)) {
		if (error)
			*error = BTPluginImportError(@"The selected .battman item is not a readable directory package.", nil);
		return nil;
	}
	BTPluginQuarantinedPackage *quarantined = [self.quarantineStore
		quarantinePackageAtURL:packageURL developerMode:developerMode error:error];
	if (!quarantined)
		return nil;
	BTPluginImportResult *result = [[BTPluginImportResult alloc] bt_init];
	result.quarantinedPackage = quarantined;
	result.importedAt = [NSDate date];
	return result;
}

- (BOOL)handleOpenPackageURL:(NSURL *)packageURL {
	if (![self canHandlePackageURL:packageURL])
		return NO;
	NSURL *capturedURL = [packageURL copy];
	NSString *pendingKey = capturedURL.URLByStandardizingPath.path;
	@synchronized (self) {
		if ([self.pendingCanonicalPaths containsObject:pendingKey])
			return YES;
		[self.pendingCanonicalPaths addObject:pendingKey];
	}
	dispatch_async(self.importQueue, ^{
		BOOL scoped = [capturedURL startAccessingSecurityScopedResource];
		__block BTPluginImportResult *result = nil;
		__block NSError *resultError = nil;
		NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
		NSError *coordinationError = nil;
		[coordinator coordinateReadingItemAtURL:capturedURL
			options:NSFileCoordinatorReadingWithoutChanges error:&coordinationError
			byAccessor:^(NSURL *coordinatedURL) {
				result = [self quarantineImportAtURL:coordinatedURL developerMode:NO error:&resultError];
			}];
		if (!result && !resultError && coordinationError)
			resultError = BTPluginImportError(@"The plug-in package could not be read safely.", coordinationError);
		if (scoped)
			[capturedURL stopAccessingSecurityScopedResource];
		@synchronized (self) {
			[self.pendingCanonicalPaths removeObject:pendingKey];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
			if (result)
				userInfo[BTPluginImportResultUserInfoKey] = result;
			if (resultError)
				userInfo[BTPluginImportErrorUserInfoKey] = resultError;
			[[NSNotificationCenter defaultCenter] postNotificationName:BTPluginImportDidFinishNotification
				object:self userInfo:userInfo];
		});
	});
	return YES;
}

@end
