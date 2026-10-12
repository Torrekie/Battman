#import "BAAnalyticsHistoryService.h"
#import "BAAnalyticsHistoryReader.h"
#include <math.h>
#include <sys/stat.h>
#include <zlib.h>

static NSTimeInterval const BAHistoryRefreshInterval = 60.0;
// A reader interpretation change must not restore a report produced by the
// earlier session/configuration rules, even when its graph format is valid.
static NSUInteger const BAHistoryCacheInterpretationVersion = 3;
NSString *const BAAnalyticsHistoryServiceDidPublishNotification = @"BAAnalyticsHistoryServiceDidPublish";
// Registration also covers non-singleton host services. New instances created
// after a wipe begins remain suspended until the process exits.
static NSHashTable<BAAnalyticsHistoryService *> *BAHistoryServices;
static BOOL BAHistoryDataWipeRequested;

static NSURL *BAHistoryCacheDirectory(void) {
	if (!NSBundle.mainBundle.bundleIdentifier.length) return nil;
	NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
	return [support URLByAppendingPathComponent:@"AnalyticsHistory" isDirectory:YES];
}

static BOOL BAHistoryHasCompletedEvidence(BAAnalyticsReport *report) {
	if (!report || report.error) return NO;
	for (BAAnalyticsFamilyReport *family in report.familyReports.allValues)
		if (family.availability == BAAnalyticsReportAvailabilityReady || family.availability == BAAnalyticsReportAvailabilityPartial) return YES;
	return NO;
}

#if DEBUG
static unsigned long long BAHistoryCacheDiagnosticNumber(NSDictionary *values, NSString *key) {
	id value = values[key];
	return [value isKindOfClass:NSNumber.class] ? [value unsignedLongLongValue] : 0;
}
static void BAHistoryLogCacheWrite(NSUInteger stage, NSUInteger bytes, BOOL cancelled, NSError *error) {
	NSDictionary *info = error.userInfo;
	NSDictionary *counts = [info[@"counts"] isKindOfClass:NSDictionary.class] ? info[@"counts"] : @{};
	// Write stages: 1 source identity, 2 encode, 3 directory, 4 envelope,
	// 5 atomic write, 6 stored, 7 restore failure. Never print I/O descriptions or source paths.
	NSLog(@"[AnalyticsHistory] cache stage=%lu code=%ld cancelled=%d bytes=%lu encodeStage=%llu reason=%llu visits=%llu nodes=%llu metadata=%llu observations=%llu intervals=%llu gaps=%llu transitions=%llu sessions=%llu windows=%llu families=%llu ioCode=%ld",
		(unsigned long)stage, (long)error.code, cancelled, (unsigned long)bytes,
		BAHistoryCacheDiagnosticNumber(info, @"stage"), BAHistoryCacheDiagnosticNumber(info, @"reason"),
		BAHistoryCacheDiagnosticNumber(info, @"visits"), BAHistoryCacheDiagnosticNumber(info, @"nodes"),
		BAHistoryCacheDiagnosticNumber(counts, @"metadata"), BAHistoryCacheDiagnosticNumber(counts, @"observation"),
		BAHistoryCacheDiagnosticNumber(counts, @"interval"), BAHistoryCacheDiagnosticNumber(counts, @"gap"),
		BAHistoryCacheDiagnosticNumber(counts, @"transition"), BAHistoryCacheDiagnosticNumber(counts, @"session"),
		BAHistoryCacheDiagnosticNumber(counts, @"window"), BAHistoryCacheDiagnosticNumber(counts, @"family"),
		[info[@"ioCode"] isKindOfClass:NSNumber.class] ? [info[@"ioCode"] longValue] : 0L);
}
#endif

static NSString *BAArchiveToken(struct stat info) {
	NSString *input = [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%lld:%ld", (unsigned long long)info.st_dev,
		(unsigned long long)info.st_ino, (long long)info.st_birthtimespec.tv_sec, (long long)info.st_size,
		(long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
	uint64_t hash = UINT64_C(14695981039346656037);
	NSData *bytes = [input dataUsingEncoding:NSUTF8StringEncoding];
	for (NSUInteger i = 0; i < bytes.length; i++) { hash ^= ((const uint8_t *)bytes.bytes)[i]; hash *= UINT64_C(1099511628211); }
	return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

// Only the known Powerlog archive directory is inspected. Inflation is streamed
// into app-owned storage, never performed by a card or on the main thread.
static NSArray<NSURL *> *BAArchiveSources(NSURL *current, NSURL *cacheDirectory, BOOL (^cancelled)(void)) {
	if (!current.isFileURL || !cacheDirectory || cancelled()) return @[];
	NSFileManager *fm = NSFileManager.defaultManager;
	NSURL *archiveDirectory = [current.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Archives" isDirectory:YES];
	NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
	for (NSURL *url in [fm contentsOfDirectoryAtURL:archiveDirectory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL]) {
		if (cancelled()) return @[];
		NSString *name = url.lastPathComponent.uppercaseString;
		if (![name hasSuffix:@".PLSQL"] && ![name hasSuffix:@".PLSQL.GZ"]) continue;
		struct stat info;
		if (lstat(url.path.fileSystemRepresentation, &info) || !S_ISREG(info.st_mode) || info.st_size <= 0 ||
			info.st_size > ([name hasSuffix:@".GZ"] ? 64 : 192) * 1024 * 1024) continue;
		[candidates addObject:@{@"url": url, @"token": BAArchiveToken(info), @"modified": @(info.st_mtimespec.tv_sec)}];
		if (candidates.count >= 128) break;
	}
	[candidates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"modified"] compare:a[@"modified"]]; }];
	if (candidates.count > 8) [candidates removeObjectsInRange:NSMakeRange(8, candidates.count - 8)];
	NSURL *storage = [cacheDirectory URLByAppendingPathComponent:@"Archives" isDirectory:YES];
	if (![fm createDirectoryAtURL:storage withIntermediateDirectories:YES attributes:nil error:NULL]) return @[];
	[storage setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
	NSMutableSet *validNames = [NSMutableSet set];
	for (NSDictionary *candidate in candidates) [validNames addObject:[candidate[@"token"] stringByAppendingString:@".sqlite"]];
	for (NSURL *old in [fm contentsOfDirectoryAtURL:storage includingPropertiesForKeys:nil options:0 error:NULL])
		if (![validNames containsObject:old.lastPathComponent]) [fm removeItemAtURL:old error:NULL];
	NSMutableArray *sources = [NSMutableArray array];
	NSUInteger diskBytes = 0;
	NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 8;
	for (NSDictionary *candidate in candidates) @autoreleasepool {
		if (cancelled() || NSProcessInfo.processInfo.systemUptime > deadline) break;
		NSURL *original = candidate[@"url"], *url = original;
		if ([original.pathExtension caseInsensitiveCompare:@"gz"] == NSOrderedSame) {
			url = [storage URLByAppendingPathComponent:[candidate[@"token"] stringByAppendingString:@".sqlite"]];
			struct stat cached;
			if (stat(url.path.fileSystemRepresentation, &cached) || cached.st_size <= 0 || cached.st_size > 192 * 1024 * 1024) {
				NSURL *partial = [url URLByAppendingPathExtension:@"partial"];
				FILE *output = fopen(partial.path.fileSystemRepresentation, "wb");
				gzFile input = gzopen(original.path.fileSystemRepresentation, "rb");
				NSUInteger count = 0;
				BOOL complete = NO, ioGood = YES;
				if (input && output) {
					uint8_t buffer[65536];
					int read = 0;
					while (!cancelled() && NSProcessInfo.processInfo.systemUptime <= deadline && (read = gzread(input, buffer, sizeof buffer)) > 0) {
						count += (NSUInteger)read;
						if (count > 192 * 1024 * 1024 || count + diskBytes > 512 * 1024 * 1024 || fwrite(buffer, 1, (size_t)read, output) != (size_t)read) { ioGood = NO; break; }
					}
					int gzipError = Z_OK; (void)gzerror(input, &gzipError);
					complete = ioGood && read == 0 && (gzipError == Z_OK || gzipError == Z_STREAM_END) &&
						!cancelled() && NSProcessInfo.processInfo.systemUptime <= deadline && count > 0 &&
						count <= 192 * 1024 * 1024 && count + diskBytes <= 512 * 1024 * 1024 && gzeof(input);
				}
				if (input && gzclose(input) != Z_OK) complete = NO;
				if (output && fclose(output) != 0) complete = NO;
				if (complete) { [fm removeItemAtURL:url error:NULL]; complete = [fm moveItemAtURL:partial toURL:url error:NULL]; }
				if (!complete) { [fm removeItemAtURL:partial error:NULL]; continue; }
			}
		}
		struct stat info;
		if (stat(url.path.fileSystemRepresentation, &info) || info.st_size > 192 * 1024 * 1024 || info.st_size <= 0) continue;
		if (diskBytes + (NSUInteger)info.st_size > 512 * 1024 * 1024) { if (![url isEqual:original]) [fm removeItemAtURL:url error:NULL]; continue; }
		uint8_t header[16]; FILE *handle = fopen(url.path.fileSystemRepresentation, "rb");
		size_t headerLength = handle ? fread(header, 1, sizeof header, handle) : 0;
		if (handle) fclose(handle);
		if (headerLength != sizeof header || memcmp(header, "SQLite format 3\0", sizeof header)) { if (![url isEqual:original]) [fm removeItemAtURL:url error:NULL]; continue; }
		struct stat originalInfo;
		if (lstat(original.path.fileSystemRepresentation, &originalInfo) || ![BAArchiveToken(originalInfo) isEqual:candidate[@"token"]]) {
			if (![url isEqual:original]) [fm removeItemAtURL:url error:NULL]; continue;
		}
		diskBytes += (NSUInteger)info.st_size;
		NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
		components.fragment = [@"ba-powerlog-source:" stringByAppendingString:candidate[@"token"]];
		[sources addObject:components.URL];
	}
	// Remove unvisited/deadline-aborted cache files too, keeping total storage bounded.
	NSMutableSet *retained = [NSMutableSet set];
	for (NSURL *source in sources) if ([source.URLByDeletingLastPathComponent.path isEqual:storage.path]) [retained addObject:source.lastPathComponent];
	for (NSURL *old in [fm contentsOfDirectoryAtURL:storage includingPropertiesForKeys:nil options:0 error:NULL])
		if (![retained containsObject:old.lastPathComponent]) [fm removeItemAtURL:old error:NULL];
	return sources;
}

@interface BAHistoryReadCancellation : NSObject
@property (atomic) BOOL cancelled;
@end
@implementation BAHistoryReadCancellation
@end

@interface BAAnalyticsHistoryService ()
@property (nonatomic, copy, nullable) NSURL *databaseURL;
@property (nonatomic, strong) NSHashTable<id<BAAnalyticsHistoryServiceSubscriber>> *subscribers;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic, strong, nullable) dispatch_source_t timer;
@property (nonatomic, strong, nullable) BAHistoryReadCancellation *readCancellation;
@property (nonatomic, strong, readwrite, nullable) BAAnalyticsReport *latestReport;
@property (nonatomic, getter=isPolling) BOOL polling;
@property (nonatomic) BOOL applicationActive;
@property (nonatomic) BOOL acquisitionPending;
@property (nonatomic) BOOL memoryPressureDefersRetry;
@property (nonatomic) uint64_t nextSequenceNumber;
@property (nonatomic, copy, nullable) NSURL *cacheDirectoryURL;
@property (nonatomic) BOOL cacheRestorePending;
@property (nonatomic, strong, nullable) BAHistoryReadCancellation *cacheRestoreCancellation;
@property (nonatomic, strong, nullable) BAHistoryReadCancellation *cacheWriteCancellation;
@property (nonatomic) BOOL preparedForDataWipe;
@end

@implementation BAAnalyticsHistoryService
+ (instancetype)sharedService {
	static BAAnalyticsHistoryService *service;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ service = [[self alloc] initWithDatabaseURL:nil]; });
	return service;
}
- (instancetype)init { return [self initWithDatabaseURL:nil]; }
- (instancetype)initWithDatabaseURL:(NSURL *)databaseURL {
	return [self initWithDatabaseURL:databaseURL cacheDirectoryURL:databaseURL ? nil : BAHistoryCacheDirectory()];
}
- (instancetype)initWithDatabaseURL:(NSURL *)databaseURL cacheDirectoryURL:(NSURL *)cacheDirectoryURL {
	self = [super init];
	if (!self) return nil;
	_databaseURL = [databaseURL copy];
	_subscribers = [NSHashTable weakObjectsHashTable];
	_workerQueue = dispatch_queue_create("com.torrekie.battman.analytics.history",
		dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
	_applicationActive = YES;
	_nextSequenceNumber = 1;
	_cacheDirectoryURL = [cacheDirectoryURL copy];
	@synchronized(BAAnalyticsHistoryService.class) {
		if (!BAHistoryServices) BAHistoryServices = [NSHashTable weakObjectsHashTable];
		[BAHistoryServices addObject:self];
		_preparedForDataWipe = BAHistoryDataWipeRequested;
		// Registration and restore scheduling are one operation: a concurrent
		// wipe cannot take its worker snapshot before this restore is enqueued.
		if (_cacheDirectoryURL && !_preparedForDataWipe) [self restoreCompletedReport];
	}
	return self;
}
- (void)publishReport:(BAAnalyticsReport *)report {
	self.latestReport = report;
	for (id<BAAnalyticsHistoryServiceSubscriber> subscriber in self.subscribers.allObjects)
		[subscriber analyticsHistoryService:self didPublishReport:report];
	[NSNotificationCenter.defaultCenter postNotificationName:BAAnalyticsHistoryServiceDidPublishNotification object:self];
}
- (void)restoreCompletedReport {
	self.cacheRestorePending = YES;
	BAHistoryReadCancellation *cancellation = [BAHistoryReadCancellation new];
	self.cacheRestoreCancellation = cancellation;
	NSURL *file = [self.cacheDirectoryURL URLByAppendingPathComponent:@"completed.plist"];
	NSURL *requestedURL = self.databaseURL;
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.workerQueue, ^{
		@autoreleasepool {
			NSURL *source = requestedURL ?: BAAnalyticsResolveHistoryURL(^BOOL { return cancellation.cancelled; });
			NSString *identity = BAAnalyticsHistorySourceIdentity(source);
			NSNumber *size = nil;
			[file getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
			NSData *bytes = !cancellation.cancelled && size.unsignedLongLongValue <= 17 * 1024 * 1024 ? [NSData dataWithContentsOfURL:file options:0 error:NULL] : nil;
			id envelope = bytes ? [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable format:NULL error:NULL] : nil;
			BAAnalyticsReport *cached = nil;
			NSError *decodeError = nil;
			if ([envelope isKindOfClass:NSDictionary.class] && [envelope[@"version"] isEqual:@1] &&
				[envelope[@"interpretationVersion"] isEqual:@(BAHistoryCacheInterpretationVersion)] &&
				identity && [envelope[@"source"] isEqual:identity] && [envelope[@"report"] isKindOfClass:NSData.class])
				cached = BAAnalyticsDecodeCachedReportCancellable(envelope[@"report"], NSDate.date, &decodeError, ^BOOL { return cancellation.cancelled; });
#if DEBUG
			if (decodeError) BAHistoryLogCacheWrite(7, [decodeError.userInfo[@"bytes"] unsignedIntegerValue], cancellation.cancelled, decodeError);
#endif
			dispatch_async(dispatch_get_main_queue(), ^{
				BAAnalyticsHistoryService *service = weakSelf;
				if (!service) return;
				service.cacheRestorePending = NO;
				service.cacheRestoreCancellation = nil;
				if (!cancellation.cancelled && cached && !service.latestReport && !service.memoryPressureDefersRetry) {
					if (cached.sequenceNumber < UINT64_MAX - 2) service.nextSequenceNumber = MAX(service.nextSequenceNumber, cached.sequenceNumber + 1);
					[service publishReport:cached];
				}
				if (service.polling && !service.memoryPressureDefersRetry) [service refreshNow];
			});
		}
	});
}
- (void)storeCompletedReport:(BAAnalyticsReport *)report sourceURL:(NSURL *)sourceURL cancellation:(BAHistoryReadCancellation *)cancellation {
	if (cancellation.cancelled || !self.cacheDirectoryURL || !BAHistoryHasCompletedEvidence(report)) return;
	NSString *identity = BAAnalyticsHistorySourceIdentity(sourceURL);
	if (!identity) {
#if DEBUG
		BAHistoryLogCacheWrite(1, 0, cancellation.cancelled, nil);
#endif
		return;
	}
	NSError *error = nil;
	NSData *encoded = BAAnalyticsEncodeCachedReportCancellable(report, &error, ^BOOL { return cancellation.cancelled; });
	if (!encoded || cancellation.cancelled) {
#if DEBUG
		BAHistoryLogCacheWrite(2, [error.userInfo[@"bytes"] unsignedIntegerValue], cancellation.cancelled, error);
#endif
		return;
	}
	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm createDirectoryAtURL:self.cacheDirectoryURL withIntermediateDirectories:YES attributes:nil error:&error]) {
#if DEBUG
		BAHistoryLogCacheWrite(3, encoded.length, cancellation.cancelled, error);
#endif
		return;
	}
	[self.cacheDirectoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
	NSData *envelope = [NSPropertyListSerialization dataWithPropertyList:@{@"version": @1,
		@"interpretationVersion": @(BAHistoryCacheInterpretationVersion), @"source": identity, @"report": encoded}
		format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if (!envelope) {
#if DEBUG
		BAHistoryLogCacheWrite(4, encoded.length, cancellation.cancelled, error);
#endif
		return;
	}
	if (cancellation.cancelled) return;
	BOOL stored = [envelope writeToURL:[self.cacheDirectoryURL URLByAppendingPathComponent:@"completed.plist"] options:NSDataWritingAtomic error:&error];
#if DEBUG
	BAHistoryLogCacheWrite(stored ? 6 : 5, encoded.length, cancellation.cancelled, error);
#else
	(void)stored;
#endif
}
- (void)dealloc {
	_readCancellation.cancelled = YES;
	_cacheRestoreCancellation.cancelled = YES;
	_cacheWriteCancellation.cancelled = YES;
	if (_timer) dispatch_source_cancel(_timer);
}
- (NSUInteger)subscriberCount {
	NSAssert(NSThread.isMainThread, @"History subscriptions are main-thread only.");
	return self.subscribers.allObjects.count;
}
- (void)addSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber {
	NSParameterAssert(NSThread.isMainThread);
	if (!subscriber) return;
	[self.subscribers addObject:subscriber];
	[self updatePollingState];
	if (self.latestReport) [subscriber analyticsHistoryService:self didPublishReport:self.latestReport];
}
- (void)removeSubscriber:(id<BAAnalyticsHistoryServiceSubscriber>)subscriber {
	NSParameterAssert(NSThread.isMainThread);
	if (subscriber) [self.subscribers removeObject:subscriber];
	[self updatePollingState];
}
- (void)setApplicationActive:(BOOL)applicationActive {
	NSParameterAssert(NSThread.isMainThread);
	_applicationActive = applicationActive;
	if (applicationActive) self.memoryPressureDefersRetry = NO;
	[self updatePollingState];
}
- (NSTimeInterval)freshCacheRemainingInterval {
	if (!self.latestReport) return -1;
	NSTimeInterval age = [NSDate.date timeIntervalSinceDate:self.latestReport.generatedAt];
	// A clock rollback does not establish freshness. Explicit refreshNow below
	// always remains available even while the cached report is recent.
	return !self.latestReport.isCached && isfinite(age) && age >= 0 && age <= BAHistoryRefreshInterval ? BAHistoryRefreshInterval - age : -1;
}
- (void)updatePollingState {
	BOOL active = !self.preparedForDataWipe && self.applicationActive && self.subscribers.allObjects.count > 0;
	if (active == self.polling) return;
	self.polling = active;
	if (!active) {
		self.readCancellation.cancelled = YES;
		self.readCancellation = nil;
		if (self.timer) { dispatch_source_cancel(self.timer); self.timer = nil; }
		return;
	}
	// One cached immutable report, one pending read, bounded rows and four-second I/O budget.
	// A minute-scale timer matches persistent history; live five-second polling remains separate.
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	self.timer = timer;
	NSTimeInterval remaining = [self freshCacheRemainingInterval];
	NSTimeInterval firstDelay = remaining >= 0 ? remaining : BAHistoryRefreshInterval;
	dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(firstDelay * NSEC_PER_SEC)),
		(uint64_t)(BAHistoryRefreshInterval * NSEC_PER_SEC), (uint64_t)(MIN(5.0, firstDelay / 5) * NSEC_PER_SEC));
	__weak typeof(self) weakSelf = self;
	dispatch_source_set_event_handler(timer, ^{ [weakSelf refreshNow]; });
	dispatch_resume(timer);
	if (remaining < 0) [self refreshNow];
}
- (void)deliverReport:(BAAnalyticsReport *)report cancellation:(BAHistoryReadCancellation *)cancellation finished:(BOOL)finished {
	NSAssert(NSThread.isMainThread, @"History delivery is main-thread only.");
	if (finished) self.acquisitionPending = NO;
	[self updatePollingState];
	if (cancellation.cancelled || self.readCancellation != cancellation || !self.polling) {
		if (finished && self.polling && !self.memoryPressureDefersRetry && self.readCancellation == nil && [self freshCacheRemainingInterval] < 0) [self refreshNow];
		return;
	}
	if (finished) self.readCancellation = nil;
	// Keep the wider completed cache visible while archive enrichment is pending.
	if (!finished && BAHistoryHasCompletedEvidence(self.latestReport)) return;
	BAAnalyticsReport *display = report.error && BAHistoryHasCompletedEvidence(self.latestReport) ? [self.latestReport reportByMarkingCached] : report;
	if (display) [self publishReport:display];
}
- (void)refreshNow {
	NSParameterAssert(NSThread.isMainThread);
	self.memoryPressureDefersRetry = NO;
	[self updatePollingState]; // Drops the timer when the final weak subscriber has disappeared.
#if DEBUG
	NSLog(@"[AnalyticsHistory] refresh active=%d polling=%d subscribers=%lu pending=%d", self.applicationActive, self.polling, (unsigned long)self.subscriberCount, self.acquisitionPending);
#endif
	if (!self.polling || self.acquisitionPending || self.cacheRestorePending) return;
	self.acquisitionPending = YES;
	BAHistoryReadCancellation *cancellation = [BAHistoryReadCancellation new];
	self.readCancellation = cancellation;
	self.cacheWriteCancellation.cancelled = YES;
	self.cacheWriteCancellation = cancellation;
	uint64_t sequence = self.nextSequenceNumber;
	self.nextSequenceNumber += 2; // Current and enriched reports are separate generations.
	NSURL *url = self.databaseURL;
	NSURL *cacheDirectory = self.cacheDirectoryURL;
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.workerQueue, ^{
		@autoreleasepool {
#if DEBUG
			NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
			NSLog(@"[AnalyticsHistory] read begin sequence=%llu cancelled=%d", (unsigned long long)sequence, cancellation.cancelled);
#endif
			NSURL *sourceURL = url ?: BAAnalyticsResolveHistoryURL(^BOOL { return cancellation.cancelled; });
			BAAnalyticsReport *report = cancellation.cancelled ? nil : BAAnalyticsReadHistoryReport(sourceURL, NSDate.date, sequence, ^BOOL { return cancellation.cancelled; });
#if DEBUG
			NSLog(@"[AnalyticsHistory] read returned sequence=%llu elapsed=%.2f report=%d error=%ld", (unsigned long long)sequence, NSProcessInfo.processInfo.systemUptime - started, report != nil, (long)report.error.code);
#endif
			BOOL enrich = cacheDirectory && sourceURL && !cancellation.cancelled;
			if (enrich) {
				dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf deliverReport:report cancellation:cancellation finished:NO]; });
				NSArray *archives = BAArchiveSources(sourceURL, cacheDirectory, ^BOOL { return cancellation.cancelled; });
				if (archives.count && !cancellation.cancelled) {
					NSMutableArray *sources = [NSMutableArray arrayWithObject:sourceURL]; [sources addObjectsFromArray:archives];
					// Release the first graph before constructing the bounded enriched graph.
					report = nil;
					report = BAAnalyticsReadHistoryReportFromSources(sources, NSDate.date, sequence + 1, ^BOOL { return cancellation.cancelled; });
				}
			}
			BAAnalyticsReport *completed = report;
			dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf deliverReport:completed cancellation:cancellation finished:YES]; });
			if (!cancellation.cancelled) [weakSelf storeCompletedReport:completed sourceURL:sourceURL cancellation:cancellation];
		}
	});
}
- (void)handleMemoryPressure {
	NSParameterAssert(NSThread.isMainThread);
	self.latestReport = nil;
	self.memoryPressureDefersRetry = YES;
	self.cacheRestoreCancellation.cancelled = YES;
	self.cacheWriteCancellation.cancelled = YES;
	self.readCancellation.cancelled = YES;
	self.readCancellation = nil;
	// Keep the minute-scale timer, but do not immediately recreate a large
	// report in response to low memory. A later timer or activation can retry.
}

- (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion {
	NSParameterAssert(NSThread.isMainThread);
	self.preparedForDataWipe = YES;
	self.cacheRestoreCancellation.cancelled = YES;
	self.cacheWriteCancellation.cancelled = YES;
	self.readCancellation.cancelled = YES;
	self.latestReport = nil;
	[self updatePollingState];
	// A write already inside its atomic filesystem operation may finish. Drain
	// that operation before the caller removes any app-owned directory.
	dispatch_async(self.workerQueue, ^{
		dispatch_async(dispatch_get_main_queue(), completion);
	});
}

+ (void)prepareForDataWipeWithCompletion:(dispatch_block_t)completion {
	NSParameterAssert(NSThread.isMainThread);
	NSArray<BAAnalyticsHistoryService *> *services;
	@synchronized(BAAnalyticsHistoryService.class) {
		BAHistoryDataWipeRequested = YES;
		services = BAHistoryServices.allObjects;
	}
	dispatch_group_t pending = dispatch_group_create();
	for (BAAnalyticsHistoryService *service in services) {
		dispatch_group_enter(pending);
		[service prepareForDataWipeWithCompletion:^{ dispatch_group_leave(pending); }];
	}
	dispatch_group_notify(pending, dispatch_get_main_queue(), completion);
}
@end
