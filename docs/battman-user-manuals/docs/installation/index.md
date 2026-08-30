---
title: Installation
---

# Installation

This page describes how to install and set up Battman.

## Requirements

- Device with Apple A11 or above.
- Device with iOS 12 or above.
- Jailbroken, or have TrollStore installed.

The A11/iOS 12 baseline is a declared product boundary supported by arm64/iOS
12 compile evidence and current simulator/device checks; it is not an
independently completed test of every A11-or-newer device on every iOS release.
Individual hardware-backed readings can be **Unavailable** when the device does
not expose the required telemetry.

Battman now provides ONLY TrollStore App and Jailbroken App. All other methods are unsupported and will not resulting a successful installation. This is caused by Battman's implementation where it heavily depending on iOS/macOS private APIs.

> If you really desired to sideload it with some sort of certificates or profiles, please make sure your Developer Provisioning Profile allows you to sign app with [Battman's entitlements](https://github.com/Torrekie/Battman/blob/master/Battman.entitlements). (How could it be possible?)

## Install (TrollStore, iOS 14+)
If you don't have TrollStore on your device, follow guides at [ios.cfw.guide](https://ios.cfw.guide/installing-trollstore/)

1. Download latest [Battman.tipa](https://github.com/Torrekie/Battman/releases/download/latest/Battman.tipa), or choose a version you preferred from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page.
2. Long hold (or find the 'Share' button) the downloaded `Battman.tipa`, tap "Share", then choose "TrollStore".
3. Press "Install" in opened TrollStore window.

## Jailbroken Install (rooted, iOS 12+)
1. Open your package manager (Cydia, Sileo, Zebra, etc.) and install `libintl8` from your bootstrap source (Elucubratus or Procursus)
2. Download `com.torrekie.battman_<version>_iphoneos-arm.deb` from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page. Make sure you choose `iphoneos-arm`, not `iphoneos-arm64`.
3. Long hold the downloaded deb package, tap "Share", and choose your package manager (or Filza) to proceed installation. (or any method you preferred to install debs)

## Jailbroken Install (rootless, iOS 15+)
1. Open your package manager (Cydia, Sileo, Zebra, etc.) and install `libintl8` from your bootstrap source (Elucubratus or Procursus)
2. Download `com.torrekie.battman_<version>_iphoneos-arm64.deb` from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page. Make sure you choose `iphoneos-arm64`, not `iphoneos-arm`.
3. Long hold the downloaded deb package, tap "Share", and choose your package manager (or Filza) to proceed installation. (or any method you preferred to install debs)

## Next steps

- If installation fails, see the Troubleshooting section.
- After installation, explore the features from the Home page.
