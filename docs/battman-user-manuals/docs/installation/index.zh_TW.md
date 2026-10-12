---
title: 安裝
---

# 在 iOS 上安裝 Battman

## 要求與涵蓋範圍

- Apple A11 或更新的裝置，iOS 12 或更新版本。
- 受支援的越獄環境，或已經正常運作的 TrollStore。

A11/iOS 12 是產品邊界，依據 arm64/iOS 12 編譯及目前模擬器和裝置檢查；這並不表示已逐一獨立驗證所有 A11 或更新裝置與每個 iOS 版本的組合。裝置未提供所需資料時，相關讀數會顯示**無法使用**。安裝管道還有自己的系統限制，下表不表示其間所有 iOS 版本都支援越獄或 TrollStore。

不支援普通憑證或描述檔側載。Battman 需要普通描述檔不能提供的特權權限和私有系統介面；僅重新簽署封存檔不會授予這些能力。

## 選擇相符的套件

請下載某個明確 [GitHub 發行版本](https://github.com/Torrekie/Battman/releases)所附的檔案，並核對該版本的說明、版本號碼和校驗和。原始碼版本為 1.1.0 並不表示正式發行已經上線。校驗和簽章中的公開金鑰指紋需要與獨立審核的指紋比較，才能確認簽署者身分。

| 環境 | 套件 | 文件規定的最低版本 |
| --- | --- | --- |
| 有根越獄 | `com.torrekie.battman_<version>_iphoneos-arm.deb` | iOS 12+ |
| 無根越獄 | `com.torrekie.battman_<version>_iphoneos-arm64.deb` | iOS 15+ |
| TrollStore | `Battman.tipa` | iOS 14+，且你的 TrollStore 支援該確切版本 |

Debian 架構名稱對應越獄目錄配置，兩種宿主套件都包含 arm64 程式碼；不能僅憑處理器的「64 位元」選擇。無根環境應選擇 `iphoneos-arm64.deb`，不要選擇 `iphoneos-arm`。

## 越獄安裝

1. 下載與有根或無根環境相符的套件。
2. 用套件管理器開啟，並檢查套件資訊。
3. 讓套件管理器透過正常的 bootstrap 軟體來源解決相依性，包括套件要求時的 `libintl8` 或 `libintl`。
4. 完成安裝並開啟 Battman。

使用 Havoc 時，請透過該管道的套件管理器說明安裝 Havoc 版。Havoc 使用單獨建置的宿主，只分發 Debian 套件，沒有 Havoc TIPA。商店分發不會授予原生外掛程式信任。避免同時安裝來自不同管道、互相衝突的宿主套件。

## TrollStore 安裝

1. 確認 TrollStore 已在你的確切 iOS 版本上正常運作。
2. 下載所選版本的 `Battman.tipa`，分享給 TrollStore，並查看安裝提示。
3. 完成安裝並開啟 Battman。

自行準備替換 TIPA 時，應檢查發行報告的 `requiresOuterResign` 狀態。封裝工具不執行最終外層簽署或安裝。新增外掛程式會改變應用程式套件，需要正確簽署的替換應用程式；將原生程式碼複製到應用程式資料目錄不是受支援的 TrollStore 啟用方法。

接下來可閱讀[分析](../features/analytics.md)或[原生外掛程式](../features/plugins.md)。
