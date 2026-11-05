[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Magic Mouse Toolkit UI/design considerations

> **[SUPERSEDED] This document is an early-stage exploration as of 2026-07-02 and does not apply to the current implementation.**
> Directions such as "undecorated, plain macOS standard look," "480×520pt," and
> "explore with Stitch" were all dropped following the Liquid Glass direction
> finalized on 2026-07-06. **The current source of truth is [DESIGN.md](./DESIGN.md)
> and `Sources/DesignSystem.swift`.** The following is kept only as a historical record.

Written 2026-07-02. Fleshes out the "Settings UI" requirements from
[SPEC.md](./SPEC.md). The implementation will be SwiftUI (integrated with
AppKit), and since the plan was to explore the design in Stitch, this also
serves to organize the premises to hand off to the Stitch-side work (DESIGN.md).

## Design direction

- Aim for **the plain look of native macOS SwiftUI components**, not a
  "polished custom design"
- Avoid custom skinning such as colors, corner radii, or shadows in general.
  Rely on the standard styling of native components like `Toggle`, `Slider`,
  `Stepper`, `Form`, and `Section`
- Reference: the undecorated, functional layouts common in the System
  Settings app itself (which this session has been operating in throughout)
  and in the settings screens of menu-bar-resident utilities such as
  Rectangle and AltTab
- Automatically follow dark mode/light mode (use system colors such as
  `Color(.labelColor)`, with no custom color palette)

## Screen layout

### 1. Menu bar dropdown (when clicking the resident icon)

A simple `NSMenu` (a native AppKit menu, not SwiftUI, following MouseToucher/MiddleClick):

```
✓ Enabled
────────────
Open Settings…
────────────
Version 1.0
About This App…
────────────
Quit                    ⌘Q
```

### 2. Settings window

A single window divided into sections (no tabs; laid out vertically with
`Form` + `Section`, close to the look of a single pane in macOS System
Settings). Window size is roughly 480×520pt, non-resizable (typical for a
utility app's settings screen).

```
┌─────────────────────────────────┐
│  Magic Mouse Toolkit Settings          │
├─────────────────────────────────┤
│  ○ Enable                  [Toggle]│
│                                   │
│  ── Gestures ──────────────────  │
│  One-finger tap = left/right click [Toggle]│
│  Two-finger tap = left click    [Toggle]│
│  Two-finger click = middle click[Toggle]│
│                                   │
│  ── Detection range ───────────  │
│  Horizontal [====●────●====] 0-100%│
│  Vertical   [========●==●==] 0-100%│
│  (higher value = further forward) │
│                                   │
│  ── Sensitivity ────────────────  │
│  Tap detection time  [Slider] 0.16s│
│  Movement tolerance  [Slider]      │
│  Scroll-misfire guard [Slider]      │
│                                   │
│  ── Debug ──────────────────────  │
│  ▸ Live tap coordinate display (collapsible) │
│                                   │
└─────────────────────────────────┘
```

## Component mapping (native SwiftUI)

| Element | SwiftUI component | Notes |
|---|---|---|
| Enable/disable, each gesture on/off | `Toggle` (`.toggleStyle(.switch)`) | The system-standard switch style. No decoration |
| Sensitivity parameters | `Slider` + value label | The standard `Slider(value:in:) { Text(...) }` form. The numeric value is shown only as a `Text` next to the Slider |
| Detection range (X/Y each min-max) | Two `Slider`s in tandem, or a custom-built `RangeSlider` equivalent | SwiftUI has no built-in "range slider," so placing a min Slider and a max Slider side by side is the simplest and keeps the native feel intact (consistent with the policy of not building an elaborate custom track UI) |
| Section dividers | `Form` + `Section(header:)` | The very structure of the macOS standard settings screen |
| Debug coordinate display | `DisclosureGroup` + `Text` (monospaced font) | Made collapsible so it stays out of view during normal use |
| Overall window | Wrap a `Form` in an `NSHostingController` and host it in a regular `NSWindow` | The standard pattern for opening a window from a menu bar app |

## Notes on building this "in Stitch"

Stitch excels at producing web/HTML-style mockups, so exporting it directly
tends to produce an "app-like but not macOS-native" look — card shadows,
gradients, custom rounded toggles, and so on. **This needs care given this
project's requirement (looking exactly like native SwiftUI)**:

- When building in Stitch, don't use the `taste-design` skill (which aims for
  a premium, non-generic UI), since it runs counter to this project's
  direction of avoiding decoration
- Instead, explicitly specify in the Stitch prompt something like: "macOS
  native System Settings look, SF Pro font, native macOS switch toggles, no
  shadows, no gradients, no rounded cards, flat grouped list style like macOS
  Preferences"
- Treat Stitch's output (HTML/CSS) purely as **a reference for layout and
  information design**; when implementing, replace it with native SwiftUI
  components per the component-mapping table above (don't code up Stitch's
  look as-is)
- When producing `DESIGN.md`, also spell out that colors "follow system
  colors" and that "no corner radii or shadows are used," so there's no
  ambiguity downstream

## Typography and color

- Font: use `Font.system(...)` (San Francisco) as-is. No custom font specified
- Font size: default Control Size inside `Form` (matches the look of the
  macOS settings screens)
- Colors: use only `Color(.controlAccentColor)` (e.g., the color when a
  toggle is on), `Color(.labelColor)`, and `Color(.secondaryLabelColor)`. No
  custom brand color
- Icon: use SF Symbols for the menu bar icon (e.g., `computermouse.fill`,
  following MouseToucher); no custom icon is created

## Open questions

- Whether to do a preview that visualizes the detection range — "overlay the
  current range settings as a rectangle on a Magic-Mouse-shaped figure" (same
  open question as in SPEC.md). Given this session's simple-first direction,
  it may be reasonable to defer this for the initial implementation and rely
  on numeric sliders alone
- Whether the settings window should use `Form` style (iOS-like grouped list)
  or simply stack `VStack`s → `Form` is recommended since it's closer to the
  native macOS "System Settings" look

---

<a id="简体中文"></a>

# Magic Mouse Toolkit 界面与设计考量

> **【已被取代】本文是截至 2026-07-02 的早期探索，不适用于当前实现。** “无装饰的 macOS 标准外观”“480×520pt”“使用 Stitch 探索”等方向，均在 2026-07-06 确定 Liquid Glass 方向后放弃。**当前以 [DESIGN.md](./DESIGN.md) 和 `Sources/DesignSystem.swift` 为准。** 以下仅作历史记录。

写于 2026-07-02。本文细化 [SPEC.md](./SPEC.md) 中的“设置界面”要求，计划用 SwiftUI 配合 AppKit 实现。由于当时准备使用 Stitch 探索设计，也在此整理交接给 Stitch 设计工作（DESIGN.md）的前提。

## 设计方向

- 目标是 **macOS 原生 SwiftUI 组件的朴素外观**，不追求精修的自定义视觉设计。
- 原则上不定制颜色、圆角或阴影，依靠 `Toggle`、`Slider`、`Stepper`、`Form`、`Section` 等原生组件的标准样式。
- 参考系统设置，以及 Rectangle、AltTab 等菜单栏工具设置页常见的无装饰功能布局。
- 自动跟随深浅色模式，使用 `Color(.labelColor)` 等系统颜色，不建立自定义配色。

## 界面布局

### 1. 菜单栏下拉菜单

使用简单的原生 AppKit `NSMenu`，而非 SwiftUI，沿用 MouseToucher／MiddleClick 的方式：

```
✓ 已启用
────────────
打开设置…
────────────
版本 1.0
关于本应用…
────────────
退出                    ⌘Q
```

### 2. 设置窗口

单窗口分节，无标签页，使用 `Form` + `Section` 纵向布局，类似 macOS 系统设置的单个面板。窗口约 480×520pt，不可调整大小，符合工具应用设置页的常见形式。

```
Magic Mouse Toolkit 设置
├─ 启用                         [开关]
├─ 手势
│  ├─ 单指轻点＝左／右键         [开关]
│  ├─ 双指轻点＝左键             [开关]
│  └─ 双指实体点击＝中键         [开关]
├─ 检测范围
│  ├─ 水平范围                   [滑块] 0–100%
│  └─ 纵向范围                   [滑块] 0–100%
│     （数值越大越靠前）
├─ 灵敏度
│  ├─ 轻点检测时间               [滑块] 0.16s
│  ├─ 移动容差                   [滑块]
│  └─ 滚动误触防止               [滑块]
└─ 调试
   └─ 实时轻点坐标显示（可折叠）
```

## 组件对应关系（原生 SwiftUI）

| 元素 | SwiftUI 组件 | 说明 |
|---|---|---|
| 启用／停用、各手势开关 | `Toggle`（`.toggleStyle(.switch)`） | 系统标准开关，无装饰 |
| 灵敏度参数 | `Slider` + 数值标签 | 标准 `Slider(value:in:) { Text(...) }`，旁边用 `Text` 显示数值 |
| 检测范围（X/Y 各自最小／最大） | 两个配合使用的 `Slider`，或自建类似 `RangeSlider` 的控件 | SwiftUI 无内建范围滑块，最小／最大两个滑块并排最简单，也能保留原生观感，符合不自建复杂轨道的方针 |
| 分节 | `Form` + `Section(header:)` | macOS 标准设置页结构 |
| 调试坐标显示 | `DisclosureGroup` + 等宽字体 `Text` | 可折叠，日常使用时隐藏 |
| 整体窗口 | 用 `NSHostingController` 包装 `Form`，放入普通 `NSWindow` | 菜单栏应用打开窗口的标准模式 |

## 使用 Stitch 探索的注意点

Stitch 擅长生成 Web／HTML 风格稿，直接导出容易得到“像应用但不像原生 macOS”的界面，例如卡片阴影、渐变、自定义圆角开关。**这需要结合本项目当时“与原生 SwiftUI 完全一致”的要求谨慎处理**：

- 在 Stitch 中制作时，不使用追求精致、非通用视觉的 `taste-design` 技能，因为它与不加装饰的方向冲突。
- 提示词应明确要求 macOS 原生系统设置外观、SF Pro 字体、原生开关、无阴影、无渐变、无圆角卡片，以及类似 macOS 偏好设置的平面分组列表。
- Stitch 的 HTML/CSS 输出仅作**布局和信息设计参考**；实现时按上表替换为原生 SwiftUI 组件，不照搬视觉皮肤。
- 生成 `DESIGN.md` 时明确颜色跟随系统、不使用圆角或阴影，避免后续歧义。

## 字体与颜色

- 字体直接用 `Font.system(...)`（San Francisco），不指定自定义字体。
- 字号使用 `Form` 默认 Control Size，与 macOS 设置页一致。
- 颜色只用 `Color(.controlAccentColor)`、`Color(.labelColor)` 和 `Color(.secondaryLabelColor)`，不设品牌色。
- 菜单栏图标使用 SF Symbols，例如沿用 MouseToucher 的 `computermouse.fill`；不创建自定义图标。

## 待定问题

- 是否在 Magic Mouse 外形图上叠加当前检测范围矩形，与 SPEC.md 的待定问题相同。按当时先求简单的方向，初版可以只用数值滑块，暂缓预览。
- 设置窗口使用 `Form` 分组列表，还是简单堆叠 `VStack`：建议 `Form`，更接近 macOS 原生系统设置。
