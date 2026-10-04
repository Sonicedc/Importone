#import "../Shared/Bridge.h"
#import "../Shared/ToneUsage.h"
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <math.h>
#import <unistd.h>
#import <rootless.h>
#import <CommonCrypto/CommonDigest.h>
#import <stdio.h>
@interface TLToneManager : NSObject
+ (instancetype)sharedToneManager;
- (NSArray *)_installedTones;
- (NSString *)_deviceITunesRingtoneDirectory;
- (NSString *)_deviceITunesRingtoneInformationPlist;
- (id)_addToneToManifestAtPath:(NSString *)path metadata:(NSDictionary *)metadata fileName:(NSString *)filename mediaDirectory:(NSString *)directory;
- (void)_reloadTonesAfterExternalChange;
- (void)removeImportedToneWithIdentifier:(NSString *)identifier;
- (BOOL)toneWithIdentifierIsValid:(NSString *)identifier;
- (void)importTone:(NSData *)data metadata:(NSDictionary *)metadata completionBlock:(void (^)(BOOL))completion;
@end
static void IPUpdateCatalog(TLToneManager *manager) {
    [manager _reloadTonesAfterExternalChange];
    NSMutableArray *catalog = [NSMutableArray new];
    for (id tone in [manager _installedTones]) {
        NSString *name = [tone valueForKey:@"name"], *identifier = [tone valueForKey:@"identifier"];
        if (!IPSafeName(name) || ![identifier isKindOfClass:NSString.class]) continue;
        NSString *path = [@"/var/lib/ringtones" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m4r"]];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) [catalog addObject:@{@"name":name, @"identifier":identifier}];
    }
    [catalog sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){ return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
    [catalog writeToFile:ROOT_PATH_NS(@"/var/mobile/Library/Importone/CustomTones.plist") atomically:YES];
}
static void IPRepairMetadata(TLToneManager *manager) {
    NSString *manifest = [manager _deviceITunesRingtoneInformationPlist];
    NSDictionary *entries = [NSDictionary dictionaryWithContentsOfFile:manifest][@"Ringtones"];
    if (![entries isKindOfClass:NSDictionary.class]) return;
    for (NSString *filename in entries) {
        NSDictionary *entry = entries[filename];
        if (![entry isKindOfClass:NSDictionary.class] || entry[@"Name"]) continue;
        NSString *name = IPSafeName(entry[@"name"]);
        NSString *source = name ? [@"/var/lib/ringtones" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m4r"]] : nil;
        if (!source || ![NSFileManager.defaultManager fileExistsAtPath:source]) continue;
        NSMutableDictionary *metadata = [entry mutableCopy]; metadata[@"Name"] = name; [metadata removeObjectForKey:@"name"];
        [manager _addToneToManifestAtPath:manifest metadata:metadata fileName:filename mediaDirectory:[manager _deviceITunesRingtoneDirectory]];
    }
}
static NSString *IPDigest(NSData *data) {
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString new]; for (NSUInteger i=0;i<sizeof(digest);i++) [hex appendFormat:@"%02x",digest[i]]; return hex;
}
static NSDictionary *IPEditTone(NSString *message,NSDictionary *info,TLToneManager *manager,NSDictionary *owned,NSString *source) {
    NSString *identifier=owned[@"identifier"],*manifest=[manager _deviceITunesRingtoneInformationPlist];
    NSDictionary *entries=[NSDictionary dictionaryWithContentsOfFile:manifest][@"Ringtones"];
    NSString *filename; NSDictionary *metadata;
    for (NSString *key in entries) {
        NSDictionary *entry=entries[key];
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"GUID"] isKindOfClass:NSString.class] && [[@"itunes:" stringByAppendingString:entry[@"GUID"]] isEqual:identifier]) { filename=key; metadata=entry; break; }
    }
    if (!filename || ![filename.lastPathComponent isEqual:filename]) return @{@"error":@"iOS could not find the ringtone registration."};
    NSString *native=[[manager _deviceITunesRingtoneDirectory] stringByAppendingPathComponent:filename];
    NSData *original=[NSData dataWithContentsOfFile:source],*nativeOriginal=[NSData dataWithContentsOfFile:native];
    if (!original.length || !nativeOriginal.length) return @{@"error":@"The ringtone audio is missing."};
    if ([message isEqual:@"readTone"]) return @{@"ok":@YES,@"data":original,@"revision":IPDigest(original),@"nativeRevision":IPDigest(nativeOriginal),@"name":owned[@"name"]};
    if (![IPDigest(original) isEqual:info[@"revision"]] || ![IPDigest(nativeOriginal) isEqual:info[@"nativeRevision"]]) return @{@"error":@"This ringtone changed while you were editing it. Open Crop again to edit the latest audio."};
    NSData *data=info[@"data"];
    if (![data isKindOfClass:NSData.class] || data.length<12 || data.length>10*1024*1024 || memcmp((const char *)data.bytes+4,"ftyp",4)) return @{@"error":@"The crop must be MPEG-4 audio smaller than 10 MB."};
    NSFileManager *fm=NSFileManager.defaultManager; NSString *token=NSUUID.UUID.UUIDString;
    NSString *candidate=[source.stringByDeletingLastPathComponent stringByAppendingPathComponent:[token stringByAppendingPathExtension:@"m4r"]];
    NSString *nativeCandidate=[native stringByAppendingFormat:@".%@.new",token];
    NSString *sourceBackup=[source stringByAppendingFormat:@".%@.backup",token],*nativeBackup=[native stringByAppendingFormat:@".%@.backup",token];
    NSError *error; BOOL ok=[data writeToFile:candidate options:NSDataWritingWithoutOverwriting error:&error];
    AVURLAsset *asset=ok ? [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:candidate] options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}] : nil;
    double duration=asset ? CMTimeGetSeconds(asset.duration) : 0;
    if (!ok || ![asset tracksWithMediaType:AVMediaTypeAudio].count || [asset tracksWithMediaType:AVMediaTypeVideo].count || !isfinite(duration) || duration<=0 || duration>40.05 || asset.hasProtectedContent) {
        [fm removeItemAtPath:candidate error:nil]; return @{@"error":@"The cropped ringtone must be valid audio of at most 40 seconds."};
    }
    // Prepare both replacements and backups before touching either registered file.
    ok=[data writeToFile:nativeCandidate options:NSDataWritingWithoutOverwriting error:&error] &&
        [fm copyItemAtPath:source toPath:sourceBackup error:&error] && [fm copyItemAtPath:native toPath:nativeBackup error:&error];
    for (NSString *path in @[candidate,nativeCandidate]) [fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:nil];
    BOOL nativeReplaced=NO,sourceReplaced=NO;
    if (ok) {
        nativeReplaced=rename(nativeCandidate.fileSystemRepresentation,native.fileSystemRepresentation)==0;
        sourceReplaced=nativeReplaced && rename(candidate.fileSystemRepresentation,source.fileSystemRepresentation)==0;
        ok=sourceReplaced;
    }
    if (ok) {
        @try {
            [manager _addToneToManifestAtPath:manifest metadata:metadata fileName:filename mediaDirectory:[manager _deviceITunesRingtoneDirectory]];
            [manager _reloadTonesAfterExternalChange]; ok=[manager toneWithIdentifierIsValid:identifier];
        } @catch (NSException *exception) { ok=NO; }
    }
    BOOL restored=YES;
    if (!ok) {
        if (nativeReplaced) restored=rename(nativeBackup.fileSystemRepresentation,native.fileSystemRepresentation)==0;
        if (sourceReplaced) restored=(rename(sourceBackup.fileSystemRepresentation,source.fileSystemRepresentation)==0) && restored;
        [manager _reloadTonesAfterExternalChange];
    }
    for (NSString *path in @[candidate,nativeCandidate]) [fm removeItemAtPath:path error:nil];
    if (ok || restored) for (NSString *path in @[sourceBackup,nativeBackup]) [fm removeItemAtPath:path error:nil];
    IPUpdateCatalog(manager);
    return ok ? @{@"ok":@YES,@"identifier":identifier,@"name":owned[@"name"]} : @{@"error":restored ? @"The crop could not be saved. Your original ringtone was kept." : @"The crop could not be saved completely. Recovery copies were retained; please contact the developer."};
}
static NSDictionary *IPManageTone(NSString *message, NSDictionary *info) {
    TLToneManager *manager = [NSClassFromString(@"TLToneManager") sharedToneManager];
    IPUpdateCatalog(manager);
    NSArray *catalog = [NSArray arrayWithContentsOfFile:ROOT_PATH_NS(@"/var/mobile/Library/Importone/CustomTones.plist")] ?: @[];
    if ([message isEqual:@"list"]) return @{@"ok":@YES, @"tones":catalog};
    NSDictionary *owned;
    for (NSDictionary *tone in catalog) if ([tone[@"identifier"] isEqual:info[@"identifier"]]) { owned = tone; break; }
    if (!owned) return @{@"error":@"This custom ringtone no longer exists. Refresh the list and try again."};
    NSString *oldName = owned[@"name"], *identifier = owned[@"identifier"];
    NSString *source = [@"/var/lib/ringtones" stringByAppendingPathComponent:[oldName stringByAppendingPathExtension:@"m4r"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([@[@"readTone", @"replace"] containsObject:message]) return IPEditTone(message,info,manager,owned,source);
    if ([@[@"canRemove", @"remove"] containsObject:message]) {
        NSString *reason = IPToneRemovalError(manager, identifier);
        if (reason) return @{@"error":reason};
        if ([message isEqual:@"canRemove"]) return @{@"ok":@YES};
    }
    if ([message isEqual:@"remove"]) {
        [manager removeImportedToneWithIdentifier:identifier];
        [manager _reloadTonesAfterExternalChange];
        if ([manager toneWithIdentifierIsValid:identifier]) return @{@"error":@"iOS could not remove the ringtone. Please try again."};
        NSError *error = nil;
        BOOL removed = [fm removeItemAtPath:source error:&error];
        IPUpdateCatalog(manager);
        return removed ? @{@"ok":@YES} : @{@"error":error.localizedDescription ?: @"Could not remove the stored audio file."};
    }
    NSString *name = IPSafeName(info[@"name"]);
    if (!name) return @{@"error":@"Use a name of 1–80 characters without slashes, colons, or control characters."};
    if ([name isEqual:oldName]) return @{@"ok":@YES};
    for (id tone in [manager _installedTones]) if ([[tone valueForKey:@"name"] caseInsensitiveCompare:name] == NSOrderedSame) return @{@"error":@"A ringtone with this name already exists."};
    NSString *manifest = [manager _deviceITunesRingtoneInformationPlist];
    NSDictionary *entries = [NSDictionary dictionaryWithContentsOfFile:manifest][@"Ringtones"];
    NSString *filename; NSDictionary *original;
    for (NSString *key in entries) {
        NSDictionary *entry = entries[key];
        if ([entry isKindOfClass:NSDictionary.class] && [[@"itunes:" stringByAppendingString:entry[@"GUID"] ?: @""] isEqual:identifier]) { filename = key; original = entry; break; }
    }
    if (!filename) return @{@"error":@"iOS could not find the ringtone registration."};
    NSString *destination = [@"/var/lib/ringtones" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m4r"]];
    NSError *error = nil;
    if (![fm moveItemAtPath:source toPath:destination error:&error]) return @{@"error":@"A file with this name already exists, or the ringtone could not be renamed."};
    BOOL renamed = NO;
    @try {
        NSMutableDictionary *metadata = [original mutableCopy]; metadata[@"Name"] = name;
        [manager _addToneToManifestAtPath:manifest metadata:metadata fileName:filename mediaDirectory:[manager _deviceITunesRingtoneDirectory]];
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:manifest][@"Ringtones"][filename];
        renamed = [saved[@"Name"] isEqual:name] && [saved[@"GUID"] isEqual:original[@"GUID"]];
    } @catch (NSException *exception) { NSLog(@"Importone rename failed: %@", exception.reason); }
    if (!renamed) {
        [fm moveItemAtPath:destination toPath:source error:nil];
        [manager _addToneToManifestAtPath:manifest metadata:original fileName:filename mediaDirectory:[manager _deviceITunesRingtoneDirectory]];
    }
    IPUpdateCatalog(manager);
    return renamed ? @{@"ok":@YES} : @{@"error":@"iOS could not rename the ringtone. Its original name was restored."};
}
@interface IPService : NSObject
@property NSMutableDictionary *jobs;
@end
@implementation IPService
- (NSDictionary *)receive:(NSString *)message userInfo:(NSDictionary *)info {
    if ([message isEqual:@"ping"]) return @{@"ok":@YES, @"version":@"0.3.0"};
    if ([message isEqual:@"status"]) return ([info[@"job"] isKindOfClass:NSString.class] ? self.jobs[info[@"job"]] : nil) ?: @{@"done":@YES, @"ok":@NO, @"error":@"Import job expired."};
    if ([@[@"list", @"rename", @"remove", @"canRemove", @"readTone", @"replace"] containsObject:message]) return IPManageTone(message, info);
    if (![message isEqual:@"import"]) return @{@"error":@"Unknown request."};
    if (!IPEnabled()) return @{@"error":@"Importone is disabled."};
    NSString *name = IPSafeName(info[@"name"]); NSData *data = info[@"data"];
    if (!name || ![data isKindOfClass:NSData.class] || !data.length || data.length > 10 * 1024 * 1024) return @{@"error":@"Invalid ringtone or ringtone exceeds 10 MB."};
    NSString *directory = @"/var/lib/ringtones";
    NSFileManager *fm = NSFileManager.defaultManager; NSError *error;
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) return @{@"error":error.localizedDescription};
    NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"m4r"]];
    if (![data writeToFile:path options:NSDataWritingWithoutOverwriting error:&error]) return @{@"error":@"A ringtone with this name already exists, or the storage directory is not writable."};
    NSURL *url = [NSURL fileURLWithPath:path]; AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    double duration = CMTimeGetSeconds(asset.duration);
    if (![asset tracksWithMediaType:AVMediaTypeAudio].count || [asset tracksWithMediaType:AVMediaTypeVideo].count || !isfinite(duration) || duration <= 0 || duration > 40.05 || asset.hasProtectedContent) { [fm removeItemAtPath:path error:nil]; return @{@"error":@"The ringtone is not valid audio of at most 40 seconds."}; }
    // Verify the container: .m4r must be MPEG-4 audio, not a renamed MP3/WAV.
    const unsigned char *bytes = data.bytes;
    if (data.length < 12 || memcmp(bytes + 4, "ftyp", 4)) { [fm removeItemAtPath:path error:nil]; return @{@"error":@"An .m4r file must contain MPEG-4 audio."}; }
    id manager = [NSClassFromString(@"TLToneManager") sharedToneManager];
    if (![manager respondsToSelector:@selector(importTone:metadata:completionBlock:)]) { [fm removeItemAtPath:path error:nil]; return @{@"error":@"This iOS version does not expose the required ToneLibrary importer."}; }
    if (self.jobs.count >= 100) [self.jobs removeAllObjects];
    NSString *job = NSUUID.UUID.UUIDString; self.jobs[job] = @{@"done":@NO};
    @try { [manager importTone:data metadata:@{@"Name":name} completionBlock:^(BOOL imported){
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = imported;
            if (ok) {
                IPUpdateCatalog(manager);
                BOOL listed = NO;
                for (NSDictionary *tone in [NSArray arrayWithContentsOfFile:ROOT_PATH_NS(@"/var/mobile/Library/Importone/CustomTones.plist")]) if ([tone[@"name"] isEqual:name]) { listed = YES; break; }
                ok = listed;
            }
            if (!ok) [fm removeItemAtPath:path error:nil];
            self.jobs[job] = ok ? @{@"done":@YES, @"ok":@YES} : @{@"done":@YES, @"ok":@NO, @"error":@"iOS did not register a selectable ringtone. Please retry."};
        });
    }]; } @catch (NSException *exception) {
        [fm removeItemAtPath:path error:nil];
        self.jobs[job] = @{@"done":@YES, @"ok":@NO, @"error":@"The ToneLibrary importer is incompatible with this iOS version."};
    }
    return @{@"ok":@YES, @"job":job};
}
@end
int main(int argc, char **argv) { @autoreleasepool {
    dlopen("/System/Library/PrivateFrameworks/ToneLibrary.framework/ToneLibrary", RTLD_NOW);
    if (argc >= 2 && !strcmp(argv[1], "--verify")) {
        id manager = [NSClassFromString(@"TLToneManager") sharedToneManager];
        for (NSString *key in @[@"_iTunesRingtoneDirectory", @"_deviceITunesRingtoneDirectory", @"_iTunesRingtoneInformationPlist", @"_deviceITunesRingtoneInformationPlist"]) {
            @try { printf("%s: %s\n", key.UTF8String, [[[manager valueForKey:key] description] UTF8String]); } @catch (NSException *e) {}
        }
        return 0;
    }
    if (argc >= 2 && !strcmp(argv[1], "--check")) {
        NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:@"ping" userInfo:@{}];
        printf("%s\n", [reply.description UTF8String] ?: "No service reply"); return [reply[@"ok"] boolValue] ? 0 : 1;
    }
    if (argc >= 3 && !strcmp(argv[1], "--manage")) {
        NSMutableDictionary *info = [NSMutableDictionary new];
        if (argc >= 4) info[@"identifier"] = [NSString stringWithUTF8String:argv[3]];
        if (argc >= 5) info[@"name"] = [NSString stringWithUTF8String:argv[4]];
        NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:[NSString stringWithUTF8String:argv[2]] userInfo:info];
        printf("%s\n", reply.description.UTF8String ?: "No reply"); return [reply[@"ok"] boolValue] ? 0 : 1;
    }
    if (argc == 4 && !strcmp(argv[1], "--import")) {
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        if (!data) return 1;
        NSDictionary *reply = [IPCenter() sendMessageAndReceiveReplyName:@"import" userInfo:@{@"name":[NSString stringWithUTF8String:argv[3]], @"data":data}];
        if (![reply[@"ok"] boolValue]) { printf("%s\n", [reply.description UTF8String] ?: "No reply"); return 1; }
        for (int i=0;i<120;i++) {
            usleep(500000);
            NSDictionary *status = [IPCenter() sendMessageAndReceiveReplyName:@"status" userInfo:@{@"job":reply[@"job"]}];
            if ([status[@"done"] boolValue]) { printf("%s\n", [status.description UTF8String]); return [status[@"ok"] boolValue] ? 0 : 1; }
        }
        return 1;
    }
    TLToneManager *manager = [NSClassFromString(@"TLToneManager") sharedToneManager];
    @try { IPRepairMetadata(manager); IPUpdateCatalog(manager); } @catch (NSException *exception) { NSLog(@"Importone metadata migration failed: %@", exception.reason); }
    IPService *service = [IPService new]; service.jobs = [NSMutableDictionary new];
    IPMessageCenter *center = IPCenter(); if (!center) return 1;
    [center runServerOnCurrentThread];
    [center registerForMessageName:@"ping" target:service selector:@selector(receive:userInfo:)];
    [center registerForMessageName:@"import" target:service selector:@selector(receive:userInfo:)];
    [center registerForMessageName:@"status" target:service selector:@selector(receive:userInfo:)];
    for (NSString *message in @[@"list", @"rename", @"remove", @"canRemove", @"readTone", @"replace"]) [center registerForMessageName:message target:service selector:@selector(receive:userInfo:)];
    [[NSRunLoop currentRunLoop] run];
} return 0; }
