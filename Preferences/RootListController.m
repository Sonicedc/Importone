#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared/Bridge.h"
#import <rootless.h>
#import <dlfcn.h>
#import "../CropController.h"
@interface IPRootListController : PSListController <AVAudioPlayerDelegate>
@property (nonatomic) BOOL busy;
@property UIView *cropHUD;
@property AVAssetExportSession *cropExporter;
@property AVAudioPlayer *tonePreviewPlayer;
@property NSString *previewIdentifier;
@property NSUInteger previewGeneration;
@property NSString *previewCategory;
@property NSString *previewMode;
@property AVAudioSessionCategoryOptions previewOptions;
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
- (void)viewDidLoad {
    [super viewDidLoad];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopTonePreview) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopTonePreview) name:AVAudioSessionInterruptionNotification object:nil];
}
- (void)viewWillDisappear:(BOOL)animated { [self stopTonePreview]; [super viewWillDisappear:animated]; }
- (void)configurePreviewButton:(UIButton *)button tone:(NSDictionary *)tone {
    BOOL active=[self.previewIdentifier isEqual:tone[@"identifier"]] && (!self.tonePreviewPlayer || self.tonePreviewPlayer.playing);
    [button setImage:[UIImage systemImageNamed:active ? @"pause.fill" : @"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    button.accessibilityLabel=[NSString stringWithFormat:@"%@ %@",active ? @"Pause preview of" : @"Play",tone[@"name"]];
    button.accessibilityIdentifier=[@"importone.preview." stringByAppendingString:tone[@"identifier"]];
    button.tintColor=UIColor.labelColor; button.enabled=!self.busy;
}
- (void)updatePreviewButtons {
    for (UITableViewCell *cell in self.table.visibleCells) {
        NSIndexPath *path=[self.table indexPathForCell:cell];
        NSDictionary *tone=path ? [[self specifierAtIndexPath:path] propertyForKey:@"importoneTone"] : nil;
        if (tone && [cell.accessoryView isKindOfClass:UIButton.class]) [self configurePreviewButton:(id)cell.accessoryView tone:tone];
    }
}
- (void)restorePreviewSession {
    if (self.previewCategory) {
        [AVAudioSession.sharedInstance setCategory:self.previewCategory mode:self.previewMode options:self.previewOptions error:nil];
        self.previewCategory=nil; self.previewMode=nil;
    }
}
- (BOOL)activatePreviewSession:(NSError **)error {
    AVAudioSession *session=AVAudioSession.sharedInstance;
    if (!self.previewCategory) { self.previewCategory=session.category; self.previewMode=session.mode; self.previewOptions=session.categoryOptions; }
    return [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:error] && [session setActive:YES error:error];
}
- (void)stopTonePreview {
    self.previewGeneration++; self.tonePreviewPlayer.delegate=nil; [self.tonePreviewPlayer stop];
    self.tonePreviewPlayer=nil; self.previewIdentifier=nil;
    [self restorePreviewSession]; [self updatePreviewButtons];
}
- (void)previewTone:(NSDictionary *)tone {
    if (self.busy) return;
    if ([self.previewIdentifier isEqual:tone[@"identifier"]] && self.tonePreviewPlayer) {
        if (self.tonePreviewPlayer.playing) { [self.tonePreviewPlayer pause]; [self restorePreviewSession]; }
        else {
            NSError *error;
            if (![self activatePreviewSession:&error] || ![self.tonePreviewPlayer play]) { [self stopTonePreview]; [self showError:error.localizedDescription ?: @"This ringtone could not be played."]; return; }
        }
        [self updatePreviewButtons]; return;
    }
    if ([self.previewIdentifier isEqual:tone[@"identifier"]]) { [self stopTonePreview]; return; }
    [self stopTonePreview]; self.previewIdentifier=tone[@"identifier"];
    NSUInteger generation=self.previewGeneration; [self updatePreviewButtons];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary *reply=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":tone[@"identifier"]}];
        NSData *data=reply[@"data"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation!=self.previewGeneration || ![self.previewIdentifier isEqual:tone[@"identifier"]]) return;
            NSError *decodeError,*sessionError;
            AVAudioPlayer *player=[reply[@"ok"] boolValue] && [data isKindOfClass:NSData.class] ? [[AVAudioPlayer alloc] initWithData:data error:&decodeError] : nil;
            BOOL ready=player && [player prepareToPlay];
            if (!ready || ![self activatePreviewSession:&sessionError]) { [self stopTonePreview]; [self showError:reply[@"error"] ?: decodeError.localizedDescription ?: sessionError.localizedDescription ?: @"This ringtone could not be played."]; return; }
            self.tonePreviewPlayer=player; player.delegate=self;
            if (![player play]) { [self stopTonePreview]; [self showError:@"This ringtone could not be played."]; return; }
            [self updatePreviewButtons];
        });
    });
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)success {
    if (player==self.tonePreviewPlayer) { [self stopTonePreview]; if (!success) [self showError:@"The ringtone preview could not finish playing."]; }
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    if (player==self.tonePreviewPlayer) { [self stopTonePreview]; [self showError:error.localizedDescription ?: @"The ringtone could not be decoded."]; }
}
- (void)dealloc {
    self.tonePreviewPlayer.delegate=nil; [self.tonePreviewPlayer stop]; [self restorePreviewSession];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _specifiers = nil; [self reloadSpecifiers]; }
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Importone" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)performOperation:(NSString *)operation tone:(NSDictionary *)tone name:(NSString *)name {
    [self stopTonePreview];
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
- (void)setCropStep:(NSString *)step {
    if (!self.cropHUD) {
        UIView *overlay=[[UIView alloc] initWithFrame:self.view.bounds]; overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        overlay.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.12];
        UIVisualEffectView *card=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        card.translatesAutoresizingMaskIntoConstraints=NO; card.layer.cornerRadius=22; card.clipsToBounds=YES; [overlay addSubview:card];
        UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge]; [spinner startAnimating];
        UILabel *label=[UILabel new]; label.tag=501; label.numberOfLines=0; label.textAlignment=NSTextAlignmentCenter; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[spinner,label]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=20; stack.translatesAutoresizingMaskIntoConstraints=NO; [card.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],[card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],[card.widthAnchor constraintEqualToConstant:220],[card.heightAnchor constraintEqualToConstant:220],[stack.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],[stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-20]]];
        self.cropHUD=overlay; [self.view addSubview:overlay];
    }
    ((UILabel *)[self.cropHUD viewWithTag:501]).text=step;
}
- (void)finishCropWorkspace:(NSURL *)workspace error:(NSString *)error {
    self.cropExporter=nil; [self.cropHUD removeFromSuperview]; self.cropHUD=nil;
    self.busy=NO; self.table.userInteractionEnabled=YES;
    [NSFileManager.defaultManager removeItemAtURL:workspace error:nil];
    _specifiers=nil; [self reloadSpecifiers]; if (error) [self showError:error];
}
- (void)saveCropAsset:(AVAsset *)asset range:(CMTimeRange)range tone:(NSDictionary *)tone snapshot:(NSDictionary *)snapshot workspace:(NSURL *)workspace {
    [self setCropStep:@"Converting selection…"];
    AVAssetExportSession *exporter=[[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!exporter || ![exporter.supportedFileTypes containsObject:AVFileTypeAppleM4A]) { [self finishCropWorkspace:workspace error:@"This ringtone cannot be cropped on this device."]; return; }
    self.cropExporter=exporter; exporter.outputURL=[workspace URLByAppendingPathComponent:@"crop.m4r"]; exporter.outputFileType=AVFileTypeAppleM4A; exporter.timeRange=range;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        if (exporter.status!=AVAssetExportSessionStatusCompleted) { dispatch_async(dispatch_get_main_queue(), ^{ [self finishCropWorkspace:workspace error:exporter.error.localizedDescription ?: @"The crop could not be converted. Your original ringtone was kept."]; }); return; }
        dispatch_async(dispatch_get_main_queue(), ^{ [self setCropStep:@"Saving ringtone…"]; });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSData *data=[NSData dataWithContentsOfURL:exporter.outputURL];
        NSDictionary *reply=data ? [IPCenter() sendMessageAndReceiveReplyName:@"replace" userInfo:@{@"identifier":tone[@"identifier"],@"revision":snapshot[@"revision"],@"nativeRevision":snapshot[@"nativeRevision"],@"data":data}] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ [self finishCropWorkspace:workspace error:[reply[@"ok"] boolValue] ? nil : (reply[@"error"] ?: @"Importone could not confirm that the crop was saved. Refresh the list and try again.")]; });
        });
    }];
}
- (void)cropTone:(NSDictionary *)tone {
    [self stopTonePreview];
    if (self.busy) return;
    self.busy=YES; self.table.userInteractionEnabled=NO; [self setCropStep:@"Opening ringtone…"];
    NSURL *workspace=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSDictionary *snapshot=[IPCenter() sendMessageAndReceiveReplyName:@"readTone" userInfo:@{@"identifier":tone[@"identifier"]}];
        NSData *data=snapshot[@"data"]; NSError *error;
        NSURL *source=[workspace URLByAppendingPathComponent:@"original.m4r"];
        BOOL ready=[snapshot[@"ok"] boolValue] && [data isKindOfClass:NSData.class] && [NSFileManager.defaultManager createDirectoryAtURL:workspace withIntermediateDirectories:YES attributes:nil error:&error] && [data writeToURL:source options:NSDataWritingAtomic error:&error];
        AVURLAsset *asset=ready ? [AVURLAsset URLAssetWithURL:source options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}] : nil;
        ready=ready && [asset tracksWithMediaType:AVMediaTypeAudio].count && asset.exportable && CMTimeGetSeconds(asset.duration)>0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ready) { [self finishCropWorkspace:workspace error:snapshot[@"error"] ?: error.localizedDescription ?: @"This ringtone could not be opened for cropping."]; return; }
            [self.cropHUD removeFromSuperview]; self.cropHUD=nil;
            IPCropController *editor=[[IPCropController alloc] initWithAsset:asset];
            [editor loadViewIfNeeded]; editor.navigationItem.rightBarButtonItem.title=@"Save Crop";
            editor.completion=^(BOOL accepted,CMTimeRange range){
                if (accepted) [self saveCropAsset:asset range:range tone:tone snapshot:snapshot workspace:workspace];
                else [self finishCropWorkspace:workspace error:nil];
            };
            UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:editor];
            navigation.modalPresentationStyle=UIModalPresentationPageSheet; navigation.modalInPresentation=YES;
            navigation.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];
            [self presentViewController:navigation animated:YES completion:nil];
        });
    });
}
- (void)renameTone:(NSDictionary *)tone {
    [self stopTonePreview];
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
    [self stopTonePreview];
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
    [self stopTonePreview];
    NSDictionary *tone = [specifier propertyForKey:@"importoneTone"];
    if (!tone || self.busy) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:tone[@"name"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self renameTone:tone]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Crop" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self cropTone:tone]; }]];
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
        NSDictionary *tone=[specifier propertyForKey:@"importoneTone"];
        if (tone) {
            UIButton *play=[UIButton buttonWithType:UIButtonTypeSystem]; play.frame=CGRectMake(0,0,44,44);
            [self configurePreviewButton:play tone:tone];
            __weak IPRootListController *weakSelf=self;
            [play addAction:[UIAction actionWithHandler:^(UIAction *action){ [weakSelf previewTone:tone]; }] forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView=play;
        }
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
    UIContextualAction *crop = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Crop" handler:^(UIContextualAction *action, UIView *view, void (^completion)(BOOL)){ completion(YES); [self cropTone:tone]; }];
    crop.backgroundColor = UIColor.systemPurpleColor;
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove, crop, rename]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
- (void)openSounds {
    [self stopTonePreview];
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
