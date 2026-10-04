#import <Foundation/Foundation.h>
extern NSString *IPSafeName(NSString *);
int main(void) { @autoreleasepool {
    NSArray *invalid = @[@"", @"   ", @".", @"..", @"../tone", @"a/b", @"a\\b", @"a:b", @"a\nb", @"a\0b", [@"x" stringByPaddingToLength:81 withString:@"x" startingAtIndex:0]];
    for (NSString *name in invalid) NSCAssert(IPSafeName(name) == nil, @"Accepted unsafe name: %@", name);
    NSCAssert([IPSafeName(@"  My Tone  ") isEqual:@"My Tone"], @"Trimming failed");
    NSCAssert([IPSafeName(@"着信音 🎵") isEqual:@"着信音 🎵"], @"Unicode failed");
    NSCAssert(IPSafeName([@"x" stringByPaddingToLength:80 withString:@"x" startingAtIndex:0]) != nil, @"Boundary failed");
    NSCAssert(IPSafeName(nil) == nil, @"nil accepted");
    puts("Filename validation passed (unsafe paths, control characters, Unicode, limits).");
} return 0; }
