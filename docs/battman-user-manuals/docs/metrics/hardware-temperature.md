---
title: Hardware Temperature
---

# Hardware Temperature

The **Hardware Temperature** view shows real‑time readings from the device’s thermal sensors.

It corresponds to the **Hardware Temperature** row in the Battery tab.

## Sections

Battman groups temperature data into several sections:

- **System Thermal Monitor State**  
  Shows the status of system thermal monitor daemon `thermalmonitord`.
- **Thermal Basics**  
  High‑level thermal metrics: thermal pressure level, [thermal notification level](../../troubleshooting/thermals/thermal-notification-levels), maximum trigger temperature and sunlight‑exposure state.
- **Device Sensors**
  Per‑sensor readings reported by the system (e.g. SoC, skin, battery pack, camera module).
- **HID / HID Raw Data**  
  Lower‑level HID temperature channels aggregated from multiple hardware sensors.

## Usage notes

- Some sensors may not update in real time or may report stub values.
- Thermal behavior can be tuned from **Thermal Tunes**, while this page is focused on read‑only monitoring.
