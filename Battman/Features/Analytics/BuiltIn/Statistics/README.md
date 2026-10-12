# Statistical canvases

The host builds these statistical card sources:

- `BAStatisticsAnalysis.m`
- `BAStatisticsCanvasCards.m`
- `BAStatisticsDrawing.m`
- `BAAnalyticsDwellCanvasCard.m`
- `BAAnalyticsCompareCanvasCard.m`
- `BAAnalyticsRhythmCanvasCard.m`

Factory: `BAAnalyticsCreateStatisticalCanvasCards()`, declared in the shared Canvas contract and `BAStatisticsCanvasCards.h`. Identifiers are `com.torrekie.battman.analytics.dwell`, `com.torrekie.battman.analytics.compare`, and `com.torrekie.battman.analytics.rhythm`. Supported sizes are dwell 1×2/2×2, compare 1×2/2×1/2×2, and rhythm 2×1/2×2. These cards use SDK v1 registration.

Each card and its optional detail controller live in the corresponding independent source file. These three cards opt into precise graphical drill-down: dwell highlights the selected time-weighted bin; comparison shows independent session-duration dots with the selected session highlighted; rhythm expands one civil day into signed hourly rates and observation coverage. The detail receives the immutable derived result that produced the card, so report or time-zone changes cannot silently alter an open selection. The shared detail base provides only readable evidence and optional source disclosure. All visible prose and VoiceOver descriptions use Battman's gettext macro; a runtime thermometer and connection glyph replace redundant graph legend text.

Statistics consume immutable normalized reports only. Canonical trusted intervals, independently unioned for the required fields, establish coverage. General report gaps can also describe another field/source, so they are not blindly subtracted from an independently trusted canonical pair. Missing time is the complement of the applicable trusted coverage. Missing adjacent trusted pairs and session-owned gaps prohibit complete comparisons. Interpolation always uses the **original observation timestamps and values**, even after the report clips an interval.

Dwell uses time-weighted half-open SOC bins, with 100% included in the final bin. The temperature matrix requires jointly valid SOC and temperature. Trusted linear crossings split duration at SOC and temperature boundaries; details disclose the estimate, actual coverage, connected/unplugged/unknown state breakdown, and bounded contributor spans. Span summaries include original observed endpoint values, original timestamps/IDs and validated source/unit metadata, separately from clipped/interpolated estimates. This retains auditable evidence when shared observation filters exclude both endpoints of a crossing pair.

Comparison consumes only producer-selected compatible candidates; it does not parse opaque IDs or infer replacement from FCC variation. It additionally requires complete session boundaries, contiguous trusted SOC/connection pairs, validated connected endpoints, consistent measurement provenance, and both upward 20→80% crossings. Duplicate/overlapping sessions and missing crossings are excluded with counts and preview reasons. The first trusted upward 20% crossing and first subsequent upward 80% crossing define the estimate; observed pauses and reversals remain included. Temperature peaks are actual validated samples within that same SOC range, with separate temperature coverage. Q1/Q3 use lower/upper halves excluding the central odd-n item, whiskers use observed min/max, and n<3 shows individual points.

Rhythm uses local calendar day/hour boundaries and UTC offsets, preserves repeated DST hours, and omits nonexistent hours from elapsed coverage. It divides signed observed SOC decline by actual valid unplugged seconds. The compact daily view uses the same time-weighted rate; it does not average hourly cells equally. Connected grey, missing/unknown hatching, and valid zero marks are distinct. A negative rate retains an observed SOC rise and does not infer charging. Unknown sampled states are conservatively excluded from unplugged rates.

Graph selections preserve report sequence, family, metric, normalized time range and up to 256 source IDs. Bins include `context.filters` with `minimum`, `maximum`, and `includeMaximum`; the last SOC bin includes 100%. Detail contexts retain aggregate totals while bounding span/session/hour previews to the shared 256-node/8-KiB budget; preview truncation is explicit. Large Dynamic Type uses a scrollable evidence list with the same selections. Editing gates both graph and list actions. Normal graph accessibility and 44-point target expansion use the shared Canvas implementation.

## Validation

The Foundation check links the data model/report implementations and statistical calculator from the current source tree. Run it on macOS with Xcode command-line tools:

```
python3 Battman/Features/Analytics/BuiltIn/Statistics/Tests/run_statistics_tests.py
```

It covers original-endpoint clipping, overlapping field coverage union, 100% inclusion, missing joint temperature, missing trusted pairs, complete/partial/duplicate comparisons, observed temperature peaks, FCC fluctuations, small-n boxes, 167/169-hour DST weeks and repeated offsets, weighted rates, connected/unknown/zero distinctions, property-list details, preview budget limits, and observed-versus-interpolated span values. `Tests/BAStatisticsMathTests.c` provides pure C checks for elapsed weighting, SOC/temperature crossings, missing/gap exclusion, and odd/even/small-n quantiles.

`Tests/Simulator/run-analytics-card-screenshots.sh` renders production canvases using synthetic reports on a caller-selected, already booted Simulator. It exercises supported sizes, localization, Dynamic Type, missing data, selection details, editing, and dense-history preparation. Generated screenshots and validation results belong in the caller's output directory.

Historical temperature is displayed only when its source and unit are validated. Joint temperature distributions and temperature peaks remain unavailable without such data. Synthetic validated temperature is confined to the UI fixture; production cards do not substitute demonstration data.
