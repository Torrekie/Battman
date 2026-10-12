---
title: 安装
---

# 在 iOS 上安装 Battman

## 要求与覆盖范围

- Apple A11 或更新的设备，iOS 12 或更新版本。
- 受支持的越狱环境，或已经正常工作的 TrollStore。

A11/iOS 12 是产品边界，依据 arm64/iOS 12 编译及当前模拟器和设备检查；这并不表示已逐一独立验证所有 A11 或更新设备与每个 iOS 版本的组合。设备未暴露所需数据时，相关读数会显示**不可用**。安装渠道还有自己的系统限制，下表不表示其间所有 iOS 版本都支持越狱或 TrollStore。

不支持普通证书或描述文件侧载。Battman 需要普通描述文件不能提供的特权权限和私有系统接口；仅重新签名归档不会授予这些能力。

## 选择匹配的软件包

请下载某个明确 [GitHub 发布版本](https://github.com/Torrekie/Battman/releases)所附的文件，并核对该版本的说明、版本号和校验和。源码版本为 1.1.0 并不表示生产发布已经上线。校验和签名中的公钥指纹需要与独立审核的指纹比较，才能确认签名者身份。

| 环境 | 软件包 | 文档规定的最低版本 |
| --- | --- | --- |
| 有根越狱 | `com.torrekie.battman_<version>_iphoneos-arm.deb` | iOS 12+ |
| 无根越狱 | `com.torrekie.battman_<version>_iphoneos-arm64.deb` | iOS 15+ |
| TrollStore | `Battman.tipa` | iOS 14+，且你的 TrollStore 支持该具体版本 |

Debian 架构名称对应越狱目录布局，两种宿主包都包含 arm64 代码；不能仅凭处理器的“64 位”选择。无根环境应选择 `iphoneos-arm64.deb`，不要选择 `iphoneos-arm`。

## 越狱安装

1. 下载与有根或无根环境匹配的软件包。
2. 用软件包管理器打开，并检查软件包信息。
3. 让软件包管理器通过正常的 bootstrap 软件源解决依赖，包括软件包要求时的 `libintl8` 或 `libintl`。
4. 完成安装并打开 Battman。

使用 Havoc 时，请通过该渠道的软件包管理器说明安装 Havoc 版。Havoc 使用单独构建的宿主，只分发 Debian 软件包，没有 Havoc TIPA。商店分发不会授予原生插件信任。避免同时安装来自不同渠道、互相冲突的宿主软件包。

## TrollStore 安装

1. 确认 TrollStore 已在你的具体 iOS 版本上正常工作。
2. 下载所选版本的 `Battman.tipa`，分享给 TrollStore，并查看安装提示。
3. 完成安装并打开 Battman。

自行准备替换 TIPA 时，应检查发布报告的 `requiresOuterResign` 状态。打包工具不执行最终外层签名或安装。添加插件会改变应用包，需要正确签名的替换应用；把原生代码复制到应用数据目录不是受支持的 TrollStore 启用方法。

接下来可阅读[分析](../features/analytics.md)或[原生插件](../features/plugins.md)。
