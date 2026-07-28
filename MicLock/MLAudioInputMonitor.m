#import "MLAudioInputMonitor.h"
#import <AudioToolbox/AudioToolbox.h>
#import <ctype.h>
#import <math.h>
#import <string.h>

static UInt32 const MLAudioInputMonitorBufferCount = 3;
// 1024 frames is 23.2 ms at 44.1 kHz, so two buffers fit inside the 50 ms UI update
// window below. At 2048 frames (46.4 ms) every second buffer was discarded by the
// throttle and the meter ran at ~10.8 Hz instead of the intended 20 Hz.
static UInt32 const MLAudioInputMonitorFramesPerBuffer = 1024;

static NSString *MLAudioInputMonitorStatusMessage(OSStatus status)
{
    UInt32 bigEndianStatus = CFSwapInt32HostToBig((UInt32)status);
    char statusCharacters[5] = {0};
    memcpy(statusCharacters, &bigEndianStatus, 4);

    BOOL printable = YES;
    for (NSUInteger index = 0; index < 4; index++)
    {
        if (!isprint(statusCharacters[index]))
        {
            printable = NO;
            break;
        }
    }

    if (printable)
    {
        return [NSString stringWithFormat:@"Audio input failed (%s).", statusCharacters];
    }

    return [NSString stringWithFormat:@"Audio input failed (%d).", (int)status];
}

@interface MLAudioInputMonitor ()

// monitoring and audioQueue are read from the AudioQueue callback thread
// while the main thread mutates them, so they must be atomic.
@property (atomic, assign, readwrite, getter=isMonitoring) BOOL monitoring;
@property (nonatomic, copy, readwrite) NSString *lastErrorMessage;
@property (atomic, assign) AudioQueueRef audioQueue;
@property (nonatomic, assign) AudioStreamBasicDescription audioFormat;
@property (nonatomic, assign) CFTimeInterval lastLevelDispatchTime;

@end

@implementation MLAudioInputMonitor

static void MLAudioInputQueueCallback(void *userData,
                                      AudioQueueRef audioQueue,
                                      AudioQueueBufferRef buffer,
                                      const AudioTimeStamp *startTime,
                                      UInt32 numberPacketDescriptions,
                                      const AudioStreamPacketDescription *packetDescriptions)
{
    (void)startTime;
    (void)numberPacketDescriptions;
    (void)packetDescriptions;

    MLAudioInputMonitor *monitor = (__bridge MLAudioInputMonitor *)userData;
    if (monitor == nil || audioQueue != monitor.audioQueue)
    {
        return;
    }

    [monitor processBuffer:buffer];

    if (monitor.isMonitoring && monitor.audioQueue == audioQueue)
    {
        AudioQueueEnqueueBuffer(audioQueue, buffer, 0, NULL);
    }
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _lastErrorMessage = @"";
        _audioFormat = [self defaultAudioFormat];
    }
    return self;
}

- (AVAuthorizationStatus)microphoneAuthorizationStatus
{
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
}

- (void)requestMicrophoneAccessWithCompletion:(void (^)(BOOL granted))completion
{
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted)
    {
        if (completion == nil)
        {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^
        {
            completion(granted);
        });
    }];
}

- (BOOL)startMonitoring
{
    if (self.isMonitoring)
    {
        return YES;
    }

    AVAuthorizationStatus authorizationStatus = [self microphoneAuthorizationStatus];
    if (authorizationStatus != AVAuthorizationStatusAuthorized)
    {
        self.lastErrorMessage = @"Microphone access needed.";
        return NO;
    }

    self.lastErrorMessage = @"";
    self.audioFormat = [self defaultAudioFormat];

    AudioQueueRef queue = NULL;
    OSStatus status = AudioQueueNewInput(&_audioFormat,
                                         MLAudioInputQueueCallback,
                                         (__bridge void *)self,
                                         NULL,
                                         NULL,
                                         0,
                                         &queue);
    if (status != noErr)
    {
        [self failWithStatus:status];
        return NO;
    }

    self.audioQueue = queue;

    UInt32 bufferByteSize = MLAudioInputMonitorFramesPerBuffer * _audioFormat.mBytesPerFrame;
    for (UInt32 index = 0; index < MLAudioInputMonitorBufferCount; index++)
    {
        AudioQueueBufferRef buffer = NULL;
        status = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffer);
        if (status != noErr)
        {
            [self failWithStatus:status];
            [self stopMonitoring];
            return NO;
        }

        status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        if (status != noErr)
        {
            [self failWithStatus:status];
            [self stopMonitoring];
            return NO;
        }
    }

    self.monitoring = YES;
    status = AudioQueueStart(queue, NULL);
    if (status != noErr)
    {
        self.monitoring = NO;
        [self failWithStatus:status];
        [self stopMonitoring];
        return NO;
    }

    return YES;
}

- (void)stopMonitoring
{
    if (self.audioQueue == NULL)
    {
        self.monitoring = NO;
        return;
    }

    AudioQueueRef queue = self.audioQueue;
    self.monitoring = NO;

    // Stop synchronously before clearing the property: once AudioQueueStop
    // returns no more callbacks run, so nothing races the NULL write below.
    AudioQueueStop(queue, true);
    AudioQueueDispose(queue, true);
    self.audioQueue = NULL;
}

- (AudioStreamBasicDescription)defaultAudioFormat
{
    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = 44100.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = sizeof(Float32);
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(Float32);
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 8 * sizeof(Float32);
    return format;
}

- (void)processBuffer:(AudioQueueBufferRef)buffer
{
    if (buffer == NULL || buffer->mAudioDataByteSize == 0)
    {
        return;
    }

    UInt32 sampleCount = buffer->mAudioDataByteSize / sizeof(Float32);
    if (sampleCount == 0)
    {
        return;
    }

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastLevelDispatchTime < 0.05)
    {
        return;
    }
    self.lastLevelDispatchTime = now;

    Float32 *samples = (Float32 *)buffer->mAudioData;
    double sumSquares = 0.0;
    for (UInt32 index = 0; index < sampleCount; index++)
    {
        Float32 sample = samples[index];
        sumSquares += (double)sample * (double)sample;
    }

    double rms = sqrt(sumSquares / (double)sampleCount);
    Float32 decibels = 20.0f * log10f((Float32)MAX(rms, 0.0000001));
    CGFloat meterLevel = (CGFloat)MIN(1.0, MAX(0.0, ((double)decibels + 55.0) / 45.0));

    dispatch_async(dispatch_get_main_queue(), ^
    {
        [self.delegate audioInputMonitor:self didUpdateLevel:meterLevel decibels:decibels];
    });
}

- (void)failWithStatus:(OSStatus)status
{
    NSString *message = MLAudioInputMonitorStatusMessage(status);
    self.lastErrorMessage = message;

    dispatch_async(dispatch_get_main_queue(), ^
    {
        [self.delegate audioInputMonitor:self didFailWithMessage:message];
    });
}

- (void)dealloc
{
    [self stopMonitoring];
}

@end
