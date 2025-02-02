#import "ShadowService.h"

#import <AppSupport/CPDistributedMessagingCenter.h>

#import "../apple_priv/NSTask.h"

@implementation ShadowService {
    NSCache* responseCache;
    NSString* dpkgPath;

    CPDistributedMessagingCenter* center;
    NSSet* dpkgInstalledDb;
    NSSet* dpkgExceptionDb;
}

- (BOOL)isPathRestricted_internal:(NSString *)path {
    if(!path || [path isEqualToString:@"/"] || [path isEqualToString:@""]) {
        return NO;
    }

    // Check response cache for given path.
    NSNumber* responseCachePath = [responseCache objectForKey:path];

    if(responseCachePath) {
        return [responseCachePath boolValue];
    }

    BOOL restricted = NO;

    NSArray* base_extra = @[
        @"/Library/Application Support",
        @"/usr/lib"
    ];

    if(!restricted && dpkgInstalledDb) {
        // Local service - filter using dpkgInstalledDb and dpkgExceptionDb
        restricted = [dpkgInstalledDb containsObject:path];

        if(restricted && dpkgExceptionDb) {
            restricted = !([dpkgExceptionDb containsObject:path] || [base_extra containsObject:path]);
        }
    }

    if(!restricted && dpkgPath) {
        // Call dpkg to see if file is part of any installed packages on the system.
        NSTask* task = [NSTask new];
        NSPipe* stdoutPipe = [NSPipe new];

        [task setLaunchPath:dpkgPath];
        [task setArguments:@[@"--no-pager", @"-S", path]];
        [task setStandardOutput:stdoutPipe];
        [task launch];
        [task waitUntilExit];

        NSLog(@"%@: %@", @"dpkg", path);

        if([task terminationStatus] == 0) {
            // Path found in dpkg database - exclude if base package is part of the package list.
            NSData* data = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
            NSString* output = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
            NSArray* lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

            for(NSString* line in lines) {
                NSArray* line_split = [line componentsSeparatedByString:@": "];

                if([line_split count] == 2) {
                    NSString* line_packages = line_split[0];

                    if([line_packages hasPrefix:@"local diversion"]) {
                        continue;
                    }

                    NSString* line_path = line_split[1];
                    NSArray* line_packages_split = [line_packages componentsSeparatedByString:@", "];

                    BOOL exception = [line_packages_split containsObject:@"base"] || [line_packages_split containsObject:@"firmware-sbin"];

                    if(!exception) {
                        if([base_extra containsObject:line_path]) {
                            exception = YES;
                        }
                    }

                    restricted = !exception;
                    [responseCache setObject:@(restricted) forKey:line_path];
                }
            }
        }
    }

    if(!restricted) {
        // Recurse call into parent directories.
        NSString* pathParent = [path stringByDeletingLastPathComponent];

        if(![pathParent isEqualToString:@"/"]) {
            BOOL isParentPathRestricted = [self isPathRestricted_internal:pathParent];

            if(isParentPathRestricted) {
                restricted = YES;
            }
        }
    }

    [responseCache setObject:@(restricted) forKey:path];
    return restricted;
}

- (NSArray*)getURLSchemes_internal {
    if([responseCache objectForKey:@"schemes"]) {
        return [responseCache objectForKey:@"schemes"];
    }

    NSMutableSet* schemes = [NSMutableSet new];

    // Local service - load using dpkgInstalledDb
    if(dpkgInstalledDb) {
        for(NSString* path_installed in dpkgInstalledDb) {
            if([path_installed hasSuffix:@"app/Info.plist"]) {
                NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:path_installed];

                if(plist && plist[@"CFBundleURLTypes"]) {
                    for(NSDictionary* type in plist[@"CFBundleURLTypes"]) {
                        if(type[@"CFBundleURLSchemes"]) {
                            for(NSString* scheme in type[@"CFBundleURLSchemes"]) {
                                [schemes addObject:scheme];
                            }
                        }
                    }
                }
            }
        }
    }

    if(dpkgPath) {
        NSTask* task = [NSTask new];
        NSPipe* stdoutPipe = [NSPipe new];

        [task setLaunchPath:dpkgPath];
        [task setArguments:@[@"--no-pager", @"-S", @"app/Info.plist"]];
        [task setStandardOutput:stdoutPipe];
        [task launch];
        [task waitUntilExit];

        if([task terminationStatus] == 0) {
            NSData* data = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
            NSString* output = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];

            NSCharacterSet* separator = [NSCharacterSet newlineCharacterSet];
            NSArray<NSString *>* lines = [output componentsSeparatedByCharactersInSet:separator];

            for(NSString* entry in lines) {
                NSArray<NSString *>* line = [entry componentsSeparatedByString:@": "];

                if([line count] == 2) {
                    NSString* plistpath = [line objectAtIndex:1];

                    if([plistpath hasSuffix:@"Info.plist"]) {
                        NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:plistpath];

                        if(plist && plist[@"CFBundleURLTypes"]) {
                            for(NSDictionary* type in plist[@"CFBundleURLTypes"]) {
                                if(type[@"CFBundleURLSchemes"]) {
                                    for(NSString* scheme in type[@"CFBundleURLSchemes"]) {
                                        [schemes addObject:scheme];
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    NSArray* schemes_ret = [schemes allObjects];
    [responseCache setObject:schemes_ret forKey:@"schemes"];
    return schemes_ret;
}

- (NSDictionary *)handleMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo {
    if(!name) {
        return nil;
    }

    NSDictionary* response = nil;

    if([name isEqualToString:@"resolvePath"]) {
        if(!userInfo) {
            return nil;
        }

        NSString* rawPath = userInfo[@"path"];

        if(!rawPath) {
            return nil;
        }

        // Resolve and standardize path.
        if(dpkgPath) {
            // Unsandboxed and unhooked - safe to resolve
            NSString* path = [[rawPath stringByExpandingTildeInPath] stringByStandardizingPath];

            if([path hasPrefix:@"/private/var"] || [path hasPrefix:@"/private/etc"]) {
                NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
                [pathComponents removeObjectAtIndex:1];
                path = [NSString pathWithComponents:pathComponents];
            }

            if([path hasPrefix:@"/var/tmp"]) {
                NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
                [pathComponents removeObjectAtIndex:1];
                path = [NSString pathWithComponents:pathComponents];
            }

            response = @{
                @"path" : path
            };
        } else {
            // Sandboxed and hooked
            return nil;
        }
    } else if([name isEqualToString:@"isPathRestricted"]) {
        if(!userInfo) {
            return nil;
        }
        
        NSString* path = userInfo[@"path"];

        if(!path || ![path isAbsolutePath] || [path isEqualToString:@"/"] || [path isEqualToString:@""]) {
            return nil;
        }

        if(dpkgPath && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return nil;
        }

        NSLog(@"%@: %@", name, path);
        
        // Check if path is restricted.
        BOOL restricted = [self isPathRestricted_internal:path];

        response = @{
            @"restricted" : @(restricted)
        };
    } else if([name isEqualToString:@"getURLSchemes"]) {
        response = @{
            @"schemes" : [self getURLSchemes_internal]
        };
    }

    return response;
}

- (NSDictionary *)generateDatabase {
    NSMutableDictionary* db = [NSMutableDictionary new];
    NSMutableSet* db_installed = [NSMutableSet new];
    NSMutableSet* db_exception = [NSMutableSet new];

    // Determine dpkg info database path.
    NSString* dpkgInfoPath;
    NSArray* dpkgInfoPaths = @[
        @"/Library/dpkg/info",
        @"/var/lib/dpkg/info",
        @"/var/jb/Library/dpkg/info",
        @"/var/jb/var/lib/dpkg/info"
    ];

    for(NSString* path in dpkgInfoPaths) {
        if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            dpkgInfoPath = path;
            break;
        }
    }

    // Iterate all list files in database.
    NSArray* db_files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dpkgInfoPath] includingPropertiesForKeys:@[] options:0 error:nil];

    for(NSURL* db_file in db_files) {
        if([db_file pathExtension] && [[db_file pathExtension] isEqualToString:@"list"]) {
            NSString* content = [NSString stringWithContentsOfURL:db_file encoding:NSUTF8StringEncoding error:nil];

            if(content) {
                // Read all lines
                NSArray* lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

                for(NSString* line in lines) {
                    if(![line isEqualToString:@""]) {
                        // Add to relevant set
                        if([[db_file lastPathComponent] isEqualToString:@"base.list"] || [[db_file lastPathComponent] isEqualToString:@"firmware-sbin.list"]) {
                            [db_exception addObject:line];
                        } else {
                            [db_installed addObject:line];
                        }
                    }
                }
            }
        }
    }

    // Filter some unneeded filenames.
    NSArray* filter_names = @[
        @"/."
    ];

    for(NSString* name in filter_names) {
        [db_installed removeObject:name];
        [db_exception removeObject:name];
    }

    [db setObject:[db_installed allObjects] forKey:@"installed"];
    [db setObject:[db_exception allObjects] forKey:@"exception"];
    return [db copy];
}

- (void)startService {
    NSArray* dpkgPaths = @[
        @"/usr/bin/dpkg-query",
        @"/var/jb/usr/bin/dpkg-query",
        @"/usr/local/bin/dpkg-query",
        @"/var/jb/usr/local/bin/dpkg-query"
    ];

    for(NSString* path in dpkgPaths) {
        if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            dpkgPath = path;
            break;
        }
    }

    [self connectService];

    if(center) {
        [center runServerOnCurrentThread];

        // Register messages.
        [center registerForMessageName:@"isPathRestricted" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
        [center registerForMessageName:@"getURLSchemes" target:self selector:@selector(handleMessageNamed:withUserInfo:)];
        [center registerForMessageName:@"resolvePath" target:self selector:@selector(handleMessageNamed:withUserInfo:)];

        // rocketbootstrap_unlock(CPDMC_SERVICE_NAME);
    }
}

- (void)startLocalService {
    // Load precompiled data from filesystem.
    NSDictionary* db_plist = [NSDictionary dictionaryWithContentsOfFile:@LOCAL_SERVICE_DB];

    if(!db_plist) {
        NSLog(@"%@", @"could not load db");
    } else {
        NSLog(@"%@", @"successfully loaded db");
    }

    if(db_plist[@"installed"]) {
        dpkgInstalledDb = [NSSet setWithArray:db_plist[@"installed"]];
    }

    if(db_plist[@"exception"]) {
        dpkgExceptionDb = [NSSet setWithArray:db_plist[@"exception"]];
    }
}

- (void)connectService {
    center = [CPDistributedMessagingCenter centerNamed:@CPDMC_SERVICE_NAME];
    // rocketbootstrap_distributedmessagingcenter_apply(center);
}

- (NSDictionary *)sendIPC:(NSString *)messageName withArgs:(NSDictionary *)args useService:(BOOL)service {
    if(service) {
        if(center) {
            NSError* error = nil;
            NSDictionary* result = [center sendMessageAndReceiveReplyName:messageName userInfo:args error:&error];
            return error ? nil : result;
        }

        return nil;
    }

    return [self handleMessageNamed:messageName withUserInfo:args];
}

- (NSDictionary *)sendIPC:(NSString *)messageName withArgs:(NSDictionary *)args {
    return [self sendIPC:messageName withArgs:args useService:NO];
}

- (NSString *)resolvePath:(NSString *)path {
    if(!path) {
        return nil;
    }

    NSDictionary* response = [self sendIPC:@"resolvePath" withArgs:@{
        @"path" : path
    } useService:(center != nil)];

    if(response) {
        path = response[@"path"];
    } else {
        path = [path stringByReplacingOccurrencesOfString:@"/./" withString:@"/"];
        path = [path stringByReplacingOccurrencesOfString:@"//" withString:@"/"];

        if([path hasPrefix:@"/private/var"] || [path hasPrefix:@"/private/etc"]) {
            NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
            [pathComponents removeObjectAtIndex:1];
            path = [NSString pathWithComponents:pathComponents];
        }

        if([path hasPrefix:@"/var/tmp"]) {
            NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
            [pathComponents removeObjectAtIndex:1];
            path = [NSString pathWithComponents:pathComponents];
        }
    }

    return path;
}

- (BOOL)isPathRestricted:(NSString *)path {
    if(!path || [path isEqualToString:@"/"] || [path isEqualToString:@""]) {
        return NO;
    }

    NSNumber* response_cached = [responseCache objectForKey:path];

    if(response_cached) {
        return [response_cached boolValue];
    }

    NSDictionary* response = [self sendIPC:@"isPathRestricted" withArgs:@{
        @"path" : path
    } useService:(dpkgInstalledDb == nil)];

    if(response) {
        BOOL restricted = [response[@"restricted"] boolValue];

        if(!restricted) {
            BOOL responseParent = [self isPathRestricted:[path stringByDeletingLastPathComponent]];

            if(responseParent) {
                restricted = YES;
            }
        }

        [responseCache setObject:@(restricted) forKey:path];
        return restricted;
    }

    return NO;
}

- (NSArray*)getURLSchemes {
    NSDictionary* response = [self sendIPC:@"getURLSchemes" withArgs:nil useService:(dpkgInstalledDb == nil)];

    if(response) {
        return response[@"schemes"];
    }

    return @[@"cydia", @"sileo", @"zbra", @"filza"];
}

- (NSDictionary *)getVersions {
    return @{
        @"build_date" : [NSString stringWithFormat:@"%@ %@", @__DATE__, @__TIME__],
        @"bypass_version" : @BYPASS_VERSION,
        @"api_version" : @API_VERSION
    };
}

+ (NSDictionary *)getDefaultPreferences {
    return @{
		@"Global_Enabled" : @(NO),
		@"Global_Service" : @(NO),
		@"Tweak_CompatEx" : @(NO),
		@"Hook_Filesystem" : @(YES),
		@"Hook_DynamicLibraries" : @(YES),
		@"Hook_URLScheme" : @(YES),
		@"Hook_EnvVars" : @(YES),
		@"Hook_FilesystemExtra" : @(NO),
		@"Hook_Foundation" : @(NO),
		@"Hook_DeviceCheck" : @(YES),
		@"Hook_MachBootstrap" : @(NO),
		@"Hook_SymLookup" : @(NO),
		@"Hook_LowLevelC" : @(NO),
		@"Hook_AntiDebugging" : @(NO),
		@"Hook_DynamicLibrariesExtra" : @(NO),
		@"Hook_ObjCRuntime" : @(NO),
		@"Hook_FakeMac" : @(NO),
		@"Hook_Syscall" : @(NO),
		@"Hook_Sandbox" : @(NO)
	};
}

+ (NSUserDefaults *)getPreferences {
    NSUserDefaults* result = [[NSUserDefaults alloc] initWithSuiteName:@SHADOW_PREFS_PLIST];

	// Register default preferences.
	[result registerDefaults:[self getDefaultPreferences]];

    return result;
}

- (instancetype)init {
    if((self = [super init])) {
        responseCache = [NSCache new];
        center = nil;
        dpkgInstalledDb = nil;
        dpkgExceptionDb = nil;
    }

    return self;
}
@end
