#import "ImportActivity.h"
#import "CropController.h"
#import "Shared/Bridge.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>
@interface IPImportController : UIViewController
@property UILabel *step;
@property UIActivityIndicatorView *spinner;
@property UIProgressView *progress;
@property NSURL *source;
@property NSItemProvider *provider;
@property NSURL *materializedDirectory;
@property BOOL started;
@property NSURL *workspace;
@property NSURL *converted;
@property AVAssetExportSession *exporter;
@property NSTimer *timer;
@property (copy) void (^finished)(BOOL);
@end
@implementation IPImportController
- (void)viewDidLoad {
    [super viewDidLoad]; self.modalInPresentation = YES;
    self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.12];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.layer.cornerRadius = 24; blur.layer.cornerCurve = kCACornerCurveContinuous; blur.clipsToBounds = YES;
    [self.view addSubview:blur];
    [NSLayoutConstraint activateConstraints:@[[blur.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [blur.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor], [blur.widthAnchor constraintEqualToConstant:220], [blur.heightAnchor constraintEqualToConstant:220]]];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.step = [UILabel new]; self.step.textAlignment = NSTextAlignmentCenter; self.step.numberOfLines = 3; self.step.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.progress = [UIProgressView new];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.spinner, self.step, self.progress]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [blur.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:blur.contentView.centerXAnchor], [stack.centerYAnchor constraintEqualToAnchor:blur.contentView.centerYAnchor], [stack.widthAnchor constraintEqualToConstant:176]]];
    [self.spinner startAnimating]; self.step.text = @"Checking audio…";
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.started) return;
    self.started = YES;
    if (self.provider) [self resolveProvider]; else [self start];
}
- (void)resolveProvider {
    self.step.text = @"Loading audio file…";
    self.materializedDirectory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSError *error;
    if (![NSFileManager.defaultManager createDirectoryAtURL:self.materializedDirectory withIntermediateDirectories:YES attributes:nil error:&error]) { [self fail:error.localizedDescription]; return; }
    NSString *type;
    for (NSString *identifier in self.provider.registeredTypeIdentifiers) {
        if ([[UTType typeWithIdentifier:identifier] conformsToType:UTTypeAudio]) { type = identifier; break; }
    }
    void (^received)(NSURL *, NSError *) = ^(NSURL *url, NSError *failure){
        if (!url || failure) { [self fail:failure.localizedDescription ?: @"The shared file could not be loaded."]; return; }
        BOOL scoped = [url startAccessingSecurityScopedResource];
        __block NSError *copyError; NSError *coordinationError;
        NSString *filename = url.lastPathComponent;
        if (!filename.length) filename = @"Audio.m4a";
        NSURL *local = [self.materializedDirectory URLByAppendingPathComponent:filename];
        [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readingURL){
            NSNumber *size; [readingURL getResourceValue:&size forKey:NSURLFileSizeKey error:&copyError];
            if (size.unsignedLongLongValue > 100 * 1024 * 1024) { copyError = [NSError errorWithDomain:@"Importone" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Choose an audio file smaller than 100 MB."}]; return; }
            [NSFileManager.defaultManager copyItemAtURL:readingURL toURL:local error:&copyError];
        }];
        if (scoped) [url stopAccessingSecurityScopedResource];
        if (coordinationError || copyError) { [self fail:(coordinationError ?: copyError).localizedDescription]; return; }
        dispatch_async(dispatch_get_main_queue(), ^{ self.source = local; [self start]; });
    };
    if (type || [self.provider hasItemConformingToTypeIdentifier:UTTypeData.identifier]) {
        [self.provider loadFileRepresentationForTypeIdentifier:type ?: UTTypeData.identifier completionHandler:received];
    } else {
        [self.provider loadItemForTypeIdentifier:UTTypeFileURL.identifier options:nil completionHandler:^(id item, NSError *failure){
            received([item isKindOfClass:NSURL.class] ? item : nil, failure);
        }];
    }
}
- (void)finish:(BOOL)success {
    [self.timer invalidate]; self.timer = nil; [self.exporter cancelExport];
    if (self.workspace) [[NSFileManager defaultManager] removeItemAtURL:self.workspace error:nil];
    if (self.materializedDirectory) [[NSFileManager defaultManager] removeItemAtURL:self.materializedDirectory error:nil];
    [self dismissViewControllerAnimated:YES completion:^{ if (self.finished) self.finished(success); }];
}
- (void)fail:(NSString *)message {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self fail:message]; }); return; }
    [self.timer invalidate]; self.timer = nil; [self.spinner stopAnimating];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Importone" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [self finish:NO]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)start {
    self.workspace = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error; NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:self.workspace withIntermediateDirectories:YES attributes:nil error:&error]) { [self fail:error.localizedDescription]; return; }
    BOOL scoped = [self.source startAccessingSecurityScopedResource];
    NSURL *local = [self.workspace URLByAppendingPathComponent:self.source.lastPathComponent];
    __block NSError *copyError;
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateReadingItemAtURL:self.source options:0 error:&error byAccessor:^(NSURL *url){
        NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:&copyError];
        if (size.unsignedLongLongValue > 100 * 1024 * 1024) { copyError = [NSError errorWithDomain:@"Importone" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Choose an audio file smaller than 100 MB."}]; return; }
        [fm copyItemAtURL:url toURL:local error:&copyError];
    }];
    if (scoped) [self.source stopAccessingSecurityScopedResource];
    if (error || copyError) { [self fail:(error ?: copyError).localizedDescription]; return; }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:local options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration", @"exportable"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *loadError;
            for (NSString *key in @[@"tracks", @"duration", @"exportable"]) if ([asset statusOfValueForKey:key error:&loadError] != AVKeyValueStatusLoaded) { [self fail:loadError.localizedDescription ?: @"Cannot read this file."]; return; }
            double seconds = CMTimeGetSeconds(asset.duration);
            if (![asset tracksWithMediaType:AVMediaTypeAudio].count || [asset tracksWithMediaType:AVMediaTypeVideo].count || !isfinite(seconds) || seconds <= 0 || asset.hasProtectedContent) { [self fail:@"Choose a readable, unprotected audio file. Video files are not supported."]; return; }
            if (seconds > 40) {
                self.step.text = @"Choose your ringtone selection"; [self.spinner stopAnimating];
                IPCropController *crop = [[IPCropController alloc] initWithAsset:asset];
                __weak IPImportController *weakSelf = self;
                crop.completion = ^(BOOL accepted, CMTimeRange range){
                    IPImportController *controller = weakSelf;
                    if (!accepted) { [controller finish:NO]; return; }
                    [controller convertAsset:asset range:range];
                };
                UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:crop];
                navigation.modalPresentationStyle = UIModalPresentationPageSheet; navigation.modalInPresentation = YES;
                navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
                navigation.sheetPresentationController.prefersGrabberVisible = YES;
                [self presentViewController:navigation animated:YES completion:nil];
                return;
            }
            if ([local.pathExtension.lowercaseString isEqual:@"m4r"]) { self.converted = local; [self rename]; return; }
            [self convertAsset:asset range:kCMTimeRangeInvalid];
        });
    }];
    });
}
- (void)convertAsset:(AVAsset *)asset range:(CMTimeRange)range {
    self.step.text = CMTIMERANGE_IS_VALID(range) ? @"Cropping and converting to .m4r…" : @"Converting to .m4r…";
    self.progress.progress = 0; [self.spinner startAnimating];
    self.exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!self.exporter || ![self.exporter.supportedFileTypes containsObject:AVFileTypeAppleM4A]) { [self fail:@"This audio format cannot be converted on this device."]; return; }
    if (CMTIMERANGE_IS_VALID(range)) self.exporter.timeRange = range;
    self.converted = [self.workspace URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"m4r"]];
    self.exporter.outputURL = self.converted; self.exporter.outputFileType = AVFileTypeAppleM4A;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer){ self.progress.progress = self.exporter.progress; }];
    [self.exporter exportAsynchronouslyWithCompletionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{
        [self.timer invalidate]; self.timer = nil;
        if (self.exporter.status != AVAssetExportSessionStatusCompleted) { [self fail:self.exporter.error.localizedDescription ?: @"Conversion failed."]; return; }
        [self rename];
    }); }];
}
- (void)rename {
    self.step.text = @"Name your ringtone"; self.progress.progress = 1; [self.spinner stopAnimating];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Ringtone" message:@"Enter a name (up to 80 characters). Existing ringtones will never be replaced." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){ field.text = self.source.lastPathComponent.stringByDeletingPathExtension; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ [self finish:NO]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *name = IPSafeName(alert.textFields.firstObject.text);
        if (!name) { [self fail:@"Use 1–80 characters without slashes, colons, or control characters."]; return; }
        self.step.text = @"Installing ringtone…"; [self.spinner startAnimating];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:self.converted];
            if (data.length > 10 * 1024 * 1024) { dispatch_async(dispatch_get_main_queue(), ^{ [self fail:@"The resulting ringtone exceeds 10 MB."]; }); return; }
            NSDictionary *reply = data ? [IPCenter() sendMessageAndReceiveReplyName:@"import" userInfo:@{@"name":name, @"data":data}] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (![reply[@"ok"] boolValue]) { [self fail:reply[@"error"] ?: @"The import service is unavailable. Restart the app and reinstall Importone if needed."]; return; }
                self.step.text = @"Registering with iOS…";
                __block NSUInteger polls = 0;
                self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer){
                    if (++polls > 120) { [self fail:@"iOS did not finish registering the tone. Check Settings before retrying."]; return; }
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                        NSDictionary *status = [IPCenter() sendMessageAndReceiveReplyName:@"status" userInfo:@{@"job":reply[@"job"]}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (!self.timer || ![status[@"done"] boolValue]) return;
                            [self.timer invalidate]; self.timer = nil;
                            if (![status[@"ok"] boolValue]) { [self fail:status[@"error"] ?: @"iOS rejected the ringtone."]; return; }
                            [self.spinner stopAnimating]; self.step.text = @"Ringtone imported";
                            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"Ringtone Imported" message:@"Select it in Settings → Sounds & Haptics → Ringtone." preferredStyle:UIAlertControllerStyleAlert];
                            [done addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [self finish:YES]; }]];
                            [self presentViewController:done animated:YES completion:nil];
                        });
                    });
                }];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
@interface IPImportActivity ()
@property NSURL *source;
@property NSItemProvider *provider;
@property IPImportController *controller;
@end
@implementation IPImportActivity
+ (UIActivityCategory)activityCategory { return UIActivityCategoryAction; }
- (UIActivityType)activityType { return @"com.sonicedc.importone.import"; }
- (NSString *)activityTitle { return @"Importone"; }
- (UIImage *)activityImage { return [UIImage systemImageNamed:@"bell.badge.fill"]; }
- (BOOL)isAudioCandidate:(id)item {
    if ([item isKindOfClass:NSURL.class] && [item isFileURL]) {
        UTType *type = [UTType typeWithFilenameExtension:[item pathExtension]];
        return [type conformsToType:UTTypeAudio] || [[item pathExtension] caseInsensitiveCompare:@"m4r"] == NSOrderedSame;
    }
    if ([item isKindOfClass:NSItemProvider.class]) {
        NSItemProvider *provider = item;
        if ([provider hasItemConformingToTypeIdentifier:UTTypeAudio.identifier]) return YES;
        UTType *type = [UTType typeWithFilenameExtension:provider.suggestedName.pathExtension];
        if ([type conformsToType:UTTypeAudio] || [provider.suggestedName.pathExtension.lowercaseString isEqual:@"m4r"]) return YES;
        // Generic file-URL providers are validated from their actual contents after loading.
        return [provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier];
    }
    return NO;
}
- (BOOL)canPerformWithActivityItems:(NSArray *)items {
    if (!IPEnabled()) return NO;
    NSUInteger count = 0;
    for (id item in self.providedItems ?: items) if ([self isAudioCandidate:item]) count++;
    return count == 1;
}
- (void)prepareWithActivityItems:(NSArray *)items {
    self.source = nil; self.provider = nil;
    for (id item in self.providedItems ?: items) if ([self isAudioCandidate:item]) {
        if ([item isKindOfClass:NSURL.class]) self.source = item; else self.provider = item;
        break;
    }
}
- (UIViewController *)activityViewController {
    self.controller = [IPImportController new]; self.controller.modalPresentationStyle = UIModalPresentationOverFullScreen; self.controller.source = self.source; self.controller.provider = self.provider;
    __weak IPImportActivity *weakSelf = self;
    self.controller.finished = ^(BOOL success){ [weakSelf activityDidFinish:success]; };
    return self.controller;
}
@end
