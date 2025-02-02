#import <Foundation/Foundation.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

#import <AltList/ATLApplicationListSubcontroller.h>
#import <HBLog.h>
#import "../api/ShadowService.h"

@interface SHDWAppListController : ATLApplicationListSubcontroller
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier *)specifier;
@end
