#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@class MLAudioDevice;

@interface MLAudioDeviceService : NSObject

- (NSArray<MLAudioDevice *> *)availableInputDevices;
- (AudioDeviceID)currentDefaultInputDevice;
- (BOOL)setDefaultInputDevice:(AudioDeviceID)deviceID;

- (void)startMonitoringWithChangeHandler:(dispatch_block_t)changeHandler;
- (void)stopMonitoring;

@end
