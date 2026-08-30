//
//  BTPluginPackageManifest.m
//  Battman
//

#import "BTPluginPackageManifest.h"

#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <mach-o/loader.h>

#import "BTPluginPackageErrors.h"
#import "BTPluginStrictJSON.h"
#import "../BTPluginIdentifiers.h"

NSUInteger const BTPluginManifestMaximumByteCount = 256 * 1024;
NSUInteger const BTPluginManifestMaximumJSONDepth = 16;
NSString * const BTPluginMachOCodeIdentityAlgorithm = @"macho-codesign-independent-sha256-v1";

static const NSUInteger BTPluginManifestMaximumJSONTokens = 8192;
static const NSUInteger BTPluginManifestMaximumRawJSONStringBytes = 16 * 1024;
static const uint64_t BTPluginManifestMaximumFileByteCount = 64ULL * 1024ULL * 1024ULL;
static const NSUInteger BTPluginManifestMaximumDisplayNameScalars = 256;
static const NSUInteger BTPluginManifestMaximumAuthorNameScalars = 128;

typedef struct {
	const uint8_t *bytes;
	NSUInteger length;
	NSUInteger index;
	NSUInteger tokenCount;
	NSError *__autoreleasing *error;
} BTPluginJSONScanner;

static BOOL BTPluginJSONFail(BTPluginJSONScanner *scanner, NSString *description) {
	if (scanner->error && !*scanner->error)
		*scanner->error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidJSON, description, nil, nil);
	return NO;
}

static void BTPluginJSONSkipWhitespace(BTPluginJSONScanner *scanner) {
	while (scanner->index < scanner->length) {
		uint8_t byte = scanner->bytes[scanner->index];
		if (byte != ' ' && byte != '\t' && byte != '\r' && byte != '\n')
			break;
		scanner->index++;
	}
}

static BOOL BTPluginJSONByteIsHex(uint8_t byte) {
	return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f') || (byte >= 'A' && byte <= 'F');
}

static NSString *BTPluginJSONDecodeStringToken(BTPluginJSONScanner *scanner,
																 NSUInteger start,
																 NSUInteger length) {
	NSMutableData *wrapped = [NSMutableData dataWithCapacity:length + 2];
	uint8_t opening = '[';
	uint8_t closing = ']';
	[wrapped appendBytes:&opening length:1];
	[wrapped appendBytes:scanner->bytes + start length:length];
	[wrapped appendBytes:&closing length:1];
	NSError *decodeError = nil;
	id object = [NSJSONSerialization JSONObjectWithData:wrapped options:0 error:&decodeError];
	if (![object isKindOfClass:[NSArray class]] || [object count] != 1 || ![[object firstObject] isKindOfClass:[NSString class]]) {
		BTPluginJSONFail(scanner, @"Manifest.json contains an invalid UTF-8 or escaped JSON string.");
		return nil;
	}
	return [object firstObject];
}

static BOOL BTPluginJSONParseString(BTPluginJSONScanner *scanner, NSString **decodedString) {
	if (scanner->index >= scanner->length || scanner->bytes[scanner->index] != '"')
		return BTPluginJSONFail(scanner, @"Manifest.json expected a JSON string.");
	NSUInteger start = scanner->index++;
	while (scanner->index < scanner->length) {
		uint8_t byte = scanner->bytes[scanner->index++];
		if (byte == '"') {
			NSUInteger tokenLength = scanner->index - start;
			if (tokenLength > BTPluginManifestMaximumRawJSONStringBytes)
				return BTPluginJSONFail(scanner, @"Manifest.json contains an oversized string token.");
			if (decodedString) {
				NSString *decoded = BTPluginJSONDecodeStringToken(scanner, start, tokenLength);
				if (!decoded)
					return NO;
				*decodedString = decoded;
			}
			return YES;
		}
		if (byte < 0x20)
			return BTPluginJSONFail(scanner, @"Manifest.json contains an unescaped control character.");
		if (byte != '\\')
			continue;
		if (scanner->index >= scanner->length)
			return BTPluginJSONFail(scanner, @"Manifest.json ends inside a string escape.");
		uint8_t escape = scanner->bytes[scanner->index++];
		if (escape == '"' || escape == '\\' || escape == '/' || escape == 'b' || escape == 'f' ||
			escape == 'n' || escape == 'r' || escape == 't')
			continue;
		if (escape != 'u')
			return BTPluginJSONFail(scanner, @"Manifest.json contains an invalid string escape.");
		if (scanner->length - scanner->index < 4)
			return BTPluginJSONFail(scanner, @"Manifest.json ends inside a Unicode escape.");
		for (NSUInteger offset = 0; offset < 4; offset++) {
			if (!BTPluginJSONByteIsHex(scanner->bytes[scanner->index + offset]))
				return BTPluginJSONFail(scanner, @"Manifest.json contains an invalid Unicode escape.");
		}
		scanner->index += 4;
	}
	return BTPluginJSONFail(scanner, @"Manifest.json contains an unterminated string.");
}

static BOOL BTPluginJSONParseValue(BTPluginJSONScanner *scanner, NSUInteger depth);

static BOOL BTPluginJSONParseObject(BTPluginJSONScanner *scanner, NSUInteger depth) {
	scanner->index++;
	BTPluginJSONSkipWhitespace(scanner);
	if (scanner->index < scanner->length && scanner->bytes[scanner->index] == '}') {
		scanner->index++;
		return YES;
	}

	NSMutableSet<NSString *> *keys = [NSMutableSet set];
	while (scanner->index < scanner->length) {
		NSString *key = nil;
		if (!BTPluginJSONParseString(scanner, &key))
			return NO;
		if ([keys containsObject:key])
			return BTPluginJSONFail(scanner, @"Manifest.json contains a duplicate object key.");
		[keys addObject:key];
		BTPluginJSONSkipWhitespace(scanner);
		if (scanner->index >= scanner->length || scanner->bytes[scanner->index++] != ':')
			return BTPluginJSONFail(scanner, @"Manifest.json expected ':' after an object key.");
		if (!BTPluginJSONParseValue(scanner, depth + 1))
			return NO;
		BTPluginJSONSkipWhitespace(scanner);
		if (scanner->index >= scanner->length)
			return BTPluginJSONFail(scanner, @"Manifest.json ends inside an object.");
		uint8_t delimiter = scanner->bytes[scanner->index++];
		if (delimiter == '}')
			return YES;
		if (delimiter != ',')
			return BTPluginJSONFail(scanner, @"Manifest.json expected ',' or '}' in an object.");
		BTPluginJSONSkipWhitespace(scanner);
	}
	return BTPluginJSONFail(scanner, @"Manifest.json ends inside an object.");
}

static BOOL BTPluginJSONParseArray(BTPluginJSONScanner *scanner, NSUInteger depth) {
	scanner->index++;
	BTPluginJSONSkipWhitespace(scanner);
	if (scanner->index < scanner->length && scanner->bytes[scanner->index] == ']') {
		scanner->index++;
		return YES;
	}
	while (scanner->index < scanner->length) {
		if (!BTPluginJSONParseValue(scanner, depth + 1))
			return NO;
		BTPluginJSONSkipWhitespace(scanner);
		if (scanner->index >= scanner->length)
			return BTPluginJSONFail(scanner, @"Manifest.json ends inside an array.");
		uint8_t delimiter = scanner->bytes[scanner->index++];
		if (delimiter == ']')
			return YES;
		if (delimiter != ',')
			return BTPluginJSONFail(scanner, @"Manifest.json expected ',' or ']' in an array.");
		BTPluginJSONSkipWhitespace(scanner);
	}
	return BTPluginJSONFail(scanner, @"Manifest.json ends inside an array.");
}

static BOOL BTPluginJSONParseNumber(BTPluginJSONScanner *scanner) {
	NSUInteger index = scanner->index;
	if (scanner->bytes[index] == '-') {
		index++;
		if (index >= scanner->length)
			return BTPluginJSONFail(scanner, @"Manifest.json contains an incomplete number.");
	}
	if (scanner->bytes[index] == '0') {
		index++;
		if (index < scanner->length && scanner->bytes[index] >= '0' && scanner->bytes[index] <= '9')
			return BTPluginJSONFail(scanner, @"Manifest.json contains a number with a leading zero.");
	} else if (scanner->bytes[index] >= '1' && scanner->bytes[index] <= '9') {
		do {
			index++;
		} while (index < scanner->length && scanner->bytes[index] >= '0' && scanner->bytes[index] <= '9');
	} else {
		return BTPluginJSONFail(scanner, @"Manifest.json contains an invalid number.");
	}
	if (index < scanner->length && scanner->bytes[index] == '.') {
		index++;
		NSUInteger fractionStart = index;
		while (index < scanner->length && scanner->bytes[index] >= '0' && scanner->bytes[index] <= '9')
			index++;
		if (index == fractionStart)
			return BTPluginJSONFail(scanner, @"Manifest.json contains an incomplete fraction.");
	}
	if (index < scanner->length && (scanner->bytes[index] == 'e' || scanner->bytes[index] == 'E')) {
		index++;
		if (index < scanner->length && (scanner->bytes[index] == '+' || scanner->bytes[index] == '-'))
			index++;
		NSUInteger exponentStart = index;
		while (index < scanner->length && scanner->bytes[index] >= '0' && scanner->bytes[index] <= '9')
			index++;
		if (index == exponentStart)
			return BTPluginJSONFail(scanner, @"Manifest.json contains an incomplete exponent.");
	}
	scanner->index = index;
	return YES;
}

static BOOL BTPluginJSONConsumeLiteral(BTPluginJSONScanner *scanner, const char *literal, NSUInteger length) {
	if (scanner->length - scanner->index < length || memcmp(scanner->bytes + scanner->index, literal, length) != 0)
		return BTPluginJSONFail(scanner, @"Manifest.json contains an invalid literal.");
	scanner->index += length;
	return YES;
}

static BOOL BTPluginJSONParseValue(BTPluginJSONScanner *scanner, NSUInteger depth) {
	if (depth > BTPluginManifestMaximumJSONDepth)
		return BTPluginJSONFail(scanner, @"Manifest.json exceeds the maximum nesting depth.");
	if (++scanner->tokenCount > BTPluginManifestMaximumJSONTokens)
		return BTPluginJSONFail(scanner, @"Manifest.json contains too many values.");
	BTPluginJSONSkipWhitespace(scanner);
	if (scanner->index >= scanner->length)
		return BTPluginJSONFail(scanner, @"Manifest.json ends before a value.");
	uint8_t byte = scanner->bytes[scanner->index];
	if (byte == '{')
		return BTPluginJSONParseObject(scanner, depth);
	if (byte == '[')
		return BTPluginJSONParseArray(scanner, depth);
	if (byte == '"')
		return BTPluginJSONParseString(scanner, NULL);
	if (byte == '-' || (byte >= '0' && byte <= '9'))
		return BTPluginJSONParseNumber(scanner);
	if (byte == 't')
		return BTPluginJSONConsumeLiteral(scanner, "true", 4);
	if (byte == 'f')
		return BTPluginJSONConsumeLiteral(scanner, "false", 5);
	if (byte == 'n')
		return BTPluginJSONConsumeLiteral(scanner, "null", 4);
	return BTPluginJSONFail(scanner, @"Manifest.json contains an unexpected token.");
}

static BOOL BTPluginJSONPreflight(NSData *data, NSUInteger maximumByteCount, NSError **error) {
	if (data.length == 0 || data.length > maximumByteCount) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorLimitExceeded,
				@"Manifest.json is empty or exceeds its byte limit.", @"Manifest.json", nil);
		return NO;
	}
	const uint8_t *bytes = data.bytes;
	if (data.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidJSON,
				@"Manifest.json must not contain a UTF-8 byte-order mark.", @"Manifest.json", nil);
		return NO;
	}
	BTPluginJSONScanner scanner = {
		.bytes = bytes,
		.length = data.length,
		.index = 0,
		.tokenCount = 0,
		.error = error,
	};
	if (!BTPluginJSONParseValue(&scanner, 1))
		return NO;
	BTPluginJSONSkipWhitespace(&scanner);
	if (scanner.index != scanner.length)
		return BTPluginJSONFail(&scanner, @"Manifest.json contains trailing data.");
	return YES;
}

id BTPluginStrictJSONObjectWithData(NSData *data,
										NSUInteger maximumByteCount,
										NSString *documentName,
										NSError **error) {
	NSError *strictError = nil;
	if (!BTPluginJSONPreflight(data, maximumByteCount, &strictError)) {
		if (error) {
			NSString *description = strictError.localizedDescription;
			if (documentName.length > 0 && ![documentName isEqualToString:@"Manifest.json"])
				description = [description stringByReplacingOccurrencesOfString:@"Manifest.json" withString:documentName];
			*error = BTPluginPackageMakeError((BTPluginPackageErrorCode)strictError.code,
				description, documentName, strictError.userInfo[NSUnderlyingErrorKey]);
		}
		return nil;
	}
	NSError *jsonError = nil;
	id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
	if (!object && error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidJSON,
			@"The signed JSON document is not valid UTF-8 JSON.", documentName, jsonError);
	return object;
}

static BOOL BTPluginAssignManifestError(NSError **error, NSString *description) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidManifest, description, @"Manifest.json", nil);
	return NO;
}

static BOOL BTPluginDictionaryHasExactKeys(NSDictionary *dictionary,
														 NSArray<NSString *> *required,
														 NSArray<NSString *> *optional,
														 NSString *context,
														 NSError **error) {
	NSMutableSet *allowed = [NSMutableSet setWithArray:required];
	[allowed addObjectsFromArray:optional];
	NSSet *actual = [NSSet setWithArray:dictionary.allKeys];
	for (NSString *key in required) {
		if (![actual containsObject:key])
			return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"%@ is missing required key '%@'.", context, key]);
	}
	NSMutableSet *unknown = [actual mutableCopy];
	[unknown minusSet:allowed];
	if (unknown.count > 0)
		return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"%@ contains unknown key '%@'.", context, [[unknown allObjects] firstObject]]);
	return YES;
}

static BOOL BTPluginJSONString(NSDictionary *dictionary,
								 NSString *key,
								 NSUInteger minimumLength,
								 NSUInteger maximumLength,
								 NSString **output,
								 NSError **error) {
	id value = dictionary[key];
	if (![value isKindOfClass:[NSString class]] || [value length] < minimumLength || [value length] > maximumLength)
		return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"Manifest key '%@' has an invalid string value.", key]);
	if (output)
		*output = value;
	return YES;
}

static BOOL BTPluginJSONUnsignedInteger(NSDictionary *dictionary,
											  NSString *key,
											  uint64_t minimum,
											  uint64_t maximum,
											  uint64_t *output,
											  NSError **error) {
	id value = dictionary[key];
	if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
		return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"Manifest key '%@' must be an integer.", key]);
	double number = [value doubleValue];
	if (!isfinite(number) || number < (double)minimum || number > (double)maximum || floor(number) != number)
		return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"Manifest key '%@' is outside its integer range.", key]);
	uint64_t integer = [value unsignedLongLongValue];
	if ((double)integer != number)
		return BTPluginAssignManifestError(error, [NSString stringWithFormat:@"Manifest key '%@' is not an exactly representable integer.", key]);
	if (output)
		*output = integer;
	return YES;
}

BOOL BTPluginPackageLowercaseSHA256IsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 64)
		return NO;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')))
			return NO;
	}
	return YES;
}

static BOOL BTPluginVersionStringIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0 || value.length > 64)
		return NO;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		BOOL valid = (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') ||
			(character >= '0' && character <= '9') || character == '.' || character == '_' || character == '+' || character == '-';
		if (!valid || (index == 0 && !((character >= 'A' && character <= 'Z') ||
			(character >= 'a' && character <= 'z') || (character >= '0' && character <= '9'))))
			return NO;
	}
	return YES;
}

static BOOL BTPluginEntryPointIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0 || value.length > 255)
		return NO;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		BOOL valid = (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') ||
			(character >= '0' && character <= '9') || character == '_';
		if (!valid || (index == 0 && character >= '0' && character <= '9'))
			return NO;
	}
	return YES;
}

static BOOL BTPluginStringGetUnicodeScalarCount(NSString *value, NSUInteger *scalarCount) {
	NSUInteger count = 0;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		if (character >= 0xd800 && character <= 0xdbff) {
			if (index + 1 >= value.length)
				return NO;
			unichar lowSurrogate = [value characterAtIndex:++index];
			if (lowSurrogate < 0xdc00 || lowSurrogate > 0xdfff)
				return NO;
		} else if (character >= 0xdc00 && character <= 0xdfff) {
			return NO;
		}
		count++;
	}
	if (scalarCount)
		*scalarCount = count;
	return YES;
}

static BOOL BTPluginDisplayStringIsValid(NSString *value, NSUInteger maximumScalarCount) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0)
		return NO;
	NSUInteger scalarCount = 0;
	if (!BTPluginStringGetUnicodeScalarCount(value, &scalarCount) || scalarCount > maximumScalarCount ||
		![value isEqualToString:value.precomposedStringWithCanonicalMapping])
		return NO;
	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	if ([value rangeOfCharacterFromSet:whitespace].location == 0 ||
		[value rangeOfCharacterFromSet:whitespace options:NSBackwardsSearch].location == value.length - 1 ||
		[value rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound ||
		[value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
		return NO;
	for (NSUInteger index = 0; index < value.length; index++) {
		unichar character = [value characterAtIndex:index];
		if (character == 0x061c || character == 0x200e || character == 0x200f ||
			(character >= 0x202a && character <= 0x202e) ||
			(character >= 0x2066 && character <= 0x2069))
			return NO;
	}
	return YES;
}

static BOOL BTPluginHomepageURLIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0 || value.length > 2048 ||
		[value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound ||
		[value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound ||
		[value containsString:@"\\"])
		return NO;
	NSURLComponents *components = [NSURLComponents componentsWithString:value];
	return [components.scheme isEqualToString:@"https"] && components.host.length > 0 &&
		components.user.length == 0 && components.password.length == 0 && components.URL != nil;
}

static BOOL BTPluginSupportEmailIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length < 3 || value.length > 254 ||
		![value canBeConvertedToEncoding:NSASCIIStringEncoding] ||
		[value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound ||
		[value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
		return NO;
	NSArray<NSString *> *parts = [value componentsSeparatedByString:@"@"];
	if (parts.count != 2)
		return NO;
	NSString *local = parts[0];
	NSString *domain = parts[1];
	if (local.length == 0 || local.length > 64 || domain.length == 0 || domain.length > 253 ||
		[local hasPrefix:@"."] || [local hasSuffix:@"."] || [local containsString:@".."])
		return NO;
	NSCharacterSet *localAllowed = [NSCharacterSet characterSetWithCharactersInString:
		@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.!#$%&'*+/=?^_`{|}~-"];
	if ([local rangeOfCharacterFromSet:localAllowed.invertedSet].location != NSNotFound)
		return NO;
	NSArray<NSString *> *labels = [domain componentsSeparatedByString:@"."];
	if (labels.count < 2)
		return NO;
	NSCharacterSet *domainAllowed = [NSCharacterSet characterSetWithCharactersInString:
		@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"];
	for (NSString *label in labels) {
		if (label.length == 0 || label.length > 63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"] ||
			[label rangeOfCharacterFromSet:domainAllowed.invertedSet].location != NSNotFound)
			return NO;
	}
	return YES;
}

BOOL BTPluginPackageRelativePathIsValid(NSString *path) {
	if (![path isKindOfClass:[NSString class]] || path.length == 0 || [path hasPrefix:@"/"] || [path hasSuffix:@"/"])
		return NO;
	NSData *utf8 = [path dataUsingEncoding:NSUTF8StringEncoding];
	if (!utf8 || utf8.length == 0 || utf8.length > 1024)
		return NO;
	if (![path isEqualToString:path.precomposedStringWithCanonicalMapping])
		return NO;
	if ([path rangeOfString:@"\\"].location != NSNotFound ||
		[path rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
		return NO;
	NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
	for (NSString *component in components) {
		if (component.length == 0 || [component isEqualToString:@"."] || [component isEqualToString:@".."])
			return NO;
	}
	return [path.stringByStandardizingPath isEqualToString:path];
}

static NSComparisonResult BTPluginCompareUTF8Strings(NSString *left, NSString *right) {
	NSData *leftData = [left dataUsingEncoding:NSUTF8StringEncoding];
	NSData *rightData = [right dataUsingEncoding:NSUTF8StringEncoding];
	NSUInteger common = MIN(leftData.length, rightData.length);
	int comparison = common == 0 ? 0 : memcmp(leftData.bytes, rightData.bytes, common);
	if (comparison < 0)
		return NSOrderedAscending;
	if (comparison > 0)
		return NSOrderedDescending;
	if (leftData.length < rightData.length)
		return NSOrderedAscending;
	if (leftData.length > rightData.length)
		return NSOrderedDescending;
	return NSOrderedSame;
}

@interface BTPluginManifestPublisher ()
@property (nonatomic, copy, readwrite) NSString *primaryKeyIdentifier;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *signatureKeyIdentifiers;
@property (nonatomic, copy, readwrite) NSString *algorithm;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestPublisher
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestAuthor ()
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite, nullable) NSString *homepageURL;
@property (nonatomic, copy, readwrite, nullable) NSString *supportEmail;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestAuthor
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestCodeIdentity ()
@property (nonatomic, copy, readwrite) NSString *algorithm;
@property (nonatomic, readwrite) uint64_t unsignedByteCount;
@property (nonatomic, copy, readwrite) NSString *sha256;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestCodeIdentity
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestPayload ()
@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, copy, readwrite) NSString *kind;
@property (nonatomic, copy, readwrite) NSString *executablePath;
@property (nonatomic, copy, readwrite) NSString *architecture;
@property (nonatomic, copy, readwrite) NSString *minimumIOSVersion;
@property (nonatomic, copy, readwrite) NSString *entryPoint;
@property (nonatomic, strong, readwrite, nullable) BTPluginManifestCodeIdentity *codeIdentity;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestPayload
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestExtensionPoint ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, readwrite) uint32_t interfaceVersion;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestExtensionPoint
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginExtensionPointChange ()
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, readwrite) BTPluginExtensionPointChangeKind kind;
@property (nonatomic, strong, readwrite, nullable) NSNumber *previousInterfaceVersion;
@property (nonatomic, strong, readwrite, nullable) NSNumber *currentInterfaceVersion;
- (instancetype)bt_init;
@end

@implementation BTPluginExtensionPointChange
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestFile ()
@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, readwrite) uint64_t size;
@property (nonatomic, copy, readwrite) NSString *mode;
@property (nonatomic, copy, readwrite) NSString *sha256;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestFile
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginManifestAuthorizationReference ()
@property (nonatomic, copy, readwrite) NSString *kind;
@property (nonatomic, copy, readwrite) NSString *identifier;
@property (nonatomic, readwrite) uint64_t minimumSequence;
- (instancetype)bt_init;
@end
@implementation BTPluginManifestAuthorizationReference
- (instancetype)bt_init { return [super init]; }
@end

@interface BTPluginPackageManifest ()
@property (nonatomic, readwrite) uint32_t formatVersion;
@property (nonatomic, readwrite) uint32_t schemaVersion;
@property (nonatomic, copy, readwrite) NSString *pluginIdentifier;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, copy, readwrite) NSString *displayVersion;
@property (nonatomic, copy, readwrite) NSString *buildVersion;
@property (nonatomic, strong, readwrite) BTPluginManifestPublisher *publisher;
@property (nonatomic, strong, readwrite, nullable) BTPluginManifestAuthor *author;
@property (nonatomic, readwrite) uint32_t minimumHostABI;
@property (nonatomic, readwrite) uint32_t maximumHostABI;
@property (nonatomic, strong, readwrite) BTPluginManifestPayload *payload;
@property (nonatomic, copy, readwrite) NSArray<BTPluginManifestExtensionPoint *> *extensionPoints;
@property (nonatomic, copy, readwrite) NSArray<BTPluginManifestFile *> *files;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *dependencies;
@property (nonatomic, readwrite) uint64_t releaseSequence;
@property (nonatomic, copy, readwrite) NSArray<BTPluginManifestAuthorizationReference *> *authorizationReferences;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, BTPluginManifestFile *> *filesByPath;
- (instancetype)bt_init;
@end

@implementation BTPluginPackageManifest

- (instancetype)bt_init { return [super init]; }

+ (instancetype)manifestWithData:(NSData *)data error:(NSError **)error {
	id root = BTPluginStrictJSONObjectWithData(data, BTPluginManifestMaximumByteCount, @"Manifest.json", error);
	if (!root)
		return nil;
	if (![root isKindOfClass:[NSDictionary class]]) {
		if (error)
			*error = BTPluginPackageMakeError(BTPluginPackageErrorInvalidJSON,
				@"Manifest.json must contain one top-level object.", @"Manifest.json", nil);
		return nil;
	}
	NSDictionary *dictionary = root;
	NSArray *required = @[
		@"formatVersion", @"schemaVersion", @"pluginIdentifier", @"displayName",
		@"displayVersion", @"buildVersion", @"publisher", @"hostABI", @"payload",
		@"extensionPoints", @"files", @"dependencies", @"releaseSequence"
	];
	if (!BTPluginDictionaryHasExactKeys(dictionary, required, @[ @"author", @"authorizationReferences" ], @"Manifest", error))
		return nil;

	uint64_t formatVersion = 0;
	uint64_t schemaVersion = 0;
	uint64_t releaseSequence = 0;
	if (!BTPluginJSONUnsignedInteger(dictionary, @"formatVersion", 1, 1, &formatVersion, error) ||
		!BTPluginJSONUnsignedInteger(dictionary, @"schemaVersion", 1, 1, &schemaVersion, error) ||
		!BTPluginJSONUnsignedInteger(dictionary, @"releaseSequence", 1, 9007199254740991ULL, &releaseSequence, error))
		return nil;

	NSString *pluginIdentifier = nil;
	NSString *displayName = nil;
	NSString *displayVersion = nil;
	NSString *buildVersion = nil;
	if (!BTPluginJSONString(dictionary, @"pluginIdentifier", 3, 255, &pluginIdentifier, error) ||
		!BTPluginJSONString(dictionary, @"displayName", 1,
			BTPluginManifestMaximumDisplayNameScalars * 2, &displayName, error) ||
		!BTPluginJSONString(dictionary, @"displayVersion", 1, 64, &displayVersion, error) ||
		!BTPluginJSONString(dictionary, @"buildVersion", 1, 64, &buildVersion, error))
		return nil;
	if (!BTPluginIdentifierIsValid(pluginIdentifier)) {
		BTPluginAssignManifestError(error, @"pluginIdentifier must be a lowercase reverse-DNS identifier.");
		return nil;
	}
	if (!BTPluginDisplayStringIsValid(displayName, BTPluginManifestMaximumDisplayNameScalars)) {
		BTPluginAssignManifestError(error, @"displayName must be a bounded canonical display string without control, line-separator, or bidirectional formatting characters.");
		return nil;
	}
	if (!BTPluginVersionStringIsValid(displayVersion) || !BTPluginVersionStringIsValid(buildVersion)) {
		BTPluginAssignManifestError(error, @"The display or build version has an invalid format.");
		return nil;
	}

	NSDictionary *publisherDictionary = dictionary[@"publisher"];
	if (![publisherDictionary isKindOfClass:[NSDictionary class]] ||
		!BTPluginDictionaryHasExactKeys(publisherDictionary,
			@[ @"primaryKeyIdentifier", @"signatureKeyIdentifiers", @"algorithm" ], @[], @"publisher", error))
		return nil;
	NSString *primaryKeyIdentifier = nil;
	NSString *algorithm = nil;
	if (!BTPluginJSONString(publisherDictionary, @"primaryKeyIdentifier", 64, 64, &primaryKeyIdentifier, error) ||
		!BTPluginJSONString(publisherDictionary, @"algorithm", 1, 64, &algorithm, error))
		return nil;
	if (!BTPluginPackageLowercaseSHA256IsValid(primaryKeyIdentifier) || ![algorithm isEqualToString:@"ecdsa-p256-sha256"]) {
		BTPluginAssignManifestError(error, @"The publisher key identifier or signature algorithm is invalid.");
		return nil;
	}
	NSArray *signatureKeyIdentifiers = publisherDictionary[@"signatureKeyIdentifiers"];
	if (![signatureKeyIdentifiers isKindOfClass:[NSArray class]] || signatureKeyIdentifiers.count == 0 || signatureKeyIdentifiers.count > 8) {
		BTPluginAssignManifestError(error, @"publisher.signatureKeyIdentifiers must contain between one and eight keys.");
		return nil;
	}
	NSMutableSet *signatureKeySet = [NSMutableSet set];
	for (id value in signatureKeyIdentifiers) {
		if (!BTPluginPackageLowercaseSHA256IsValid(value) || [signatureKeySet containsObject:value]) {
			BTPluginAssignManifestError(error, @"publisher.signatureKeyIdentifiers contains an invalid or duplicate key.");
			return nil;
		}
		[signatureKeySet addObject:value];
	}
	if (![signatureKeySet containsObject:primaryKeyIdentifier]) {
		BTPluginAssignManifestError(error, @"The primary publisher key must be present in signatureKeyIdentifiers.");
		return nil;
	}
	BTPluginManifestPublisher *publisher = [[BTPluginManifestPublisher alloc] bt_init];
	publisher.primaryKeyIdentifier = primaryKeyIdentifier;
	publisher.signatureKeyIdentifiers = [signatureKeyIdentifiers copy];
	publisher.algorithm = algorithm;

	BTPluginManifestAuthor *author = nil;
	id authorValue = dictionary[@"author"];
	if (authorValue) {
		if (![authorValue isKindOfClass:[NSDictionary class]] ||
			!BTPluginDictionaryHasExactKeys(authorValue, @[ @"name" ],
				@[ @"homepageURL", @"supportEmail" ], @"author", error))
			return nil;
		NSString *authorName = nil;
		NSString *homepageURL = nil;
		NSString *supportEmail = nil;
		if (!BTPluginJSONString(authorValue, @"name", 1,
			BTPluginManifestMaximumAuthorNameScalars * 2, &authorName, error) ||
			(authorValue[@"homepageURL"] && !BTPluginJSONString(authorValue, @"homepageURL", 1, 2048, &homepageURL, error)) ||
			(authorValue[@"supportEmail"] && !BTPluginJSONString(authorValue, @"supportEmail", 3, 254, &supportEmail, error)))
			return nil;
		if (!BTPluginDisplayStringIsValid(authorName, BTPluginManifestMaximumAuthorNameScalars) ||
			(homepageURL && !BTPluginHomepageURLIsValid(homepageURL)) ||
			(supportEmail && !BTPluginSupportEmailIsValid(supportEmail))) {
			BTPluginAssignManifestError(error, @"The author name, HTTPS homepage, or support email is invalid.");
			return nil;
		}
		author = [[BTPluginManifestAuthor alloc] bt_init];
		author.name = authorName;
		author.homepageURL = homepageURL;
		author.supportEmail = supportEmail;
	}

	NSDictionary *hostABI = dictionary[@"hostABI"];
	if (![hostABI isKindOfClass:[NSDictionary class]] ||
		!BTPluginDictionaryHasExactKeys(hostABI, @[ @"minimum", @"maximum" ], @[], @"hostABI", error))
		return nil;
	uint64_t minimumHostABI = 0;
	uint64_t maximumHostABI = 0;
	if (!BTPluginJSONUnsignedInteger(hostABI, @"minimum", 1, UINT32_MAX, &minimumHostABI, error) ||
		!BTPluginJSONUnsignedInteger(hostABI, @"maximum", 1, UINT32_MAX, &maximumHostABI, error))
		return nil;
	if (minimumHostABI > maximumHostABI) {
		BTPluginAssignManifestError(error, @"hostABI.minimum cannot exceed hostABI.maximum.");
		return nil;
	}

	NSDictionary *payloadDictionary = dictionary[@"payload"];
	NSArray *payloadKeys = @[ @"path", @"kind", @"executablePath", @"architecture", @"minimumIOSVersion", @"entryPoint" ];
	if (![payloadDictionary isKindOfClass:[NSDictionary class]] ||
		!BTPluginDictionaryHasExactKeys(payloadDictionary, payloadKeys, @[ @"codeIdentity" ], @"payload", error))
		return nil;
	NSString *payloadPath = nil;
	NSString *payloadKind = nil;
	NSString *executablePath = nil;
	NSString *architecture = nil;
	NSString *minimumIOSVersion = nil;
	NSString *entryPoint = nil;
	if (!BTPluginJSONString(payloadDictionary, @"path", 1, 1024, &payloadPath, error) ||
		!BTPluginJSONString(payloadDictionary, @"kind", 1, 16, &payloadKind, error) ||
		!BTPluginJSONString(payloadDictionary, @"executablePath", 1, 1024, &executablePath, error) ||
		!BTPluginJSONString(payloadDictionary, @"architecture", 1, 16, &architecture, error) ||
		!BTPluginJSONString(payloadDictionary, @"minimumIOSVersion", 1, 32, &minimumIOSVersion, error) ||
		!BTPluginJSONString(payloadDictionary, @"entryPoint", 1, 255, &entryPoint, error))
		return nil;
	if (!BTPluginPackageRelativePathIsValid(payloadPath) || !BTPluginPackageRelativePathIsValid(executablePath) ||
		[payloadPath containsString:@"/"]) {
		BTPluginAssignManifestError(error, @"The v1 payload and executable paths are not canonical package-relative paths.");
		return nil;
	}
	BOOL isBundle = [payloadKind isEqualToString:@"bundle"];
	BOOL isSO = [payloadKind isEqualToString:@"so"];
	if ((!isBundle && !isSO) || (isBundle && ![payloadPath hasSuffix:@".bundle"]) ||
		(isSO && ![payloadPath hasSuffix:@".so"]) ||
		(isBundle && ![executablePath hasPrefix:[payloadPath stringByAppendingString:@"/"]]) ||
		(isSO && ![executablePath isEqualToString:payloadPath]) || ![architecture isEqualToString:@"arm64"] ||
		![entryPoint isEqualToString:@"BattmanPluginEntryPointV1"] || !BTPluginEntryPointIsValid(entryPoint)) {
		BTPluginAssignManifestError(error, @"The payload kind, architecture, path, or entry point is invalid for ABI v1.");
		return nil;
	}
	NSArray<NSString *> *versionComponents = [minimumIOSVersion componentsSeparatedByString:@"."];
	if (versionComponents.count == 0 || versionComponents.count > 3) {
		BTPluginAssignManifestError(error, @"payload.minimumIOSVersion has an invalid format.");
		return nil;
	}
	for (NSString *component in versionComponents) {
		if (component.length == 0 || component.length > 3 ||
			[component rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
			BTPluginAssignManifestError(error, @"payload.minimumIOSVersion has an invalid format.");
			return nil;
		}
	}
	BTPluginManifestCodeIdentity *codeIdentity = nil;
	id codeIdentityValue = payloadDictionary[@"codeIdentity"];
	if (codeIdentityValue) {
		if (![codeIdentityValue isKindOfClass:[NSDictionary class]] ||
			!BTPluginDictionaryHasExactKeys(codeIdentityValue,
				@[ @"algorithm", @"unsignedByteCount", @"sha256" ], @[], @"payload.codeIdentity", error))
			return nil;
		NSString *codeIdentityAlgorithm = nil;
		NSString *codeIdentitySHA256 = nil;
		uint64_t unsignedByteCount = 0;
		if (!BTPluginJSONString(codeIdentityValue, @"algorithm", 1, 64, &codeIdentityAlgorithm, error) ||
			!BTPluginJSONString(codeIdentityValue, @"sha256", 64, 64, &codeIdentitySHA256, error) ||
			!BTPluginJSONUnsignedInteger(codeIdentityValue, @"unsignedByteCount",
				sizeof(struct mach_header_64), BTPluginManifestMaximumFileByteCount, &unsignedByteCount, error))
			return nil;
		if (![codeIdentityAlgorithm isEqualToString:BTPluginMachOCodeIdentityAlgorithm] ||
			!BTPluginPackageLowercaseSHA256IsValid(codeIdentitySHA256)) {
			BTPluginAssignManifestError(error, @"payload.codeIdentity has an unsupported algorithm or digest.");
			return nil;
		}
		codeIdentity = [[BTPluginManifestCodeIdentity alloc] bt_init];
		codeIdentity.algorithm = codeIdentityAlgorithm;
		codeIdentity.unsignedByteCount = unsignedByteCount;
		codeIdentity.sha256 = codeIdentitySHA256;
	}
	BTPluginManifestPayload *payload = [[BTPluginManifestPayload alloc] bt_init];
	payload.path = payloadPath;
	payload.kind = payloadKind;
	payload.executablePath = executablePath;
	payload.architecture = architecture;
	payload.minimumIOSVersion = minimumIOSVersion;
	payload.entryPoint = entryPoint;
	payload.codeIdentity = codeIdentity;

	NSArray *extensionDictionaries = dictionary[@"extensionPoints"];
	if (![extensionDictionaries isKindOfClass:[NSArray class]] || extensionDictionaries.count == 0 || extensionDictionaries.count > 32) {
		BTPluginAssignManifestError(error, @"extensionPoints must contain between one and 32 declarations.");
		return nil;
	}
	NSMutableArray *extensionPoints = [NSMutableArray arrayWithCapacity:extensionDictionaries.count];
	NSMutableSet *extensionIdentifiers = [NSMutableSet set];
	for (id value in extensionDictionaries) {
		if (![value isKindOfClass:[NSDictionary class]] ||
			!BTPluginDictionaryHasExactKeys(value, @[ @"identifier", @"interfaceVersion" ], @[], @"extension point", error))
			return nil;
		NSString *identifier = nil;
		uint64_t interfaceVersion = 0;
		if (!BTPluginJSONString(value, @"identifier", 3, 255, &identifier, error) ||
			!BTPluginJSONUnsignedInteger(value, @"interfaceVersion", 1, UINT32_MAX, &interfaceVersion, error))
			return nil;
		if (!BTPluginIdentifierIsValid(identifier) || [extensionIdentifiers containsObject:identifier]) {
			BTPluginAssignManifestError(error, @"An extension point identifier is invalid or duplicated.");
			return nil;
		}
		[extensionIdentifiers addObject:identifier];
		BTPluginManifestExtensionPoint *extensionPoint = [[BTPluginManifestExtensionPoint alloc] bt_init];
		extensionPoint.identifier = identifier;
		extensionPoint.interfaceVersion = (uint32_t)interfaceVersion;
		[extensionPoints addObject:extensionPoint];
	}

	NSArray *fileDictionaries = dictionary[@"files"];
	if (![fileDictionaries isKindOfClass:[NSArray class]] || fileDictionaries.count < 2 || fileDictionaries.count > 502) {
		BTPluginAssignManifestError(error, @"files must contain between two and 502 entries.");
		return nil;
	}
	NSMutableArray *files = [NSMutableArray arrayWithCapacity:fileDictionaries.count];
	NSMutableDictionary *filesByPath = [NSMutableDictionary dictionaryWithCapacity:fileDictionaries.count];
	NSMutableSet *foldedPaths = [NSMutableSet setWithCapacity:fileDictionaries.count];
	NSString *previousPath = nil;
	for (id value in fileDictionaries) {
		if (![value isKindOfClass:[NSDictionary class]] ||
			!BTPluginDictionaryHasExactKeys(value, @[ @"path", @"size", @"mode", @"sha256" ], @[], @"file", error))
			return nil;
		NSString *path = nil;
		NSString *mode = nil;
		NSString *sha256 = nil;
		uint64_t size = 0;
		if (!BTPluginJSONString(value, @"path", 1, 1024, &path, error) ||
			!BTPluginJSONString(value, @"mode", 1, 16, &mode, error) ||
			!BTPluginJSONString(value, @"sha256", 64, 64, &sha256, error) ||
			!BTPluginJSONUnsignedInteger(value, @"size", 0, BTPluginManifestMaximumFileByteCount, &size, error))
			return nil;
		NSString *foldedPath = [path lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
		if (!BTPluginPackageRelativePathIsValid(path) || [path isEqualToString:@"Manifest.json"] ||
			[path hasPrefix:@"Signatures/"] || filesByPath[path] || [foldedPaths containsObject:foldedPath] ||
			(previousPath && BTPluginCompareUTF8Strings(previousPath, path) != NSOrderedAscending)) {
			BTPluginAssignManifestError(error, @"The file inventory contains an unsafe, duplicate, case-colliding, or unsorted path.");
			return nil;
		}
		if ((![[NSSet setWithArray:@[ @"data", @"executable" ]] containsObject:mode]) ||
			([mode isEqualToString:@"executable"] && ![path isEqualToString:executablePath]) ||
			([path isEqualToString:executablePath] && ![mode isEqualToString:@"executable"]) ||
			!BTPluginPackageLowercaseSHA256IsValid(sha256)) {
			BTPluginAssignManifestError(error, @"A file inventory mode or SHA-256 value is invalid.");
			return nil;
		}
		BTPluginManifestFile *file = [[BTPluginManifestFile alloc] bt_init];
		file.path = path;
		file.size = size;
		file.mode = mode;
		file.sha256 = sha256;
		[files addObject:file];
		filesByPath[path] = file;
		[foldedPaths addObject:foldedPath];
		previousPath = path;
	}
	if (!filesByPath[@"Info.plist"] || !filesByPath[executablePath]) {
		BTPluginAssignManifestError(error, @"The file inventory must contain Info.plist and the declared payload executable.");
		return nil;
	}

	NSArray *dependencies = dictionary[@"dependencies"];
	if (![dependencies isKindOfClass:[NSArray class]] || dependencies.count > 32) {
		BTPluginAssignManifestError(error, @"dependencies must be an array of no more than 32 strings.");
		return nil;
	}
	NSMutableSet *dependencySet = [NSMutableSet set];
	for (id dependency in dependencies) {
		if (![dependency isKindOfClass:[NSString class]] || [dependency length] == 0 || [dependency length] > 512 ||
			[dependencySet containsObject:dependency]) {
			BTPluginAssignManifestError(error, @"dependencies contains an invalid or duplicate value.");
			return nil;
		}
		[dependencySet addObject:dependency];
	}

	NSArray *authorizationDictionaries = dictionary[@"authorizationReferences"] ?: @[];
	if (![authorizationDictionaries isKindOfClass:[NSArray class]] || authorizationDictionaries.count > 8) {
		BTPluginAssignManifestError(error, @"authorizationReferences must contain no more than eight entries.");
		return nil;
	}
	NSMutableArray *authorizationReferences = [NSMutableArray arrayWithCapacity:authorizationDictionaries.count];
	for (id value in authorizationDictionaries) {
		if (![value isKindOfClass:[NSDictionary class]] ||
			!BTPluginDictionaryHasExactKeys(value, @[ @"kind", @"identifier", @"minimumSequence" ], @[], @"authorization reference", error))
			return nil;
		NSString *kind = nil;
		NSString *identifier = nil;
		uint64_t minimumSequence = 0;
		if (!BTPluginJSONString(value, @"kind", 1, 32, &kind, error) ||
			!BTPluginJSONString(value, @"identifier", 3, 255, &identifier, error) ||
			!BTPluginJSONUnsignedInteger(value, @"minimumSequence", 1, 9007199254740991ULL, &minimumSequence, error))
			return nil;
		if (!([kind isEqualToString:@"key-rotation"] || [kind isEqualToString:@"catalog-delegation"]) ||
			!BTPluginIdentifierIsValid(identifier)) {
			BTPluginAssignManifestError(error, @"An authorization reference is invalid.");
			return nil;
		}
		BTPluginManifestAuthorizationReference *reference = [[BTPluginManifestAuthorizationReference alloc] bt_init];
		reference.kind = kind;
		reference.identifier = identifier;
		reference.minimumSequence = minimumSequence;
		[authorizationReferences addObject:reference];
	}

	BTPluginPackageManifest *manifest = [[BTPluginPackageManifest alloc] bt_init];
	manifest.formatVersion = (uint32_t)formatVersion;
	manifest.schemaVersion = (uint32_t)schemaVersion;
	manifest.pluginIdentifier = pluginIdentifier;
	manifest.displayName = displayName;
	manifest.displayVersion = displayVersion;
	manifest.buildVersion = buildVersion;
	manifest.publisher = publisher;
	manifest.author = author;
	manifest.minimumHostABI = (uint32_t)minimumHostABI;
	manifest.maximumHostABI = (uint32_t)maximumHostABI;
	manifest.payload = payload;
	manifest.extensionPoints = extensionPoints;
	manifest.files = files;
	manifest.dependencies = [dependencies copy];
	manifest.releaseSequence = releaseSequence;
	manifest.authorizationReferences = authorizationReferences;
	manifest.filesByPath = filesByPath;
	return manifest;
}

@end

NSArray<BTPluginExtensionPointChange *> *BTPluginExtensionPointChangesFromManifests(
	BTPluginPackageManifest *previousManifest, BTPluginPackageManifest *currentManifest) {
	if (BTPluginManifestUpdateLineageStatusFromManifests(previousManifest, currentManifest) !=
		BTPluginManifestUpdateLineageStatusAvailable)
		return @[];
	NSMutableDictionary<NSString *, NSNumber *> *previous = [NSMutableDictionary dictionary];
	for (BTPluginManifestExtensionPoint *extensionPoint in previousManifest.extensionPoints)
		previous[extensionPoint.identifier] = @(extensionPoint.interfaceVersion);
	NSMutableDictionary<NSString *, NSNumber *> *current = [NSMutableDictionary dictionary];
	for (BTPluginManifestExtensionPoint *extensionPoint in currentManifest.extensionPoints)
		current[extensionPoint.identifier] = @(extensionPoint.interfaceVersion);
	NSMutableSet<NSString *> *identifiers = [NSMutableSet setWithArray:previous.allKeys];
	[identifiers addObjectsFromArray:current.allKeys];
	NSArray<NSString *> *sortedIdentifiers = [identifiers.allObjects sortedArrayUsingComparator:
		^NSComparisonResult(NSString *left, NSString *right) {
		return [left compare:right options:NSLiteralSearch];
	}];
	NSMutableArray<BTPluginExtensionPointChange *> *changes = [NSMutableArray array];
	for (NSString *identifier in sortedIdentifiers) {
		NSNumber *previousVersion = previous[identifier];
		NSNumber *currentVersion = current[identifier];
		BTPluginExtensionPointChangeKind kind = 0;
		if (!previousVersion)
			kind = BTPluginExtensionPointChangeKindAdded;
		else if (!currentVersion)
			kind = BTPluginExtensionPointChangeKindRemoved;
		else if (previousVersion.unsignedIntValue != currentVersion.unsignedIntValue)
			kind = BTPluginExtensionPointChangeKindVersionChanged;
		if (kind == 0)
			continue;
		BTPluginExtensionPointChange *change = [[BTPluginExtensionPointChange alloc] bt_init];
		change.identifier = identifier;
		change.kind = kind;
		change.previousInterfaceVersion = previousVersion;
		change.currentInterfaceVersion = currentVersion;
		[changes addObject:change];
	}
	return changes;
}

BTPluginManifestUpdateLineageStatus BTPluginManifestUpdateLineageStatusFromManifests(
	BTPluginPackageManifest *previousManifest, BTPluginPackageManifest *currentManifest) {
	if (![currentManifest isKindOfClass:[BTPluginPackageManifest class]])
		return BTPluginManifestUpdateLineageStatusDifferentPlugin;
	if (![previousManifest isKindOfClass:[BTPluginPackageManifest class]])
		return BTPluginManifestUpdateLineageStatusNoPriorVersion;
	if (![previousManifest.pluginIdentifier isEqualToString:currentManifest.pluginIdentifier])
		return BTPluginManifestUpdateLineageStatusDifferentPlugin;
	if (![previousManifest.publisher.primaryKeyIdentifier
		isEqualToString:currentManifest.publisher.primaryKeyIdentifier])
		return BTPluginManifestUpdateLineageStatusPublisherChanged;
	if (currentManifest.releaseSequence <= previousManifest.releaseSequence)
		return BTPluginManifestUpdateLineageStatusNotNewer;
	return BTPluginManifestUpdateLineageStatusAvailable;
}
