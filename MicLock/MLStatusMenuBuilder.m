#import "MLStatusMenuBuilder.h"
#import "MLAudioDevice.h"
#import "MLFallbackSelection.h"
#import "MLInputSelectionResolver.h"
#import "MLMenuSelectionPayload.h"
#import "MLPreferencesStore.h"

@implementation MLStatusMenuBuildResult

+ (instancetype)resultWithMenu:(NSMenu *)menu startupItem:(NSMenuItem *)startupItem
{
    return [[self alloc] initWithMenu:menu startupItem:startupItem];
}

- (instancetype)initWithMenu:(NSMenu *)menu startupItem:(NSMenuItem *)startupItem
{
    self = [super init];
    if (self)
    {
        _menu = menu;
        _startupItem = startupItem;
    }

    return self;
}

@end

@implementation MLStatusMenuBuilder

+ (MLStatusMenuBuildResult *)menuWithDevices:(NSArray<MLAudioDevice *> *)devices
                       currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
                                activeDevice:(MLAudioDevice *)activeDevice
                           activeSourceTitle:(NSString *)activeSourceTitle
                           preferredInputUID:(NSString *)preferredInputUID
                          fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                                      paused:(BOOL)paused
                     preferredInputAvailable:(BOOL)preferredInputAvailable
                       didApplyResolvedInput:(BOOL)didApplyResolvedInput
                                      target:(id<MLStatusMenuActionHandling>)target
                                    delegate:(id<NSMenuDelegate>)delegate
{
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *shortVersion = bundleInfo[@"CFBundleShortVersionString"] ?: @"";
    NSString *buildVersion = bundleInfo[@"CFBundleVersion"] ?: @"";
    NSString *versionString = [NSString stringWithFormat:@"Version %@ (build %@)", shortVersion, buildVersion];

    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = delegate;

    NSMenuItem *versionItem = [menu addItemWithTitle:versionString action:nil keyEquivalent:@""];
    versionItem.enabled = NO;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *pauseItem = [menu addItemWithTitle:NSLocalizedString(@"Pause", @"Pause")
                                            action:@selector(manualPause:)
                                     keyEquivalent:@""];
    pauseItem.target = target;
    pauseItem.state = paused ? NSControlStateValueOn : NSControlStateValueOff;

    [menu addItem:[NSMenuItem separatorItem]];

    NSString *activeDeviceTitle = activeDevice != nil ? activeDevice.displayName : @"No input device available";
    NSMenuItem *currentInputItem = [menu addItemWithTitle:[NSString stringWithFormat:@"Current input: %@", activeDeviceTitle]
                                                   action:nil
                                            keyEquivalent:@""];
    currentInputItem.enabled = NO;

    NSMenuItem *sourceItem = [menu addItemWithTitle:[NSString stringWithFormat:@"Source: %@", activeSourceTitle ?: @"Unavailable"]
                                             action:nil
                                      keyEquivalent:@""];
    sourceItem.enabled = NO;

    if (paused)
    {
        NSMenuItem *pausedItem = [menu addItemWithTitle:@"Monitoring is paused"
                                                 action:nil
                                          keyEquivalent:@""];
        pausedItem.enabled = NO;
    }
    else if (didApplyResolvedInput)
    {
        NSMenuItem *appliedItem = [menu addItemWithTitle:@"Applied selected input device"
                                                  action:nil
                                           keyEquivalent:@""];
        appliedItem.enabled = NO;
    }

    if (preferredInputUID.length > 0 && !preferredInputAvailable)
    {
        NSMenuItem *fallbackItem = [menu addItemWithTitle:@"Primary input unavailable, fallback chain is active"
                                                   action:nil
                                            keyEquivalent:@""];
        fallbackItem.enabled = NO;
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *selectionHeader = [menu addItemWithTitle:@"Input Selection"
                                                  action:nil
                                           keyEquivalent:@""];
    selectionHeader.enabled = NO;

    NSString *primarySummary = [self selectionSummaryForUID:preferredInputUID
                                                  inDevices:devices
                                                 emptyTitle:@"Not set"
                                           unavailableTitle:@"Unavailable"];
    NSMenuItem *primaryItem = [menu addItemWithTitle:[NSString stringWithFormat:@"Primary: %@", primarySummary]
                                              action:nil
                                       keyEquivalent:@""];
    primaryItem.submenu = [self selectionMenuForDevices:devices
                                            selectedUID:preferredInputUID
                                                action:@selector(primaryDeviceSelected:)
                                                  slot:NSNotFound
                                 includeDisabledOption:NO
                                  currentDefaultInputID:currentDefaultInputID
                                                target:target];

    for (NSUInteger slot = 0; slot < MLFallbackSelectionSlotCount; slot++)
    {
        MLFallbackSelection *fallbackSelection = slot < fallbackSelections.count ? fallbackSelections[slot] : [MLFallbackSelection emptySelection];
        NSString *fallbackTitle = [NSString stringWithFormat:@"Fallback %lu: %@",
                                   (unsigned long)(slot + 1),
                                   [self selectionSummaryForFallbackSelection:fallbackSelection
                                                                    inDevices:devices
                                                                   emptyTitle:@"Disabled"
                                                             unavailableTitle:@"Unavailable"]];

        NSMenuItem *fallbackItem = [menu addItemWithTitle:fallbackTitle
                                                   action:nil
                                            keyEquivalent:@""];
        fallbackItem.submenu = [self selectionMenuForDevices:devices
                                                 selectedUID:fallbackSelection.uid
                                                      action:@selector(fallbackDeviceSelected:)
                                                        slot:slot
                                       includeDisabledOption:YES
                                       currentDefaultInputID:currentDefaultInputID
                                                      target:target];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *startupItem = [menu addItemWithTitle:@"Open at login"
                                              action:@selector(toggleStartupItem)
                                       keyEquivalent:@""];
    startupItem.target = target;

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [menu addItemWithTitle:@"Quit"
                                           action:@selector(terminate)
                                    keyEquivalent:@""];
    quitItem.target = target;

    return [MLStatusMenuBuildResult resultWithMenu:menu startupItem:startupItem];
}

+ (NSMenu *)selectionMenuForDevices:(NSArray<MLAudioDevice *> *)devices
                        selectedUID:(NSString *)selectedUID
                             action:(SEL)action
                               slot:(NSUInteger)slot
              includeDisabledOption:(BOOL)includeDisabledOption
               currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
                             target:(id)target
{
    NSMenu *submenu = [[NSMenu alloc] init];

    if (includeDisabledOption)
    {
        NSMenuItem *disabledItem = [submenu addItemWithTitle:@"Disabled"
                                                      action:@selector(clearFallbackDevice:)
                                               keyEquivalent:@""];
        disabledItem.target = target;
        disabledItem.representedObject = [MLMenuSelectionPayload payloadWithDevice:nil slot:slot];
        disabledItem.state = selectedUID.length == 0 ? NSControlStateValueOn : NSControlStateValueOff;

        [submenu addItem:[NSMenuItem separatorItem]];
    }

    for (MLAudioDevice *device in devices)
    {
        NSMenuItem *deviceItem = [submenu addItemWithTitle:device.displayName
                                                    action:action
                                             keyEquivalent:@""];
        deviceItem.target = target;

        if (slot == NSNotFound)
        {
            deviceItem.representedObject = device;
        }
        else
        {
            deviceItem.representedObject = [MLMenuSelectionPayload payloadWithDevice:device slot:slot];
        }

        deviceItem.state = [device.uid isEqualToString:selectedUID] ? NSControlStateValueOn : NSControlStateValueOff;

        if (device.deviceID == currentDefaultInputID)
        {
            deviceItem.toolTip = @"Currently selected by macOS.";
        }
    }

    return submenu;
}

+ (NSString *)selectionSummaryForFallbackSelection:(MLFallbackSelection *)selection
                                         inDevices:(NSArray<MLAudioDevice *> *)devices
                                        emptyTitle:(NSString *)emptyTitle
                                  unavailableTitle:(NSString *)unavailableTitle
{
    if (selection.uid.length == 0)
    {
        return emptyTitle;
    }

    MLAudioDevice *device = [MLInputSelectionResolver deviceWithUID:selection.uid inDevices:devices];
    if (device != nil)
    {
        return device.displayName;
    }

    if (selection.displayName.length > 0)
    {
        return [NSString stringWithFormat:@"%@ - %@", selection.displayName, unavailableTitle];
    }

    return unavailableTitle;
}

+ (NSString *)selectionSummaryForUID:(NSString *)uid
                           inDevices:(NSArray<MLAudioDevice *> *)devices
                          emptyTitle:(NSString *)emptyTitle
                    unavailableTitle:(NSString *)unavailableTitle
{
    if (uid.length == 0)
    {
        return emptyTitle;
    }

    MLAudioDevice *device = [MLInputSelectionResolver deviceWithUID:uid inDevices:devices];
    if (device != nil)
    {
        return device.displayName;
    }

    return unavailableTitle;
}

@end
