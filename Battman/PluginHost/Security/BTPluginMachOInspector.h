//
//  BTPluginMachOInspector.h
//  Battman
//
//  Bounded, byte-only inspection of the single native payload. This API does
//  not map an image, create an NSBundle, resolve a symbol, or execute code.
//

#import <Foundation/Foundation.h>

#import "BTPluginPackageStructuralVerifier.h"

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginMachOInspection : NSObject
@property (nonatomic, strong, readonly) NSURL *executableURL;
@property (nonatomic, readonly) uint64_t sliceFileOffset;
@property (nonatomic, readonly) uint64_t sliceByteCount;
@property (nonatomic, readonly) uint32_t machOFileType;
@property (nonatomic, copy, readonly) NSString *minimumIOSVersion;
@property (nonatomic, copy, readonly) NSArray<NSString *> *linkedDependencies;
@property (nonatomic, copy, readonly) NSArray<NSString *> *nonSystemDependencies;
@property (nonatomic, copy, readonly) NSArray<NSString *> *runpaths;
@property (nonatomic, readonly) uint32_t codeSignatureOffsetInSlice;
@property (nonatomic, readonly) uint32_t codeSignatureByteCount;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface BTPluginMachOInspector : NSObject

- (instancetype)init;
- (instancetype)initWithHostApplicationBundleIdentifier:(nullable NSString *)hostApplicationBundleIdentifier
	NS_DESIGNATED_INITIALIZER;

- (nullable BTPluginMachOInspection *)inspectPackageInspection:(BTPluginPackageInspection *)inspection
									  hostIOSVersion:(NSOperatingSystemVersion)hostIOSVersion
											 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
