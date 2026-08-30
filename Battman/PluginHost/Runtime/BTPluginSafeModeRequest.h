//
//  BTPluginSafeModeRequest.h
//  Battman
//
//  Filesystem-backed recovery request. Any sentinel forces safe mode; only the
//  exact private marker created by this object is consumed after one launch.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BTPluginSafeModeLaunchArgument;
FOUNDATION_EXPORT NSString * const BTPluginSafeModeSentinelName;

@interface BTPluginSafeModeRequest : NSObject

@property (nonatomic, strong, readonly) NSURL *sentinelURL;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithSentinelURL:(NSURL *)sentinelURL NS_DESIGNATED_INITIALIZER;

- (BOOL)requestOneShotWithError:(NSError * _Nullable * _Nullable)error;

// Returns YES whenever any item exists at the sentinel path. The exact safe
// private marker is consumed; malformed, manually created, or unsafe items stay
// in place as persistent emergency recovery requests.
- (BOOL)consumeOneShotRequestIfPresent;

@end

NS_ASSUME_NONNULL_END
