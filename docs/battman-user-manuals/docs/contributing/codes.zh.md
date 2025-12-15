---
title: 代码贡献
---

# 参与代码贡献

欢迎为 Battman 提交代码改进。

## 开始之前

- 建议先阅读根目录下的 `README.md`，了解项目结构与构建依赖。
- 准备好合适的 iOS 工具链与开发 / 测试环境。

## 项目结构

Battman 使用 **Objective-C 和 C** 编写（不使用 Swift）。主要代码库组织如下：

### 目录布局

- **`Battman/`** - 主应用程序代码
  - **`battery_utils/`** - 电池信息与硬件交互工具
  - **`hw/`** - 硬件特定接口（例如 IOMFB）
  - **`cobjc/`** - 用于 C 兼容性的自定义 Objective-C 运行时包装器
  - **`ObjCExt/`** - Objective-C 类别扩展
  - **`CGIconSet/`** - 自定义图标生成代码
  - **`brightness/`** - 亮度控制功能
  - **`scprefs/`** - 偏好设置集成
  - **`security/`** - 安全与保护代码

### 文件命名规范

- 视图控制器：`*ViewController.h` / `*ViewController.m`
- 自定义视图：`*View.h` / `*View.m` 或 `*Cell.h` / `*Cell.m`
- C 头文件：`*.h` 对应 `*.c` 或 `*.m` 实现文件
- 头文件使用 `#pragma once` 或传统包含保护

## 代码风格指南

### 语言与架构

- **主要语言**：Objective-C 和 C
- **无外部依赖**：不使用 CocoaPods、Swift Packages 或第三方框架
- **不使用 Storyboards 或 XIBs**：UI 以编程方式构建
- **不使用 Xcode Assets**：资源以编程方式生成

#### 为什么不使用 Xcode Assets 和 Storyboards？

Battman 不使用 Xcode Assets (.xcassets) 或 Storyboards/XIBs，原因如下：

- **开源工具链兼容性**：这些格式是 Apple 的私有商业格式，无法使用开源工具链构建。这会阻止项目在非 Apple 平台或使用替代构建系统上构建。

- **跨平台协作**：我们有不使用 macOS 和 Xcode 的协作者。使用这些格式会破坏可维护性，并阻止贡献者在他们偏好的环境中工作。

- **编程式 UI 偏好**：我们始终偏好以编程方式编写 UI，而不是在某种文件中预定义它们。这种方法提供更好的版本控制、更轻松的代码审查，以及 UI 构建的更大灵活性。

#### 为什么不使用第三方依赖？

Battman 有意避免第三方依赖（CocoaPods、Swift Packages、外部框架），原因如下：

- **控制与可维护性**：外部代码不在我们的控制之下，我们无法响应可能影响项目的潜在未来更改、破坏性更新或弃用。

- **协作可访问性**：并非每个协作者都能在其构建系统上拉取此类依赖。避免外部依赖可确保所有贡献者无论其环境设置如何都能构建和处理项目，促进更好的协作。

如果您需要通常来自第三方库的功能，请直接在代码库中实现它或调整必要的代码以适合 Battman 的架构（例如，我们已完全用 Objective-C 重写了 Swift 的 `UberSegmentedControl`）。

#### 为什么不使用 Swift 代码？

Battman 仅使用 Objective-C 和 C，不接受 Swift 代码提交，原因如下：

- **稳定性与兼容性**：Swift 本身频繁更新并带有破坏性更改，并且总是试图放弃对先前系统版本的支持。这会产生维护负担和兼容性问题，与 Battman 支持 iOS 12+ 的目标相冲突。

- **工具链大小**：Swift 工具链比常规 LLVM + Clang 大得多，这对我们现有的协作者不友好，他们可能资源有限或偏好最小化工具链安装。

- **不可避免的 Swift 例外**：如果您的提交无法避免使用 Swift（例如，WidgetKit 仅允许 Swift），请创建一个新的子项目来包含它。否则，所有逻辑和 UI 都应使用 Objective-C 和 C 编写。

  如果您必须使用 Swift，您的 Swift 代码必须满足以下要求：
  - 您的 Swift 代码应在 iOS 12 或更早版本上编译和测试。
  - 您的 Swift 代码应使用 Swift 4 或更早版本编写。
  - 您的 Swift 代码至少应能在 iOS 上使用 Procursus 的 Swift 工具链构建。

### C / Objective-C 模式

#### 单例模式

```objc
+ (instancetype)sharedPrefs {
    static BattmanPrefs *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] _init];
    });
    return shared;
}
```

#### iOS 版本检查

```objc
if (@available(iOS 13.0, *)) {
    // iOS 13+ 代码
} else {
    // 回退代码
}
```
```c
if (__builtin_available(iOS 13.0, *)) {
    // iOS 13+ 代码
} else {
    // 回退代码
}
```

#### 调试日志

```c
// DBGLOG 基于 NSLog()
DBGLOG(CFSTR("调试消息: %@"), value);
```
```objc
// DBGLOG 基于 NSLog()
DBGLOG(@"调试消息: %@", value);
```

#### 本地化

```c
// 对于 NSString
NSString *localized = _("String to localize");

// 对于 C 字符串
const char *localized = _C("String to localize");
```

#### 静态初始化

```c
static dispatch_once_t onceToken;
static bool value;

dispatch_once(&onceToken, ^{
    // 一次性初始化
    value = compute_value();
});
```

### 错误处理

- 检查系统调用的返回值
- 对错误条件使用 `os_log_error`
- 尽可能提供回退路径
- 避免在可恢复的错误上崩溃

### 内存管理

- Objective-C 代码使用 ARC
- C 代码使用手动内存管理（malloc 的要用 free）
- 小心处理 CF 类型 - 适当使用 `CFRelease`

### 构建系统

Battman 可以使用以下方式构建：
- **Xcode**：标准 Xcode 项目
- **Makefile**：位于 `Battman/Makefile`，支持 Linux 构建

关键构建参数：
- `-fobjc-arc`：自动引用计数
- `-target arm64-apple-ios12.0`：iOS 12+ 部署目标
- `-DDEBUG`：调试构建
- `-DUSE_GETTEXT`：可选的 gettext 本地化支持

## 推荐工作流程

1. Fork 本仓库，并基于此创建功能分支。
2. 使用清晰、聚焦的提交（commit）逐步完成修改。
3. 尽量将 PR 控制在易于审阅的规模，而不是一次性包含大量无关改动。
4. 在尽可能多的相关 iOS 版本 / 设备上进行测试。
5. 提交 Pull Request，并在说明中写明：
   - 具体改动内容；
   - 测试方式与结果；
   - 对用户可见行为的任何影响。

## 代码审查指南

- 遵循现有的代码风格和模式
- 保持与 iOS 12+ 的兼容性
- 尽可能在模拟器和真实设备上测试
- 使用适当的日志记录（调试使用 DBGLOG，生产使用 os_log）
- 确保正确的内存管理
- 为复杂逻辑或硬件特定代码添加注释
- 如果行为发生变化，请更新相关文档

请勿将个人证书、密钥等私密信息加入仓库或构建脚本中。
