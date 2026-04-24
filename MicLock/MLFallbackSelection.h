#import <Foundation/Foundation.h>

@interface MLFallbackSelection : NSObject

@property (nonatomic, copy, readonly) NSString *uid;
@property (nonatomic, copy, readonly) NSString *displayName;

+ (instancetype)selectionWithUID:(NSString *)uid displayName:(NSString *)displayName;
+ (instancetype)emptySelection;
+ (instancetype)selectionFromStoredValue:(id)value;

- (instancetype)initWithUID:(NSString *)uid displayName:(NSString *)displayName NS_DESIGNATED_INITIALIZER;
- (NSDictionary<NSString *, NSString *> *)dictionaryRepresentation;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end
