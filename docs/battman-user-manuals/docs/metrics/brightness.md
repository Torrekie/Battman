---
title: Brightness
---

# Brightness

The **Brightness** page reads and presents screen‑brightness data.

It corresponds to the **Brightness** section on the Battery tab.

## What is shown

- Current brightness as a **user percentage**.
- Hardware and user‑accessible brightness limits values in **nits**.
- Display characteristics such as resolution, color gamut (sRGB / P3), refresh rate and color depth.

## Advanced Controls

In **Advanced**, we currently provide some limited controls to adjust system global configs:

- **Low Power Mode Brightness Reduction**: Controls how system reducts the screen visual brightness when Low Power Mode is enabled.
- **Auto Dim**: Controls whether system automatically triggers screen dim when device is idled.
- **Auto Dim on A/C**: Similar to **Auto Dim**, but only controls the A/C attached behaviors.

### Percent vs. nits isn’t linear

- iOS maps the user slider to panel output with a perceptual (gamma‑like) curve, not a straight line.
- The function is roughly exponential: `f(percentage) ≠ max_nits * percentage`.
- Example: on a 650‑nit panel, 50% user brightness typically lands near ~150 nits, not ~325.
- This curve keeps low and mid levels more usable for human vision.

## Notice

- Changes made to **Advanced** settings through Battman will directly modify your device's global configuration. These configuration changes are treated as global user data by iOS. As a result, your customized brightness settings will be included when you back up your device using iTunes or other iPhone backup tools. If you restore this backup onto another device, the same brightness settings will also be applied to that device automatically.