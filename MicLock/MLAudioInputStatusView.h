#import <Cocoa/Cocoa.h>

@interface MLAudioInputStatusView : NSView

@property (nonatomic, strong, readonly) NSSlider *volumeSlider;
@property (nonatomic, strong, readonly) NSButton *muteCheckbox;
@property (nonatomic, strong, readonly) NSButton *monitoringCheckbox;

- (instancetype)initWithTarget:(id)target
                  volumeAction:(SEL)volumeAction
                    muteAction:(SEL)muteAction
              monitoringAction:(SEL)monitoringAction NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

- (void)updateWithDeviceName:(NSString *)deviceName
                  statusText:(NSString *)statusText
                       level:(CGFloat)level
                 inputVolume:(Float32)inputVolume
             volumeAvailable:(BOOL)volumeAvailable
                       muted:(BOOL)muted
               muteAvailable:(BOOL)muteAvailable
                  monitoring:(BOOL)monitoring
         monitoringAvailable:(BOOL)monitoringAvailable
              levelAvailable:(BOOL)levelAvailable;

@end
