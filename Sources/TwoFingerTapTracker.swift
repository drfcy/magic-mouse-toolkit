/// Tracks a two-finger tap without depending on touch position or mouse orientation.
/// Only the Multitouch callback mutates this value.
struct TwoFingerTapTracker {
    private(set) var isTracking = false
    private var firstID: Int32 = 0
    private var secondID: Int32 = 0
    private var startAt: Double = 0
    private var firstStart = (x: 0.0, y: 0.0)
    private var secondStart = (x: 0.0, y: 0.0)
    private var firstLast = (x: 0.0, y: 0.0)
    private var secondLast = (x: 0.0, y: 0.0)
    private var maxStraight = 0.0
    private var path = 0.0
    private var frames = 0

    mutating func begin(firstID: Int32, firstX: Double, firstY: Double,
                        secondID: Int32, secondX: Double, secondY: Double,
                        at time: Double) {
        isTracking = true
        self.firstID = firstID
        self.secondID = secondID
        startAt = time
        firstStart = (firstX, firstY)
        secondStart = (secondX, secondY)
        firstLast = firstStart
        secondLast = secondStart
        maxStraight = 0
        path = 0
        frames = 1
    }

    mutating func update(firstID: Int32, firstX: Double, firstY: Double,
                         secondID: Int32, secondX: Double, secondY: Double) {
        guard isTracking else { return }
        let first: (x: Double, y: Double)
        let second: (x: Double, y: Double)
        if firstID == self.firstID && secondID == self.secondID {
            first = (firstX, firstY)
            second = (secondX, secondY)
        } else if firstID == self.secondID && secondID == self.firstID {
            first = (secondX, secondY)
            second = (firstX, firstY)
        } else {
            cancel()
            return
        }
        func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }
        maxStraight = max(maxStraight, distance(first, firstStart), distance(second, secondStart))
        path += max(distance(first, firstLast), distance(second, secondLast))
        firstLast = first
        secondLast = second
        frames += 1
    }

    mutating func finish(at time: Double, maxDuration: Double, minFrames: Int) -> Bool {
        defer { cancel() }
        return isTracking
            && time - startAt <= maxDuration
            && frames >= minFrames
            && maxStraight <= 0.035
            && path <= 0.05
    }

    mutating func cancel() {
        isTracking = false
        frames = 0
    }
}
