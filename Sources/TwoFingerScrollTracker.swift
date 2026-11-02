/// Recognizes translation only after the device has actually reported two
/// contacts. A large single contact is never guessed to be two fingers.
/// Owned exclusively by the multitouch callback; no event posting here.
struct TwoFingerScrollTracker {
    struct Contact {
        var id: Int32
        var x: Double
        var y: Double
    }

    private var first: Contact?
    private var second: Contact?
    private var lastAt: Double = -1e9
    private var lastPairAt: Double = -1e9
    private var survivingID: Int32?
    private var pendingX = 0.0
    private var pendingY = 0.0
    private(set) var isScrolling = false

    mutating func reset() { self = Self() }

    mutating func update(count: Int, first a: Contact?, second b: Contact?,
                         at time: Double) -> (x: Double, y: Double) {
        guard count == 1 || count == 2, let a else {
            reset()
            return (0, 0)
        }
        guard let oldA = first, let oldB = second, time > lastAt,
              time - lastAt < 0.15 else {
            reset()
            if count == 2, let b { first = a; second = b; lastPairAt = time; lastAt = time }
            return (0, 0)
        }

        var dx = 0.0
        var dy = 0.0
        if count == 2, let b {
            let nextA: Contact
            let nextB: Contact
            if a.id == oldA.id && b.id == oldB.id { nextA = a; nextB = b }
            else if b.id == oldA.id && a.id == oldB.id { nextA = b; nextB = a }
            else {
                // A replacement/merged contact can have a very different
                // center. Establish a new baseline instead of scrolling it.
                first = a; second = b; lastAt = time; lastPairAt = time
                survivingID = nil; pendingX = 0; pendingY = 0
                isScrolling = false
                return (0, 0)
            }
            if let survivingID {
                if time - lastPairAt <= 0.09 {
                    // Use the finger that stayed visible. The returning
                    // finger's location must not produce a catch-up jump.
                    let old = survivingID == oldA.id ? oldA : oldB
                    let next = survivingID == oldA.id ? nextA : nextB
                    dx = next.x - old.x; dy = next.y - old.y
                }
            } else {
                dx = ((nextA.x - oldA.x) + (nextB.x - oldB.x)) / 2
                dy = ((nextA.y - oldA.y) + (nextB.y - oldB.y)) / 2
            }
            first = nextA; second = nextB
            lastPairAt = time; lastAt = time; survivingID = nil
        } else {
            // Only an already-moving, confirmed two-finger gesture may bridge
            // a brief dropout. A one-finger stroke cannot start scrolling.
            guard isScrolling, time - lastPairAt <= 0.09,
                  a.id == oldA.id || a.id == oldB.id else {
                survivingID = a.id == oldA.id || a.id == oldB.id ? a.id : nil
                first = nil; second = nil
                isScrolling = false; pendingX = 0; pendingY = 0
                return (0, 0)
            }
            if a.id == oldA.id {
                dx = a.x - oldA.x; dy = a.y - oldA.y; first = a
            } else {
                dx = a.x - oldB.x; dy = a.y - oldB.y; second = a
            }
            lastAt = time; survivingID = a.id
        }

        // Reject a discontinuous sensor jump, keeping the new baseline.
        guard abs(dx) <= 0.15, abs(dy) <= 0.15 else { return (0, 0) }
        if !isScrolling {
            pendingX += dx; pendingY += dy
            // Physical rather than normalized distance: a slow stroke still
            // engages, while tiny contact-center fluctuations do not scroll.
            let mmX = pendingX * 57.1
            let mmY = pendingY * 113.5
            guard mmX * mmX + mmY * mmY >= 0.5 * 0.5 else { return (0, 0) }
            isScrolling = true
            let result = (x: pendingX, y: pendingY)
            pendingX = 0; pendingY = 0
            return result
        }
        return (dx, dy)
    }
}

/// Produces one explicit began/changed/ended sequence, with subpixel carry
/// confined to that gesture. Owned exclusively by the event drain queue.
struct TouchScrollSequence {
    struct Packet {
        var x: Int32
        var y: Int32
        var phase: Int64
    }
    private var remainderX = 0.0
    private var remainderY = 0.0
    private var didBegin = false

    mutating func consume(x: Double, y: Double, active: Bool) -> [Packet] {
        remainderX += x; remainderY += y
        let stepX = Int32(remainderX.rounded(.towardZero))
        let stepY = Int32(remainderY.rounded(.towardZero))
        remainderX -= Double(stepX); remainderY -= Double(stepY)
        var packets: [Packet] = []
        if stepX != 0 || stepY != 0 {
            packets.append(Packet(x: stepX, y: stepY, phase: didBegin ? 2 : 1))
            didBegin = true
        }
        if !active {
            if didBegin { packets.append(Packet(x: 0, y: 0, phase: 4)) }
            self = Self()
        }
        return packets
    }
}
