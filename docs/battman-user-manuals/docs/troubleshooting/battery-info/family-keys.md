---
title: Family Codes
---

# Family Codes

Family codes identify the type of power adapter or charging source connected to your device. They help identify the charging interface and capabilities of the connected adapter.

## Overview

Family codes are used by the system to:
- Determine charging capabilities and power limits
- Identify the type of connection (USB, AC, wireless, etc.)
- Apply appropriate charging protocols and safety limits
- Display adapter information in system diagnostics

## Code Values

### No Connection / Unsupported

| Code | Hex Value | Description |
|------|-----------|-------------|
| `kIOPSFamilyCodeDisconnected` | `0x00000000` | No adapter connected or detected |
| `kIOPSFamilyCodeUnsupported` | `0xE00002C7` | Adapter detected but not supported or recognized |

### FireWire

| Code | Hex Value | Description |
|------|-----------|-------------|
| `kIOPSFamilyCodeFirewire` | `0xE0008000` | FireWire (IEEE 1394) power adapter (legacy) |

### USB Power Sources

USB family codes are grouped under the `0xE0004000` base range:

| Code | Hex Value | Description |
|------|-----------|-------------|
| `kIOPSFamilyCodeUSBHost` | `0xE0004000` | USB host port (standard USB port) |
| `kIOPSFamilyCodeUSBHostSuspended` | `0xE0004001` | USB SDP (Standard Downstream Port) - low power USB port |
| `kIOPSFamilyCodeUSBDevice` | `0xE0004002` | USB device mode (device acting as USB peripheral) |
| `kIOPSFamilyCodeUSBAdapter` | `0xE0004003` | Generic USB adapter |
| `kIOPSFamilyCodeUSBChargingPortDedicated` | `0xE0004004` | USB DCP (Dedicated Charging Port) - dedicated USB charger |
| `kIOPSFamilyCodeUSBChargingPortDownstream` | `0xE0004005` | USB CDP (Charging Downstream Port) - USB port that can charge while providing data |
| `kIOPSFamilyCodeUSBChargingPort` | `0xE0004006` | USB CP (Charging Port) - generic USB charging port |
| `kIOPSFamilyCodeUSBUnknown` | `0xE0004007` | Unknown USB power source type |
| `kIOPSFamilyCodeUSBCBrick` | `0xE0004008` | USB-C brick adapter (non-PD USB-C charger) |
| `kIOPSFamilyCodeUSBCTypeC` | `0xE0004009` | USB-C Type-C port (standard USB-C connection) |
| `kIOPSFamilyCodeUSBCPD` | `0xE000400A` | USB-C PD (Power Delivery) - USB-C charger with Power Delivery protocol |

### AC Power

| Code | Hex Value | Description |
|------|-----------|-------------|
| `kIOPSFamilyCodeAC` | `0xE0024000` | AC power adapter (traditional MacBook power adapter) |

### External Power Sources

External power codes are used for proprietary or specialized charging interfaces. They are grouped sequentially starting from `0xE0024001`:

| Code | Hex Value | Description |
|------|-----------|-------------|
| `kIOPSFamilyCodeExternal` | `0xE0024001` | External Power 1 - Generic external power source |
| `kIOPSFamilyCodeExternal2` | `0xE0024002` | External Power 2 - Secondary external power source |
| `kIOPSFamilyCodeExternal3` | `0xE0024003` | External Power 3 - Baseline Arca charging interface |
| `kIOPSFamilyCodeExternal4` | `0xE0024004` | External Power 4 - Additional external power source |
| `kIOPSFamilyCodeExternal5` | `0xE0024005` | External Power 5 - Additional external power source |
| `kIOPSFamilyCodeExternal6` | `0xE0024006` | External Power 6 - MagSafe charger (wireless charging) |
| `kIOPSFamilyCodeExternal7` | `0xE0024007` | External Power 7 - MagSafe accessory (e.g., MagSafe Battery Pack) |

## Understanding USB Charging Ports

### USB SDP (Standard Downstream Port)
- Provides up to 500mA at 5V (2.5W)
- Used for standard USB data ports
- Slowest charging option

### USB DCP (Dedicated Charging Port)
- Provides up to 1.5A at 5V (7.5W)
- Designed specifically for charging (no data)
- Common on wall chargers and car chargers

### USB CDP (Charging Downstream Port)
- Provides up to 1.5A at 5V (7.5W)
- Supports both charging and data transfer simultaneously
- Found on computers and some hubs

### USB-C Power Delivery (PD)
- Can provide variable voltage and current (up to 100W+ depending on adapter)
- Negotiates power levels dynamically
- Supports fast charging on compatible devices
- Most capable USB charging standard

## Device-Specific Behavior

### MacBooks
- AC adapters show as `kIOPSFamilyCodeAC`
- USB-C adapters show as `kIOPSFamilyCodeUSBCPD` or `kIOPSFamilyCodeUSBCTypeC`

### iPhone / iPad
- MagSafe chargers appear as `kIOPSFamilyCodeExternal6`
- MagSafe accessories (like Battery Pack) appear as `kIOPSFamilyCodeExternal7`

## Troubleshooting

### "Unsupported" Family Code
If you see `kIOPSFamilyCodeUnsupported`:
- The adapter may not be Apple-certified or MFi-compatible
- The adapter may be damaged or malfunctioning
- The device may not recognize third-party adapters
- Try using an Apple-certified adapter

### "Disconnected" When Adapter is Connected
If you see `kIOPSFamilyCodeDisconnected` despite having an adapter connected:
- Check the physical connection (cable, port)
- Try a different cable or port
- The adapter may not be providing power
- Check for debris in the charging port

### USB-C Not Charging
If a USB-C adapter shows a family code but isn't charging:
- Verify the adapter supports Power Delivery (PD)
- Check that the cable supports charging (some USB-C cables are data-only)
- Ensure the adapter provides sufficient power for your device
- Check the [Not Charging Reason](../not-charging-reason) for specific error codes

### Wireless Charging Issues
For MagSafe or inductive charging:
- Ensure the device supports wireless charging
- Check that the charger is properly aligned
- Remove any cases or accessories that might interfere
- Verify the charger is Apple-certified (for MagSafe)