#import <Foundation/Foundation.h>

typedef void (^MLCoreAudioReviveCompletion)(BOOL success, NSString *message);

@interface MLCoreAudioReviver : NSObject

- (void)restartCoreAudioWithCompletion:(MLCoreAudioReviveCompletion)completion;

@end
