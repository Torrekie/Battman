---
title: Thermal Tunes
---

# Thermal Tunes

The **Thermal Tunes** screen exposes mid‑level thermal‑management switches that normally stay hidden from users.

## Sections

- **General** – whether apps receive thermal state updates, and whether the system reduces power when heating.
- **Hot‑In‑Pocket Mode (HIP)** – available on supported iPhones; controls thermal behavior when the screen is off and the device is in a pocket.
- **Sunlight Exposure** – automatic vs manual control of sunlight exposure mode and current sunlight status.
- **Thermal Levels** – current thermal pressure and notification level, with a segmented bar allowing manual overrides.


## How the toggles work

- **Lock (padlock icon):** prevents `thermalmonitord` from resetting the setting back to its default. Use this when you want your chosen value to persist across reboots and system changes.
- **Checkmark:** the actual on/off state of the feature. Toggle it to enable or disable the behavior itself.

## Safety notes

Changing these settings can:

- Increase device and battery temperatures.
- Affect charging, backlight, flashlight and media behaviors.

## Notice

- Changes made to **Thermal Tunes** settings through Battman will directly modify your device's global configuration for `thermalmonitord`. These configuration changes are treated as global user data by iOS. As a result, your customized thermal settings will be included when you back up your device using iTunes or other iPhone backup tools. If you restore this backup onto another device, the same thermal settings will also be applied to that device automatically.
