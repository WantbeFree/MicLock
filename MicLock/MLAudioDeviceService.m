#import "MLAudioDeviceService.h"
#import "MLAudioDevice.h"

static AudioObjectPropertyAddress MLAudioAddress(AudioObjectPropertySelector selector,
                                                 AudioObjectPropertyScope scope)
{
    AudioObjectPropertyAddress address = {
        selector,
        scope,
        kAudioObjectPropertyElementMain
    };
    return address;
}

static void MLLogAudioStatus(NSString *operation, OSStatus status)
{
    if (status != noErr)
    {
        NSLog(@"%@ failed with OSStatus %d", operation, (int)status);
    }
}

@interface MLAudioDeviceService ()

@property (nonatomic, strong) dispatch_queue_t listenerQueue;
@property (nonatomic, copy) AudioObjectPropertyListenerBlock changeListener;
@property (nonatomic, copy) dispatch_block_t changeHandler;

@end

@implementation MLAudioDeviceService

- (NSArray<MLAudioDevice *> *)availableInputDevices
{
    AudioObjectPropertyAddress devicesAddress = MLAudioAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                     &devicesAddress,
                                                     0,
                                                     NULL,
                                                     &dataSize);

    if (status != noErr || dataSize == 0)
    {
        MLLogAudioStatus(@"AudioObjectGetPropertyDataSize(devices)", status);
        return @[];
    }

    NSMutableData *deviceData = [NSMutableData dataWithLength:dataSize];
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                        &devicesAddress,
                                        0,
                                        NULL,
                                        &dataSize,
                                        deviceData.mutableBytes);

    if (status != noErr)
    {
        MLLogAudioStatus(@"AudioObjectGetPropertyData(devices)", status);
        return @[];
    }

    AudioDeviceID *deviceIDs = deviceData.mutableBytes;
    NSUInteger deviceCount = dataSize / sizeof(AudioDeviceID);
    NSMutableArray<MLAudioDevice *> *devices = [NSMutableArray array];

    for (NSUInteger index = 0; index < deviceCount; index++)
    {
        AudioDeviceID deviceID = deviceIDs[index];
        if (![self deviceIsAlive:deviceID] ||
            ![self deviceHasInputChannels:deviceID] ||
            ![self deviceCanBeDefaultInput:deviceID])
        {
            continue;
        }

        NSString *name = [self stringPropertyForObject:deviceID
                                              selector:kAudioObjectPropertyName
                                                 scope:kAudioObjectPropertyScopeGlobal];
        if (name.length == 0)
        {
            name = [NSString stringWithFormat:@"Audio Device %u", deviceID];
        }

        NSString *uid = [self stringPropertyForObject:deviceID
                                             selector:kAudioDevicePropertyDeviceUID
                                                scope:kAudioObjectPropertyScopeGlobal] ?: @"";
        UInt32 transportType = [self uint32PropertyForObject:deviceID
                                                    selector:kAudioDevicePropertyTransportType
                                                       scope:kAudioObjectPropertyScopeGlobal
                                                defaultValue:kAudioDeviceTransportTypeUnknown];
        NSString *displayName = [self displayNameForDeviceName:name transportType:transportType];

        [devices addObject:[MLAudioDevice deviceWithID:deviceID
                                                   uid:uid
                                                  name:name
                                           displayName:displayName
                                         transportType:transportType
                                               builtIn:(transportType == kAudioDeviceTransportTypeBuiltIn)]];
    }

    return devices;
}

- (AudioDeviceID)currentDefaultInputDevice
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioHardwarePropertyDefaultInputDevice,
                                                        kAudioObjectPropertyScopeGlobal);
    AudioDeviceID deviceID = kAudioDeviceUnknown;
    UInt32 dataSize = sizeof(deviceID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &deviceID);

    if (status != noErr)
    {
        MLLogAudioStatus(@"AudioObjectGetPropertyData(defaultInput)", status);
        return kAudioDeviceUnknown;
    }

    return deviceID;
}

- (BOOL)setDefaultInputDevice:(AudioDeviceID)deviceID
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioHardwarePropertyDefaultInputDevice,
                                                        kAudioObjectPropertyScopeGlobal);
    UInt32 dataSize = sizeof(deviceID);
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 dataSize,
                                                 &deviceID);

    if (status != noErr)
    {
        MLLogAudioStatus(@"AudioObjectSetPropertyData(defaultInput)", status);
        return NO;
    }

    return YES;
}

- (void)startMonitoringWithChangeHandler:(dispatch_block_t)changeHandler
{
    [self stopMonitoring];

    self.changeHandler = changeHandler;
    self.listenerQueue = dispatch_queue_create("com.miclock.audio-listener", DISPATCH_QUEUE_SERIAL);

    __weak typeof(self) weakSelf = self;
    self.changeListener = ^(UInt32 inNumberAddresses, const AudioObjectPropertyAddress *inAddresses)
    {
        (void)inNumberAddresses;
        (void)inAddresses;

        dispatch_async(dispatch_get_main_queue(), ^
        {
            MLAudioDeviceService *strongSelf = weakSelf;
            if (strongSelf.changeHandler != nil)
            {
                strongSelf.changeHandler();
            }
        });
    };

    [self addListenerForAddress:MLAudioAddress(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)];
    [self addListenerForAddress:MLAudioAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)];
}

- (void)stopMonitoring
{
    if (self.changeListener == nil)
    {
        self.changeHandler = nil;
        return;
    }

    [self removeListenerForAddress:MLAudioAddress(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)];
    [self removeListenerForAddress:MLAudioAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)];

    self.changeListener = nil;
    self.changeHandler = nil;
    self.listenerQueue = nil;
}

- (void)addListenerForAddress:(AudioObjectPropertyAddress)address
{
    OSStatus status = AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject,
        &address,
        self.listenerQueue,
        self.changeListener);

    MLLogAudioStatus(@"AudioObjectAddPropertyListenerBlock", status);
}

- (void)removeListenerForAddress:(AudioObjectPropertyAddress)address
{
    OSStatus status = AudioObjectRemovePropertyListenerBlock(
        kAudioObjectSystemObject,
        &address,
        self.listenerQueue,
        self.changeListener);

    MLLogAudioStatus(@"AudioObjectRemovePropertyListenerBlock", status);
}

- (BOOL)deviceIsAlive:(AudioDeviceID)deviceID
{
    UInt32 alive = [self uint32PropertyForObject:deviceID
                                        selector:kAudioDevicePropertyDeviceIsAlive
                                           scope:kAudioObjectPropertyScopeGlobal
                                    defaultValue:0];
    return alive != 0;
}

- (BOOL)deviceCanBeDefaultInput:(AudioDeviceID)deviceID
{
    UInt32 canBeDefault = [self uint32PropertyForObject:deviceID
                                               selector:kAudioDevicePropertyDeviceCanBeDefaultDevice
                                                  scope:kAudioObjectPropertyScopeInput
                                           defaultValue:0];
    return canBeDefault != 0;
}

- (BOOL)deviceHasInputChannels:(AudioDeviceID)deviceID
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioDevicePropertyStreamConfiguration,
                                                        kAudioObjectPropertyScopeInput);
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &dataSize);
    if (status != noErr || dataSize == 0)
    {
        return NO;
    }

    NSMutableData *bufferData = [NSMutableData dataWithLength:dataSize];
    status = AudioObjectGetPropertyData(deviceID,
                                        &address,
                                        0,
                                        NULL,
                                        &dataSize,
                                        bufferData.mutableBytes);
    if (status != noErr)
    {
        MLLogAudioStatus(@"AudioObjectGetPropertyData(streamConfiguration)", status);
        return NO;
    }

    AudioBufferList *bufferList = bufferData.mutableBytes;
    UInt32 channelCount = 0;
    for (UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; bufferIndex++)
    {
        channelCount += bufferList->mBuffers[bufferIndex].mNumberChannels;
    }

    return channelCount > 0;
}

- (NSString *)displayNameForDeviceName:(NSString *)name transportType:(UInt32)transportType
{
    NSString *transportLabel = [self labelForTransportType:transportType];
    if (transportLabel.length == 0)
    {
        return name;
    }

    return [NSString stringWithFormat:@"%@ (%@)", name, transportLabel];
}

- (NSString *)labelForTransportType:(UInt32)transportType
{
    switch (transportType)
    {
        case kAudioDeviceTransportTypeBuiltIn:
            return @"Built-in";

        case kAudioDeviceTransportTypeBluetooth:
        case kAudioDeviceTransportTypeBluetoothLE:
            return @"Bluetooth";

        case kAudioDeviceTransportTypeUSB:
            return @"USB";

        case kAudioDeviceTransportTypeThunderbolt:
            return @"Thunderbolt";

        case kAudioDeviceTransportTypeHDMI:
            return @"HDMI";

        case kAudioDeviceTransportTypeDisplayPort:
            return @"DisplayPort";

        case kAudioDeviceTransportTypeAirPlay:
            return @"AirPlay";

        case kAudioDeviceTransportTypeContinuityCaptureWired:
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            return @"Continuity";

        case kAudioDeviceTransportTypeVirtual:
            return @"Virtual";

        default:
            return @"";
    }
}

- (NSString *)stringPropertyForObject:(AudioObjectID)objectID
                             selector:(AudioObjectPropertySelector)selector
                                scope:(AudioObjectPropertyScope)scope
{
    AudioObjectPropertyAddress address = MLAudioAddress(selector, scope);
    CFStringRef stringValue = NULL;
    UInt32 dataSize = sizeof(stringValue);
    OSStatus status = AudioObjectGetPropertyData(objectID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &stringValue);

    if (status != noErr || stringValue == NULL)
    {
        return nil;
    }

    return CFBridgingRelease(stringValue);
}

- (UInt32)uint32PropertyForObject:(AudioObjectID)objectID
                         selector:(AudioObjectPropertySelector)selector
                            scope:(AudioObjectPropertyScope)scope
                     defaultValue:(UInt32)defaultValue
{
    AudioObjectPropertyAddress address = MLAudioAddress(selector, scope);
    UInt32 value = defaultValue;
    UInt32 dataSize = sizeof(value);
    OSStatus status = AudioObjectGetPropertyData(objectID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &value);

    if (status != noErr)
    {
        return defaultValue;
    }

    return value;
}

@end
