#import "ImportActivity.h"
#import "Shared/Bridge.h"

static NSArray *IPActivities(NSArray *activities, NSArray *items) {
    NSMutableArray *result = [activities mutableCopy] ?: [NSMutableArray new];
    if (!IPEnabled()) return result;
    for (UIActivity *activity in result) if ([activity.activityType isEqual:@"com.sonicedc.importone.import"]) return result;
    IPImportActivity *activity = [IPImportActivity new];
    activity.providedItems = items;
    [result addObject:activity];
    return result;
}

@interface IPShareConfiguration : NSProxy <UIActivityItemsConfigurationReading>
@property (nonatomic, strong) id<UIActivityItemsConfigurationReading> original;
@end
@implementation IPShareConfiguration
- (NSArray<NSItemProvider *> *)itemProvidersForActivityItemsConfiguration {
    return self.original.itemProvidersForActivityItemsConfiguration;
}
- (NSArray<UIActivity *> *)applicationActivitiesForActivityItemsConfiguration {
    NSArray *existing = [self.original respondsToSelector:_cmd] ? self.original.applicationActivitiesForActivityItemsConfiguration : nil;
    return IPActivities(existing, self.itemProvidersForActivityItemsConfiguration);
}
- (BOOL)respondsToSelector:(SEL)selector {
    if (selector == @selector(applicationActivitiesForActivityItemsConfiguration) || selector == @selector(itemProvidersForActivityItemsConfiguration)) return YES;
    return [self.original respondsToSelector:selector];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector { return [(id)self.original methodSignatureForSelector:selector]; }
- (void)forwardInvocation:(NSInvocation *)invocation { [invocation invokeWithTarget:self.original]; }
@end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities {
    return %orig(items, IPActivities(activities, nil));
}
- (instancetype)initWithActivityItemsConfiguration:(id<UIActivityItemsConfigurationReading>)configuration {
    if (!IPEnabled() || !configuration) return %orig;
    IPShareConfiguration *proxy = [IPShareConfiguration alloc];
    proxy.original = configuration;
    return %orig(proxy);
}
%end
