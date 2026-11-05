[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Third-party notices

Magic Mouse Toolkit contains or is derived from ideas and portions of the following
open-source projects.

## MouseToucher

Repository: <https://github.com/meatpaste/mousetoucher>

License: MIT

Copyright (c) 2025 Roger Hughes

MouseToucher was used as the starting point for parts of the private
MultitouchSupport bridge declarations, device enumeration approach, direct
`swiftc`/`lipo` build flow, permission setup, and the early tap-recognition
prototype. Magic Mouse Toolkit has substantially restructured and extended these
areas, but retains this notice because the provenance is material.

Current provenance by area:

| Magic Mouse Toolkit area | MouseToucher relationship | Current state |
|---|---|---|
| `Sources/MultitouchBridge.h` | API declarations and touch-structure layout derived from the MouseToucher bridge | Renamed, corrected, reduced, and extended with family ID and IOHID SPI declarations |
| `Sources/MultitouchDevice.swift` | External-device enumeration and built-in-device filtering originated in MouseToucher | Reworked with family filtering, retain/release, sleep handling, reconnect retries, IOKit notifications, and source separation |
| `Sources/TouchGestureManager.swift` / `TapRecognizer.swift` | Early tap-recognition prototype was informed by MouseToucher | Replaced by a larger state machine with multi-finger groups, vetoes, macros, and trackpad mode |
| `Sources/SynthesizedClick.swift` | Initial CGEvent click-posting approach was informed by MouseToucher | Reworked with event signatures, right-click support, and diagnostics |
| `Sources/AppDelegate.swift` | Initial menu-bar and Accessibility setup was informed by MouseToucher | Reworked around settings, permission monitoring, sleep lifecycle, macros, and device state |
| `build.sh` | Direct `swiftc` plus `lipo` Universal Binary flow was informed by MouseToucher | Rewritten for the current source tree, macOS 26, configurable signing, retries, SwiftUI, QuartzCore, and IOKit |
| `Info.plist` / `main.swift` | Standard macOS app-bundle boilerplate follows the same shape | Product-specific identifiers and current deployment target |

A source comparison against MouseToucher `main` at commit `edc96506` found no
large unchanged Swift implementation block in the current Magic Mouse Toolkit tree.
The remaining relationship is best described as limited direct textual reuse
plus material architectural and prototype provenance. It is intentionally
credited rather than minimized.

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## MiddleClick

Repository: <https://github.com/artginzburg/MiddleClick>

License: GNU General Public License v3.0

MiddleClick informed the CGEventTap approach used to transform a physical
mouse click into a middle click and was quoted in early architecture
documentation. Magic Mouse Toolkit is distributed under GPL-3.0-only so that the
license remains compatible with this provenance. The GPL text is included in
[LICENSE](./LICENSE).

## Apple frameworks and trademarks

Magic Mouse, macOS, AppKit, SwiftUI, IOKit, and MultitouchSupport are Apple
technologies or trademarks. Apple does not endorse this project.
MultitouchSupport and the IOHIDEventSystemClient functions used here are not
public APIs and may change without notice.

---

<a id="简体中文"></a>

# 第三方声明

Magic Mouse Toolkit 包含、借鉴或衍生自以下开源项目的思想与部分代码。

## MouseToucher

仓库：<https://github.com/meatpaste/mousetoucher>

许可证：MIT

Copyright (c) 2025 Roger Hughes

MouseToucher 是私有 MultitouchSupport 桥接声明、设备枚举方式、直接使用 `swiftc` / `lipo` 的构建流程、权限设置和早期轻点识别原型的部分实现起点。Magic Mouse Toolkit 已对这些部分进行了大幅重构和扩展，但由于来源关系具有实质意义，继续保留本声明。

各部分的当前来源关系：

| Magic Mouse Toolkit 部分 | 与 MouseToucher 的关系 | 当前状态 |
|---|---|---|
| `Sources/MultitouchBridge.h` | API 声明和触摸结构布局衍生自 MouseToucher 桥接代码 | 已重命名、修正、精简，并增加 family ID 和 IOHID SPI 声明 |
| `Sources/MultitouchDevice.swift` | 外接设备枚举和内建设备过滤源于 MouseToucher | 已重构，增加设备族过滤、retain/release、睡眠处理、重连重试、IOKit 通知和输入来源区分 |
| `Sources/TouchGestureManager.swift` / `TapRecognizer.swift` | 早期轻点识别原型受到 MouseToucher 启发 | 已替换为更大的状态机，包含多指分组、否决条件、宏和触控板模式 |
| `Sources/SynthesizedClick.swift` | 最初的 CGEvent 点击投递方式受到 MouseToucher 启发 | 已重构，增加事件签名、右键支持和诊断 |
| `Sources/AppDelegate.swift` | 最初的菜单栏和辅助功能设置受到 MouseToucher 启发 | 已围绕设置、权限监控、睡眠生命周期、宏和设备状态重构 |
| `build.sh` | 直接使用 `swiftc` 和 `lipo` 构建通用二进制文件的方式受到 MouseToucher 启发 | 已按当前源代码目录、macOS 26、可配置签名、重试、SwiftUI、QuartzCore 和 IOKit 重写 |
| `Info.plist` / `main.swift` | 标准 macOS 应用包样板采用相同结构 | 使用本产品标识和当前部署目标 |

与 MouseToucher `main` 的 `edc96506` 提交进行源代码比较后，未发现当前 Magic Mouse Toolkit 代码树中存在大块未修改的 Swift 实现。现存关系可描述为有限的直接文本复用，以及具有实质意义的架构与原型来源。本项目明确标注这些贡献，不淡化其来源。

### MIT 许可证

上方英文部分的 [MIT License](#mit-license) 保留了完整许可证原文。该原文及版权声明应按其要求随副本或软件的重要部分一并保留。

## MiddleClick

仓库：<https://github.com/artginzburg/MiddleClick>

许可证：GNU General Public License v3.0

MiddleClick 为通过 CGEventTap 将实体鼠标点击转换为中键点击的方式提供了参考，早期架构文档也曾引用该项目。为保持与该来源的许可证兼容，Magic Mouse Toolkit 按 GPL-3.0-only 分发。GPL 原文见 [LICENSE](./LICENSE)。

## Apple 框架与商标

Magic Mouse、macOS、AppKit、SwiftUI、IOKit 和 MultitouchSupport 是 Apple 的技术或商标。Apple 未为本项目背书。此处使用的 MultitouchSupport 和 IOHIDEventSystemClient 函数不是公开 API，可能随时发生变化。
