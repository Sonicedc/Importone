#import <Foundation/Foundation.h>
NSString *IPSafeName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return nil;
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || name.length > 80 || [name isEqual:@"."] || [name isEqual:@".."] ||
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\:"]].location != NSNotFound ||
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    return name;
}
