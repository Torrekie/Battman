// Test-only non-Analytics extension point. Never ship this as app ABI.
#import <Foundation/Foundation.h>

#define BT_PLUGIN_EXTENSION_POINT_MOCK_STATUS_V1 "com.torrekie.battman.tests.status-provider.v1"
#define BTMockStatusExtensionPointIdentifier @BT_PLUGIN_EXTENSION_POINT_MOCK_STATUS_V1
#define BTMockStatusExtensionPointVersion 1u

@protocol BTMockStatusProvider <NSObject>
@property (nonatomic, readonly, copy) NSString *mockStatusIdentifier;
- (NSDictionary<NSString *, NSString *> *)currentMockStatus;
@end
