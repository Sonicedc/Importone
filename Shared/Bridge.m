#import "Bridge.h"
#import <dlfcn.h>
#import <rootless.h>
CPDistributedMessagingCenter *IPCenter(void) {
    static CPDistributedMessagingCenter *center; static dispatch_once_t once;
    dispatch_once(&once, ^{
        center = [CPDistributedMessagingCenter centerNamed:@"com.sonicedc.importoned"];
        void *library = dlopen(ROOT_PATH("/usr/lib/librocketbootstrap.dylib"), RTLD_NOW);
        void (*apply)(CPDistributedMessagingCenter *) = library ? dlsym(library, "rocketbootstrap_distributedmessagingcenter_apply") : NULL;
        if (apply) apply(center); else center = nil;
    }); return center;
}
BOOL IPEnabled(void) {
    CFPreferencesAppSynchronize(CFSTR("com.sonicedc.importone"));
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Enabled"), CFSTR("com.sonicedc.importone")));
    return value ? [value boolValue] : YES;
}
