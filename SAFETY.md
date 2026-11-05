[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Safety

Magic Mouse Toolkit uses CGEventTap, which monitors and transforms system-wide
input, and Apple's private MultitouchSupport API. It has been verified on real
hardware for normal use, but operations that forcibly change permissions or
processes require caution.

## Accessibility permission

While Magic Mouse Toolkit is running, do not do the following:

- Turn off Magic Mouse Toolkit's accessibility permission in System Settings
- Remove Magic Mouse Toolkit from the accessibility list
- Reset permissions with `tccutil reset`
- Toggle the permission ON/OFF repeatedly in a short time

Revoking permission while an app holding a CGEventTap is running can cause
clicks and keyboard input to stop responding on the macOS side.

When changing permissions:

1. Quit Magic Mouse Toolkit normally from the menu bar
2. Confirm in Activity Monitor that `MagicMouseToolkit` has terminated
3. Change the permission in System Settings
4. Launch Magic Mouse Toolkit

If input stops responding, quit Magic Mouse Toolkit using another available
input path. If that does not recover it, restart macOS.

## Cursor speed

The speed boost temporarily changes the system-wide `HIDMouseAcceleration`.
It is restored to its original value on normal quit.

If the speed remains altered after a force quit:

1. Quit Magic Mouse Toolkit
2. Move the "System Settings → Mouse → Tracking speed" slider once
3. If needed, turn off Magic Mouse Toolkit's speed boost and restart it

## Macro recording

While recording, all keyboard events are monitored via a listen-only
CGEventTap. Recorded data is stored only on the local device, but you should
not record while entering passwords or other secret information.

## Development and verification

Even when modifying input-related code, do not use permission ON/OFF toggling
as a regression test. For changes around EventInterceptor, PermissionMonitor,
and MultitouchDevice, first build, review the code, and verify the normal
quit path.

---

<a id="简体中文"></a>

# 安全说明

Magic Mouse Toolkit 使用 CGEventTap 监视和转换系统范围内的输入，并使用 Apple 私有的 MultitouchSupport API。日常使用已经过实体设备验证，但强制修改权限或进程状态的操作仍需谨慎。

## 辅助功能权限

Magic Mouse Toolkit 运行期间，请勿执行以下操作：

- 在系统设置中关闭 Magic Mouse Toolkit 的辅助功能权限
- 将 Magic Mouse Toolkit 从辅助功能列表中移除
- 使用 `tccutil reset` 重置权限
- 在短时间内反复开关权限

持有 CGEventTap 的应用仍在运行时撤销权限，可能导致 macOS 的鼠标点击和键盘输入失去响应。

需要更改权限时：

1. 从菜单栏正常退出 Magic Mouse Toolkit。
2. 在活动监视器中确认 `MagicMouseToolkit` 已终止。
3. 在系统设置中更改权限。
4. 重新启动 Magic Mouse Toolkit。

如果输入失去响应，请通过其他可用的输入方式退出 Magic Mouse Toolkit；仍无法恢复时，重启 macOS。

## 光标速度

速度增强会暂时修改系统范围内的 `HIDMouseAcceleration`，正常退出时恢复原值。

如果强制退出后速度仍未恢复：

1. 退出 Magic Mouse Toolkit。
2. 移动一次“系统设置 → 鼠标 → 跟踪速度”滑块。
3. 必要时，关闭 Magic Mouse Toolkit 的速度增强并重新启动应用。

## 宏录制

录制期间，通过只监听的 CGEventTap 监视所有键盘事件。录制数据仅保存在本机，但不要在输入密码或其他秘密信息时进行录制。

## 开发与验证

即使修改输入相关代码，也不要把反复开关权限作为回归测试。修改 EventInterceptor、PermissionMonitor 和 MultitouchDevice 时，应先构建、审查代码，并验证正常退出流程。
