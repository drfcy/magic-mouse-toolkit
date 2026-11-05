[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Magic Mouse Toolkit architecture

Magic Mouse Toolkit is a menu bar app that reads Magic Mouse multi-touch input and
converts it into clicks, scrolling, cursor movement, and keyboard macros via CGEvent.

## Runtime

- Swift 6
- macOS 26 SDK
- AppKit + SwiftUI
- Built directly with `swiftc`
- arm64 / x86_64 Universal Binary
- Bundle ID: `com.mori0818.magicmousetoolkit`

## Third-party provenance

See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md) for detailed copyright
notices and licenses.

### MouseToucher

[MouseToucher](https://github.com/meatpaste/mousetoucher) is MIT licensed.
Magic Mouse Toolkit's early prototype used it as a starting point for the
following areas:

- C bridge declarations for `MultitouchSupport.framework`
- Device enumeration via `MTDeviceCreateList` and `MTDeviceIsBuiltIn`
- The Universal Binary build approach using `swiftc` and `lipo`
- Initial setup for requesting Accessibility permissions
- The initial design of the tap-detection state machine

The current code adds device retain/release, Bluetooth reconnection, IOKit
attach/detach notifications, shared state across callbacks, scroll vetoes,
macros, virtual trackpad mode, and more, and has substantially redesigned the
file structure and implementation. Even so, because the provenance remains
material, MouseToucher's copyright notice and MIT License continue to be
included.

### MiddleClick

[MiddleClick](https://github.com/artginzburg/MiddleClick) is GPL-3.0 licensed.
Its approach of rewriting the type and button number of the same CGEvent and
resending it as a middle click — rather than discarding and reposting the
physical click event — was referenced and adapted here.

Magic Mouse Toolkit is distributed in its entirety under GPL-3.0-only to
preserve compatibility with this provenance.

## Components

### `MultitouchDevice.swift`

- Enumerates devices from MultitouchSupport
- Determines a Magic Mouse's family ID and built-in attribute
- Monitors the built-in trackpad solely to distinguish input sources
- Retains/releases device references
- Handles sleep/wake, Bluetooth reconnection, and IOKit attach/detach notifications

### `TouchGestureManager.swift` / `TapRecognizer.swift`

- Tracks touch frames
- Determines one-, two-, and three-finger gestures
- Suppresses false taps during scrolling, physical clicks, and inertia
- Reads settings from `SettingsSnapshot`; does not read UserDefaults inside MT callbacks

### `EventInterceptor.swift`

Handles the following through a single CGEventTap:

- Monitoring physical clicks
- Converting a two-finger physical click into a middle click
- Monitoring scroll state
- Separating scroll ownership while in virtual trackpad mode
- Passing through native inertial scrolling

Inside the CGEventTap callback, it is a safety requirement not to allocate,
write to file logs, or read UserDefaults.

### `TrackpadModeController.swift`

- Converts relative movement on the Magic Mouse surface into cursor movement
- Generates events on a dedicated 120 Hz queue
- Stops cursor tracking during two-finger scrolling
- Switches modes via a three-finger double tap

### `MacroRecorder.swift` / `ActionExecutor.swift`

- Records key events with a listen-only CGEventTap
- Automatically stops after 200 events or 60 seconds
- Saves to on-device UserDefaults
- Plays back on a dedicated serial queue
- Interrupts a previous playback via a generation number when retriggered

The public release removes the unused code paths for arbitrary shell
commands, launching arbitrary apps, and generic keystrokes, exposing only
macros and trackpad-mode switching.

### `PermissionMonitor.swift`

Rather than relying solely on the TCC cache of `AXIsProcessTrusted()`, this
monitors permission state by checking whether a test CGEventTap can be
created. When permission is lost, it fully tears down EventInterceptor.

See [SAFETY.md](./SAFETY.md) for user-facing safety requirements.

### `PointerSpeedManager.swift`

Changes the system's `HIDMouseAcceleration` via the IOHIDEventSystemClient
SPI. It keeps the original value in UserDefaults and restores it on normal
termination.

### `Logger.swift`

Writes diagnostic information to the unified log and to
`~/Library/Logs/MagicMouseToolkit.log`. The file log rotates to
`MagicMouseToolkit.log.old` at roughly 1 MiB.

## Build and signing

`build.sh` compiles arm64 and x86_64 separately and combines them into a
Universal Binary with `lipo`.

- `SIGN_ID` unspecified: ad-hoc signing
- `SIGN_ID` specified and present in Keychain: signs with the specified identity

To distribute a public binary, Developer ID Application signing and Apple
notarization must be performed separately. Private keys and certificates are
not included in the repository.

## Private API boundary

This project depends on the following private APIs:

- `/System/Library/PrivateFrameworks/MultitouchSupport.framework`
- `MTDevice*`
- `MTRegisterContactFrameCallback`
- `IOHIDEventSystemClient*`
- `HIDMouseAcceleration`

As a result, it is not suitable for the Mac App Store and may lose
compatibility with future versions of macOS.

---

<a id="简体中文"></a>

# Magic Mouse Toolkit 架构

Magic Mouse Toolkit 是一个菜单栏应用，读取 Magic Mouse 的多点触控输入，并通过 CGEvent 将其转换为点击、滚动、光标移动和键盘宏。

## 运行环境

- Swift 6
- macOS 26 SDK
- AppKit + SwiftUI
- 直接使用 `swiftc` 构建
- arm64 / x86_64 通用二进制文件
- Bundle ID：`com.mori0818.magicmousetoolkit`

## 第三方来源

详细版权声明与许可证见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

### MouseToucher

[MouseToucher](https://github.com/meatpaste/mousetoucher) 使用 MIT 许可证。Magic Mouse Toolkit 早期原型的以下部分以其为起点：

- `MultitouchSupport.framework` 的 C 桥接声明
- 通过 `MTDeviceCreateList` 和 `MTDeviceIsBuiltIn` 枚举设备
- 使用 `swiftc` 和 `lipo` 构建通用二进制文件
- 请求辅助功能权限的初始设置
- 轻点检测状态机的初始设计

当前代码增加了设备 retain/release、蓝牙重连、IOKit 连接／断开通知、跨回调共享状态、滚动否决、宏和虚拟触控板模式等，并大幅调整了文件结构与实现。由于这些来源关系仍具有实质意义，继续保留 MouseToucher 的版权声明与 MIT 许可证。

### MiddleClick

[MiddleClick](https://github.com/artginzburg/MiddleClick) 使用 GPL-3.0 许可证。本项目参考并改编了它的处理方式：直接改写同一个 CGEvent 的类型和按钮编号，将其作为中键点击继续传递，而不是丢弃实体点击事件后重新投递。

为保持与上述代码来源的许可证兼容，Magic Mouse Toolkit 整体按 GPL-3.0-only 分发。

## 组件

### `MultitouchDevice.swift`

- 从 MultitouchSupport 枚举设备
- 判断 Magic Mouse 的 family ID 与内建设备属性
- 仅为区分输入来源而监视内建触控板
- 管理设备引用的 retain/release
- 处理睡眠／唤醒、蓝牙重连及 IOKit 连接／断开通知

### `TouchGestureManager.swift` / `TapRecognizer.swift`

- 跟踪触摸帧
- 判断单指、双指和三指手势
- 在滚动、实体点击和惯性过程中抑制误触发轻点
- 从 `SettingsSnapshot` 读取设置，不在 MT 回调内读取 UserDefaults

### `EventInterceptor.swift`

通过单个 CGEventTap 处理：

- 监视实体点击
- 将双指实体点击转换为中键点击
- 监视滚动状态
- 在虚拟触控板模式下区分滚动事件的归属
- 放行原生惯性滚动

CGEventTap 回调内不得分配内存、写入文件日志或读取 UserDefaults，这是安全要求。

### `TrackpadModeController.swift`

- 将 Magic Mouse 表面的相对移动转换为光标移动
- 在专用的 120 Hz 队列上生成事件
- 双指滚动期间停止光标跟踪
- 通过三指双击切换模式

### `MacroRecorder.swift` / `ActionExecutor.swift`

- 使用只监听的 CGEventTap 录制按键事件
- 达到 200 个事件或 60 秒时自动停止
- 保存至本机 UserDefaults
- 在专用串行队列上回放
- 再次触发时，通过代数编号中断上一次回放

公开版本移除了未使用的任意 Shell 命令、任意应用启动和通用按键代码路径，只开放宏和触控板模式切换。

### `PermissionMonitor.swift`

通过检查能否创建测试 CGEventTap 监控权限状态，而不只依赖 `AXIsProcessTrusted()` 的 TCC 缓存。权限丢失时，完整拆除 EventInterceptor。

面向用户的安全要求见 [SAFETY.md](./SAFETY.md)。

### `PointerSpeedManager.swift`

通过 IOHIDEventSystemClient SPI 修改系统的 `HIDMouseAcceleration`，将原值保存在 UserDefaults 中，并在正常终止时恢复。

### `Logger.swift`

将诊断信息写入统一日志和 `~/Library/Logs/MagicMouseToolkit.log`。文件日志达到约 1 MiB 后轮换为 `MagicMouseToolkit.log.old`。

## 构建与签名

`build.sh` 分别编译 arm64 和 x86_64，再使用 `lipo` 合并为通用二进制文件。

- 未指定 `SIGN_ID`：使用 ad-hoc 签名
- 已指定 `SIGN_ID` 且钥匙串中存在该身份：使用指定身份签名

公开分发二进制文件时，需要另行完成 Developer ID Application 签名和 Apple 公证。仓库不包含私钥或证书。

## 私有 API 边界

本项目依赖以下私有 API：

- `/System/Library/PrivateFrameworks/MultitouchSupport.framework`
- `MTDevice*`
- `MTRegisterContactFrameCallback`
- `IOHIDEventSystemClient*`
- `HIDMouseAcceleration`

因此，本项目不适用于 Mac App Store，并可能在未来 macOS 版本中失去兼容性。
