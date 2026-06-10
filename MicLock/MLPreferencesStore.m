#import "MLPreferencesStore.h"
#import "MLFallbackSelection.h"

NSUInteger const MLFallbackSelectionSlotCount = 3;

static NSString * const MLPausedDefaultsKey = @"paused";
static NSString * const MLPreferredInputUIDDefaultsKey = @"preferredInputUID";
static NSString * const MLPreferredInputDisplayNameDefaultsKey = @"preferredInputDisplayName";
static NSString * const MLFallbackInputUIDsDefaultsKey = @"fallbackInputUIDs";
static NSString * const MLLegacyDefaultsSuiteName = @"com.milgra.asqf";

@interface MLPreferencesStore ()

@property (nonatomic, strong) NSUserDefaults *defaults;

@end

@implementation MLPreferencesStore

- (instancetype)initWithUserDefaults:(NSUserDefaults *)defaults
{
    self = [super init];
    if (self != nil)
    {
        _defaults = defaults ?: [NSUserDefaults standardUserDefaults];
        [self migrateLegacyDefaultsIfNeeded];
    }
    return self;
}

- (BOOL)paused
{
    return [self.defaults boolForKey:MLPausedDefaultsKey];
}

- (void)setPaused:(BOOL)paused
{
    [self.defaults setBool:paused forKey:MLPausedDefaultsKey];
}

- (NSString *)preferredInputUID
{
    return [self.defaults stringForKey:MLPreferredInputUIDDefaultsKey];
}

- (void)setPreferredInputUID:(NSString *)uid
{
    if (uid.length > 0)
    {
        [self.defaults setObject:uid forKey:MLPreferredInputUIDDefaultsKey];
    }
    else
    {
        [self.defaults removeObjectForKey:MLPreferredInputUIDDefaultsKey];
    }
}

- (NSString *)preferredInputDisplayName
{
    return [self.defaults stringForKey:MLPreferredInputDisplayNameDefaultsKey];
}

- (void)setPreferredInputDisplayName:(NSString *)displayName
{
    if (displayName.length > 0)
    {
        [self.defaults setObject:displayName forKey:MLPreferredInputDisplayNameDefaultsKey];
    }
    else
    {
        [self.defaults removeObjectForKey:MLPreferredInputDisplayNameDefaultsKey];
    }
}

- (NSArray<MLFallbackSelection *> *)fallbackSelections
{
    return [self normalizedFallbackSelectionsFromValue:[self.defaults objectForKey:MLFallbackInputUIDsDefaultsKey]];
}

- (void)saveFallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections
{
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *storedSelections = [NSMutableArray arrayWithCapacity:MLFallbackSelectionSlotCount];
    NSArray<MLFallbackSelection *> *normalizedSelections = [self normalizedFallbackSelectionsFromValue:fallbackSelections];
    for (MLFallbackSelection *selection in normalizedSelections)
    {
        [storedSelections addObject:[selection dictionaryRepresentation]];
    }
    [self.defaults setObject:storedSelections forKey:MLFallbackInputUIDsDefaultsKey];
}

- (NSArray<MLFallbackSelection *> *)normalizedFallbackSelectionsFromValue:(id)value
{
    NSMutableArray<MLFallbackSelection *> *selections = [NSMutableArray arrayWithCapacity:MLFallbackSelectionSlotCount];
    if ([value isKindOfClass:[NSArray class]])
    {
        for (id entry in (NSArray *)value)
        {
            [selections addObject:[MLFallbackSelection selectionFromStoredValue:entry]];
        }
    }

    while (selections.count < MLFallbackSelectionSlotCount)
    {
        [selections addObject:[MLFallbackSelection emptySelection]];
    }

    if (selections.count > MLFallbackSelectionSlotCount)
    {
        [selections removeObjectsInRange:NSMakeRange(MLFallbackSelectionSlotCount, selections.count - MLFallbackSelectionSlotCount)];
    }

    return [selections copy];
}

- (void)migrateLegacyDefaultsIfNeeded
{
    NSUserDefaults *legacyDefaults = [[NSUserDefaults alloc] initWithSuiteName:MLLegacyDefaultsSuiteName];
    if (legacyDefaults == nil)
    {
        return;
    }

    [self copyLegacyObjectForKey:MLPausedDefaultsKey fromDefaults:legacyDefaults];
    [self copyLegacyObjectForKey:MLPreferredInputUIDDefaultsKey fromDefaults:legacyDefaults];
    [self copyLegacyObjectForKey:MLPreferredInputDisplayNameDefaultsKey fromDefaults:legacyDefaults];
    [self copyLegacyObjectForKey:MLFallbackInputUIDsDefaultsKey fromDefaults:legacyDefaults];
}

- (void)copyLegacyObjectForKey:(NSString *)key fromDefaults:(NSUserDefaults *)legacyDefaults
{
    if ([self.defaults objectForKey:key] != nil)
    {
        return;
    }

    id legacyValue = [legacyDefaults objectForKey:key];
    if (legacyValue != nil)
    {
        [self.defaults setObject:legacyValue forKey:key];
    }
}

@end
