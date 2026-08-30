---
title: 類型代碼
---

# 類型代碼

類型代碼用於標識連接到設備的電源適配器或充電源類型。它們有助於識別所連接適配器的充電接口和功能。

## 概覽

類型代碼由系統用於：
- 確定充電能力和功率限制
- 識別連接類型（USB、交流電源、無線等）
- 應用適當的充電協議和安全限制
- 在系統診斷中顯示適配器信息

## 代碼值

### 未連接 / 不支持

| 代碼 | 十六進制值 | 說明 |
|------|-----------|------|
| `kIOPSFamilyCodeDisconnected` | `0x00000000` | 未連接或未檢測到適配器 |
| `kIOPSFamilyCodeUnsupported` | `0xE00002C7` | 檢測到適配器但不支持或無法識別 |

### FireWire

| 代碼 | 十六進制值 | 說明 |
|------|-----------|------|
| `kIOPSFamilyCodeFirewire` | `0xE0008000` | FireWire (IEEE 1394) 電源適配器（舊款） |

### USB 電源

USB 類型代碼分組在 `0xE0004000` 基礎範圍內：

| 代碼 | 十六進制值 | 說明 |
|------|-----------|------|
| `kIOPSFamilyCodeUSBHost` | `0xE0004000` | USB 接口（標準 USB 端口） |
| `kIOPSFamilyCodeUSBHostSuspended` | `0xE0004001` | USB 標準下行端口（SDP）- 低功率 USB 端口 |
| `kIOPSFamilyCodeUSBDevice` | `0xE0004002` | USB 設備模式（設備作為 USB 外設） |
| `kIOPSFamilyCodeUSBAdapter` | `0xE0004003` | 通用 USB 適配器 |
| `kIOPSFamilyCodeUSBChargingPortDedicated` | `0xE0004004` | USB 專用充電端口（DCP）- 專用 USB 充電器 |
| `kIOPSFamilyCodeUSBChargingPortDownstream` | `0xE0004005` | USB 充電下行端口（CDP）- 可在提供數據的同時充電的 USB 端口 |
| `kIOPSFamilyCodeUSBChargingPort` | `0xE0004006` | USB 充電端口（CP）- 通用 USB 充電端口 |
| `kIOPSFamilyCodeUSBUnknown` | `0xE0004007` | 未知 USB 電源類型 |
| `kIOPSFamilyCodeUSBCBrick` | `0xE0004008` | USB-C 電源磚（非 PD USB-C 充電器） |
| `kIOPSFamilyCodeUSBCTypeC` | `0xE0004009` | USB-C Type-C 端口（標準 USB-C 連接） |
| `kIOPSFamilyCodeUSBCPD` | `0xE000400A` | USB-C PD（Power Delivery）- 支持 Power Delivery 協議的 USB-C 充電器 |

### 交流電源

| 代碼 | 十六進制值 | 說明 |
|------|-----------|------|
| `kIOPSFamilyCodeAC` | `0xE0024000` | 交流電源適配器（傳統 MacBook 電源適配器） |

### 外部電源

外部電源代碼用於專有或專用充電接口。它們從 `0xE0024001` 開始按順序分組：

| 代碼 | 十六進制值 | 說明 |
|------|-----------|------|
| `kIOPSFamilyCodeExternal` | `0xE0024001` | 外部電源 1 - 通用外部電源 |
| `kIOPSFamilyCodeExternal2` | `0xE0024002` | 外部電源 2 - 次要外部電源 |
| `kIOPSFamilyCodeExternal3` | `0xE0024003` | 外部電源 3 - Baseline Arca 充電接口 |
| `kIOPSFamilyCodeExternal4` | `0xE0024004` | 外部電源 4 - 其他外部電源 |
| `kIOPSFamilyCodeExternal5` | `0xE0024005` | 外部電源 5 - 其他外部電源 |
| `kIOPSFamilyCodeExternal6` | `0xE0024006` | 外部電源 6 - MagSafe 充電器（無線充電） |
| `kIOPSFamilyCodeExternal7` | `0xE0024007` | 外部電源 7 - MagSafe 配件（例如 MagSafe 外接電池） |

## 瞭解 USB 充電端口

### USB SDP（標準下行端口）
- 提供最高 500mA @ 5V（2.5W）
- 用於標準 USB 數據端口
- 最慢的充電選項

### USB DCP（專用充電端口）
- 提供最高 1.5A @ 5V（7.5W）
- 專為充電設計（無數據）
- 常見於壁式充電器和車載充電器

### USB CDP（充電下行端口）
- 提供最高 1.5A @ 5V（7.5W）
- 同時支持充電和數據傳輸
- 常見於計算機和部分集線器

### USB-C Power Delivery (PD)
- 可提供可變電壓和電流（根據適配器最高 100W+）
- 動態協商功率級別
- 在兼容設備上支持快速充電
- 功能最強大的 USB 充電標準

## 設備特定行為

### MacBook
- 交流電源適配器顯示為 `kIOPSFamilyCodeAC`
- USB-C 適配器顯示為 `kIOPSFamilyCodeUSBCPD` 或 `kIOPSFamilyCodeUSBCTypeC`

### iPhone / iPad
- MagSafe 充電器顯示為 `kIOPSFamilyCodeExternal6`
- MagSafe 配件（如外接電池）顯示為 `kIOPSFamilyCodeExternal7`

## 故障排除

### "不支持" 類型代碼
如果您看到 `kIOPSFamilyCodeUnsupported`：
- 適配器可能未通過 Apple 認證或不兼容 MFi
- 適配器可能已損壞或出現故障
- 設備可能無法識別第三方適配器
- 嘗試使用 Apple 認證的適配器

### 已連接適配器但顯示 "未連接"
如果您已連接適配器但仍看到 `kIOPSFamilyCodeDisconnected`：
- 檢查物理連接（線纜、端口）
- 嘗試使用不同的線纜或端口
- 適配器可能未提供電源
- 檢查充電端口是否有異物

### USB-C 未充電
如果 USB-C 適配器顯示類型代碼但未充電：
- 確認適配器支持 Power Delivery (PD)
- 檢查線纜是否支持充電（部分 USB-C 線纜僅支持數據傳輸）
- 確保適配器為設備提供足夠的功率
- 查看[未充電原因](not-charging-reason.md)以獲取具體錯誤代碼

### 無線充電問題
對於 MagSafe 或感應式充電：
- 確保設備支持無線充電
- 檢查充電器是否正確對齊
- 移除可能幹擾的保護殼或配件
- 確認充電器已通過 Apple 認證（對於 MagSafe）
