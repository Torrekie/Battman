//
//  NSBundle+Auto.h
//  Battman
//
//  Created by Torrekie on 2025/12/2.
//

#import <Foundation/Foundation.h>

@interface NSBundle (Auto)
+ (instancetype)systemBundleWithName:(NSString *)name;
+ (instancetype)systemBundleWithName:(NSString *)name fallbackExecutable:(NSString *)executable;
@end
