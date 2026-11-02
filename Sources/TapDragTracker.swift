/// A first left tap arms a second, held touch for dragging. No cursor events
/// are emitted until the second touch has moved far enough to be intentional.
/// State is owned by the multitouch callback thread.
struct TapDragTracker {
    private enum Phase {
        case idle, armed, candidate, dragging
    }

    private var phase: Phase = .idle
    private var armedAt = 0.0
    private var travelX = 0.0
    private var travelY = 0.0

    var isCandidate: Bool { phase == .candidate }
    var isDragging: Bool { phase == .dragging }

    mutating func arm(afterLeftTapAt timestamp: Double) {
        phase = .armed
        armedAt = timestamp
        travelX = 0
        travelY = 0
    }

    /// The second touch may start anywhere on the surface; its screen cursor
    /// begins at the position of the first tap, as on a regular trackpad.
    mutating func begin(at timestamp: Double) -> Bool {
        let isSecondTouch = phase == .armed
            && timestamp >= armedAt
            && timestamp - armedAt <= 0.45
        phase = isSecondTouch ? .candidate : .idle
        travelX = 0
        travelY = 0
        return isSecondTouch
    }

    /// Returns true exactly once, when movement crosses the drag threshold.
    mutating func advance(contactDX: Double, contactDY: Double) -> Bool {
        guard phase == .candidate else { return false }
        // Approximate physical distance prevents the narrow axis from having
        // a larger effective activation threshold than the long axis.
        travelX += contactDX * 57.1
        travelY += contactDY * 113.5
        if travelX * travelX + travelY * travelY >= 1.0 {
            phase = .dragging
            return true
        }
        return false
    }

    /// Returns whether a synthetic mouse-up is required.
    mutating func end() -> Bool {
        let hadDrag = phase == .dragging
        phase = .idle
        travelX = 0
        travelY = 0
        return hadDrag
    }

    mutating func cancel() -> Bool { end() }
}
