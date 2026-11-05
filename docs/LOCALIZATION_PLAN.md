[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Internationalization (Japanese/English localization) implementation procedure

Created: 2026-07-27. This document was written after verifying it against the actual current code (`main` branch, `ce0998e`) (checked against real source).
The goal is that the localization work can be completed by reading only this document. Rewriting the README's announcement text is out of scope (a separate task).

## 0. Current state (checked against real source)

- **Build method**: no Xcode project. `build.sh` calls `swiftc` directly to compile arm64/x86_64 separately and combines them with `lipo`.
  This means `.lproj` files are not automatically compiled or bundled. **Resources must be bundled manually.**
- **Localization infrastructure**: `NSLocalizedString` / `.strings` / `.xcstrings` currently do not exist at all. `Info.plist` also has neither
  `CFBundleDevelopmentRegion` nor `CFBundleLocalizations` set.
- **Distribution of Japanese strings** (across all 19 files in `Sources/`, 552 lines contain Japanese):
  - Of these, **382 lines are comments only** (out of scope for translation; left in Japanese as developer notes)
  - The remaining **roughly 170 lines are in-code strings** (UI display or log output), which are the candidates for conversion

## 1. Scope (targets and non-targets for this conversion)

### In scope (to be wrapped with NSLocalizedString)

Only strings the user actually sees on screen. Locations confirmed by inspecting the real source:

| File | Content | Approx. count |
|---|---|---|
| `Sources/AppDelegate.swift` | Menu-bar item titles (lines 164, 169, 174, 179, 186, 193, 197, 203, 209) and dynamic status strings (lines 262-263, 268-269, 276-277) | ~18 locations |
| `Sources/SettingsView.swift` | `Text` / `Button` / `Toggle` / `Picker` / `caption` / `SliderRow` labels throughout the settings screen | ~90 locations |
| `Sources/TrackpadModeHUD.swift` | line 69, `"トラックパッドモード beta"` | 1 location |
| `Sources/TapRecognizer.swift` | `TapFailureReason`'s 10 cases (lines 16-26) and the label/actual/threshold strings in `record()` calls | ~25 locations |
| `Sources/TouchGestureManager.swift` | 3 locations of `DebugFeed.shared.pushEvent(...)` (lines 357, 379, 385) | 3 locations |

Since these also appear in the debug live display the user sees in screenshots (the "Recent Events" and "Judgment Breakdown" panes),
the `TapFailureReason` and `pushEvent` text is easy to overlook but is included in scope.

### Out of scope (not touched this time)

- Japanese messages in `MMTLog.log(...)` calls (developer-facing diagnostic logs that only go to `~/Library/Logs/MagicMouseToolkit.log` and never appear in the UI).
  Will be broken out as a separate task if needed in the future.
- Comments (382 lines).
- Documentation text such as `README.md` (out of scope this time per the user's instruction; to be handled as a separate task once the code work is done).

## 2. Points requiring caution (enum rawValues doubling as display strings)

Real-source inspection found two spots where an enum's `rawValue` is used directly as the on-screen display string.
**Since these are not persisted (no `Codable`/`UserDefaults`), rewriting them is safe in itself**, but
translating `rawValue` directly into English would break the display logic wherever existing code references `.rawValue` (effectively yielding empty strings),
so we separate "identifier-purpose rawValue" from "display-purpose string."

- `Sources/SettingsView.swift` lines 68-71, `BoundActionKind` (`case macro = "マクロ"` etc.)
  → Change `rawValue` to an ASCII identifier and add `var localizedTitle: String`, with the UI referencing that instead.
  It's used only by `ForEach(BoundActionKind.allCases)` and `Identifiable`'s `id` (line 212), so no other logic is affected (confirmed).
- `Sources/TapRecognizer.swift` lines 16-26, `TapFailureReason`
  → Likewise, turn `rawValue` into an identifier and add `var localizedDescription: String`.
  The only reference sites are the `.rawValue` calls at `TouchGestureManager.swift` lines 277, 278, 330, 337 (confirmed),
  which should be replaced with `.localizedDescription`.

## 3. Infrastructure setup

1. **Add to Info.plist**:
   ```xml
   <key>CFBundleDevelopmentRegion</key>
   <string>ja</string>
   <key>CFBundleLocalizations</key>
   <array>
       <string>ja</string>
       <string>en</string>
   </array>
   ```
2. **New resource directories**: `Resources/ja.lproj/Localizable.strings`, `Resources/en.lproj/Localizable.strings`
   (create as empty files; the ja version will be generated via genstrings in §4)
3. **Modify `build.sh`**: add copying of Resources to the `.app` bundle-generation section
   (currently the part that creates `Contents/MacOS` and does `cp Info.plist`):
   ```sh
   mkdir -p "build/$APP/Contents/Resources"
   cp -R Resources/ja.lproj Resources/en.lproj "build/$APP/Contents/Resources/"
   ```
4. Since `build.yml`'s "Validate scripts and plist" step only runs `plutil -lint Info.plist`,
   it should still pass after adding the keys (no additional CI changes expected to be needed).

## 4. Code conversion / translation flow

1. Wrap the in-scope locations from §1 with `NSLocalizedString("original Japanese text", comment: "description of where it appears on screen")`.
   Use the Japanese original text itself as the key (following Apple's standard `genstrings` workflow; do not mint new keys).
2. For places using `String(format:)` (e.g. `SettingsView.swift` lines 187, 341, 349, etc., and `TapRecognizer.swift` lines 64-134),
   wrap the format string itself with `NSLocalizedString`. Where word order may differ in English, use positional specifiers like `%1$@`.
3. For the two spots from §2, once `rawValue` has been turned into an identifier, call `NSLocalizedString` inside `localizedTitle` / `localizedDescription`.
4. Once all locations have been wrapped, extract:
   ```sh
   genstrings -o Resources/ja.lproj Sources/*.swift
   ```
   The generated `Resources/ja.lproj/Localizable.strings` is UTF-16, so verify the encoding before committing,
   e.g. via `iconv -f UTF-16 -t UTF-8`.
5. Create `Resources/en.lproj/Localizable.strings` and add the English translation for each key from `ja.lproj` (manual translation).

## 5. Build and verification steps

1. Build with `./build.sh`.
2. Verify the English UI: launch with `open "build/Magic Mouse Toolkit.app" --args -AppleLanguages "(en)"` and visually check
   the three areas: the menu bar, the settings screen, and the debug live display (including the tap-judgment breakdown pane).
3. Also verify no strings are missing in Japanese (the default) (immediately after `genstrings`, ja should equal the original text, so there should be no diff).
4. `codesign --verify --deep --strict` is already verified by an existing step in `build.yml`, so no additional action is needed.

## 6. Suggested approach

Since converting all ~170 locations at once would make review difficult, proceed incrementally file by file:

1. Separate out identifiers for `TapFailureReason` / `BoundActionKind` (§2) — do this first since other files depend on it
2. `AppDelegate.swift` (menu)
3. `SettingsView.swift` (settings screen; since the count is high, split into first/second half if needed)
4. `TrackpadModeHUD.swift` / `TouchGestureManager.swift` (the rest)
5. Infrastructure setup from §3, run genstrings from §4, translate
6. Verification (§5)

Branch off `feature/localization` from the public repository's `main` (this is a separate lineage from the private development repository
`~/Documents/Claude/MagicControl`; since `main` is currently the source of truth in the public repository, branch directly from there).

---

<a id="简体中文"></a>

# 国际化（日文／英文本地化）实施流程

创建于 2026-07-27。本文已对照当时实际代码 `main` 分支的 `ce0998e` 提交核实。
目标是仅凭本文即可完成本地化；README 公告文案的改写不在当次工作范围内，另作任务处理。

## 0. 当时状态（已对照源代码）

- **构建方式**：无 Xcode 项目；`build.sh` 直接调用 `swiftc` 分别编译 arm64/x86_64，再用 `lipo` 合并。因此 `.lproj` 不会自动编译或打包，**必须手动复制资源**。
- **本地化基础设施**：当时尚无 `NSLocalizedString` / `.strings` / `.xcstrings`；`Info.plist` 中也未设置 `CFBundleDevelopmentRegion` 或 `CFBundleLocalizations`。
- **日文分布**：`Sources/` 共 19 个文件，552 行包含日文，其中 **382 行仅为注释**，不翻译，保留为开发笔记；其余**约 170 行为代码内字符串**，包括界面或日志输出，是转换候选。

## 1. 范围

### 范围内：用 NSLocalizedString 包装

仅处理实际显示在用户屏幕上的字符串，已核对位置如下：

| 文件 | 内容 | 大致数量 |
|---|---|---|
| `Sources/AppDelegate.swift` | 菜单栏条目，第 164、169、174、179、186、193、197、203、209 行；动态状态字符串，第 262–263、268–269、276–277 行 | 约 18 处 |
| `Sources/SettingsView.swift` | 整个设置页的 `Text` / `Button` / `Toggle` / `Picker` / `caption` / `SliderRow` 标签 | 约 90 处 |
| `Sources/TrackpadModeHUD.swift` | 第 69 行，`"トラックパッドモード beta"` | 1 处 |
| `Sources/TapRecognizer.swift` | `TapFailureReason` 的 10 个 case，第 16–26 行；`record()` 的标签、实际值和阈值字符串 | 约 25 处 |
| `Sources/TouchGestureManager.swift` | 第 357、379、385 行的 `DebugFeed.shared.pushEvent(...)` | 3 处 |

`TapFailureReason` 和 `pushEvent` 的文字也会出现在用户看到的实时调试界面“最近事件”“判断明细”面板，容易遗漏，但属于范围内。

### 范围外：当次不修改

- `MMTLog.log(...)` 中的日文消息：仅写入 `~/Library/Logs/MagicMouseToolkit.log` 的开发诊断日志，不显示于界面；如需处理，另作任务。
- 382 行注释。
- `README.md` 等文档文字：按当时用户指令排除，代码工作完成后另行处理。

## 2. 注意：兼作显示文字的 enum rawValue

源代码中有两处直接把 enum 的 `rawValue` 用于界面显示。它们**没有通过 Codable／UserDefaults 持久化，因此改写本身安全**；但若只把 rawValue 改为英文而不处理引用，会破坏现有显示逻辑，实际可能变为空字符串，因此需区分“标识符 rawValue”和“显示字符串”。

- `Sources/SettingsView.swift` 第 68–71 行的 `BoundActionKind`，如 `case macro = "マクロ"`：rawValue 改为 ASCII 标识符，新增 `var localizedTitle: String`，界面改用该属性。已确认只被 `ForEach(BoundActionKind.allCases)` 和第 212 行 `Identifiable.id` 使用，不影响其他逻辑。
- `Sources/TapRecognizer.swift` 第 16–26 行的 `TapFailureReason`：同样把 rawValue 改为标识符，新增 `var localizedDescription: String`。已确认引用仅位于 `TouchGestureManager.swift` 第 277、278、330、337 行，将 `.rawValue` 改为 `.localizedDescription`。

## 3. 基础设施

1. 在 `Info.plist` 增加：

   ```xml
   <key>CFBundleDevelopmentRegion</key>
   <string>ja</string>
   <key>CFBundleLocalizations</key>
   <array>
       <string>ja</string>
       <string>en</string>
   </array>
   ```

2. 新建 `Resources/ja.lproj/Localizable.strings` 和 `Resources/en.lproj/Localizable.strings`，初始为空；日文版本在第 4 节通过 genstrings 生成。
3. 在 `build.sh` 创建 `.app` 包的部分，即创建 `Contents/MacOS`、复制 `Info.plist` 附近，增加：

   ```sh
   mkdir -p "build/$APP/Contents/Resources"
   cp -R Resources/ja.lproj Resources/en.lproj "build/$APP/Contents/Resources/"
   ```

4. `build.yml` 的“Validate scripts and plist”步骤只运行 `plutil -lint Info.plist`，新增键后应仍能通过，预计无需其他 CI 调整。

## 4. 代码转换与翻译流程

1. 第 1 节范围内位置使用 `NSLocalizedString("original Japanese text", comment: "description of where it appears on screen")` 包装；按 Apple 标准 `genstrings` 工作流，直接以日文原文作键，不另造键。
2. 使用 `String(format:)` 的位置，例如 `SettingsView.swift` 第 187、341、349 行及 `TapRecognizer.swift` 第 64–134 行，要包装格式字符串本身。不同语言语序可能变化时使用 `%1$@` 等位置参数。
3. 第 2 节两处 rawValue 改为标识符后，在 `localizedTitle` / `localizedDescription` 内调用 `NSLocalizedString`。
4. 完成包装后提取：

   ```sh
   genstrings -o Resources/ja.lproj Sources/*.swift
   ```

   生成的 `Resources/ja.lproj/Localizable.strings` 为 UTF-16，提交前确认编码，例如使用 `iconv -f UTF-16 -t UTF-8`。
5. 创建英文 `Resources/en.lproj/Localizable.strings`，逐键手工翻译日文版本。

## 5. 构建与验证

1. 运行 `./build.sh`。
2. 用 `open "build/Magic Mouse Toolkit.app" --args -AppleLanguages "(en)"` 启动英文界面，目视检查菜单栏、设置页、实时调试显示，包括轻点判断明细面板。
3. 同时确认日文默认界面没有缺失字符串。刚运行 genstrings 时，日文应等于原文，不产生显示差异。
4. `build.yml` 已有步骤检查 `codesign --verify --deep --strict`，无需另加操作。

## 6. 建议顺序

一次转换约 170 处难以审阅，建议逐文件推进：

1. 先拆分 `TapFailureReason` / `BoundActionKind` 标识符，第 2 节；其他文件依赖它们。
2. `AppDelegate.swift` 菜单。
3. `SettingsView.swift` 设置页，数量多，可分前后两部分。
4. `TrackpadModeHUD.swift` / `TouchGestureManager.swift` 其余位置。
5. 完成第 3 节基础设施，运行第 4 节 genstrings 并翻译。
6. 按第 5 节验证。

从公开仓库的 `main` 创建 `feature/localization` 分支。当时该仓库与私有开发仓库 `~/Documents/Claude/MagicControl` 为不同谱系；公开仓库以 `main` 为准，应直接从那里分支。
