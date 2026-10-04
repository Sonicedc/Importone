// On-device integration test. Uses synthetic audio; never packaged.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "../CropController.h"
static const char IPPresentedKey, IPRenamedKey;
static void capturePresentation(id self, SEL selector, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    objc_setAssociatedObject(self,&IPPresentedKey,controller,OBJC_ASSOCIATION_RETAIN_NONATOMIC); if (completion) completion();
}
static void captureRename(id self, SEL selector) { objc_setAssociatedObject(self,&IPRenamedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void immediateDismiss(id self, SEL selector, BOOL animated, void (^completion)(void)) { if (completion) completion(); }
static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}
@interface NSObject (IPCropProbe)
- (void)accept;
- (void)cancel;
- (void)togglePreview;
- (void)stopPreview;
- (void)finish:(BOOL)success;
@end
@interface IPProbePan : UIPanGestureRecognizer
@property UIGestureRecognizerState probeState;
@property CGPoint probeTranslation;
@end
@implementation IPProbePan
- (UIGestureRecognizerState)state { return self.probeState; }
- (CGPoint)translationInView:(UIView *)view { return self.probeTranslation; }
@end
@interface IPProbeHold : UILongPressGestureRecognizer
@property UIGestureRecognizerState probeState;
@property CGPoint probeLocation;
@end
@implementation IPProbeHold
- (UIGestureRecognizerState)state { return self.probeState; }
- (CGPoint)locationInView:(UIView *)view { return self.probeLocation; }
@end
@interface NSObject (IPCropGestures)
- (void)pan:(UIPanGestureRecognizer *)recognizer;
- (void)hold:(UILongPressGestureRecognizer *)recognizer;
@end
static Class importerClass, dismissClass;
static UIViewController *openCrop(NSURL *source) {
    UIViewController *importer=[importerClass new]; [importer setValue:source forKey:@"source"];
    [importer loadViewIfNeeded]; [importer viewDidAppear:NO];
    if (!waitFor(^BOOL{ return objc_getAssociatedObject(importer,&IPPresentedKey)!=nil; },15)) { puts("Crop sheet was not presented for long audio"); return nil; }
    UINavigationController *navigation=objc_getAssociatedObject(importer,&IPPresentedKey);
    if (![navigation isKindOfClass:UINavigationController.class] || ![navigation.topViewController isKindOfClass:NSClassFromString(@"IPCropController")]) { puts("Long audio did not open the crop controller"); return nil; }
    object_setClass(navigation,dismissClass); [navigation loadViewIfNeeded]; [navigation.topViewController loadViewIfNeeded];
    return importer;
}
int main(int argc,char **argv) { setbuf(stdout,NULL); @autoreleasepool {
    if (argc!=2) return 1;
    if (!dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/Importone.dylib",RTLD_NOW)) { puts(dlerror()); return 2; }
    importerClass=objc_allocateClassPair(NSClassFromString(@"IPImportController"),"IPCropProbeImporter",0);
    class_addMethod(importerClass,@selector(presentViewController:animated:completion:),(IMP)capturePresentation,"v@:@B@?");
    class_addMethod(importerClass,NSSelectorFromString(@"rename"),(IMP)captureRename,"v@:"); objc_registerClassPair(importerClass);
    dismissClass=objc_allocateClassPair(UINavigationController.class,"IPCropProbeNavigation",0);
    class_addMethod(dismissClass,@selector(dismissViewControllerAnimated:completion:),(IMP)immediateDismiss,"v@:B@?"); objc_registerClassPair(dismissClass);
    NSURL *source=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    UIViewController *importer=openCrop(source); if (!importer) return 3;
    UINavigationController *navigation=objc_getAssociatedObject(importer,&IPPresentedKey);
    IPCropController *crop=(id)navigation.topViewController;
    crop.view.frame=CGRectMake(0,0,390,430); [crop.view layoutIfNeeded];
    IPWaveformView *wave=[crop valueForKey:@"waveform"];
    if (!waitFor(^BOOL{ return wave.peaks.count==4096; },30)) { printf("Waveform load failed: %s\n",[[crop valueForKey:@"statusLabel"] text].UTF8String); return 4; }
    double maximum=0; for (NSNumber *peak in wave.peaks) maximum=MAX(maximum,peak.doubleValue);
    if (maximum<0.5 || wave.bounds.size.width<200) { puts("Waveform samples or layout invalid"); return 5; }
    [wave setSelectionStart:-10]; if (wave.start!=0) return 6;
    [wave setSelectionStart:10000]; if (fabs(wave.start-(wave.duration-40))>0.001) return 7;
    [wave setSelectionStart:10];
    IPProbePan *pan=[IPProbePan new]; pan.probeState=UIGestureRecognizerStateBegan; [wave pan:pan];
    pan.probeState=UIGestureRecognizerStateChanged; pan.probeTranslation=CGPointMake(-wave.bounds.size.width/8,0); [wave pan:pan];
    if (fabs(wave.start-20)>0.001) { puts("Waveform drag mapping invalid"); return 8; }
    for (NSNumber *edge in @[@0,@1]) {
        [wave setSelectionStart:10]; IPProbeHold *hold=[IPProbeHold new];
        hold.probeState=UIGestureRecognizerStateBegan; hold.probeLocation=CGPointMake(wave.bounds.size.width*(edge.boolValue ? 0.75 : 0.25),85); [wave hold:hold];
        if (!wave.zoomed || wave.zoomEdge!=edge.integerValue) return 9;
        hold.probeState=UIGestureRecognizerStateChanged; hold.probeLocation=CGPointMake(hold.probeLocation.x-wave.bounds.size.width/8,85); [wave hold:hold];
        if (fabs(wave.start-11)>0.001) { puts("Bracket precision zoom mapping invalid"); return 10; }
        hold.probeState=UIGestureRecognizerStateEnded; [wave hold:hold]; if (wave.zoomed) return 11;
    }
    [wave setSelectionStart:12.345];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:crop.view.bounds.size];
    NSData *png=UIImagePNGRepresentation([renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [crop.view.layer renderInContext:context.CGContext]; }]);
    [png writeToFile:@"/var/mobile/ImportoneCropPreview.png" atomically:YES];
    [crop togglePreview]; AVPlayer *player=[crop valueForKey:@"player"]; player.volume=0;
    if (!player || fabs(CMTimeGetSeconds(player.currentItem.forwardPlaybackEndTime)-52.345)>0.001) { puts("Preview range invalid"); return 12; }
    if (!waitFor(^BOOL{ return player.rate>0; },10)) { puts("Preview did not start"); return 13; }
    [player seekToTime:CMTimeMakeWithSeconds(wave.start+39.95,60000) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    if (!waitFor(^BOOL{ return ![[crop valueForKey:@"playing"] boolValue]; },5)) { puts("Preview did not stop at the selection end"); return 20; }
    [crop togglePreview];
    [wave setSelectionStart:13]; if (player.rate!=0 || [[crop valueForKey:@"playing"] boolValue]) return 14;
    [wave setSelectionStart:12.345]; [crop accept];
    if (!waitFor(^BOOL{ return [objc_getAssociatedObject(importer,&IPRenamedKey) boolValue]; },20)) { puts("Crop export did not reach rename"); return 15; }
    NSURL *converted=[importer valueForKey:@"converted"];
    AVURLAsset *result=[AVURLAsset URLAssetWithURL:converted options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}]; double seconds=CMTimeGetSeconds(result.duration);
    AVAssetExportSession *exporter=[importer valueForKey:@"exporter"];
    printf("Export duration %.6f, selected start %.6f\n",seconds,CMTimeGetSeconds(exporter.timeRange.start));
    AVAudioFile *decoded=[[AVAudioFile alloc] initForReading:converted error:nil];
    double decodedSeconds=decoded.length/decoded.processingFormat.sampleRate;
    if (!decoded || fabs(decodedSeconds-40)>0.05 || seconds>40.05 || fabs(CMTimeGetSeconds(exporter.timeRange.start)-12.345)>0.001 || ![converted.pathExtension isEqual:@"m4r"] || [converted isEqual:source]) { puts("Exported crop range or format invalid"); return 16; }
    [NSFileManager.defaultManager removeItemAtPath:@"/var/mobile/ImportoneCropResult.m4r" error:nil];
    [NSFileManager.defaultManager copyItemAtURL:converted toURL:[NSURL fileURLWithPath:@"/var/mobile/ImportoneCropResult.m4r"] error:nil];
    NSURL *workspace=[importer valueForKey:@"workspace"]; [importer finish:NO];
    if ([NSFileManager.defaultManager fileExistsAtPath:workspace.path]) return 17;
    UIViewController *cancelled=openCrop(source); if (!cancelled) return 18;
    UINavigationController *cancelNavigation=objc_getAssociatedObject(cancelled,&IPPresentedKey);
    NSURL *cancelWorkspace=[cancelled valueForKey:@"workspace"]; [(id)cancelNavigation.topViewController cancel];
    if ([NSFileManager.defaultManager fileExistsAtPath:cancelWorkspace.path]) { puts("Cancel left temporary files"); return 19; }
    puts("PASS: automatic crop sheet, decoded waveform, drag bounds, both precision brackets, bounded preview, exact 40-second export, rename handoff, and cancellation cleanup.");
    return 0;
} }
