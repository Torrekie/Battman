---
title: Brightness Backends
---

# Brightness Backends

Battman distinguishes between different **brightness backends** used by the system display.

- **Standard** – classic backlight control path used on older or simpler devices.
- **DCP** – Display Co‑Processor based pipeline used on newer devices (A14 or above) with more complex panel control.

## Why it matters

- Different backends may expose different limits, ramps and latency characteristics.
- Some advanced features (HDR, high refresh rates) are usually tied to DCP‑based pipelines.
- Bugs or quirks can be backend‑specific; knowing which backend is active can help when reporting issues.

This field is informational only; you cannot switch backends from within Battman.
