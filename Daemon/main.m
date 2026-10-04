#import "../Shared/Bridge.h"
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <math.h>
#import <unistd.h>
@interface TLToneManager : NSObject
+ (instancetype)sharedToneManager;
- (void)importTone:(NSData *)data metadata:(NSDictionary *)metadata completionBlock:(void (^)(BOOL))completion;
@end
@interface IPService : NSObject
@property NSMutableDictionary *jobs;
@end
@implementation IPService
- (NSDictionary *)receive:(NSString *)message userInfo:(NSDictionary *)info {
    if ([message isEqual:@"ping"]) return @{@"ok":@YES, @"version":@"0.1.4"};
    if ([message isEqual:@"status"]) return ([info[@"job"] isKindOfClass:NSString.class] ? self.jobs[info[@"job"]] : nil) ?: @{@"done":@YES, @"ok":@NO, @"error":@"Import job expired."};
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
    @try { [manager importTone:data metadata:@{@"name":name} completionBlock:^(BOOL imported){
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = imported;
            if (!ok) [fm removeItemAtPath:path error:nil];
            self.jobs[job] = ok ? @{@"done":@YES, @"ok":@YES} : @{@"done":@YES, @"ok":@NO, @"error":@"ToneLibrary rejected this ringtone."};
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
    IPService *service = [IPService new]; service.jobs = [NSMutableDictionary new];
    IPMessageCenter *center = IPCenter(); if (!center) return 1;
    [center runServerOnCurrentThread];
    [center registerForMessageName:@"ping" target:service selector:@selector(receive:userInfo:)];
    [center registerForMessageName:@"import" target:service selector:@selector(receive:userInfo:)];
    [center registerForMessageName:@"status" target:service selector:@selector(receive:userInfo:)];
    [[NSRunLoop currentRunLoop] run];
} return 0; }
