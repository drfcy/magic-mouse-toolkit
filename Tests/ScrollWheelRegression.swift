import CoreGraphics
import Foundation
import QuartzCore

enum ScrollWheelRegression {
    static func run(_ handle: (CGEvent) -> Unmanaged<CGEvent>?) {
        AppSettings.shared.registerDefaults()
        // Registration defaults are in-memory only; do not change app preferences.
        UserDefaults.standard.register(defaults: [AppSettings.Key.verticalScrollOnly: true])
        let shared = SharedState.shared
        var assertions = 0

        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            assertions += 1
        }

        func reset() {
            shared.trackpadModeActive = true
            shared.fingerCount = 0
            shared.lastFrameAt = -1e9
            shared.builtInTrackpadFingerCount = 0
            shared.builtInTrackpadLastFrameAt = -1e9
            shared.trackpadScrollPassthrough = false
            shared.trackpadMomentumEligibleUntil = -1e9
            shared.trackpadScrollOwner = 0
            shared.lastScrollAt = -1e9
            shared.momentumActive = false
        }

        func scroll(_ units: CGScrollEventUnit, _ vertical: Int32, _ horizontal: Int32) -> CGEvent {
            CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                    wheel1: vertical, wheel2: horizontal, wheel3: 0)!
        }

        // Ordinary wheels must work with either mode, in both directions and axes.
        for active in [false, true] {
            for vertical: Int32 in [-3, 3] {
                reset()
                shared.trackpadModeActive = active
                let event = scroll(.line, vertical, 2)
                let fields: [CGEventField] = [
                    .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                    .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
                    .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2
                ]
                let before = fields.map { event.getDoubleValueField($0) }
                check(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
                      "Test fixture must represent a discrete wheel")
                check(handle(event) != nil, "Ordinary wheel must not be swallowed")
                check(fields.map { event.getDoubleValueField($0) } == before,
                      "Ordinary wheel deltas must remain unchanged, including horizontal")
                check(shared.lastScrollAt == -1e9,
                      "Another mouse must not update Magic Mouse scroll timing")
            }
        }

        // Interleaving a wheel must not reset an ongoing Magic Mouse gesture.
        reset()
        shared.trackpadScrollPassthrough = true
        shared.trackpadMomentumEligibleUntil = 123
        shared.trackpadScrollOwner = 1
        shared.momentumActive = true
        check(handle(scroll(.line, 1, 0)) != nil, "Interleaved wheel must pass")
        check(shared.trackpadScrollPassthrough && shared.trackpadScrollOwner == 1
              && shared.trackpadMomentumEligibleUntil == 123 && shared.momentumActive,
              "Interleaved wheel must not alter the active touch-scroll sequence")

        // BetterTouchTool turns this USB wheel into continuous injected scrolls.
        // These must pass without becoming a Magic Mouse gesture or losing an
        // existing gesture's momentum state.
        reset()
        shared.trackpadScrollPassthrough = true
        shared.trackpadMomentumEligibleUntil = 123
        shared.trackpadScrollOwner = 1
        shared.momentumActive = true
        let smoothedWheel = scroll(.pixel, -4, 3)
        smoothedWheel.setIntegerValueField(.eventSourceUnixProcessID, value: 5104)
        smoothedWheel.setIntegerValueField(.eventSourceUserData, value: 0x4d4d4741)
        let smoothedFields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2
        ]
        let smoothedBefore = smoothedFields.map { smoothedWheel.getDoubleValueField($0) }
        check(smoothedWheel.getIntegerValueField(.scrollWheelEventIsContinuous) == 1,
              "Smoothed wheel fixture must be continuous")
        check(smoothedWheel.getIntegerValueField(.eventSourceUnixProcessID) == 5104,
              "Smoothed wheel fixture must preserve its source PID")
        check(handle(smoothedWheel) != nil, "Injected continuous wheel must pass")
        check(smoothedFields.map { smoothedWheel.getDoubleValueField($0) } == smoothedBefore,
              "Injected continuous wheel deltas must remain unchanged")
        check(shared.trackpadScrollPassthrough && shared.trackpadScrollOwner == 1
              && shared.trackpadMomentumEligibleUntil == 123 && shared.momentumActive
              && shared.lastScrollAt == -1e9,
              "Injected wheel must not alter Magic Mouse scroll state")

        // The one-finger touch-scroll suppression must still work.
        reset()
        shared.fingerCount = 1
        shared.lastFrameAt = CACurrentMediaTime()
        check(handle(scroll(.pixel, 12, 0)) == nil,
              "One-finger continuous scrolling must remain suppressed in trackpad mode")

        // Two-finger Magic Mouse and built-in trackpad scrolling must still pass.
        for owner in [1, 2] {
            reset()
            if owner == 1 {
                shared.fingerCount = 2
                shared.lastFrameAt = CACurrentMediaTime()
            } else {
                shared.builtInTrackpadFingerCount = 2
                shared.builtInTrackpadLastFrameAt = CACurrentMediaTime()
            }
            let event = scroll(.pixel, 12, 4)
            check(handle(event) != nil, "Recognized two-finger scroll must pass")
            check(shared.trackpadScrollOwner == owner, "Touch-scroll owner must be retained")
            check(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0,
                  "Existing horizontal-scroll setting must still apply to touch scrolling")
            shared.fingerCount = 0
            shared.builtInTrackpadFingerCount = 0
            let end = scroll(.pixel, 0, 0)
            end.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
            check(handle(end) != nil, "Touch-scroll end must pass")
            let momentum = scroll(.pixel, 6, 0)
            momentum.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
            check(handle(momentum) != nil, "Momentum following recognized touch scroll must pass")
        }

        reset()
        shared.trackpadModeActive = false
        check(handle(scroll(.pixel, 12, 0)) != nil,
              "Continuous scrolling must pass when trackpad mode is off")
        print("PASS: \(assertions) scroll regression assertions; no events posted or input taps installed.")
    }
}
