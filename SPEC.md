[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Magic Mouse Toolkit Specification

## Background and purpose

Add the following two custom operations to Magic Mouse:
1. Click (left/right) via tap
2. Middle click via a two-finger operation

Testing with existing commercial/OSS tools (MiddleClick, MouseToucher)
revealed the following issues:

- **MiddleClick**: also responds to the trackpad, so it cannot be restricted
  to Magic Mouse only
- **MouseToucher**: Magic Mouse-specific (already has logic built in to
  exclude the built-in trackpad). However, it had the following operational
  problems:
  - Every adjustment of sensitivity/response range requires rewriting the
    source code and rebuilding
  - With ad-hoc signing, rebuilding changes the code-signing hash (cdhash),
    which can cause macOS to prompt for re-approval of accessibility
    permission. See `SAFETY.md` for the safe procedure of quitting the app
    before changing permissions
  - No middle-click functionality

To solve these, we will integrate the functionality of both tools and
**newly develop our own app whose settings can be changed from the UI
(no rebuild required)**.

## Operating environment

- macOS (Universal Binary supporting both Apple Silicon and Intel)
- Magic Mouse (Bluetooth connection)
- Target devices are external multitouch devices only (the built-in trackpad
  is detected and excluded via `MTDeviceIsBuiltIn`)

## Functional requirements

### 1. One-finger tap → left click / right click

- Lightly tapping the Magic Mouse surface with one finger produces a normal
  left click
- If the X coordinate of the tap position exceeds a (variable) threshold, it
  is treated as a right click (carried over from the existing tool: default
  X > 0.6)
- Conditions for judging a tap:
  - Contact duration is at or below the "maximum tap duration"
  - The amount of finger movement during contact is at or below the
    "movement tolerance"
  - To avoid misidentifying a tap as a scroll operation, the finger's
    cumulative movement distance and instantaneous speed are also used in
    the judgment (see "Scroll misfire prevention" below)

### 2. Two-finger tap → left click

- Tapping with two fingers at nearly the same time is treated as a left
  click
- Applies the same effective range and sensitivity judgment as the
  one-finger tap (initial policy; to be verified)

### 3. Two-finger click (physical press) → middle click

- When the Magic Mouse body is physically pressed down (a normal click
  action) while two fingers are resting on it, that input is **replaced
  with a middle click**
- Implementation approach: monitor system-level physical click events
  (`leftMouseDown`/`leftMouseUp`) with a `CGEventTap`. If the number of
  multitouch contact fingers at the moment the click occurs is two, swallow
  the original left-click event and instead synthesize and dispatch a
  middle-click event (`otherMouseDown`/`otherMouseUp`)
- If there is one finger (normal click) or three or more fingers, the event
  is passed through unchanged

### 4. Effective range (tap response zone) adjustable from the UI

- The Magic Mouse surface is handled in normalized coordinates (0.0–1.0),
  and a click is only registered if the position where the tap **started**
  falls within this rectangular range
- The following can be adjusted from the UI, in percent units (0–100%):
  - X direction: minimum and maximum values (horizontal range)
  - Y direction: minimum and maximum values (vertical range; verified that a
    higher Y value corresponds to the front — the tip end reached by
    extending the finger)
- Changes take effect immediately without restarting the app (saved to
  UserDefaults, and read in real time by the running instance)

### 5. Sensitivity adjustable numerically from the UI

"Sensitivity" is a collective term for several internal parameters. It is
adjusted in the UI via sliders, etc.

| Parameter | Description | Default (reference: final value from MouseToucher testing) |
|---|---|---|
| Maximum tap duration | If contact duration exceeds this, the tap is not registered (seconds) | 0.16 |
| Cursor movement tolerance | Upper limit of cursor movement amount during a tap (screen coordinate system) | 0.045 |
| Finger straight-line movement tolerance | Upper limit of the straight-line distance from the tap start point to the current point (surface normalized coordinates 0–1) | 0.09 |
| Finger cumulative movement distance tolerance | Upper limit of the total path length the finger traveled during a tap (countermeasure for back-and-forth scrolling, surface normalized coordinates 0–1) | 0.07 |
| Instantaneous speed tolerance | Upper limit of the maximum instantaneous speed observed during a tap (surface normalized coordinates/second, countermeasure for flick scrolling) | Needs calibration (measurement was interrupted in the previous session) |

In the UI, these will be individually adjustable via fine-grained sliders
(the idea of consolidating them into a single slider for an "easy mode" is
deferred for now and will be considered further if requested).

### 6. Scroll misfire prevention

To distinguish tap judgment from scroll judgment, the following are used in
combination (knowledge gained from existing MouseToucher testing):

- Straight-line movement distance check (start point → end point)
- Cumulative movement distance check (handles cases where back-and-forth
  scrolling brings the start and end points close together)
- Instantaneous speed check (uses the `velocity` field of MTTouch. A fast
  flick scroll can have a high speed even when the movement distance is
  small, allowing it to slip through the distance-based judgment. This
  detects that case)

### 7. Settings UI

- Menu-bar resident app (no Dock icon, `LSUIElement`)
- Clicking the menu bar icon shows the following menu:
  - Toggle enabled/disabled
  - "Open Settings…" → shows the settings window
  - Launch at login (toggle; or manage as before via the Login Items in
    System Settings)
  - About this app
  - Quit
- Settings window (SwiftUI):
  - Effective range settings: X min/max, Y min/max (percent sliders). If
    possible, consider a preview that overlays the rectangle in real time on
    a graphic of the Magic Mouse for visual confirmation (a simplified
    display is acceptable for the initial implementation)
  - Sensitivity settings: adjust the above 5 parameters via sliders or
    numeric input
  - For debugging: live display of tap coordinates (to assist calibration;
    shows the current X/Y coordinates and whether the most recent tap was
    inside/outside the zone)

## Non-functional requirements

### Stabilizing accessibility permission

- Use a **stable self-signed certificate** for code signing (a self-signed
  certificate with a fixed Common Name, not ad-hoc)
- This ensures that permission (TCC) is not revoked when rebuilding to add
  sensitivity adjustments or new features
- Record the certificate setup procedure in the README/comments (reuse the
  procedure already verified with MouseToucher)

### Permission requests

- Accessibility permission (`AXIsProcessTrustedWithOptions`): required for
  synthesizing clicks from taps, and for the event tap/replacement of
  physical clicks
- If permission is not granted on first launch, display an alert prompting
  the user to open System Settings (carried over from existing MouseToucher)

## Open items / to be discussed

- Whether the effective range for the two-finger tap (left click) is shared
  with the one-finger tap, or configurable separately
- Whether support for three-finger gestures is needed (not included in this
  scope; alternative candidates such as BetterTouchTool have been considered
  separately)
- The specific default value for the instantaneous speed tolerance
  (calibration needed; to be determined by collecting logs on real hardware)
- Feasibility and priority of implementing the range preview overlaid on the
  Magic Mouse shape in the settings window

## Development approach

1. Review and agreement on this specification
2. Implement core logic (multitouch detection, tap/click judgment, settings
   loading)
3. Implement the settings UI (SwiftUI)
4. Implement two-finger physical click → middle click conversion
   (CGEventTap)
5. Calibrate sensitivity and range on real hardware (verify while adjusting
   from the UI, no rebuild required)
6. Consider disabling/uninstalling MiddleClick and MouseToucher

---

<a id="简体中文"></a>

# Magic Mouse Toolkit 功能规格

## 背景与目的

为 Magic Mouse 增加以下两类自定义操作：

1. 通过轻点执行左／右键点击。
2. 通过双指操作执行中键点击。

测试现有商业／开源工具（MiddleClick、MouseToucher）后，发现以下问题：

- **MiddleClick**：也会响应触控板，无法仅作用于 Magic Mouse。
- **MouseToucher**：专用于 Magic Mouse，已有排除内建触控板的逻辑，但存在这些操作问题：
  - 每次调整灵敏度或响应范围都要修改源代码并重新构建。
  - ad-hoc 签名下，重建会改变代码签名哈希（cdhash），可能导致 macOS 要求重新批准辅助功能权限。先退出应用再更改权限的安全流程见 `SAFETY.md`。
  - 没有中键点击功能。

为解决这些问题，计划整合两者的功能，**开发可直接从界面修改设置、无需重新构建的应用**。

## 运行环境

- macOS，通用二进制文件支持 Apple Silicon 和 Intel
- Magic Mouse，蓝牙连接
- 仅以外接多点触控设备为目标；通过 `MTDeviceIsBuiltIn` 检测并排除内建触控板

## 功能要求

### 1. 单指轻点 → 左／右键点击

- 单指轻点 Magic Mouse 表面时，执行普通左键点击。
- 轻点位置的 X 坐标超过可调整的阈值时，视为右键点击；沿用现有工具的默认值 X > 0.6。
- 轻点判断条件：
  - 接触时长不超过“轻点最长时长”。
  - 接触期间手指移动量不超过“移动容差”。
  - 为避免将滚动误判为轻点，同时判断手指累计移动距离和瞬时速度，见下文“滚动误触防止”。

### 2. 双指轻点 → 左键点击

- 两根手指几乎同时轻点时，视为左键点击。
- 使用与单指轻点相同的有效范围和灵敏度判断；这是初步方案，尚待验证。

### 3. 双指实体按压 → 中键点击

- 两指放在 Magic Mouse 上并实体按下鼠标时，将输入**替换为中键点击**。
- 实现思路：用 `CGEventTap` 监视系统级实体点击事件（`leftMouseDown` / `leftMouseUp`）。点击发生时，如多点触控接触指数量为 2，则吞掉原左键事件，改为合成并发送中键事件（`otherMouseDown` / `otherMouseUp`）。
- 单指普通点击或三指及以上接触时，原样放行事件。

### 4. 从界面调整有效范围（轻点响应区域）

- 将 Magic Mouse 表面映射为 0.0–1.0 的归一化坐标；只有轻点**起始位置**位于矩形范围内时，才注册点击。
- 界面中以 0–100% 百分比调整：
  - X 方向：最小值和最大值，即水平范围。
  - Y 方向：最小值和最大值，即纵向范围；已验证 Y 越大越靠前，亦即伸直手指所指向的前端。
- 修改保存到 UserDefaults，由运行中的实例实时读取，无需重启应用。

### 5. 从界面以数值调整灵敏度

“灵敏度”是多个内部参数的统称，通过滑块等界面控件调整。

| 参数 | 说明 | 默认值（参考 MouseToucher 测试最终值） |
|---|---|---|
| 轻点最长时长 | 接触时长超过此值则不注册轻点，单位秒 | 0.16 |
| 光标移动容差 | 轻点期间屏幕坐标系中的光标移动量上限 | 0.045 |
| 手指直线移动容差 | 轻点起点至当前点的直线距离上限，表面归一化坐标 0–1 | 0.09 |
| 手指累计移动距离容差 | 轻点期间手指总路径长度上限，用于防止往返滚动误触，表面归一化坐标 0–1 | 0.07 |
| 瞬时速度容差 | 轻点期间观测到的最大瞬时速度上限，单位为表面归一化坐标／秒，用于防止快速甩动滚动误触 | 需要校准，上次会话中测量中断 |

这些参数将通过细粒度滑块分别调整。暂缓把它们整合为一个“简易模式”滑块，如有需求再考虑。

### 6. 滚动误触防止

结合既有 MouseToucher 测试经验，综合以下指标区分轻点和滚动：

- 直线移动距离：起点到终点。
- 累计移动距离：识别往返滚动后起终点重新接近的情况。
- 瞬时速度：使用 MTTouch 的 `velocity` 字段。快速甩动即使移动距离较小，也可能有较高速度；距离判断可能放过此类输入，速度判断用于补充识别。

### 7. 设置界面

- 菜单栏常驻应用，无 Dock 图标，使用 `LSUIElement`。
- 点击菜单栏图标显示：
  - 启用／停用开关
  - “打开设置…”：显示设置窗口
  - 登录时启动：开关，或仍通过系统设置中的登录项管理
  - 关于本应用
  - 退出
- SwiftUI 设置窗口：
  - 有效范围：X 最小／最大、Y 最小／最大百分比滑块。如可行，考虑在 Magic Mouse 图形上实时叠加矩形范围预览；初版可采用简化显示。
  - 灵敏度：通过滑块或数值输入调整上述 5 个参数。
  - 调试：实时显示轻点坐标，辅助校准；显示当前 X/Y 坐标及最近一次轻点位于区域内还是区域外。

## 非功能要求

### 稳定辅助功能权限

- 使用**稳定的自签名证书**进行代码签名：固定 Common Name，不使用 ad-hoc。
- 目的是避免为增加灵敏度调整或新功能而重新构建时，权限（TCC）被撤销。
- 在 README／注释中记录证书设置步骤，沿用已在 MouseToucher 中验证的流程。

### 权限请求

- 辅助功能权限（`AXIsProcessTrustedWithOptions`）用于从轻点合成点击，以及事件监听和实体点击替换。
- 首次启动未授权时，弹窗提示用户打开系统设置；沿用现有 MouseToucher 的方式。

## 待定事项

- 双指轻点（左键）的有效范围是否与单指共用，或单独配置。
- 是否需要三指手势支持；不在本规格范围内，BetterTouchTool 等替代方案另行考虑。
- 瞬时速度容差的具体默认值，需要在实体设备上收集日志校准。
- 设置窗口中在 Magic Mouse 外形上叠加范围预览的可行性与优先级。

## 开发步骤

1. 审阅并确认本规格。
2. 实现核心逻辑：多点触控检测、轻点／点击判断、设置加载。
3. 实现 SwiftUI 设置界面。
4. 实现双指实体点击到中键点击的 CGEventTap 转换。
5. 在实体设备上从界面调整并验证灵敏度与范围，无需重建。
6. 考虑停用或卸载 MiddleClick 和 MouseToucher。
