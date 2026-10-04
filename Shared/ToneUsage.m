#import "ToneUsage.h"
#import <dlfcn.h>
@interface NSObject (IPToneUsage)
- (NSString *)currentToneIdentifierForAlertType:(NSInteger)type;
@end
NSString *IPToneRemovalError(id manager, NSString *identifier) {
    NSInteger (*alertTypeFromString)(NSString *) = dlsym(RTLD_DEFAULT, "TLAlertTypeFromString");
    if (!alertTypeFromString || ![manager respondsToSelector:@selector(currentToneIdentifierForAlertType:)]) return @"Importone could not check the current sound assignments. Please try again before removing this ringtone.";
    NSArray *types = @[@"TLAlertTypeIncomingCall", @"TLAlertTypeTextMessage", @"TLAlertTypeNewVoicemail", @"TLAlertTypeNewMail", @"TLAlertTypeSentMail", @"TLAlertTypeCalendarAlert", @"TLAlertTypeReminderAlert"];
    NSArray *names = @[@"Ringtone", @"Text Tone", @"New Voicemail", @"New Mail", @"Sent Mail", @"Calendar Alerts", @"Reminder Alerts"];
    NSMutableArray *assigned = [NSMutableArray new];
    @try {
        for (NSUInteger i=0;i<types.count;i++) {
            NSInteger type = alertTypeFromString(types[i]);
            if (type <= 0) return @"Importone could not check all sound assignments. Select another tone in Sounds & Haptics and try again.";
            if ([[manager currentToneIdentifierForAlertType:type] isEqual:identifier]) [assigned addObject:names[i]];
        }
    } @catch (NSException *exception) { return @"Importone could not check the current sound assignments. Please try again."; }
    if (!assigned.count) return nil;
    return [NSString stringWithFormat:@"This ringtone is currently selected for %@. Select another ringtone in Settings → Sounds & Haptics before deleting it.",[assigned componentsJoinedByString:@", "]];
}
