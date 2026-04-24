#import <Foundation/Foundation.h>

@class MLAudioDevice;

@interface MLMenuSelectionPayload : NSObject

@property (nonatomic, strong, readonly) MLAudioDevice *device;
@property (nonatomic, assign, readonly) NSUInteger slot;

+ (instancetype)payloadWithDevice:(MLAudioDevice *)device slot:(NSUInteger)slot;
- (instancetype)initWithDevice:(MLAudioDevice *)device slot:(NSUInteger)slot NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end
