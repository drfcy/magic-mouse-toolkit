[English](#english) | [简体中文](#简体中文)

<a id="english"></a>

# Magic Mouse Toolkit Implementation Spec (Code-Aligned Edition)

Created: 2026-07-02. The goal is that implementation can be completed by reading only this document (implementer assumed to be Sonnet 5).
For background and history, see SPEC.md / ARCHITECTURE.md; for design tokens, see DESIGN.md.

## 0. Phases

- **Phase 1 (prototype, scope of this document)**: All features + a simple UI (a native-looking Form using DESIGN.md's tokens). Through functional verification and calibration
- **Phase 2**: Reskin to the Liquid Glass design (structured so this only requires swapping token values in DesignSystem.swift and introducing GlassWindow)

## 1. Countermeasures against false tap/scroll triggers — 4-layer defense (the core of this spec)

Estimation from touch coordinates alone (distance/velocity thresholds) inherently leaves boundary misjudgments. So we **use the OS's own scroll determination (the `.scrollWheel` event) as the ground-truth signal**. Since a CGEventTap is always attached for middle-click conversion anyway, adding `.scrollWheel` to the set of monitored events costs almost nothing extra.

A tap is only recognized if it passes **every one of the following layers**:

### Layer 1: Contact geometry (touch-coordinate based, the conventional approach)
- Contact duration ≤ `tapMaxDuration`
- Straight-line distance (start point → end point) ≤ `tapMaxStraightDistance`
- Cumulative path length (sum of per-frame movement) ≤ `tapMaxPathLength`
- Observed peak instantaneous speed (max norm of `MTTouch.normalized.velocity`) ≤ `tapMaxVelocity`
- Contact frame count ≥ `tapMinFrames` (excludes momentary grazes/noise frames. Since Magic Mouse touch frames run at roughly 90Hz, this requires contact of 3 frames ≈ 33ms or more)

### Layer 2: Scroll veto (uses the OS's scroll determination)
- If a `.scrollWheel` event was observed between touch-start and the moment of tap judgment, or within `scrollVetoWindow` (default 0.25s) looking back from the judgment moment, the tap **does not register**
- Recording of scrollWheel is passive (events pass through unmodified). `ScrollMonitor` only retains the last-observed timestamp

### Layer 3: Momentum-scroll veto
- A touch that began while `.scrollWheel`'s `kCGScrollWheelEventMomentumPhase` was began/continued (i.e., during momentum scrolling) has **its entire contact excluded from tap candidacy** (the `beganDuringMomentum` flag is set, guaranteeing non-registration on release)
- Reason: on Magic Mouse, "stopping momentum scroll with a finger" happens routinely in daily use, and this is the single most common pattern behind false clicks

### Layer 4: Physical-button veto
- While a physical button is held down (between leftMouseDown and Up), and within `buttonVetoWindow` (default 0.1s) after buttonUp, taps do not register
- Reason: a finger is also detected as a touch during a physical click, so this prevents a double click formed from "physical click + synthesized tap"

### Known limitations (to be documented in the README)
- If you tap the Magic Mouse while another device such as a trackpad is scrolling, Layer 2 will falsely veto (one click gets ignored). This is a rare two-handed-operation case and the error is fail-safe, so it's accepted
- Since Layer 2 depends on a scroll event actually occurring, the very small movements right before a scroll starts are handled by Layer 1 instead (division of responsibility)

## 2. Project structure

```
MagicMouseToolkit/
├── build.sh
├── Info.plist
├── MagicMouseToolkit.entitlements    (unused. Ad-hoc distribution, no App Sandbox)
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MultitouchBridge.h       (also consolidates the HID system SPI declarations, due to the single-bridging-header constraint)
│   ├── MultitouchDevice.swift
│   ├── TouchGestureManager.swift
│   ├── TapRecognizer.swift
│   ├── EventInterceptor.swift
│   ├── SynthesizedClick.swift
│   ├── ActionKind.swift         (Codable model for tap assignments; includes RecordedKeyEvent)
│   ├── ActionExecutor.swift     (executes ActionKind; includes reentrancy guard logic for macro playback)
│   ├── MacroRecorder.swift      (three-finger-tap macro recording, listen-only CGEventTap)
│   ├── PointerSpeedManager.swift(tracking-speed boost, IOHIDEventSystemClient SPI)
│   ├── Settings.swift
│   ├── DesignSystem.swift       (implementation of DESIGN.md's tokens)
│   └── SettingsView.swift
└── docs (SPEC.md and other existing docs)
```

## 3. Build and signing

### build.sh
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Magic Mouse Toolkit.app"
BIN="MagicMouseToolkit"
SIGN_ID="${SIGN_ID:-}"              # ad-hoc signing if unspecified

SWIFT_FILES=(Sources/*.swift)
FLAGS=(-import-objc-header Sources/MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -O)

mkdir -p build
# Phase 2's Liquid Glass (glassEffect) is a macOS 26+ API, so the deployment target is raised
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target arm64-apple-macos26.0  -o build/$BIN-arm64
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target x86_64-apple-macos26.0 -o build/$BIN-x86_64
lipo -create build/$BIN-arm64 build/$BIN-x86_64 -output build/$BIN

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp Info.plist "build/$APP/Contents/"
cp build/$BIN "build/$APP/Contents/MacOS/"
codesign --force --sign "$SIGN_ID" "build/$APP"
echo "Built: build/$APP"
```
- Export the environment variable `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"` at the top of build.sh (per CLAUDE.md defaults)
- Always verify behavior via `open -a "build/Magic Mouse Toolkit.app"` (the launchd parent). Running the binary directly from the terminal bypasses TCC

### Info.plist (required keys)
| Key | Value |
|---|---|
| CFBundleIdentifier | com.mori0818.magicmousetoolkit |
| CFBundleName / CFBundleDisplayName | Magic Mouse Toolkit |
| CFBundleExecutable | MagicMouseToolkit |
| CFBundleVersion / ShortVersionString | 1.0 |
| LSUIElement | true |
| NSHighResolutionCapable | true |

## 4. MultitouchBridge.h (full contents)

```c
#ifndef MultitouchBridge_h
#define MultitouchBridge_h
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
  int32_t frame;
  double timestamp;
  int32_t identifier;
  int32_t state;          // 4 = Touching
  int32_t fingerId, handId;
  MTVector normalized;    // both position/velocity normalized 0.0-1.0 (larger Y = further forward)
  float size;
  int32_t zero1;
  float angle, majorAxis, minorAxis;
  MTVector absolute;
  int32_t zero2, zero3;
  float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int32_t *familyId);

#endif
```
- Touch state constant: only `4 (Touching)` is treated as "in contact." Touches in any other state are not counted toward the per-frame finger count
- The `MTTouch` layout is identical to the one verified on real hardware in the MouseToucher fork. If `position` returns anomalous values (outside the 0-1 range), suspect a layout mismatch and first check the validity of `timestamp` and `identifier` in the logs

## 5. Device management — MultitouchDevice.swift

```swift
final class MultitouchDeviceManager {
    static let shared = MultitouchDeviceManager()
    private var activeDevices: [MTDeviceRef] = []
    func start()    // enumerate → filter → register
    func stop()     // unregister all + MTDeviceStop
    func restart()  // stop() → start() after 0.5s (handles device reconnection)
}
```

- **Filter condition (Magic Mouse only)**: `MTDeviceIsBuiltIn(dev) == false` and `MTDeviceGetFamilyID` succeeds with `familyId == 112 || familyId == 113`
  - 112/113 = the Magic Mouse family. **On first launch, always log the actual familyId** (so that a mismatch on Magic Mouse 2 / USB-C models can be spotted immediately). If the filter yields zero devices, surface "No device passed the familyId filter. Detected familyIds: [...]" in the menu bar status display
  - Fallback setting `deviceFilterStrict` (default true). Setting it to false falls back to the old behavior of using only `!MTDeviceIsBuiltIn` (an escape hatch for units whose familyId doesn't match expectations)
- Callbacks are C function pointers and cannot capture context; forward from a global function to `TouchGestureManager.shared`
- **Reconnection handling**: `NSWorkspace.shared.notificationCenter`'s `didWakeNotification` combined with `IOServiceAddMatchingNotification` (matching on AppleMultitouchDevice) would be complex, so **the prototype simplifies this**: subscribe to didWake notifications, and provide a "Redetect Device" menu-bar item that calls `restart()`. Automatic BT-reconnection detection is deferred to Phase 2

## 6. Settings — Settings.swift

Backed by `UserDefaults.standard`. Every property posts `NotificationCenter.default.post(name: .settingsChanged)` from its `didSet`. Readers (TouchGestureManager / EventInterceptor) copy all values into a local `SettingsSnapshot` struct upon receiving the notification, and hold onto that (UserDefaults is never read inside a callback — for speed and safety).

| Property | UserDefaults key | Type | Default | UI range |
|---|---|---|---|---|
| enabled | mmt.enabled | Bool | true | — |
| oneFingerTapEnabled | mmt.tap1.enabled | Bool | true | — |
| twoFingerTapEnabled | mmt.tap2.enabled | Bool | true | — |
| middleClickEnabled | mmt.middle.enabled | Bool | true | — |
| rightZoneMinX | mmt.zone.rightMinX | Double | 0.6 | 0–1 |
| zoneMinX / zoneMaxX | mmt.zone.minX / maxX | Double | 0.0 / 1.0 | 0–1 |
| zoneMinY / zoneMaxY | mmt.zone.minY / maxY | Double | 0.0 / 1.0 | 0–1 |
| tapMaxDuration | mmt.tap.maxDuration | Double | 0.16 | 0.05–0.5 s |
| tapMaxStraightDistance | mmt.tap.maxStraight | Double | 0.09 | 0.01–0.3 |
| tapMaxPathLength | mmt.tap.maxPath | Double | 0.07 | 0.01–0.3 |
| tapMaxVelocity | mmt.tap.maxVelocity | Double | 1.5 | 0.2–8.0 /s |
| tapMinFrames | mmt.tap.minFrames | Int | 3 | 1–10 |
| scrollVetoWindow | mmt.veto.scroll | Double | 0.25 | 0–1.0 s |
| buttonVetoWindow | mmt.veto.button | Double | 0.10 | 0–0.5 s |
| twoFingerSyncWindow | mmt.tap2.syncWindow | Double | 0.06 | 0.02–0.2 s |
| deviceFilterStrict | mmt.device.strict | Bool | true | — |

- The default of 1.5 for `tapMaxVelocity` is provisional. It's the target for calibration via the debug display (§9)
- Register initial values at launch via `UserDefaults.standard.register(defaults:)`

## 7. Tap recognition — TouchGestureManager.swift + TapRecognizer.swift

### Shared state (read by EventInterceptor)
```swift
struct TouchSharedState {          // protected by os_unfair_lock
    var fingerCount: Int = 0       // number of fingers in state==4 for the current frame
    var lastFrameAt: CFTimeInterval = 0   // time the last touch frame was received (CACurrentMediaTime)
}
```

### Touch frame processing (MT callback, background thread)
1. Reference `SettingsSnapshot`. If `enabled == false`, only update fingerCount and return
2. Update shared state (fingerCount, lastFrameAt)
3. Map each touch by its `identifier` key into `activeTouches: [Int32: TouchTrack]` and update

```swift
struct TouchTrack {
    let id: Int32
    let startTime: Double          // timestamp of the MT frame
    let startPos: MTPoint
    var lastPos: MTPoint
    var pathLength: Float = 0      // Σ|Δpos|
    var maxVelocity: Float = 0     // max ‖normalized.velocity‖
    var frames: Int = 1
    var beganDuringMomentum: Bool  // whether ScrollMonitor.momentumActive was true at start (Layer 3)
    var vetoed: Bool = false       // set true once a Layer-1 threshold violation is confirmed mid-contact (no further updates needed)
}
```

4. For touches present in the frame: update the track. `pathLength += hypot(Δx, Δy)`, `maxVelocity = max(...)`. If a threshold is exceeded, set `vetoed = true`
5. **An identifier present in the previous frame but absent in the current frame = a release**. Judgment happens on release (see next section)
6. If any frame is observed with 3 or more simultaneous fingers, set `vetoed = true` on every track at that point

### Tap judgment on release (TapRecognizer)
```
Registration condition (all AND):
  !track.vetoed
  !track.beganDuringMomentum                          // Layer 3
  duration = releaseTime - startTime ≤ tapMaxDuration
  |endPos - startPos| ≤ tapMaxStraightDistance
  pathLength ≤ tapMaxPathLength
  maxVelocity ≤ tapMaxVelocity
  frames ≥ tapMinFrames
  startPos is within the zone [zoneMinX,zoneMaxX]×[zoneMinY,zoneMaxY]
  ScrollMonitor.lastScrollAt < startTime - scrollVetoWindow   // Layer 2 (before start)
  ScrollMonitor.lastScrollAt < now → no scroll occurred during contact   // Layer 2 (during contact)
  EventInterceptor.buttonDown == false                 // Layer 4
  now - EventInterceptor.lastButtonUpAt > buttonVetoWindow
```
(Layer 2 may be implemented with the simplification: "does not register if `lastScrollAt` was ever updated on or after `startTime - scrollVetoWindow`")

- **One-finger tap**: on registration, synthesize a right click if `endPos.x > rightZoneMinX`, otherwise a left click
- **Two-finger tap**: synthesize a single left click when two tracks satisfy (a) start-time difference ≤ `twoFingerSyncWindow`, (b) both have been released and both meet the registration condition, and (c) release-time difference ≤ `twoFingerSyncWindow * 2`. **Once a two-finger tap registers, do not fire a one-finger tap for the same two tracks** (hold off one-finger judgment for up to `twoFingerSyncWindow*2` until the second release. Implementation: don't fire a released track immediately — queue it in `pendingRelease`, and use delayed judgment where (i) its partner appears → fire the two-finger tap, or (ii) it times out → fire the one-finger tap. Reuse a single `DispatchSourceTimer` for this)
  - Note: this hold-off applies only when two-finger tap is enabled. If `twoFingerTapEnabled == false`, fire the one-finger tap immediately (zero delay)
- Click synthesis is done via `SynthesizedClick.post(button:at:)` (§8). The firing position is the **current cursor position** (the location from `CGEvent(source: nil)`)

## 8. Event tap — EventInterceptor.swift + SynthesizedClick.swift

### One CGEventTap serving three roles
```swift
CGEvent.tapCreate(
  tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: (1 << CGEventType.leftMouseDown.rawValue)
                  | (1 << CGEventType.leftMouseUp.rawValue)
                  | (1 << CGEventType.scrollWheel.rawValue),
  callback: interceptorCallback, userInfo: nil)
```
Callback discipline: **no allocation, no logging, no reading UserDefaults**. Only reading SettingsSnapshot and shared state, plus rewriting integer fields, is allowed.

Branching logic (pseudocode):
```
case .tapDisabledByTimeout, .tapDisabledByUserInput:
    CGEventTapEnable(tap, true); return event            // self-recovery
case .scrollWheel:                                        // acts as ScrollMonitor
    lastScrollAt = now
    phase = event[.scrollWheelEventMomentumPhase]
    momentumActive = (phase == 1 || phase == 2)           // began/continued
    return event                                          // pass through unmodified
case .leftMouseDown:
    if event[.eventSourceUserData] == kMCEventSignature: return event   // pass through our own synthesized events
    buttonDown = true
    if middleClickEnabled
       && shared.fingerCount == 2
       && (now - shared.lastFrameAt) < 0.08 {             // device-correlation guard
        convertingToMiddle = true
        event.type = .otherMouseDown
        event[.mouseEventButtonNumber] = 2                // center
    }
    return event
case .leftMouseUp:
    if event[.eventSourceUserData] == kMCEventSignature: return event
    buttonDown = false; lastButtonUpAt = now
    if convertingToMiddle {                               // if down decided the conversion, up must convert too
        convertingToMiddle = false
        event.type = .otherMouseUp
        event[.mouseEventButtonNumber] = 2
    }
    return event
```
- When `enabled == false` or `middleClickEnabled == false`: since there's no need to keep recording scrollWheel (taps are disabled, or the veto target is disabled), **disable the tap entirely (`CGEventTapEnable(false)`) when master enable is OFF**. When only middleClick is OFF but tapping is enabled, keep the tap alive (needed for Layer 2), but pass Down/Up through unmodified
- If tap creation fails (no permission) → route to AppDelegate's permission flow (§10)

### SynthesizedClick.swift
```swift
enum SynthesizedClick {
    static let signature: Int64 = 0x4D43_4C4B          // "MCLK"
    static func post(button: CGMouseButton) {
        let loc = CGEvent(source: nil)!.location
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = signature                       // self-identification (EventInterceptor passes it through)
        let (down, up): (CGEventType, CGEventType) = ...  // left/right/other depending on button
        CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: up,   mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
    }
}
```
- No delay is inserted between down and up (verified fine in MouseToucher testing)
- Note: `CGEventSource.userData` is readable on the event side via the `.eventSourceUserData` field

## 9. UI — SettingsView.swift (prototype version)

Build using only DESIGN.md's tokens (`DesignSystem.swift`). Do not write literal font sizes, colors, or spacing directly into views.

Structure (`Form` + `Section`, window 440×620, not resizable):
1. **General**: master enable toggle
2. **Gestures**: toggles for one-finger tap / two-finger tap / middle click + a slider for the right-click zone's starting X
3. **Active range**: 4 sliders for X min/max and Y min/max (shown as %)
4. **Sensitivity**: 5 sliders for tapMaxDuration / MaxStraight / MaxPath / MaxVelocity / MinFrames (current value shown right-aligned in a monospaced font)
5. **False-trigger countermeasures**: scrollVetoWindow / buttonVetoWindow / twoFingerSyncWindow
6. **Debug** (DisclosureGroup, updates only while open):
   - Current finger count and latest touch coordinates (x, y)
   - **Breakdown of the judgment for the most recent tap attempt**: side-by-side measured values and thresholds for each condition, color-coded to show which layer/condition it failed at (e.g., `path 0.11 > 0.07 ✗`). This is the primary tool for calibrating the velocity threshold
   - Recent events: the last 10 entries of history such as "Tap registered (left)," "Scroll veto," "Momentum veto," etc.
   - Debug data handoff: TouchGestureManager pushes to `DebugFeed.shared` (an ObservableObject, a 10-entry ring buffer) **only while the DisclosureGroup is open** (toggle the `DebugFeed.isActive` flag in the view's onAppear/onDisappear. Overhead while closed is a single flag check)
7. **Reset**: a "Restore sensitivity to defaults" button

Menu bar (NSMenu, AppKit):
```
✓ Enabled                  (toggle, master enable)
──────────
Open Settings…
Redetect Device            (MultitouchDeviceManager.restart)
──────────
About Magic Mouse Toolkit
Quit ⌘Q
```
Icon: SF Symbols `computermouse.fill` (template image). The settings window is created lazily and released on close (`NSWindow.isReleasedWhenClosed` doesn't play well with SwiftUI hosting, so set it to false and release by assigning the reference to nil).

## 10. AppDelegate — launch sequence

1. `UserDefaults.register(defaults:)`
2. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — if not yet authorized, wait for authorization by polling every 2 seconds (**discard the timer once authorized**; this is the only timer)
3. Once authorized: `MultitouchDeviceManager.shared.start()` → `EventInterceptor.shared.start()`
4. Set up the menu bar icon
5. Subscribe to `didWakeNotification` → `MultitouchDeviceManager.restart()`

## 11. Threading and synchronization

| Data | Writer | Reader | Protection |
|---|---|---|---|
| TouchSharedState (fingerCount, lastFrameAt) | MT callback thread | Event tap (main RunLoop) | os_unfair_lock (nanosecond-scale hold time) |
| lastScrollAt / momentumActive / buttonDown / lastButtonUpAt / convertingToMiddle | Event tap | MT callback thread | same as above (may share the same lock) |
| SettingsSnapshot | Main (swapped in on notification receipt) | Both callbacks | whole-struct swap + lock |
| DebugFeed | MT callback → dispatched to main | SwiftUI | emission itself is suppressed via the isActive flag |

## 12. Test checklist (real hardware)

1. Core behavior before glass/window concerns: one-finger tap = left click, right click in the right zone, two-finger tap = left click, two-finger physical click = middle click (verify via e.g. closing a tab in Finder)
2. **False-trigger scenarios** (no click should occur in any of these): slow scroll start / quick flick / back-and-forth scroll / stopping momentum scroll with a finger / tapping while physically clicking / operating a trackpad (should not respond at all)
3. Clicks/scrolling from other mice or trackpads must be completely unaffected
4. Settings changes take effect immediately (no rebuild or restart)
5. Behavior after waking from sleep; behavior of "Redetect Device"
6. Rebuild → re-sign → permissions must not be revoked
7. Idle CPU in the single digits % and memory ≤15MB in Activity Monitor
8. CGEventTap self-recovery: must not stop functioning under high load (verify over extended operation)

## 13. Handoff points for Phase 2

- Visual changes are confined to changing token values in `DesignSystem.swift` plus adding `GlassWindow.swift` (a borderless NSWindow subclass). SettingsView's layout structure is reused as-is
- Liquid Glass verification: validate `.glassEffect()` standalone in a borderless transparent window before integrating

## 14. Three-finger tap = macro recorder / tracking-speed boost (implemented 2026-07-10)

This section records the key points of the already-implemented macro recorder and tracking-speed boost.

### Macro recorder (three-finger tap)
- Added `ActionKind.macro([RecordedKeyEvent])`. `RecordedKeyEvent` is a Codable holding `keyCode/flags/isDown/isFlagsChanged/offset`
- `MacroRecorder` (`ObservableObject`): records keyDown/keyUp/flagsChanged via a dedicated listen-only CGEventTap. Auto-stops at a cap of 200 events/60 seconds. Self-synthesized events (`SynthesizedClick.signature`) are excluded
- `ActionExecutor.perform(.macro)`: replays `CGEvent`s according to `offset` on a dedicated serial queue. A generation counter protected by `os_unfair_lock` ensures that re-triggering during playback immediately cancels the previous playback (prevents duplicate playback)
- The default action for three-finger tap was changed to an empty macro (`.macro([])`). The old default of a Mission Control keystroke was removed
- Settings UI: added recording start/stop, clear, and event-count display to the "Three-finger tap (macro)" section

### Tracking-speed boost
- `PointerSpeedManager`: directly rewrites `HIDMouseAcceleration` (the value behind the System Settings slider, IOFixed 16.16) via the `IOHIDEventSystemClient` SPI (`IOHIDEventSystemClientCreateSimpleClient` / `CopyProperty` / `SetProperty`), applying it immediately. The initial value is captured at launch so it can be restored
- The SPI declarations are consolidated into the existing single bridging header `MultitouchBridge.h` (since `swiftc -import-objc-header` only accepts one)
- Added `AppSettings.pointerSpeedBoost: Double`, reflected in `SettingsSnapshot`
- Settings UI: added a "Cursor Speed Boost" slider

### Build and real-hardware verification
- Ran `./build.sh`; all sources, including the two features above, compile successfully. No errors other than the existing `onChange(of:perform:)` deprecation warning. Confirmed through generation and signing of `build/Magic Mouse Toolkit.app`
- Macro recording/playback and the speed boost have been verified on real hardware
- Virtual trackpad, two-finger scroll, native momentum, and input separation from the built-in trackpad have also been verified on real hardware
- Toggling Accessibility permission mid-run can trigger a known macOS input freeze, so it is excluded from regression testing. See `SAFETY.md` for safety requirements

---

<a id="简体中文"></a>

# Magic Mouse Toolkit 实现规格（代码对齐版）

创建于 2026-07-02。目标是仅凭本文即可完成实现，原文假定实现者为 Sonnet 5。背景和历史见 SPEC.md / ARCHITECTURE.md，设计令牌见 DESIGN.md。

## 0. 阶段

- **阶段 1：原型，本文范围**：全部功能，加上使用 DESIGN.md 令牌、具有原生观感的简单 Form 界面，完成功能验证和校准。
- **阶段 2**：更换为 Liquid Glass 设计；结构上应只需替换 DesignSystem.swift 令牌值并加入 GlassWindow。

## 1. 轻点／滚动误触防止：四层防护（本文核心）

只靠触摸坐标的距离／速度阈值，难免出现边界误判。因此**用操作系统自身的滚动判断，即 `.scrollWheel` 事件，作为基准信号**。中键转换本来就需要 CGEventTap，增加 `.scrollWheel` 监听几乎没有额外开销。

轻点必须**同时通过以下各层**才会被识别：

### 第 1 层：接触几何（传统触摸坐标判断）

- 接触时长 ≤ `tapMaxDuration`。
- 起点至终点直线距离 ≤ `tapMaxStraightDistance`。
- 每帧移动累加的路径长度 ≤ `tapMaxPathLength`。
- 观测瞬时速度峰值，即 `MTTouch.normalized.velocity` 的最大模长，≤ `tapMaxVelocity`。
- 接触帧数 ≥ `tapMinFrames`，排除短暂擦碰／噪声。Magic Mouse 触摸帧约 90 Hz，3 帧约为 33 ms。

### 第 2 层：滚动否决（使用系统滚动判断）

- 从接触开始至轻点判定时，或从判定时刻回溯 `scrollVetoWindow`（默认 0.25s）内，若观测到 `.scrollWheel`，则**不注册轻点**。
- 被动记录 scrollWheel，事件原样放行；`ScrollMonitor` 只保留最近一次观测时间。

### 第 3 层：惯性滚动否决

- 接触开始时，若 `.scrollWheel` 的 `kCGScrollWheelEventMomentumPhase` 为 began/continued，即正在惯性滚动，则**整次接触都不作为轻点候选**；设置 `beganDuringMomentum`，保证抬指时不注册。
- 原因：用手指停止 Magic Mouse 惯性滚动是日常常见操作，也是误点击最常见的来源。

### 第 4 层：实体按钮否决

- 实体按钮按住期间，即 leftMouseDown 至 Up 之间，以及 buttonUp 后 `buttonVetoWindow`（默认 0.1s）内，不注册轻点。
- 原因：实体点击也会检测到手指接触，需防止“实体点击 + 合成轻点”形成双击。

### 已知限制（需在 README 中说明）

- 其他设备如触控板正在滚动时轻点 Magic Mouse，第 2 层可能误否决，漏掉一次点击。这是较少见的双手操作情况，且结果偏向安全，因此接受。
- 第 2 层依赖实际产生滚动事件，滚动开始前的微小位移交由第 1 层处理。

## 2. 项目结构

下列目录示例及代码保留原文，文件名和标识符不作翻译：

```
MagicMouseToolkit/
├── build.sh
├── Info.plist
├── MagicMouseToolkit.entitlements    (unused. Ad-hoc distribution, no App Sandbox)
├── Sources/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MultitouchBridge.h       (also consolidates the HID system SPI declarations, due to the single-bridging-header constraint)
│   ├── MultitouchDevice.swift
│   ├── TouchGestureManager.swift
│   ├── TapRecognizer.swift
│   ├── EventInterceptor.swift
│   ├── SynthesizedClick.swift
│   ├── ActionKind.swift         (Codable model for tap assignments; includes RecordedKeyEvent)
│   ├── ActionExecutor.swift     (executes ActionKind; includes reentrancy guard logic for macro playback)
│   ├── MacroRecorder.swift      (three-finger-tap macro recording, listen-only CGEventTap)
│   ├── PointerSpeedManager.swift(tracking-speed boost, IOHIDEventSystemClient SPI)
│   ├── Settings.swift
│   ├── DesignSystem.swift       (implementation of DESIGN.md's tokens)
│   └── SettingsView.swift
└── docs (SPEC.md and other existing docs)
```

其中 `MultitouchBridge.h` 因只能使用一个桥接头文件，也汇总 HID 系统 SPI 声明；`ActionKind.swift` 包含轻点操作的 Codable 模型和 RecordedKeyEvent；`ActionExecutor.swift` 包含宏回放重入保护；`MacroRecorder.swift` 使用只监听的 CGEventTap；`PointerSpeedManager.swift` 通过 IOHIDEventSystemClient SPI 增强跟踪速度。

## 3. 构建与签名

### build.sh

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="Magic Mouse Toolkit.app"
BIN="MagicMouseToolkit"
SIGN_ID="${SIGN_ID:-}"              # ad-hoc signing if unspecified

SWIFT_FILES=(Sources/*.swift)
FLAGS=(-import-objc-header Sources/MultitouchBridge.h
       -F /System/Library/PrivateFrameworks -framework MultitouchSupport
       -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit -O)

mkdir -p build
# Phase 2's Liquid Glass (glassEffect) is a macOS 26+ API, so the deployment target is raised
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target arm64-apple-macos26.0  -o build/$BIN-arm64
swiftc "${SWIFT_FILES[@]}" "${FLAGS[@]}" -target x86_64-apple-macos26.0 -o build/$BIN-x86_64
lipo -create build/$BIN-arm64 build/$BIN-x86_64 -output build/$BIN

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp Info.plist "build/$APP/Contents/"
cp build/$BIN "build/$APP/Contents/MacOS/"
codesign --force --sign "$SIGN_ID" "build/$APP"
echo "Built: build/$APP"
```

- 在 build.sh 顶部导出 `CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"`，原文依据 CLAUDE.md 的默认设置。
- 始终通过 `open -a "build/Magic Mouse Toolkit.app"` 验证，以 launchd 为父进程；从终端直接运行二进制会绕过 TCC。

### Info.plist（必需键）

| 键 | 值 |
|---|---|
| CFBundleIdentifier | com.mori0818.magicmousetoolkit |
| CFBundleName / CFBundleDisplayName | Magic Mouse Toolkit |
| CFBundleExecutable | MagicMouseToolkit |
| CFBundleVersion / ShortVersionString | 1.0 |
| LSUIElement | true |
| NSHighResolutionCapable | true |


## 4. MultitouchBridge.h（完整内容）

```c
#ifndef MultitouchBridge_h
#define MultitouchBridge_h
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
  int32_t frame;
  double timestamp;
  int32_t identifier;
  int32_t state;          // 4 = Touching
  int32_t fingerId, handId;
  MTVector normalized;    // both position/velocity normalized 0.0-1.0 (larger Y = further forward)
  float size;
  int32_t zero1;
  float angle, majorAxis, minorAxis;
  MTVector absolute;
  int32_t zero2, zero3;
  float zDensity;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef device, MTTouch *touches,
                                         int numTouches, double timestamp, int frame);

CFMutableArrayRef MTDeviceCreateList(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTUnregisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);
bool MTDeviceIsBuiltIn(MTDeviceRef);
OSStatus MTDeviceGetFamilyID(MTDeviceRef, int32_t *familyId);

#endif
```

- 仅将触摸状态 `4 (Touching)` 视为接触，其他状态不计入当前帧指数量。
- `MTTouch` 布局与 MouseToucher 分支的实机验证版本一致。若 `position` 超出 0–1，应怀疑布局不匹配，先检查日志中 `timestamp` 和 `identifier` 是否有效。

## 5. 设备管理：MultitouchDevice.swift

```swift
final class MultitouchDeviceManager {
    static let shared = MultitouchDeviceManager()
    private var activeDevices: [MTDeviceRef] = []
    func start()    // enumerate → filter → register
    func stop()     // unregister all + MTDeviceStop
    func restart()  // stop() → start() after 0.5s (handles device reconnection)
}
```

- **仅匹配 Magic Mouse 的过滤条件**：`MTDeviceIsBuiltIn(dev) == false`，且 `MTDeviceGetFamilyID` 成功，满足 `familyId == 112 || familyId == 113`。
- 112/113 表示 Magic Mouse 设备族。**首次启动务必记录实际 familyId**，以便及时发现 Magic Mouse 2 / USB-C 型号不匹配。若未匹配到设备，在菜单栏显示“No device passed the familyId filter. Detected familyIds: [...]”。
- 备用设置 `deviceFilterStrict` 默认 true；设为 false 时退回仅检查 `!MTDeviceIsBuiltIn` 的旧行为，供 familyId 不符合预期的设备使用。
- 回调是 C 函数指针，不能捕获上下文，从全局函数转发到 `TouchGestureManager.shared`。
- **重连处理**：结合 `NSWorkspace.shared.notificationCenter` 的 `didWakeNotification` 与匹配 AppleMultitouchDevice 的 `IOServiceAddMatchingNotification` 较复杂，**原型先简化**：监听唤醒，并提供调用 `restart()` 的“重新检测设备”菜单项；自动蓝牙重连检测留到阶段 2。

## 6. 设置：Settings.swift

以 `UserDefaults.standard` 为存储。各属性在 `didSet` 中发送 `NotificationCenter.default.post(name: .settingsChanged)`。TouchGestureManager / EventInterceptor 收到通知后把全部值复制到本地 `SettingsSnapshot` 并保留。出于性能和安全考虑，回调内绝不读取 UserDefaults。

| 属性 | UserDefaults 键 | 类型 | 默认值 | 界面范围 |
|---|---|---|---|---|
| enabled | mmt.enabled | Bool | true | — |
| oneFingerTapEnabled | mmt.tap1.enabled | Bool | true | — |
| twoFingerTapEnabled | mmt.tap2.enabled | Bool | true | — |
| middleClickEnabled | mmt.middle.enabled | Bool | true | — |
| rightZoneMinX | mmt.zone.rightMinX | Double | 0.6 | 0–1 |
| zoneMinX / zoneMaxX | mmt.zone.minX / maxX | Double | 0.0 / 1.0 | 0–1 |
| zoneMinY / zoneMaxY | mmt.zone.minY / maxY | Double | 0.0 / 1.0 | 0–1 |
| tapMaxDuration | mmt.tap.maxDuration | Double | 0.16 | 0.05–0.5 s |
| tapMaxStraightDistance | mmt.tap.maxStraight | Double | 0.09 | 0.01–0.3 |
| tapMaxPathLength | mmt.tap.maxPath | Double | 0.07 | 0.01–0.3 |
| tapMaxVelocity | mmt.tap.maxVelocity | Double | 1.5 | 0.2–8.0 /s |
| tapMinFrames | mmt.tap.minFrames | Int | 3 | 1–10 |
| scrollVetoWindow | mmt.veto.scroll | Double | 0.25 | 0–1.0 s |
| buttonVetoWindow | mmt.veto.button | Double | 0.10 | 0–0.5 s |
| twoFingerSyncWindow | mmt.tap2.syncWindow | Double | 0.06 | 0.02–0.2 s |
| deviceFilterStrict | mmt.device.strict | Bool | true | — |


表中依次为属性、UserDefaults 键、类型、默认值和界面范围。

- `tapMaxVelocity` 的 1.5 为暂定值，需通过第 9 节调试显示校准。
- 启动时用 `UserDefaults.standard.register(defaults:)` 注册初值。

## 7. 轻点识别：TouchGestureManager.swift + TapRecognizer.swift

### 共享状态（由 EventInterceptor 读取）

```swift
struct TouchSharedState {          // protected by os_unfair_lock
    var fingerCount: Int = 0       // number of fingers in state==4 for the current frame
    var lastFrameAt: CFTimeInterval = 0   // time the last touch frame was received (CACurrentMediaTime)
}
```

`fingerCount` 表示当前帧 state==4 的手指数；`lastFrameAt` 是最近触摸帧的 CACurrentMediaTime 时间。共享状态受 os_unfair_lock 保护。

### 触摸帧处理（MT 后台回调）

1. 读取 `SettingsSnapshot`；若 `enabled == false`，只更新 fingerCount 并返回。
2. 更新共享的 fingerCount 和 lastFrameAt。
3. 按触摸 `identifier` 映射到 `activeTouches: [Int32: TouchTrack]` 并更新。

```swift
struct TouchTrack {
    let id: Int32
    let startTime: Double          // timestamp of the MT frame
    let startPos: MTPoint
    var lastPos: MTPoint
    var pathLength: Float = 0      // Σ|Δpos|
    var maxVelocity: Float = 0     // max ‖normalized.velocity‖
    var frames: Int = 1
    var beganDuringMomentum: Bool  // whether ScrollMonitor.momentumActive was true at start (Layer 3)
    var vetoed: Bool = false       // set true once a Layer-1 threshold violation is confirmed mid-contact (no further updates needed)
}
```

`TouchTrack` 保存起始时间、起点、最近位置、累计路径、最大速度、帧数、是否在惯性期间开始接触及是否已被否决。

4. 当前帧存在的接触更新路径和速度：`pathLength += hypot(Δx, Δy)`、`maxVelocity = max(...)`；超阈值则设 `vetoed = true`。
5. **上一帧存在、当前帧消失的 identifier 表示抬指**，在抬指时判定。
6. 任一帧出现同时接触的三指及以上时，将当时所有轨迹设为 `vetoed = true`。

### 抬指时的轻点判断（TapRecognizer）

以下注册条件必须全部成立：未否决、未在惯性期间开始接触、时长／位移／路径／速度／帧数达标、起点在区域内、满足滚动窗口及实体按钮条件。

```
Registration condition (all AND):
  !track.vetoed
  !track.beganDuringMomentum                          // Layer 3
  duration = releaseTime - startTime ≤ tapMaxDuration
  |endPos - startPos| ≤ tapMaxStraightDistance
  pathLength ≤ tapMaxPathLength
  maxVelocity ≤ tapMaxVelocity
  frames ≥ tapMinFrames
  startPos is within the zone [zoneMinX,zoneMaxX]×[zoneMinY,zoneMaxY]
  ScrollMonitor.lastScrollAt < startTime - scrollVetoWindow   // Layer 2 (before start)
  ScrollMonitor.lastScrollAt < now → no scroll occurred during contact   // Layer 2 (during contact)
  EventInterceptor.buttonDown == false                 // Layer 4
  now - EventInterceptor.lastButtonUpAt > buttonVetoWindow
```

第 2 层可简化为：只要 `lastScrollAt` 曾在 `startTime - scrollVetoWindow` 或之后更新，就不注册。

- **单指轻点**：注册时，`endPos.x > rightZoneMinX` 则合成右键，否则左键。
- **双指轻点**：两条轨迹起始时间差 ≤ `twoFingerSyncWindow`、均已抬指且满足注册条件、抬指时间差 ≤ `twoFingerSyncWindow * 2` 时，只合成一次左键。**双指一旦注册，同两条轨迹不得再触发单指**。单指判断最多等待 `twoFingerSyncWindow*2`：已抬指轨迹先入 `pendingRelease`，配对轨迹出现则触发双指，超时则触发单指；复用一个 `DispatchSourceTimer`。
- 仅在启用双指轻点时等待；`twoFingerTapEnabled == false` 时，单指立即触发，零延迟。
- 点击通过第 8 节 `SynthesizedClick.post(button:at:)` 合成，位置为 **`CGEvent(source: nil)` 返回的当前光标位置**。

## 8. 事件监听：EventInterceptor.swift + SynthesizedClick.swift

### 单个 CGEventTap 承担三种作用

```swift
CGEvent.tapCreate(
  tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: (1 << CGEventType.leftMouseDown.rawValue)
                  | (1 << CGEventType.leftMouseUp.rawValue)
                  | (1 << CGEventType.scrollWheel.rawValue),
  callback: interceptorCallback, userInfo: nil)
```

回调要求：**不分配内存、不写日志、不读取 UserDefaults**。只允许读取 SettingsSnapshot 和共享状态，以及改写整数事件字段。

分支逻辑伪代码：

```
case .tapDisabledByTimeout, .tapDisabledByUserInput:
    CGEventTapEnable(tap, true); return event            // self-recovery
case .scrollWheel:                                        // acts as ScrollMonitor
    lastScrollAt = now
    phase = event[.scrollWheelEventMomentumPhase]
    momentumActive = (phase == 1 || phase == 2)           // began/continued
    return event                                          // pass through unmodified
case .leftMouseDown:
    if event[.eventSourceUserData] == kMCEventSignature: return event   // pass through our own synthesized events
    buttonDown = true
    if middleClickEnabled
       && shared.fingerCount == 2
       && (now - shared.lastFrameAt) < 0.08 {             // device-correlation guard
        convertingToMiddle = true
        event.type = .otherMouseDown
        event[.mouseEventButtonNumber] = 2                // center
    }
    return event
case .leftMouseUp:
    if event[.eventSourceUserData] == kMCEventSignature: return event
    buttonDown = false; lastButtonUpAt = now
    if convertingToMiddle {                               // if down decided the conversion, up must convert too
        convertingToMiddle = false
        event.type = .otherMouseUp
        event[.mouseEventButtonNumber] = 2
    }
    return event
```

- 总开关关闭时，**完整禁用监听 `CGEventTapEnable(false)`**。仅关闭中键、仍启用轻点时，保留监听以供第 2 层使用，但原样放行 Down/Up。
- 创建监听失败、没有权限时，进入第 10 节 AppDelegate 权限流程。

### SynthesizedClick.swift

```swift
enum SynthesizedClick {
    static let signature: Int64 = 0x4D43_4C4B          // "MCLK"
    static func post(button: CGMouseButton) {
        let loc = CGEvent(source: nil)!.location
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = signature                       // self-identification (EventInterceptor passes it through)
        let (down, up): (CGEventType, CGEventType) = ...  // left/right/other depending on button
        CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: up,   mouseCursorPosition: loc, mouseButton: button)?.post(tap: .cghidEventTap)
    }
}
```

- down 与 up 之间不加延迟，MouseToucher 测试已验证可用。
- `CGEventSource.userData` 可从事件的 `.eventSourceUserData` 字段读取，用来识别自身合成事件并放行。

## 9. 界面：SettingsView.swift（原型版）

仅使用 DESIGN.md 的 `DesignSystem.swift` 令牌，不在视图中直接写字号、颜色和间距。

结构为 `Form` + `Section`，窗口 440×620，不可调整大小：

1. **常规**：总启用开关。
2. **手势**：单指／双指／中键开关，以及右键区起始 X 滑块。
3. **有效范围**：X 最小／最大、Y 最小／最大，共 4 个百分比滑块。
4. **灵敏度**：tapMaxDuration / MaxStraight / MaxPath / MaxVelocity / MinFrames，共 5 个滑块；当前值以等宽字体右对齐。
5. **误触防止**：scrollVetoWindow / buttonVetoWindow / twoFingerSyncWindow。
6. **调试**：DisclosureGroup，只在展开时更新。显示当前指数量与最近坐标；最近一次轻点的**判断明细**逐项并列展示实测值与阈值，用颜色指出失败层／条件，例如 `path 0.11 > 0.07 ✗`，作为速度阈值校准主要工具；展示最近 10 条轻点成功、滚动否决、惯性否决等事件。TouchGestureManager **只在展开时**推送至 `DebugFeed.shared`，这是 ObservableObject 的 10 项环形缓冲；视图 onAppear/onDisappear 切换 `DebugFeed.isActive`，关闭时开销仅为检查一个标志。
7. **重置**：“恢复默认灵敏度”按钮。

菜单栏（AppKit NSMenu）的原文布局：

```
✓ Enabled                  (toggle, master enable)
──────────
Open Settings…
Redetect Device            (MultitouchDeviceManager.restart)
──────────
About Magic Mouse Toolkit
Quit ⌘Q
```

对应启用、打开设置、重新检测设备、关于和退出。图标用模板图像 SF Symbols `computermouse.fill`。设置窗口延迟创建，关闭时释放；SwiftUI 托管下 `NSWindow.isReleasedWhenClosed` 配合不佳，因此设为 false，再将引用置 nil 释放。

## 10. AppDelegate 启动顺序

1. `UserDefaults.register(defaults:)`。
2. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`；未授权时每 2 秒轮询，**授权后丢弃定时器**，这是唯一的定时器。
3. 授权后依次启动 `MultitouchDeviceManager.shared.start()` 和 `EventInterceptor.shared.start()`。
4. 设置菜单栏图标。
5. 订阅 `didWakeNotification`，调用 `MultitouchDeviceManager.restart()`。

## 11. 线程与同步

| 数据 | 写入方 | 读取方 | 保护方式 |
|---|---|---|---|
| TouchSharedState（fingerCount、lastFrameAt） | MT 回调线程 | 事件监听，主 RunLoop | os_unfair_lock，持锁为纳秒量级 |
| lastScrollAt / momentumActive / buttonDown / lastButtonUpAt / convertingToMiddle | 事件监听 | MT 回调线程 | 同上，可共用锁 |
| SettingsSnapshot | 主线程，收到通知后整体替换 | 两类回调 | 结构整体替换 + 锁 |
| DebugFeed | MT 回调派发到主线程 | SwiftUI | 通过 isActive 抑制发送本身 |

## 12. 实体设备测试清单

1. 先检查核心功能，再处理玻璃／窗口：单指轻点左键、右侧区域右键、双指轻点左键、双指实体点击中键；原文举例通过关闭 Finder 标签页验证。
2. **误触场景均不得点击**：缓慢开始滚动、快速甩动、往返滚动、用手指停止惯性滚动、实体点击期间轻点、操作触控板时完全不响应。
3. 其他鼠标或触控板的点击／滚动完全不受影响。
4. 设置立即生效，无需重建或重启。
5. 检查睡眠唤醒后及“重新检测设备”的行为。
6. 重新构建、重新签名后权限不应撤销。
7. 活动监视器中空闲 CPU 为个位数百分比，内存 ≤15MB。
8. CGEventTap 在高负载下可自恢复，长时间运行验证不中断。

## 13. 阶段 2 交接点

- 视觉修改限制在 `DesignSystem.swift` 令牌及新增的无边框 NSWindow 子类 `GlassWindow.swift`；复用 SettingsView 布局结构。
- 整合前，先在独立无边框透明窗口中验证 `.glassEffect()`。

## 14. 三指轻点宏录制／跟踪速度增强（2026-07-10 已实现）

本节记录当时已实现的宏录制和速度增强要点。

### 宏录制（三指轻点）

- 新增 `ActionKind.macro([RecordedKeyEvent])`；`RecordedKeyEvent` 为包含 `keyCode/flags/isDown/isFlagsChanged/offset` 的 Codable。
- `MacroRecorder` 为 ObservableObject，通过专用只监听 CGEventTap 录制 keyDown/keyUp/flagsChanged，达到 200 个事件或 60 秒自动停止；排除自身合成的 `SynthesizedClick.signature` 事件。
- `ActionExecutor.perform(.macro)` 在专用串行队列按 `offset` 回放 CGEvent；用 os_unfair_lock 保护的代数计数器，保证回放中再次触发时立即取消旧回放，防止重复播放。
- 三指轻点默认操作改为空宏 `.macro([])`，移除旧的 Mission Control 按键默认值。
- 设置页“三指轻点（宏）”增加开始／停止录制、清空和事件数量显示。

### 跟踪速度增强

- `PointerSpeedManager` 通过 `IOHIDEventSystemClientCreateSimpleClient` / `CopyProperty` / `SetProperty` SPI 直接改写 `HIDMouseAcceleration`，即系统设置滑块对应的 IOFixed 16.16 值，立即生效；启动时捕获原值以便恢复。
- SPI 声明整合在唯一的桥接头 `MultitouchBridge.h`，因为 `swiftc -import-objc-header` 只接受一个头文件。
- 新增 `AppSettings.pointerSpeedBoost: Double`，同步至 `SettingsSnapshot`。
- 设置页增加“光标速度增强”滑块。

### 当时的构建与实机验证

- 运行 `./build.sh`，含上述两项功能的所有源代码编译成功；除已有 `onChange(of:perform:)` 弃用警告外无错误，成功生成并签名 `build/Magic Mouse Toolkit.app`。
- 宏录制／回放和速度增强已在实体设备验证。
- 虚拟触控板、双指滚动、原生惯性及与内建触控板的输入区分也已实机验证。
- 运行期间切换辅助功能权限可能触发已知 macOS 输入冻结，因此不列入回归测试；安全要求见 `SAFETY.md`。
