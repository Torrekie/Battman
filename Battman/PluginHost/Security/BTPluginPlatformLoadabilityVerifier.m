//
//  BTPluginPlatformLoadabilityVerifier.m
//  Battman
//

#import "BTPluginPlatformLoadabilityVerifier.h"

#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

#if TARGET_OS_OSX
#import <Security/SecStaticCode.h>
#endif

#import "../Model/BTPluginPackageErrors.h"

static BOOL BTPluginPlatformFail(NSError **error, NSString *description, NSString *relativePath, NSError *underlyingError) {
	if (error)
		*error = BTPluginPackageMakeError(BTPluginPackageErrorPlatformSignature,
			description, relativePath, underlyingError);
	return NO;
}

static BOOL BTPluginStatIsIdentical(const struct stat *left, const struct stat *right) {
	return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
		left->st_size == right->st_size && left->st_mode == right->st_mode &&
		left->st_mtimespec.tv_sec == right->st_mtimespec.tv_sec &&
		left->st_mtimespec.tv_nsec == right->st_mtimespec.tv_nsec &&
		left->st_ctimespec.tv_sec == right->st_ctimespec.tv_sec &&
		left->st_ctimespec.tv_nsec == right->st_ctimespec.tv_nsec;
}

static NSString *BTPluginHexDigest(const uint8_t *bytes, NSUInteger length) {
	static const char digits[] = "0123456789abcdef";
	NSMutableData *output = [NSMutableData dataWithLength:length * 2];
	char *characters = output.mutableBytes;
	for (NSUInteger index = 0; index < length; index++) {
		characters[index * 2] = digits[bytes[index] >> 4];
		characters[index * 2 + 1] = digits[bytes[index] & 0x0f];
	}
	return [[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding];
}

static BOOL BTPluginHashOpenExecutable(int descriptor,
									   uint64_t expectedSize,
									   NSString *expectedSHA256,
									   NSString *relativePath,
									   NSError **error) {
	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	uint8_t buffer[64 * 1024];
	uint64_t offset = 0;
	while (offset < expectedSize) {
		NSUInteger wanted = (NSUInteger)MIN((uint64_t)sizeof(buffer), expectedSize - offset);
		ssize_t count = pread(descriptor, buffer, wanted, (off_t)offset);
		if (count <= 0 || (NSUInteger)count != wanted) {
			return BTPluginPlatformFail(error,
				@"The payload executable changed during platform-signature preflight.", relativePath, nil);
		}
		CC_SHA256_Update(&context, buffer, (CC_LONG)count);
		offset += (uint64_t)count;
	}
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &context);
	if (![BTPluginHexDigest(digest, sizeof(digest)) isEqualToString:expectedSHA256]) {
		return BTPluginPlatformFail(error,
			@"The platform-signature probe did not receive the structurally verified payload bytes.", relativePath, nil);
	}
	return YES;
}

@implementation BTPluginPlatformLoadabilityVerifier

- (BOOL)verifyPackageInspection:(BTPluginPackageInspection *)packageInspection
				 machOInspection:(BTPluginMachOInspection *)machOInspection
							  error:(NSError **)error {
	if (![packageInspection isKindOfClass:[BTPluginPackageInspection class]] ||
		![machOInspection isKindOfClass:[BTPluginMachOInspection class]] ||
		![packageInspection.executableURL isEqual:machOInspection.executableURL]) {
		return BTPluginPlatformFail(error, @"Platform preflight requires matching structural and Mach-O inspections.", nil, nil);
	}
	NSString *relativePath = packageInspection.manifest.payload.executablePath;
	BTPluginInspectedFile *expectedFile = packageInspection.filesByPath[relativePath];
	int descriptor = open(packageInspection.executableURL.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0)
		return BTPluginPlatformFail(error, @"The payload executable could not be opened for platform preflight.", relativePath, nil);
	struct stat before;
	if (fstat(descriptor, &before) != 0 || !S_ISREG(before.st_mode) || before.st_nlink != 1 || before.st_size < 0 ||
		(uint64_t)before.st_size != expectedFile.fileSize ||
		!BTPluginHashOpenExecutable(descriptor, expectedFile.fileSize, expectedFile.sha256, relativePath, error)) {
		if (error && !*error)
			BTPluginPlatformFail(error, @"The payload executable identity changed before platform preflight.", relativePath, nil);
		close(descriptor);
		return NO;
	}

	BOOL valid = YES;
#if TARGET_OS_OSX
	SecStaticCodeRef staticCode = NULL;
	OSStatus creationStatus = SecStaticCodeCreateWithPath((__bridge CFURLRef)packageInspection.executableURL,
		kSecCSDefaultFlags, &staticCode);
	if (creationStatus != errSecSuccess || !staticCode) {
		NSError *underlying = [NSError errorWithDomain:NSOSStatusErrorDomain code:creationStatus userInfo:nil];
		valid = BTPluginPlatformFail(error,
			@"The platform could not create a static-code view of the payload.", relativePath, underlying);
	} else {
		CFErrorRef validationError = NULL;
		SecCSFlags flags = kSecCSStrictValidate | kSecCSNoNetworkAccess | kSecCSDoNotValidateResources;
		OSStatus validationStatus = SecStaticCodeCheckValidityWithErrors(staticCode, flags, NULL, &validationError);
		if (validationStatus != errSecSuccess) {
			NSError *underlying = CFBridgingRelease(validationError);
			if (!underlying)
				underlying = [NSError errorWithDomain:NSOSStatusErrorDomain code:validationStatus userInfo:nil];
			valid = BTPluginPlatformFail(error,
				@"The platform rejected the payload's static code signature.", relativePath, underlying);
		} else if (validationError) {
			CFRelease(validationError);
		}
		CFRelease(staticCode);
	}
#else
	fsignatures_t signature = {0};
	signature.fs_file_start = (off_t)machOInspection.sliceFileOffset;
	signature.fs_blob_start = (void *)(uintptr_t)machOInspection.codeSignatureOffsetInSlice;
	signature.fs_blob_size = machOInspection.codeSignatureByteCount;
	if (fcntl(descriptor, F_ADDFILESIGS_RETURN, &signature) == -1) {
		int savedErrno = errno;
		NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil];
		valid = BTPluginPlatformFail(error,
			@"The iOS kernel rejected the embedded code signature before mapping.", relativePath, underlying);
	} else if ((uint64_t)signature.fs_file_start < machOInspection.codeSignatureOffsetInSlice) {
		valid = BTPluginPlatformFail(error,
			@"The iOS kernel reports that the signature does not cover every byte before LC_CODE_SIGNATURE.",
			relativePath, nil);
	} else {
		char message[512] = {0};
		fchecklv_t check = {
			.lv_file_start = (off_t)machOInspection.sliceFileOffset,
			.lv_error_message_size = sizeof(message),
			.lv_error_message = message,
		};
		if (fcntl(descriptor, F_CHECK_LV, &check) == -1) {
			int savedErrno = errno;
			NSString *kernelMessage = [[NSString alloc] initWithBytes:message
				length:strnlen(message, sizeof(message)) encoding:NSUTF8StringEncoding];
			NSString *description = kernelMessage.length > 0 ?
				[NSString stringWithFormat:@"The iOS library-validation policy rejected this payload: %@", kernelMessage] :
				@"The iOS library-validation policy rejected this payload.";
			NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil];
			valid = BTPluginPlatformFail(error, description, relativePath, underlying);
		}
	}
#endif

	struct stat after;
	BOOL unchanged = fstat(descriptor, &after) == 0 && BTPluginStatIsIdentical(&before, &after) &&
		BTPluginHashOpenExecutable(descriptor, expectedFile.fileSize, expectedFile.sha256, relativePath, valid ? error : NULL);
	close(descriptor);
	if (!unchanged && valid)
		return BTPluginPlatformFail(error, @"The payload executable changed during platform preflight.", relativePath, nil);
	return valid && unchanged;
}

@end
