// On-device, non-presenting integration check. Built separately, never packaged.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <objc/runtime.h>
@interface TKTonePickerController : NSObject
- (instancetype)initWithAlertType:(long long)type;
- (NSInteger)numberOfSections;
- (id)pickerItemForSection:(NSInteger)section;
- (id)_identifierOfToneAtIndexPath:(NSIndexPath *)path;
- (BOOL)didSelectTonePickerItem:(id)item;
@property (nonatomic, copy) NSString *selectedToneIdentifier;
- (void)stopPlayingWithFadeOut:(BOOL)fade;
@end
@interface NSObject (IPProbePickerItem)
- (NSInteger)numberOfChildren;
- (id)childItemAtIndex:(NSInteger)index;
- (NSString *)text;
@end
@interface IPImportActivity : UIActivity
@property (nonatomic, copy) NSArray *providedItems;
@end
@interface IPShareConfiguration : NSProxy
@property (nonatomic, strong) id<UIActivityItemsConfigurationReading> original;
@end
int main(void) { setbuf(stdout,NULL); @autoreleasepool {
    printf("Share controller bundle: %s\n", [NSBundle bundleForClass:UIActivityViewController.class].bundleIdentifier.UTF8String);
    printf("Automatically injected: %s\n", NSClassFromString(@"IPImportActivity") ? "yes" : "no");
    void *tweak = dlopen("/var/jb/Library/MobileSubstrate/DynamicLibraries/Importone.dylib", RTLD_NOW);
    if (!tweak) { printf("Tweak load error: %s\n", dlerror()); return 1; }
    Class activityClass = NSClassFromString(@"IPImportActivity");
    IPImportActivity *activity = [activityClass new];
    NSURL *audio = [NSURL fileURLWithPath:@"/Library/Ringtones/Apex.m4r"];
    if (![activity canPerformWithActivityItems:@[audio]]) { puts("Audio URL activity rejected"); return 2; }
    if ([activity canPerformWithActivityItems:@[[NSURL fileURLWithPath:@"/tmp/document.pdf"]]]) { puts("PDF incorrectly accepted"); return 3; }
    NSItemProvider *provider = [[NSItemProvider alloc] initWithContentsOfURL:audio];
    activity.providedItems = @[provider];
    if (![activity canPerformWithActivityItems:@[]]) { puts("Audio item provider rejected"); return 4; }
    UIActivityItemsConfiguration *configuration = [[UIActivityItemsConfiguration alloc] initWithItemProviders:@[provider]];
    id<UIActivityItemsConfigurationReading> proxy = [NSClassFromString(@"IPShareConfiguration") alloc];
    [(IPShareConfiguration *)proxy setOriginal:configuration];
    NSArray *activities = proxy.applicationActivitiesForActivityItemsConfiguration;
    if (activities.count != 1 || ![[activities.firstObject activityTitle] isEqual:@"Importone"]) { puts("Configuration action missing"); return 5; }
    [activity prepareWithActivityItems:@[audio]];
    UIViewController *progress = [activity activityViewController];
    [progress loadViewIfNeeded];
    progress.view.bounds = CGRectMake(0,0,390,844); [progress.view layoutIfNeeded];
    UIVisualEffectView *card;
    for (UIView *child in progress.view.subviews) if ([child isKindOfClass:UIVisualEffectView.class]) card = (id)child;
    if (!card || fabs(card.bounds.size.width - 220) > 1 || fabs(card.bounds.size.height - 220) > 1 || card.layer.cornerRadius != 24 || progress.modalPresentationStyle != UIModalPresentationOverFullScreen) { puts("Compact card layout invalid"); return 13; }
    puts("PASS: 220-point rounded progress card, full-screen blur removed.");
    NSError *error;
    NSBundle *preferences = [NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/ImportonePrefs.bundle"];
    if (![preferences loadAndReturnError:&error] || ![NSStringFromClass(preferences.principalClass) isEqual:@"IPRootListController"]) { printf("Settings bundle error: %s\n", error.description.UTF8String); return 6; }
    UIViewController *settings = [preferences.principalClass new];
    @try { [settings loadViewIfNeeded]; } @catch (NSException *exception) { printf("Settings view error: %s\n", exception.reason.UTF8String); return 7; }
    if (!settings.isViewLoaded) { puts("Settings view did not load"); return 8; }
    for (NSNumber *alert in @[@1, @2, @3, @4, @5, @6]) {
        TKTonePickerController *picker = [[NSClassFromString(@"TKTonePickerController") alloc] initWithAlertType:alert.longLongValue];
        BOOL found = NO;
        for (NSInteger section=0; section < picker.numberOfSections; section++) {
            id item = [picker pickerItemForSection:section];
            if ([[item text] isEqual:@"Custom Ringtones"]) {
                if ([item numberOfChildren] < 1) { puts("Custom section empty"); return 9; }
                id row = [item childItemAtIndex:0];
                NSString *identifier = [picker _identifierOfToneAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
                if (![identifier hasPrefix:@"itunes:"] || ![[row text] length]) { puts("Native tone row invalid"); return 10; }
                [picker didSelectTonePickerItem:row];
                [picker stopPlayingWithFadeOut:NO];
                if (![picker.selectedToneIdentifier isEqual:identifier]) { puts("Native row selection failed"); return 11; }
                printf("PASS: custom section for alert type %lld, %ld tones, selected native identifier.\n", alert.longLongValue,(long)[item numberOfChildren]);
                found = YES; break;
            }
        }
        if (!found) { printf("Custom section missing for alert type %lld\n", alert.longLongValue); return 12; }
    }
    puts("PASS: audio URL, non-audio rejection, item-provider configuration, and Settings bundle loading.");
} return 0; }
