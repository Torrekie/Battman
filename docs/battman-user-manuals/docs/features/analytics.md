---
title: Analytics
---

# Analytics

The Analytics tab in Battman 1.1.0 contains ten built-in cards. Its shared
visible-only metrics service samples when cards are visible and stops when you
leave the tab or the app enters the background. Historical cards separately
read the system's available Powerlog records. History may extend before your
current app session; the short live curve does not.

## Arrange and explore cards

Tap **Edit** to add, remove, resize, or reorder cards, then **Done** to save the
layout. Supported sizes vary by card. Outside editing, tap a supported graph
point, interval, bin, or session to inspect its details; some cards also provide
an **Open** action. Large text and VoiceOver offer readable descriptions of the
same observations. If a card provider is removed, its saved position remains an
**Unavailable** card until you remove it or restore that provider.

## The ten built-in cards

| Card | What it shows | How to interpret it |
| --- | --- | --- |
| Current Battery | Charge level, charging state, Low Power Mode, current, temperature, and a short power curve | Fields can be missing independently. Net power and an explicitly labeled average are different readings. The curve covers foreground samples only. |
| Capacity observations | Full-charge capacity, design capacity, cycle observations, and available capacity history | Ratios need compatible design capacity. A capacity change alone does not prove a battery replacement. |
| Cell consistency | Available main-battery cell voltages and their spread | Spread needs at least two valid channels from the same observation. Current readings are labeled when history is absent; missing channels are not invented. |
| Connected session | Charge level, signed current, and temperature during an observed connection | A connected cable does not prove charging. Sampled boundaries, pauses, and gaps remain visible. |
| Battery discharge | Charge-level decline and battery output while unplugged | Missing output and an unknown reconnection time remain distinct. The graph does not identify which app used the energy. |
| Connection and charging states | Observed connected, charging, full, unknown, and conflicting states | Transition times are sample-bounded. An absent not-charging reason is not inferred. |
| Power readings | Input, battery net power, budget, and target, when available | These are different measurement points and observation times. Budget and target are not delivered power; subtracting them does not establish efficiency or loss. |
| Time by battery level | Time-weighted charge-level distribution, with temperature where validated | Missing time is excluded and disclosed. This is not a damage or battery-health score. |
| Charging comparison | Comparable complete charging sessions with trusted upward 20–80% crossings | Partial, duplicate, overlapping, and gapped sessions are excluded. Few qualifying sessions may leave only individual points or no comparison. |
| Discharge rhythm | Signed charge-level change per valid unplugged hour, grouped by local calendar time | Connected time, missing time, and measured zero are different. A negative rate preserves an observed charge-level rise without assuming charging. |

**Charge Gauge** and the SDK Analytics card are developer examples distributed
as source only, separate from these ten built-in cards. See
[Native plug-ins](plugins.md) for developing and testing your own card.

## Missing, partial, and cached data

**Unavailable** means the device or environment did not supply a usable
measurement. An empty historical graph may mean no readable Powerlog source,
no supported fields, insufficient samples, or no session meeting that card's
conditions. It is not the same as a measured zero. The first history result can
arrive after current readings, and archived records can add more coverage later.

Battman retains local startup readings and completed history reports to make
reopening the page faster. Cached values are labeled; **Showing cached history;
refreshing in background** means the displayed history is an earlier completed
report while the app is refreshing it. Here “background” means asynchronous
work while Analytics is active, not continuous sampling after the app closes.
Read the displayed age, coverage, and gaps before comparing measurements.

Refreshes cannot recover observations that the system never recorded or no
longer retains. Reopening Analytics allows a new read, but does not guarantee
more history. [Wiping Battman data](../preferences/wiping-data.md) removes its
local caches and layout; it does not erase the system's original Powerlog
records or make unsupported measurements available.

History-derived cards use validated sources and units. They do not substitute
demonstration values for missing temperatures, cell channels, or power readings.
The charts describe observed behavior and are not a battery diagnosis.

Native plug-ins can add cards, but execute inside Battman with its process
access. Review their source and trust requirements before approval.
