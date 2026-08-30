//
//  BTPluginIdentifiers.m
//  Battman
//

#import "BTPluginIdentifiers.h"

BOOL BTPluginIdentifierIsValid(NSString *identifier) {
	if (![identifier isKindOfClass:[NSString class]] || identifier.length < 3 || identifier.length > 255)
		return NO;

	NSArray<NSString *> *components = [identifier componentsSeparatedByString:@"."];
	if (components.count < 2)
		return NO;

	for (NSString *component in components) {
		if (component.length == 0 || component.length > 63)
			return NO;

		for (NSUInteger index = 0; index < component.length; index++) {
			unichar character = [component characterAtIndex:index];
			BOOL alphanumeric = (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9');
			BOOL hyphen = character == '-';
			if (!alphanumeric && !hyphen)
				return NO;
			if (hyphen && (index == 0 || index + 1 == component.length))
				return NO;
		}
	}

	return YES;
}
