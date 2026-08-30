//
//  BTPluginImportPresenter.h
//  Battman
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BTPluginImportPresenter : NSObject
+ (instancetype)sharedPresenter;
- (void)startObserving;
@end

NS_ASSUME_NONNULL_END
