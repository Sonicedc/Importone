#import "Bridge.h"
#import <rootless.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *IPQueuePath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/Importone/IPC");
}
static NSDictionary *IPReadPlist(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return nil;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != getuid() || st.st_size <= 0 || st.st_size > 11 * 1024 * 1024) { close(fd); return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)st.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t amount = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
        if (amount <= 0) { close(fd); return nil; }
        offset += amount;
    }
    close(fd);
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
    return [plist isKindOfClass:NSDictionary.class] ? plist : nil;
}
static BOOL IPWritePlist(NSDictionary *plist, NSString *path) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
@interface IPMessageCenter ()
@property NSMutableDictionary *targets;
@property NSMutableDictionary *selectors;
@property NSTimer *timer;
@end
@implementation IPMessageCenter
- (instancetype)init { if ((self = [super init])) { _targets = [NSMutableDictionary new]; _selectors = [NSMutableDictionary new]; } return self; }
- (NSDictionary *)sendMessageAndReceiveReplyName:(NSString *)name userInfo:(NSDictionary *)info {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *directory = [IPQueuePath() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]) return nil;
    if (!IPWritePlist(@{@"message":name, @"info":info}, [directory stringByAppendingPathComponent:@"request.plist"])) { [fm removeItemAtPath:directory error:nil]; return nil; }
    NSDictionary *reply;
    // Used only from background queues. The daemon polls every 0.2 seconds.
    for (NSUInteger attempt = 0; attempt < 150; attempt++) {
        reply = IPReadPlist([directory stringByAppendingPathComponent:@"reply.plist"]);
        if (reply) break;
        usleep(100000);
    }
    [fm removeItemAtPath:directory error:nil];
    return reply;
}
- (void)registerForMessageName:(NSString *)name target:(id)target selector:(SEL)selector {
    self.targets[name] = target; self.selectors[name] = NSStringFromSelector(selector);
}
- (void)runServerOnCurrentThread {
    [NSFileManager.defaultManager createDirectoryAtPath:IPQueuePath() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ [self drain]; }];
}
- (void)drain {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *children = [fm contentsOfDirectoryAtPath:IPQueuePath() error:nil];
    NSUInteger handled = 0;
    for (NSString *child in children) {
        if (![[NSUUID alloc] initWithUUIDString:child]) continue;
        NSString *directory = [IPQueuePath() stringByAppendingPathComponent:child];
        struct stat st;
        if (lstat(directory.fileSystemRepresentation, &st) || !S_ISDIR(st.st_mode) || st.st_uid != getuid()) continue;
        NSDictionary *attributes = [fm attributesOfItemAtPath:directory error:nil];
        if (-[attributes[NSFileModificationDate] timeIntervalSinceNow] > 90) { [fm removeItemAtPath:directory error:nil]; continue; }
        NSString *path = [directory stringByAppendingPathComponent:@"request.plist"];
        NSDictionary *request = IPReadPlist(path);
        if (!request) continue;
        [fm removeItemAtPath:path error:nil];
        NSString *message = request[@"message"]; NSDictionary *info = request[@"info"];
        NSDictionary *reply = @{@"error":@"Invalid import request."};
        if ([message isKindOfClass:NSString.class] && [info isKindOfClass:NSDictionary.class] && self.targets[message]) {
            id target = self.targets[message]; SEL selector = NSSelectorFromString(self.selectors[message]);
            NSDictionary *(*receive)(id, SEL, NSString *, NSDictionary *) = (void *)[target methodForSelector:selector];
            reply = receive(target, selector, message, info) ?: reply;
        }
        IPWritePlist(reply, [directory stringByAppendingPathComponent:@"reply.plist"]);
        if (++handled == 8) break;
    }
}
@end
IPMessageCenter *IPCenter(void) {
    static IPMessageCenter *center; static dispatch_once_t once;
    dispatch_once(&once, ^{ center = [IPMessageCenter new]; }); return center;
}
BOOL IPEnabled(void) {
    CFPreferencesAppSynchronize(CFSTR("com.sonicedc.importone"));
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), CFSTR("com.sonicedc.importone")));
    return value ? [value boolValue] : YES;
}
