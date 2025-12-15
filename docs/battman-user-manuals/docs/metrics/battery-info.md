---
title: Battery Info
---

# Battery Info

The **Battery Info** page in Battman shows detailed information read directly from the device’s battery gas-gauge and `IOAccessoryManager`.

It corresponds to the **Battery Info** section on the Battery tab.

## What You May Want to Know

- Current charge level (%), voltage, and current
- Design capacity, nominal/actual full-charge capacity, and cycle count
- Charging state and power source (USB, adapter, wireless, MagSafe, etc.)
- Not-charging reasons

Unlike other tools that are based on `IOPM`, Battman does **not** guess or smooth values: it exposes the deepest raw metrics that the hardware reports.

## Subsections

On the "Battery Info" page, you may see the following sections, depending on your device's current state:

- [Gas Gauge (Basic)](#gas-gauge-basic)
- [Adapter Details](#adapter-details)
- [Inductive Port / Serial Port](#inductive-port--serial-port)

Each section lists the detected metrics from different parts.

### Gas Gauge (Basic)

This section displays the most commonly used Gas Gauge metrics.

#### Device Information

| Field | Description |
| --- | --- |
| Device Name | Gas Gauge IC used by the installed battery (e.g., `bq20z451`). |
| Battery Serial No. | Serial number of the battery pack. |
| Chemistry ID | ChemID used to match battery-specific strategies shipped in the OS. |
| Cell Count | Number of cells in the pack (e.g., `3` for a 3‑cell battery). |

#### Capacity Metrics

| Field | Description |
| --- | --- |
| Full Charge Capacity | Current maximum charge capacity in mAh, reported by the Gas Gauge IC. |
| Designed Capacity | Original design capacity in mAh when the battery was new. |
| Remaining Capacity | Current remaining charge capacity in mAh. |
| Qmax | Designed maximum chemical capacity of the pack. |
| True Remaining Capacity | Actual remaining capacity in mAh, reported by the BMS. |
| Battery Uptime | Time the battery has been in use since the last reset. |

#### Discharge Metrics

| Field | Description |
| --- | --- |
| Depth of Discharge (DOD₀) | Chemical depth of discharge, updated from OCV readings in a `relaxed` state. |
| Passed Charge | Cumulative capacity of the current charge/discharge cycle; resets with each DOD₀ update. |

#### Electrical Measurements

| Field | Description |
| --- | --- |
| Voltage | Average working voltage in mV (e.g., `11433 mV`). |
| Avg. Current | Average working current in mA (negative = discharging, e.g., `-807 mA`). |
| Avg. Power | Average working power in mW (negative = consumption, e.g., `-9226 mW`). |
| OCV Current | Open-circuit voltage current measurement. |
| OCV Voltage | Open-circuit voltage measurement. |
| Max Load Current | Maximum load current the battery can handle. |
| Max Load Current 2 | Secondary maximum load current measurement. |

#### State of Charge

| Field | Description |
| --- | --- |
| State of Charge | Battery percentage reported by the Gas Gauge IC. |
| State of Charge (UI) | SoC shown in the UI (differ from actual SoC). |
| Daily Max SoC / Daily Min SoC | Highest/lowest SoC reached in a day, reported by the BMS. |

#### Time Estimates

| Field | Description |
| --- | --- |
| Time to Full | Estimated time until the battery reaches full charge. |
| Time to Empty | Estimated time until the battery is depleted. |

#### Cycle Information

| Field | Description |
| --- | --- |
| Cycle Count | Charge/discharge cycles completed (e.g., `1145`). |
| Designed Cycle Count | Maximum cycles the battery is designed to handle. |

#### Temperature

| Field | Description |
| --- | --- |
| Avg. Temperature | Average working temperature reported by the Gas Gauge IC (e.g., `30.73 °C`). |

#### Advanced Metrics

| Field | Description |
| --- | --- |
| Resistance Scale | Scaling factor used for resistance calculations. |
| Flags | See [Flags](../../troubleshooting/battery-info/flags). |
| IT Misc Status | Impedance Track miscellaneous status information. |
| Simulation Rate | Rate at which the Gas Gauge performs Impedance Track™ simulations. |

### Adapter Details

This section displays information about the current working adapter<sup>\[1\]</sup>.

!!! note "Working Adapter"
    When one or multiple adapters are connected, the device will choose the best adapter as the working external power source; others will be inhibited.

#### Connection Information

| Field | Description |
| --- | --- |
| Port | Numeric ID of the port in use. iPhone/iPad: `1` Serial (Lightning/USB-C), `2` Inductive (MagSafe/Wireless). MacBooks: `1` USB port 1, `2` USB port 2. |
| Adapter Type | Numeric ID describing the current adapter type (undocumented). |
| Type | Family code (`kIOPSPowerAdapterFamilyKey`) of the connected adapter. See [Family Keys](../../troubleshooting/battery-info/family-keys). |

#### Charging Status

| Field | Description |
| --- | --- |
| Status | Charging status: `Charging` or `Not Charging`. |
| Reason | Reason code when not charging. See [NotChargingReason](../../troubleshooting/battery-info/not-charging-reason). |
| Charger Capable | Adapter is identified as a compatible power source. |
| External Connected | Adapter is present and usable as a stable power source / UPS. |

#### Power Specifications

| Field | Description |
| --- | --- |
| Current Rating / Voltage Rating | Designed current/voltage the adapter provides. |
| Input Current / Input Voltage | Actual input current/voltage being received. |
| Charging Current / Charging Voltage | Final current/voltage charging the battery. |
| PMU Configuration / Charger Configuration | Charging current limit set by the PMU/charger. |
| HVC Mode | High Voltage Charging modes allowed by the adapter hardware (not user-configurable). |

#### Hardware Information

| Field | Description |
| --- | --- |
| Charger IC ID | Numeric ID of the device's charger IC. `0xFFFFFFFF` on some USB‑C devices means no readable IC ID. |

#### Adapter Identification

The following fields are only available when an adapter is designed to work with Apple devices (or emulates an Apple/MFi genuine adapter):

| Field | Description |
| --- | --- |
| Model Name | Adapter model name (e.g., "61W USB-C Power Adapter"). |
| Manufacturer | Vendor name (e.g., "Apple Inc."). |
| Model | Model number (e.g., `0x1685`). |
| Firmware Version | Firmware version (e.g., `01050029` → `1.5.0.29`). |
| Hardware Version | Hardware version (e.g., `1.0`). |
| Serial No. | Adapter serial (e.g., `C4H306600XDL4YRAD`). |
| Description | PMU description of the adapter type (e.g., "pd charger"). |

### Inductive Port / Serial Port

When your device is connecting to an inductive power accessory / USB accessory which providing it’s informations, this section will appear in your page.

#### Identification

| Field | Description |
| --- | --- |
| Acc. ID | Systen internally used numeric ID of the attached accessory. |
| Digital ID | (Lightning only) Chip ID of the accessory. |
| ID Serial No. | (Lightning only) Interface Device Serial Number (ID‑SN). |
| IM Serial No. | (Lightning only) Interface Module Serial Number (MSN). |
| PPID | Accessory PPID (manufacturer-provided identifier). |
| Port Type | Connecting port type, from `IOAccessoryManager`. |
| Allowed Features | Accessory feature flags (may be device-specific). |
| Serial No. | (MagSafe only) Serial number of the accessory. |
| Manufacturer | Accessory vendor. |
| Product ID | HID PID. |
| Vendor ID | HID VID. |
| Model | Accessory model (e.g., `A2384`). |
| Name | Accessory name (e.g., "MagSafe Battery Pack"). |
| Firmware Version | Accessory firmware version (e.g., `2.7.b.0`). |
| Hardware Version | Accessory hardware version (e.g., `1.0.0`). |

#### Power Role

| Field | Description |
| --- | --- |
| Battery Pack | Indicates if the accessory acts as a [Smart Battery Case](https://apple.fandom.com/wiki/Smart_Battery_Case). |
| Providing Power | Accessory is working as a power source. |
| Status | (MagSafe only) Current accessory working status. |
| Accepting Charge | (Accessory UPS only) Accessory is accepting charge. |

#### Accessory Battery (UPS)

| Field | Description |
| --- | --- |
| State of Charge | Accessory battery percentage. |
| Max Capacity | Accessory battery full-charge capacity. |
| Current Capacity | Accessory battery current capacity. |
| Avg. Charging Current | Average charging current when accepting charge. |
| Charging Voltage Rating | Charging voltage rating. |
| Cell Count | Battery cell count of the accessory pack. |
| Cycle Count | Cycle count of the accessory pack. |
| Current / Voltage | Real-time accessory output current/voltage. |
| Incoming Current / Incoming Voltage | Real-time current/voltage received by the device. |
| Temperature | Current accessory temperature. |
| Acc. Time to Full / Acc. Time to Empty | Time estimates from the accessory gas gauge IC. |
| Power Mode | Active power modes of the accessory. |
| Sleep Power | Sleep power modes of the accessory. |
| Supervised Acc. Attached | Whether the accessory is marked as **supervised**. |
| Supervised Transports Restricted | Whether supervised transports are restricted. |

#### USB (Serial Port Only)

| Field | Description |
| --- | --- |
| USB Connect State | Current USB device connect state. |
| USB Charging Volt. | Current USB device charging voltage. |
| USB Current Config | Current USB device charging current configuration. |