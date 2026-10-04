#import <Foundation/Foundation.h>
#import <AppSupport/CPDistributedMessagingCenter.h>
#ifdef __cplusplus
extern "C" {
#endif
CPDistributedMessagingCenter *IPCenter(void);
BOOL IPEnabled(void);
NSString *IPSafeName(NSString *name);

#ifdef __cplusplus
}
#endif
