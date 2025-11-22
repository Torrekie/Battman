# Battman 电池管理器
被抛弃者的现代电池管理器，为它们的老设备打造。

## 屏幕截图
<div style="width:20%; margin: auto;" align="middle">
<img src="../Screenshots/Main-zh_CN.png?raw=true" alt="Battman Main Demo" width="25%" height="25%" />
<img src="../Screenshots/Gas Gauge-zh_CN.png?raw=true" alt="Battman Gas Gauge Demo" width="25%" height="25%" />
<img src="../Screenshots/Gas Gauge-1-zh_CN.png?raw=true" alt="Battman Gas Gauge Demo 2" width="25%" height="25%" />
<img src="../Screenshots/Adapter-zh_CN.png?raw=true" alt="Battman Adapter Demo" width="25%" height="25%" />
<img src="../Screenshots/Inductive-zh_CN.png?raw=true" alt="Battman Inductive Demo" width="25%" height="25%" />
<img src="../Screenshots/Inductive-1-zh_CN.png?raw=true" alt="Battman Inductive Demo 2" width="25%" height="25%" />
<img src="../Screenshots/Serial-zh_CN.png?raw=true" alt="Battman Serial Demo" width="25%" height="25%" />
<img src="../Screenshots/Temperature-zh_CN.png?raw=true" alt="Battman Temperature Demo" width="25%" height="25%" />
<img src="../Screenshots/ChargingMgmt-zh_CN.png?raw=true" alt="Battman Charging Management Demo" width="25%" height="25%" />
<img src="../Screenshots/ChargingLimit-zh_CN.png?raw=true" alt="Battman Charging Limit Demo" width="25%" height="25%" />
<img src="../Screenshots/Thermal-zh_CN.png?raw=true" alt="Battman Thermal Demo" width="25%" height="25%" />
</div>

$${\color{grey}真正优雅的软件讲究代码的艺术，而非外表的点缀。}$$

<br />

### 优势
- [x] 纯粹地由Objective-C与C打造
- [x] 明朗的UI，编写自明朗的Objective-C
- [x] 不含**StoryBoards**，不含**额外的二进制文件**，不含**Xcode 资源库**
- [x] 不含**Swift和SwiftUI**
- [x] 不含**CocoaPods**，不含**Swift 扩展包**，不含**外部代码包依赖**，不含**第三方框架**
- [x] Xcode 编译？不用 Xcode 编译也可以
- [x] 编译在 Linux（没错，“你需要 Mac 来做 iOS App”是 Apple 的鼓动宣传）
- [x] 直接获取并操作硬件最深处的原始数据
- [x] 支持 iPhone、iPad、iPod、Xcode 模拟器和 Apple 芯片的 Mac 设备（如果有人捐赠设备的话，我甚至可以支持Apple Watch和Apple TV）
- [x] 高度适配设备电池中的德州仪器电量监测计芯片
- [x] 比 IOPS 和 PowerManagement 提供的信息还要**多得多**
- [x] 检测你的**电源适配器**、**无线充电器**、甚至你的 **MagSafe 配件**

### 只有 Battman 能做到

目前为止，其他面向iOS的电池管理工具没能做到的事情
(截止至 9th Sun Mar 2025 UTC+0)
- [x] 完整的 **未充电原因（NotChargingReason）** 解码，详见 [not_charging_reason.h](../Battman/battery_utils/not_charging_reason.h)
- [x] 德州仪器 Impedance Track™ 信息的获取
- [x] 实时充电电压/电流的读取
- [x] 完美运行在 Xcode Simulator （其他人在他们的软件里用 IOPS，所以不行）
- [x] 智能充电（优化电池充电）交互
- [x] 低电量模式行为控制
- [x] 详细的 MagSafe 配件信息
- [x] 详细的 Lightning 线缆与配件信息
- [x] 读取全部硬件温度传感器

### 前置条件

- 越狱设备，或者通过TrollStore安装
- iOS 12+ / macOS 11+（欢迎向前移植）
- arm64（A7+ 理论上的 / M1+）
- Gettext libintl（可选，用于本地化）
- GTK+ 3（可选，用于运行在基于GTK+的桌面环境）

### 下载

前往最新 [Release](https://github.com/Torrekie/Battman/releases/latest) 以获取预构建包。

或者，如果你希望自己构建它：

```bash
# 在 macOS，安装 Xcode 并直接用其编译
# 在 Linux 或者 BSD，确保一个 LLVM 跨平台编译工具链和 iPhoneOS.sdk 已经准备好，并且按需修改 Battman/Makefile
# 在 iOS，当你使用 Torrekie/Comdartiwerk 作为基础套件时
apt install git odcctools bash clang make sed grep ld64 ldid libintl-dev iphoneos.sdk
git clone https://github.com/Torrekie/Battman
# 如果目标 iOS 12 或更早，下载 SF-Pro-Display-Regular.otf，然后放在 Battman/
wget <https://LINK/OF/SF-Pro-Display-Regular.otf> -O Battman/SF-Pro-Display-Regular.otf
cd Battman
make -C Battman all
# 生成的 Battman.ipa 将位于 $(CWD)/Battman/build/Battman.ipa
```

### 已知问题
- Battman 在 **A7 至 A10** 的设备运行时并未真正与硬件交互，因为没有AppleSMC，作为替代这些设备使用我们无法测试的AppleHPM。

### 已测试设备
- iPhone 12 系列 (D52)
- iPad Pro 2021 第三代 (J51)
- iPhone XR
- iPad Air 2

如果 Battman 未能在你的设备正常工作，请提交[疑述](../../../issues/new)。

### 即将实现
- [ ] AppKit/Cocoa UI for macOS
- [ ] GTK+/X11 UI for iOS/macOS
- [ ] 自动识别电量计芯片
- [ ] 可选的数据采集（用于解码当前未知的参数）
- [x] 高级功能（Apple 系统管理控制器/Apple 电源管理 操作界面）
- [x] 温度控制
- [ ] 作为命令行程序运行
- [ ] 作为守护进程运行
- [x] 充电限制
- [x] 无线/MagSafe 适配
- [ ] App 能耗限制
- [ ] Jetsam 控制
- [ ] 风扇控制
- [ ] 蓝牙配件（AirPods等）

### 许可证

自 27th Sat Sep 2025 UTC+0 起，Battman 由 MIT 转变为[非自由协议](../LICENSE/LICENSE.md)，你不会因为我想以此维持生计而怪罪于我，对吧？

## 免责声明

**请勿用于生产环境，无任何保障，风险自负。**
