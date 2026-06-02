#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@class MLAudioDevice;

@interface MLAudioDeviceService : NSObject

- (NSArray<MLAudioDevice *> *)availableInputDevices;
- (AudioDeviceID)currentDefaultInputDevice;
- (BOOL)setDefaultInputDevice:(AudioDeviceID)deviceID;
- (BOOL)getInputVolume:(Float32 *)volume forDevice:(AudioDeviceID)deviceID;
- (BOOL)setInputVolume:(Float32)volume forDevice:(AudioDeviceID)deviceID;
- (BOOL)getInputMuted:(BOOL *)muted forDevice:(AudioDeviceID)deviceID;
- (BOOL)setInputMuted:(BOOL)muted forDevice:(AudioDeviceID)deviceID;

- (void)startMonitoringWithChangeHandler:(dispatch_block_t)changeHandler;
- (void)stopMonitoring;

- (void)startObservingDevice:(AudioDeviceID)deviceID changeHandler:(dispatch_block_t)changeHandler;
- (void)stopObservingDevice;

@end
