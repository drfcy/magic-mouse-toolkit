import Foundation

/// Raises cursor gain only for sustained, directional one-finger travel.
/// The four fixed samples avoid allocation in the multitouch callback.
struct CursorAcceleration {
    private var lastTimestamp: Double?
    private var x0 = 0.0, y0 = 0.0, t0 = 0.0
    private var x1 = 0.0, y1 = 0.0, t1 = 0.0
    private var x2 = 0.0, y2 = 0.0, t2 = 0.0
    private var x3 = 0.0, y3 = 0.0, t3 = 0.0
    private var sampleCount = 0
    private var appliedMultiplier = 1.0

    mutating func reset(at timestamp: Double? = nil) {
        lastTimestamp = timestamp
        x0 = 0; y0 = 0; t0 = 0
        x1 = 0; y1 = 0; t1 = 0
        x2 = 0; y2 = 0; t2 = 0
        x3 = 0; y3 = 0; t3 = 0
        sampleCount = 0
        appliedMultiplier = 1
    }

    /// Contact deltas are normalized to the surface; approximate physical
    /// dimensions keep speed comparable along the mouse's narrow and long axes.
    mutating func multiplier(contactDX: Double, contactDY: Double,
                             timestamp: Double, strength: Double) -> Double {
        guard timestamp.isFinite, contactDX.isFinite, contactDY.isFinite else {
            reset()
            return 1
        }
        guard strength > 0 else {
            reset(at: timestamp)
            return 1
        }
        guard let previous = lastTimestamp else {
            reset(at: timestamp)
            return 1
        }
        let dt = timestamp - previous
        guard dt > 0, dt <= 0.08 else {
            reset(at: timestamp)
            return 1
        }
        lastTimestamp = timestamp

        let dx = contactDX * 57.1  // approximate Magic Mouse width, mm
        let dy = contactDY * 113.5 // approximate Magic Mouse length, mm
        x3 = x2; y3 = y2; t3 = t2
        x2 = x1; y2 = y1; t2 = t1
        x1 = x0; y1 = y0; t1 = t0
        x0 = dx; y0 = dy; t0 = dt
        sampleCount = min(4, sampleCount + 1)

        // Precision must return as soon as the finger slows, even while the
        // recent window still contains fast-travel samples.
        if hypot(dx, dy) / dt < 25 {
            appliedMultiplier = 1
            return 1
        }

        let net = hypot(x0 + x1 + x2 + x3, y0 + y1 + y2 + y3)
        let path = hypot(x0, y0) + hypot(x1, y1) + hypot(x2, y2) + hypot(x3, y3)
        let duration = t0 + t1 + t2 + t3
        var target = 1.0
        let largestStep = max(hypot(x0, y0), hypot(x1, y1), hypot(x2, y2), hypot(x3, y3))
        if sampleCount >= 3, net >= 1.2, duration > 0, path > 0,
           largestStep < path * 0.75 {
            let speed = net / duration // mm/s, using net rather than jitter path
            let coherence = net / path
            let speedFraction = min(1, max(0, (speed - 25) / 95))
            let directionFraction = min(1, max(0, (coherence - 0.7) / 0.25))
            let smoothSpeed = speedFraction * speedFraction * (3 - 2 * speedFraction)
            target += min(2, strength) * smoothSpeed * directionFraction
        }

        // Low-speed response remains immediate. Only the extra fast-travel gain
        // is eased, with a quicker return to 1 when the finger slows down.
        let response = target > appliedMultiplier ? 0.55 : 0.8
        appliedMultiplier += (target - appliedMultiplier) * response
        return appliedMultiplier
    }
}
