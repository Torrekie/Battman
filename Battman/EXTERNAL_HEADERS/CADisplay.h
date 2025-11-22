#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@interface CADisplayMode : NSObject
@property (nonatomic, readonly, assign) NSUInteger width;
@property (nonatomic, readonly, assign) NSUInteger height;
@property (nonatomic, readonly, assign) CGFloat pixelAspectRatio;
@property (nonatomic, readonly, assign) CGFloat refreshRate;
@property (nonatomic, readonly, assign) BOOL isVirtual;
@property (nonatomic, readonly, assign, getter=isHighBandwidth) BOOL highBandwidth;
@property (nonatomic, readonly, copy) NSString *colorMode;
@property (nonatomic, readonly, assign) BOOL colorModeIsYCbCr;
@property (nonatomic, readonly, assign) NSUInteger preferredScale;
@property (nonatomic, readonly, copy) NSString *hdrMode;
@property (nonatomic, readonly, copy) NSString *colorGamut;
@property (nonatomic, readonly, assign) NSUInteger bitDepth;
@property (nonatomic, readonly, assign) BOOL isVRR;
@property (nonatomic, readonly, assign) NSUInteger internalRepresentation;
@end

@interface CADisplayAttributes : NSObject
@property (atomic, readonly, assign) NSInteger dolbyVision;
@property (atomic, readonly, assign) NSInteger pqEOTF;
@property (atomic, readonly, assign) NSInteger hdrStaticMetadataType1;
@property (atomic, readonly, assign) NSInteger bt2020YCC;
@property (atomic, readonly, assign) BOOL legacyHDMIEDID;
@property (atomic, readonly, assign) uint32_t manufaturerID;
@property (atomic, readonly, assign) uint32_t productID;
@property (atomic, readonly, assign) uint32_t weekOfManufacture;
@property (atomic, readonly, assign) uint32_t yearOfManufacture;
@property (atomic, readonly, assign) uint32_t serialNumber;
@end

@interface CADisplayPreferences : NSObject
@property (nonatomic, assign) BOOL matchContent;
@property (nonatomic, copy) NSString *preferredHdrMode;
@property (nonatomic, readonly, assign) int _preferredHdrType;
@end

@interface CADisplay : NSObject
@property (nonatomic, readonly, strong) NSArray *availableModes;
@property (nonatomic, strong) CADisplayMode *currentMode;
@property (nonatomic, readonly, strong) CADisplayMode *preferredMode;
@property (nonatomic, copy) NSString *colorMode;
@property (atomic, assign) BOOL allowsVirtualModes;
@property (nonatomic, readonly, assign) CGRect bounds;
@property (nonatomic, readonly, assign) CGRect frame;
@property (nonatomic, readonly, strong) NSString *name;
@property (nonatomic, readonly, strong) NSString *deviceName;
@property (nonatomic, readonly, assign) uint32_t displayId;
@property (nonatomic, readonly, assign) NSInteger displayType;
@property (nonatomic, readonly, assign) uint32_t seed;
@property (nonatomic, readonly, assign) uint32_t connectionSeed;
@property (nonatomic, readonly, strong) NSString *uniqueId;
@property (nonatomic, readonly, strong) NSString *containerId;
@property (nonatomic, readonly, assign, getter=isSupported) BOOL supported;
@property (nonatomic, readonly, assign) NSInteger tag;
@property (nonatomic, readonly, assign) int processId;
@property (nonatomic, readonly, assign, getter=isExternal) BOOL external;
@property (nonatomic, readonly, assign) CGFloat refreshRate;
@property (nonatomic, readonly, assign) CGFloat heartbeatRate;
@property (nonatomic, readonly, assign) NSInteger minimumFrameDuration;
@property (nonatomic, readonly, assign) BOOL hasNativeFrameRateRequest;
@property (nonatomic, readonly, assign, getter=isOverscanned) BOOL overscanned;
@property (nonatomic, copy) NSString *overscanAdjustment;
@property (nonatomic, readonly, assign) CGFloat overscanAmount;
@property (nonatomic, readonly, assign) CGSize overscanAmounts;
@property (nonatomic, readonly, assign, getter=isCloned) BOOL cloned;
@property (nonatomic, readonly, assign, getter=isCloning) BOOL cloning;
@property (nonatomic, readonly, assign, getter=isCloningSupported) BOOL cloningSupported;
@property (nonatomic, readonly, strong) NSString *nativeOrientation;
@property (nonatomic, readonly, strong) NSString *currentOrientation;
@property (nonatomic, readonly, assign) uint32_t odLUTVersion;
@property (nonatomic, readonly, assign) BOOL supportsExtendedColors;
@property (nonatomic, readonly, strong) CADisplayAttributes *externalDisplayAttributes;
@property (nonatomic, readonly, assign) int linkQuality;
@property (nonatomic, assign) CGFloat latency;
@property (nonatomic, copy) CADisplayPreferences *preferences;
@property (nonatomic, readonly, strong) NSString *productName;

+ (NSArray<CADisplay *> *)displays;
+ (instancetype)mainDisplay;
@end
