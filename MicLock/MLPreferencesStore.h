#import <Foundation/Foundation.h>

@class MLFallbackSelection;

FOUNDATION_EXPORT NSUInteger const MLFallbackSelectionSlotCount;

@interface MLPreferencesStore : NSObject

- (instancetype)initWithUserDefaults:(NSUserDefaults *)defaults NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (BOOL)paused;
- (void)setPaused:(BOOL)paused;

- (NSString *)preferredInputUID;
- (void)setPreferredInputUID:(NSString *)uid;

- (NSString *)preferredInputDisplayName;
- (void)setPreferredInputDisplayName:(NSString *)displayName;

- (NSArray<MLFallbackSelection *> *)fallbackSelections;
- (void)saveFallbackSelections:(NSArray<MLFallbackSelection *> *)fallbackSelections;
- (NSArray<MLFallbackSelection *> *)normalizedFallbackSelectionsFromValue:(id)value;

@end
