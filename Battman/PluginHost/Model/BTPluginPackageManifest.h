//
//  BTPluginPackageManifest.h
//  Battman
//
//  Strict model for Manifest.json schema version 1. Parsing is bounded and
//  rejects duplicate JSON keys before Foundation deserialization.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const BTPluginManifestMaximumByteCount;
FOUNDATION_EXPORT NSUInteger const BTPluginManifestMaximumJSONDepth;
FOUNDATION_EXPORT NSString * const BTPluginMachOCodeIdentityAlgorithm;

@interface BTPluginManifestPublisher : NSObject
@property (nonatomic, copy, readonly) NSString *primaryKeyIdentifier;
@property (nonatomic, copy, readonly) NSArray<NSString *> *signatureKeyIdentifiers;
@property (nonatomic, copy, readonly) NSString *algorithm;
- (instancetype)init NS_UNAVAILABLE;
@end

// Human-facing, publisher-asserted metadata. These values are covered by the
// Manifest.json signature, but are not themselves a cryptographic identity.
@interface BTPluginManifestAuthor : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *homepageURL;
@property (nonatomic, copy, readonly, nullable) NSString *supportEmail;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManifestCodeIdentity : NSObject
@property (nonatomic, copy, readonly) NSString *algorithm;
@property (nonatomic, readonly) uint64_t unsignedByteCount;
@property (nonatomic, copy, readonly) NSString *sha256;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManifestPayload : NSObject
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *kind;
@property (nonatomic, copy, readonly) NSString *executablePath;
@property (nonatomic, copy, readonly) NSString *architecture;
@property (nonatomic, copy, readonly) NSString *minimumIOSVersion;
@property (nonatomic, copy, readonly) NSString *entryPoint;
@property (nonatomic, strong, readonly, nullable) BTPluginManifestCodeIdentity *codeIdentity;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManifestExtensionPoint : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, readonly) uint32_t interfaceVersion;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef NS_ENUM(NSUInteger, BTPluginExtensionPointChangeKind) {
	BTPluginExtensionPointChangeKindAdded = 1,
	BTPluginExtensionPointChangeKindRemoved = 2,
	BTPluginExtensionPointChangeKindVersionChanged = 3,
};

typedef NS_ENUM(NSUInteger, BTPluginManifestUpdateLineageStatus) {
	BTPluginManifestUpdateLineageStatusNoPriorVersion = 1,
	BTPluginManifestUpdateLineageStatusAvailable = 2,
	BTPluginManifestUpdateLineageStatusDifferentPlugin = 3,
	BTPluginManifestUpdateLineageStatusPublisherChanged = 4,
	BTPluginManifestUpdateLineageStatusNotNewer = 5,
};

// A deterministic, non-executing comparison of two signed manifest models.
// A nil previous manifest means that no trustworthy same-ID baseline was
// available; callers must present that state as unavailable rather than
// treating every current extension point as a newly requested capability.
@interface BTPluginExtensionPointChange : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, readonly) BTPluginExtensionPointChangeKind kind;
@property (nonatomic, strong, readonly, nullable) NSNumber *previousInterfaceVersion;
@property (nonatomic, strong, readonly, nullable) NSNumber *currentInterfaceVersion;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManifestFile : NSObject
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, copy, readonly) NSString *mode;
@property (nonatomic, copy, readonly) NSString *sha256;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginManifestAuthorizationReference : NSObject
@property (nonatomic, copy, readonly) NSString *kind;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, readonly) uint64_t minimumSequence;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginPackageManifest : NSObject

@property (nonatomic, readonly) uint32_t formatVersion;
@property (nonatomic, readonly) uint32_t schemaVersion;
@property (nonatomic, copy, readonly) NSString *pluginIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *displayVersion;
@property (nonatomic, copy, readonly) NSString *buildVersion;
@property (nonatomic, strong, readonly) BTPluginManifestPublisher *publisher;
@property (nonatomic, strong, readonly, nullable) BTPluginManifestAuthor *author;
@property (nonatomic, readonly) uint32_t minimumHostABI;
@property (nonatomic, readonly) uint32_t maximumHostABI;
@property (nonatomic, strong, readonly) BTPluginManifestPayload *payload;
@property (nonatomic, copy, readonly) NSArray<BTPluginManifestExtensionPoint *> *extensionPoints;
@property (nonatomic, copy, readonly) NSArray<BTPluginManifestFile *> *files;
@property (nonatomic, copy, readonly) NSArray<NSString *> *dependencies;
@property (nonatomic, readonly) uint64_t releaseSequence;
@property (nonatomic, copy, readonly) NSArray<BTPluginManifestAuthorizationReference *> *authorizationReferences;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, BTPluginManifestFile *> *filesByPath;

- (instancetype)init NS_UNAVAILABLE;

+ (nullable instancetype)manifestWithData:(NSData *)data
								 error:(NSError * _Nullable * _Nullable)error;

@end

FOUNDATION_EXPORT BOOL BTPluginPackageRelativePathIsValid(NSString *path);
FOUNDATION_EXPORT BOOL BTPluginPackageLowercaseSHA256IsValid(NSString *value);

FOUNDATION_EXPORT NSArray<BTPluginExtensionPointChange *> *
BTPluginExtensionPointChangesFromManifests(BTPluginPackageManifest * _Nullable previousManifest,
	BTPluginPackageManifest *currentManifest);

// A prior manifest is comparable only when it is the same plug-in, uses the
// same primary publisher key, and has a lower monotonic release sequence. ABI
// v1 does not infer publisher-key rotation from an identifier match.
FOUNDATION_EXPORT BTPluginManifestUpdateLineageStatus
BTPluginManifestUpdateLineageStatusFromManifests(BTPluginPackageManifest * _Nullable previousManifest,
	BTPluginPackageManifest *currentManifest);

NS_ASSUME_NONNULL_END
