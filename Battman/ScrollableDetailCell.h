//
//  ScrollableDetailCell.h
//  Battman
//
//  Created by Torrekie on 2025/12/3.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// UITableViewCell subclass that replaces the system's detailTextLabel with a horizontally scrollable label.
/// Use it like a regular cell class (registerClass:forCellReuseIdentifier: or in storyboard).
@interface ScrollableDetailCell : UITableViewCell

@end

NS_ASSUME_NONNULL_END
