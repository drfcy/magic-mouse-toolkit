import AppKit
import Combine
import CoreGraphics
import Darwin
import Foundation

/// 仮想トラックパッドモード。有効化中はマルチタッチのストロークをカーソル移動に変換し、
/// タップをクリックとして合成する。プロトタイプ(prototypes/virtual_trackpad/main.swift)の
/// 検証済みロジックを、本体の SharedState/SettingsSnapshot/SynthesizedClick に接続して移植したもの。
///
/// 規律(手順書 magic-mouse-toolkit-仮想トラックパッド実装手順.md 準拠):
/// MTコールバック(handleContactFrame)内では CGEvent 生成・メモリ確保・ログ出力を行わず、
/// os_unfair_lock で保護したアキュムレータへの書き込みのみに留める。実際の CGEvent 生成/post は
/// 専用シリアルキュー上の 120Hz タイマー(drainAndPost)でのみ行う。
final class TrackpadModeController: ObservableObject {
    static let shared = TrackpadModeController()
    static let scrollSignature: Int64 = 0x4D4D5453

    private init() {
        refreshDisplayBounds()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayBounds()
        }
        NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            if !AppSettings.shared.enabled { self?.stopForTermination() }
        }
        NotificationCenter.default.addObserver(
            forName: .settingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive, !AppSettings.shared.enabled else { return }
            self.deactivate()
        }
    }

    private let drainQueue = DispatchQueue(label: "com.mori0818.magicmousetoolkit.trackpadmode.drain")
    private var drainTimer: DispatchSourceTimer?
    /// drainQueue専用。他スレッドから触らないこと
    private lazy var moveEventSource = CGEventSource(stateID: .hidSystemState)

    // 全ディスプレイのbounds(CG座標・左上原点)。120Hzのdrainループから毎回
    // CGGetActiveDisplayListを呼ぶのは避け、着脱/配置変更通知でのみ更新する。
    private var displayLock = os_unfair_lock()
    private var displayBounds: [CGRect] = []

    private func refreshDisplayBounds() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let bounds = ids.map { CGDisplayBounds($0) }
        os_unfair_lock_lock(&displayLock)
        displayBounds = bounds
        os_unfair_lock_unlock(&displayLock)
    }

    private func currentDisplayBounds() -> [CGRect] {
        os_unfair_lock_lock(&displayLock)
        let bounds = displayBounds
        os_unfair_lock_unlock(&displayLock)
        return bounds
    }

    /// 移動先がどのディスプレイにも属さない場合、軸ごとに分解して通る方だけ動かす
    /// (壁沿いの滑走。物理マウスと同じ挙動)。ディスプレイ間の隙間へワープするのを防ぐ。
    private func resolvedPosition(current: CGPoint, target: CGPoint) -> CGPoint {
        let bounds = currentDisplayBounds()
        guard !bounds.isEmpty else { return current }
        func contains(_ point: CGPoint) -> Bool {
            bounds.contains { $0.contains(point) }
        }
        if contains(target) { return target }
        let xOnly = CGPoint(x: target.x, y: current.y)
        if contains(xOnly) { return xOnly }
        let yOnly = CGPoint(x: current.x, y: target.y)
        if contains(yOnly) { return yOnly }
        return current
    }

    private var accLock = os_unfair_lock()
    private var accDX: Double = 0
    private var accDY: Double = 0
    private var accScrollX: Double = 0
    private var accScrollY: Double = 0
    private var accClickPending = false
    private var accClickCount = 1
    private var accRightClickPending = false
    private var accDragDownPending = false
    private var accDragUpPending = false
    private var accTogglePending = false
    /// Only the drain queue reads/writes this after posting synthetic events.
    private var dragButtonPosted = false
    private var lastDragLocation: CGPoint?

    // Contact identities belong to the MT callback; event phases/subpixels to
    // the drain queue. No event allocation or posting occurs in the callback.
    private var twoFingerScroll = TwoFingerScrollTracker()
    private var scrollOrientation = TrackpadModeOrientation.upright
    private var suppressScrollUntilAllReleased = false
    private var scrollSequence = TouchScrollSequence()
    private var accScrollGestureActive = false
    private let twoFingerScrollGain = 1000.0

    // 現在追跡中の指(1本のみ)。2本以上では追跡を中断し、スクロールに専念する。
    private var trackedID: Int32?
    private var lastTouchPos = MTPoint(x: 0, y: 0)

    // タップ判定用の追跡状態(タッチ開始時にリセット)
    private var touchStartPos = MTPoint(x: 0, y: 0)
    private var touchStartTime: Double = 0
    private var touchPathLength: Double = 0
    private var touchMaxVelocity: Double = 0
    private var touchFrameCount: Int = 0
    private var touchHadPhysicalButton = false
    private var cursorAcceleration = CursorAcceleration()
    private var tapDrag = TapDragTracker()
    private var pendingDragDX = 0.0
    private var pendingDragDY = 0.0
    private var twoFingerTap = TwoFingerTapTracker()
    private var suppressSingleUntilAllReleased = false

    // モード解除用の3本指タップ追跡。MTコールバック内では数値状態だけを更新し、
    // 実際の切り替えは drainAndPost からメインキューへ渡す。
    private var threeFingerTracking = false
    private var threeFingerStartTime: Double = 0
    private var threeFingerStartPos = MTPoint(x: 0, y: 0)
    private var threeFingerLastPos = MTPoint(x: 0, y: 0)
    private var threeFingerPathLength: Double = 0
    private var threeFingerMaxVelocity: Double = 0
    private var threeFingerFrameCount: Int = 0
    private var lastThreeFingerToggleTapAt: Double = -1e9
    private let trackpadToggleDoubleTapWindow: Double = 0.45

    @Published private(set) var isActive = false

    func toggle() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.toggle() }
            return
        }
        if isActive {
            deactivate()
        } else {
            activate()
        }
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        resetTrackingState()

        os_unfair_lock_lock(&accLock)
        accDX = 0
        accDY = 0
        accScrollX = 0
        accScrollY = 0
        accScrollGestureActive = false
        accClickPending = false
        accClickCount = 1
        accRightClickPending = false
        accDragDownPending = false
        accDragUpPending = false
        accTogglePending = false
        os_unfair_lock_unlock(&accLock)
        twoFingerScroll.reset()
        suppressScrollUntilAllReleased = false
        drainQueue.sync { scrollSequence = TouchScrollSequence() }

        SharedState.shared.trackpadScrollPassthrough = false
        SharedState.shared.trackpadMomentumEligibleUntil = -1e9
        SharedState.shared.trackpadScrollOwner = 0
        SharedState.shared.fingerCount = 0
        SharedState.shared.trackpadModeActive = true

        let timer = DispatchSource.makeTimerSource(queue: drainQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 120.0)
        timer.setEventHandler { [weak self] in self?.drainAndPost() }
        timer.resume()
        drainTimer = timer

        MMTLog.log("[診断] TrackpadMode: 有効化")
        TrackpadModeHUD.flash(active: true)
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false

        // trackpadModeActive を落とす前に追跡状態を先に畳んでおく。
        // 先に落とすと、その瞬間に走っているMTコールバックが中途半端な
        // trackedID/アキュムレータを読む余地が理論上生まれるため
        drainTimer?.cancel()
        drainTimer = nil
        trackedID = nil
        cursorAcceleration.reset()
        _ = tapDrag.cancel()
        pendingDragDX = 0
        pendingDragDY = 0
        twoFingerTap.cancel()
        suppressSingleUntilAllReleased = false
        SharedState.shared.trackpadScrollPassthrough = false
        SharedState.shared.trackpadMomentumEligibleUntil = -1e9
        SharedState.shared.trackpadScrollOwner = 0
        SharedState.shared.fingerCount = 0
        SharedState.shared.trackpadModeActive = false
        twoFingerScroll.reset()
        suppressScrollUntilAllReleased = false
        os_unfair_lock_lock(&accLock)
        accScrollX = 0
        accScrollY = 0
        accScrollGestureActive = false
        accDX = 0
        accDY = 0
        accClickPending = false
        accClickCount = 1
        accRightClickPending = false
        accDragDownPending = false
        accDragUpPending = false
        os_unfair_lock_unlock(&accLock)

        // Close the scroll phase and release held buttons on normal teardown.
        drainQueue.sync {
            postScrollPackets(scrollSequence.consume(x: 0, y: 0, active: false))
            releaseDragButtonIfNeeded()
        }

        MMTLog.log("[診断] TrackpadMode: 無効化")
        TrackpadModeHUD.flash(active: false)
    }

    private func resetTrackingState() {
        trackedID = nil
        lastTouchPos = MTPoint(x: 0, y: 0)
        touchStartPos = MTPoint(x: 0, y: 0)
        touchStartTime = 0
        touchPathLength = 0
        touchMaxVelocity = 0
        touchFrameCount = 0
        cursorAcceleration.reset()
        _ = tapDrag.cancel()
        pendingDragDX = 0
        pendingDragDY = 0
        twoFingerTap.cancel()
        suppressSingleUntilAllReleased = false
        lastThreeFingerToggleTapAt = -1e9
        resetThreeFingerTracking()
    }

    private func cancelTapDrag() {
        let needsMouseUp = tapDrag.cancel()
        pendingDragDX = 0
        pendingDragDY = 0
        if needsMouseUp {
            os_unfair_lock_lock(&accLock)
            if accDragDownPending {
                // The drain queue has not pressed yet; discard the drag entirely.
                accDragDownPending = false
                accDX = 0
                accDY = 0
            } else {
                accDragUpPending = true
            }
            os_unfair_lock_unlock(&accLock)
        }
    }

    func stopForTermination() {
        if isActive { deactivate() }
    }

    private func resetThreeFingerTracking() {
        threeFingerTracking = false
        threeFingerStartTime = 0
        threeFingerStartPos = MTPoint(x: 0, y: 0)
        threeFingerLastPos = MTPoint(x: 0, y: 0)
        threeFingerPathLength = 0
        threeFingerMaxVelocity = 0
        threeFingerFrameCount = 0
    }

    /// MTコールバック経由(TouchGestureManager)から呼ばれる。CGEvent生成・ログ出力禁止。
    func handleContactFrame(touches: UnsafeBufferPointer<MTTouch>, timestamp: Double, settings: SettingsSnapshot) {
        // モード中は TouchGestureManager が早期returnするため、指本数と時刻をここで共有する。
        var touchingCount = 0
        var firstTouch: MTTouch?
        var secondTouch: MTTouch?
        var positionSumX: Float = 0
        var positionSumY: Float = 0
        var maxVelocity: Double = 0
        for touch in touches where touch.state == 4 {
            touchingCount += 1
            if firstTouch == nil { firstTouch = touch }
            else if secondTouch == nil { secondTouch = touch }
            positionSumX += touch.normalized.position.x
            positionSumY += touch.normalized.position.y
            let velocity = touch.normalized.velocity
            let magnitude = (Double(velocity.x) * Double(velocity.x)
                + Double(velocity.y) * Double(velocity.y)).squareRoot()
            maxVelocity = max(maxVelocity, magnitude)
        }
        SharedState.shared.fingerCount = touchingCount
        SharedState.shared.lastFrameAt = timestamp

        let orientation = TrackpadModeOrientation(rawValue: settings.trackpadModeOrientation) ?? .upright
        if orientation != scrollOrientation {
            twoFingerScroll.reset()
            scrollOrientation = orientation
            os_unfair_lock_lock(&accLock)
            accScrollX = 0; accScrollY = 0
            os_unfair_lock_unlock(&accLock)
        }
        let firstContact = firstTouch.map {
            TwoFingerScrollTracker.Contact(id: $0.identifier,
                x: Double($0.normalized.position.x), y: Double($0.normalized.position.y))
        }
        let secondContact = secondTouch.map {
            TwoFingerScrollTracker.Contact(id: $0.identifier,
                x: Double($0.normalized.position.x), y: Double($0.normalized.position.y))
        }
        if touchingCount == 0 { suppressScrollUntilAllReleased = false }
        else if touchingCount > 2 { suppressScrollUntilAllReleased = true }
        let translation: (x: Double, y: Double)
        if orientation == .upright || suppressScrollUntilAllReleased || threeFingerTracking {
            twoFingerScroll.reset()
            translation = (0, 0)
        } else {
            translation = twoFingerScroll.update(count: touchingCount, first: firstContact,
                                                  second: secondContact, at: timestamp)
        }
        let scroll = orientation.scrollDelta(contactDX: translation.x,
                                              contactDY: translation.y, gain: twoFingerScrollGain)
        os_unfair_lock_lock(&accLock)
        accScrollX += settings.verticalScrollOnly ? 0 : scroll.x
        accScrollY += scroll.y
        accScrollGestureActive = twoFingerScroll.isScrolling
        os_unfair_lock_unlock(&accLock)

        if touchingCount >= 3,
           settings.threeFingerTapEnabled,
           settings.threeFingerTapAction.isTrackpadToggle {
            twoFingerTap.cancel()
            suppressSingleUntilAllReleased = true
            let centroid = MTPoint(
                x: positionSumX / Float(touchingCount),
                y: positionSumY / Float(touchingCount))
            if threeFingerTracking {
                let dx = Double(centroid.x - threeFingerLastPos.x)
                let dy = Double(centroid.y - threeFingerLastPos.y)
                threeFingerPathLength += (dx * dx + dy * dy).squareRoot()
                threeFingerLastPos = centroid
                threeFingerMaxVelocity = max(threeFingerMaxVelocity, maxVelocity)
                threeFingerFrameCount += 1
            } else {
                threeFingerTracking = true
                threeFingerStartTime = timestamp
                threeFingerStartPos = centroid
                threeFingerLastPos = centroid
                threeFingerPathLength = 0
                threeFingerMaxVelocity = maxVelocity
                threeFingerFrameCount = 1
            }

            trackedID = nil
            cursorAcceleration.reset()
            cancelTapDrag()
            os_unfair_lock_lock(&accLock)
            accDX = 0
            accDY = 0
            os_unfair_lock_unlock(&accLock)
            return
        }

        // 3本指を順に離す途中は2本指スクロールへ遷移させず、全指リリース時に確定する。
        if threeFingerTracking {
            if touchingCount == 0 {
                let dx = Double(threeFingerLastPos.x - threeFingerStartPos.x)
                let dy = Double(threeFingerLastPos.y - threeFingerStartPos.y)
                let straightDistance = (dx * dx + dy * dy).squareRoot()
                let duration = timestamp - threeFingerStartTime
                let isTap = duration <= settings.tapMaxDuration
                    && straightDistance <= settings.tapMaxStraightDistance
                    && threeFingerPathLength <= settings.tapMaxPathLength
                    && threeFingerMaxVelocity <= settings.tapMaxVelocity
                    && threeFingerFrameCount >= settings.tapMinFrames
                resetThreeFingerTracking()
                if isTap {
                    if timestamp - lastThreeFingerToggleTapAt <= trackpadToggleDoubleTapWindow {
                        lastThreeFingerToggleTapAt = -1e9
                        os_unfair_lock_lock(&accLock)
                        accTogglePending = true
                        os_unfair_lock_unlock(&accLock)
                    } else {
                        lastThreeFingerToggleTapAt = timestamp
                    }
                } else {
                    lastThreeFingerToggleTapAt = -1e9
                }
                suppressSingleUntilAllReleased = false
            }
            return
        }

        // A multi-finger contact must never become a one-finger left tap while
        // the fingers are being lifted one after another.
        if touchingCount > 2 {
            twoFingerTap.cancel()
            suppressSingleUntilAllReleased = true
            trackedID = nil
            cursorAcceleration.reset()
            cancelTapDrag()
            return
        }

        // 2本以上ではカーソル・タップ追跡を中断し、未ドレインの移動量も破棄する。
        if touchingCount >= 2 {
            if SharedState.shared.buttonDown {
                twoFingerTap.cancel()
            } else if let first = firstTouch, let second = secondTouch {
                let firstPos = first.normalized.position
                let secondPos = second.normalized.position
                if twoFingerTap.isTracking {
                    twoFingerTap.update(
                        firstID: first.identifier, firstX: Double(firstPos.x), firstY: Double(firstPos.y),
                        secondID: second.identifier, secondX: Double(secondPos.x), secondY: Double(secondPos.y))
                } else if !suppressSingleUntilAllReleased &&
                            (trackedID == nil ||
                             ((trackedID == first.identifier || trackedID == second.identifier) &&
                              timestamp - touchStartTime <= settings.twoFingerSyncWindow)) {
                    twoFingerTap.begin(
                        firstID: first.identifier, firstX: Double(firstPos.x), firstY: Double(firstPos.y),
                        secondID: second.identifier, secondX: Double(secondPos.x), secondY: Double(secondPos.y),
                        at: timestamp)
                }
            }
            suppressSingleUntilAllReleased = true
            if twoFingerScroll.isScrolling { twoFingerTap.cancel() }
            trackedID = nil
            cursorAcceleration.reset()
            cancelTapDrag()
            os_unfair_lock_lock(&accLock)
            accDX = 0
            accDY = 0
            os_unfair_lock_unlock(&accLock)
            return
        }

        if twoFingerTap.isTracking {
            let isTap = twoFingerTap.finish(
                at: timestamp, maxDuration: settings.tapMaxDuration,
                minFrames: settings.tapMinFrames)
            if isTap && !SharedState.shared.buttonDown
                && timestamp - SharedState.shared.lastButtonUpAt > settings.buttonVetoWindow {
                os_unfair_lock_lock(&accLock)
                if settings.trackpadTapZones {
                    if settings.twoFingerTapEnabled { accClickPending = true }
                } else {
                    accRightClickPending = true
                }
                os_unfair_lock_unlock(&accLock)
            }
        }

        if suppressSingleUntilAllReleased {
            trackedID = nil
            cursorAcceleration.reset()
            cancelTapDrag()
            if touchingCount == 0 { suppressSingleUntilAllReleased = false }
            return
        }

        guard let touch = firstTouch else {
            evaluateTapAndReset(endPos: lastTouchPos, endTime: timestamp, settings: settings)
            return
        }

        if trackedID != touch.identifier {
            // 新規タッチ開始。デルタ0で基準位置だけ記録(いきなり跳ばないように)
            if tapDrag.isDragging { cancelTapDrag() }
            trackedID = touch.identifier
            lastTouchPos = touch.normalized.position
            touchStartPos = touch.normalized.position
            touchStartTime = timestamp
            touchPathLength = 0
            touchMaxVelocity = 0
            touchFrameCount = 0
            touchHadPhysicalButton = SharedState.shared.buttonDown
            cursorAcceleration.reset(at: timestamp)
            if settings.trackpadTapDragEnabled && !touchHadPhysicalButton {
                _ = tapDrag.begin(at: timestamp)
            } else {
                _ = tapDrag.cancel()
            }
            pendingDragDX = 0
            pendingDragDY = 0
            return
        }

        let ndx = Double(touch.normalized.position.x - lastTouchPos.x)
        let ndy = Double(touch.normalized.position.y - lastTouchPos.y)
        let uprightDX = ndx * settings.trackpadModeGain
        // MTの正規化Yは前方(指を伸ばす先端側)が大きい。画面は上原点でYが下に増えるため、
        // 「前方へなぞる=カーソルが上へ動く」という直感に合わせて符号反転する(プロトタイプStep2確認済み)
        let uprightDY = -ndy * settings.trackpadModeGain
        let (rawDX, rawDY) = orientation.cursorDelta(
            x: uprightDX, y: uprightDY,
            sidewaysAspectRatio: settings.trackpadSidewaysAspectRatio)
        let acceleration = cursorAcceleration.multiplier(
            contactDX: ndx, contactDY: ndy,
            timestamp: timestamp, strength: settings.trackpadAccelerationStrength)
        lastTouchPos = touch.normalized.position

        touchPathLength += (ndx * ndx + ndy * ndy).squareRoot()
        let velocity = touch.normalized.velocity
        let velocityMagnitude = (Double(velocity.x) * Double(velocity.x) + Double(velocity.y) * Double(velocity.y)).squareRoot()
        touchMaxVelocity = max(touchMaxVelocity, velocityMagnitude)
        touchFrameCount += 1

        let cursorDX = rawDX * acceleration
        let cursorDY = rawDY * acceleration
        let physicalButtonHeld = SharedState.shared.buttonDown
        touchHadPhysicalButton = touchHadPhysicalButton || physicalButtonHeld
            || SharedState.shared.lastButtonUpAt >= touchStartTime
        if !settings.trackpadTapDragEnabled || touchHadPhysicalButton {
            cancelTapDrag()
        }
        if tapDrag.isCandidate {
            pendingDragDX += cursorDX
            pendingDragDY += cursorDY
            if tapDrag.advance(contactDX: ndx, contactDY: ndy) {
                os_unfair_lock_lock(&accLock)
                accDragDownPending = true
                accDX += pendingDragDX
                accDY += pendingDragDY
                os_unfair_lock_unlock(&accLock)
                pendingDragDX = 0
                pendingDragDY = 0
            }
            return
        }

        let movement = (x: cursorDX, y: cursorDY)
        os_unfair_lock_lock(&accLock)
        accDX += movement.x
        accDY += movement.y
        os_unfair_lock_unlock(&accLock)
    }

    /// タッチ終了(リリース)時にタップかどうかを判定し、成立していればクリックフラグを立てる。
    /// CGEventの生成はここでは行わない(MTコールバックの規律)。
    private func evaluateTapAndReset(endPos: MTPoint, endTime: Double, settings: SettingsSnapshot) {
        guard trackedID != nil else { return }
        trackedID = nil
        cursorAcceleration.reset()
        let wasSecondTap = tapDrag.isCandidate
        let completedDrag = tapDrag.end()
        pendingDragDX = 0
        pendingDragDY = 0
        if completedDrag {
            os_unfair_lock_lock(&accLock)
            accDragUpPending = true
            os_unfair_lock_unlock(&accLock)
            return
        }

        // A physical click must not also become a synthetic tap on finger lift.
        guard !touchHadPhysicalButton, !SharedState.shared.buttonDown,
              SharedState.shared.lastButtonUpAt < touchStartTime else { return }

        let dx = Double(endPos.x - touchStartPos.x)
        let dy = Double(endPos.y - touchStartPos.y)
        let straightDistance = (dx * dx + dy * dy).squareRoot()
        let duration = endTime - touchStartTime

        let isTap = duration <= settings.tapMaxDuration
            && straightDistance <= settings.tapMaxStraightDistance
            && touchPathLength <= settings.tapMaxPathLength
            && touchMaxVelocity <= settings.tapMaxVelocity
            && touchFrameCount >= settings.tapMinFrames

        if isTap {
            let isRightTap = settings.trackpadTapZones
                && Double(touchStartPos.x) >= settings.rightZoneMinX
            os_unfair_lock_lock(&accLock)
            if isRightTap {
                accRightClickPending = true
            } else {
                accClickPending = true
                accClickCount = wasSecondTap ? 2 : 1
            }
            os_unfair_lock_unlock(&accLock)
            if !isRightTap && settings.trackpadTapDragEnabled {
                tapDrag.arm(afterLeftTapAt: endTime)
            }
        }
    }

    /// Drain-queue only: keep the same synthetic signature as ordinary taps so
    /// EventInterceptor does not treat the held button as a physical click.
    private func postDragButton(_ type: CGEventType) -> Bool {
        guard let src = moveEventSource,
              let location = CGEvent(source: nil)?.location ?? lastDragLocation,
              let event = CGEvent(mouseEventSource: src, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: .left) else {
            return false
        }
        event.setIntegerValueField(.eventSourceUserData, value: SynthesizedClick.signature)
        event.post(tap: .cghidEventTap)
        lastDragLocation = location
        return true
    }

    private func releaseDragButtonIfNeeded() {
        guard dragButtonPosted else { return }
        // A physical down has taken ownership; its real mouse-up will release.
        if SharedState.shared.leftButtonDown || postDragButton(.leftMouseUp) {
            dragButtonPosted = false
            lastDragLocation = nil
        }
    }

    private func postScrollPackets(_ packets: [TouchScrollSequence.Packet]) {
        for packet in packets {
            guard let event = CGEvent(scrollWheelEvent2Source: moveEventSource,
                                      units: .pixel, wheelCount: 2,
                                      wheel1: packet.y, wheel2: packet.x, wheel3: 0) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.scrollSignature)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: packet.phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            // These are already pixel-based touch deltas, not physical wheel
            // input. Post after HID filters so BTT's wheel smoothing does not
            // swallow/re-amplify them (verified in the three-stage probe).
            event.post(tap: .cgSessionEventTap)
        }
    }

    /// 専用キューのタイマーがアキュムレータをドレインし、mouseMoved / クリックを post する(120Hz)。
    private func drainAndPost() {
        os_unfair_lock_lock(&accLock)
        let dx = accDX
        let dy = accDY
        let scrollX = accScrollX
        let scrollY = accScrollY
        let scrollGestureActive = accScrollGestureActive
        let clickPending = accClickPending
        let clickCount = accClickCount
        let rightClickPending = accRightClickPending
        let dragDownPending = accDragDownPending
        let dragUpPending = accDragUpPending
        let togglePending = accTogglePending
        accDX = 0
        accDY = 0
        accScrollX = 0
        accScrollY = 0
        accClickPending = false
        accClickCount = 1
        accRightClickPending = false
        accDragDownPending = false
        accDragUpPending = false
        accTogglePending = false
        os_unfair_lock_unlock(&accLock)

        let settings = SettingsStore.shared.snapshot
        let shared = SharedState.shared
        let staleContact = CACurrentMediaTime() - shared.lastFrameAt > 0.3
        if !settings.trackpadTapDragEnabled || staleContact || shared.buttonDown {
            releaseDragButtonIfNeeded()
        }

        postScrollPackets(scrollSequence.consume(x: scrollX, y: scrollY,
                                                   active: scrollGestureActive && !staleContact))

        // The first tap's click must be posted before the second touch's
        // mouse-down, even when both arrive within a single 120 Hz drain tick.
        if clickPending {
            SynthesizedClick.post(button: .left, clickCount: clickCount)
        }
        if rightClickPending {
            SynthesizedClick.post(button: .right)
        }
        if dragDownPending && !dragButtonPosted && settings.trackpadTapDragEnabled
            && !staleContact && !shared.buttonDown {
            dragButtonPosted = postDragButton(.leftMouseDown)
        }

        if dx != 0 || dy != 0 {
            if let current = CGEvent(source: nil)?.location {
                let target = CGPoint(x: current.x + dx, y: current.y + dy)
                let resolved = resolvedPosition(current: current, target: target)

                if let src = moveEventSource,
                   let move = CGEvent(
                        mouseEventSource: src,
                        mouseType: (dragButtonPosted || (settings.trackpadPressDragEnabled && shared.leftButtonDown))
                            ? .leftMouseDragged : .mouseMoved,
                        mouseCursorPosition: resolved,
                        mouseButton: .left
                   ) {
                    move.setIntegerValueField(.eventSourceUserData, value: SynthesizedClick.signature)
                    move.post(tap: .cghidEventTap)
                    if dragButtonPosted { lastDragLocation = resolved }
                }
            }
        }
        if dragUpPending { releaseDragButtonIfNeeded() }

        if togglePending {
            DispatchQueue.main.async { [weak self] in self?.toggle() }
        }
    }
}
