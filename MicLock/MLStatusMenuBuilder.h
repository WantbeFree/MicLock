#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>

@class MLAudioDevice;
@class MLFallbackSelection;

@protocol MLStatusMenuActionHandling <NSObject>

- (void)manualPause:(NSMenuItem *)item;
- (void)refreshAudioDevices:(NSMenuItem *)item;
- (void)reviveAudio:(NSMenuItem *)item;
- (void)savedInputSelected:(NSMenuItem *)item;
- (void)primaryDeviceSelected:(NSMenuItem *)item;
- (void)fallbackDeviceSelected:(NSMenuItem *)item;
- (void)clearFallbackDevice:(NSMenuItem *)item;
- (void)toggleStartupItem;
- (void)terminate;

@end

@interface MLStatusMenuBuildResult : NSObject

@property (nonatomic, strong, readonly) NSMenu *menu;
@property (nonatomic, strong, readonly) NSMenuItem *startupItem;

+ (instancetype)resultWithMenu:(NSMenu *)menu startupItem:(NSMenuItem *)startupItem;
- (instancetype)initWithMenu:(NSMenu *)menu startupItem:(NSMenuItem *)startupItem NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MLStatusMenuBuilder : NSObject

+ (MLStatusMenuBuildResult *)menuWithDevices:(NSArray<MLAudioDevice *> *)devices
                       currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
                           preferredInputUID:(NSString *)preferredInputUID
                    preferredInputDisplayName:(NSString *)preferredInputDisplayName
                          fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                                      paused:(BOOL)paused
                                      target:(id<MLStatusMenuActionHandling>)target
                                    delegate:(id<NSMenuDelegate>)delegate;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end
