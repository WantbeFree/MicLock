#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class MLAudioInputMonitor;

@protocol MLAudioInputMonitorDelegate <NSObject>

- (void)audioInputMonitor:(MLAudioInputMonitor *)monitor didUpdateLevel:(CGFloat)level decibels:(Float32)decibels;
- (void)audioInputMonitor:(MLAudioInputMonitor *)monitor didFailWithMessage:(NSString *)message;

@end

@interface MLAudioInputMonitor : NSObject

@property (nonatomic, weak) id<MLAudioInputMonitorDelegate> delegate;
@property (atomic, assign, readonly, getter=isMonitoring) BOOL monitoring;
@property (nonatomic, copy, readonly) NSString *lastErrorMessage;

- (AVAuthorizationStatus)microphoneAuthorizationStatus;
- (void)requestMicrophoneAccessWithCompletion:(void (^)(BOOL granted))completion;

- (BOOL)startMonitoring;
- (void)stopMonitoring;

@end
