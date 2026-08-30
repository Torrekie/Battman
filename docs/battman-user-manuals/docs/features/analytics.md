---
title: Analytics
---

# Analytics

The Analytics tab presents battery, temperature, charging, capacity, cycle, and
power information as cards. Values come from one shared, visible-only metrics
service: Battman starts sampling when an Analytics card is visible and stops
when you leave the tab or the app moves to the background. A value marked
**Unavailable** means the device or current environment did not provide that
measurement; it is not replaced with an estimate.

Tap **Edit** to add, remove, resize, or reorder cards. Battman preserves this
layout. If a card provider is removed later, its place remains as an
**Unavailable** card so you can identify or remove it instead of silently
losing the layout. A card may provide an **Open** action for more detail.

Built-in cards are part of Battman. Native plug-ins can provide additional
cards, but they are in-process code and receive the same process access as
Battman. Read [Native plug-ins](plugins.md) before approving one.
