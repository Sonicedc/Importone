#import "../Shared/Bridge.h"
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <math.h>
@interface TLToneManager : NSObject
+ (instancetype)sharedToneManager;
- (void)importTone:(NSData *)data metadata:(NSDictionary *)metadata completionBlock:(void (^)(NSString *, NSError *))completion;
@end
@interface IPService : NSObject
@property NSMutableDictionary *jobs;
@end
@implementation IPService
- (NSDictionary *)receive:(NSString *)message userInfo:(NSDictionary *)info {
    if ([message isEqual:@"status"]) return self.jobs[info[@"job"]] ?: @{@"done":@YES, @"ok":@NO, @"error":@"Import job expired."};
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
    @try { [manager importTone:data metadata:@{@"name":name} completionBlock:^(NSString *identifier, NSError *failure){
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL ok = [identifier isKindOfClass:NSString.class] && identifier.length && !failure;
            if (!ok) [fm removeItemAtPath:path error:nil];
            self.jobs[job] = ok ? @{@"done":@YES, @"ok":@YES} : @{@"done":@YES, @"ok":@NO, @"error":failure.localizedDescription ?: @"ToneLibrary rejected this ringtone."};
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
    IPService *service = [IPService new]; service.jobs = [NSMutableDictionary new];
    CPDistributedMessagingCenter *center = IPCenter(); if (!center) return 1;
    [center runServerOnCurrentThread];
    [center registerForMessageName:@"import" target:service selector:@selector(receive:userInfo:)];
    [center registerForMessageName:@"status" target:service selector:@selector(receive:userInfo:)];
    [[NSRunLoop currentRunLoop] run];
} return 0; }
