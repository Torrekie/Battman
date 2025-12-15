---
title: Charging Limits
---

# Charging Limits

The **Charging Limits** configures an experimental background daemon that keeps the battery within a chosen range.

## Main concepts

- **Limit at (%)**  
  Target charge level where Battman stops charging.
- **Resume at (%)**  
  (Optional) lower threshold where charging is allowed again.
- **Drain Mode** 
  Decide whether to keep A/C power or block A/C while discharging.
- **Override OBC**  
  Optionally override Optimized Battery Charging when Battman is in control.

### Overriding OBC?

The system shipped `Optimized Battery Charging` feature is communicating with a lower interface where controlling the device’s charging states.

Normally, you should avoid using Battman’s **Charging Limit** when you are using a calibrated and authorized genuine battery part. Apple’s OBC behaves better.

If you really desired to use this feacture, please notice that OBC may prevent others from changing the charging state when **Override OBC** is disabled.

## Working states

- **Allowing charge** — daemon is running and letting the battery climb toward the limit.

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_continue.PNG" alt="Allowing charge badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **Blocking charge** — daemon is holding charge at the limit.

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_stop.PNG" alt="Stopping charge badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **No external power** — no adapter detected, so the limit cannot be enforced.

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_noext.PNG" alt="No external power badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **External power but no power** — adapter is connected but not delivering power (e.g., weak cable/negotiation/scheduled).

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_nopwr.PNG" alt="No current badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

- **Optimized Battery Charging is in control** — when running in “soft” mode which without overriding OBC, Apple’s OBC may ignore Battman’s requests. Enable “Override OBC” before starting the daemon if you need Battman to take precedence.

<p align="center" style="margin-top: -0.5em; margin-bottom: 0.5em;">
  <img src="/controls/images/Battman_badge_obc.PNG" alt="OBC badge" style="max-width: 30%; height: auto; display: block; margin: 0 auto;" />
</p>

## Warnings

- This feature is still experimental and may now working correctly on your device.
- This feature writes directly to system power interfaces and runs long‑lived background code.
- Currently, Battman's "daemon" runs as a regular background process and does not use the system's `LaunchDaemons` feature. As a result, rebooting or performing an ldrestart will stop the charging limit process, and you will need to manually restart it for the feature to take effect again.