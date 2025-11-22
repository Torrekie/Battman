# Battman
Strayers' modern battery manager for their good old iOS devices.

### 🌍
[简体中文](docs/README-zh_CN.md)

## Screenshots
<div style="width:20%; margin: auto;" align="middle">
<img src="Screenshots/Main.png?raw=true" alt="Battman Main Demo" width="25%" height="25%" />
<img src="Screenshots/Gas Gauge.png?raw=true" alt="Battman Gas Gauge Demo" width="25%" height="25%" />
<img src="Screenshots/Gas Gauge-1.png?raw=true" alt="Battman Gas Gauge Demo 2" width="25%" height="25%" />
<img src="Screenshots/Adapter.png?raw=true" alt="Battman Adapter Demo" width="25%" height="25%" />
<img src="Screenshots/Inductive.png?raw=true" alt="Battman Inductive Demo" width="25%" height="25%" />
<img src="Screenshots/Inductive-1.png?raw=true" alt="Battman Inductive Demo 2" width="25%" height="25%" />
<img src="Screenshots/Serial.png?raw=true" alt="Battman Serial Demo" width="25%" height="25%" />
<img src="Screenshots/Temperature.png?raw=true" alt="Battman Temperature Demo" width="25%" height="25%" />
<img src="Screenshots/ChargingMgmt.png?raw=true" alt="Battman Charging Management Demo" width="25%" height="25%" />
<img src="Screenshots/ChargingLimit.png?raw=true" alt="Battman Charging Limit Demo" width="25%" height="25%" />
<img src="Screenshots/Thermal.png?raw=true" alt="Battman Thermal Demo" width="25%" height="25%" />
</div>

$${\color{grey}True \space elegance \space in \space software \space lies \space in \space the \space art \space of \space its \space code \space rather \space than \space in \space superficial \space design.}$$

<br />

### Advantages
- [x] Purely constructed with Objective-C & C
- [x] UI purely written with brilliant Objective-C codes
- [x] NO StoryBoards, NO additional binaries, NO Xcode Assets
- [x] NO Swift and SwiftUI involved
- [x] NO CocoaPods, NO Swift Packages, NO external code requirements, NO 3rd-party frameworks
- [x] Compile WITH/WITHOUT Xcode
- [x] Builds on Linux (Yes, "you need Mac to make iOS apps" is Apple propaganda)
- [x] Obtain & Operate directly from/with your hardware with the deepest raw data
- [x] Supporting iPhone & iPad & iPod & Xcode Simulator & Apple Silicon Macs (If someone donate devices I can even code for Apple Watches and Apple TVs)
- [x] Highly integrated with your battery Gas Gauge IC that manufactured by Texas Instruments
- [x] Show as much as power informations than IOPS & PowerManagement provided
- [x] Identifying your power adapters, wireless chargers, or even your MagSafe accessories

### Only Battman Can Do

What other battery utils made for iOS hasn’t done
(As of 9th Sun Mar 2025 UTC+0)
- [x] Complete NotChargingReason decoding (see [not_charging_reason.h](Battman/battery_utils/not_charging_reason.h))
- [x] Texas Intruments Impedance Track™ information retrieving
- [x] Real-time charging current/voltage reading
- [x] Running perfectly when in Xcode Simulator (Other people uses IOPS in their app so not working in Sims)
- [x] Smart Charging (Optimized Battery Charging) communication
- [x] Low Power Mode behavior control
- [x] Detailed information for attached MagSafe Accessories
- [x] Detailed information for attached Lightning Cables & Accessories
- [x] Read all hardware temperature sensors

### Requirements

- Jailbroken or install with TrollStore
- iOS 12+ / macOS 11+ (backports welcomed)
- arm64 (A7+ theoretically / M1+)
- Gettext libintl (Optional, for localizations)
- GTK+ 3 (Optional, for running under GTK+ based WM)

### Download

Check latest [Release](https://github.com/Torrekie/Battman/releases/latest) for a prebuilt package.

Or, if you wish to build it by yourself:

```bash
# On macOS, install Xcode and directly build in it
# On Linux or BSD, make sure a LLVM cross toolchain and iPhoneOS.sdk is prepared, modify Battman/Makefile if needed
# On iOS, when you using Torrekie/Comdartiwerk as bootstrap
apt install git odcctools bash clang make sed grep ld64 ldid libintl-dev iphoneos.sdk
git clone https://github.com/Torrekie/Battman
cd Battman
# If Targeting iOS 12 or ealier, download SF-Pro-Display-Regular.otf somewhere, and put it under Battman/
wget <https://LINK/OF/SF-Pro-Display-Regular.otf> -O Battman/SF-Pro-Display-Regular.otf
make -C Battman all
# Produced Battman.ipa will under $(CWD)/Battman/build/Battman.ipa
```

### Known Issues

- Battman is not actually integrated with hardware when running under devices with A7 to A10, since there has no AppleSMC, instead they uses AppleHPM which we cannot test.

### Tested Devices
- iPhone 12 Series (D52)
- iPad Pro 2021 3th Gen (J51)
- iPhone XR
- iPad Air 2

Please file [issues](../../issues/new) if Battman not working correctly on your device

### TODO
- [ ] AppKit/Cocoa UI for macOS
- [ ] GTK+/X11 UI for iOS/macOS
- [ ] Auto identify Gas Gauge IC
- [ ] Optional data collection (For decoding currently unknown params)
- [x] Advanced features (AppleSMC/ApplePMGR interface)
- [x] Thermal control
- [ ] Run as CLI
- [ ] Run as daemon
- [x] Charge limit
- [x] Wireless/MagSafe integration
- [ ] App rate limit
- [ ] Jetsam control
- [ ] Fan control
- [ ] Bluetooth accessories (AirPods, etc.)

### License

As of 27th Sat Sep 2025 UTC+0, Battman uses [non-free license](LICENSE/LICENSE.md) instead of MIT, you won't blame me if I want to make living with this right?

## Disclaimer

DO NOT USE FOR PRODUCTION, NO WARRANTY GURARANTEED, USE AT YOUR OWN RISK.
