//
//  SegmentedTextField.h
//  Battman
//
//  Created by Torrekie on 2025/10/16.
//

#import <UIKit/UIKit.h>

@interface SegmentedTextField : UISegmentedControl

- (instancetype)initWithItems:(NSArray *)items;
- (UITextField *)textFieldAtIndex:(NSInteger)index;

@end
