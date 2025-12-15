---
title: Installation
---

# Installation

This page describes how to install and set up Battman.

## Requirements

- Device with Apple A11 or above.
- Device with iOS 12 or above.
- Jailbroken, or have TrollStore installed.

Battman now provides ONLY TrollStore App and Jailbroken App. All other methods are unsupported and will not resulting a successful installation. This is caused by Battman's implementation where it heavily depending on iOS/macOS private APIs.

> If you really desired to sideload it with some sort of certificates or profiles, please make sure your Developer Provisioning Profile allows you to sign app with [Battman's entitlements](https://github.com/Torrekie/Battman/blob/master/Battman.entitlements). (How could it be possible?)

## Install (TrollStore, iOS 14+)
If you don't have TrollStore on your device, follow guides at [ios.cfw.guide](https://ios.cfw.guide/installing-trollstore/)

1. Download latest [Battman.tipa](https://github.com/Torrekie/Battman/releases/download/latest/Battman.tipa), or choose a version you preferred from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page.
2. Long hold (or find the 'Share' button) the downloaded `Battman.tipa`, tap "Share", then choose "TrollStore".
3. Press "Install" in opened TrollStore window.

## Jailbroken Install (rooted, iOS 12+)
1. Open your package manager (Cydia, Sileo, Zebra, etc.) and install `libintl8` from your bootstrap source (Elucubratus or Procursus)
2. Download latest `com.torrekie.battman_<version>_iphoneos-arm.deb` from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page. Where `<version>` is the version number of Battman, please make sure you are downloading the one with `iphoneos-arm` but not `iphoneos-arm64`. Current latest version is [1.0.3.1 (click to download)](https://github.com/Torrekie/Battman/releases/v1.0.3.1/com.torrekie.battman_1.0.3.1_iphoneos-arm.deb).
3. Long hold the downloaded deb package, tap "Share", and choose your package manager (or Filza) to proceed installation. (or any method you preferred to install debs)

## Jailbroken Install (rootless, iOS 15+)
1. Open your package manager (Cydia, Sileo, Zebra, etc.) and install `libintl8` from your bootstrap source (Elucubratus or Procursus)
2. Download latest `com.torrekie.battman_<version>_iphoneos-arm.deb` from our [Releases](https://github.com/Torrekie/Battman/releases/latest) page. Where `<version>` is the version number of Battman, please make sure you are downloading the one with `iphoneos-arm` but not `iphoneos-arm64`. Current latest version is [1.0.3.1 (click to download)](https://github.com/Torrekie/Battman/releases/v1.0.3.1/com.torrekie.battman_1.0.3.1_iphoneos-arm64.deb).
3. Long hold the downloaded deb package, tap "Share", and choose your package manager (or Filza) to proceed installation. (or any method you preferred to install debs)

## Next steps

- If installation fails, see the Troubleshooting section.
- After installation, explore the features from the Home page.
