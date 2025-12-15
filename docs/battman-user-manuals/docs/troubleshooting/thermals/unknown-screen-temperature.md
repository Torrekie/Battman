---
title: 'Unknown' Screen Temperature
---

# "Unknown" Screen Temperature

Sometimes Battman cannot map the system’s thermal readings to a meaningful screen or panel temperature. In that case the UI may show **"Unknown"** on screen temperature or omit the value entirely.

## Why this happens

- The device firmware does not expose a dedicated panel temperature sensor.
- The current iOS version hides or aggregates the relevant sensor.
- Battman is running on a simulator or an unsupported platform (for example, certain Macs).
- Battman has not supported reading panel temperature for your device.

## What you can do

- Use the **Hardware Temperature** page to inspect other available sensors.
- Check for abnormal thermal pressure or throttling rather than relying on a single screen‑temperature number.
- Keep Battman updated; support for more sensors may be added over time.
