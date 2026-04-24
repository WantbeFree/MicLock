#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@class MLAudioDevice;
@class MLFallbackSelection;

@interface MLInputResolution : NSObject

@property (nonatomic, strong, readonly) MLAudioDevice *device;
@property (nonatomic, copy, readonly) NSString *activeSourceTitle;
@property (nonatomic, assign, readonly) BOOL preferredInputAvailable;

+ (instancetype)resolutionWithDevice:(MLAudioDevice *)device
                    activeSourceTitle:(NSString *)activeSourceTitle
              preferredInputAvailable:(BOOL)preferredInputAvailable;

- (instancetype)initWithDevice:(MLAudioDevice *)device
             activeSourceTitle:(NSString *)activeSourceTitle
       preferredInputAvailable:(BOOL)preferredInputAvailable NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MLInputSelectionResolver : NSObject

+ (MLAudioDevice *)initialPrimaryDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices
                                    currentDefault:(AudioDeviceID)currentDefaultInputID;

+ (MLInputResolution *)resolutionFromDevices:(NSArray<MLAudioDevice *> *)devices
                              currentDefault:(AudioDeviceID)currentDefaultInputID
                           preferredInputUID:(NSString *)preferredInputUID
                          fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections;

+ (MLAudioDevice *)deviceWithUID:(NSString *)uid inDevices:(NSArray<MLAudioDevice *> *)devices;
+ (MLAudioDevice *)deviceWithID:(AudioDeviceID)deviceID inDevices:(NSArray<MLAudioDevice *> *)devices;
+ (MLAudioDevice *)builtInDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices;
+ (MLAudioDevice *)firstNonAvoidedAutomaticFallbackDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices;
+ (BOOL)isAvoidedAutomaticFallbackTransportType:(UInt32)transportType;

@end
