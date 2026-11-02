# Magic Mouse Toolkit（个人修改版）

这是基于 [mori0818/Magic Mouse Toolkit](https://github.com/mori0818/magic-mouse-toolkit) 修改的 macOS 工具，用 Apple Magic Mouse 实现可配置的轻点操作和“触控板模式”。本仓库保留原项目的来源与许可证信息，并在此基础上加入中文界面和个人功能调整；它不是原作者发布的官方版本。

## 这个版本改了什么

- 设置界面整理为“常用”“触控板模式”“鼠标模式”“高级与诊断”四个类别。
- 新增简体中文界面，并保留英文和日文。
- 可从菜单栏直接开关触控板模式，也可设置应用启动后自动开启。
- 可选触控板式轻点（单指左键、双指右键）或左右分区式点击。
- 增加光标加速度，并可分别调整慢速移动的基础倍率与快速移动的加速。
- 支持鼠标横向摆放时调整光标移动方向和轨迹比例。

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

## 系统鼠标速度

系统指针速度增强会暂时修改全局 `HIDMouseAcceleration`，正常退出时会恢复。如果程序被强制退出后速度没有恢复，请先退出程序，再到“系统设置 → 鼠标”移动一次“跟踪速度”滑块。

## 使用前请留意

程序运行时不要在系统设置中关闭或移除它的“辅助功能”权限。若要更改权限，请先从菜单栏正常退出程序，再修改权限并重新打开。权限操作不当可能导致系统输入暂时失灵。更多说明见 [SAFETY.md](./SAFETY.md)。

## 来源与许可证

本项目是原项目的衍生修改版本。原项目为 [mori0818/Magic Mouse Toolkit](https://github.com/mori0818/magic-mouse-toolkit)。它本身也记录了所借鉴的第三方项目及其许可。请保留仓库中的 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)、[LICENSE](./LICENSE) 和相关版权声明。

本项目按 GNU GPL v3.0 only 发布。第三方代码来源及许可说明见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

## 其他文档

- [SAFETY.md](./SAFETY.md)：权限修改、输入异常与系统鼠标速度
- [SPEC.md](./SPEC.md)：功能规格
- [ARCHITECTURE.md](./ARCHITECTURE.md)：架构与代码来源
- [IMPLEMENTATION.md](./IMPLEMENTATION.md)：实现细节
- [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)：第三方代码与许可证
- [CONTRIBUTING.md](./CONTRIBUTING.md)：贡献指南
- [SECURITY.md](./SECURITY.md)：安全问题反馈
