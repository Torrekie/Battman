//
//  BrightnessCardCell.h
//  Battman
//
//  Created by Torrekie on 2025/11/15.
//

#import <UIKit/UIKit.h>

@interface BrightnessCardCell : UITableViewCell

@property (nonatomic, copy) NSString *resolutionText;
@property (nonatomic, copy) NSString *displayGamut;
@property (nonatomic, assign) BOOL isNightShiftSupported;
@property (nonatomic, assign) BOOL isTrueToneSupported;
@property (nonatomic, assign) CGFloat temperatureCelsius;
@property (nonatomic, assign) BOOL unknownTemperature;

@end
