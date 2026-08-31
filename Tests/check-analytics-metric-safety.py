#!/usr/bin/env python3
"""Static regression checks for hardware-backed Analytics metrics.

The checks are intentionally host-only.  They assert that unavailable SMC
readings are represented by missing metrics, that cell-temperature reads are
bounded, and that the user-facing cards explain health/cycle/temperature
semantics instead of displaying fabricated zeroes.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LIBSMC = (ROOT / "Battman/battery_utils/libsmc.c").read_text(encoding="utf-8")
LIBSMC_H = (ROOT / "Battman/battery_utils/libsmc.h").read_text(encoding="utf-8")
BATTERY_INFO = (ROOT / "Battman/battery_utils/battery_info.c").read_text(encoding="utf-8")
BATTERY_INFO_HEADER = (ROOT / "Battman/battery_utils/battery_info.h").read_text(encoding="utf-8")
BATTERY_CELL = (ROOT / "Battman/BatteryCellView/BatteryInfoTableViewCell.m").read_text(encoding="utf-8")
TEMP_CELL = (ROOT / "Battman/BatteryCellView/TemperatureInfoTableViewCell.m").read_text(encoding="utf-8")
TEMP_PAGE = (ROOT / "Battman/SimpleTemperatureViewController.m").read_text(encoding="utf-8")
HID = (ROOT / "Battman/battery_utils/hid.m").read_text(encoding="utf-8")
BUILT_IN_CARD = (ROOT / "Battman/Features/Analytics/BuiltIn/BAAnalyticsBuiltInCard.m").read_text(encoding="utf-8")
TEMP_CARD = (ROOT / "Battman/Features/Analytics/BuiltIn/BAAnalyticsTemperatureAverageCard.m").read_text(encoding="utf-8")
HEALTH_CARD = (ROOT / "Battman/Features/Analytics/BuiltIn/BAAnalyticsBatterySummaryCard.m").read_text(encoding="utf-8")
CAPACITY_CARD = (ROOT / "Battman/Features/Analytics/BuiltIn/BAAnalyticsRemainingCapacityCard.m").read_text(encoding="utf-8")
CYCLE_CARD = (ROOT / "Battman/Features/Analytics/BuiltIn/BAAnalyticsCycleSummaryCard.m").read_text(encoding="utf-8")
METRIC_SOURCE = (ROOT / "Battman/Features/Analytics/Data/BAAnalyticsSystemMetricSource.m").read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: missing {label}: {needle}")


require(LIBSMC_H, "battman_temperature_is_valid", "shared temperature validity rule")
require(LIBSMC_H, "get_temperature_per_cell_with_count(size_t *out_count)", "atomic cell-temperature snapshot API")
require(LIBSMC, "if (num <= 0 || num > 32)", "bounded cell-count guard")
require(LIBSMC, "*out_count = (size_t)num", "cell count matches returned temperature array")
require(LIBSMC, "float *cells = calloc((size_t)num, sizeof(*cells));", "checked cell allocation")
require(LIBSMC, "if (!allValid)", "all-cell validity check")
require(LIBSMC, "scaledRemaining > UINT16_MAX", "capacity multiplication overflow guard")
require(LIBSMC, "return true;", "capacity success is independent of optional key metadata")
require(BATTERY_INFO, "Gas Gauge values are read from AppleSMC", "SMC source explanation")
require(BATTERY_INFO, "bool capacitiesValid = capacityOK && full_cap > 0 && design_cap > 0", "zero-capacity unavailable guard")
require(BATTERY_INFO, "bool healthOK = capacitiesValid &&", "health unavailable guard")
require(BATTERY_INFO, "bool cycleCountOK = smc_read_n('B0CT'", "cycle-count read status")
require(BATTERY_INFO, "battman_temperature_is_valid(averageTemperature)", "battery-info temperature guard")
require(BATTERY_INFO, "if (!hasSMC)", "unsupported-SMC safe path")
require(BATTERY_INFO_HEADER, "BIN_DYNAMIC_HIDDEN", "refresh-scoped unavailable marker")
require(BATTERY_INFO_HEADER, "BIN_DYNAMIC_HIDDEN_VISIBILITY", "dynamic visibility provenance marker")
require(BATTERY_INFO, "BIN_SECTION) == BIN_SECTION", "section priority is preserved while hiding")
require(BATTERY_INFO, "bool hadIntrinsicHidden", "intrinsic hidden-row preservation")
require(BATTERY_INFO, "bool alreadyDynamic", "repeated unavailable refresh provenance")
require(BATTERY_INFO, "bool addedVisibility = alreadyDynamic", "dynamic visibility marker survives re-hide")
if "abort(); // this section should not have been added" in BATTERY_INFO:
    raise SystemExit("FAIL: SMC refresh still aborts when the connection disappears")

require(BATTERY_CELL, "if (!updatedForeground)", "stale foreground gauge reset")
require(BATTERY_CELL, "if (!updatedBackground)", "stale background gauge reset")
require(TEMP_CELL, "Temperature is unavailable because no valid hardware reading was returned.", "temperature unavailable copy")
require(TEMP_CELL, "get_temperature_per_cell_with_count(&cellCount)", "temperature cell count is paired with the sample")
require(TEMP_CELL, "[self.temperatureCell updatePercentage:0.0]", "neutral unavailable gauge")
if "arc4random_uniform" in TEMP_CELL or "Who moved my temperature sensors?" in TEMP_CELL:
    raise SystemExit("FAIL: unavailable temperature still uses the random animation")
if "total / num" in TEMP_CELL:
    raise SystemExit("FAIL: temperature average can divide by an invalid cell count")
require(TEMP_PAGE, "getTemperatureHIDData()", "temperature page refreshes HID snapshots")
require(TEMP_PAGE, "getSensorTemperatures()", "temperature page refreshes sensor snapshots")
require(TEMP_PAGE, "dispatch_queue_create(\"com.torrekie.Battman.temperature-sensors\"", "temperature snapshots leave the main thread")
require(TEMP_PAGE, "validTemperature =", "temperature page filters invalid sensor values")
THERM_TEST = (ROOT / "Battman/ThermAniTestViewController.m").read_text(encoding="utf-8")
require(THERM_TEST, "get_temperature_per_cell_with_count(&cellCount)", "thermometer test uses paired cell count")
require(HID, "CFBridgingRelease(IOHIDEventSystemClientCopyServices(client))", "HID service ownership transfer")
require(HID, "CFRelease((CFTypeRef)event)", "HID event release")
require(HID, "static NSDictionary *skinModelsByProduct = nil", "persistent HID skin-model cache")
if "__block NSDictionary *skinModelsByProduct" in HID:
    raise SystemExit("FAIL: HID skin-model cache is block-local and disappears after dispatch_once")
require(BUILT_IN_CARD, "self.detailLabel.numberOfLines = compact ? 1 : 0", "compact card detail visibility")
require(BUILT_IN_CARD, "addObjectsFromArray:presentation.detailLines", "compact card accessibility detail")
require(METRIC_SOURCE, "(settings[0] != UINT8_MAX && settings[1] == UINT8_MAX)",
        "analytics rejects resume-only charging-limit settings")
require(METRIC_SOURCE, "settings[0] >= settings[1]", "analytics rejects equal charging-limit thresholds")

for card, label in (
    (TEMP_CARD, "temperature card"),
    (HEALTH_CARD, "health card"),
    (CAPACITY_CARD, "capacity card"),
    (CYCLE_CARD, "cycle card"),
):
    require(card, "Unavailable", f"{label} unavailable state")

require(TEMP_CARD, "Potentially Stale", "temperature stale state")
require(TEMP_CARD, "No change detected for several minutes", "temperature stale explanation")
require(TEMP_CARD, "if (span >= 240.0)", "temperature stale horizon")
require(HEALTH_CARD, "Health is calculated from Full Charge Capacity and Designed Capacity", "health explanation")
require(CYCLE_CARD, "Cycle count is reported by the battery controller", "cycle explanation")
require(CYCLE_CARD, "Designed Cycle Count is a manufacturer reference", "designed-cycle explanation")

print("Analytics metric safety checks: PASS")
