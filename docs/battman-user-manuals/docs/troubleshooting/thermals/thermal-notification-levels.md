---
title: Thermal Notification Levels
---

# Thermal Notification Levels

!!! note "Deprecated Feature"
    This feature has been deprecated by iOS and no longer available on iOS 16 or above.

Battman exposes the system's **thermal notification levels**, which describe how aggressively iOS will react to heat.

## Levels

The thermal notification system uses a progressive series of behavior levels, each representing increasingly aggressive thermal mitigation measures. The numbers shown below are **behavior indices** (0-10), not the actual system notification level IDs.

0. **Normal** — Normal operation with no thermal restrictions.

1. **70% Torch** — Torch (flashlight) brightness reduced to 70%.

2. **70% Backlight** — Display backlight reduced to 70%.

3. **50% Torch** — Torch brightness further reduced to 50%.

4. **50% Backlight** — Display backlight reduced to 50%.

5. **Torch Disabled** — Torch is completely disabled.

6. **25% Backlight** — Aggressive backlight reduction to 25%.

7. **Maps halo Disabled** — Visual effects like Maps halo are disabled.

8. **App Terminated** — Applications may be terminated to reduce thermal load.

9. **Device Restart** — Extreme thermal conditions may trigger a device restart.

10. **Ready** — Thermal table is ready (internal state).

## Implementation Details

**Important:** The actual system notification level IDs are **dynamically assigned** by iOS and are not constant values. The behavior indices (0-10) shown above are just identifiers for the different thermal mitigation behaviors.

This dynamic mapping allows Battman to work correctly even when iOS assigns different numeric IDs to the same thermal behaviors.

## In Battman

- The **Thermal Tunes** screen shows the current notification level and allows limited overrides.
- The **Hardware Temperature** page helps correlate these levels with sensor readings.

If you frequently hit high notification levels, consider reducing load, improving airflow, or adjusting Thermal Tunes more conservatively.
