// On-device integration probe. Edits only a disposable tone and restores its test assignment.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../Shared/Bridge.h"
@interface NSObject (IPEditProbe)
- (void)cropTone:(NSDictionary *)tone;
- (void)setSelectionFrom:(double)start to:(double)end;
- (void)cancel;
- (void)accept;
- (BOOL)busy;
@end
@interface TLToneManager : NSObject
+ (instancetype)sharedToneManager;
- (NSString *)currentToneIdentifierForAlertType:(NSInteger)type;
- (void)setCurrentToneIdentifier:(NSString *)identifier forAlertType:(NSInteger)type;
- (NSString *)_deviceITunesRingtoneInformationPlist;
- (NSString *)_deviceITunesRingtoneDirectory;
@end
static UIViewController *presented;
static void capture(id self,SEL cmd,UIViewController *controller,BOOL animated,void (^completion)(void)) { presented=controller; if (completion) completion(); }
static void dismiss(id self,SEL cmd,BOOL animated,void (^completion)(void)) { if (completion) completion(); }
static BOOL waitFor(BOOL (^condition)(void),double seconds) { NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds]; while (!condition() && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; return condition(); }
int main(void) { setbuf(stdout,NULL); @autoreleasepool {
    NSDictionary *tone;
    for (NSDictionary *entry in [IPCenter() sendMessageAndReceiveReplyName:@"list" userInfo:@{}][@"tones"]) if ([entry[@"name"] isEqual:@"ImportoneEditCheck"]) tone=entry;
    if (!tone) { puts("Disposable edit tone missing"); return 1; }
    NSString *identifier=tone[@"identifier"];
    NSDictionary *initial=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":identifier}];
    if (![initial[@"ok"] boolValue]) return 2;
    dlopen("/System/Library/PrivateFrameworks/ToneLibrary.framework/ToneLibrary",RTLD_NOW);
    TLToneManager *manager=[NSClassFromString(@"TLToneManager") sharedToneManager];
    NSString *original=[manager currentToneIdentifierForAlertType:1];
    NSInteger result=0;
    @try {
        NSBundle *bundle=[NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/ImportonePrefs.bundle"];
        if (![bundle load]) { puts("Preferences bundle did not load"); result=3; }
        Class settingsClass=objc_allocateClassPair(NSClassFromString(@"IPRootListController"),"IPEditProbeSettings",0);
        class_addMethod(settingsClass,@selector(presentViewController:animated:completion:),(IMP)capture,"v@:@B@?"); objc_registerClassPair(settingsClass);
        Class navClass=objc_allocateClassPair(UINavigationController.class,"IPEditProbeNavigation",0);
        class_addMethod(navClass,@selector(dismissViewControllerAnimated:completion:),(IMP)dismiss,"v@:B@?"); objc_registerClassPair(navClass);
        UIViewController *settings=[settingsClass new]; [settings loadViewIfNeeded];
        for (int pass=0; !result && pass<2; pass++) {
            presented=nil; [(id)settings cropTone:tone];
            if (!waitFor(^BOOL{ return presented!=nil; },15) || ![presented isKindOfClass:UINavigationController.class]) { puts("Preference Crop failed to open editor"); result=4; break; }
            UINavigationController *navigation=(id)presented; object_setClass(navigation,navClass);
            UIViewController *editor=navigation.topViewController; id wave=[editor valueForKey:@"waveform"];
            if (![NSStringFromClass(editor.class) isEqual:@"IPPreferencesCropController"] || ![editor.navigationItem.rightBarButtonItem.title isEqual:@"Save Crop"] || !waitFor(^BOOL{ return [[wave valueForKey:@"peaks"] count]==4096; },15)) { puts("Shared preference editor or waveform invalid"); result=5; break; }
            if (fabs([[wave valueForKey:@"end"] doubleValue]-20)>0.05) { puts("Short source initial selection invalid"); result=16; break; }
            [wave setSelectionFrom:10 to:16];
            if (!pass) {
                [(id)editor cancel];
                NSDictionary *afterCancel=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":identifier}];
                if ([(id)settings busy] || ![afterCancel[@"revision"] isEqual:initial[@"revision"]]) { puts("Cancel changed original audio"); result=6; }
                continue;
            }
            [manager setCurrentToneIdentifier:identifier forAlertType:1];
            [(id)editor accept];
            if (!waitFor(^BOOL{ return ![(id)settings busy]; },25)) { puts("Crop save did not finish"); result=7; break; }
            if ([presented isKindOfClass:UIAlertController.class]) { printf("Save error: %s\n",[(UIAlertController *)presented message].UTF8String); result=8; break; }
            NSDictionary *saved=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":identifier}];
            if (![saved[@"ok"] boolValue] || [saved[@"revision"] isEqual:initial[@"revision"]] || ![saved[@"revision"] isEqual:saved[@"nativeRevision"]] || ![saved[@"name"] isEqual:tone[@"name"]] || ![[manager currentToneIdentifierForAlertType:1] isEqual:identifier]) { puts("Replacement lost identity, assignment, or audio consistency"); result=9; break; }
            NSString *stage=[@"/var/lib/ringtones" stringByAppendingPathComponent:[tone[@"name"] stringByAppendingPathExtension:@"m4r"]];
            AVAudioFile *decoded=[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:stage] error:nil];
            double duration=decoded.length/decoded.processingFormat.sampleRate;
            if (!decoded || fabs(duration-6)>0.05) { printf("Saved duration invalid: %.3f\n",duration); result=10; break; }
            NSMutableDictionary *stale=[@{@"identifier":identifier,@"data":initial[@"data"],@"revision":initial[@"revision"],@"nativeRevision":initial[@"nativeRevision"]} mutableCopy];
            if ([[IPCenter() sendMessageAndReceiveReplyName:@"replace" userInfo:stale][@"ok"] boolValue]) { puts("Stale overwrite accepted"); result=11; break; }
            stale[@"revision"]=saved[@"revision"]; stale[@"nativeRevision"]=saved[@"nativeRevision"]; stale[@"data"]=[@"invalid audio" dataUsingEncoding:NSUTF8StringEncoding];
            if ([[IPCenter() sendMessageAndReceiveReplyName:@"replace" userInfo:stale][@"ok"] boolValue]) { puts("Invalid overwrite accepted"); result=12; break; }
            NSDictionary *final=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":identifier}];
            if (![final[@"revision"] isEqual:saved[@"revision"]]) { puts("Rejected saves changed audio"); result=13; }
        }
    } @finally { [manager setCurrentToneIdentifier:original forAlertType:1]; }
    if (![[manager currentToneIdentifierForAlertType:1] isEqual:original]) { puts("Sound assignment restoration failed"); return 14; }
    NSDictionary *removed=[IPCenter() sendMessageAndReceiveReplyName:@"remove" userInfo:@{@"identifier":identifier}];
    if (![removed[@"ok"] boolValue]) { puts("Disposable test cleanup failed"); return 15; }
    if (!result) puts("PASS: preference Crop uses shared editor; cancel preserves audio; 6-second save overwrites both files; name, native ID and assignment persist; stale and invalid saves rejected; assignment restored and test tone removed.");
    return (int)result;
} }
