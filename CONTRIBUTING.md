[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Contributing

Contributions are welcome.

## Development setup

Requirements:

- macOS 26 or later
- Xcode or a Swift toolchain containing the macOS 26 SDK
- Apple Magic Mouse for physical gesture testing

Build:

```sh
./build.sh
```

The default build uses ad-hoc signing. To use an existing signing identity:

```sh
SIGN_ID="Your Signing Identity" ./build.sh
```

## Workflow

1. Create a focused feature branch.
2. Keep changes limited to one feature or fix.
3. Run `./build.sh`.
4. Describe the physical-device checks you performed.
5. Open a pull request with the motivation, implementation, risks, and checks.

## Input-safety rules

- Read [SAFETY.md](./SAFETY.md) before changing CGEventTap, permissions, or
  MultitouchSupport code.
- Do not use accessibility permission toggling as a routine test.
- Do not run `tccutil reset` in tests or setup scripts.
- Keep MT and CGEventTap callbacks allocation-free and free of file logging.
- Do not add code that silently records or transmits keyboard input.

## Licensing

Contributions are accepted under GPL-3.0-only. Preserve third-party copyright
and license notices. If code is based on another project, identify the source
and license in the pull request and update `THIRD_PARTY_NOTICES.md` when needed.

---

<a id="简体中文"></a>

# 贡献指南

欢迎参与贡献。

## 开发环境

要求：

- macOS 26 或更高版本
- Xcode，或包含 macOS 26 SDK 的 Swift 工具链
- 实体 Apple Magic Mouse，用于手势测试

构建：

```sh
./build.sh
```

默认构建使用 ad-hoc 签名。使用已有签名身份：

```sh
SIGN_ID="Your Signing Identity" ./build.sh
```

## 工作流程

1. 创建专门的功能分支。
2. 每次修改聚焦于一个功能或修复。
3. 运行 `./build.sh`。
4. 说明完成了哪些实体设备检查。
5. 提交 Pull Request，交代修改动机、实现、风险和验证情况。

## 输入安全规则

- 修改 CGEventTap、权限或 MultitouchSupport 代码前，先阅读 [SAFETY.md](./SAFETY.md)。
- 不要把切换辅助功能权限作为常规测试。
- 不要在测试或设置脚本中运行 `tccutil reset`。
- MT 和 CGEventTap 回调中应避免内存分配和文件日志写入。
- 不要添加静默记录或传输键盘输入的代码。

## 许可证

贡献按 GPL-3.0-only 接受。保留第三方版权与许可证声明。如果代码基于其他项目，请在 Pull Request 中注明来源和许可证，并按需更新 `THIRD_PARTY_NOTICES.md`。
