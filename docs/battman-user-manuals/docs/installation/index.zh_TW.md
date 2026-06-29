title: 安裝
---

# 安裝

本頁介紹如何安裝和配置 Battman。

## 環境要求

- A11 及以上設備。
- iOS 12 及以上系統。
- 設備已越獄，或已安裝 TrollStore。

Battman 目前僅提供 TrollStore 版本和越獄版。其他安裝方式不受支持，且無法成功安裝。這是因為 Battman 嚴重依賴 iOS/macOS 私有 API。

> 如果你仍想用證書/描述文件來安裝，請確保你的開發配置描述文件允許使用 [Battman 的 entitlements](https://github.com/Torrekie/Battman/blob/master/Battman.entitlements)。（這真的可行嗎？）

## 安裝（TrollStore，iOS 14+）

如果你的設備尚未安裝 TrollStore，請參閱 [ios.cfw.guide](https://ios.cfw.guide/installing-trollstore/) 的教程。

1. 下載最新的 [Battman.tipa](https://github.com/Torrekie/Battman/releases/download/latest/Battman.tipa)，或從 [Releases](https://github.com/Torrekie/Battman/releases/latest) 頁面選擇所需版本。
2. 長按（或點擊「共享」）下載的 `Battman.tipa`，選擇「分享」，然後點擊「TrollStore」。
3. 在 TrollStore 彈出的窗口中點擊「Install」完成安裝。

## 越獄安裝（rooted，iOS 12+）

1. 打開包管理器（Cydia、Sileo、Zebra 等），從 bootstrap 源（Elucubratus 或 Procursus）安裝 `libintl8`。
2. 從 [Releases](https://github.com/Torrekie/Battman/releases/latest) 頁面下載最新的 `com.torrekie.battman_<version>_iphoneos-arm.deb`，請務必選擇 `iphoneos-arm` 版本。當前最新版本為 [1.0.4（點擊下載）](https://github.com/Torrekie/Battman/releases/v1.0.4/com.torrekie.battman_1.0.4_iphoneos-arm.deb)。
3. 長按下載的 deb，點擊「共享」，選擇包管理器（或 Filza）進行安裝（或使用你偏好的 deb 安裝方式）。

## 越獄安裝（rootless，iOS 15+）

1. 打開包管理器（Cydia、Sileo、Zebra 等），從 bootstrap 源（Elucubratus 或 Procursus）安裝 `libintl8`。
2. 從 [Releases](https://github.com/Torrekie/Battman/releases/latest) 頁面下載最新的 `com.torrekie.battman_<version>_iphoneos-arm.deb`，請務必選擇 `iphoneos-arm64` 版本。當前最新版本為 [1.0.4（點擊下載）](https://github.com/Torrekie/Battman/releases/v1.0.4/com.torrekie.battman_1.0.4_iphoneos-arm64.deb)。
3. 長按下載的 deb，點擊「共享」，選擇包管理器（或 Filza）進行安裝（或使用你偏好的 deb 安裝方式）。

## 後續步驟

- 如果安裝失敗，請查看「故障排除」章節。
- 安裝完成後，可以從首頁瞭解更多功能。
