# Magic Mouse Toolkit（个人修改版）

<p align="center">
  <img src="docs/images/app-icon.png" width="180" alt="Magic Mouse Toolkit 图标：紫色圆角底上的白色妙控鼠标">
</p>

这是基于 [mori0818/Magic Mouse Toolkit](https://github.com/mori0818/magic-mouse-toolkit) 修改的 macOS 工具。本仓库记录的是个人修改版，主要尝试把 Apple Magic Mouse 从传统鼠标改造成一种可以像触控板一样操作 Mac 的输入设备。

本项目沿用并扩展了原项目的代码，保留其来源、许可证和第三方代码说明；它不是原作者发布的官方版本。个人修改目前位于 [`drfcy-custom-edition` 分支](https://github.com/drfcy/magic-mouse-toolkit/tree/drfcy-custom-edition)。

## 为什么做这个修改版

Magic Mouse 有多点触控表面，能识别轻点、滑动和多指手势。但在我的实际使用中，它作为传统鼠标时最突出的困难是光标点选不够准确：光标会受手指在表面的接触位置影响，小幅变化也可能让指针偏移，精确点中小目标并不容易。与我使用过的罗技 GPW3（Logitech G Pro X Superlight 2）等传统鼠标相比，我认为 Magic Mouse 的优势不在于取代常规鼠标的定位精度，而在于它的触控表面和多指输入能力。

因此，这个修改版想探索另一种用法：**不把 Magic Mouse 当作一只普通鼠标来用，而是把它当作妙控板式的触控输入面。** 软件中的“触控板模式”把手指在鼠标表面的移动转换为光标移动，并提供轻点、点击方式、滚动方向和灵敏度等设置。光标移动倍率和加速度也可以调整，以改善慢速定位和快速移动时的手感。

### 两款鼠标的实测参数完整对比

下表整理了我提供的 RTINGS 测试截图中的数据。GPW3 在这里指 Logitech G Pro X Superlight 2。

| 测试指标 | Apple Magic Mouse 2 | Logitech GPW3（G Pro X Superlight 2） |
| --- | ---: | ---: |
| CPI 综合评分 | 6.0 | **9.8** |
| SRAV（速度相关误差变化） | +1.00% | **−0.04%（1600 CPI）** |
| 速度间精度误差 | 3.85% | **0.34%** |
| 最差追踪误差 | −27.15% | **1.44%** |
| CPI 范围 | 固定 1300 | 可调，最低 100 |
| CPI 调节步长 | 不支持 | 1 CPI |
| 传感器延迟评分 | 6.2 | **9.4** |
| 移动中途延迟 | 23.7 ms | **1.4 ms** |
| 点击延迟评分 | 3.4 | **9.8** |
| 无线点击延迟 | 44.4 ms（蓝牙） | **1.5 ms（接收器）** |
| 无线最大回报率 | 约 90 Hz（其他测试） | **8000 Hz** |
| 重量 | 约 99 g | **约 60 g** |
| 连接方式 | 蓝牙 | LIGHTSPEED 无线接收器 |

参数来源：[RTINGS Apple Magic Mouse 2 测试](https://www.rtings.com/mouse/reviews/apple/magic-mouse-2?share_token=ZHQVeCAFp2EUqG71TACcUUSY-3oh335x)；[RTINGS Logitech G Pro X Superlight 2 测试](https://www.rtings.com/mouse/reviews/logitech/g-pro-x-superlight-2?share_token=jtg4JUMtqqbIA9gwXpGg-OLOhg6f5HtA)。GPW3 的 8000 Hz 是支持的最高回报率，实际回报率还取决于设备设置、接收器和系统环境；Magic Mouse 2 的约 90 Hz 来自其他测试，并非固定适用于所有环境。

两款鼠标的 SRAV 测试设置并不相同：Magic Mouse 2 在固定 1300 CPI 下测试，GPW3 的对应数据是在 1600 CPI 下测试。因此这些数据适合说明各自的速度稳定性，但不是完全同设置的实验室对照。RTINGS 的测试也不能直接等同于 macOS 上最终的光标体验。

### 这些数据如何解释“点不准”

- **移动反馈延迟差距明显。** Magic Mouse 2 的移动中途延迟为 23.7 ms，GPW3 为 1.4 ms，前者约为后者的 17 倍。这可能让小目标附近的减速和微调显得不够跟手。
- **不同速度下的追踪一致性有差距。** Magic Mouse 2 的速度间精度误差为 3.85%，GPW3 为 0.34%，数值约相差 11.3 倍。它反映的是速度变化时追踪结果的一致性差距，不能说 GPW3 的实际定位精度因此提高了 11.3 倍。
- **点击反馈也有明显差距。** 无线点击延迟分别为 44.4 ms 和 1.5 ms，数值约相差 30 倍。它主要影响点击响应快慢；如果光标已经停稳，这项延迟本身通常不会把点击位置移到别处。
- **总体追踪误差和最差值要分开理解。** Magic Mouse 2 的平均追踪偏差约为 −20%，曲线整体较平，固定比例偏差可以通过调整跟踪速度补偿；−27.15% 是最差测试值，不是日常每次移动的典型误差。GPW3 的最差追踪误差为 1.44%，曲线接近 0% 误差线。

从这组实测数据看，GPW3 在追踪一致性、移动响应和点击响应方面有明显优势，这支持了我把 Magic Mouse 改作触控板式输入设备的动机。但“点不准”还可能同时受到手指接触面积变化、macOS 指针加速、按压时鼠标是否移动等因素影响；这些 RTINGS 测试没有直接测量我个人的完整操作链路，所以数据解释的是硬件差异，不是对单一原因的证明。

这个思路还有两点实际考虑：

- **不用桌面也能操作 Mac。** 把 Magic Mouse 拿在手里，可以单手移动光标和执行轻点；人在离 Mac 较远的地方时，也能把它当作简单的手持遥控输入设备。
- **提供一种成本较低的尝试。** 在我的购买场景中，Magic Mouse 的价格明显低于妙控板。若手边已经有 Magic Mouse，这种方案也可以利用现有设备探索触控板式操作。

这些参数来自特定测试和我提供的资料，不能替代每位用户在自己的桌面、系统设置和握持方式下进行的对照测试。设计动机仍是个人使用判断，不代表所有用户的体验，也不声称软件可以完全复制 Apple 妙控板的硬件、系统行为或全部手势。

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
