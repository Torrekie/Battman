---
title: 类型代码
---

# 类型代码

类型代码用于标识连接到设备的电源适配器或充电源类型。它们有助于识别所连接适配器的充电接口和功能。

## 概览

类型代码由系统用于：
- 确定充电能力和功率限制
- 识别连接类型（USB、交流电源、无线等）
- 应用适当的充电协议和安全限制
- 在系统诊断中显示适配器信息

## 代码值

### 未连接 / 不支持

| 代码 | 十六进制值 | 说明 |
|------|-----------|------|
| `kIOPSFamilyCodeDisconnected` | `0x00000000` | 未连接或未检测到适配器 |
| `kIOPSFamilyCodeUnsupported` | `0xE00002C7` | 检测到适配器但不支持或无法识别 |

### FireWire

| 代码 | 十六进制值 | 说明 |
|------|-----------|------|
| `kIOPSFamilyCodeFirewire` | `0xE0008000` | FireWire (IEEE 1394) 电源适配器（旧款） |

### USB 电源

USB 类型代码分组在 `0xE0004000` 基础范围内：

| 代码 | 十六进制值 | 说明 |
|------|-----------|------|
| `kIOPSFamilyCodeUSBHost` | `0xE0004000` | USB 接口（标准 USB 端口） |
| `kIOPSFamilyCodeUSBHostSuspended` | `0xE0004001` | USB 标准下行端口（SDP）- 低功率 USB 端口 |
| `kIOPSFamilyCodeUSBDevice` | `0xE0004002` | USB 设备模式（设备作为 USB 外设） |
| `kIOPSFamilyCodeUSBAdapter` | `0xE0004003` | 通用 USB 适配器 |
| `kIOPSFamilyCodeUSBChargingPortDedicated` | `0xE0004004` | USB 专用充电端口（DCP）- 专用 USB 充电器 |
| `kIOPSFamilyCodeUSBChargingPortDownstream` | `0xE0004005` | USB 充电下行端口（CDP）- 可在提供数据的同时充电的 USB 端口 |
| `kIOPSFamilyCodeUSBChargingPort` | `0xE0004006` | USB 充电端口（CP）- 通用 USB 充电端口 |
| `kIOPSFamilyCodeUSBUnknown` | `0xE0004007` | 未知 USB 电源类型 |
| `kIOPSFamilyCodeUSBCBrick` | `0xE0004008` | USB-C 电源砖（非 PD USB-C 充电器） |
| `kIOPSFamilyCodeUSBCTypeC` | `0xE0004009` | USB-C Type-C 端口（标准 USB-C 连接） |
| `kIOPSFamilyCodeUSBCPD` | `0xE000400A` | USB-C PD（Power Delivery）- 支持 Power Delivery 协议的 USB-C 充电器 |

### 交流电源

| 代码 | 十六进制值 | 说明 |
|------|-----------|------|
| `kIOPSFamilyCodeAC` | `0xE0024000` | 交流电源适配器（传统 MacBook 电源适配器） |

### 外部电源

外部电源代码用于专有或专用充电接口。它们从 `0xE0024001` 开始按顺序分组：

| 代码 | 十六进制值 | 说明 |
|------|-----------|------|
| `kIOPSFamilyCodeExternal` | `0xE0024001` | 外部电源 1 - 通用外部电源 |
| `kIOPSFamilyCodeExternal2` | `0xE0024002` | 外部电源 2 - 次要外部电源 |
| `kIOPSFamilyCodeExternal3` | `0xE0024003` | 外部电源 3 - Baseline Arca 充电接口 |
| `kIOPSFamilyCodeExternal4` | `0xE0024004` | 外部电源 4 - 其他外部电源 |
| `kIOPSFamilyCodeExternal5` | `0xE0024005` | 外部电源 5 - 其他外部电源 |
| `kIOPSFamilyCodeExternal6` | `0xE0024006` | 外部电源 6 - MagSafe 充电器（无线充电） |
| `kIOPSFamilyCodeExternal7` | `0xE0024007` | 外部电源 7 - MagSafe 配件（例如 MagSafe 外接电池） |

## 了解 USB 充电端口

### USB SDP（标准下行端口）
- 提供最高 500mA @ 5V（2.5W）
- 用于标准 USB 数据端口
- 最慢的充电选项

### USB DCP（专用充电端口）
- 提供最高 1.5A @ 5V（7.5W）
- 专为充电设计（无数据）
- 常见于壁式充电器和车载充电器

### USB CDP（充电下行端口）
- 提供最高 1.5A @ 5V（7.5W）
- 同时支持充电和数据传输
- 常见于计算机和部分集线器

### USB-C Power Delivery (PD)
- 可提供可变电压和电流（根据适配器最高 100W+）
- 动态协商功率级别
- 在兼容设备上支持快速充电
- 功能最强大的 USB 充电标准

## 设备特定行为

### MacBook
- 交流电源适配器显示为 `kIOPSFamilyCodeAC`
- USB-C 适配器显示为 `kIOPSFamilyCodeUSBCPD` 或 `kIOPSFamilyCodeUSBCTypeC`

### iPhone / iPad
- MagSafe 充电器显示为 `kIOPSFamilyCodeExternal6`
- MagSafe 配件（如外接电池）显示为 `kIOPSFamilyCodeExternal7`

## 故障排除

### "不支持" 类型代码
如果您看到 `kIOPSFamilyCodeUnsupported`：
- 适配器可能未通过 Apple 认证或不兼容 MFi
- 适配器可能已损坏或出现故障
- 设备可能无法识别第三方适配器
- 尝试使用 Apple 认证的适配器

### 已连接适配器但显示 "未连接"
如果您已连接适配器但仍看到 `kIOPSFamilyCodeDisconnected`：
- 检查物理连接（线缆、端口）
- 尝试使用不同的线缆或端口
- 适配器可能未提供电源
- 检查充电端口是否有异物

### USB-C 未充电
如果 USB-C 适配器显示类型代码但未充电：
- 确认适配器支持 Power Delivery (PD)
- 检查线缆是否支持充电（部分 USB-C 线缆仅支持数据传输）
- 确保适配器为设备提供足够的功率
- 查看[未充电原因](../not-charging-reason)以获取具体错误代码

### 无线充电问题
对于 MagSafe 或感应式充电：
- 确保设备支持无线充电
- 检查充电器是否正确对齐
- 移除可能干扰的保护壳或配件
- 确认充电器已通过 Apple 认证（对于 MagSafe）
