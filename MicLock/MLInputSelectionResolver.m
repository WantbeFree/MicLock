#import "MLInputSelectionResolver.h"
#import "MLAudioDevice.h"
#import "MLFallbackSelection.h"

@implementation MLInputResolution

+ (instancetype)resolutionWithDevice:(MLAudioDevice *)device
              preferredInputAvailable:(BOOL)preferredInputAvailable
{
    return [[self alloc] initWithDevice:device
                preferredInputAvailable:preferredInputAvailable];
}

- (instancetype)initWithDevice:(MLAudioDevice *)device
       preferredInputAvailable:(BOOL)preferredInputAvailable
{
    self = [super init];
    if (self != nil)
    {
        _device = device;
        _preferredInputAvailable = preferredInputAvailable;
    }
    return self;
}

@end

@implementation MLInputSelectionResolver

+ (MLAudioDevice *)initialPrimaryDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices
                                    currentDefault:(AudioDeviceID)currentDefaultInputID
{
    MLAudioDevice *initialDevice = [self builtInDeviceFromDevices:devices];
    if (initialDevice == nil)
    {
        initialDevice = [self firstNonAvoidedAutomaticFallbackDeviceFromDevices:devices];
    }
    if (initialDevice == nil)
    {
        initialDevice = [self deviceWithID:currentDefaultInputID inDevices:devices];
    }
    if (initialDevice == nil)
    {
        initialDevice = devices.firstObject;
    }
    return initialDevice;
}

+ (MLInputResolution *)resolutionFromDevices:(NSArray<MLAudioDevice *> *)devices
                              currentDefault:(AudioDeviceID)currentDefaultInputID
                           preferredInputUID:(NSString *)preferredInputUID
                          fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
{
    MLAudioDevice *primaryDevice = [self deviceWithUID:preferredInputUID inDevices:devices];
    if (primaryDevice != nil)
    {
        return [MLInputResolution resolutionWithDevice:primaryDevice
                               preferredInputAvailable:YES];
    }

    BOOL preferredInputAvailable = (preferredInputUID.length == 0);
    for (NSUInteger slot = 0; slot < fallbackSelections.count; slot++)
    {
        MLFallbackSelection *selection = fallbackSelections[slot];
        MLAudioDevice *fallbackDevice = [self deviceWithUID:selection.uid inDevices:devices];
        if (fallbackDevice != nil)
        {
            return [MLInputResolution resolutionWithDevice:fallbackDevice
                                   preferredInputAvailable:preferredInputAvailable];
        }
    }

    MLAudioDevice *automaticDevice = [self builtInDeviceFromDevices:devices];
    if (automaticDevice != nil)
    {
        return [MLInputResolution resolutionWithDevice:automaticDevice
                               preferredInputAvailable:preferredInputAvailable];
    }

    automaticDevice = [self firstNonAvoidedAutomaticFallbackDeviceFromDevices:devices];
    if (automaticDevice != nil)
    {
        return [MLInputResolution resolutionWithDevice:automaticDevice
                               preferredInputAvailable:preferredInputAvailable];
    }

    automaticDevice = [self deviceWithID:currentDefaultInputID inDevices:devices];
    if (automaticDevice != nil)
    {
        return [MLInputResolution resolutionWithDevice:automaticDevice
                               preferredInputAvailable:preferredInputAvailable];
    }

    automaticDevice = devices.firstObject;
    return [MLInputResolution resolutionWithDevice:automaticDevice
                           preferredInputAvailable:preferredInputAvailable];
}

+ (MLAudioDevice *)deviceWithUID:(NSString *)uid inDevices:(NSArray<MLAudioDevice *> *)devices
{
    if (uid.length == 0)
    {
        return nil;
    }

    for (MLAudioDevice *device in devices)
    {
        if ([device.uid isEqualToString:uid])
        {
            return device;
        }
    }
    return nil;
}

+ (MLAudioDevice *)deviceWithID:(AudioDeviceID)deviceID inDevices:(NSArray<MLAudioDevice *> *)devices
{
    if (deviceID == kAudioDeviceUnknown)
    {
        return nil;
    }

    for (MLAudioDevice *device in devices)
    {
        if (device.deviceID == deviceID)
        {
            return device;
        }
    }
    return nil;
}

+ (MLAudioDevice *)builtInDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices
{
    for (MLAudioDevice *device in devices)
    {
        if (device.isBuiltIn)
        {
            return device;
        }
    }
    return nil;
}

+ (MLAudioDevice *)firstNonAvoidedAutomaticFallbackDeviceFromDevices:(NSArray<MLAudioDevice *> *)devices
{
    for (MLAudioDevice *device in devices)
    {
        if (![self isAvoidedAutomaticFallbackTransportType:device.transportType])
        {
            return device;
        }
    }
    return nil;
}

+ (BOOL)isAvoidedAutomaticFallbackTransportType:(UInt32)transportType
{
    switch (transportType)
    {
        case kAudioDeviceTransportTypeBluetooth:
        case kAudioDeviceTransportTypeBluetoothLE:
        case kAudioDeviceTransportTypeAirPlay:
        case kAudioDeviceTransportTypeContinuityCaptureWired:
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            return YES;

        default:
            return NO;
    }
}

@end
