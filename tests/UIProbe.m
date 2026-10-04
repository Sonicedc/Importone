// On-device, non-presenting integration check. Built separately, never packaged.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
@interface IPImportActivity : UIActivity
@property (nonatomic, copy) NSArray *providedItems;
@end
@interface IPShareConfiguration : NSProxy
@property (nonatomic, strong) id<UIActivityItemsConfigurationReading> original;
@end
int main(void) { @autoreleasepool {
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
    NSError *error;
    NSBundle *preferences = [NSBundle bundleWithPath:@"/var/jb/Library/PreferenceBundles/ImportonePrefs.bundle"];
    if (![preferences loadAndReturnError:&error] || ![NSStringFromClass(preferences.principalClass) isEqual:@"IPRootListController"]) { printf("Settings bundle error: %s\n", error.description.UTF8String); return 6; }
    puts("PASS: audio URL, non-audio rejection, item-provider configuration, and Settings bundle loading.");
} return 0; }
