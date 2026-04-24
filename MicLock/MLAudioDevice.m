#import "MLAudioDevice.h"

@implementation MLAudioDevice

+ (instancetype)deviceWithID:(AudioDeviceID)deviceID
                         uid:(NSString *)uid
                        name:(NSString *)name
                 displayName:(NSString *)displayName
               transportType:(UInt32)transportType
                     builtIn:(BOOL)builtIn
{
    return [[self alloc] initWithID:deviceID
                                uid:uid
                               name:name
                        displayName:displayName
                      transportType:transportType
                            builtIn:builtIn];
}

- (instancetype)initWithID:(AudioDeviceID)deviceID
                       uid:(NSString *)uid
                      name:(NSString *)name
               displayName:(NSString *)displayName
             transportType:(UInt32)transportType
                   builtIn:(BOOL)builtIn
{
    self = [super init];
    if (self != nil)
    {
        _deviceID = deviceID;
        _uid = [uid copy] ?: @"";
        _name = [name copy] ?: @"";
        _displayName = [displayName copy] ?: _name;
        _transportType = transportType;
        _builtIn = builtIn;
    }
    return self;
}

@end
