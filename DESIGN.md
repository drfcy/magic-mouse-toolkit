[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Magic Mouse Toolkit Design System (DESIGN.md)

Created 2026-07-02 / fully revised 2026-07-28.
**The source of truth is `Sources/DesignSystem.swift`. This document explains its intent and the empirical basis behind it.**
If values disagree, the code is correct. Never write literal values in views — always go through `DS.*` tokens.

The original two-stage plan of "Phase 1 (native) → Phase 2 (Liquid Glass reskin)"
was completed on 2026-07-06. Everything below describes the current (post-Phase-2) implementation.

## Design concept

**"Turn the surface glass of the Magic Mouse 2 (white) directly into the window itself"**

- A standard `.titled` window + a transparent title bar + an empty unified `NSToolbar`. The traffic-light controls and title bar are not custom-built
- `glassEffect(.regular)` is spread across the full window, with a **white plate** placed on top inset 8pt from every edge.
  This 8pt band is what reads as the "glass rim"
- Decoration is limited to what's needed for the physical representation of glass. **No shadows, gradients, or multiple accent colors**
- The white plate is fixed white (`window.appearance = .aqua` locks the appearance to light). Text uses tokens that follow the system appearance

## Token conventions (self-imposed rules)

1. One token per role. **Only one ladder per role** — never create duplicate tokens
   (e.g., top content padding is `contentTop`, one value only. Don't add more per page type)
2. Never use spacing values that fall outside the 4/8 grid (`DS.Space`). The only exception is `DS.Plate`
3. Only `.regular` and `.semibold` font weights (never `.medium`)
4. No shadows. Don't mix corner-radius styles (continuous / circular)
5. Only one accent color, `DS.Color.accent`. **The only place it is explicitly `.tint`ed is `Toggle`**
6. **Layout values are never decided by eye.** Determine them from pixel measurements on @2x captures or from font-metric measurements,
   and leave the basis as a comment on the token

## Token definitions (`Sources/DesignSystem.swift`)

### Colors `DS.Color`

| Token | Value | Usage |
|---|---|---|
| `labelPrimary` | `.primary` | Labels/headings on control rows |
| `labelSecondary` | `.secondary` | Captions, units, numeric values |
| `accent` | `.controlAccentColor` | `Toggle` only (the sole accent) |
| `debugPass` / `debugFail` | systemGreen / systemRed | ✓ / ✗ judgment in the live display |
| `plateBase` | white 0.78 | The white plate's base; edges show a slight translucency |
| `plateCore` | white 0.82 | The white core, inset 26pt from the edge and blurred(18) |
| `cardFill` | rgb(241,241,241) | Live-display cards |

Compositing `plateBase` + `plateCore` yields a center of ≈0.96 (nearly white) and an edge of ≈0.78 (the glass beneath shows through).
A center-anchored `RadialGradient` is **not used** because it produces circular banding on large screens (the fade is instead distance-from-edge based).

### Spacing `DS.Space`

`xs 4 / s 8 / m 12 / l 16 / xl 24 / xxl 32`. Only use this ladder — never create one-off values per use case.

### Plate geometry `DS.Plate` — **do not touch**

| Token | Value | Meaning |
|---|---|---|
| `inset` | 8 | Width of the glass rim (how far the white plate sits inside the edges) |
| `fadeWidth` | 26 | How far the white core is pulled in from the plate edge = the fade band |
| `fadeBlur` | 18 | Edge blur applied to the white core |
| `radius` | 16 | Corner radius of the white plate (**must always use `style: .continuous`**) |

**Principle of concentric corner radii**: the inner corner radius = the outer window's corner radius − the inset.
Since macOS 26's `.titled` window uses a continuous (squircle) curve with a measured curvature range of ≈28pt,
a continuous radius of 16pt against an 8pt inset makes the rim width look uniform (measured 7.5–8.5pt) at both corners and edges.
Using `circular` would make the rim look thin at the corners.

### Corner radius `DS.Radius`

Only `card = 10`. Aside from the plate geometry, this is the only corner radius used anywhere in the app.

### Typography `DS.Font` (5 tokens)

| Token | Definition | Usage |
|---|---|---|
| `pageTitle` | 13 / semibold | Page heading "Advanced Settings," back-button icon |
| `sectionHeader` | 11 / semibold | Section headers, column headings |
| `body` | 13 | Labels on control rows, HUD body text |
| `caption` | 11 | Supplementary captions, card body text |
| `value` | 12 / monospaced | Slider values, measured values in live displays |

The Figma comp's 10pt / 7pt were too small on real hardware, so they were raised to macOS's standard legible sizes (2026-07-10).

### Layout `DS.Layout`

| Token | Value | Basis |
|---|---|---|
| `windowSize` | 700 × 392 | contentSize. The unified title bar adds 66pt on top for a total measured height of 458 |
| `contentLeading` / `contentTrailing` | 32 (`Space.xxl`) | Left/right symmetric. Shortened from 40→32 (2026-07-28 real-hardware feedback) |
| `mainColumnWidth` | 328 | 32 + **328** + 44 + 264 + 32 = 700 |
| `columnGap` | 44 | From the right edge of the left column to the left edge of the card |
| `liveCardSize` | 264 × 340 | Must fit within the plate. No overflow allowed |
| `contentTop` | 8 (`Space.s`) | Distance from the bottom of the title bar (safe area). **Shared across all pages** |
| `formBuiltInInset` | 30 | `Form(.grouped)`'s built-in inset. **@2x measured value** |
| `formInsetCompensation` | `contentLeading − 30` = 2 | Correction to align the left/right edges of the Advanced Settings page with the main screen |
| `rowHeight` | 26 | Fixed height for control rows. Fixed mechanically so wrapping never causes wobble |
| `sliderLabelWidth` | 176 | Longest label, en "2-finger simultaneity window" measured at 175.2pt → rounded up to the next 8-grid step |
| `valueWidth` | 64 | Longest value, en "0.25 sec" measured at 59.3pt → rounded up to the next 8-grid step |

**Height breakdown**: `contentTop 8 + heading 15 + gap 12 + card 340 = 375` + bottom padding 9 + rim 8 = 392.
When tightening the top, also measure the bottom edge, and shrink the height tokens until top and bottom are comparable (top 8 / bottom 9.5pt).

**Left edge of `Form(.formStyle(.grouped))` (macOS 26, 700pt width, @2x measured, 2026-07-28)**

| Element | Left edge |
|---|---|
| Section header text | 30pt |
| Contents of rows within a group card (labels, captions) | 30pt |
| **The group card's background rectangle itself** | **20pt** (10pt further out than the headers/rows) |

The only baseline that can be shared is the 30 that headers and rows have in common. **Only the card background always overflows 10pt outward,
and this cannot be reconciled while keeping Form's structure intact** (reconciling it would require restructuring into a `VStack` with a custom card).
By giving the custom header (back button + page title) `contentLeading`, and giving the Form `formInsetCompensation`,
all text ends up on the same left line (32pt).

## Component conventions

- **Toggle**: `Toggle` + `.toggleStyle(.switch)` + `.controlSize(.small)` + `.tint(DS.Color.accent)`
- **Buttons**: standardize on `.bordered` **only**, and express hierarchy purely through `controlSize`
  (primary = `.regular` / secondary/lower-level settings = `.small`). `.borderedProminent` is not used
- **Slider rows**: share `SliderRow` across every slider. Fixed via `lineLimit(1)` + `frame(height: rowHeight)`.
  **The value column contains only "number + unit"** (qualifiers like "25% from the tip" belong on the row label side).
  Putting variable-length text in a fixed-width value column causes that row alone to wrap, breaking the rhythm of rows across sections
- **Sections**: the Advanced Settings page uses `Form` + `Section(header:)` + `.formStyle(.grouped)` +
  `.scrollContentBackground(.hidden)`. The main screen uses a flat `VStack`
- **Live display**: numeric values always use `DS.Font.value` (monospaced). Judgments are shown as ✓/✗ + `debugPass`/`debugFail`
- No custom-drawn controls are created

## Prohibited

- Literal values specified directly in views (`.padding(13)`, `Color.gray`, `.font(.system(size: 12))`, etc.)
- Third-party fonts or color assets
- Shadows, multiple accent colors, `.borderedProminent`
- Leaving a trailing `Spacer(minLength: 0)` at the end of a fixed-width two-column `HStack`.
  Since `spacing` applies to every adjacent pair, the gap ends up counted twice, and the overflowing `HStack`
  gets center-aligned, making the left/right margins asymmetric. Keep margins symmetric via the outer `padding` instead
- Deciding layout by eye. After implementation, verify actual left/right and top/bottom coordinates numerically via @2x captures

## Localization and layout

The first argument to `NSLocalizedString` **is the Japanese literal itself, used as the key** (shared key across both ja/en `.strings` files, currently 117 entries).
Since changing the wording changes the key, whenever a layout adjustment touches the displayed string,
you must update `Resources/{ja,en}.lproj/Localizable.strings` for both languages at the same time and verify the keys match up (0 missing, 0 unused).

Determine fixed-width column widths only after measuring fonts **across all languages** (don't decide by looking at Japanese alone).
In fact, English labels run longer than Japanese ones, and `sliderLabelWidth` is bottlenecked by English.

## Verification steps

1. `./build.sh` (no Xcode project. SourceKit's "Cannot find ... in scope" is a false positive from per-file independent indexing)
2. `open "build/Magic Mouse Toolkit.app"` → confirm it's running with `pgrep -x MagicMouseToolkit`
3. Take an @2x capture with `screencapture -l <windowID>` (px ÷ 2 = pt) and measure left/right/top/bottom edges and row heights in pixels
4. Cross-check localization keys (the first argument across `Sources/*.swift` vs. both `.strings` files converted with `plutil -convert json`)

---

<a id="简体中文"></a>

# Magic Mouse Toolkit 设计系统（DESIGN.md）

创建于 2026-07-02，全面修订于 2026-07-28。
**以 `Sources/DesignSystem.swift` 为准。本文解释设计意图及其测量依据。** 数值不一致时，以代码为准。不要在视图中直接写字面值，统一使用 `DS.*` 设计令牌。

最初的“阶段 1：原生界面 → 阶段 2：Liquid Glass 换肤”计划已于 2026-07-06 完成。以下描述阶段 2 完成后的实现。

## 设计理念

**“把白色 Magic Mouse 2 的表面玻璃直接变成窗口本身。”**

- 标准 `.titled` 窗口、透明标题栏、空的统一 `NSToolbar`；不自绘红黄绿按钮和标题栏。
- 整个窗口铺设 `glassEffect(.regular)`，其上放置四周内缩 8pt 的**白色面板**，这条 8pt 带构成“玻璃边缘”。
- 装饰仅用于表现玻璃的物理质感，**不用阴影、渐变或多种强调色**。
- 白色面板固定为白色，通过 `window.appearance = .aqua` 锁定浅色外观；文字采用跟随系统外观的令牌。

## 令牌约定（项目自定规则）

1. 每种用途只设一个令牌、**一套数值梯度**，不创建重复令牌。例如内容顶部内边距只用一个 `contentTop`，不按页面另设数值。
2. 间距必须遵守 `DS.Space` 的 4/8 网格，唯一例外是 `DS.Plate`。
3. 字重只用 `.regular` 和 `.semibold`，不用 `.medium`。
4. 不用阴影；不混用 continuous 和 circular 圆角样式。
5. 只用一个强调色 `DS.Color.accent`，**显式调用 `.tint` 的位置仅限 `Toggle`**。
6. **不凭目测决定布局数值**。依据 @2x 截图像素或字体度量结果，并在令牌注释中留下依据。

## 令牌定义（`Sources/DesignSystem.swift`）

### 颜色 `DS.Color`

| 令牌 | 数值 | 用途 |
|---|---|---|
| `labelPrimary` | `.primary` | 控件行标签和标题 |
| `labelSecondary` | `.secondary` | 辅助文字、单位、数值 |
| `accent` | `.controlAccentColor` | 仅用于 `Toggle`，唯一强调色 |
| `debugPass` / `debugFail` | systemGreen / systemRed | 实时显示中判断通过／失败的 ✓ / ✗ |
| `plateBase` | white 0.78 | 白色面板底层，边缘略微透光 |
| `plateCore` | white 0.82 | 白色核心，距边缘内缩 26pt，模糊半径 18 |
| `cardFill` | rgb(241,241,241) | 实时显示卡片 |

`plateBase` 与 `plateCore` 叠加后，中心约为 0.96（近白色），边缘约为 0.78，可透出下方玻璃。不使用中心锚定的 `RadialGradient`，因为大屏上会出现环形色带；改为按距边缘的距离衰减。

### 间距 `DS.Space`

`xs 4 / s 8 / m 12 / l 16 / xl 24 / xxl 32`。只用这一套梯度，不按场景创建临时值。

### 面板几何 `DS.Plate`——**不要修改**

| 令牌 | 数值 | 含义 |
|---|---|---|
| `inset` | 8 | 玻璃边宽度，即白色面板距窗口边缘的内缩量 |
| `fadeWidth` | 26 | 白色核心距面板边缘的内缩量，即渐隐带宽 |
| `fadeBlur` | 18 | 白色核心的边缘模糊 |
| `radius` | 16 | 白色面板圆角，**必须使用 `style: .continuous`** |

**同心圆角原则**：内圆角半径 = 外窗口圆角半径 − 内缩量。macOS 26 的 `.titled` 窗口使用连续超椭圆曲线，实测曲率范围约为 28pt；在 8pt 内缩下使用 16pt continuous 圆角，边和角的玻璃边宽视觉一致，实测 7.5–8.5pt。若用 circular，角部会显得过薄。

### 圆角 `DS.Radius`

仅有 `card = 10`。除面板几何外，这是应用中唯一使用的圆角半径。

### 字体 `DS.Font`（5 个令牌）

| 令牌 | 定义 | 用途 |
|---|---|---|
| `pageTitle` | 13 / semibold | “高级设置”页面标题、返回按钮图标 |
| `sectionHeader` | 11 / semibold | 分节标题、列标题 |
| `body` | 13 | 控件行标签、HUD 正文 |
| `caption` | 11 | 辅助说明、卡片正文 |
| `value` | 12 / monospaced | 滑块数值、实时显示中的测量值 |

Figma 稿中的 10pt / 7pt 在实体设备上过小，已于 2026-07-10 调整为 macOS 常用的可读字号。

### 布局 `DS.Layout`

| 令牌 | 数值 | 依据 |
|---|---|---|
| `windowSize` | 700 × 392 | contentSize；统一标题栏增加 66pt，实测总高 458 |
| `contentLeading` / `contentTrailing` | 32（`Space.xxl`） | 左右对称，按 2026-07-28 实机反馈从 40 缩至 32 |
| `mainColumnWidth` | 328 | 32 + **328** + 44 + 264 + 32 = 700 |
| `columnGap` | 44 | 左列右缘至卡片左缘 |
| `liveCardSize` | 264 × 340 | 必须完整容纳于面板，不能溢出 |
| `contentTop` | 8（`Space.s`） | 标题栏底部安全区至内容的距离，**所有页面共用** |
| `formBuiltInInset` | 30 | `Form(.grouped)` 内建内缩，**@2x 实测值** |
| `formInsetCompensation` | `contentLeading − 30` = 2 | 让高级设置和主界面的文字左右对齐 |
| `rowHeight` | 26 | 控件行固定高度，防止换行造成抖动 |
| `sliderLabelWidth` | 176 | 最长英文标签“2-finger simultaneity window”实测 175.2pt，向上取至下一个 8 网格值 |
| `valueWidth` | 64 | 最长英文数值“0.25 sec”实测 59.3pt，向上取至下一个 8 网格值 |

**高度分解**：`contentTop 8 + heading 15 + gap 12 + card 340 = 375`，再加底部留白 9 和玻璃边 8，合计 392。收紧顶部时也要测量底边，调整高度令牌使上下相近，实测顶部 8、底部 9.5pt。

**`Form(.formStyle(.grouped))` 左边界**：macOS 26，宽 700pt，@2x 实测于 2026-07-28。

| 元素 | 左边界 |
|---|---|
| 分节标题文字 | 30pt |
| 分组卡片内各行的标签、辅助文字 | 30pt |
| **分组卡片背景矩形本身** | **20pt**，比标题／行向外多出 10pt |

标题和行共用的 30pt 是唯一可统一的基准。**只有卡片背景始终向外溢出 10pt，保留 Form 结构时无法消除这一差异**；若要消除，需要改成自定义卡片的 `VStack`。给自定义页头（返回按钮与页面标题）设置 `contentLeading`，给 Form 设置 `formInsetCompensation`，即可使所有文字左侧统一在 32pt。

## 组件约定

- **开关**：`Toggle` + `.toggleStyle(.switch)` + `.controlSize(.small)` + `.tint(DS.Color.accent)`。
- **按钮**：统一只用 `.bordered`，仅以 `controlSize` 表达层级；主要按钮用 `.regular`，次要／下级设置用 `.small`，不用 `.borderedProminent`。
- **滑块行**：统一复用 `SliderRow`，使用 `lineLimit(1)` 与 `frame(height: rowHeight)` 固定布局。**数值列只放“数字 + 单位”**；“距前端 25%”等限定语放标签列。固定宽度数值列出现长短不一的文字，会导致单行换行并破坏跨分节的行节奏。
- **分节**：高级设置用 `Form` + `Section(header:)` + `.formStyle(.grouped)` + `.scrollContentBackground(.hidden)`；主界面用平铺 `VStack`。
- **实时显示**：数值始终用等宽的 `DS.Font.value`；判断用 ✓/✗ 和 `debugPass` / `debugFail`。
- 不自绘控件。

## 禁止事项

- 直接在视图中写字面值，例如 `.padding(13)`、`Color.gray`、`.font(.system(size: 12))`。
- 第三方字体或颜色资源。
- 阴影、多种强调色、`.borderedProminent`。
- 在固定宽度双列 `HStack` 末尾保留 `Spacer(minLength: 0)`。`spacing` 会作用于每一对相邻元素，导致列间距计算两次；溢出的 `HStack` 居中后会造成左右不对称。应通过外层 `padding` 保持边距对称。
- 凭目测决定布局。实现后应以 @2x 截图数值检查真实左右、上下坐标。

## 本地化与布局

`NSLocalizedString` 的第一个参数**直接使用日文原句作为键**，ja/en 的 `.strings` 共用键；本文记录时为 117 项。修改措辞会改变键，因此布局调整涉及显示文字时，应同步更新 `Resources/{ja,en}.lproj/Localizable.strings`，核对缺失与未使用键均为 0。

固定列宽应在测量**所有语言**的字体后决定，不能只看日文。英文标签实际上更长，`sliderLabelWidth` 的瓶颈来自英文。

## 验证步骤

1. 运行 `./build.sh`。无 Xcode 项目；SourceKit 独立逐文件索引产生的“Cannot find ... in scope”为误报。
2. 用 `open "build/Magic Mouse Toolkit.app"` 启动，再用 `pgrep -x MagicMouseToolkit` 确认进程运行。
3. 用 `screencapture -l <windowID>` 截取 @2x 图像，以 px ÷ 2 = pt 测量左右、上下边缘和行高。
4. 核对本地化键：`Sources/*.swift` 中第一个参数，与通过 `plutil -convert json` 转换的两份 `.strings` 对照。
