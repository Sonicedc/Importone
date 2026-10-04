#import "ImportActivity.h"
#import "Shared/Bridge.h"
%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    NSMutableArray *result = [activities mutableCopy] ?: [NSMutableArray new];
    if (IPEnabled()) [result addObject:[IPImportActivity new]];
    return %orig(items, result);
}
%end
