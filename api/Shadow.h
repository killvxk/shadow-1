#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <pwd.h>

#import "ShadowService.h"

@interface Shadow : NSObject
- (BOOL)isCallerTweak:(NSArray*)backtrace;
- (BOOL)isCPathRestricted:(const char *)path;
- (BOOL)isPathRestricted:(NSString *)path;
- (BOOL)isPathRestricted:(NSString *)path resolve:(BOOL)resolve;
- (BOOL)isURLRestricted:(NSURL *)url;

- (void)setTweakCompatExtra:(BOOL)enabled;

+ (instancetype)shadowWithService:(ShadowService *)_service;
@end
