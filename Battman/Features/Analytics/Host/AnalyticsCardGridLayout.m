//
//  AnalyticsCardGridLayout.m
//  Battman — Analytics Host
//

#import "AnalyticsCardGridLayout.h"

static NSMutableArray<NSNumber *> *BAAnalyticsGridEnsureRow(NSMutableArray<NSMutableArray<NSNumber *> *> *rows, NSUInteger rowIndex, NSUInteger columns) {
	while (rows.count <= rowIndex) {
		NSMutableArray<NSNumber *> *row = [NSMutableArray arrayWithCapacity:columns];
		for (NSUInteger column = 0; column < columns; column++)
			[row addObject:@NO];
		[rows addObject:row];
	}
	return rows[rowIndex];
}

static BOOL BAAnalyticsGridCanPlace(NSMutableArray<NSMutableArray<NSNumber *> *> *rows, NSUInteger row, NSUInteger column, NSUInteger widthSpan, NSUInteger heightSpan, NSUInteger columns) {
	if (column + widthSpan > columns)
		return NO;

	for (NSUInteger rowOffset = 0; rowOffset < heightSpan; rowOffset++) {
		NSUInteger currentRowIndex = row + rowOffset;
		if (currentRowIndex >= rows.count)
			continue;
		NSMutableArray<NSNumber *> *currentRow = rows[currentRowIndex];
		for (NSUInteger columnOffset = 0; columnOffset < widthSpan; columnOffset++) {
			if ([currentRow[column + columnOffset] boolValue])
				return NO;
		}
	}

	return YES;
}

static void BAAnalyticsGridMarkPlaced(NSMutableArray<NSMutableArray<NSNumber *> *> *rows, NSUInteger row, NSUInteger column, NSUInteger widthSpan, NSUInteger heightSpan, NSUInteger columns) {
	for (NSUInteger rowOffset = 0; rowOffset < heightSpan; rowOffset++) {
		NSMutableArray<NSNumber *> *currentRow = BAAnalyticsGridEnsureRow(rows, row + rowOffset, columns);
		for (NSUInteger columnOffset = 0; columnOffset < widthSpan; columnOffset++)
			currentRow[column + columnOffset] = @YES;
	}
}

@interface BAAnalyticsCardGridLayout ()
@property (nonatomic, strong) NSDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *itemAttributes;
@property (nonatomic, strong) NSArray<UICollectionViewLayoutAttributes *> *visibleAttributes;
@property (nonatomic) CGSize contentSize;
@end

@implementation BAAnalyticsCardGridLayout

- (instancetype)init {
	self = [super init];
	if (!self)
		return nil;

	_sectionInset = UIEdgeInsetsMake(16.0, 16.0, 28.0, 16.0);
	_minimumInteritemSpacing = 12.0;
	_minimumLineSpacing = 12.0;
	_minimumColumnWidth = 170.0;
	_maximumNumberOfColumns = 6;
	return self;
}

- (NSUInteger)numberOfColumnsForWidth:(CGFloat)viewWidth {
	UIEdgeInsets inset = self.sectionInset;
	CGFloat availableWidth = MAX(0.0, viewWidth - inset.left - inset.right);
	CGFloat spacing = self.minimumInteritemSpacing;
	CGFloat targetColumnWidth = MAX(1.0, self.minimumColumnWidth);
	NSUInteger columns = MAX(2u, (NSUInteger)floor((availableWidth + spacing) / (targetColumnWidth + spacing)));
	return MIN(columns, MAX(2u, self.maximumNumberOfColumns));
}

- (CGFloat)columnWidthForColumns:(NSUInteger)columns viewWidth:(CGFloat)viewWidth {
	UIEdgeInsets inset = self.sectionInset;
	CGFloat availableWidth = MAX(0.0, viewWidth - inset.left - inset.right);
	CGFloat spacing = self.minimumInteritemSpacing;
	if (columns <= 1)
		return MAX(1.0, floor(availableWidth));
	return MAX(1.0, floor((availableWidth - spacing * (columns - 1)) / columns));
}

- (void)prepareLayout {
	[super prepareLayout];

	UICollectionView *collectionView = self.collectionView;
	if (!collectionView) {
		self.itemAttributes = @{};
		self.visibleAttributes = @[];
		self.contentSize = CGSizeZero;
		return;
	}

	NSUInteger columns = [self numberOfColumnsForWidth:CGRectGetWidth(collectionView.bounds)];
	CGFloat columnWidth = [self columnWidthForColumns:columns viewWidth:CGRectGetWidth(collectionView.bounds)];
	CGFloat columnStride = columnWidth + self.minimumInteritemSpacing;
	CGFloat rowStride = columnWidth + self.minimumLineSpacing;
	NSMutableArray<NSMutableArray<NSNumber *> *> *occupiedRows = [NSMutableArray array];
	NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *attributesByIndexPath = [NSMutableDictionary dictionary];
	NSMutableArray<UICollectionViewLayoutAttributes *> *attributes = [NSMutableArray array];
	CGFloat contentBottom = self.sectionInset.top;
	id<BAAnalyticsCardGridLayoutDelegate> delegate = (id<BAAnalyticsCardGridLayoutDelegate>)collectionView.delegate;
	BOOL rightToLeft = collectionView.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

	NSInteger sectionCount = collectionView.numberOfSections;
	for (NSInteger section = 0; section < sectionCount; section++) {
		NSInteger itemCount = [collectionView numberOfItemsInSection:section];
		for (NSInteger item = 0; item < itemCount; item++) {
			NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
			BAAnalyticsCardSize cardSize = BAAnalyticsCardSize1x1;
			if ([delegate respondsToSelector:@selector(collectionView:cardGridLayout:sizeForItemAtIndexPath:)])
				cardSize = [delegate collectionView:collectionView cardGridLayout:self sizeForItemAtIndexPath:indexPath];

			CGSize span = BAAnalyticsCardGridSpan(cardSize);
			NSUInteger widthSpan = MIN(MAX((NSUInteger)span.width, 1u), columns);
			NSUInteger heightSpan = MAX((NSUInteger)span.height, 1u);
			NSUInteger placedRow = 0;
			NSUInteger placedColumn = 0;
			BOOL placed = NO;

			for (NSUInteger row = 0; !placed; row++) {
				for (NSUInteger column = 0; column + widthSpan <= columns; column++) {
					if (!BAAnalyticsGridCanPlace(occupiedRows, row, column, widthSpan, heightSpan, columns))
						continue;
					placedRow = row;
					placedColumn = column;
					placed = YES;
					break;
				}
			}

			BAAnalyticsGridMarkPlaced(occupiedRows, placedRow, placedColumn, widthSpan, heightSpan, columns);

			CGFloat width = columnWidth * widthSpan + self.minimumInteritemSpacing * (widthSpan - 1);
			CGFloat height = columnWidth * heightSpan + self.minimumLineSpacing * (heightSpan - 1);
			CGFloat x = rightToLeft
				? CGRectGetWidth(collectionView.bounds) - self.sectionInset.right - width - placedColumn * columnStride
				: self.sectionInset.left + placedColumn * columnStride;
			CGFloat y = self.sectionInset.top + placedRow * rowStride;
			UICollectionViewLayoutAttributes *itemAttributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
			itemAttributes.frame = CGRectIntegral(CGRectMake(x, y, width, height));
			attributesByIndexPath[indexPath] = itemAttributes;
			[attributes addObject:itemAttributes];
			contentBottom = MAX(contentBottom, CGRectGetMaxY(itemAttributes.frame));
		}
	}

	self.itemAttributes = attributesByIndexPath;
	self.visibleAttributes = attributes;
	self.contentSize = CGSizeMake(CGRectGetWidth(collectionView.bounds), contentBottom + self.sectionInset.bottom);
}

- (CGSize)collectionViewContentSize {
	return self.contentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
	NSMutableArray<UICollectionViewLayoutAttributes *> *visibleAttributes = [NSMutableArray array];
	for (UICollectionViewLayoutAttributes *attributes in self.visibleAttributes) {
		if (CGRectIntersectsRect(attributes.frame, rect))
			[visibleAttributes addObject:attributes];
	}
	return visibleAttributes;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
	return self.itemAttributes[indexPath];
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
	return fabs(CGRectGetWidth(newBounds) - CGRectGetWidth(self.collectionView.bounds)) > DBL_EPSILON || fabs(CGRectGetHeight(newBounds) - CGRectGetHeight(self.collectionView.bounds)) > DBL_EPSILON;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForInteractivelyMovingItemAtIndexPath:(NSIndexPath *)indexPath withTargetPosition:(CGPoint)position {
	UICollectionViewLayoutAttributes *attributes = [[super layoutAttributesForInteractivelyMovingItemAtIndexPath:indexPath withTargetPosition:position] copy];
	if (!attributes)
		attributes = [[self layoutAttributesForItemAtIndexPath:indexPath] copy];
	attributes.center = position;
	attributes.zIndex = NSIntegerMax;
	attributes.alpha = 0.96;
	attributes.transform = CGAffineTransformMakeScale(1.03, 1.03);
	return attributes;
}

- (NSIndexPath *)targetIndexPathForInteractivelyMovingItem:(NSIndexPath *)previousIndexPath withPosition:(CGPoint)position {
	NSIndexPath *indexPathAtPoint = [self.collectionView indexPathForItemAtPoint:position];
	if (indexPathAtPoint)
		return indexPathAtPoint;

	NSIndexPath *nearestIndexPath = previousIndexPath;
	CGFloat nearestDistance = CGFLOAT_MAX;
	for (UICollectionViewLayoutAttributes *attributes in self.visibleAttributes) {
		CGFloat dx = attributes.center.x - position.x;
		CGFloat dy = attributes.center.y - position.y;
		CGFloat distance = dx * dx + dy * dy;
		if (distance < nearestDistance) {
			nearestDistance = distance;
			nearestIndexPath = attributes.indexPath;
		}
	}
	return nearestIndexPath;
}

@end
