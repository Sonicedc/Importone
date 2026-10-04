#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <rootless.h>
#import "Shared/Bridge.h"
@interface TLToneManager : NSObject
- (BOOL)toneWithIdentifierIsValid:(NSString *)identifier;
@end
@interface TKTonePickerController : NSObject
- (void)_invalidatePickerItemCaches;
- (TLToneManager *)_toneManager;
@end
static void IPRegroupTones(TKTonePickerController *picker) {
    if (!IPEnabled()) return;
    NSArray *catalog = [NSArray arrayWithContentsOfFile:ROOT_PATH_NS(@"/var/mobile/Library/Importone/CustomTones.plist")];
    if (![catalog isKindOfClass:NSArray.class]) return;
    NSMutableArray *identifiers = [NSMutableArray new];
    for (NSDictionary *tone in catalog) {
        if (![tone isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = tone[@"identifier"];
        if ([identifier isKindOfClass:NSString.class] && [[picker _toneManager] toneWithIdentifierIsValid:identifier]) [identifiers addObject:identifier];
    }
    if (!identifiers.count) return;
    NSArray *oldLists = [picker valueForKey:@"_toneGroupLists"];
    NSArray *oldNames = [picker valueForKey:@"_toneGroupNames"];
    NSArray *oldBuckets = [picker valueForKey:@"_toneGroupBucketIdentifiers"];
    if (![oldLists isKindOfClass:NSArray.class] || oldLists.count != oldNames.count || oldLists.count != oldBuckets.count) return;
    NSMutableArray *lists = [NSMutableArray new], *names = [NSMutableArray new], *buckets = [NSMutableArray new];
    [lists addObject:identifiers]; [names addObject:@"Custom Ringtones"]; [buckets addObject:@"importone.custom"];
    for (NSUInteger index = 0; index < oldLists.count; index++) {
        if ([oldBuckets[index] isEqual:@"importone.custom"]) continue;
        NSMutableArray *remaining = [oldLists[index] mutableCopy];
        [remaining removeObjectsInArray:identifiers];
        if (!remaining.count && [oldLists[index] count]) continue;
        [lists addObject:remaining]; [names addObject:oldNames[index]]; [buckets addObject:oldBuckets[index]];
    }
    [picker setValue:lists forKey:@"_toneGroupLists"];
    [picker setValue:names forKey:@"_toneGroupNames"];
    [picker setValue:buckets forKey:@"_toneGroupBucketIdentifiers"];
    [picker _invalidatePickerItemCaches];
}
%hook TKTonePickerController
- (void)_reloadTones { %orig; IPRegroupTones(self); }
%end
%ctor {
    dlopen("/System/Library/PrivateFrameworks/ToneKit.framework/ToneKit", RTLD_NOW);
    %init;
}
