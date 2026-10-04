#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
@interface IPRootListController : PSListController
@end
@implementation IPRootListController
- (NSArray *)specifiers { if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self]; return _specifiers; }
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
