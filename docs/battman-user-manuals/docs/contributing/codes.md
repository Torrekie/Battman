---
title: Contributing Code
---

# Contributing Code

We welcome code contributions to Battman.

## Before you start

- Read the main `README.md` for an overview of the project layout and build requirements.
- Make sure you have a suitable iOS toolchain and environment set up.

## Project Structure

Battman is written in **Objective-C and C** (no Swift). The main codebase is organized as follows:

### Directory Layout

- **`Battman/`** - Main application code
  - **`battery_utils/`** - Battery information and hardware interaction utilities
  - **`hw/`** - Hardware-specific interfaces (e.g., IOMFB)
  - **`cobjc/`** - Custom Objective-C runtime wrappers for C compatibility
  - **`ObjCExt/`** - Objective-C category extensions
  - **`CGIconSet/`** - Custom icon generation code
  - **`brightness/`** - Brightness control functionality
  - **`scprefs/`** - Preferences integration
  - **`security/`** - Security and protection code

### File Naming Conventions

- View controllers: `*ViewController.h` / `*ViewController.m`
- Custom views: `*View.h` / `*View.m` or `*Cell.h` / `*Cell.m`
- C headers: `*.h` with corresponding `*.c` or `*.m` implementations
- Headers use `#pragma once` or traditional include guards

## Code Style Guidelines

### Language and Architecture

- **Primary languages**: Objective-C and C
- **No external dependencies**: No CocoaPods, Swift Packages, or third-party frameworks
- **No Storyboards or XIBs**: UI is built programmatically
- **No Xcode Assets**: Resources are generated programmatically

#### Why No Xcode Assets and Storyboards?

Battman does not use Xcode Assets (.xcassets) or Storyboards/XIBs for the following reasons:

- **Open-source toolchain compatibility**: Those formats are private commercial formats made by Apple, which are not buildable with open-source toolchains. This prevents the project from being built on non-Apple platforms or with alternative build systems.

- **Cross-platform collaboration**: We have collaborators not using macOS and Xcode. Using those formats will break the maintainability and prevent contributors from working on the project in their preferred environments.

- **Programmatic UI preference**: We always prefer writing UI programmatically, instead of predefining them in some sort of files. This approach provides better version control, easier code review, and more flexibility in UI construction.

#### Why No Third-Party Dependencies?

Battman intentionally avoids third-party dependencies (CocoaPods, Swift Packages, external frameworks) for the following reasons:

- **Control and maintainability**: External code is not under our control, and we cannot respond to potential future changes, breaking updates, or deprecations that may affect the project.

- **Collaboration accessibility**: Not every collaborator is able to pull such dependencies on their build systems. Avoiding external dependencies ensures that all contributors can build and work on the project regardless of their environment setup, facilitating better collaboration.

If you need functionality that would typically come from a third-party library, please implement it directly in the codebase or adapt the necessary code to fit Battman's architecture (For example, we have completely rewritten Swift `UberSegmentedControl` in Objective-C).

#### Why No Swift Code?

Battman uses Objective-C and C exclusively, and does not accept Swift code submissions for the following reasons:

- **Stability and compatibility**: Swift itself has frequent updates with breaking changes, and is always trying to drop support for previous system versions. This creates maintenance burden and compatibility issues that conflict with Battman's goal of supporting iOS 12+.

- **Toolchain size**: The Swift toolchain is much larger than regular LLVM + Clang, which is not friendly for our existing collaborators who may have limited resources or prefer minimal toolchain installations.

- **Exception for unavoidable Swift**: If your submission is not Swift-avoidable (for example, WidgetKit only allows Swift), please create a new subproject to contain it. Otherwise, all logic and UI should be written in Objective-C and C.

  If you must use Swift, your Swift code must meet these requirements:
  - Your Swift code should have been compiled and tested on iOS 12 or earlier.
  - Your Swift code should be written in Swift 4 or older.
  - Your Swift code should at least be buildable with Procursus' Swift toolchain on iOS.

### C / Objective-C Patterns

#### Singleton Pattern

```objc
+ (instancetype)sharedPrefs {
    static BattmanPrefs *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] _init];
    });
    return shared;
}
```

#### iOS Version Checks

```objc
if (@available(iOS 13.0, *)) {
    // iOS 13+ code
} else {
    // Fallback code
}
```
```c
if (__builtin_available(iOS 13.0, *)) {
    // iOS 13+ code
} else {
    // Fallback code
}
```

#### Debug Logging

```c
// DBGLOG is based on NSLog()
DBGLOG(CFSTR("Debug message: %@"), value);
```
```objc
// DBGLOG is based on NSLog()
DBGLOG(@"Debug message: %@", value);
```

#### Localization

```c
// For NSString
NSString *localized = _("String to localize");

// For C strings
const char *localized = _C("String to localize");
```

#### Static Initialization

```c
static dispatch_once_t onceToken;
static bool value;

dispatch_once(&onceToken, ^{
    // One-time initialization
    value = compute_value();
});
```

### Error Handling

- Check return values from system calls
- Use `os_log_error` for error conditions
- Provide fallback paths when possible
- Avoid crashing on recoverable errors

### Memory Management

- Use ARC for Objective-C code
- Manual memory management for C code (free what you malloc)
- Be careful with CF types - use `CFRelease` appropriately

### Build System

Battman can be built with:
- **Xcode**: Standard Xcode project
- **Makefile**: Located in `Battman/Makefile`, supports Linux builds

Key build flags:
- `-fobjc-arc`: Automatic Reference Counting
- `-target arm64-apple-ios12.0`: iOS 12+ deployment target
- `-DDEBUG`: Debug builds
- `-DUSE_GETTEXT`: Optional gettext localization support

## Typical workflow

1. Fork the repository and create a feature branch.
2. Make your changes with clear, focused commits.
3. Prefer small, reviewable pull requests rather than large, mixed ones.
4. Test on as many relevant iOS versions / devices as you can.
5. Open a pull request and describe:
   - What you changed.
   - How you tested it.
   - Any user‑visible behavior differences.

## Code Review Guidelines

- Follow existing code style and patterns
- Maintain compatibility with iOS 12+
- Test on both simulator and real devices when possible
- Use appropriate logging (DBGLOG for debug, os_log for production)
- Ensure proper memory management
- Add comments for complex logic or hardware-specific code
- Update related documentation if behavior changes

Please avoid introducing private information (such as personal certificates or keys) into the repository or build scripts.
