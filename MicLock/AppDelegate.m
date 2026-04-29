#import "AppDelegate.h"
#import "GBLaunchAtLogin.h"
#import "MLAudioDevice.h"
#import "MLAudioDeviceService.h"
#import "MLCoreAudioReviver.h"
#import "MLFallbackSelection.h"
#import "MLInputSelectionResolver.h"
#import "MLMenuSelectionPayload.h"
#import "MLPreferencesStore.h"
#import "MLStatusMenuBuilder.h"
#import <UserNotifications/UserNotifications.h>

static NSTimeInterval const kAudioRefreshDebounceInterval = 0.15;
static NSTimeInterval const kWakeRefreshInitialDelay = 1.0;
static NSTimeInterval const kWakeRefreshFollowUpDelay = 5.0;
static NSTimeInterval const kUnavailableNotificationMinimumInterval = 300.0;

@interface MLAudioRefreshResult : NSObject

@property (nonatomic, copy, readonly) NSArray<MLAudioDevice *> *devices;
@property (nonatomic, copy, readonly) NSString *preferredInputUID;
@property (nonatomic, copy, readonly) NSArray<MLFallbackSelection *> *fallbackSelections;
@property (nonatomic, strong, readonly) MLInputResolution *resolution;
@property (nonatomic, assign, readonly) AudioDeviceID currentDefaultInputID;

+ (instancetype)resultWithDevices:(NSArray<MLAudioDevice *> *)devices
                 preferredInputUID:(NSString *)preferredInputUID
                fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                         resolution:(MLInputResolution *)resolution
              currentDefaultInputID:(AudioDeviceID)currentDefaultInputID;

- (instancetype)initWithDevices:(NSArray<MLAudioDevice *> *)devices
               preferredInputUID:(NSString *)preferredInputUID
              fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                       resolution:(MLInputResolution *)resolution
            currentDefaultInputID:(AudioDeviceID)currentDefaultInputID NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@implementation MLAudioRefreshResult

+ (instancetype)resultWithDevices:(NSArray<MLAudioDevice *> *)devices
                 preferredInputUID:(NSString *)preferredInputUID
                fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                         resolution:(MLInputResolution *)resolution
              currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
{
    return [[self alloc] initWithDevices:devices
                       preferredInputUID:preferredInputUID
                      fallbackSelections:fallbackSelections
                               resolution:resolution
                    currentDefaultInputID:currentDefaultInputID];
}

- (instancetype)initWithDevices:(NSArray<MLAudioDevice *> *)devices
               preferredInputUID:(NSString *)preferredInputUID
              fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                       resolution:(MLInputResolution *)resolution
            currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
{
    self = [super init];
    if (self)
    {
        _devices = [devices copy] ?: @[];
        _preferredInputUID = [preferredInputUID copy] ?: @"";
        _fallbackSelections = [fallbackSelections copy] ?: @[];
        _resolution = resolution;
        _currentDefaultInputID = currentDefaultInputID;
    }

    return self;
}

@end

@interface AppDelegate () <MLStatusMenuActionHandling>

@property (weak) IBOutlet NSWindow *window;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) BOOL refreshInProgress;
@property (nonatomic, assign) NSUInteger refreshRequestGeneration;
@property (nonatomic, strong) dispatch_queue_t refreshQueue;
@property (nonatomic, copy) NSString *preferredInputUID;
@property (nonatomic, copy) NSString *preferredInputDisplayName;
@property (nonatomic, copy) NSString *manualOverrideInputUID;
@property (nonatomic, copy) NSArray<MLFallbackSelection *> *fallbackSelections;
@property (nonatomic, strong) MLPreferencesStore *preferencesStore;
@property (nonatomic, strong) MLAudioDeviceService *audioDeviceService;
@property (nonatomic, strong) MLCoreAudioReviver *coreAudioReviver;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *startupItem;
@property (nonatomic, copy) NSString *lastPreferredInputDisplayName;
@property (nonatomic, strong) NSDate *lastUnavailableNotificationDate;
@property (nonatomic, assign) BOOL hasObservedPreferredInputAvailability;
@property (nonatomic, assign) BOOL lastPreferredInputAvailable;
@property (nonatomic, assign) BOOL reviveInProgress;
@property (nonatomic, assign) BOOL reopenMenuAfterRefresh;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    (void)aNotification;

    self.preferencesStore = [[MLPreferencesStore alloc] initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
    self.paused = [self.preferencesStore paused];
    self.preferredInputUID = [self.preferencesStore preferredInputUID];
    self.preferredInputDisplayName = [self.preferencesStore preferredInputDisplayName];
    self.fallbackSelections = [self.preferencesStore fallbackSelections];
    self.refreshQueue = dispatch_queue_create("com.miclock.audio-refresh", DISPATCH_QUEUE_SERIAL);
    self.audioDeviceService = [[MLAudioDeviceService alloc] init];
    self.coreAudioReviver = [[MLCoreAudioReviver alloc] init];

    [self setupStatusItem];

    __weak typeof(self) weakSelf = self;
    [self.audioDeviceService startMonitoringWithChangeHandler:^
    {
        [weakSelf scheduleAudioStateRefresh];
    }];

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(systemDidWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];

    [self refreshAudioStateAndMenu];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [self.audioDeviceService stopMonitoring];
}

- (void)setupStatusItem
{
    NSImage *image = nil;
    NSURL *vectorIconURL = [[NSBundle mainBundle] URLForResource:@"microphone" withExtension:@"svg"];
    if (vectorIconURL != nil)
    {
        image = [[NSImage alloc] initWithContentsOfURL:vectorIconURL];
        [image setSize:NSMakeSize(18.0, 18.0)];
    }

    if (image != nil)
    {
        [image setTemplate:YES];
    }
    else
    {
        NSImageSymbolConfiguration *symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                                          weight:NSFontWeightSemibold
                                                                                                           scale:NSImageSymbolScaleMedium];
        image = [NSImage imageWithSystemSymbolName:@"mic.fill"
                           accessibilityDescription:@"Microphone"];
        if (image != nil)
        {
            image = [image imageWithSymbolConfiguration:symbolConfiguration];
            [image setTemplate:YES];
        }
    }

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.toolTip = @"MicLock";
    self.statusItem.button.image = image;
    self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;
}

- (void)scheduleAudioStateRefresh
{
    self.refreshRequestGeneration += 1;

    NSUInteger generation = self.refreshRequestGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAudioRefreshDebounceInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^
    {
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil || generation != strongSelf.refreshRequestGeneration)
        {
            return;
        }

        [strongSelf refreshAudioStateAndMenu];
    });
}

- (void)invalidatePendingAudioRefreshResults
{
    self.refreshRequestGeneration += 1;
}

- (void)refreshAudioStateAndMenu
{
    if (self.refreshInProgress)
    {
        [self scheduleAudioStateRefresh];
        return;
    }

    self.refreshInProgress = YES;

    NSUInteger generation = self.refreshRequestGeneration;
    BOOL paused = self.paused;
    NSString *preferredInputUID = [self.preferredInputUID copy] ?: @"";
    NSString *manualOverrideInputUID = [self.manualOverrideInputUID copy] ?: @"";
    NSArray<MLFallbackSelection *> *fallbackSelections = [[self.preferencesStore normalizedFallbackSelectionsFromValue:self.fallbackSelections] copy];
    MLAudioDeviceService *audioDeviceService = self.audioDeviceService;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.refreshQueue, ^
    {
        AppDelegate *workerSelf = weakSelf;
        if (workerSelf == nil)
        {
            return;
        }

        NSArray<MLAudioDevice *> *devices = [audioDeviceService availableInputDevices];
        AudioDeviceID currentDefaultInputID = [audioDeviceService currentDefaultInputDevice];

        NSString *resolvedPreferredInputUID = [workerSelf preferredInputUIDByEnsuringSelection:preferredInputUID
                                                                                   withDevices:devices
                                                                                currentDefault:currentDefaultInputID];
        NSArray<MLFallbackSelection *> *resolvedFallbackSelections = [workerSelf fallbackSelectionsBySynchronizingSelections:fallbackSelections
                                                                                                                 withDevices:devices];

        MLAudioDevice *manualOverrideDevice = [MLInputSelectionResolver deviceWithUID:manualOverrideInputUID
                                                                            inDevices:devices];
        MLInputResolution *resolution = nil;
        if (manualOverrideDevice != nil)
        {
            BOOL preferredInputAvailable = (resolvedPreferredInputUID.length == 0 ||
                                            [MLInputSelectionResolver deviceWithUID:resolvedPreferredInputUID
                                                                         inDevices:devices] != nil);
            resolution = [MLInputResolution resolutionWithDevice:manualOverrideDevice
                                         preferredInputAvailable:preferredInputAvailable];
        }
        else
        {
            resolution = [MLInputSelectionResolver resolutionFromDevices:devices
                                                          currentDefault:currentDefaultInputID
                                                       preferredInputUID:resolvedPreferredInputUID
                                                      fallbackSelections:resolvedFallbackSelections];
        }

        MLAudioDevice *resolvedDevice = resolution.device;
        AudioDeviceID resolvedInputID = resolvedDevice != nil ? resolvedDevice.deviceID : kAudioDeviceUnknown;

        BOOL didApplyDefaultInput = NO;
        if (!paused &&
            resolvedInputID != kAudioDeviceUnknown &&
            currentDefaultInputID != resolvedInputID)
        {
            didApplyDefaultInput = [audioDeviceService setDefaultInputDevice:resolvedInputID];
            if (didApplyDefaultInput)
            {
                currentDefaultInputID = resolvedInputID;
            }
        }

        MLAudioRefreshResult *result = [MLAudioRefreshResult resultWithDevices:devices
                                                             preferredInputUID:resolvedPreferredInputUID
                                                            fallbackSelections:resolvedFallbackSelections
                                                                     resolution:resolution
                                                          currentDefaultInputID:currentDefaultInputID];

        dispatch_async(dispatch_get_main_queue(), ^
        {
            AppDelegate *strongSelf = weakSelf;
            if (strongSelf == nil)
            {
                return;
            }

            if (generation != strongSelf.refreshRequestGeneration)
            {
                strongSelf.refreshInProgress = NO;
                [strongSelf scheduleAudioStateRefresh];
                return;
            }

            [strongSelf applyAudioRefreshResult:result];
        });
    });
}

- (void)primaryDeviceSelected:(NSMenuItem *)item
{
    MLAudioDevice *device = item.representedObject;
    if (![device isKindOfClass:[MLAudioDevice class]] || device.uid.length == 0)
    {
        return;
    }

    [self invalidatePendingAudioRefreshResults];
    self.manualOverrideInputUID = nil;
    self.preferredInputUID = device.uid;
    self.preferredInputDisplayName = device.displayName;
    [self.preferencesStore setPreferredInputUID:device.uid];
    [self.preferencesStore setPreferredInputDisplayName:device.displayName];

    NSMutableArray<MLFallbackSelection *> *fallbacks = [[self.preferencesStore normalizedFallbackSelectionsFromValue:self.fallbackSelections] mutableCopy];
    for (NSUInteger slot = 0; slot < fallbacks.count; slot++)
    {
        if ([fallbacks[slot].uid isEqualToString:device.uid])
        {
            fallbacks[slot] = [MLFallbackSelection emptySelection];
        }
    }
    [self updateFallbackSelections:fallbacks];

    [self refreshAudioStateAndMenu];
}

- (void)fallbackDeviceSelected:(NSMenuItem *)item
{
    MLMenuSelectionPayload *payload = item.representedObject;
    if (![payload isKindOfClass:[MLMenuSelectionPayload class]] ||
        ![payload.device isKindOfClass:[MLAudioDevice class]])
    {
        return;
    }

    [self invalidatePendingAudioRefreshResults];
    self.manualOverrideInputUID = nil;
    [self setFallbackUID:payload.device.uid displayName:payload.device.displayName forSlot:payload.slot];
    [self refreshAudioStateAndMenu];
}

- (void)clearFallbackDevice:(NSMenuItem *)item
{
    MLMenuSelectionPayload *payload = item.representedObject;
    if (![payload isKindOfClass:[MLMenuSelectionPayload class]])
    {
        return;
    }

    [self invalidatePendingAudioRefreshResults];
    self.manualOverrideInputUID = nil;
    [self setFallbackUID:nil displayName:nil forSlot:payload.slot];
    [self refreshAudioStateAndMenu];
}

- (void)savedInputSelected:(NSMenuItem *)item
{
    MLAudioDevice *device = item.representedObject;
    if (![device isKindOfClass:[MLAudioDevice class]] || device.uid.length == 0)
    {
        return;
    }

    self.manualOverrideInputUID = device.uid;
    [self refreshAudioStateAndMenu];
}

- (void)manualPause:(NSMenuItem *)item
{
    (void)item;

    self.paused = !self.paused;
    [self.preferencesStore setPaused:self.paused];
    [self refreshAudioStateAndMenu];
}

- (void)terminate
{
    [NSApp terminate:nil];
}

- (void)toggleStartupItem
{
    GBLaunchAtLoginStatus status = [GBLaunchAtLogin status];

    if (status == GBLaunchAtLoginStatusEnabled)
    {
        [GBLaunchAtLogin removeAppFromLoginItems];
    }
    else
    {
        [GBLaunchAtLogin addAppAsLoginItem];
    }

    [self updateStartupItemState];

    if ([GBLaunchAtLogin status] == GBLaunchAtLoginStatusRequiresApproval)
    {
        [GBLaunchAtLogin openLoginItemsSettings];
    }
}

- (void)updateStartupItemState
{
    if (self.startupItem == nil)
    {
        return;
    }

    GBLaunchAtLoginStatus status = [GBLaunchAtLogin status];
    self.startupItem.title = @"Open at login";
    self.startupItem.toolTip = nil;

    switch (status)
    {
        case GBLaunchAtLoginStatusEnabled:
            self.startupItem.state = NSControlStateValueOn;
            break;

        case GBLaunchAtLoginStatusRequiresApproval:
            self.startupItem.state = NSControlStateValueMixed;
            self.startupItem.title = @"Open at login (approve in Settings)";
            self.startupItem.toolTip = @"Approve the app in System Settings > General > Login Items.";
            break;

        case GBLaunchAtLoginStatusDisabled:
        default:
            self.startupItem.state = NSControlStateValueOff;
            break;
    }
}

- (void)menuWillOpen:(NSMenu *)menu
{
    (void)menu;
    [self updateStartupItemState];
}

- (NSString *)preferredInputUIDByEnsuringSelection:(NSString *)preferredInputUID
                                       withDevices:(NSArray<MLAudioDevice *> *)devices
                                    currentDefault:(AudioDeviceID)currentDefaultInputID
{
    if (preferredInputUID.length > 0)
    {
        return preferredInputUID;
    }

    MLAudioDevice *initialDevice = [MLInputSelectionResolver initialPrimaryDeviceFromDevices:devices
                                                                             currentDefault:currentDefaultInputID];
    if (initialDevice.uid.length > 0)
    {
        return initialDevice.uid;
    }

    return @"";
}

- (void)setFallbackUID:(NSString *)uid
           displayName:(NSString *)displayName
               forSlot:(NSUInteger)slot
{
    if (slot >= MLFallbackSelectionSlotCount)
    {
        return;
    }

    NSMutableArray<MLFallbackSelection *> *selections = [[self.preferencesStore normalizedFallbackSelectionsFromValue:self.fallbackSelections] mutableCopy];

    if (uid.length > 0)
    {
        for (NSUInteger index = 0; index < selections.count; index++)
        {
            if (index != slot && [selections[index].uid isEqualToString:uid])
            {
                selections[index] = [MLFallbackSelection emptySelection];
            }
        }
        selections[slot] = [MLFallbackSelection selectionWithUID:uid displayName:displayName];
    }
    else
    {
        selections[slot] = [MLFallbackSelection emptySelection];
    }

    [self updateFallbackSelections:selections];
}

- (NSArray<MLFallbackSelection *> *)fallbackSelectionsBySynchronizingSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                                                                   withDevices:(NSArray<MLAudioDevice *> *)devices
{
    NSMutableArray<MLFallbackSelection *> *selections = [fallbackSelections mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger slot = 0; slot < selections.count; slot++)
    {
        MLFallbackSelection *selection = selections[slot];
        if (selection.uid.length == 0)
        {
            continue;
        }

        MLAudioDevice *device = [MLInputSelectionResolver deviceWithUID:selection.uid inDevices:devices];
        if (device == nil)
        {
            continue;
        }

        if (![selection.displayName isEqualToString:device.displayName ?: @""])
        {
            selections[slot] = [MLFallbackSelection selectionWithUID:selection.uid displayName:device.displayName];
        }
    }

    return [selections copy];
}

- (void)updateFallbackSelections:(NSArray<MLFallbackSelection *> *)selections
{
    self.fallbackSelections = [self.preferencesStore normalizedFallbackSelectionsFromValue:selections];
    [self.preferencesStore saveFallbackSelections:self.fallbackSelections];
}

- (void)applyAudioRefreshResult:(MLAudioRefreshResult *)result
{
    if (![(self.preferredInputUID ?: @"") isEqualToString:result.preferredInputUID])
    {
        self.preferredInputUID = result.preferredInputUID;
        [self.preferencesStore setPreferredInputUID:result.preferredInputUID];
    }

    if (![self.fallbackSelections isEqualToArray:result.fallbackSelections])
    {
        [self updateFallbackSelections:result.fallbackSelections];
    }

    MLAudioDevice *preferredDevice = [MLInputSelectionResolver deviceWithUID:self.preferredInputUID
                                                                   inDevices:result.devices];
    if (preferredDevice.displayName.length > 0 &&
        ![self.preferredInputDisplayName isEqualToString:preferredDevice.displayName])
    {
        self.preferredInputDisplayName = preferredDevice.displayName;
        [self.preferencesStore setPreferredInputDisplayName:preferredDevice.displayName];
    }

    if (self.manualOverrideInputUID.length > 0 &&
        [MLInputSelectionResolver deviceWithUID:self.manualOverrideInputUID inDevices:result.devices] == nil)
    {
        self.manualOverrideInputUID = nil;
    }

    [self updatePreferredInputAvailabilityFromResult:result];

    MLStatusMenuBuildResult *menuResult = [MLStatusMenuBuilder menuWithDevices:result.devices
                                                         currentDefaultInputID:result.currentDefaultInputID
                                                             preferredInputUID:self.preferredInputUID
                                                   preferredInputDisplayName:self.preferredInputDisplayName
                                                            fallbackSelections:self.fallbackSelections
                                                                        paused:self.paused
                                                                        target:self
                                                                      delegate:self];
    self.menu = menuResult.menu;
    self.startupItem = menuResult.startupItem;
    [self updateStartupItemState];
    [self.statusItem setMenu:self.menu];

    self.refreshInProgress = NO;
    if (self.reopenMenuAfterRefresh)
    {
        self.reopenMenuAfterRefresh = NO;
        [self reopenStatusMenuSoon];
    }
}

- (void)refreshAudioDevices:(NSMenuItem *)item
{
    (void)item;
    self.reopenMenuAfterRefresh = YES;
    [self scheduleAudioStateRefresh];
}

- (void)reviveAudio:(NSMenuItem *)item
{
    (void)item;

    if (self.reviveInProgress)
    {
        return;
    }

    self.reviveInProgress = YES;
    [self postNotificationWithTitle:@"MicLock"
                                body:@"Restarting CoreAudio. macOS may ask for administrator approval."];

    __weak typeof(self) weakSelf = self;
    [self.coreAudioReviver restartCoreAudioWithCompletion:^(BOOL success, NSString *message)
    {
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil)
        {
            return;
        }

        strongSelf.reviveInProgress = NO;
        if (success)
        {
            [strongSelf postNotificationWithTitle:@"MicLock"
                                             body:@"CoreAudio restarted. Refreshing input devices now."];
            strongSelf.reopenMenuAfterRefresh = YES;
            [strongSelf scheduleWakeRecoveryRefreshes];
            return;
        }

        if ([message localizedCaseInsensitiveContainsString:@"User canceled"])
        {
            return;
        }

        [strongSelf showReviveFailureAlertWithMessage:message];
    }];
}

- (void)systemDidWake:(NSNotification *)notification
{
    (void)notification;
    [self scheduleWakeRecoveryRefreshes];
}

- (void)scheduleWakeRecoveryRefreshes
{
    [self scheduleAudioStateRefreshAfterDelay:kWakeRefreshInitialDelay];
    [self scheduleAudioStateRefreshAfterDelay:kWakeRefreshFollowUpDelay];
}

- (void)reopenStatusMenuSoon
{
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^
    {
        AppDelegate *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.statusItem.button == nil || strongSelf.menu == nil)
        {
            return;
        }

        [strongSelf.statusItem.button performClick:nil];
    });
}

- (void)scheduleAudioStateRefreshAfterDelay:(NSTimeInterval)delay
{
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^
    {
        [weakSelf scheduleAudioStateRefresh];
    });
}

- (void)updatePreferredInputAvailabilityFromResult:(MLAudioRefreshResult *)result
{
    NSString *preferredInputUID = result.preferredInputUID ?: @"";
    BOOL hasPreferredInput = preferredInputUID.length > 0;
    BOOL preferredInputAvailable = !hasPreferredInput || result.resolution.preferredInputAvailable;

    if (hasPreferredInput && preferredInputAvailable)
    {
        MLAudioDevice *preferredDevice = [MLInputSelectionResolver deviceWithUID:preferredInputUID
                                                                       inDevices:result.devices];
        if (preferredDevice.displayName.length > 0)
        {
            self.lastPreferredInputDisplayName = preferredDevice.displayName;
        }
    }

    BOOL becameUnavailable = (hasPreferredInput &&
                              self.hasObservedPreferredInputAvailability &&
                              self.lastPreferredInputAvailable &&
                              !preferredInputAvailable);

    self.hasObservedPreferredInputAvailability = YES;
    self.lastPreferredInputAvailable = preferredInputAvailable;

    if (becameUnavailable && [self shouldPostUnavailableNotification])
    {
        NSString *deviceName = self.lastPreferredInputDisplayName.length > 0 ? self.lastPreferredInputDisplayName : @"Selected microphone";
        NSString *body = [NSString stringWithFormat:@"%@ disappeared from CoreAudio. Try Revive Audio; if it is missing from USB too, power-cycle the dock/KVM path.", deviceName];
        [self postNotificationWithTitle:@"MicLock lost the primary input" body:body];
    }
}

- (BOOL)shouldPostUnavailableNotification
{
    NSDate *now = [NSDate date];
    if (self.lastUnavailableNotificationDate != nil &&
        [now timeIntervalSinceDate:self.lastUnavailableNotificationDate] < kUnavailableNotificationMinimumInterval)
    {
        return NO;
    }

    self.lastUnavailableNotificationDate = now;
    return YES;
}

- (void)postNotificationWithTitle:(NSString *)title body:(NSString *)body
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings)
    {
        void (^deliverNotification)(void) = ^
        {
            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = title ?: @"MicLock";
            content.body = body ?: @"";

            NSString *identifier = [NSString stringWithFormat:@"com.miclock.notification.%@", [NSUUID UUID].UUIDString];
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                                  content:content
                                                                                  trigger:nil];
            [center addNotificationRequest:request withCompletionHandler:nil];
        };

        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
            settings.authorizationStatus == UNAuthorizationStatusProvisional)
        {
            deliverNotification();
            return;
        }

        if (settings.authorizationStatus != UNAuthorizationStatusNotDetermined)
        {
            return;
        }

        [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert
                              completionHandler:^(BOOL granted, NSError *error)
        {
            (void)error;
            if (granted)
            {
                deliverNotification();
            }
        }];
    }];
}

- (void)showReviveFailureAlertWithMessage:(NSString *)message
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"CoreAudio restart failed";
    alert.informativeText = message.length > 0 ? message : @"macOS did not allow MicLock to restart CoreAudio.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
