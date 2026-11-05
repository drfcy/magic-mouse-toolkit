[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Security policy

## Reporting a vulnerability

Please do not disclose security or privacy vulnerabilities in a public issue.
Use GitHub's private vulnerability reporting or a private Security Advisory for
this repository.

Include:

- affected commit or version
- macOS and device version
- reproduction steps
- expected and actual behavior
- whether Accessibility or Input Monitoring permissions were involved
- relevant logs with personal information removed

Do not reproduce permission-related input freezes without first reading
[SAFETY.md](./SAFETY.md).

## Scope

Security-sensitive areas include:

- CGEventTap creation and event transformation
- keyboard macro recording and playback
- accessibility permission monitoring
- shell or process execution
- system pointer-speed modification
- release signing and update distribution

The project does not currently provide automatic updates or network services.

---

<a id="简体中文"></a>

# 安全政策

## 报告漏洞

请勿在公开 Issue 中披露安全或隐私漏洞。请使用 GitHub 的私密漏洞报告功能，或为本仓库创建私密 Security Advisory。

报告中请包含：

- 受影响的提交或版本
- macOS 和设备版本
- 复现步骤
- 预期行为和实际行为
- 是否涉及辅助功能或输入监控权限
- 已移除个人信息的相关日志

复现与权限相关的输入失灵问题前，请先阅读 [SAFETY.md](./SAFETY.md)。

## 范围

与安全有关的部分包括：

- CGEventTap 的创建与事件转换
- 键盘宏的录制和回放
- 辅助功能权限监控
- Shell 或进程执行
- 系统指针速度修改
- 发布签名与更新分发

本项目目前不提供自动更新或网络服务。
