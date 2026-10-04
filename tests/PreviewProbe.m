// On-device preview integration check. Uses only two disposable silent tones.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "../Shared/Bridge.h"
@interface NSObject (IPPreviewProbe)
- (UITableView *)table;
- (id)specifierAtIndexPath:(NSIndexPath *)path;
- (id)propertyForKey:(NSString *)key;
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path;
- (void)previewTone:(NSDictionary *)tone;
- (void)stopTonePreview;
@end
static UIViewController *presented;
static void capture(id self,SEL cmd,UIViewController *controller,BOOL animated,void (^completion)(void)) { presented=controller; if (completion) completion(); }
static BOOL waitFor(BOOL (^condition)(void),double seconds) { NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:seconds]; while (!condition() && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]]; return condition(); }
static void pump(double seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static AVAudioPlayer *player(UIViewController *controller) { return [controller valueForKey:@"tonePreviewPlayer"]; }
int main(void) { setbuf(stdout,NULL); @autoreleasepool {
    NSMutableArray *tones=[NSMutableArray new];
    for (NSDictionary *tone in [IPCenter() sendMessageAndReceiveReplyName:@"list" userInfo:@{}][@"tones"]) if ([tone[@"name"] hasPrefix:@"ImportonePreviewCheck"]) [tones addObject:tone];
    if (tones.count!=2) { puts("Two disposable silent tones required"); return 1; }
    NSBundle *bundle=[NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/ImportonePrefs.bundle"]; if (![bundle load]) return 2;
    Class settingsClass=objc_allocateClassPair(NSClassFromString(@"IPRootListController"),"IPPreviewProbeSettings",0);
    class_addMethod(settingsClass,@selector(presentViewController:animated:completion:),(IMP)capture,"v@:@B@?"); objc_registerClassPair(settingsClass);
    UIViewController *settings=[bundle.principalClass new]; [settings loadViewIfNeeded]; object_setClass(settings,settingsClass); settings.view.frame=CGRectMake(0,0,390,844); [settings.view layoutIfNeeded];
    UITableView *table=[(id)settings table]; UIButton *button;
    for (NSInteger section=0;section<table.numberOfSections;section++) for (NSInteger row=0;row<[table numberOfRowsInSection:section];row++) {
        NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];
        NSDictionary *tone=[[(id)settings specifierAtIndexPath:path] propertyForKey:@"importoneTone"];
        if ([tone[@"identifier"] isEqual:tones[0][@"identifier"]]) button=(id)[(id)settings tableView:table cellForRowAtIndexPath:path].accessoryView;
    }
    NSInteger result=0;
    NSString *category=AVAudioSession.sharedInstance.category,*mode=AVAudioSession.sharedInstance.mode;
    AVAudioSessionCategoryOptions options=AVAudioSession.sharedInstance.categoryOptions;
    @try {
        do {
            printf("Preview control: %s, label %s, image %s, sections %ld\n",NSStringFromClass(button.class).UTF8String ?: "nil",button.accessibilityLabel.UTF8String ?: "nil",[button imageForState:UIControlStateNormal] ? "yes" : "no",(long)table.numberOfSections);
            if (![button isKindOfClass:UIButton.class] || ![button.accessibilityLabel hasPrefix:@"Play"] || ![button imageForState:UIControlStateNormal]) { puts("Play glyph missing"); result=3; break; }
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
            if (!waitFor(^BOOL{ return player(settings).playing; },10) || presented) { puts("Play button did not preview independently of row actions"); result=4; break; }
            AVAudioPlayer *first=player(settings); first.volume=0; pump(0.1);
            [button sendActionsForControlEvents:UIControlEventTouchUpInside]; double pausedAt=first.currentTime;
            if (first.playing || player(settings)!=first) { puts("Pause did not preserve player"); result=5; break; }
            pump(0.1); if (fabs(first.currentTime-pausedAt)>0.03) { puts("Paused playback advanced"); result=6; break; }
            [button sendActionsForControlEvents:UIControlEventTouchUpInside]; pump(0.1);
            if (!first.playing || first.currentTime<=pausedAt || player(settings)!=first) { puts("Resume restarted or failed"); result=7; break; }
            [(id)settings previewTone:tones[1]];
            if (first.playing || !waitFor(^BOOL{ return player(settings).playing; },10) || ![[settings valueForKey:@"previewIdentifier"] isEqual:tones[1][@"identifier"]]) { puts("Switching did not stop the old preview"); result=8; break; }
            AVAudioPlayer *second=player(settings); second.volume=0; second.currentTime=second.duration-0.05;
            if (!waitFor(^BOOL{ return player(settings)==nil && [settings valueForKey:@"previewIdentifier"]==nil; },3)) { puts("Natural completion did not reset play state"); result=9; break; }
            [(id)settings previewTone:tones[0]]; [(id)settings previewTone:tones[0]]; pump(0.8);
            if (player(settings) || [settings valueForKey:@"previewIdentifier"]) { puts("Canceled load started playback later"); result=10; break; }
            [(id)settings previewTone:tones[0]]; [settings viewWillDisappear:NO]; pump(0.8);
            if (player(settings) || [settings valueForKey:@"previewIdentifier"]) { puts("Leaving page allowed delayed playback"); result=11; break; }
            [(id)settings previewTone:tones[0]]; if (!waitFor(^BOOL{ return player(settings).playing; },10)) { result=12; break; }
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
            if (player(settings) || ![AVAudioSession.sharedInstance.category isEqual:category] || ![AVAudioSession.sharedInstance.mode isEqual:mode] || AVAudioSession.sharedInstance.categoryOptions!=options) { puts("Backgrounding did not stop and restore audio session"); result=13; break; }
            [(id)settings previewTone:tones[0]]; if (!waitFor(^BOOL{ return player(settings).playing; },10)) { result=14; break; }
            [NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionInterruptionNotification object:AVAudioSession.sharedInstance];
            if (player(settings)) { puts("Interruption did not stop playback"); result=15; break; }
            presented=nil; [(id)settings previewTone:@{@"name":@"Missing",@"identifier":@"itunes:ImportonePreviewMissing"}];
            if (!waitFor(^BOOL{ return [presented isKindOfClass:UIAlertController.class]; },10) || player(settings) || [settings valueForKey:@"previewIdentifier"]) { puts("Missing tone did not fail cleanly"); result=16; break; }
        } while (NO);
    } @finally {
        [(id)settings stopTonePreview];
        for (NSDictionary *tone in tones) if (![[IPCenter() sendMessageAndReceiveReplyName:@"remove" userInfo:@{@"identifier":tone[@"identifier"]}][@"ok"] boolValue]) result=17;
    }
    if (!result) puts("PASS: play glyph control, independent tap, pause/resume, exclusive playback, natural completion, canceled loads, page dismissal, backgrounding, interruption, session restoration and missing-tone errors. Disposable tones removed.");
    return (int)result;
} }
