#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
@interface IPCreditCell : PSTableCell
@property UIImageView *creditIcon;
@property UILabel *creditName;
@property NSString *credit;
@end
@implementation IPCreditCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier])){
        self.textLabel.text=nil;self.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        _creditIcon=[UIImageView new];_creditIcon.contentMode=UIViewContentModeScaleAspectFit;_creditIcon.translatesAutoresizingMaskIntoConstraints=NO;
        _creditName=[UILabel new];_creditName.font=[UIFont systemFontOfSize:17 weight:UIFontWeightMedium];_creditName.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:_creditIcon];[self.contentView addSubview:_creditName];
        [NSLayoutConstraint activateConstraints:@[[_creditIcon.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],[_creditIcon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],[_creditIcon.widthAnchor constraintEqualToConstant:32],[_creditIcon.heightAnchor constraintEqualToConstant:32],[_creditName.leadingAnchor constraintEqualToAnchor:_creditIcon.trailingAnchor constant:12],[_creditName.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],[_creditName.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-12]]];
        [self refreshCellContentsWithSpecifier:specifier];
    }return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];self.textLabel.text=nil;self.credit=[specifier propertyForKey:@"credit"];
    self.creditName.text=[specifier propertyForKey:@"label"];self.accessibilityLabel=self.creditName.text;self.accessibilityTraits=UIAccessibilityTraitLink;
    BOOL author=[self.credit isEqual:@"sonicedc"];
    self.creditIcon.layer.cornerRadius=author?16:0;self.creditIcon.clipsToBounds=YES;
    self.creditName.textColor=author?[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){return traits.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:.73 green:.65 blue:.94 alpha:1]:[UIColor colorWithRed:.48 green:.35 blue:.73 alpha:1];}]:UIColor.labelColor;
    [self updateIcon];
}
- (void)updateIcon {
    NSString *name=[self.credit isEqual:@"sonicedc"]?@"sonicedc.png":(self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark?@"github-white.png":@"github-black.png");
    self.creditIcon.image=[UIImage imageNamed:name inBundle:[NSBundle bundleForClass:IPCreditCell.class] compatibleWithTraitCollection:self.traitCollection];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {[super traitCollectionDidChange:previous];[self updateIcon];}
@end
