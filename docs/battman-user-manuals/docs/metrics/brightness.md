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

### Percent vs. nits isn’t linear

- iOS maps the user slider to panel output with a perceptual (gamma‑like) curve, not a straight line.
- The function is roughly exponential: `f(percentage) ≠ max_nits * percentage`.
- Example: on a 650‑nit panel, 50% user brightness typically lands near ~150 nits, not ~325.
- This curve keeps low and mid levels more usable for human vision.