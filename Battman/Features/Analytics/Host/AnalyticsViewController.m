//
//  AnalyticsViewController.m
//  Battman — Analytics Host
//

#import "common.h"
#import "AnalyticsViewController.h"

#import "AnalyticsCardGridLayout.h"
#import "AnalyticsCardCell.h"
#import "BAAnalyticsCardLayoutStore.h"
#import "BAAnalyticsUnavailableCard.h"
#import "../Data/BAAnalyticsMetricService.h"
#import "../Data/BAAnalyticsSystemMetricSource.h"
#import "../../../PluginHost/Application/BTPluginPlatform.h"
#import "../../../PluginHost/BTPluginRegistry.h"
#import "ObjCExt/UIColor+compat.h"

UIImage *imageForSFProGlyph(NSString *glyph, NSString *fontName, CGFloat fontSize, UIColor *tintColor);

static NSString *const BAAnalyticsCardCellIdentifier = @"BAAnalyticsCardCell";

static NSTimeInterval BAAnalyticsMotionDuration(NSTimeInterval duration) {
	return UIAccessibilityIsReduceMotionEnabled() ? 0.0 : duration;
}

@interface BAAnalyticsCardState : NSObject
@property (nonatomic, strong) id<BAAnalyticsCard> card;
@property (nonatomic) BAAnalyticsCardSize size;
@property (nonatomic, copy) NSString *persistedDisplayName;
@property (nonatomic) NSUInteger persistedRestorationSchemaVersion;
@property (nonatomic, copy) NSDictionary *persistedRestorationState;
@end

@implementation BAAnalyticsCardState
@end

@interface AnalyticsViewController () <UICollectionViewDataSource, BAAnalyticsCardGridLayoutDelegate, UIGestureRecognizerDelegate, BAAnalyticsMetricServiceSubscriber>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) BAAnalyticsCardGridLayout *collectionLayout;
@property (nonatomic, strong) BTPluginRegistry *pluginRegistry;
@property (nonatomic, copy) NSArray<id<BAAnalyticsCard>> *availableCards;
@property (nonatomic, strong) NSMutableArray<BAAnalyticsCardState *> *cardStates;
@property (nonatomic, strong) BAAnalyticsMetricService *metricService;
@property (nonatomic, strong) NSHashTable<BAAnalyticsCardCell *> *visibleCardCells;
@property (nonatomic) BOOL metricSubscribed;
@property (nonatomic, strong) UIBarButtonItem *addCardButtonItem;
@property (nonatomic) BOOL movingCard;
@property (nonatomic) NSTimeInterval suppressResizeActionsUntil;
@property (nonatomic, strong) UIView *draggingSnapshotView;
@property (nonatomic, copy) NSString *draggingCardIdentifier;
@property (nonatomic) NSUInteger draggingOriginalIndex;
@property (nonatomic) CGPoint draggingSnapshotCenterOffset;
@property (nonatomic) BOOL reorderingDraggedCard;
@property (nonatomic) NSTimeInterval lastDragReorderTime;
@property (nonatomic) BOOL pendingDragFinish;
@property (nonatomic) BOOL pendingDragCancellation;
@end

@implementation AnalyticsViewController

- (NSString *)title {
	return _("Analytics");
}

- (instancetype)init {
	self = [super initWithNibName:nil bundle:nil];
	if (!self)
		return nil;

	UITabBarItem *tabbarItem = [UITabBarItem new];
	tabbarItem.title = _("Analytics");
	if (@available(iOS 13.0, *)) {
		tabbarItem.image = [UIImage systemImageNamed:@"chart.bar.xasis"]; // I would prefer chart.bar.xaxis but that was not something iOS 14
		if (tabbarItem.image == nil)
			tabbarItem.image = [UIImage systemImageNamed:@"chart.pie.fill"];
	}
	if (tabbarItem.image == nil) {
		// U+1008C9 chart.bar.xaxis
		tabbarItem.image = imageForSFProGlyph(@"􀣉", @SFPRO, 22, [UIColor grayColor]);
	}
	tabbarItem.tag = 0;
	self.tabBarItem = tabbarItem;

	self.pluginRegistry = BTPluginPlatform.sharedPlatform.registry;
	self.availableCards = (NSArray<id<BAAnalyticsCard>> *)[self.pluginRegistry
		extensionObjectsForExtensionPointIdentifier:BAAnalyticsCardExtensionPointIdentifier];
	self.cardStates = [self configuredCardStates];
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	if ([userDefaults objectForKey:BAAnalyticsCardLayoutDefaultsKey] == nil && [userDefaults objectForKey:BAAnalyticsLegacyCardLayoutDefaultsKey] != nil)
		[self saveCardLayout];
	self.metricService = [[BAAnalyticsMetricService alloc] initWithSource:[BAAnalyticsSystemMetricSource new]];
	self.visibleCardCells = [NSHashTable weakObjectsHashTable];
	[self.metricService setApplicationActive:[UIApplication sharedApplication].applicationState != UIApplicationStateBackground];

	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.navigationItem.title = [self title];
	self.addCardButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(showAddCardMenu:)];
	self.navigationItem.rightBarButtonItem = self.editButtonItem;
	[self updateEditingButtons];
	self.view.backgroundColor = [UIColor compatBackgroundColor];

	self.collectionLayout = [BAAnalyticsCardGridLayout new];
	self.collectionLayout.minimumInteritemSpacing = 12.0;
	self.collectionLayout.minimumLineSpacing = 12.0;
	self.collectionLayout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 28.0, 16.0);
	self.collectionLayout.minimumColumnWidth = 170.0;
	self.collectionLayout.maximumNumberOfColumns = 6;

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.collectionLayout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = [UIColor compatBackgroundColor];
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	[self.collectionView registerClass:[BAAnalyticsCardCell class] forCellWithReuseIdentifier:BAAnalyticsCardCellIdentifier];
	[self.view addSubview:self.collectionView];

	if (@available(iOS 11.0, *)) {
		self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
		[NSLayoutConstraint activateConstraints:@[
			[self.collectionView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
			[self.collectionView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
			[self.collectionView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
			[self.collectionView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
		]];
	} else {
		[NSLayoutConstraint activateConstraints:@[
			[self.collectionView.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
			[self.collectionView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor],
			[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
			[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		]];
	}

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleCardLongPress:)];
	longPress.minimumPressDuration = 0.35;
	longPress.cancelsTouchesInView = YES;
	longPress.delegate = self;
	[self.collectionView addGestureRecognizer:longPress];

	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	[notificationCenter addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
	[notificationCenter addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
	[notificationCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	[notificationCenter addObserver:self selector:@selector(applicationDidReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (self.metricSubscribed)
		[self.metricService removeSubscriber:self];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	for (BAAnalyticsCardCell *cell in self.collectionView.visibleCells) {
		[cell setAnalyticsCardDisplayed:YES];
		[self.visibleCardCells addObject:cell];
	}
	[self updateMetricSubscription];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	for (BAAnalyticsCardCell *cell in self.visibleCardCells.allObjects)
		[cell setAnalyticsCardDisplayed:NO];
	[self.visibleCardCells removeAllObjects];
	[self updateMetricSubscription];
}

- (void)applicationWillResignActive:(NSNotification *)notification {
	[self.metricService setApplicationActive:NO];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification {
	[self.metricService setApplicationActive:NO];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
	[self.metricService setApplicationActive:YES];
	[self.metricService refreshNow];
}

- (void)applicationDidReceiveMemoryWarning:(NSNotification *)notification {
	[self.metricService handleMemoryPressure];
	for (id<BAAnalyticsCard> card in self.availableCards) {
		if ([card respondsToSelector:@selector(analyticsCardDidReceiveMemoryWarning)])
			[card analyticsCardDidReceiveMemoryWarning];
	}
	if (!self.movingCard)
		[self.collectionView reloadData];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	if (self.movingCard)
		[self finishDraggingCardCancelled:YES];
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
		[self.collectionLayout invalidateLayout];
	} completion:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
	[super traitCollectionDidChange:previousTraitCollection];
	self.view.backgroundColor = [UIColor compatBackgroundColor];
	self.collectionView.backgroundColor = [UIColor compatBackgroundColor];
	[self.collectionLayout invalidateLayout];
	if (!self.movingCard)
		[self.collectionView reloadData];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	[super setEditing:editing animated:animated && !UIAccessibilityIsReduceMotionEnabled()];
	[self updateEditingButtons];
	if (!self.movingCard)
		[self.collectionView reloadData];
}

- (void)updateEditingButtons {
	self.navigationItem.leftBarButtonItem = self.editing ? self.addCardButtonItem : nil;
	self.addCardButtonItem.enabled = [self hiddenCards].count > 0;
}

#pragma mark - Card State

- (NSMutableArray<BAAnalyticsCardState *> *)configuredCardStates {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	BOOL hasSavedLayout = [userDefaults objectForKey:BAAnalyticsCardLayoutDefaultsKey] != nil || [userDefaults objectForKey:BAAnalyticsLegacyCardLayoutDefaultsKey] != nil;
	NSArray<BAAnalyticsCardLayoutRecord *> *savedLayout = [BAAnalyticsCardLayoutStore loadRecordsFromUserDefaults:userDefaults];

	NSMutableDictionary<NSString *, id<BAAnalyticsCard>> *cardsByIdentifier = [NSMutableDictionary dictionaryWithCapacity:self.availableCards.count];
	for (id<BAAnalyticsCard> card in self.availableCards) {
		if (card.analyticsCardIdentifier.length > 0)
			cardsByIdentifier[card.analyticsCardIdentifier] = card;
	}

	NSMutableArray<BAAnalyticsCardState *> *states = [NSMutableArray arrayWithCapacity:self.availableCards.count];
	NSMutableSet<NSString *> *usedIdentifiers = [NSMutableSet setWithCapacity:self.availableCards.count];

	for (BAAnalyticsCardLayoutRecord *record in savedLayout) {
		NSString *identifier = record.cardIdentifier;
		if ([usedIdentifiers containsObject:identifier])
			continue;

		id<BAAnalyticsCard> card = cardsByIdentifier[identifier];
		if (!card) {
			card = [[BAAnalyticsUnavailableCard alloc] initWithIdentifier:identifier
														 displayName:record.displayName
										 restorationSchemaVersion:record.restorationSchemaVersion
												 restorationState:record.restorationState];
		}

		BAAnalyticsCardState *state = [BAAnalyticsCardState new];
		state.card = card;
		state.size = [self validSizeFromSavedValue:@(record.sizeValue) forCard:card];
		state.persistedDisplayName = record.displayName;
		state.persistedRestorationSchemaVersion = record.restorationSchemaVersion;
		state.persistedRestorationState = record.restorationState;
		[self restorePersistedStateForCardState:state];
		[states addObject:state];
		[usedIdentifiers addObject:identifier];
	}

	if (hasSavedLayout)
		return states;

	for (id<BAAnalyticsCard> card in self.availableCards) {
		if ([usedIdentifiers containsObject:card.analyticsCardIdentifier])
			continue;
		BAAnalyticsCardState *state = [BAAnalyticsCardState new];
		state.card = card;
		state.size = BAAnalyticsCardSizeMaskContainsSize(card.supportedAnalyticsCardSizes, card.defaultAnalyticsCardSize) ? card.defaultAnalyticsCardSize : BAAnalyticsCardDefaultSizeForMask(card.supportedAnalyticsCardSizes);
		state.persistedDisplayName = [self displayNameForCard:card];
		state.persistedRestorationState = @{};
		[states addObject:state];
	}

	return states;
}

- (void)restorePersistedStateForCardState:(BAAnalyticsCardState *)state {
	NSDictionary *restorationState = state.persistedRestorationState;
	if (!restorationState || ![state.card respondsToSelector:@selector(analyticsCardRestoreState:)])
		return;
	@try {
		NSUInteger currentSchemaVersion = [state.card respondsToSelector:@selector(analyticsCardRestorationSchemaVersion)] ? [state.card analyticsCardRestorationSchemaVersion] : 0;
		if (currentSchemaVersion != state.persistedRestorationSchemaVersion) {
			if (![state.card respondsToSelector:@selector(analyticsCardMigrateRestorationState:fromSchemaVersion:)])
				return;
			restorationState = [state.card analyticsCardMigrateRestorationState:restorationState fromSchemaVersion:state.persistedRestorationSchemaVersion];
			if (![restorationState isKindOfClass:[NSDictionary class]])
				return;
			state.persistedRestorationSchemaVersion = currentSchemaVersion;
			state.persistedRestorationState = restorationState;
		}
		[state.card analyticsCardRestoreState:restorationState];
	} @catch (NSException *exception) {
		NSLog(@"Analytics card %@ rejected its restoration state: %@", state.card.analyticsCardIdentifier, exception.reason);
	}
}

- (NSString *)displayNameForCard:(id<BAAnalyticsCard>)card {
	if ([card respondsToSelector:@selector(analyticsCardDisplayName)] && card.analyticsCardDisplayName.length > 0)
		return card.analyticsCardDisplayName;
	return card.analyticsCardIdentifier;
}

- (BOOL)isCardIdentifierVisible:(NSString *)identifier {
	return [self indexOfCardIdentifier:identifier] != NSNotFound;
}

- (NSArray<id<BAAnalyticsCard>> *)hiddenCards {
	NSMutableArray<id<BAAnalyticsCard>> *hiddenCards = [NSMutableArray array];
	for (id<BAAnalyticsCard> card in self.availableCards) {
		if (![self isCardIdentifierVisible:card.analyticsCardIdentifier])
			[hiddenCards addObject:card];
	}
	return hiddenCards;
}

- (BAAnalyticsCardState *)stateForCard:(id<BAAnalyticsCard>)card {
	BAAnalyticsCardState *state = [BAAnalyticsCardState new];
	state.card = card;
	state.size = BAAnalyticsCardSizeMaskContainsSize(card.supportedAnalyticsCardSizes, card.defaultAnalyticsCardSize) ? card.defaultAnalyticsCardSize : BAAnalyticsCardDefaultSizeForMask(card.supportedAnalyticsCardSizes);
	state.persistedDisplayName = [self displayNameForCard:card];
	state.persistedRestorationState = @{};
	return state;
}

- (BAAnalyticsCardSize)validSizeFromSavedValue:(id)value forCard:(id<BAAnalyticsCard>)card {
	if (![value isKindOfClass:[NSNumber class]])
		return card.defaultAnalyticsCardSize;

	BAAnalyticsCardSize size = (BAAnalyticsCardSize)[value integerValue];
	if (!BAAnalyticsCardSizeMaskContainsSize(card.supportedAnalyticsCardSizes, size))
		return card.defaultAnalyticsCardSize;
	return size;
}

- (void)saveCardLayout {
	NSMutableArray<BAAnalyticsCardLayoutRecord *> *layout = [NSMutableArray arrayWithCapacity:self.cardStates.count];
	for (BAAnalyticsCardState *state in self.cardStates) {
		NSString *displayName = [self displayNameForCard:state.card] ?: state.persistedDisplayName;
		NSUInteger restorationSchemaVersion = state.persistedRestorationSchemaVersion;
		NSDictionary *restorationState = state.persistedRestorationState;
		@try {
			if ([state.card respondsToSelector:@selector(analyticsCardRestorationSchemaVersion)])
				restorationSchemaVersion = [state.card analyticsCardRestorationSchemaVersion];
			if ([state.card respondsToSelector:@selector(analyticsCardRestorationState)])
				restorationState = [state.card analyticsCardRestorationState];
		} @catch (NSException *exception) {
			NSLog(@"Analytics card %@ failed to provide restoration state: %@", state.card.analyticsCardIdentifier, exception.reason);
		}
		BAAnalyticsCardLayoutRecord *record = [[BAAnalyticsCardLayoutRecord alloc] initWithCardIdentifier:state.card.analyticsCardIdentifier
																	 displayName:displayName ?: state.card.analyticsCardIdentifier
																	   sizeValue:state.size
													 restorationSchemaVersion:restorationSchemaVersion
															 restorationState:restorationState];
		[layout addObject:record];
	}
	[BAAnalyticsCardLayoutStore saveRecords:layout toUserDefaults:[NSUserDefaults standardUserDefaults]];
}

#pragma mark - Collection View

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.cardStates.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	BAAnalyticsCardCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:BAAnalyticsCardCellIdentifier forIndexPath:indexPath];
	BAAnalyticsCardState *state = self.cardStates[indexPath.item];
	[cell configureWithCard:state.card size:state.size editing:self.editing];
	[cell.resizeButton addTarget:self action:@selector(resizeCardFromButton:) forControlEvents:UIControlEventTouchUpInside];
	[cell.removeButton addTarget:self action:@selector(removeCardFromButton:) forControlEvents:UIControlEventTouchUpInside];
	for (UIButton *button in cell.actionButtons)
		[button addTarget:self action:@selector(performCardActionFromButton:) forControlEvents:UIControlEventTouchUpInside];
	cell.hidden = self.draggingCardIdentifier && [state.card.analyticsCardIdentifier isEqualToString:self.draggingCardIdentifier];
	return cell;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (![cell isKindOfClass:[BAAnalyticsCardCell class]])
		return;
	BAAnalyticsCardCell *analyticsCell = (BAAnalyticsCardCell *)cell;
	[self.visibleCardCells addObject:analyticsCell];
	if (self.view.window != nil)
		[analyticsCell setAnalyticsCardDisplayed:YES];
	if (self.metricService.latestSnapshot)
		[analyticsCell applyMetricSnapshot:self.metricService.latestSnapshot];
	[self updateMetricSubscription];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (![cell isKindOfClass:[BAAnalyticsCardCell class]])
		return;
	BAAnalyticsCardCell *analyticsCell = (BAAnalyticsCardCell *)cell;
	[analyticsCell setAnalyticsCardDisplayed:NO];
	[self.visibleCardCells removeObject:analyticsCell];
	[self updateMetricSubscription];
}

- (void)updateMetricSubscription {
	BOOL shouldSubscribe = self.viewIfLoaded.window != nil && self.visibleCardCells.allObjects.count > 0;
	if (shouldSubscribe == self.metricSubscribed)
		return;
	self.metricSubscribed = shouldSubscribe;
	if (shouldSubscribe) {
		[self.metricService setApplicationActive:[UIApplication sharedApplication].applicationState != UIApplicationStateBackground];
		[self.metricService addSubscriber:self];
	} else {
		[self.metricService removeSubscriber:self];
	}
}

- (void)analyticsMetricService:(BAAnalyticsMetricService *)service didPublishSnapshot:(BAAnalyticsMetricSnapshot *)snapshot {
	NSAssert([NSThread isMainThread], @"Analytics snapshots are delivered on the main thread.");
	for (BAAnalyticsCardCell *cell in self.visibleCardCells.allObjects)
		[cell applyMetricSnapshot:snapshot];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.editing || self.movingCard || indexPath.item >= self.cardStates.count)
		return;

	BAAnalyticsCardState *state = self.cardStates[indexPath.item];
	[self openCardState:state];
}

- (BOOL)collectionView:(UICollectionView *)collectionView canMoveItemAtIndexPath:(NSIndexPath *)indexPath {
	return indexPath.item < self.cardStates.count;
}

- (void)collectionView:(UICollectionView *)collectionView moveItemAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
	if (self.reorderingDraggedCard)
		return;
	if (sourceIndexPath.item == destinationIndexPath.item || sourceIndexPath.item >= self.cardStates.count)
		return;

	BAAnalyticsCardState *state = self.cardStates[sourceIndexPath.item];
	[self.cardStates removeObjectAtIndex:sourceIndexPath.item];
	NSUInteger destinationIndex = MIN((NSUInteger)destinationIndexPath.item, self.cardStates.count);
	[self.cardStates insertObject:state atIndex:destinationIndex];
}

- (BAAnalyticsCardSize)collectionView:(UICollectionView *)collectionView cardGridLayout:(BAAnalyticsCardGridLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.item >= self.cardStates.count)
		return BAAnalyticsCardSize1x1;
	BAAnalyticsCardState *state = self.cardStates[indexPath.item];
	return state.size;
}

#pragma mark - Editing

- (void)showAddCardMenu:(id)sender {
	NSArray<id<BAAnalyticsCard>> *hiddenCards = [self hiddenCards];
	if (hiddenCards.count == 0) {
		[self updateEditingButtons];
		return;
	}

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_("Add Card") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for (id<BAAnalyticsCard> card in hiddenCards) {
		UIAlertAction *action = [UIAlertAction actionWithTitle:[self displayNameForCard:card] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[self addCard:card];
		}];
		[alert addAction:action];
	}
	[alert addAction:[UIAlertAction actionWithTitle:_("Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if ([alert respondsToSelector:@selector(popoverPresentationController)] && alert.popoverPresentationController)
		alert.popoverPresentationController.barButtonItem = self.addCardButtonItem;
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)addCard:(id<BAAnalyticsCard>)card {
	if (!card || [self isCardIdentifierVisible:card.analyticsCardIdentifier])
		return;

	BAAnalyticsCardState *state = [self stateForCard:card];
	NSUInteger index = self.cardStates.count;
	[self.cardStates addObject:state];
	[self saveCardLayout];
	[self updateEditingButtons];

	[self.collectionView performBatchUpdates:^{
		[self.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
	} completion:nil];
}

- (void)removeCardFromButton:(UIButton *)sender {
	if (self.movingCard)
		return;

	CGPoint center = CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds));
	CGPoint point = [sender convertPoint:center toView:self.collectionView];
	NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
	if (!indexPath || indexPath.item >= self.cardStates.count)
		return;

	[self.cardStates removeObjectAtIndex:indexPath.item];
	[self saveCardLayout];
	[self updateEditingButtons];

	[self.collectionView performBatchUpdates:^{
		[self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
	} completion:nil];
}

- (void)resizeCardFromButton:(UIButton *)sender {
	if (self.movingCard)
		return;
	if (CFAbsoluteTimeGetCurrent() < self.suppressResizeActionsUntil)
		return;

	CGPoint center = CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds));
	CGPoint point = [sender convertPoint:center toView:self.collectionView];
	NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
	if (!indexPath || indexPath.item >= self.cardStates.count)
		return;

	BAAnalyticsCardState *state = self.cardStates[indexPath.item];
	state.size = BAAnalyticsCardNextSize(state.size, state.card.supportedAnalyticsCardSizes);
	[self saveCardLayout];

	[self.collectionView performBatchUpdates:^{
		[self.collectionLayout invalidateLayout];
		[self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
	} completion:nil];
}

- (void)handleCardLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
	CGPoint location = [gestureRecognizer locationInView:self.collectionView];
	switch (gestureRecognizer.state) {
		case UIGestureRecognizerStateBegan: {
			NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:location];
			if (!indexPath || indexPath.item >= self.cardStates.count)
				return;
			UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
			if (!cell)
				return;

				self.suppressResizeActionsUntil = CFAbsoluteTimeGetCurrent() + 0.75;
				if (!self.editing)
					[super setEditing:YES animated:!UIAccessibilityIsReduceMotionEnabled()];
				[self updateEditingButtons];

				BAAnalyticsCardState *state = self.cardStates[indexPath.item];
				self.movingCard = YES;
				self.draggingCardIdentifier = state.card.analyticsCardIdentifier;
				self.draggingOriginalIndex = indexPath.item;
				self.lastDragReorderTime = 0.0;
				self.pendingDragFinish = NO;
				self.pendingDragCancellation = NO;
				self.draggingSnapshotView = [cell snapshotViewAfterScreenUpdates:NO];
			if (!self.draggingSnapshotView) {
				self.draggingCardIdentifier = nil;
				self.movingCard = NO;
				return;
			}
			self.draggingSnapshotView.frame = cell.frame;
			self.draggingSnapshotCenterOffset = CGPointMake(CGRectGetMidX(cell.frame) - location.x, CGRectGetMidY(cell.frame) - location.y);
			self.draggingSnapshotView.layer.zPosition = 1000.0;
			[self.collectionView addSubview:self.draggingSnapshotView];
			cell.hidden = YES;

				[UIView animateWithDuration:BAAnalyticsMotionDuration(0.12) animations:^{
					self.draggingSnapshotView.transform = CGAffineTransformMakeScale(1.03, 1.03);
					self.draggingSnapshotView.alpha = 0.96;
				}];
				break;
			}
			case UIGestureRecognizerStateChanged:
				if (self.movingCard) {
					self.draggingSnapshotView.center = CGPointMake(location.x + self.draggingSnapshotCenterOffset.x, location.y + self.draggingSnapshotCenterOffset.y);
					[self moveDraggedCardIfNeededForCenter:self.draggingSnapshotView.center];
				}
				break;
		case UIGestureRecognizerStateEnded:
			if (self.movingCard)
				[self finishDraggingCardCancelled:NO];
			break;
		default:
			if (self.movingCard)
				[self finishDraggingCardCancelled:YES];
			break;
	}
}

- (void)performCardActionFromButton:(UIButton *)sender {
	if (self.editing || self.movingCard)
		return;

	CGPoint center = CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds));
	CGPoint point = [sender convertPoint:center toView:self.collectionView];
	NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
	if (!indexPath || indexPath.item >= self.cardStates.count)
		return;

	BAAnalyticsCardState *state = self.cardStates[indexPath.item];
	if (![state.card respondsToSelector:@selector(analyticsCardActionsForSize:)])
		return;

	NSArray<id<BAAnalyticsCardAction>> *actions = [state.card analyticsCardActionsForSize:state.size];
	NSUInteger actionIndex = (NSUInteger)sender.tag;
	if (actionIndex >= actions.count)
		return;

	id<BAAnalyticsCardAction> action = actions[actionIndex];
	if ([state.card respondsToSelector:@selector(analyticsCardPerformAction:presentingViewController:)])
		[state.card analyticsCardPerformAction:action presentingViewController:self];
}

- (void)openCardState:(BAAnalyticsCardState *)state {
	if (![state.card respondsToSelector:@selector(analyticsCardViewControllerForSize:)])
		return;

	UIViewController *viewController = [state.card analyticsCardViewControllerForSize:state.size];
	if (!viewController)
		return;

	if (self.navigationController && ![viewController isKindOfClass:[UINavigationController class]])
		[self.navigationController pushViewController:viewController animated:YES];
	else
		[self presentViewController:viewController animated:YES completion:nil];
}

- (NSUInteger)indexOfCardIdentifier:(NSString *)identifier {
	if (!identifier)
		return NSNotFound;

	for (NSUInteger index = 0; index < self.cardStates.count; index++) {
		BAAnalyticsCardState *state = self.cardStates[index];
		if ([state.card.analyticsCardIdentifier isEqualToString:identifier])
			return index;
	}
	return NSNotFound;
}

- (NSUInteger)targetIndexForDragCenter:(CGPoint)center currentIndex:(NSUInteger)currentIndex {
	NSIndexPath *currentIndexPath = [NSIndexPath indexPathForItem:currentIndex inSection:0];
	UICollectionViewLayoutAttributes *currentAttributes = [self.collectionLayout layoutAttributesForItemAtIndexPath:currentIndexPath];
	if (!currentAttributes)
		return currentIndex;

	CGFloat deltaX = center.x - currentAttributes.center.x;
	CGFloat deltaY = center.y - currentAttributes.center.y;
	CGFloat verticalThreshold = MAX(34.0, CGRectGetHeight(currentAttributes.frame) * 0.32);
	CGFloat horizontalThreshold = MAX(34.0, CGRectGetWidth(currentAttributes.frame) * 0.32);

	if (fabs(deltaY) > verticalThreshold && fabs(deltaY) >= fabs(deltaX) * 0.85) {
		if (deltaY > 0.0)
			return MIN(currentIndex + 1, self.cardStates.count - 1);
		if (currentIndex > 0)
			return currentIndex - 1;
		return currentIndex;
	}

	if (fabs(deltaX) < horizontalThreshold)
		return currentIndex;

	NSIndexPath *preferredIndexPath = nil;
	CGFloat preferredScore = CGFLOAT_MAX;
	for (NSUInteger index = 0; index < self.cardStates.count; index++) {
		if (index == currentIndex)
			continue;

		NSIndexPath *indexPath = [NSIndexPath indexPathForItem:index inSection:0];
		UICollectionViewLayoutAttributes *attributes = [self.collectionLayout layoutAttributesForItemAtIndexPath:indexPath];
		if (!attributes)
			continue;

		CGRect frame = CGRectInset(attributes.frame, -self.collectionLayout.minimumInteritemSpacing / 2.0, -self.collectionLayout.minimumLineSpacing / 2.0);
		if (!CGRectContainsPoint(frame, center))
			continue;

		CGFloat normalizedX = fabs(attributes.center.x - center.x) / MAX(1.0, CGRectGetWidth(attributes.frame));
		CGFloat normalizedY = fabs(attributes.center.y - center.y) / MAX(1.0, CGRectGetHeight(attributes.frame));
		CGFloat score = normalizedX + normalizedY * 1.35;
		if (score < preferredScore) {
			preferredScore = score;
			preferredIndexPath = indexPath;
		}
	}

	return preferredIndexPath ? (NSUInteger)preferredIndexPath.item : currentIndex;
}

- (void)moveDraggedCardIfNeededForCenter:(CGPoint)center {
	if (self.reorderingDraggedCard)
		return;

	NSUInteger currentIndex = [self indexOfCardIdentifier:self.draggingCardIdentifier];
	if (currentIndex == NSNotFound)
		return;

	NSIndexPath *currentIndexPath = [NSIndexPath indexPathForItem:currentIndex inSection:0];
	BAAnalyticsCardState *state = self.cardStates[currentIndex];
	NSUInteger targetIndex = [self targetIndexForDragCenter:center currentIndex:currentIndex];
	if (targetIndex == currentIndex)
		return;

	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	if (self.lastDragReorderTime > 0.0 && now - self.lastDragReorderTime < 0.14)
		return;
	self.lastDragReorderTime = now;

	self.reorderingDraggedCard = YES;
	[self.collectionView performBatchUpdates:^{
		[self.cardStates removeObjectAtIndex:currentIndex];
		[self.cardStates insertObject:state atIndex:targetIndex];
		[self.collectionView moveItemAtIndexPath:currentIndexPath toIndexPath:[NSIndexPath indexPathForItem:targetIndex inSection:0]];
	} completion:^(BOOL finished) {
		self.reorderingDraggedCard = NO;
		if (self.pendingDragFinish) {
			BOOL cancelled = self.pendingDragCancellation;
			self.pendingDragFinish = NO;
			self.pendingDragCancellation = NO;
			[self finishDraggingCardCancelled:cancelled];
			return;
		}
		NSUInteger visibleIndex = [self indexOfCardIdentifier:self.draggingCardIdentifier];
		if (visibleIndex != NSNotFound) {
			UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:visibleIndex inSection:0]];
			cell.hidden = YES;
		}
	}];
}

- (void)finishDraggingCardCancelled:(BOOL)cancelled {
	if (self.reorderingDraggedCard) {
		self.pendingDragFinish = YES;
		self.pendingDragCancellation = self.pendingDragCancellation || cancelled;
		return;
	}
	self.suppressResizeActionsUntil = CFAbsoluteTimeGetCurrent() + 0.35;

	NSUInteger currentIndex = [self indexOfCardIdentifier:self.draggingCardIdentifier];
	if (cancelled && currentIndex != NSNotFound && self.draggingOriginalIndex != NSNotFound && currentIndex != self.draggingOriginalIndex) {
		BAAnalyticsCardState *state = self.cardStates[currentIndex];
		[self.cardStates removeObjectAtIndex:currentIndex];
		NSUInteger restoredIndex = MIN(self.draggingOriginalIndex, self.cardStates.count);
		[self.cardStates insertObject:state atIndex:restoredIndex];
		[self.collectionLayout invalidateLayout];
		[self.collectionView reloadData];
		[self.collectionView layoutIfNeeded];
		currentIndex = restoredIndex;
	}
	NSIndexPath *finalIndexPath = currentIndex == NSNotFound ? nil : [NSIndexPath indexPathForItem:currentIndex inSection:0];
	UICollectionViewCell *finalCell = finalIndexPath ? [self.collectionView cellForItemAtIndexPath:finalIndexPath] : nil;
	CGRect finalFrame = finalCell ? finalCell.frame : self.draggingSnapshotView.frame;

	[UIView animateWithDuration:BAAnalyticsMotionDuration(0.18) animations:^{
		self.draggingSnapshotView.transform = CGAffineTransformIdentity;
		self.draggingSnapshotView.alpha = 1.0;
		self.draggingSnapshotView.frame = finalFrame;
	} completion:^(BOOL finished) {
		finalCell.hidden = NO;
		[self.draggingSnapshotView removeFromSuperview];
		self.draggingSnapshotView = nil;
		self.draggingCardIdentifier = nil;
		self.draggingOriginalIndex = NSNotFound;
		self.movingCard = NO;
		self.reorderingDraggedCard = NO;
		[self saveCardLayout];
		[self.collectionView reloadData];
	}];
}

@end
