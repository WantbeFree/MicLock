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
                           preferredInputUID:(NSString *)preferredInputUID
                    preferredInputDisplayName:(NSString *)preferredInputDisplayName
                          fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                                      paused:(BOOL)paused
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

    [self addSavedInputsSectionToMenu:menu
                               devices:devices
                  currentDefaultInputID:currentDefaultInputID
                     preferredInputUID:preferredInputUID
              preferredInputDisplayName:preferredInputDisplayName
                    fallbackSelections:fallbackSelections
                                target:target];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refreshItem = [menu addItemWithTitle:@"Refresh Devices"
                                              action:@selector(refreshAudioDevices:)
                                       keyEquivalent:@""];
    refreshItem.target = target;
    refreshItem.toolTip = @"Rescan CoreAudio input devices without changing your selections.";

    NSMenuItem *reviveItem = [menu addItemWithTitle:@"Revive Audio..."
                                             action:@selector(reviveAudio:)
                                      keyEquivalent:@""];
    reviveItem.target = target;
    reviveItem.toolTip = @"Restart CoreAudio with administrator approval, then rescan devices.";

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

+ (void)addSavedInputsSectionToMenu:(NSMenu *)menu
                             devices:(NSArray<MLAudioDevice *> *)devices
                currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
                   preferredInputUID:(NSString *)preferredInputUID
            preferredInputDisplayName:(NSString *)preferredInputDisplayName
                  fallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
                              target:(id<MLStatusMenuActionHandling>)target
{
    NSMenuItem *savedHeader = [menu addItemWithTitle:@"Saved Inputs"
                                             action:nil
                                      keyEquivalent:@""];
    savedHeader.enabled = NO;

    NSUInteger savedInputCount = 0;
    if (preferredInputUID.length > 0)
    {
        [self addSavedInputItemToMenu:menu
                            roleTitle:@"Primary"
                                  uid:preferredInputUID
                   storedDisplayName:preferredInputDisplayName
                              devices:devices
                 currentDefaultInputID:currentDefaultInputID
                                target:target];
        savedInputCount += 1;
    }

    for (NSUInteger slot = 0; slot < fallbackSelections.count; slot++)
    {
        MLFallbackSelection *fallbackSelection = fallbackSelections[slot];
        if (fallbackSelection.uid.length == 0)
        {
            continue;
        }

        NSString *roleTitle = [NSString stringWithFormat:@"Fallback %lu", (unsigned long)(slot + 1)];
        [self addSavedInputItemToMenu:menu
                            roleTitle:roleTitle
                                  uid:fallbackSelection.uid
                   storedDisplayName:fallbackSelection.displayName
                              devices:devices
                 currentDefaultInputID:currentDefaultInputID
                                target:target];
        savedInputCount += 1;
    }

    if (savedInputCount == 0)
    {
        NSMenuItem *emptyItem = [menu addItemWithTitle:@"No saved inputs yet"
                                                action:nil
                                         keyEquivalent:@""];
        emptyItem.enabled = NO;
    }
}

+ (void)addSavedInputItemToMenu:(NSMenu *)menu
                      roleTitle:(NSString *)roleTitle
                            uid:(NSString *)uid
             storedDisplayName:(NSString *)storedDisplayName
                        devices:(NSArray<MLAudioDevice *> *)devices
           currentDefaultInputID:(AudioDeviceID)currentDefaultInputID
                          target:(id<MLStatusMenuActionHandling>)target
{
    MLAudioDevice *device = [MLInputSelectionResolver deviceWithUID:uid inDevices:devices];
    BOOL available = (device != nil);
    NSString *displayName = available ? device.displayName : storedDisplayName;
    if (displayName.length == 0)
    {
        displayName = @"Unavailable";
    }

    NSString *availabilitySuffix = (!available && storedDisplayName.length > 0) ? @" - Unavailable" : @"";
    NSString *title = [NSString stringWithFormat:@"%@: %@%@", roleTitle, displayName, availabilitySuffix];
    NSMenuItem *item = [menu addItemWithTitle:title
                                       action:(available ? @selector(savedInputSelected:) : nil)
                                keyEquivalent:@""];
    item.enabled = available;
    item.target = available ? target : nil;
    item.representedObject = device;

    if (available && device.deviceID == currentDefaultInputID)
    {
        item.state = NSControlStateValueOn;
    }

    item.toolTip = available ? @"Click to use this saved input now." : @"This saved input is not currently visible to CoreAudio.";
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
