//
//  VirtBriCardCell.h
//  Battman
//
//  Created by Torrekie on 2025/11/19.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtBriCardCell : UITableViewCell

// Hardware capabilities
@property (nonatomic, assign) BOOL digitalDimmingSupported;
@property (nonatomic, assign) BOOL extrabrightEDRSupported;

// Nits range values
@property (nonatomic, assign) NSInteger hardwareAccessibleMaxNits;
@property (nonatomic, assign) NSInteger hardwareAccessibleMinNits;
@property (nonatomic, assign) NSInteger minNitsAccessibleWithDigitalDimming;
@property (nonatomic, assign) NSInteger userAccessibleMaxNits;

// Current state values
@property (nonatomic, assign) CGFloat brightnessPercentage;
@property (nonatomic, assign) CGFloat currentNits;
@property (nonatomic, assign) CGFloat currentNitsPhysical;

@end

NS_ASSUME_NONNULL_END
