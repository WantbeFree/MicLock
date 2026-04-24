#import "MLFallbackSelection.h"

NSString * const MLFallbackSelectionUIDKey = @"uid";
NSString * const MLFallbackSelectionNameKey = @"displayName";

@implementation MLFallbackSelection

+ (instancetype)selectionWithUID:(NSString *)uid displayName:(NSString *)displayName
{
    return [[self alloc] initWithUID:uid displayName:displayName];
}

+ (instancetype)emptySelection
{
    return [self selectionWithUID:@"" displayName:@""];
}

+ (instancetype)selectionFromStoredValue:(id)value
{
    if ([value isKindOfClass:[NSDictionary class]])
    {
        NSDictionary *dictionary = (NSDictionary *)value;
        NSString *uid = [dictionary[MLFallbackSelectionUIDKey] isKindOfClass:[NSString class]] ? dictionary[MLFallbackSelectionUIDKey] : @"";
        NSString *displayName = [dictionary[MLFallbackSelectionNameKey] isKindOfClass:[NSString class]] ? dictionary[MLFallbackSelectionNameKey] : @"";
        return [self selectionWithUID:uid displayName:displayName];
    }

    if ([value isKindOfClass:[NSString class]])
    {
        return [self selectionWithUID:(NSString *)value displayName:@""];
    }

    return [self emptySelection];
}

- (instancetype)initWithUID:(NSString *)uid displayName:(NSString *)displayName
{
    self = [super init];
    if (self != nil)
    {
        _uid = [uid copy] ?: @"";
        _displayName = [displayName copy] ?: @"";
    }
    return self;
}

- (NSDictionary<NSString *, NSString *> *)dictionaryRepresentation
{
    return @{
        MLFallbackSelectionUIDKey: self.uid,
        MLFallbackSelectionNameKey: self.displayName
    };
}

- (BOOL)isEqual:(id)object
{
    if (self == object)
    {
        return YES;
    }

    if (![object isKindOfClass:[MLFallbackSelection class]])
    {
        return NO;
    }

    MLFallbackSelection *selection = object;
    return [self.uid isEqualToString:selection.uid] &&
           [self.displayName isEqualToString:selection.displayName];
}

- (NSUInteger)hash
{
    return self.uid.hash ^ self.displayName.hash;
}

@end
