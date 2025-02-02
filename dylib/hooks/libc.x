#import "hooks.h"

%group shadowhook_libc
%hookf(int, access, const char *pathname, int mode) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(ssize_t, readlink, const char* pathname, char* buf, size_t bufsize) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(ssize_t, readlinkat, int dirfd, const char* pathname, char* buf, size_t bufsize) {
    if(pathname) {
        NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if(![path isAbsolutePath]) {
            // Get file descriptor path.
            char pathnameParent[PATH_MAX];
            NSString* pathParent = nil;

            if(dirfd == AT_FDCWD) {
                pathParent = [[NSFileManager defaultManager] currentDirectoryPath];
            } else if(fcntl(dirfd, F_GETPATH, pathnameParent) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathnameParent length:strlen(pathnameParent)];
            }

            if(pathParent) {
                path = [pathParent stringByAppendingPathComponent:path];
            }
        }

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}

%hookf(int, chdir, const char *pathname) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, fchdir, int fd) {
    // Get file descriptor path.
    char pathname[PATH_MAX];

    if(fcntl(fd, F_GETPATH, pathname) != -1) {
        if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}

%hookf(int, chroot, const char *pathname) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }
    
    return %orig;
}

%hookf(int, getfsstat, struct statfs *buf, int bufsize, int flags) {
    int result = %orig;

    if(result != -1 && buf) {
        struct statfs* buf_ptr = buf;
        struct statfs* buf_end = buf + sizeof(struct statfs) * result;

        while(buf_ptr < buf_end) {
            if([@(buf_ptr->f_mntonname) isEqualToString:@"/"]) {
                // Mark rootfs read-only
                buf_ptr->f_flags |= MNT_RDONLY;
                break;
            }

            buf_ptr++;
        }
    }

    return result;
}

%hookf(int, statfs, const char *pathname, struct statfs *buf) {
    int result = %orig;

    if(result == 0 && pathname) {
        NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            memset(buf, 0, sizeof(struct statfs));
            errno = ENOENT;
            return -1;
        }

        // Modify flags
        if(buf) {
            if([path hasPrefix:@"/var"]
            || [path hasPrefix:@"/private/var"]
            || [path hasPrefix:@"/private/preboot"]) {
                buf->f_flags |= MNT_NOSUID | MNT_NODEV;
            } else {
                buf->f_flags |= MNT_RDONLY | MNT_ROOTFS;
            }
        }
    }

    return result;
}

%hookf(int, fstatfs, int fd, struct statfs *buf) {
    int result = %orig;

    if(result == 0) {
        // Get file descriptor path.
        char pathname[PATH_MAX];
        NSString* path = nil;

        if(fcntl(fd, F_GETPATH, pathname) != -1) {
            path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

            if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
                memset(buf, 0, sizeof(struct statfs));
                errno = ENOENT;
                return -1;
            }

            // Modify flags
            if(buf) {
                if([path hasPrefix:@"/var"]
                || [path hasPrefix:@"/private/var"]
                || [path hasPrefix:@"/private/preboot"]) {
                    buf->f_flags |= MNT_NOSUID | MNT_NODEV;
                } else {
                    buf->f_flags |= MNT_RDONLY | MNT_ROOTFS;
                }
            }
        }
    }

    return result;
}

%hookf(int, stat, const char *pathname, struct stat *buf) {
    int result = %orig;
    
    if(result == 0) {
        NSString* path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            memset(buf, 0, sizeof(struct stat));
            errno = ENOENT;
            return -1;
        }

        if(buf) {
            if([path isEqualToString:@"/Applications"]
            || [path isEqualToString:@"/Library/Ringtones"]
            || [path isEqualToString:@"/Library/Wallpaper"]
            || [path isEqualToString:@"/usr/include"]
            || [path isEqualToString:@"/usr/libexec"]
            || [path isEqualToString:@"/usr/share"]) {
                buf->st_mode &= ~S_IFLNK;
                buf->st_mode |= S_IFDIR;
            }

            if([path isEqualToString:@"/bin"]) {
                if(buf->st_size > 128) {
                    buf->st_size = 128;
                }
            }
        }
    }

    return result;
}

%hookf(int, lstat, const char *pathname, struct stat *buf) {
    int result = %orig;

    if(result == 0) {
        NSString* path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if([_shadow isPathRestricted:path resolve:(buf && buf->st_mode & S_IFLNK) ? NO : YES] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            memset(buf, 0, sizeof(struct stat));
            errno = ENOENT;
            return -1;
        }

        if(buf) {
            if([path isEqualToString:@"/Applications"]
            || [path isEqualToString:@"/Library/Ringtones"]
            || [path isEqualToString:@"/Library/Wallpaper"]
            || [path isEqualToString:@"/usr/include"]
            || [path isEqualToString:@"/usr/libexec"]
            || [path isEqualToString:@"/usr/share"]) {
                buf->st_mode &= ~S_IFLNK;
                buf->st_mode |= S_IFDIR;
            }

            if([path isEqualToString:@"/bin"]) {
                if(buf->st_size > 128) {
                    buf->st_size = 128;
                }
            }
        }
    }

    return result;
}

// %hookf(int, fstat, int fd, struct stat *buf) {
//     int result = %orig;

//     if(result == 0) {
//         // Get file descriptor path.
//         char pathname[PATH_MAX];
//         NSString* path = nil;

//         if(fcntl(fd, F_GETPATH, pathname) != -1) {
//             path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

//             if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
//                 errno = EBADF;
//                 return -1;
//             }

//             if(buf) {
//                 if([path isEqualToString:@"/bin"]) {
//                     if(buf->st_size > 128) {
//                         buf->st_size = 128;
//                     }
//                 }
//             }
//         }
//     }

//     return result;
// }

%hookf(int, fstatat, int dirfd, const char *pathname, struct stat *buf, int flags) {
    int result = %orig;

    if(result == 0 && pathname) {
        NSString* path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if(![path isAbsolutePath]) {
            // Get file descriptor path.
            char pathnameParent[PATH_MAX];
            NSString* pathParent = nil;

            if(dirfd == AT_FDCWD) {
                pathParent = [[NSFileManager defaultManager] currentDirectoryPath];
            } else if(fcntl(dirfd, F_GETPATH, pathnameParent) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathnameParent length:strlen(pathnameParent)];
            }

            if(pathParent) {
                path = [pathParent stringByAppendingPathComponent:path];
            }
        }

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            memset(buf, 0, sizeof(struct stat));
            errno = ENOENT;
            return -1;
        }

        if(buf) {
            if([path isEqualToString:@"/Applications"]
            || [path isEqualToString:@"/Library/Ringtones"]
            || [path isEqualToString:@"/Library/Wallpaper"]
            || [path isEqualToString:@"/usr/include"]
            || [path isEqualToString:@"/usr/libexec"]
            || [path isEqualToString:@"/usr/share"]) {
                buf->st_mode &= ~S_IFLNK;
                buf->st_mode |= S_IFDIR;
            }

            if([path isEqualToString:@"/bin"]) {
                if(buf->st_size > 128) {
                    buf->st_size = 128;
                }
            }
        }
    }

    return result;
}

%hookf(int, faccessat, int dirfd, const char *pathname, int mode, int flags) {
    int result = %orig;

    if(result == 0 && pathname) {
        NSString* path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if(![path isAbsolutePath]) {
            // Get file descriptor path.
            char pathnameParent[PATH_MAX];
            NSString* pathParent = nil;

            if(dirfd == AT_FDCWD) {
                pathParent = [[NSFileManager defaultManager] currentDirectoryPath];
            } else if(fcntl(dirfd, F_GETPATH, pathnameParent) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathnameParent length:strlen(pathnameParent)];
            }

            if(pathParent) {
                path = [pathParent stringByAppendingPathComponent:path];
            }
        }

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return result;
}

%hookf(int, readdir_r, DIR *restrict dirp, struct dirent *restrict entry, struct dirent **restrict oresult) {
    int result = %orig;
    
    if(result == 0 && *oresult) {
        int fd = dirfd(dirp);

        do {
            // Get file descriptor path.
            char pathname[PATH_MAX];
            NSString* pathParent = nil;

            if(fcntl(fd, F_GETPATH, pathname) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];
                NSString* path = [pathParent stringByAppendingPathComponent:@((*oresult)->d_name)];

                if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
                    // call readdir again to skip ahead
                    result = %orig(dirp, entry, oresult);
                } else {
                    break;
                }
            }
        } while(result == 0 && *oresult);
    }

    return result;
}

%hookf(struct dirent *, readdir, DIR* dirp) {
    struct dirent* result = %orig;
    
    if(result) {
        int fd = dirfd(dirp);

        do {
            // Get file descriptor path.
            char pathname[PATH_MAX];
            NSString* pathParent = nil;

            if(fcntl(fd, F_GETPATH, pathname) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];
                NSString* path = [pathParent stringByAppendingPathComponent:@(result->d_name)];

                if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
                    // call readdir again to skip ahead
                    result = %orig(dirp);
                } else {
                    break;
                }
            }
        } while(result);
    }

    return result;
}

%hookf(FILE *, fopen, const char *pathname, const char *mode) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return NULL;
    }

    return %orig;
}

%hookf(FILE *, freopen, const char *pathname, const char *mode, FILE *stream) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return NULL;
    }

    return %orig;
}

%hookf(char *, realpath, const char *pathname, char *resolved_path) {
    if(![_shadow isCallerTweak:[NSThread callStackReturnAddresses]] && ([_shadow isCPathRestricted:pathname] || [_shadow isCPathRestricted:resolved_path])) {
        errno = ENOENT;
        return NULL;
    }

    return %orig;
}

%hookf(int, execve, const char *pathname, char *const argv[], char *const envp[]) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, execvp, const char *pathname, char *const argv[]) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, posix_spawn, pid_t *pid, const char *pathname, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, posix_spawnp, pid_t *pid, const char *pathname, const posix_spawn_file_actions_t *file_actions, const posix_spawnattr_t *attrp, char *const argv[], char *const envp[]) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, getattrlist, const char* path, struct attrlist* attrList, void* attrBuf, size_t attrBufSize, unsigned long options) {
    if([_shadow isCPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, symlink, const char* path1, const char* path2) {
    if([_shadow isCPathRestricted:path2] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = EACCES;
        return -1;
    }

    return %orig;
}

%hookf(int, link, const char* path1, const char* path2) {
    if(([_shadow isCPathRestricted:path1] || [_shadow isCPathRestricted:path2]) && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, rename, const char* old, const char* new) {
    if(([_shadow isCPathRestricted:old] || [_shadow isCPathRestricted:new]) && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, remove, const char* pathname) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, unlink, const char* pathname) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, unlinkat, int dirfd, const char* pathname, int flags) {
    if(pathname) {
        NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if(![path isAbsolutePath]) {
            // Get file descriptor path.
            char pathnameParent[PATH_MAX];
            NSString* pathParent = nil;

            if(dirfd == AT_FDCWD) {
                pathParent = [[NSFileManager defaultManager] currentDirectoryPath];
            } else if(fcntl(dirfd, F_GETPATH, pathnameParent) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathnameParent length:strlen(pathnameParent)];
            }

            if(pathParent) {
                path = [pathParent stringByAppendingPathComponent:path];
            }
        }

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}

%hookf(int, rmdir, const char* pathname) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(long, pathconf, const char* pathname, int name) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(long, fpathconf, int fd, int name) {
    // Get file descriptor path.
    char pathname[PATH_MAX];

    if(fcntl(fd, F_GETPATH, pathname) != -1) {
        if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}

%hookf(int, utimes, const char* pathname, const struct timeval times[2]) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    return %orig;
}

%hookf(int, futimes, int fd, const struct timeval times[2]) {
    // Get file descriptor path.
    char pathname[PATH_MAX];

    if(fcntl(fd, F_GETPATH, pathname) != -1) {
        if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    return %orig;
}
%end

%group shadowhook_libc_env
%hookf(char *, getenv, const char *name) {
    if(name) {
        NSString *env = [NSString stringWithUTF8String:name];

        if([env isEqualToString:@"DYLD_INSERT_LIBRARIES"]
        || [env isEqualToString:@"_MSSafeMode"]
        || [env isEqualToString:@"_SafeMode"]
        || [env isEqualToString:@"_SubstituteSafeMode"]
        || [env isEqualToString:@"SHELL"]) {
            return NULL;
        }
        
        // if([env isEqualToString:@"SIMULATOR_DEVICE_NAME"]) {
        //     struct utsname systemInfo;
        //     uname(&systemInfo);

        //     return (char *)[@(systemInfo.machine) UTF8String];
        // }
    }

    return %orig;
}
%end

%group shadowhook_libc_debug
%hookf(int, ptrace, int _request, pid_t _pid, caddr_t _addr, int _data) {
    if(_request == PT_DENY_ATTACH) {
        return 0;
    }

    return %orig;
}

%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if(namelen == 4
    && name[0] == CTL_KERN
    && name[1] == KERN_PROC
    && name[2] == KERN_PROC_ALL
    && name[3] == 0) {
        // Running process check.
        *oldlenp = 0;
        return 0;
    }

    int ret = %orig;

    if(ret == 0
    && name[0] == CTL_KERN
    && name[1] == KERN_PROC
    && name[2] == KERN_PROC_PID
    && name[3] == getpid()) {
        // Remove trace flag.
        if(oldp) {
            struct kinfo_proc *p = ((struct kinfo_proc *) oldp);

            if((p->kp_proc.p_flag & P_TRACED) == P_TRACED) {
                p->kp_proc.p_flag &= ~P_TRACED;
            }
        }
    }

    return ret;
}

%hookf(pid_t, getppid) {
    return 1;
}
%end

static int (*original_open)(const char *pathname, int oflag, ...);
static int replaced_open(const char *pathname, int oflag, ...) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return -1;
    }

    int result = -1;

    if(oflag & O_CREAT) {
        mode_t mode;
        va_list args;
        va_start(args, oflag);
        mode = (mode_t) va_arg(args, int);
        va_end(args);

        result = original_open(pathname, oflag, mode);
    } else {
        result = original_open(pathname, oflag);
    }

    return result;
}

static int (*original_openat)(int dirfd, const char *pathname, int oflag, ...);
static int replaced_openat(int dirfd, const char *pathname, int oflag, ...) {
    if(pathname) {
        NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

        if(![path isAbsolutePath]) {
            // Get file descriptor path.
            char pathnameParent[PATH_MAX];
            NSString* pathParent = nil;

            if(dirfd == AT_FDCWD) {
                pathParent = [[NSFileManager defaultManager] currentDirectoryPath];
            } else if(fcntl(dirfd, F_GETPATH, pathnameParent) != -1) {
                pathParent = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathnameParent length:strlen(pathnameParent)];
            }

            if(pathParent) {
                NSMutableArray* pathComponents = [[pathParent pathComponents] mutableCopy];
                [pathComponents addObject:@(pathname)];

                path = [NSString pathWithComponents:pathComponents];
            }
        }

        if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
            errno = ENOENT;
            return -1;
        }
    }

    int result = -1;

    if(oflag & O_CREAT) {
        mode_t mode;
        va_list args;
        va_start(args, oflag);
        mode = (mode_t) va_arg(args, int);
        va_end(args);

        result = original_openat(dirfd, pathname, oflag, mode);
    } else {
        result = original_openat(dirfd, pathname, oflag);
    }

    return result;
}

%group shadowhook_libc_opendir
// %hookf(DIR *, opendir, const char *pathname) {
//     DIR* result = %orig;
    
//     if(result && pathname) {
//         NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];

//         if([_shadow isPathRestricted:path] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
//             errno = ENOENT;
//             return NULL;
//         }
//     }

//     return result;
// }

%hookf(DIR *, __opendir2, const char *pathname, size_t bufsize) {
    if([_shadow isCPathRestricted:pathname] && ![_shadow isCallerTweak:[NSThread callStackReturnAddresses]]) {
        errno = ENOENT;
        return NULL;
    }

    return %orig;
}
%end

void shadowhook_libc(void) {
    %init(shadowhook_libc);
}

void shadowhook_libc_envvar(void) {
    %init(shadowhook_libc_env);
}

void shadowhook_libc_lowlevel(void) {
    %init(shadowhook_libc_opendir);
    MSHookFunction(open, replaced_open, (void **) &original_open);
    MSHookFunction(openat, replaced_openat, (void **) &original_openat);
}

void shadowhook_libc_antidebugging(void) {
    %init(shadowhook_libc_debug);
}
