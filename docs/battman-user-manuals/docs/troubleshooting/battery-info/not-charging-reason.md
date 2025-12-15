---
title: Not Charging Reason
---

# Not Charging Reason

The "Not Charging Reason" is a diagnostic value that explains why your device is not charging when a charger is connected. This information is read from the Apple SMC (System Management Controller) and helps identify the root cause of charging issues.

## Overview

The Not Charging Reason is stored in the SMC key `CHNC` (Charger Not Charging) and can have different formats depending on your device's generation:

- **Version 0 (NonSMC)**: Legacy devices without SMC support
- **Version 1 (Gibraltar/BNCR)**: Enum-based format used on specific Intel Mac models
- **Version 2 (SMC/CHNC)**: Bitmask-based format used on Apple Silicon and most modern devices

The version is determined by reading the `RGEN` (Reason Generation) SMC key.

## Version 2 (SMC/CHNC) - Modern Devices

Version 2 uses a bitmask format where multiple reasons can be active simultaneously. This is the format used on Apple Silicon Macs and most modern devices as of 2025.

### Common Reasons

| Reason | Description |
|--------|-------------|
| **Fully Charged** | Battery has reached 100% charge capacity |
| **Too Cold** | Battery temperature is below the minimum threshold to stop charging |
| **Too Hot** | Battery temperature is above the maximum threshold to stop charging |
| **Too Cold To Start** | Battery temperature is too low to begin charging |
| **Too Hot To Start** | Battery temperature is too high to begin charging |

### Presence Issues

| Reason | Description |
|--------|-------------|
| **Charger Watchdog Timeout** | Charging has been active for over 15 hours, or charge timeout flag is set |
| **Battery Not Present** | System cannot detect the battery |
| **VBUS Not Present** | No power detected on the USB power bus |

### Charging Inhibit Conditions

| Reason | Description |
|--------|-------------|
| **High SoC High Temp Stopped** | Charging stopped due to high state of charge combined with high temperature |
| **Sensor Communication Failed** | Communication with battery management sensors has failed |

### System Modes

| Reason | Description |
|--------|-------------|
| **Accessory Connecting** | IOAccessoryManager is managing an accessory connection |
| **Kiosk Mode** | Device is in kiosk mode, which may inhibit charging |
| **CoreMotion** | CoreMotion framework is controlling charging behavior |
| **USB-PD Connecting** | USB Power Delivery negotiation in progress |

### Charging Control

| Reason | Description |
|--------|-------------|
| **setbatt Controlled** | Charging is being controlled by the `setbatt` tool or similar system utility |
| **Predictive Charging** | System is using predictive charging to optimize battery health |
| **Wireless Charger Controlled** | Wireless/inductive charger is managing the charging process |
| **Gas Gauge FW Updating** | Battery gas gauge firmware is being updated (common with MagSafe chargers) |
| **Battery Inhibit Inflow Unsupported** | Battery hardware doesn't support software-controlled charge inhibition |
| **PCTM** | Power Control Thermal Management is active |
| **Inhibit Client Adapter** | Client adapter charging is inhibited |
| **Cell Voltage Too High** | One or more battery cells have exceeded safe voltage limits |
| **Battery Not Requesting Charge** | Battery management system is not requesting charge |
| **Camera Streaming** | Continuity Camera or webcam streaming is active (macOS 13 / iOS 16+) |

### System Controls

| Reason | Description |
|--------|-------------|
| **VACTFB** | Voltage/current feedback system is controlling charging |
| **Field Diagnostics** | Device is in field diagnostics mode |
| **Inhibit Inflow** | System has explicitly inhibited charge inflow |
| **Carrier Mode Testing** | Device is in carrier testing mode |

### Permanent Faults

These indicate serious hardware or firmware issues that may require service:

| Reason | Description |
|--------|-------------|
| **Charged Too Long** | Battery has been charging for an excessive duration |
| **Vbatt Fault** | Battery voltage fault detected |
| **Ibatt MinFault** | Battery current minimum fault detected |
| **Charger Communication Failure** | Communication with the charger has failed |
| **Cell Check Fault** | Battery cell integrity check failed |

When any permanent fault is detected, the system may display "Permanent Battery Failure" as the primary reason.

## Version 1 (Gibraltar/BNCR) - Intel Mac Models

Version 1 uses an enum-based format where only one reason is active at a time. This format is used on specific Intel Mac models:

- J132, J137, J140, J152, J213, J214, J215, J680, J780

### Common Reasons

| Value | Reason | Description |
|-------|--------|-------------|
| `NO_REASON` | No Reason | Device is charging normally |
| `NO_AC` | No AC Power | No AC adapter detected |
| `NO_BATTERY` | No Battery | Battery not detected |
| `BAD_BATTERY` | Bad Battery | Battery health check failed |
| `BATTERY_FC` | Fully Charged | Battery is at full capacity |
| `BATTERY_NO_CHG_REQ` | Battery Not Requesting Charge | Battery management system not requesting charge |
| `AC_INSERT` | Using AC Power | Device is running on AC power only |
| `G3` | G3 Mechanical Off | Device is in G3 power state |
| `ADAPTER_DISABLED` | Adapter Disabled | Charger adapter is disabled |
| `ADAPTER_UNKNOWN` | Unknown Adapter | Charger adapter is not recognized |
| `ADAPTER_NOT_ALLOW_CHARGING` | Adapter Not Allowed | Charger adapter is not authorized for charging |
| `CALIBRATION` | Calibration | Battery is being calibrated |
| `B0LI_0` | Charging Disabled | Charging has been disabled |
| `OS_NO_CHG` | OS Charging Disabled | Operating system has disabled charging |
| `BCLM_REACHED` | Charging Limit Reached | Battery charge limit has been reached |
| `UPSTREAM_NO_CHG` | Upstream Charging Disabled | Upstream charging control disabled |
| `PM_NO_CHG` | PowerManagement Charging Disabled | Power management has disabled charging |
| `TB0T_OVER_50` | Battery Temperature over 50℃ | Battery temperature exceeds 50°C |
| `TB0T_OVER_45` | Battery Temperature over 45℃ | Battery temperature exceeds 45°C |
| `TEMP_GRADIENT_TOO_HIGH` | Temperature Gradient Too High | Battery temperature is changing too rapidly |
| `TEMP_NOT_ATV_VLD` | Temperature Not Valid | Battery temperature reading is invalid |
| `BATTERY_TCA` | Battery TCA | Battery thermal control active |
| `OW_TDM_LINK_ACTIVE` | One-Wire TDM Link Active | One-wire communication active |
| `CELL_VOLTAGE_TOO_HIGH` | Cell Voltage Too High | Battery cell voltage exceeds safe limits |
| `OBC_NO_CHG` | Predictive Charging | Optimized Battery Charging is active |
| `VACTFB_NO_CHG` | VACTFB No Charge | Voltage/current feedback preventing charge |
| `OBC_NO_INFLOW` | Predictive Charging (Inflow) | Optimized Battery Charging preventing charge inflow |

## Version 0 (NonSMC) - Legacy Devices

Version 0 is used on very old devices that don't have SMC support. Known devices include:

- D10, D11
- J71, J72, J73, J81, J82, J85, J86, J87, J96, J97, J98, J99, J120, J121, J127, J128, J171, J172, J207, J208
- N27, N28, N61, N66, N69, N71, N74, N75, N111, N121

### NonSMC Specific Reasons

| Reason | Description |
|--------|-------------|
| **POSM Mode** | Power On Self Test mode |
| **Display** | Display-related charging control |
| **Too Cold** | Battery temperature too low |
| **Too Hot** | Battery temperature too high |
| **Done** | Charging complete |
| **Too Long** | Charging duration exceeded |
| **CHG_WD** | Charger watchdog timeout |

## Interpreting the Value

The Not Charging Reason is typically displayed as a hexadecimal value (e.g., `0x00000001`). In Version 2 (bitmask format), multiple bits can be set simultaneously, indicating multiple reasons.

### Example Interpretations

- `0x00000001` - Fully Charged
- `0x00000002` - Too Cold
- `0x00000004` - Too Hot
- `0x00000003` - Fully Charged AND Too Cold (both bits set)

## Troubleshooting Tips

1. **Temperature Issues**: If you see "Too Cold" or "Too Hot" reasons, allow the device to reach a normal operating temperature (typically 0-35°C).

2. **Predictive Charging**: If "Predictive Charging" is shown, this is normal behavior. The system is learning your usage patterns to optimize battery health.

3. **Firmware Updates**: "Gas Gauge FW Updating" is temporary and should resolve once the update completes.

4. **Permanent Faults**: If you see any permanent fault reasons, the battery or charging system may need service.

5. **Multiple Reasons**: In Version 2, multiple reasons can be active. Check all listed reasons to understand the complete charging state.

## Technical Notes

- The Not Charging Reason is read from SMC key `CHNC` (8 bytes on most devices, 64 bytes on mobile devices)
- The generation/version is determined by SMC key `RGEN`
