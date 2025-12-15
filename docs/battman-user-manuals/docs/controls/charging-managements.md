---
title: Charging Managements
---

# Charging Managements

The **Charging Managements** screen lets you control how the system charges the battery and controls Low Power Mode.

## Features

- **Block Charging**  
  Uses SMC registers to stop charging while keeping the device powered from A/C.
- **Block Power Supply**  
  Completely ingore A/C. Forces the device to draw from the battery even when plugged in.
- **OBC schedule**  
  Integrates with `PowerUI` to manually schedule `Optimized Battery Charging` (start / end time).
- **Low Power Mode Config**  
  Enables, disables and auto‑disables LPM based on plug state and battery‑percentage thresholds, with options to hide system alerts.

## Notice

- Changes made to **Low Power Mode** settings through Battman will directly modify your device's global configuration for LPM. These configuration changes are treated as global user data by iOS. As a result, your customized Low Power Mode settings will be included when you back up your device using iTunes or other iPhone backup tools. If you restore this backup onto another device, the same Low Power Mode settings will also be applied to that device automatically.