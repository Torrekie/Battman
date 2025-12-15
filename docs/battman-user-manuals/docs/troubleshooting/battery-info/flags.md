---
title: Flags
---

# Flags

Battman shows the raw gas‑gauge flags reported by the battery fuel‑gauge IC. These bits come directly from Texas Instruments gauges (bq274xx, bq275xx, bq20zxx) and are rendered in the **Flags** row of the Battery Info table as two bytes (High and Low).

## What you see in the app

- A hex value (e.g., `0x00CC`) shows the combined 16-bit flag word.
- Two segmented rows display the bits: the top row is the high byte, the bottom row is the low byte.
- A filled/bright segment means the bit is set; dim means clear.

## How Battman maps flags

- If the gauge model is known (from device name or board target), Battman loads the matching TI flag layout; otherwise it guesses a close layout.
- Bits are presented in two rows. Selected segments indicate set bits.
- Meanings follow the TI datasheets; key fields are summarized below.

## Common TI flag meanings

**bq2742x (incl. bq27421/25/26/27)**

High byte (left→right as shown in the UI)

| Bit | Meaning |
| --- | --- |
| OT | Over-temperature |
| UT | Under-temperature |
| EEFAIL | EEPROM write failure (27425 only) |
| FC | Full charge detected |
| CHG | Charge allowed |

Low byte (left→right)

| Bit | Meaning |
| --- | --- |
| OCVTAKEN | Open-circuit voltage sample taken |
| DODC | Depth-of-discharge correction active (421/426/427) |
| ITPOR | Power-on reset occurred |
| CFGUPMODE | In configuration update mode |
| BAT_DET | Battery detected |
| SOC1 | Low state-of-charge threshold reached |
| SOCF | Critical state-of-charge threshold reached |
| DSG | Discharging |

**bq2754x / generic bq275**

High byte (left→right)

| Bit | Meaning |
| --- | --- |
| OTC | Over-temp while charging (27545) |
| OTD | Over-temp while discharging (27545) |
| BATHI | High battery voltage |
| BATLOW | Low battery voltage |
| CHG_INH | Charging inhibited by temperature |
| FC | Full charge detected |
| CHG | Charge allowed (27545) |

Low byte — generic bq275 (left→right)

| Bit | Meaning |
| --- | --- |
| CHG_SUS | Charge suspended |
| IMAX | Imax change interrupt |
| CHG | Charge allowed |
| SOC1 | Low state-of-charge threshold reached |
| SOCF | Critical state-of-charge threshold reached |
| DSG | Discharging |

Low byte — bq27545 variant (left→right)

| Bit | Meaning |
| --- | --- |
| OCVTAKEN | Relaxed OCV sample taken |
| ISD | Internal short detected |
| TDD | Tab disconnect detected |
| HW1 / HW0 | Device ID bits |
| SOC1 | Low state-of-charge threshold reached |
| SOCF | Critical state-of-charge threshold reached |
| DSG | Discharging |

**bq20zxx (MacBook battery status)**

High byte (left→right)

| Bit | Meaning |
| --- | --- |
| OCA | Over-charged alarm |
| TCA | Terminate charge alarm |
| OTA | Over-temperature alarm |
| TDA | Terminate discharge alarm |
| RCA | Remaining capacity alarm |
| RTA | Remaining time alarm |

Low byte (left→right)

| Bit | Meaning |
| --- | --- |
| INIT | Gauge initialization |
| DSG | Discharging |
| FC | Fully charged |
| FD | Fully discharged |
| EC3 | SBS error code bit 3 |
| EC2 | SBS error code bit 2 |
| EC1 | SBS error code bit 1 |
| EC0 | SBS error code bit 0 |

## Notes

- Flag layouts mirror TI documentation; consult the specific datasheet for thresholds and timing.
- Battman displays flags read-only. Interpretation depends on charger state and the OEM thresholds. If flags consistently look wrong, the pack or gauge may be misreporting.

