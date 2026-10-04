#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared/Bridge.h"
#import <rootless.h>
#import <dlfcn.h>
@interface IPRootListController : PSListController
@property (nonatomic) BOOL busy;
@end
@implementation IPRootListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        NSUInteger position = [items indexOfObjectPassingTest:^BOOL(PSSpecifier *s, NSUInteger idx, BOOL *stop){ return [s.identifier isEqual:@"SoundsShortcut"]; }];
        NSArray *tones = [NSArray arrayWithContentsOfFile:ROOT_PATH_NS(@"/var/mobile/Library/Importone/CustomTones.plist")] ?: @[];
        if (position != NSNotFound) {
            if (!tones.count) {
                PSSpecifier *empty = [PSSpecifier preferenceSpecifierNamed:@"No custom ringtones yet" target:self set:NULL get:NULL detail:Nil cell:PSTitleValueCell edit:Nil];
                [items insertObject:empty atIndex:position++];
            }
            for (NSDictionary *tone in tones) {
                if (!IPSafeName(tone[@"name"]) || ![tone[@"identifier"] isKindOfClass:NSString.class]) continue;
                PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:tone[@"name"] target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
                row.buttonAction = @selector(manageTone:);
                row->action = @selector(manageTone:);
                [row setProperty:tone forKey:@"importoneTone"];
                [items insertObject:row atIndex:position++];
            }
        }
        _specifiers = items;
    }
    return _specifiers;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _specifiers = nil; [self reloadSpecifiers]; }
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Importone" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)performOperation:(NSString *)operation tone:(NSDictionary *)tone name:(NSString *)name {
    if (self.busy) return;
    self.busy = YES; self.table.userInteractionEnabled = NO;
    NSMutableDictionary *info = [@{@"identifier":tone[@"identifier"]} mutableCopy];
    if (name) info[@"name"] = name;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:operation userInfo:info];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO; self.table.userInteractionEnabled = YES;
            self->_specifiers = nil; [self reloadSpecifiers];
            if (![reply[@"ok"] boolValue]) [self showError:reply[@"error"] ?: @"Importone could not contact its service. Please try again."];
        });
    });
}
- (void)renameTone:(NSDictionary *)tone {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Ringtone" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){ field.text = tone[@"name"]; field.clearButtonMode = UITextFieldViewModeWhileEditing; field.autocorrectionType = UITextAutocorrectionTypeNo; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *name = IPSafeName(alert.textFields.firstObject.text);
        if (!name) { [self showError:@"Use a name of 1–80 characters without slashes, colons, or control characters."]; return; }
        [self performOperation:@"rename" tone:tone name:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)removeTone:(NSDictionary *)tone {
    if (self.busy) return;
    self.busy = YES; self.table.userInteractionEnabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:@"canRemove" userInfo:@{@"identifier":tone[@"identifier"]}];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO; self.table.userInteractionEnabled = YES;
            if (![reply[@"ok"] boolValue]) [self showError:reply[@"error"] ?: @"Importone could not check this ringtone’s sound assignments. Please try again."];
            else [self confirmRemoveTone:tone];
        });
    });
}
- (void)confirmRemoveTone:(NSDictionary *)tone {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove Ringtone?" message:[NSString stringWithFormat:@"Remove “%@” from your custom ringtones?",tone[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){ [self performOperation:@"remove" tone:tone name:nil]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)manageTone:(PSSpecifier *)specifier {
    NSDictionary *tone = [specifier propertyForKey:@"importoneTone"];
    if (!tone || self.busy) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:tone[@"name"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self renameTone:tone]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){ [self removeTone:tone]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"importoneTone"] || [specifier.identifier isEqual:@"OpenSounds"]) {
        // Use the native Enabled row's font, including its size and regular weight.
        PSSpecifier *enabled;
        for (PSSpecifier *item in self.specifiers) if ([[item propertyForKey:@"key"] isEqual:@"Enabled"]) { enabled = item; break; }
        NSIndexPath *enabledPath = enabled ? [self indexPathForSpecifier:enabled] : nil;
        UITableViewCell *enabledCell = enabledPath ? [super tableView:tableView cellForRowAtIndexPath:enabledPath] : nil;
        cell.textLabel.font = enabledCell.textLabel.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.numberOfLines = 1;
        cell.imageView.image = nil;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textAlignment = NSTextAlignmentNatural;
    }
    return cell;
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return !self.busy && [[self specifierAtIndexPath:indexPath] propertyForKey:@"importoneTone"] != nil;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *tone = [[self specifierAtIndexPath:indexPath] propertyForKey:@"importoneTone"];
    if (!tone || self.busy) return nil;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Remove" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)){ completion(YES); [self removeTone:tone]; }];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)){ completion(YES); [self renameTone:tone]; }];
    rename.backgroundColor = UIColor.systemBlueColor;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove, rename]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
- (void)openSounds {
    dlopen("/System/Library/PrivateFrameworks/Settings/SoundsAndHapticsSettings.framework/SoundsAndHapticsSettings", RTLD_NOW);
    Class soundsClass = NSClassFromString(@"SHSSoundsPrefController");
    if (self.navigationController && [soundsClass isSubclassOfClass:UIViewController.class]) {
        @try {
            UIViewController *controller = [soundsClass new];
            controller.title = @"Sounds & Haptics";
            [controller loadViewIfNeeded];
            [self.navigationController pushViewController:controller animated:YES];
            return;
        } @catch (NSException *exception) { NSLog(@"Importone Sounds shortcut: %@", exception.reason); }
    }
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"prefs:root=Sounds"] options:@{} completionHandler:^(BOOL success){
        if (!success) dispatch_async(dispatch_get_main_queue(), ^{ [self showError:@"Open Settings → Sounds & Haptics to select your ringtone or alert tone."]; });
    }];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], CFSTR("com.sonicedc.importone")));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)value, CFSTR("com.sonicedc.importone")); CFPreferencesAppSynchronize(CFSTR("com.sonicedc.importone"));
}
- (void)openSonicedc { [self open:@"https://github.com/Sonicedc"]; }
- (void)openRepository { [self open:@"https://github.com/Sonicedc/Importone"]; }
- (void)open:(NSString *)url { [UIApplication.sharedApplication openURL:[NSURL URLWithString:url] options:@{} completionHandler:nil]; }
- (void)openLicenses {
    UIViewController *controller = [UIViewController new]; controller.title=@"Licenses";
    UITextView *text = [UITextView new]; text.editable=NO; text.backgroundColor=UIColor.systemBackgroundColor; text.textColor=UIColor.labelColor;
    NSMutableString *licenses=[NSMutableString new]; NSBundle *bundle=[NSBundle bundleForClass:self.class];
    for (NSString *name in @[@"SubstrateLicense", @"ElleKitLicense", @"PreferenceLoaderLicense"]) { [licenses appendFormat:@"%@\n%@\n\n",name,[NSString stringWithContentsOfFile:[bundle pathForResource:name ofType:@"txt"] encoding:NSUTF8StringEncoding error:nil] ?: @""]; }
    text.text=licenses; controller.view=text; [self.navigationController pushViewController:controller animated:YES];
}
@end
