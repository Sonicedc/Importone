#import <Foundation/Foundation.h>
@interface IPMessageCenter : NSObject
- (NSDictionary *)sendMessageAndReceiveReplyName:(NSString *)name userInfo:(NSDictionary *)info;
- (void)registerForMessageName:(NSString *)name target:(id)target selector:(SEL)selector;
- (void)runServerOnCurrentThread;
@end
#ifdef __cplusplus
extern "C" {
#endif
IPMessageCenter *IPCenter(void);
BOOL IPEnabled(void);
NSString *IPSafeName(NSString *name);
#ifdef __cplusplus
}
#endif
