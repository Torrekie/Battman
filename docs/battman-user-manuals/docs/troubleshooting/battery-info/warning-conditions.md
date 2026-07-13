---
title: Warning Conditions
---

# Warning Conditions

This page explains battery‑related warning conditions as reported by Battman and the system.

## Data warnings shown in Battery Info

Battman flags suspicious or missing telemetry values in the Battery Info table. A warning icon appears beside the row, and tapping it shows the detail text below.

- **Remaining Capacity**
    - Unusual when reported capacity exceeds the current full‑charge capacity or is more than 10 mAh above the device‑calculated True Remaining Capacity. Message: “Unusual Remaining Capacity, a non-genuine battery component may be in use.” For the first case, Battman also shows an “Estimated Remaining” capacity derived from state of charge.
    - Missing value triggers “Remaining Capacity not detected.”
- **Cycle Count**
    - Warns when cycle count exceeds the nominal design target. If the gauge does not provide a design value, Battman uses 500 for iPhone 14-era and earlier identifiers, 1000 for iPhone 15-era and later identifiers, iPad, Apple Watch, and MacBook families, and 400 for iPod. The warning notes possible capacity or peak-performance reduction and explicitly states that cycle count alone does not indicate battery authenticity.
- **Time to Empty**
    - Battman hides discharge TTE while actively charging and rejects unavailable or sentinel values. While discharging, it compares a valid reported estimate with a floating-point capacity/current estimate; a large mismatch produces the neutral warning “Time to Empty is inconsistent with the current battery telemetry.”
- **DOD₀ at Last OCV**
    - DOD₀ is a dimensionless raw reference on a documented 0–16384 scale, not a capacity and not comparable with Qmax. Values above 16384 produce “DOD₀ is outside the documented 0–16384 range.” Values in range do not warn.

Warning titles use the following labels: “Error Data”, “Unusual Data”, “Data Too Large”, or “Empty Data”, depending on the specific condition.

If you continuously see those warnings, consider professional hardware diagnostics.
