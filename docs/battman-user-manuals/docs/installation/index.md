---
title: Installation
---

# Install Battman on iOS

## Requirements and coverage

- Apple A11 or newer, with iOS 12 or newer.
- A supported jailbreak, or an already working TrollStore installation.

The A11/iOS 12 baseline is a declared product boundary supported by arm64/iOS
12 compile evidence and current simulator/device checks; it is not an
independently completed test of every A11-or-newer device on every iOS release.
Individual readings can be **Unavailable** when the device does not expose the
required telemetry. The installation method has its own OS requirements; the
versions below do not imply that every intervening iOS build supports TrollStore
or a jailbreak.

Ordinary certificate/profile sideloading is unsupported. Battman requires
privileged entitlements and private system interfaces that a normal provisioning
profile does not provide. Re-signing an archive alone does not grant them.

## Choose the matching package

Use the assets attached to a specific [GitHub release](https://github.com/Torrekie/Battman/releases).
Check that release's notes, version, and checksums before installation; do not
assume the 1.1.0 source tree means that a production release is already published.
The release checksum signature identifies its signer only when the public-key
fingerprint is compared with an independently reviewed fingerprint.

| Environment | Package | Documented OS baseline |
| --- | --- | --- |
| Rooted jailbreak | `com.torrekie.battman_<version>_iphoneos-arm.deb` | iOS 12+ |
| Rootless jailbreak | `com.torrekie.battman_<version>_iphoneos-arm64.deb` | iOS 15+ |
| TrollStore | `Battman.tipa` | iOS 14+, only on versions supported by your TrollStore installation |

The Debian architecture name describes the jailbreak layout. Both host
packages contain arm64 code; do not choose by the CPU's “64-bit” label alone.
For rootless use `iphoneos-arm64.deb`, not `iphoneos-arm`.

## Jailbreak installation

1. Download the package matching your rooted or rootless environment.
2. Open it with your package manager and review the package details.
3. Let the package manager resolve dependencies from the bootstrap's normal
   sources, including `libintl8` or `libintl` when requested by the package.
4. Complete installation and open Battman.

If using Havoc, install the Havoc channel package through that channel's package
manager instructions. Havoc has a separately built host and supports Debian
packages only; there is no Havoc TIPA. Marketplace delivery does not grant trust
to a native plug-in. Avoid installing conflicting host packages from different
channels at the same time.

## TrollStore installation

1. Confirm TrollStore already works on your exact iOS version.
2. Download the selected release's `Battman.tipa`, share it to TrollStore, and
   review the installation prompt.
3. Complete installation and open Battman.

When preparing a replacement TIPA yourself, follow the release report's
`requiresOuterResign` status. The packaging tools do not perform final outer
signing or installation. Adding plug-ins changes the app bundle and requires a
properly signed replacement app; copying native code into app data is not a
supported TrollStore activation method.

Continue with [Analytics](../features/analytics.md) or
[Native plug-ins](../features/plugins.md).
