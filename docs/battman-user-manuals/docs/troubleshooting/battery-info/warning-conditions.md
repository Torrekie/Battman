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
    - Warns when cycle count exceeds the design target. If the design value is not provided by the gauge, Battman infers it based on Apple official documentation (before iPhone 15: 500; newer iPhone, iPad, Watch, MacBook: 1000; iPod: 400). Message: “Cycle Count exceeded designed cycle count, consider replacing with a genuine battery.”
- **Time to Empty**
    - When discharging, Battman compares the reported time‑to‑empty against an ideal estimate (capacity ÷ discharge current). If reported TTE is more than 1.5× the ideal, it flags “Unusual Time to Empty, a non-genuine battery component may be in use.”
- **Depth of Discharge**
    - Flags “Unusual Depth of Discharge, a non-genuine battery component may be in use.” when DOD0 is more than 3× Qmax, which is atypical even with load or charge attached.

Warning titles use the following labels: “Error Data”, “Unusual Data”, “Data Too Large”, or “Empty Data”, depending on the specific condition.

If you continuously see those warnings, consider professional hardware diagnostics.
