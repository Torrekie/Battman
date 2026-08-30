//
//  BTPluginOfficialTrustLoader.m
//  Battman
//


#import "BTPluginOfficialTrustLoader.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Security/Security.h>
#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <math.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../Model/BTPluginPackageErrors.h"
#import "../Model/BTPluginPackageManifest.h"
#import "BTPluginP256.h"
#import "BTPluginTrustMetadataVerifier.h"

#if DEBUG
// Disposable engineering trust roots must not advance or equivocate the
// production rollback record on a simulator or development device.
static NSString * const BTPluginDefaultTrustMetadataStateService =
	@"com.torrekie.Battman.PluginTrustMetadata.debug.v1";
#else
static NSString * const BTPluginDefaultTrustMetadataStateService =
	@"com.torrekie.Battman.PluginTrustMetadata.v1";
#endif
static NSString * const BTPluginTrustMetadataStateAccount = @"official-metadata";
static const uint64_t BTPluginRootPolicyMaximumByteCount = 64ULL * 1024ULL;
static const uint64_t BTPluginTrustMetadataMaximumByteCount = 256ULL * 1024ULL;
static const uint64_t BTPluginTrustSignatureMaximumByteCount = 256;
static const NSUInteger BTPluginTrustSignatureMaximumCount = 8;
static const uint64_t BTPluginTrustMaximumJSONInteger = 9007199254740991ULL;
static const NSUInteger BTPluginTrustMetadataStateMaximumByteCount = 64 * 1024;

static BOOL BTPluginOfficialTrustFail(NSError **error,
	BTPluginPackageErrorCode code,
	NSString *description,
	NSString *relativePath,
	NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(code, description, relativePath, underlyingError);
	return NO;
}

static NSError *BTPluginOfficialTrustPOSIXError(int code) {
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

static BOOL BTPluginOfficialTrustStatIsUnchanged(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_size == right->st_size && left->st_mode == right->st_mode &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static BOOL BTPluginOfficialTrustDirectoryIsSafe(struct stat value) {
	mode_t unsafe = S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX;
	return S_ISDIR(value.st_mode) && (value.st_mode & unsafe) == 0 &&
		(value.st_mode & (S_IRUSR | S_IXUSR)) == (S_IRUSR | S_IXUSR);
}

static NSData *BTPluginOfficialTrustReadFile(int parentDescriptor,
	NSString *name,
	uint64_t maximumByteCount,
	NSString *relativePath,
	NSError **error) {
	int descriptor = openat(parentDescriptor, name.fileSystemRepresentation,
		O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorMissingFile,
			@"An official trust resource could not be opened without following links.",
			relativePath, BTPluginOfficialTrustPOSIXError(errno));
		return nil;
	}
	struct stat before;
	if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_nlink != 1 ||
		before.st_size <= 0 || (uint64_t)before.st_size > maximumByteCount ||
		(before.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID | S_ISVTX)) != 0 ||
		(before.st_mode & S_IRUSR) == 0) {
		int status = errno;
		close(descriptor);
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnsafePath,
			@"An official trust resource has an unsafe type, link count, size, or mode.",
			relativePath, status == 0 ? nil : BTPluginOfficialTrustPOSIXError(status));
		return nil;
	}
	NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)before.st_size];
	uint8_t *cursor = data.mutableBytes;
	NSUInteger remaining = data.length;
	while (remaining > 0) {
		ssize_t count = read(descriptor, cursor, remaining);
		if (count <= 0) {
			int status = count < 0 ? errno : EIO;
			close(descriptor);
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
				@"An official trust resource could not be read completely.", relativePath,
				BTPluginOfficialTrustPOSIXError(status));
			return nil;
		}
		cursor += count;
		remaining -= (NSUInteger)count;
	}
	struct stat after;
	BOOL unchanged = fstat(descriptor, &after) == 0 &&
		BTPluginOfficialTrustStatIsUnchanged(&before, &after);
	close(descriptor);
	if (!unchanged) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorRaceDetected,
			@"An official trust resource changed while it was being read.", relativePath, nil);
		return nil;
	}
	return data;
}

static NSSet<NSString *> *BTPluginOfficialTrustDirectoryEntries(int descriptor,
	NSString *relativePath,
	NSUInteger maximumCount,
	NSError **error) {
	int duplicate = dup(descriptor);
	if (duplicate < 0) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
			@"An official trust directory could not be inspected.", relativePath,
			BTPluginOfficialTrustPOSIXError(errno));
		return nil;
	}
	DIR *directory = fdopendir(duplicate);
	if (!directory) {
		int status = errno;
		close(duplicate);
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
			@"An official trust directory could not be inspected.", relativePath,
			BTPluginOfficialTrustPOSIXError(status));
		return nil;
	}
	NSMutableSet<NSString *> *entries = [NSMutableSet set];
	errno = 0;
	struct dirent *entry = NULL;
	while ((entry = readdir(directory)) != NULL) {
		if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
			continue;
		NSString *name = [[NSString alloc] initWithBytes:entry->d_name
			length:strlen(entry->d_name) encoding:NSUTF8StringEncoding];
		if (!name || name.length == 0 || [entries containsObject:name] || entries.count >= maximumCount) {
			closedir(directory);
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnexpectedFile,
				@"An official trust directory contains invalid or excessive entries.", relativePath, nil);
			return nil;
		}
		[entries addObject:name];
	}
	int status = errno;
	closedir(directory);
	if (status != 0) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
			@"An official trust directory could not be enumerated completely.", relativePath,
			BTPluginOfficialTrustPOSIXError(status));
		return nil;
	}
	return entries;
}

static BOOL BTPluginOfficialTrustObjectHasExactKeys(NSDictionary *dictionary,
	NSArray<NSString *> *expectedKeys) {
	if (![dictionary isKindOfClass:[NSDictionary class]])
		return NO;
	for (id key in dictionary.allKeys) {
		if (![key isKindOfClass:[NSString class]])
			return NO;
	}
	return [[NSSet setWithArray:dictionary.allKeys]
		isEqualToSet:[NSSet setWithArray:expectedKeys]];
}

static BOOL BTPluginOfficialTrustInteger(id value,
	uint64_t minimum,
	uint64_t maximum,
	uint64_t *output) {
	if (![value isKindOfClass:[NSNumber class]] ||
		CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
		return NO;
	double number = [value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < (double)minimum ||
		number > (double)maximum)
		return NO;
	uint64_t result = [value unsignedLongLongValue];
	if ((double)result != number)
		return NO;
	if (output)
		*output = result;
	return YES;
}

static BTPluginRootTrustPolicy *BTPluginOfficialTrustParseRootPolicy(NSData *data,
	NSError **error) {
	NSError *propertyListError = nil;
	id object = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&propertyListError];
	if (!BTPluginOfficialTrustObjectHasExactKeys(object,
		@[ @"schemaVersion", @"signatureThreshold", @"rootPublicKeys" ])) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"RootPolicy.plist has missing, malformed, or unknown keys.", @"RootPolicy.plist",
			propertyListError);
		return nil;
	}
	NSDictionary *dictionary = object;
	uint64_t threshold = 0;
	NSArray *rootPublicKeys = dictionary[@"rootPublicKeys"];
	if (!BTPluginOfficialTrustInteger(dictionary[@"schemaVersion"], 1, 1, NULL) ||
		!BTPluginOfficialTrustInteger(dictionary[@"signatureThreshold"], 1, 8, &threshold) ||
		![rootPublicKeys isKindOfClass:[NSArray class]] || rootPublicKeys.count == 0 ||
		rootPublicKeys.count > 8 || threshold > rootPublicKeys.count) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidInfoPlist,
			@"RootPolicy.plist has an invalid schema, threshold, or key count.", @"RootPolicy.plist", nil);
		return nil;
	}
	NSMutableDictionary<NSString *, NSData *> *keys = [NSMutableDictionary dictionary];
	NSString *previousIdentifier = nil;
	for (id value in rootPublicKeys) {
		if (!BTPluginOfficialTrustObjectHasExactKeys(value,
			@[ @"keyIdentifier", @"publicKeyX963Base64" ])) {
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"RootPolicy.plist contains a malformed root-key record.", @"RootPolicy.plist", nil);
			return nil;
		}
		NSString *keyIdentifier = value[@"keyIdentifier"];
		NSString *base64 = value[@"publicKeyX963Base64"];
		if (!BTPluginPackageLowercaseSHA256IsValid(keyIdentifier) ||
			![base64 isKindOfClass:[NSString class]] || base64.length != 88 ||
			(previousIdentifier && [previousIdentifier compare:keyIdentifier options:NSLiteralSearch] != NSOrderedAscending)) {
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidInfoPlist,
				@"RootPolicy.plist root keys must be unique, fingerprinted, and bytewise sorted.",
				@"RootPolicy.plist", nil);
			return nil;
		}
		NSData *publicKey = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
		if (!BTPluginP256PublicKeyMatchesIdentifier(publicKey, keyIdentifier) ||
			![[publicKey base64EncodedStringWithOptions:0] isEqualToString:base64]) {
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidSignature,
				@"RootPolicy.plist contains an invalid root public key.", @"RootPolicy.plist", nil);
			return nil;
		}
		keys[keyIdentifier] = publicKey;
		previousIdentifier = keyIdentifier;
	}
	return [[BTPluginRootTrustPolicy alloc] initWithRootPublicKeysByIdentifier:keys
		signatureThreshold:(NSUInteger)threshold error:error];
}

static NSError *BTPluginTrustMetadataStateError(NSString *description, OSStatus status) {
	NSError *underlying = status == errSecSuccess ? nil :
		[NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
	return BTPluginPackageMakeError(BTPluginPackageErrorTrustStore, description, nil, underlying);
}

@interface BTPluginKeychainTrustMetadataStateStore ()
@property (nonatomic, copy) NSString *serviceName;
@end

@implementation BTPluginKeychainTrustMetadataStateStore

- (instancetype)init {
	return [self initWithServiceName:BTPluginDefaultTrustMetadataStateService];
}

- (instancetype)initWithServiceName:(NSString *)serviceName {
	self = [super init];
	if (self)
		_serviceName = ([serviceName isKindOfClass:[NSString class]] &&
			serviceName.length > 0 && serviceName.length <= 255) ? [serviceName copy] :
			[BTPluginDefaultTrustMetadataStateService copy];
	return self;
}

- (NSDictionary *)baseQuery {
	return @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: self.serviceName,
		(__bridge id)kSecAttrAccount: BTPluginTrustMetadataStateAccount,
		(__bridge id)kSecAttrSynchronizable: @NO,
	};
}

- (NSDictionary *)readRecordNotFound:(BOOL *)notFound error:(NSError **)error {
	NSMutableDictionary *query = [[self baseQuery] mutableCopy];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status == errSecItemNotFound) {
		if (notFound)
			*notFound = YES;
		return nil;
	}
	if (status != errSecSuccess || !result || CFGetTypeID(result) != CFDataGetTypeID()) {
		if (result)
			CFRelease(result);
		if (error)
			*error = BTPluginTrustMetadataStateError(
				@"The official trust-metadata state could not be read from Keychain.", status);
		return nil;
	}
	NSData *data = CFBridgingRelease(result);
	if (data.length == 0 || data.length > BTPluginTrustMetadataStateMaximumByteCount) {
		if (error)
			*error = BTPluginTrustMetadataStateError(
				@"The official trust-metadata Keychain state exceeds its size limit.", errSecSuccess);
		return nil;
	}
	NSError *propertyListError = nil;
	id record = [NSPropertyListSerialization propertyListWithData:data
		options:NSPropertyListImmutable format:NULL error:&propertyListError];
	if (!BTPluginOfficialTrustObjectHasExactKeys(record,
		@[ @"schema", @"type", @"sequence", @"metadataSHA256" ]) ||
		![record[@"schema"] isEqual:@1] || ![record[@"type"] isEqual:@"official-metadata"] ||
		!BTPluginOfficialTrustInteger(record[@"sequence"], 1, BTPluginTrustMaximumJSONInteger, NULL) ||
		!BTPluginPackageLowercaseSHA256IsValid(record[@"metadataSHA256"])) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"The official trust-metadata Keychain state is malformed.", nil, propertyListError);
		return nil;
	}
	if (notFound)
		*notFound = NO;
	return record;
}

- (BOOL)readPreviousSequence:(uint64_t *)sequence
					 metadataSHA256:(NSString **)metadataSHA256
								 error:(NSError **)error {
	if (!sequence || !metadataSHA256) {
		if (error)
			*error = BTPluginTrustMetadataStateError(
				@"The trust-metadata state outputs are missing.", errSecSuccess);
		return NO;
	}
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *record = [self readRecordNotFound:&notFound error:error];
		if (notFound) {
			*sequence = 0;
			*metadataSHA256 = nil;
			return YES;
		}
		if (!record)
			return NO;
		*sequence = [record[@"sequence"] unsignedLongLongValue];
		*metadataSHA256 = record[@"metadataSHA256"];
		return YES;
	}
}

- (BOOL)storeRecord:(NSDictionary *)record error:(NSError **)error {
	NSError *serializationError = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:record
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&serializationError];
	if (!data) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorTrustStore,
				@"The official trust-metadata state could not be serialized.", nil, serializationError);
		return NO;
	}
	NSDictionary *query = [self baseQuery];
	NSDictionary *update = @{ (__bridge id)kSecValueData: data };
	OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
	if (status == errSecItemNotFound) {
		NSMutableDictionary *addition = [query mutableCopy];
		addition[(__bridge id)kSecValueData] = data;
		addition[(__bridge id)kSecAttrAccessible] =
			(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		status = SecItemAdd((__bridge CFDictionaryRef)addition, NULL);
	}
	if (status == errSecSuccess)
		return YES;
	if (error)
		*error = BTPluginTrustMetadataStateError(
			@"The official trust-metadata state could not be stored in Keychain.", status);
	return NO;
}

- (BOOL)recordSequence:(uint64_t)sequence
			 metadataSHA256:(NSString *)metadataSHA256
						 error:(NSError **)error {
	if (sequence == 0 || sequence > BTPluginTrustMaximumJSONInteger ||
		!BTPluginPackageLowercaseSHA256IsValid(metadataSHA256)) {
		if (error)
			*error = BTPluginTrustMetadataStateError(
				@"The official trust-metadata state update is invalid.", errSecSuccess);
		return NO;
	}
	@synchronized (self) {
		BOOL notFound = NO;
		NSDictionary *current = [self readRecordNotFound:&notFound error:error];
		if (!notFound && !current)
			return NO;
		if (current) {
			uint64_t currentSequence = [current[@"sequence"] unsignedLongLongValue];
			NSString *currentDigest = current[@"metadataSHA256"];
			if (currentSequence > sequence ||
				(currentSequence == sequence && ![currentDigest isEqualToString:metadataSHA256])) {
				if (error)
					*error = BTPluginPackageMakeError(BTPluginPackageErrorRollback,
						@"A lower or conflicting official trust-metadata state cannot be recorded.", nil, nil);
				return NO;
			}
			if (currentSequence == sequence)
				return YES;
		}
		return [self storeRecord:@{
			@"schema": @1,
			@"type": @"official-metadata",
			@"sequence": @(sequence),
			@"metadataSHA256": metadataSHA256,
		} error:error];
	}
}

@end

@interface BTPluginOfficialTrustLoadResult ()
@property (nonatomic, strong, readwrite) BTPluginTrustPolicy *trustPolicy;
@property (nonatomic, readwrite, getter=isSignedMetadataLoaded) BOOL signedMetadataLoaded;
@property (nonatomic, copy, readwrite, nullable) NSString *metadataSHA256;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *verifiedRootKeyIdentifiers;
- (instancetype)bt_init;
@end

@implementation BTPluginOfficialTrustLoadResult
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginOfficialTrustLoader ()
@property (nonatomic, strong) id<BTPluginTrustMetadataStateStore> stateStore;
@end

@implementation BTPluginOfficialTrustLoader

- (instancetype)initWithStateStore:(id<BTPluginTrustMetadataStateStore>)stateStore {
	self = [super init];
	if (self)
		_stateStore = stateStore;
	return self;
}

+ (BTPluginTrustPolicy *)emptyTrustPolicy {
	NSError *error = nil;
	BTPluginTrustPolicy *policy = [[BTPluginTrustPolicy alloc]
		initWithOfficialPublicKeysByIdentifier:@{}
		officialScopesByKeyIdentifier:@{}
		revokedKeyIdentifiers:[NSSet set]
		metadataSequence:1
		metadataUpdatedAt:[NSDate dateWithTimeIntervalSince1970:0]
		error:&error];
	NSCAssert(policy != nil, @"The compiled empty plug-in trust policy must be valid: %@", error);
	return policy;
}

- (BTPluginOfficialTrustLoadResult *)emptyResult {
	BTPluginOfficialTrustLoadResult *result = [[BTPluginOfficialTrustLoadResult alloc] bt_init];
	result.trustPolicy = [BTPluginOfficialTrustLoader emptyTrustPolicy];
	result.signedMetadataLoaded = NO;
	result.metadataSHA256 = nil;
	result.verifiedRootKeyIdentifiers = [NSSet set];
	return result;
}

- (BTPluginOfficialTrustLoadResult *)loadFromApplicationBundleURL:(NSURL *)applicationBundleURL
															 error:(NSError **)error {
	if (![applicationBundleURL isKindOfClass:[NSURL class]] || !applicationBundleURL.isFileURL ||
		!self.stateStore) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
			@"The application bundle or trust-metadata state store is invalid.", @"PluginTrust", nil);
		return nil;
	}
	NSURL *trustURL = [applicationBundleURL URLByAppendingPathComponent:@"PluginTrust" isDirectory:YES];
	struct stat pathStat;
	if (lstat(trustURL.fileSystemRepresentation, &pathStat) != 0) {
		if (errno == ENOENT) {
			uint64_t previousSequence = 0;
			NSString *previousDigest = nil;
			if (![self.stateStore readPreviousSequence:&previousSequence
				metadataSHA256:&previousDigest error:error])
				return nil;
			if (previousSequence > 0) {
				BTPluginOfficialTrustFail(error, BTPluginPackageErrorRollback,
					@"The bundled official trust metadata is missing after a newer policy was recorded.",
					@"PluginTrust", nil);
				return nil;
			}
			return [self emptyResult];
		}
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidPackage,
			@"The official trust resource directory could not be inspected.", @"PluginTrust",
			BTPluginOfficialTrustPOSIXError(errno));
		return nil;
	}
	if (!BTPluginOfficialTrustDirectoryIsSafe(pathStat)) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnsafePath,
			@"The official trust resource must be a private, non-link directory.", @"PluginTrust", nil);
		return nil;
	}
	int rootDescriptor = open(trustURL.fileSystemRepresentation,
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	if (rootDescriptor < 0) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorRaceDetected,
			@"The official trust resource directory could not be opened safely.", @"PluginTrust",
			BTPluginOfficialTrustPOSIXError(errno));
		return nil;
	}
	struct stat rootBefore;
	if (fstat(rootDescriptor, &rootBefore) != 0 ||
		!BTPluginOfficialTrustDirectoryIsSafe(rootBefore) ||
		rootBefore.st_dev != pathStat.st_dev || rootBefore.st_ino != pathStat.st_ino) {
		close(rootDescriptor);
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorRaceDetected,
			@"The official trust resource directory changed before inspection.", @"PluginTrust", nil);
		return nil;
	}

	NSSet *rootEntries = BTPluginOfficialTrustDirectoryEntries(rootDescriptor,
		@"PluginTrust", 3, error);
	NSSet *expectedRootEntries = [NSSet setWithArray:@[
		@"RootPolicy.plist", @"TrustMetadata.json", @"TrustMetadata.signatures"
	]];
	if (!rootEntries || ![rootEntries isEqualToSet:expectedRootEntries]) {
		if (rootEntries)
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnexpectedFile,
				@"PluginTrust must contain exactly the root policy, metadata, and signature directory.",
				@"PluginTrust", nil);
		close(rootDescriptor);
		return nil;
	}

	NSData *rootPolicyData = BTPluginOfficialTrustReadFile(rootDescriptor,
		@"RootPolicy.plist", BTPluginRootPolicyMaximumByteCount, @"RootPolicy.plist", error);
	NSData *metadataData = rootPolicyData ? BTPluginOfficialTrustReadFile(rootDescriptor,
		@"TrustMetadata.json", BTPluginTrustMetadataMaximumByteCount, @"TrustMetadata.json", error) : nil;
	if (!rootPolicyData || !metadataData) {
		close(rootDescriptor);
		return nil;
	}

	int signatureDescriptor = openat(rootDescriptor, "TrustMetadata.signatures",
		O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
	struct stat signaturesBefore;
	if (signatureDescriptor < 0 || fstat(signatureDescriptor, &signaturesBefore) != 0 ||
		!BTPluginOfficialTrustDirectoryIsSafe(signaturesBefore)) {
		int status = errno;
		if (signatureDescriptor >= 0)
			close(signatureDescriptor);
		close(rootDescriptor);
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnsafePath,
			@"The official trust signature directory could not be opened safely.",
			@"TrustMetadata.signatures", status == 0 ? nil : BTPluginOfficialTrustPOSIXError(status));
		return nil;
	}
	NSSet<NSString *> *signatureEntries = BTPluginOfficialTrustDirectoryEntries(signatureDescriptor,
		@"TrustMetadata.signatures", BTPluginTrustSignatureMaximumCount, error);
	if (!signatureEntries || signatureEntries.count == 0) {
		if (signatureEntries)
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorInvalidSignature,
				@"The official trust metadata has no root signatures.", @"TrustMetadata.signatures", nil);
		close(signatureDescriptor);
		close(rootDescriptor);
		return nil;
	}
	NSMutableDictionary<NSString *, NSData *> *signatures = [NSMutableDictionary dictionary];
	NSArray<NSString *> *sortedSignatureEntries = [signatureEntries.allObjects
		sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *name in sortedSignatureEntries) {
		if (![[name pathExtension] isEqualToString:@"sig"] ||
			!BTPluginPackageLowercaseSHA256IsValid([name stringByDeletingPathExtension])) {
			BTPluginOfficialTrustFail(error, BTPluginPackageErrorUnexpectedFile,
				@"The official trust signature directory contains an invalid filename.",
				[@"TrustMetadata.signatures" stringByAppendingPathComponent:name], nil);
			close(signatureDescriptor);
			close(rootDescriptor);
			return nil;
		}
		NSString *relativePath = [@"TrustMetadata.signatures" stringByAppendingPathComponent:name];
		NSData *signature = BTPluginOfficialTrustReadFile(signatureDescriptor, name,
			BTPluginTrustSignatureMaximumByteCount, relativePath, error);
		if (!signature) {
			close(signatureDescriptor);
			close(rootDescriptor);
			return nil;
		}
		signatures[[name stringByDeletingPathExtension]] = signature;
	}
	struct stat signaturesAfter;
	BOOL signaturesUnchanged = fstat(signatureDescriptor, &signaturesAfter) == 0 &&
		BTPluginOfficialTrustStatIsUnchanged(&signaturesBefore, &signaturesAfter);
	close(signatureDescriptor);
	struct stat rootAfter;
	BOOL rootUnchanged = fstat(rootDescriptor, &rootAfter) == 0 &&
		BTPluginOfficialTrustStatIsUnchanged(&rootBefore, &rootAfter);
	close(rootDescriptor);
	if (!signaturesUnchanged || !rootUnchanged) {
		BTPluginOfficialTrustFail(error, BTPluginPackageErrorRaceDetected,
			@"The official trust resource tree changed during inspection.", @"PluginTrust", nil);
		return nil;
	}

	BTPluginRootTrustPolicy *rootPolicy = BTPluginOfficialTrustParseRootPolicy(rootPolicyData, error);
	if (!rootPolicy)
		return nil;
	uint64_t previousSequence = 0;
	NSString *previousDigest = nil;
	if (![self.stateStore readPreviousSequence:&previousSequence
		metadataSHA256:&previousDigest error:error])
		return nil;
	BTPluginVerifiedTrustMetadata *verified = [[[BTPluginTrustMetadataVerifier alloc]
		initWithRootPolicy:rootPolicy]
		verifyMetadataData:metadataData
		signaturesByRootKeyIdentifier:signatures
		previousSequence:previousSequence
		previousMetadataSHA256:previousDigest
		error:error];
	if (!verified)
		return nil;
	if (![self.stateStore recordSequence:verified.trustPolicy.metadataSequence
		metadataSHA256:verified.metadataSHA256 error:error])
		return nil;

	BTPluginOfficialTrustLoadResult *result = [[BTPluginOfficialTrustLoadResult alloc] bt_init];
	result.trustPolicy = verified.trustPolicy;
	result.signedMetadataLoaded = YES;
	result.metadataSHA256 = verified.metadataSHA256;
	result.verifiedRootKeyIdentifiers = verified.verifiedRootKeyIdentifiers;
	return result;
}

@end
