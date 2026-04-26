#import "MLCoreAudioReviver.h"

static NSString * const MLCoreAudioRestartScript = @"do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges";

@implementation MLCoreAudioReviver

- (void)restartCoreAudioWithCompletion:(MLCoreAudioReviveCompletion)completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^
    {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
        task.arguments = @[@"-e", MLCoreAudioRestartScript];

        NSPipe *outputPipe = [NSPipe pipe];
        task.standardOutput = outputPipe;
        task.standardError = outputPipe;

        NSError *launchError = nil;
        BOOL launched = [task launchAndReturnError:&launchError];
        if (!launched)
        {
            [self complete:completion success:NO message:launchError.localizedDescription ?: @"Unable to start CoreAudio restart task."];
            return;
        }

        [task waitUntilExit];

        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";
        NSString *trimmedOutput = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        BOOL success = (task.terminationStatus == 0);
        NSString *message = trimmedOutput.length > 0 ? trimmedOutput : (success ? @"CoreAudio restarted." : @"CoreAudio restart failed.");
        [self complete:completion success:success message:message];
    });
}

- (void)complete:(MLCoreAudioReviveCompletion)completion
         success:(BOOL)success
         message:(NSString *)message
{
    if (completion == nil)
    {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^
    {
        completion(success, message);
    });
}

@end
