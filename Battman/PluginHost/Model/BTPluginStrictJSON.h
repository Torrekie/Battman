//
//  BTPluginStrictJSON.h
//  Battman
//
//  Bounded JSON preflight that rejects duplicate decoded object keys before
//  Foundation deserialization.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT id _Nullable BTPluginStrictJSONObjectWithData(NSData *data,
	NSUInteger maximumByteCount,
	NSString *documentName,
	NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
