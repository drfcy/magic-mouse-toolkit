@main
struct CursorAccelerationRegression {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }

        var curve = CursorAcceleration()
        curve.reset(at: 0)
        var slow = 1.0
        for frame in 1...8 {
            slow = curve.multiplier(contactDX: 0.001, contactDY: 0,
                                    timestamp: Double(frame) / 120, strength: 1)
        }
        check(slow == 1, "Slow aiming must retain the base gain")

        curve.reset(at: 0)
        var fast = 1.0
        for frame in 1...8 {
            fast = curve.multiplier(contactDX: 0.015, contactDY: 0,
                                    timestamp: Double(frame) / 120, strength: 1)
        }
        check(fast > 1.5 && fast <= 2, "Sustained fast travel should accelerate smoothly")
        let braking = curve.multiplier(contactDX: 0.0001, contactDY: 0,
                                       timestamp: 9.0 / 120, strength: 1)
        check(braking == 1, "Slowing down must restore precision immediately")

        curve.reset(at: 0)
        var vertical = 1.0
        for frame in 1...8 {
            vertical = curve.multiplier(contactDX: 0, contactDY: 0.008,
                                        timestamp: Double(frame) / 120, strength: 1)
        }
        check(vertical > 1.5, "Fast travel along the long axis should also accelerate")

        curve.reset(at: 0)
        var jitter = 1.0
        for frame in 1...12 {
            jitter = curve.multiplier(contactDX: frame.isMultiple(of: 2) ? -0.018 : 0.018,
                                      contactDY: 0, timestamp: Double(frame) / 120, strength: 1)
        }
        check(jitter == 1, "Alternating contact-centre jitter must not accelerate")

        curve.reset(at: 0)
        _ = curve.multiplier(contactDX: 0, contactDY: 0, timestamp: 1.0 / 120, strength: 1)
        _ = curve.multiplier(contactDX: 0, contactDY: 0, timestamp: 2.0 / 120, strength: 1)
        let spike = curve.multiplier(contactDX: 0.08, contactDY: 0,
                                     timestamp: 3.0 / 120, strength: 1)
        check(spike == 1, "A single large contact jump must not trigger acceleration")

        curve.reset(at: 0)
        var disabled = 0.0
        for frame in 1...8 {
            disabled = curve.multiplier(contactDX: 0.015, contactDY: 0,
                                        timestamp: Double(frame) / 120, strength: 0)
        }
        check(disabled == 1, "Zero strength must restore linear cursor movement")

        curve.reset(at: 0)
        for frame in 1...4 {
            _ = curve.multiplier(contactDX: 0.015, contactDY: 0,
                                 timestamp: Double(frame) / 120, strength: 1)
        }
        let gap = curve.multiplier(contactDX: 0.015, contactDY: 0,
                                   timestamp: 1, strength: 1)
        check(gap == 1, "A paused contact stream must reset acceleration")

        print("PASS: \(checks) cursor acceleration assertions")
    }
}
