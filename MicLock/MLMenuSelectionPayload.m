#import "MLMenuSelectionPayload.h"
#import "MLAudioDevice.h"

@implementation MLMenuSelectionPayload

+ (instancetype)payloadWithDevice:(MLAudioDevice *)device slot:(NSUInteger)slot
{
    return [[self alloc] initWithDevice:device slot:slot];
}

- (instancetype)initWithDevice:(MLAudioDevice *)device slot:(NSUInteger)slot
{
    self = [super init];
    if (self)
    {
        _device = device;
        _slot = slot;
    }

    return self;
}

@end
