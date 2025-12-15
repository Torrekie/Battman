title: 安装
---

# 安装

本页介绍如何安装和配置 Battman。

## 环境要求

- A11 及以上设备。
- iOS 12 及以上系统。
- 设备已越狱，或已安装 TrollStore。

Battman 目前仅提供 TrollStore 版本和越狱版。其他安装方式不受支持，且无法成功安装。这是因为 Battman 严重依赖 iOS/macOS 私有 API。

> 如果你仍想用证书/描述文件来安装，请确保你的开发配置描述文件允许使用 [Battman 的 entitlements](https://github.com/Torrekie/Battman/blob/master/Battman.entitlements)。（这真的可行吗？）

## 安装（TrollStore，iOS 14+）

如果你的设备尚未安装 TrollStore，请参阅 [ios.cfw.guide](https://ios.cfw.guide/installing-trollstore/) 的教程。

1. 下载最新的 [Battman.tipa](https://github.com/Torrekie/Battman/releases/download/latest/Battman.tipa)，或从 [Releases](https://github.com/Torrekie/Battman/releases/latest) 页面选择所需版本。
2. 长按（或点击“共享”）下载的 `Battman.tipa`，选择“分享”，然后点击“TrollStore”。
3. 在 TrollStore 弹出的窗口中点击“Install”完成安装。

## 越狱安装（rooted，iOS 12+）

1. 打开包管理器（Cydia、Sileo、Zebra 等），从 bootstrap 源（Elucubratus 或 Procursus）安装 `libintl8`。
2. 从 [Releases](https://github.com/Torrekie/Battman/releases/latest) 页面下载最新的 `com.torrekie.battman_<version>_iphoneos-arm.deb`，请务必选择 `iphoneos-arm` 版本。当前最新版本为 [1.0.3.2（点击下载）](https://github.com/Torrekie/Battman/releases/v1.0.3.2/com.torrekie.battman_1.0.3.2_iphoneos-arm.deb)。
3. 长按下载的 deb，点击“共享”，选择包管理器（或 Filza）进行安装（或使用你偏好的 deb 安装方式）。

## 越狱安装（rootless，iOS 15+）

1. 打开包管理器（Cydia、Sileo、Zebra 等），从 bootstrap 源（Elucubratus 或 Procursus）安装 `libintl8`。
2. 从 [Releases](https://github.com/Torrekie/Battman/releases/latest) 页面下载最新的 `com.torrekie.battman_<version>_iphoneos-arm.deb`，请务必选择 `iphoneos-arm64` 版本。当前最新版本为 [1.0.3.2（点击下载）](https://github.com/Torrekie/Battman/releases/v1.0.3.2/com.torrekie.battman_1.0.3.2_iphoneos-arm64.deb)。
3. 长按下载的 deb，点击“共享”，选择包管理器（或 Filza）进行安装（或使用你偏好的 deb 安装方式）。

## 后续步骤

- 如果安装失败，请查看「故障排除」章节。
- 安装完成后，可以从首页了解更多功能。
