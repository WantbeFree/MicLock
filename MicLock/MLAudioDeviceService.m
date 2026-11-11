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

static AudioObjectPropertyAddress MLAudioElementAddress(AudioObjectPropertySelector selector,
                                                        AudioObjectPropertyScope scope,
                                                        AudioObjectPropertyElement element)
{
    AudioObjectPropertyAddress address = {
        selector,
        scope,
        element
    };
    return address;
}

static NSUInteger const MLPlayThroughReapplyLimit = 3;
static NSTimeInterval const MLPlayThroughReapplyWindow = 30.0;

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

@property (nonatomic, strong) dispatch_queue_t deviceListenerQueue;
@property (nonatomic, copy) AudioObjectPropertyListenerBlock deviceChangeListener;
@property (nonatomic, copy) dispatch_block_t deviceChangeHandler;
@property (nonatomic, assign) AudioDeviceID observedDeviceID;
@property (nonatomic, assign) UInt32 observedChannelCount;

@property (nonatomic, copy) NSArray<NSNumber *> *playThroughObservedDeviceIDs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *playThroughReapplyUptimesByUID;

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

- (BOOL)getInputVolume:(Float32 *)volume forDevice:(AudioDeviceID)deviceID
{
    if (volume == NULL || deviceID == kAudioDeviceUnknown)
    {
        return NO;
    }

    Float32 masterVolume = 0.0f;
    if ([self getInputVolume:&masterVolume forDevice:deviceID element:kAudioObjectPropertyElementMain])
    {
        *volume = masterVolume;
        return YES;
    }

    UInt32 channelCount = [self inputChannelCountForDevice:deviceID];
    if (channelCount == 0)
    {
        return NO;
    }

    Float32 volumeSum = 0.0f;
    UInt32 readableChannelCount = 0;
    for (UInt32 channel = 1; channel <= channelCount; channel++)
    {
        Float32 channelVolume = 0.0f;
        if ([self getInputVolume:&channelVolume forDevice:deviceID element:channel])
        {
            volumeSum += channelVolume;
            readableChannelCount += 1;
        }
    }

    if (readableChannelCount == 0)
    {
        return NO;
    }

    *volume = volumeSum / readableChannelCount;
    return YES;
}

- (BOOL)setInputVolume:(Float32)volume forDevice:(AudioDeviceID)deviceID
{
    if (deviceID == kAudioDeviceUnknown)
    {
        return NO;
    }

    Float32 clampedVolume = MIN(1.0f, MAX(0.0f, volume));
    if ([self setInputVolume:clampedVolume forDevice:deviceID element:kAudioObjectPropertyElementMain])
    {
        return YES;
    }

    UInt32 channelCount = [self inputChannelCountForDevice:deviceID];
    BOOL didSetAnyChannel = NO;
    for (UInt32 channel = 1; channel <= channelCount; channel++)
    {
        if ([self setInputVolume:clampedVolume forDevice:deviceID element:channel])
        {
            didSetAnyChannel = YES;
        }
    }

    return didSetAnyChannel;
}

- (BOOL)getInputMuted:(BOOL *)muted forDevice:(AudioDeviceID)deviceID
{
    if (muted == NULL || deviceID == kAudioDeviceUnknown)
    {
        return NO;
    }

    BOOL readAnyElement = NO;
    BOOL anyMuted = NO;

    UInt32 masterMuted = 0;
    if ([self getInputMuted:&masterMuted forDevice:deviceID element:kAudioObjectPropertyElementMain])
    {
        readAnyElement = YES;
        anyMuted = anyMuted || (masterMuted != 0);
    }

    UInt32 channelCount = [self inputChannelCountForDevice:deviceID];
    for (UInt32 channel = 1; channel <= channelCount; channel++)
    {
        UInt32 channelMuted = 0;
        if ([self getInputMuted:&channelMuted forDevice:deviceID element:channel])
        {
            readAnyElement = YES;
            anyMuted = anyMuted || (channelMuted != 0);
        }
    }

    if (!readAnyElement)
    {
        return NO;
    }

    *muted = anyMuted;
    return YES;
}

- (BOOL)setInputMuted:(BOOL)muted forDevice:(AudioDeviceID)deviceID
{
    if (deviceID == kAudioDeviceUnknown)
    {
        return NO;
    }

    UInt32 mutedValue = muted ? 1 : 0;
    BOOL didSetAnyElement = NO;

    if ([self setInputMuted:mutedValue forDevice:deviceID element:kAudioObjectPropertyElementMain])
    {
        didSetAnyElement = YES;
    }

    UInt32 channelCount = [self inputChannelCountForDevice:deviceID];
    for (UInt32 channel = 1; channel <= channelCount; channel++)
    {
        if ([self setInputMuted:mutedValue forDevice:deviceID element:channel])
        {
            didSetAnyElement = YES;
        }
    }

    return didSetAnyElement;
}

- (BOOL)getInputPlayThrough:(BOOL *)playThrough forDevice:(AudioDeviceID)deviceID
{
    if (playThrough == NULL)
    {
        return NO;
    }

    BOOL readAnyElement = NO;
    BOOL anyPlayThrough = NO;
    for (NSValue *addressValue in [self inputPlayThroughAddressesForDevice:deviceID])
    {
        AudioObjectPropertyAddress address;
        [addressValue getValue:&address];

        UInt32 value = 0;
        if ([self getUInt32:&value forDevice:deviceID address:address])
        {
            readAnyElement = YES;
            anyPlayThrough = anyPlayThrough || (value != 0);
        }
    }

    if (!readAnyElement)
    {
        return NO;
    }

    *playThrough = anyPlayThrough;
    return YES;
}

- (BOOL)setInputPlayThrough:(BOOL)playThrough forDevice:(AudioDeviceID)deviceID
{
    BOOL didSetAnyElement = NO;
    for (NSValue *addressValue in [self inputPlayThroughAddressesForDevice:deviceID])
    {
        AudioObjectPropertyAddress address;
        [addressValue getValue:&address];

        if ([self setUInt32:(playThrough ? 1 : 0)
                  forDevice:deviceID
                    address:address
                  operation:@"AudioObjectSetPropertyData(inputPlayThrough)"])
        {
            didSetAnyElement = YES;
        }
    }

    return didSetAnyElement;
}

- (NSArray<NSValue *> *)inputPlayThroughAddressesForDevice:(AudioDeviceID)deviceID
{
    if (deviceID == kAudioDeviceUnknown)
    {
        return @[];
    }

    AudioObjectPropertyScope const scopes[] = {
        kAudioDevicePropertyScopePlayThrough,
        kAudioObjectPropertyScopeInput
    };
    UInt32 channelCount = [self inputChannelCountForDevice:deviceID];

    for (size_t scopeIndex = 0; scopeIndex < sizeof(scopes) / sizeof(scopes[0]); scopeIndex++)
    {
        AudioObjectPropertyAddress mainAddress = MLAudioElementAddress(kAudioDevicePropertyPlayThru,
                                                                       scopes[scopeIndex],
                                                                       kAudioObjectPropertyElementMain);
        if ([self deviceHasSettableProperty:mainAddress device:deviceID])
        {
            return @[[NSValue valueWithBytes:&mainAddress objCType:@encode(AudioObjectPropertyAddress)]];
        }

        NSMutableArray<NSValue *> *channelAddresses = [NSMutableArray array];
        for (UInt32 channel = 1; channel <= channelCount; channel++)
        {
            AudioObjectPropertyAddress channelAddress = MLAudioElementAddress(kAudioDevicePropertyPlayThru,
                                                                              scopes[scopeIndex],
                                                                              channel);
            if ([self deviceHasSettableProperty:channelAddress device:deviceID])
            {
                [channelAddresses addObject:[NSValue valueWithBytes:&channelAddress objCType:@encode(AudioObjectPropertyAddress)]];
            }
        }

        if (channelAddresses.count > 0)
        {
            return [channelAddresses copy];
        }
    }

    return @[];
}

- (NSArray<NSNumber *> *)inputPlayThroughDeviceIDsByReapplying:(NSDictionary<NSString *, NSNumber *> *)playThroughByUID
                                                       toDevices:(NSArray<MLAudioDevice *> *)devices
                                              retryReapplyAfter:(NSTimeInterval *)retryReapplyAfter
{
    NSTimeInterval earliestRetry = 0.0;

    if (self.playThroughReapplyUptimesByUID == nil)
    {
        self.playThroughReapplyUptimesByUID = [NSMutableDictionary dictionary];
    }

    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSMutableArray<NSNumber *> *playThroughDeviceIDs = [NSMutableArray array];
    for (MLAudioDevice *device in devices)
    {
        BOOL playThrough = NO;
        if (![self getInputPlayThrough:&playThrough forDevice:device.deviceID])
        {
            continue;
        }

        [playThroughDeviceIDs addObject:@(device.deviceID)];

        NSNumber *storedPlayThrough = playThroughByUID[device.uid];
        if (storedPlayThrough == nil || playThrough == storedPlayThrough.boolValue)
        {
            continue;
        }

        NSPredicate *withinWindow = [NSPredicate predicateWithBlock:^BOOL(NSNumber *uptime, NSDictionary *bindings)
        {
            (void)bindings;
            return now - uptime.doubleValue < MLPlayThroughReapplyWindow;
        }];
        NSArray<NSNumber *> *recentReapplies = [self.playThroughReapplyUptimesByUID[device.uid] filteredArrayUsingPredicate:withinWindow] ?: @[];
        if (recentReapplies.count >= MLPlayThroughReapplyLimit)
        {
            NSTimeInterval retry = MLPlayThroughReapplyWindow - (now - recentReapplies.firstObject.doubleValue);
            earliestRetry = (earliestRetry == 0.0) ? retry : MIN(earliestRetry, retry);
            continue;
        }

        if ([self setInputPlayThrough:storedPlayThrough.boolValue forDevice:device.deviceID])
        {
            recentReapplies = [recentReapplies arrayByAddingObject:@(now)];
            if (recentReapplies.count == MLPlayThroughReapplyLimit)
            {
                NSLog(@"Play-through on %@ was changed back %lu times in %.0f s; pausing reapply for that window",
                      device.displayName, (unsigned long)MLPlayThroughReapplyLimit, MLPlayThroughReapplyWindow);
            }
        }
        self.playThroughReapplyUptimesByUID[device.uid] = recentReapplies;
    }

    if (retryReapplyAfter != NULL)
    {
        *retryReapplyAfter = earliestRetry;
    }
    return [playThroughDeviceIDs copy];
}

- (void)observeInputPlayThroughOnDevices:(NSArray<NSNumber *> *)deviceIDs
{
    [self stopObservingInputPlayThrough];
    if (self.changeListener == nil)
    {
        return;
    }

    AudioObjectPropertyAddress address = MLAudioElementAddress(kAudioDevicePropertyPlayThru,
                                                               kAudioObjectPropertyScopeWildcard,
                                                               kAudioObjectPropertyElementWildcard);
    NSMutableArray<NSNumber *> *observedDeviceIDs = [NSMutableArray array];
    for (NSNumber *deviceID in deviceIDs)
    {
        OSStatus status = AudioObjectAddPropertyListenerBlock(deviceID.unsignedIntValue,
                                                              &address,
                                                              self.listenerQueue,
                                                              self.changeListener);
        MLLogAudioStatus(@"AudioObjectAddPropertyListenerBlock(inputPlayThrough)", status);
        if (status == noErr)
        {
            [observedDeviceIDs addObject:deviceID];
        }
    }

    self.playThroughObservedDeviceIDs = observedDeviceIDs;
}

- (void)stopObservingInputPlayThrough
{
    AudioObjectPropertyAddress address = MLAudioElementAddress(kAudioDevicePropertyPlayThru,
                                                               kAudioObjectPropertyScopeWildcard,
                                                               kAudioObjectPropertyElementWildcard);
    for (NSNumber *deviceID in self.playThroughObservedDeviceIDs)
    {
        AudioObjectRemovePropertyListenerBlock(deviceID.unsignedIntValue,
                                               &address,
                                               self.listenerQueue,
                                               self.changeListener);
    }

    self.playThroughObservedDeviceIDs = @[];
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
    [self stopObservingInputPlayThrough];

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

- (void)startObservingDevice:(AudioDeviceID)deviceID changeHandler:(dispatch_block_t)changeHandler
{
    // Re-register listeners if the channel layout changed, since they are
    // installed per channel element.
    if (self.observedDeviceID == deviceID && self.deviceChangeListener != nil &&
        [self inputChannelCountForDevice:deviceID] == self.observedChannelCount)
    {
        self.deviceChangeHandler = changeHandler;
        return;
    }

    [self stopObservingDevice];

    if (deviceID == kAudioDeviceUnknown)
    {
        return;
    }

    self.observedDeviceID = deviceID;
    self.deviceChangeHandler = changeHandler;
    self.deviceListenerQueue = dispatch_queue_create("com.miclock.device-listener", DISPATCH_QUEUE_SERIAL);

    __weak typeof(self) weakSelf = self;
    self.deviceChangeListener = ^(UInt32 inNumberAddresses, const AudioObjectPropertyAddress *inAddresses)
    {
        (void)inNumberAddresses;
        (void)inAddresses;

        dispatch_async(dispatch_get_main_queue(), ^
        {
            MLAudioDeviceService *strongSelf = weakSelf;
            if (strongSelf.deviceChangeHandler != nil)
            {
                strongSelf.deviceChangeHandler();
            }
        });
    };

    self.observedChannelCount = [self inputChannelCountForDevice:deviceID];

    [self addDeviceListenerForSelector:kAudioDevicePropertyMute];
    [self addDeviceListenerForSelector:kAudioDevicePropertyVolumeScalar];
}

- (void)stopObservingDevice
{
    if (self.deviceChangeListener == nil)
    {
        self.deviceChangeHandler = nil;
        self.observedDeviceID = kAudioDeviceUnknown;
        return;
    }

    [self removeDeviceListenerForSelector:kAudioDevicePropertyMute];
    [self removeDeviceListenerForSelector:kAudioDevicePropertyVolumeScalar];

    self.deviceChangeListener = nil;
    self.deviceChangeHandler = nil;
    self.deviceListenerQueue = nil;
    self.observedDeviceID = kAudioDeviceUnknown;
    self.observedChannelCount = 0;
}

- (void)addDeviceListenerForSelector:(AudioObjectPropertySelector)selector
{
    [self addDeviceListenerForSelector:selector element:kAudioObjectPropertyElementMain];
    for (UInt32 channel = 1; channel <= self.observedChannelCount; channel++)
    {
        [self addDeviceListenerForSelector:selector element:channel];
    }
}

- (void)addDeviceListenerForSelector:(AudioObjectPropertySelector)selector
                             element:(AudioObjectPropertyElement)element
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeInput,
        element
    };
    if (!AudioObjectHasProperty(self.observedDeviceID, &address))
    {
        return;
    }
    OSStatus status = AudioObjectAddPropertyListenerBlock(self.observedDeviceID,
                                                          &address,
                                                          self.deviceListenerQueue,
                                                          self.deviceChangeListener);
    MLLogAudioStatus(@"AudioObjectAddPropertyListenerBlock(device)", status);
}

- (void)removeDeviceListenerForSelector:(AudioObjectPropertySelector)selector
{
    [self removeDeviceListenerForSelector:selector element:kAudioObjectPropertyElementMain];
    for (UInt32 channel = 1; channel <= self.observedChannelCount; channel++)
    {
        [self removeDeviceListenerForSelector:selector element:channel];
    }
}

- (void)removeDeviceListenerForSelector:(AudioObjectPropertySelector)selector
                                element:(AudioObjectPropertyElement)element
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeInput,
        element
    };
    if (!AudioObjectHasProperty(self.observedDeviceID, &address))
    {
        return;
    }
    OSStatus status = AudioObjectRemovePropertyListenerBlock(self.observedDeviceID,
                                                             &address,
                                                             self.deviceListenerQueue,
                                                             self.deviceChangeListener);
    MLLogAudioStatus(@"AudioObjectRemovePropertyListenerBlock(device)", status);
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
    return [self inputChannelCountForDevice:deviceID] > 0;
}

- (UInt32)inputChannelCountForDevice:(AudioDeviceID)deviceID
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioDevicePropertyStreamConfiguration,
                                                        kAudioObjectPropertyScopeInput);
    UInt32 dataSize = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, NULL, &dataSize);
    if (status != noErr || dataSize == 0)
    {
        return 0;
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
        return 0;
    }

    AudioBufferList *bufferList = bufferData.mutableBytes;
    UInt32 channelCount = 0;
    for (UInt32 bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; bufferIndex++)
    {
        channelCount += bufferList->mBuffers[bufferIndex].mNumberChannels;
    }

    return channelCount;
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

- (BOOL)getInputVolume:(Float32 *)volume
             forDevice:(AudioDeviceID)deviceID
               element:(AudioObjectPropertyElement)element
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioDevicePropertyVolumeScalar,
                                                        kAudioObjectPropertyScopeInput);
    address.mElement = element;

    if (!AudioObjectHasProperty(deviceID, &address))
    {
        return NO;
    }

    Float32 value = 0.0f;
    UInt32 dataSize = sizeof(value);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &value);
    if (status != noErr)
    {
        return NO;
    }

    *volume = value;
    return YES;
}

- (BOOL)setInputVolume:(Float32)volume
             forDevice:(AudioDeviceID)deviceID
               element:(AudioObjectPropertyElement)element
{
    AudioObjectPropertyAddress address = MLAudioAddress(kAudioDevicePropertyVolumeScalar,
                                                        kAudioObjectPropertyScopeInput);
    address.mElement = element;

    if (!AudioObjectHasProperty(deviceID, &address))
    {
        return NO;
    }

    Boolean settable = false;
    OSStatus status = AudioObjectIsPropertySettable(deviceID, &address, &settable);
    if (status != noErr || !settable)
    {
        return NO;
    }

    Float32 value = volume;
    UInt32 dataSize = sizeof(value);
    status = AudioObjectSetPropertyData(deviceID,
                                        &address,
                                        0,
                                        NULL,
                                        dataSize,
                                        &value);
    if (status != noErr)
    {
        MLLogAudioStatus(@"AudioObjectSetPropertyData(inputVolume)", status);
        return NO;
    }

    return YES;
}

- (BOOL)getInputMuted:(UInt32 *)muted
            forDevice:(AudioDeviceID)deviceID
              element:(AudioObjectPropertyElement)element
{
    return [self getUInt32:muted
                 forDevice:deviceID
                   address:MLAudioElementAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, element)];
}

- (BOOL)setInputMuted:(UInt32)muted
            forDevice:(AudioDeviceID)deviceID
              element:(AudioObjectPropertyElement)element
{
    return [self setUInt32:muted
                 forDevice:deviceID
                   address:MLAudioElementAddress(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput, element)
                 operation:@"AudioObjectSetPropertyData(inputMute)"];
}

- (BOOL)getUInt32:(UInt32 *)value
        forDevice:(AudioDeviceID)deviceID
          address:(AudioObjectPropertyAddress)address
{
    if (value == NULL || deviceID == kAudioDeviceUnknown || !AudioObjectHasProperty(deviceID, &address))
    {
        return NO;
    }

    UInt32 data = 0;
    UInt32 dataSize = sizeof(data);
    OSStatus status = AudioObjectGetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 &dataSize,
                                                 &data);
    if (status != noErr)
    {
        return NO;
    }

    *value = data;
    return YES;
}

- (BOOL)setUInt32:(UInt32)value
        forDevice:(AudioDeviceID)deviceID
          address:(AudioObjectPropertyAddress)address
        operation:(NSString *)operation
{
    if (![self deviceHasSettableProperty:address device:deviceID])
    {
        return NO;
    }

    UInt32 data = value;
    OSStatus status = AudioObjectSetPropertyData(deviceID,
                                                 &address,
                                                 0,
                                                 NULL,
                                                 sizeof(data),
                                                 &data);
    if (status != noErr)
    {
        MLLogAudioStatus(operation, status);
        return NO;
    }

    return YES;
}

- (BOOL)deviceHasSettableProperty:(AudioObjectPropertyAddress)address device:(AudioDeviceID)deviceID
{
    if (deviceID == kAudioDeviceUnknown || !AudioObjectHasProperty(deviceID, &address))
    {
        return NO;
    }

    Boolean settable = false;
    OSStatus status = AudioObjectIsPropertySettable(deviceID, &address, &settable);
    return status == noErr && settable;
}

@end
