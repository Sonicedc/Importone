#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
@interface IPRootListController : PSListController
@end
@implementation IPRootListController
- (NSArray *)specifiers { if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self]; return _specifiers; }
- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,320,150)];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"icon@3x.png" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil]];
    icon.frame = CGRectMake(0,20,80,80); icon.center = CGPointMake(self.tableView.bounds.size.width/2,60); icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin; icon.layer.cornerRadius=18; icon.clipsToBounds=YES;
    [header addSubview:icon]; UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,110,self.tableView.bounds.size.width,30)]; title.text=@"Importone"; title.font=[UIFont systemFontOfSize:24 weight:UIFontWeightBold]; title.textAlignment=NSTextAlignmentCenter; title.autoresizingMask=UIViewAutoresizingFlexibleWidth; [header addSubview:title]; self.tableView.tableHeaderView=header;
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
