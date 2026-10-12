//
//  main.h
//  Battman
//
//  Created by Torrekie on 2025/1/19.
//

#ifndef main_h
#define main_h

#include <stdio.h>
#include <stdlib.h>
#include <locale.h>
#include <Availability.h>
#include <TargetConditionals.h>

#ifdef __OBJC__
#include <Foundation/Foundation.h>
#endif

#if __has_include(<SoftLinking/WeakLinking.h>)
#include <SoftLinking/WeakLinking.h>
#else
#define WEAK_LINK_FORCE_IMPORT(sym) extern __attribute__((weak_import)) __typeof__(sym) sym
#endif

#ifdef _
#undef _
#endif

#define _(x) cond_localize(x)

#ifndef BATTMAN_TEXTDOMAIN
#define BATTMAN_TEXTDOMAIN "battman"
#endif

#if (!defined(DEBUG) || (DEBUG == 0)) && TARGET_OS_IPHONE && (__ENVIRONMENT_IPHONE_OS_VERSION_MIN_REQUIRED__ > 120000)
#error "IPHONEOS_DEPLOYMENT_TARGET must be set to iOS 12.0 (or lower) before archiving!       \
This ensures older-OS users aren't dropped and that any @available/__builtin_available blocks \
are weakly linked correctly at link time."
#endif

#if (!defined(DEBUG) || (DEBUG == 0)) && TARGET_OS_OSX && (__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ > 110000)
#error "MACOS_DEPLOYMENT_TARGET must be set to macOS 11.0 before archiving!                   \
This ensures older-OS users aren't dropped and that any @available/__builtin_available blocks \
are weakly linked correctly at link time."
#endif

#if !defined(BATTMAN_VERSION_STRING)
#error Please define BATTMAN_VERSION_STRING before building!
#endif

#if !defined(__arm64__) && !defined(__aarch64__) && !defined(__arm64e__) && !(TARGET_OS_SIMULATOR && defined(BATTMAN_SIMULATOR_UI_FIXTURE))
#error Current Battman is arm64 only! \
Please file an issue if you would like to contribute!
#endif

__BEGIN_DECLS

#ifdef __OBJC__
NSString *cond_localize(const char *str);
#else
CFStringRef cond_localize(const char *str);
#endif

const char *cond_localize_c(const char *str);

__END_DECLS

#endif /* main_h */
