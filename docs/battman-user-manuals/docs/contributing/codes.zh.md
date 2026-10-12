---
title: 代码贡献
---

# 参与代码贡献

当前构建入口见[项目 README](https://github.com/Torrekie/Battman)和仓库约定。Battman 1.1.0 使用 Objective-C、C 和编程式界面，同时提供 Xcode 工程与基于 Make 的交叉构建路径。

## 找到相关组件

| 目录 | 用途 |
| --- | --- |
| `Battman/` | iOS 应用与设备接口 |
| `Battman/Features/Analytics/` | 宿主数据服务、卡片布局与内置卡片 |
| `Battman/PluginHost/` | 原生插件发现、验证、信任与生命周期 |
| `PluginSDK/` | 公开 SDK v1 头文件、模式、模板、工具与示例 |
| `OfficialPlugins/` | 官方插件源码与发布输入 |
| `Scripts/Build/`、`Scripts/Release/`、`Packaging/` | 构建收尾、软件包生成与发布约定 |
| `Tests/` | 针对宿主、SDK、分析与发布的专项检查 |
| `docs/battman-user-manuals/` | 本三语手册 |

## 实现与验证

保持改动集中，并保留声明的 iOS 12 部署基线。插件使用公开 SDK 约定，不依赖宿主私有控制器，也不在绘图回调中读取硬件数据。独立开发流程与签名要求见[插件开发指南](https://github.com/Torrekie/Battman/blob/master/docs/plugin-authoring.md)。

使用既有依赖和构建路径。Xcode 的 gettext 依赖会下载固定归档、校验摘要并构建，首次构建需要访问 GNU。不要为不相关改动添加自动依赖升级或强制更换工具链。保持资源可移植性及既有编程式界面约定。

运行与改动相关的最小检查，并明确说明验证范围。模拟器或编译成功不能证明所有设备的硬件行为。不要将凭证、私有签名密钥、设备标识或私有发布记录放入提交和公开诊断。

用户可见行为发生变化时，同步英语、简体中文和繁体中文手册。在仓库根目录使用隔离环境构建手册：

```sh
Scripts/Docs/render-user-manual.sh /tmp/battman-manual-preview
```

输出路径必须尚不存在。该工具使用现有、固定版本和哈希的 `Requirements/docs.txt`，执行严格构建而不部署网站。通过 HTTP 预览结果以检查导航和搜索。
