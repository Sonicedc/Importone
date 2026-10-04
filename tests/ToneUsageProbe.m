// On-device native assignment/removal integration test. Never packaged.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "../Shared/Bridge.h"
#import "../Shared/ToneUsage.h"
@interface TLToneManager : NSObject
+ (instancetype)sharedToneManager;
- (NSString *)currentToneIdentifierForAlertType:(NSInteger)type;
- (void)setCurrentToneIdentifier:(NSString *)identifier forAlertType:(NSInteger)type;
@end
int main(void) { @autoreleasepool {
    dlopen("/System/Library/PrivateFrameworks/ToneLibrary.framework/ToneLibrary",RTLD_NOW);
    TLToneManager *manager = [NSClassFromString(@"TLToneManager") sharedToneManager];
    NSDictionary *list = [IPCenter() sendMessageAndReceiveReplyName:@"list" userInfo:@{}];
    NSString *identifier;
    for (NSDictionary *tone in list[@"tones"]) if ([tone[@"name"] isEqual:@"Importone Guard Check"]) identifier = tone[@"identifier"];
    if (!identifier) { puts("Disposable test tone missing"); return 1; }
    NSArray *types = @[@1,@2,@4,@5,@6,@10,@11];
    NSMutableArray *originals = [NSMutableArray new];
    for (NSNumber *type in types) [originals addObject:[manager currentToneIdentifierForAlertType:type.integerValue] ?: NSNull.null];
    NSInteger outcome = 0;
    @try {
        for (NSNumber *type in types) {
            NSInteger index = [types indexOfObject:type];
            [manager setCurrentToneIdentifier:identifier forAlertType:type.integerValue];
            if (![[manager currentToneIdentifierForAlertType:type.integerValue] isEqual:identifier]) { puts("Test assignment was not saved"); outcome = 2; break; }
            NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:@"remove" userInfo:@{@"identifier":identifier}];
            if ([reply[@"ok"] boolValue] || [reply[@"error"] rangeOfString:@"Select another ringtone"].location == NSNotFound) { printf("Deletion was not blocked for alert type %ld\n",(long)type.integerValue); outcome=3; break; }
            printf("PASS: native deletion blocked for alert type %ld.\n",(long)type.integerValue);
            id original = originals[index];
            [manager setCurrentToneIdentifier:original == NSNull.null ? nil : original forAlertType:type.integerValue];
        }
    } @finally {
        for (NSUInteger i=0;i<types.count;i++) {
            id original = originals[i];
            [manager setCurrentToneIdentifier:original == NSNull.null ? nil : original forAlertType:[types[i] integerValue]];
        }
    }
    for (NSUInteger i=0;i<types.count;i++) {
        id original = originals[i]; NSString *restored = [manager currentToneIdentifierForAlertType:[types[i] integerValue]];
        if (original == NSNull.null ? restored != nil : ![original isEqual:restored]) { puts("Original sound assignment did not restore"); return 4; }
    }
    if (outcome) return (int)outcome;
    if (IPToneRemovalError(manager,identifier)) { puts("Unassigned test tone incorrectly blocked"); return 5; }
    NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:@"remove" userInfo:@{@"identifier":identifier}];
    if (![reply[@"ok"] boolValue]) { printf("Unassigned removal failed: %s\n",reply.description.UTF8String); return 6; }
    puts("PASS: original sound assignments restored; unassigned disposable tone removed.");
    return 0;
} }
