// The middle-click event transformation is adapted from MiddleClick (GPL-3.0).
// See THIRD_PARTY_NOTICES.md. Magic Mouse Toolkit is licensed under GPL-3.0-only.

import CoreGraphics
import QuartzCore
import AppKit
import IOKit

/// CGEventTap の C コールバック（capture 不可のためグローバル関数）。
private func eventInterceptorCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    EventInterceptor.shared.handle(type: type, event: event)
}

/// 1本の CGEventTap で3役を兼ねる:
/// - スクロール監視（第2層・第3層ベトの情報源。ScrollMonitor役）
/// - 物理クリック監視（第4層ベトの情報源）
/// - 2本指物理クリック→ミドルクリック変換
///
/// コールバック規律: ログ・UserDefaults 読み取り・IORegistry 探索禁止。
/// 例外はスクロール・ジェスチャ・物理ボタンの送信元判別に必要な CGEventCopyIOHIDEvent のみ。
/// デバイスIDは開始時と着脱時にキャッシュし、コールバック内では集合を読むだけ。
///
/// 権限喪失の検知と復旧は本クラスの責務ではなく PermissionMonitor + AppDelegate が担う
/// (SAFETY.md参照)。理由: `.tapDisabledByUserInput` はアクセシビリティ権限を
/// システム設定でOFFにした際、実機では配送されないことが確認されている(剥奪と同時に
/// タップへのイベント配送自体が止まるため)。このコールバック内で権限喪失を検知する
/// 設計は機能しないので採用しない。
final class EventInterceptor {
    static let shared = EventInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trackpadScrollSenders: Set<UInt64> = []
    private var magicMouseScrollSenders: Set<UInt64> = []
    private var magicMouseButtonSenders: Set<UInt64> = []
    private var convertedRightPressSender: UInt64?

    /// メニューバーの状態表示用
    var isRunning: Bool { eventTap != nil }

    private init() {
        // .settingsChanged の購読は生存期間中1回だけ行う。start()/stop() のたびに
        // 登録し直すと、権限失効→復旧のサイクルを重ねるごとにオブザーバが重複登録され、
        // updateEnabledState() が多重に呼ばれるようになるため。
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }

    func start() {
        guard eventTap == nil else { return }
        refreshMultitouchScrollSources()

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << 29) // NSEventTypeGesture: Magic Mouse two-finger page swipe
            | (1 << 31) // NSEventTypeSwipe

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventInterceptorCallback,
            userInfo: nil
        ) else {
            MMTLog.log("イベントタップ作成失敗(アクセシビリティ権限を確認)")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        MMTLog.log("イベントタップ作成成功(クリック監視・ミドルクリック変換が有効)")

        updateEnabledState()
    }

    /// Resolve multitouch HID sender IDs outside the event-tap callback.
    /// The device's driver class distinguishes trackpads from Magic Mice.
    func refreshMultitouchScrollSources() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var trackpads: Set<UInt64> = []
        var magicMice: Set<UInt64> = []
        var magicButtons: Set<UInt64> = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
                var senderID: UInt64 = 0
                if IORegistryEntryGetRegistryEntryID(service, &senderID) == KERN_SUCCESS {
                    if IOObjectConformsTo(parent, "AppleMultitouchTrackpadHIDEventDriver") != 0 {
                        trackpads.insert(senderID)
                    } else if IOObjectConformsTo(parent, "AppleMultitouchMouseHIDEventDriver") != 0 {
                        magicMice.insert(senderID)
                        magicButtons.insert(senderID)
                        var driverID: UInt64 = 0
                        if IORegistryEntryGetRegistryEntryID(parent, &driverID) == KERN_SUCCESS {
                            magicButtons.insert(driverID)
                        }
                    }
                }
                IOObjectRelease(parent)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        trackpadScrollSenders = trackpads
        magicMouseScrollSenders = magicMice
        magicMouseButtonSenders = magicButtons
    }

    /// タップを完全に破棄する。`tapEnable(false)` だけでなく `CFMachPortInvalidate` まで
    /// 行うのが重要: WindowServer側にポート登録が残ったままだと、権限剥奪直後の
    /// フリーズからの回復が遅れる/回復しない可能性があるため(SAFETY.md参照)。
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        // タップ破棄後に再開しても押下中・変換途中の状態が残らないようにする
        // （残っていると再有効化後の最初のクリックが誤ってミドルUpに変換される）
        clearSharedInputState()
    }

    /// 押下中・変換途中・スクロール受け渡し中の共有状態を初期化する。
    /// タップ無効化(updateEnabledState)・タップ破棄(stop)の両方から呼ぶ
    private func clearSharedInputState() {
        // The matching physical up may arrive after the tap is disabled.
        // Release our remapped left press before discarding its ownership.
        if convertedRightPressSender != nil {
            if let location = CGEvent(source: nil)?.location,
               let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                mouseCursorPosition: location, mouseButton: .left) {
                up.setIntegerValueField(.eventSourceUserData, value: SynthesizedClick.signature)
                up.post(tap: .cghidEventTap)
            }
            convertedRightPressSender = nil
        }
        let shared = SharedState.shared
        shared.convertingToMiddle = false
        shared.leftButtonDown = false
        shared.rightButtonDown = false
        shared.momentumActive = false
        shared.trackpadScrollPassthrough = false
        shared.trackpadMomentumEligibleUntil = -1e9
        shared.trackpadScrollOwner = 0
    }

    @objc private func settingsChanged() {
        updateEnabledState()
    }

    /// Remap only this Magic Mouse's physical secondary press, retaining sender
    /// ownership so its up is still paired if mode/options change while held.
    private func remapTrackpadRightPress(type: CGEventType, event: CGEvent, senderID: UInt64?) -> Bool {
        guard let senderID else { return false }
        let shared = SharedState.shared
        if type == .rightMouseDown {
            let settings = SettingsStore.shared.snapshot
            guard shared.trackpadModeActive, settings.trackpadPressDragEnabled,
                  !settings.trackpadTapZones, magicMouseButtonSenders.contains(senderID) else { return false }
            convertedRightPressSender = senderID
            shared.leftButtonDown = true
            event.type = .leftMouseDown
        } else if type == .rightMouseUp, convertedRightPressSender == senderID {
            convertedRightPressSender = nil
            shared.leftButtonDown = false
            shared.lastButtonUpAt = CACurrentMediaTime()
            event.type = .leftMouseUp
        } else {
            return false
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        return true
    }

    /// master enable OFF 時は tap 自体を無効化する（タップ判定もベト先も不要なため）。
    /// middleClick のみ OFF でタップ有効の場合は tap は生かす（第2層のスクロール監視のため）。
    ///
    /// 注意: ここでは SettingsStore のスナップショットではなく AppSettings を直接読む。
    /// スナップショットの更新も同じ .settingsChanged 通知で行われるため、オブザーバの
    /// 実行順序によっては1世代古い値を読んでしまい、有効トグルが1テンポずれる
    /// （OFF→ONに戻しても無効のままになる）バグの原因になる。
    private func updateEnabledState() {
        guard let tap = eventTap else { return }
        let enabled = AppSettings.shared.enabled
        if !enabled {
            // OFF 中は mouseUp を取りこぼすため、変換途中・押下中の状態を必ずクリアする
            clearSharedInputState()
        }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        MMTLog.log("イベントタップ: \(enabled ? "有効化" : "無効化")")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // コールバックが重くてシステムに自動無効化された場合のみ、その場で再有効化してよい。
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // システム設定でユーザーがアクセシビリティ/入力監視をOFFにした場合。
        // 実機検証では、権限剥奪と同時にこのタップへのイベント配送自体が止まり、
        // このイベントがコールバックに配送されないことが確認されている
        // (~/Library/Logs/MagicMouseToolkit.log に復旧ログが一切残らなかった)。
        // つまりここで何をしても頼りにできない。絶対に tapEnable(true) は呼ばない
        // (呼んでも意味が無い上、万一配送された場合に同期ループの引き金になりうる)。
        // 権限喪失の検知と復旧は PermissionMonitor が別経路(ポーリング)で行う。
        if type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let shared = SharedState.shared
        let now = CACurrentMediaTime()

        // A sideways two-finger stroke is recognized by macOS as the Magic
        // Mouse's horizontal page gesture, often with no scrollWheel sequence
        // at all. Raw contacts in TrackpadModeController supply the scroll.
        // Suppress only this mouse's native gesture so it cannot move pages.
        if (type.rawValue == 29 || type.rawValue == 31),
           shared.trackpadModeActive,
           SettingsStore.shared.trackpadModeOrientation != TrackpadModeOrientation.upright.rawValue,
           let hidEvent = CGEventCopyIOHIDEvent(event),
           magicMouseScrollSenders.contains(IOHIDEventGetSenderID(hidEvent)) {
            return nil
        }

        switch type {
        case .scrollWheel:
            if event.getIntegerValueField(.eventSourceUserData) == TrackpadModeController.scrollSignature {
                return Unmanaged.passUnretained(event)
            }
            // Another mouse's wheel can reach us twice: as a discrete hardware
            // event and as a continuous event injected by BetterTouchTool's
            // smooth scrolling. Neither belongs to the Magic Mouse touch sequence.
            // On this system BetterTouchTool marks those injected events with
            // userData 0x4D4D4741 and a nonzero source PID. Keep both paths out
            // of the gesture state, while retaining native touch filtering.
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
                || (event.getIntegerValueField(.eventSourceUnixProcessID) != 0
                    && event.getIntegerValueField(.eventSourceUserData) == 0x4D4D4741) {
                return Unmanaged.passUnretained(event)
            }

            // Native Magic Trackpad scrolling is continuous too. Its HID sender
            // identifies the trackpad even when no finger-count frame is being
            // monitored for this external device. Never treat it as Magic Mouse
            // touch scrolling or alter its horizontal deltas and momentum state.
            if shared.trackpadModeActive, let hidEvent = CGEventCopyIOHIDEvent(event) {
                let senderID = IOHIDEventGetSenderID(hidEvent)
                if trackpadScrollSenders.contains(senderID) {
                    return Unmanaged.passUnretained(event)
                }
                if magicMouseScrollSenders.contains(senderID),
                   SettingsStore.shared.trackpadModeOrientation != TrackpadModeOrientation.upright.rawValue {
                    // Sideways mode synthesizes scrolling from the contacts.
                    // Native horizontal scroll and momentum would double it.
                    return nil
                }
            }

            if shared.trackpadModeActive {
                // 直近フレームで2本指を確認できたスクロールと、その慣性列だけを通す。
                // デルタ値には触れず、macOSが生成した高精度の減速カーブをそのまま維持する。
                let magicMouseTwoFingers = shared.fingerCount >= 2 && (now - shared.lastFrameAt) < 0.08
                let builtInTwoFingers = shared.builtInTrackpadFingerCount >= 2
                    && (now - shared.builtInTrackpadLastFrameAt) < 0.08
                // 両方が同時なら内蔵トラックパッドを優先する。
                let detectedOwner = builtInTwoFingers ? 2 : (magicMouseTwoFingers ? 1 : 0)
                let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
                let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
                let inMomentum = (momentumPhase == 1 || momentumPhase == 2)  // began / continued
                let endsScroll = (scrollPhase == 4 || scrollPhase == 8)  // ended / cancelled
                let endsMomentum = (momentumPhase == 3)
                let passthroughActive = shared.trackpadScrollPassthrough
                let mayStartMomentum = now <= shared.trackpadMomentumEligibleUntil
                let currentOwner = shared.trackpadScrollOwner

                if endsMomentum && passthroughActive {
                    // CGMomentumScrollPhase の終端値は3。終端イベント自体を通してから閉じる。
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = 0
                } else if endsScroll && (passthroughActive || detectedOwner != 0) {
                    // 直接操作の終端イベントを通し、直後の慣性開始だけを短時間受け入れる。
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = now + 0.12
                    if currentOwner == 0 { shared.trackpadScrollOwner = detectedOwner }
                } else if detectedOwner != 0 {
                    shared.trackpadScrollPassthrough = true
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = detectedOwner
                } else if inMomentum && (passthroughActive || mayStartMomentum) && currentOwner != 0 {
                    shared.trackpadScrollPassthrough = true
                    shared.trackpadMomentumEligibleUntil = -1e9
                } else if passthroughActive {
                    // MTフレームとscrollWheelの配送順が前後しても、開始済みの列は欠落させない。
                } else {
                    shared.trackpadScrollPassthrough = false
                    shared.trackpadMomentumEligibleUntil = -1e9
                    shared.trackpadScrollOwner = 0
                    return nil
                }
            }

            // Magic Mouse はタップ程度の接触でもデルタ0のスクロールイベント(phase通知)を
            // 発生させるため、実際に移動量のあるイベントだけを「スクロール」として記録する。
            // そうしないと全タップがスクロールベトで潰される。
            let d1 = abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let d2 = abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            if d1 + d2 > 0 {
                shared.lastScrollAt = now
            }
            let phase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            shared.momentumActive = (phase == 1 || phase == 2)  // began / continued

            // 横スクロール無効化: Axis2(横)の3種のデルタ表現(整数生値・整数ポイント値・
            // 固定小数点値)をすべてゼロ化する。慣性フェーズのイベントも同じフィールドを
            // 持つため、この処理だけで横方向の慣性スクロールも止まる。
            if SettingsStore.shared.verticalScrollOnly {
                event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                MMTLog.log("[診断] 合成leftMouseDownがHIDタップを通過(注入成功)")
                return Unmanaged.passUnretained(event)
            }
            shared.leftButtonDown = true
            if !shared.trackpadModeActive
                && SettingsStore.shared.middleClickEnabled
                && shared.fingerCount == 2
                && (now - shared.lastFrameAt) < 0.08 {
                shared.convertingToMiddle = true
                event.type = .otherMouseDown
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseUp:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                return Unmanaged.passUnretained(event)
            }
            shared.leftButtonDown = false
            shared.lastButtonUpAt = now
            if shared.convertingToMiddle {
                shared.convertingToMiddle = false
                event.type = .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            }
            return Unmanaged.passUnretained(event)

        case .rightMouseDown:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                return Unmanaged.passUnretained(event)
            }
            let senderID = CGEventCopyIOHIDEvent(event).map { IOHIDEventGetSenderID($0) }
            if remapTrackpadRightPress(type: type, event: event, senderID: senderID) {
                return Unmanaged.passUnretained(event)
            }
            shared.rightButtonDown = true
            return Unmanaged.passUnretained(event)

        case .rightMouseUp:
            if event.getIntegerValueField(.eventSourceUserData) == SynthesizedClick.signature {
                return Unmanaged.passUnretained(event)
            }
            let senderID = CGEventCopyIOHIDEvent(event).map { IOHIDEventGetSenderID($0) }
            if remapTrackpadRightPress(type: type, event: event, senderID: senderID) {
                return Unmanaged.passUnretained(event)
            }
            shared.rightButtonDown = false
            shared.lastButtonUpAt = now
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
