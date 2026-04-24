#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@interface MLAudioDevice : NSObject

@property (nonatomic, assign, readonly) AudioDeviceID deviceID;
@property (nonatomic, copy, readonly) NSString *uid;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign, readonly) UInt32 transportType;
@property (nonatomic, assign, readonly, getter=isBuiltIn) BOOL builtIn;

+ (instancetype)deviceWithID:(AudioDeviceID)deviceID
                         uid:(NSString *)uid
                        name:(NSString *)name
                 displayName:(NSString *)displayName
               transportType:(UInt32)transportType
                     builtIn:(BOOL)builtIn;

- (instancetype)initWithID:(AudioDeviceID)deviceID
                       uid:(NSString *)uid
                      name:(NSString *)name
               displayName:(NSString *)displayName
             transportType:(UInt32)transportType
                   builtIn:(BOOL)builtIn NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end
