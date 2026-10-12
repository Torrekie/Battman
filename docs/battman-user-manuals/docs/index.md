---
title: Home
---

# Battman 1.1.0

Battman is a battery and power-management utility for supported jailbroken or
TrollStore-enabled iPhones and iPads. It reads the measurements exposed by the
device and provides charging, brightness, and thermal controls where supported.
Available readings and controls vary by hardware, iOS version, and installation
environment.

## Start here

- [Install Battman](installation/index.md): choose a rooted, rootless, or TrollStore package.
- [Analytics](features/analytics.md): arrange ten built-in cards and inspect live readings, charging sessions, and available history.
- [Native plug-ins](features/plugins.md): review, approve, and manage additional native cards.
- [Charging limits](controls/charging-limits.md): understand the experimental charge-limit process before enabling it.
- [Wiping data](preferences/wiping-data.md): clear Battman's settings and local caches.

## What changed in 1.1.0

Analytics now includes ten built-in cards covering current battery readings,
capacity, cell consistency, connected sessions, discharge, charging states,
power readings, time by battery level, charging comparisons, and discharge
rhythm. Cards have selectable sizes, saved layouts, and details for supported
graph selections. Missing observations remain visible as gaps or unavailable
values.

The native plug-in host and public SDK v1 are implemented. **Charge Gauge** and
the SDK Analytics card are developer examples distributed as source only.
The application also adds **`zh_TW` (Chinese (Taiwan))** localization.

Battman does not certify every A11-or-newer device and iOS combination. Its
Analytics live graph covers foreground samples; historical cards read available
system history rather than recording an uninterrupted background timeline.
A native macOS app is not currently provided.

Use the controls at the top of this site to select English, Simplified Chinese,
or Traditional Chinese and a light, dark, or automatic appearance.
