// On-device, non-presenting integration check. Built separately, never packaged.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <dlfcn.h>
#import <objc/runtime.h>
@interface NSObject (IPProbePreferences)
- (NSArray *)specifiers;
- (id)propertyForKey:(NSString *)key;
- (id)specifierAtIndexPath:(NSIndexPath *)path;
- (UITableView *)table;
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path;
- (void)openSounds;
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path;
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path;
@end
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
// A command-line probe has no visible window for animated navigation transitions.
@interface IPProbeNavigation : UINavigationController
@end
@implementation IPProbeNavigation
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated { [super pushViewController:controller animated:NO]; }
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
    BOOL management = NO;
    NSInteger toneSection = NSNotFound, shortcutSection = NSNotFound;
    UIFont *enabledFont;
    NSMutableArray<UITableViewCell *> *plainCells = [NSMutableArray new];
    UITableView *table = [(id)settings table];
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            id specifier = [(id)settings specifierAtIndexPath:path];
            if ([[specifier propertyForKey:@"key"] isEqual:@"Enabled"]) enabledFont = [(id)settings tableView:table cellForRowAtIndexPath:path].textLabel.font;
            if ([[specifier propertyForKey:@"id"] isEqual:@"OpenSounds"]) { shortcutSection = section; [plainCells addObject:[(id)settings tableView:table cellForRowAtIndexPath:path]]; }
            if (![specifier propertyForKey:@"importoneTone"]) continue;
            toneSection = section;
            UITableViewCell *cell = [(id)settings tableView:table cellForRowAtIndexPath:path];
            [plainCells addObject:cell];
            if (![cell.accessoryView isKindOfClass:UIButton.class] || cell.accessoryView.bounds.size.width<44 || ![cell.accessoryView.accessibilityIdentifier hasPrefix:@"importone.preview."]) { puts("Ringtone preview button missing"); return 20; }
            UISwipeActionsConfiguration *actions = [(id)settings tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:path];
            if (![(id)settings tableView:table canEditRowAtIndexPath:path]) { puts("Swipe editing unavailable"); return 16; }
            if (actions.actions.count != 3 || actions.performsFirstActionWithFullSwipe || ![actions.actions[0].title isEqual:@"Remove"] || ![actions.actions[1].title isEqual:@"Crop"] || ![actions.actions[2].title isEqual:@"Rename"]) { puts("Management actions invalid"); return 14; }
            management = YES;
        }
    }
    if (!management) { puts("Custom tone preferences row missing"); return 15; }
    if (shortcutSection == NSNotFound || shortcutSection == toneSection) { puts("Shortcut is not separated from ringtone list"); return 19; }
    for (UITableViewCell *cell in plainCells) {
        if (![cell.textLabel.textColor isEqual:UIColor.labelColor] || cell.imageView.image || cell.accessoryType != UITableViewCellAccessoryNone || ![cell.textLabel.font isEqual:enabledFont]) { puts("Plain row styling or Enabled font match invalid"); return 18; }
    }
    puts("PASS: plain text rows with preview controls and no decorative icons/chevrons, same font as Enabled, and separate shortcut.");
    UINavigationController *navigation = [[IPProbeNavigation alloc] initWithRootViewController:settings];
    [navigation loadViewIfNeeded];
    [(id)settings openSounds];
    if (![NSStringFromClass(navigation.topViewController.class) isEqual:@"SHSSoundsPrefController"] || !navigation.topViewController.isViewLoaded) { puts("Native Sounds shortcut failed"); return 17; }
    puts("PASS: shortcut loads and pushes native Sounds & Haptics controller.");
    for (NSNumber *alert in @[@1, @2, @4, @5, @6, @10, @11]) {
        TKTonePickerController *picker = [[NSClassFromString(@"TKTonePickerController") alloc] initWithAlertType:alert.longLongValue];
        BOOL found = NO;
        for (NSInteger section=0; section < picker.numberOfSections; section++) {
            id item = [picker pickerItemForSection:section];
            if ([[item text] isEqual:@"Custom Ringtones"]) {
                if ([item numberOfChildren] < 1) { puts("Custom section empty"); return 9; }
                id row = [item childItemAtIndex:0];
                // Native rows append a localized Default marker when the tone
                // is assigned. Find the catalog name before that marker.
                NSString *identifier,*matchedName;
                NSArray *catalog=[NSArray arrayWithContentsOfFile:@"/var/jb/var/mobile/Library/Importone/CustomTones.plist"];
                for (NSDictionary *tone in catalog) {
                    NSString *name=tone[@"name"];
                    if ([[row text] isEqual:name] || ([[row text] hasPrefix:[name stringByAppendingString:@" ("]] && name.length>matchedName.length)) { identifier=tone[@"identifier"]; matchedName=name; }
                }
                if (![identifier hasPrefix:@"itunes:"] || ![[row text] length]) { printf("Native tone row invalid: alert %lld class %s text %s identifier %s description %s\n",alert.longLongValue,NSStringFromClass([row class]).UTF8String,[[row text] UTF8String] ?: "nil",identifier.UTF8String ?: "nil",[[row description] UTF8String]); return 10; }
                [picker didSelectTonePickerItem:row];
                [picker stopPlayingWithFadeOut:NO];
                // ToneKit represents the native Default alias with a nil
                // selection; its label shows the resolved tone's name.
                BOOL defaultAlias=[[row text] hasSuffix:@" (Default)"];
                if (defaultAlias ? picker.selectedToneIdentifier!=nil : ![picker.selectedToneIdentifier isEqual:identifier]) { puts("Native row selection failed"); return 11; }
                printf("PASS: custom section for alert type %lld, %ld tones, native %s selection.\n", alert.longLongValue,(long)[item numberOfChildren],defaultAlias ? "Default" : "identifier");
                found = YES; break;
            }
        }
        if (!found) { printf("Custom section missing for alert type %lld\n", alert.longLongValue); return 12; }
    }
    puts("PASS: audio URL, non-audio rejection, item-provider configuration, and Settings bundle loading.");
} return 0; }
