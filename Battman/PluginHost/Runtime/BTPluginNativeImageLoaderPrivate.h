//
//  BTPluginNativeImageLoaderPrivate.h
//  Battman
//
//  PRIVATE HOST HEADER. Production callers must use BTPluginRuntimeLoader,
//  which pins the signed payload inventory before committing activation state
//  and performs the single native mapping step only from that private copy.
//
//  iOS 12 exposes only pathname-based dlopen; it has no public descriptor- or
//  memory-backed equivalent. A randomized 0700 capability directory therefore
//  removes the verified package directory from the load boundary, but it
//  cannot defend a process already running as Battman's effective UID or root.
//

#import <Foundation/Foundation.h>

@class BTPluginRegistry;
@class BTPluginVerifiedPackage;

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginPreparedNativeImage : NSObject

@property (nonatomic, strong, readonly) NSURL *stageRootURL;
@property (nonatomic, strong, readonly) NSURL *stagedExecutableURL;
@property (nonatomic, copy, readonly) NSString *contentSHA256;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface BTPluginNativeImageLoader : NSObject

// Copies only the signed inventory beneath the verified payload root. No
// package code is mapped, initialized, or called by this method.
- (nullable BTPluginPreparedNativeImage *)prepareImageForVerifiedPackage:
	(BTPluginVerifiedPackage *)verifiedPackage
													 error:(NSError * _Nullable * _Nullable)error;

// This is the only production dlopen/dlsym boundary. A successfully mapped
// image and its staged bytes/descriptors are intentionally retained for the
// process lifetime; there is no dlclose path.
- (BOOL)loadPreparedImage:(BTPluginPreparedNativeImage *)preparedImage
	expectedPluginIdentifier:(NSString *)pluginIdentifier
		 expectedPluginVersion:(NSString *)pluginVersion
		 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
						 registry:(BTPluginRegistry *)registry
							 error:(NSError * _Nullable * _Nullable)error;

// Fixture/ABI proof compatibility only. This pins one loose image by digest
// before delegating to loadPreparedImage:. Production package activation must
// never use this method.
- (BOOL)loadImageAtURL:(NSURL *)executableURL
	 expectedPluginIdentifier:(NSString *)pluginIdentifier
		  expectedPluginVersion:(NSString *)pluginVersion
	 declaredExtensionPoints:(NSSet<NSString *> *)declaredExtensionPoints
						 registry:(BTPluginRegistry *)registry
							 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
