#import <Foundation/Foundation.h>

#define API_VERSION "2.3"

@interface ShadowXPC : NSObject
- (NSDictionary *)handleMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
@end
