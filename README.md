# Magic Mouse Toolkit（个人修改版）

<p align="center">
  <img src="docs/images/app-icon.png" width="180" alt="Magic Mouse Toolkit 图标：紫色圆角底上的白色妙控鼠标">
</p>

这是基于 [mori0818/Magic Mouse Toolkit](https://github.com/mori0818/magic-mouse-toolkit) 修改的 macOS 工具。本仓库记录的是个人修改版，主要尝试把 Apple Magic Mouse 从传统鼠标改造成一种可以像触控板一样操作 Mac 的输入设备。

本项目沿用并扩展了原项目的代码，保留其来源、许可证和第三方代码说明；它不是原作者发布的官方版本。个人修改目前位于 [`drfcy-custom-edition` 分支](https://github.com/drfcy/magic-mouse-toolkit/tree/drfcy-custom-edition)。

## 为什么做这个修改版

Magic Mouse 有多点触控表面，能识别轻点、滑动和多指手势。但在我的实际使用中，它作为传统鼠标时最突出的困难是光标点选不够准确：光标会受手指在表面的接触位置影响，小幅变化也可能让指针偏移，精确点中小目标并不容易。与我使用过的 GWP 三代等传统鼠标相比，我认为 Magic Mouse 的优势不在于取代常规鼠标的定位精度，而在于它的触控表面和多指输入能力。

因此，这个修改版想探索另一种用法：**不把 Magic Mouse 当作一只普通鼠标来用，而是把它当作妙控板式的触控输入面。** 软件中的“触控板模式”把手指在鼠标表面的移动转换为光标移动，并提供轻点、点击方式、滚动方向和灵敏度等设置。光标移动倍率和加速度也可以调整，以改善慢速定位和快速移动时的手感。

这个思路还有两点实际考虑：

- **不用桌面也能操作 Mac。** 把 Magic Mouse 拿在手里，可以单手移动光标和执行轻点；人在离 Mac 较远的地方时，也能把它当作简单的手持遥控输入设备。
- **提供一种成本较低的尝试。** 在我的购买场景中，Magic Mouse 的价格明显低于妙控板。若手边已经有 Magic Mouse，这种方案也可以利用现有设备探索触控板式操作。

这些是本修改版的设计动机和个人使用判断，不代表所有用户的体验，也不声称软件可以完全复制 Apple 妙控板的硬件、系统行为或全部手势。

## 我的使用方案

软件只是整个方案的一部分。我的设想和实际配置由软件、BetterTouchTool（BTT）以及个人的硬件摆放方式共同组成：

1. 在本软件中开启“触控板模式”，用手指在 Magic Mouse 表面滑动来移动光标，并按需要设置轻点与点击方式。
2. 对双指缩放、三指左右切换、三指上滑等组合手势，在 BetterTouchTool 中为 Magic Mouse 设置对应操作。具体能识别哪些手势，取决于 BTT 的配置和 macOS 当前提供的输入事件。
3. 为了在桌面上使用时减少设备滑动，我会在鼠标底部贴防滑胶贴；为了避免底部光学传感器继续带动指针，我会遮住该传感器。这是我的个人硬件改造方式，不属于软件功能，也不是所有用户都必须照做。

本软件主要负责 Magic Mouse 的触摸输入、光标移动、轻点和相关滚动处理；BetterTouchTool 负责由用户配置的系统手势与快捷操作。普通鼠标和妙控板仍可按各自的方式使用。横置滚动等部分方向相关行为仍在探索中，不能据此认为所有妙控板手势都已完整实现。

## 这个版本改了什么

- 设置界面整理为“常用”“触控板模式”“鼠标模式”“高级与诊断”四个类别。
- 新增简体中文界面，并保留英文和日文。
- 可从菜单栏直接开关触控板模式，也可设置应用启动后自动开启。
- 可选触控板式轻点（单指左键、双指右键）或左右分区式点击。
- 增加光标加速度，并可分别调整慢速移动的基础倍率与快速移动的加速。
- 支持鼠标横向摆放时调整光标移动方向和轨迹比例。
- 提供轻点识别、滚动、设备检测和诊断等设置。

此列表描述本分支中已有的设置与实现，不表示本软件单独实现了 BetterTouchTool 的手势，也不表示所有方向组合和设备场景都经过了完整验证。

## 应用图标

图标以白色 Magic Mouse 为主体，放在紫色圆角底上。白色鼠标图形直接标明软件对应的设备；圆角图标和紫色背景则用于识别这个个人修改版。它表达的是“用鼠标表面进行触控操作”的项目方向，不代表图标本身包含任何功能。

## 要求

- macOS 26 或更高版本
- Apple Magic Mouse
- 构建需要 Xcode，或包含 macOS 26 SDK 的 Swift 工具链
- 执行点击合成、宏和输入映射需要“辅助功能”权限

本程序使用 Apple 的私有 `MultitouchSupport.framework` 和 IOKit 接口，macOS 更新后可能需要调整，也不适用于 Mac App Store 发布。

## 构建和运行

请明确检出个人修改分支；仓库的 `main` 分支仍对应原项目的主线。

```sh
git clone --branch drfcy-custom-edition --single-branch https://github.com/drfcy/magic-mouse-toolkit.git
cd magic-mouse-toolkit
./build.sh
open "build/Magic Mouse Toolkit.app"
```

默认使用 ad-hoc 签名。如有自己的签名身份，可通过 `SIGN_ID` 指定：

```sh
SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

不要把签名证书或私钥提交到仓库。更换签名后，macOS 可能要求重新授权；请先退出旧版本，再修改权限。

## 隐私

- 程序本身不包含遥测、分析 SDK 或网络传输功能。
- 录制宏时，按键代码、修饰键、按下状态和时间间隔会保存在本机的 UserDefaults 中；不会保存或发送按键对应的文字内容。请勿在输入密码或其他秘密信息时录制。
- 诊断日志保存在 `~/Library/Logs/MagicMouseToolkit.log`，约 1 MiB 后轮换；日志可能包含手势判断、坐标等运行信息。

## 使用前请留意

程序运行时不要在系统设置中关闭或移除它的“辅助功能”权限。若要更改权限，请先从菜单栏正常退出程序，再修改权限并重新打开。权限操作不当可能导致系统输入暂时失灵。更多说明见 [SAFETY.md](./SAFETY.md)。

系统指针速度增强会暂时修改全局 `HIDMouseAcceleration`，正常退出时会恢复。如果程序被强制退出后速度没有恢复，请先退出程序，再到“系统设置 → 鼠标”移动一次“跟踪速度”滑块。

## 来源与许可证

本项目是原项目的衍生修改版本。原项目为 [mori0818/Magic Mouse Toolkit](https://github.com/mori0818/magic-mouse-toolkit)。原项目也记录了所借鉴的第三方项目及其许可。请保留仓库中的 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)、[LICENSE](./LICENSE) 和相关版权声明。

本项目按 GNU GPL v3.0 only 发布。第三方代码来源及许可说明见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

## 其他文档

- [SAFETY.md](./SAFETY.md)：权限修改、输入异常与系统鼠标速度
- [SPEC.md](./SPEC.md)：功能规格
- [ARCHITECTURE.md](./ARCHITECTURE.md)：架构与代码来源
- [IMPLEMENTATION.md](./IMPLEMENTATION.md)：实现细节
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)：第三方代码与许可证
- [CONTRIBUTING.md](./CONTRIBUTING.md)：贡献指南
- [SECURITY.md](./SECURITY.md)：安全问题反馈
