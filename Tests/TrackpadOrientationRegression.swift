@main
struct TrackpadOrientationRegression {
    static func main() {
        var assertions = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            assertions += 1
        }

        let upright = TrackpadModeOrientation.upright
        let right = TrackpadModeOrientation.narrowEndRight
        let left = TrackpadModeOrientation.narrowEndLeft

        let original = upright.rotated(x: 3.0, y: -4.0)
        check(original.x == 3 && original.y == -4, "Upright movement must be unchanged")

        let forwardRight = right.rotated(x: 0.0, y: -100.0)
        check(forwardRight.x == 100 && forwardRight.y == 0,
              "With the narrow end on the right, a swipe toward it must move the cursor right")
        let acrossRight = right.rotated(x: 100.0, y: 0.0)
        check(acrossRight.x == 0 && acrossRight.y == 100,
              "The mouse's right edge points down when its narrow end points right")

        let forwardLeft = left.rotated(x: 0.0, y: -100.0)
        check(forwardLeft.x == -100 && forwardLeft.y == 0,
              "With the narrow end on the left, a swipe toward it must move the cursor left")
        let acrossLeft = left.rotated(x: 100.0, y: 0.0)
        check(acrossLeft.x == 0 && acrossLeft.y == -100,
              "The mouse's right edge points up when its narrow end points left")

        let oldRight = right.cursorDelta(x: 40, y: -20, sidewaysAspectRatio: 1)
        check(oldRight.x == 20 && oldRight.y == 40,
              "Aspect ratio 1 must preserve previous sideways cursor movement")
        let correctedRight = right.cursorDelta(x: 40, y: -20, sidewaysAspectRatio: 2)
        check(abs((correctedRight.x / correctedRight.y) / (oldRight.x / oldRight.y) - 2) < 0.000001,
              "Aspect ratio 2 must double horizontal versus vertical cursor travel")
        let correctedLeft = left.cursorDelta(x: 40, y: -20, sidewaysAspectRatio: 2)
        check(abs(correctedLeft.x) == abs(correctedRight.x)
                  && abs(correctedLeft.y) == abs(correctedRight.y),
              "Both sideways orientations need the same aspect correction")
        let unchangedUpright = upright.cursorDelta(x: 40, y: -20, sidewaysAspectRatio: 2)
        check(unchangedUpright.x == 40 && unchangedUpright.y == -20,
              "Sideways aspect setting must not alter upright movement")

        let scrollUpRight = right.scrollDelta(contactDX: -0.05, contactDY: 0, gain: 1000)
        check(scrollUpRight.x == 0 && scrollUpRight.y > 0,
              "A physical upward two-finger stroke must produce vertical scrolling, narrow end right")
        let scrollUpLeft = left.scrollDelta(contactDX: 0.05, contactDY: 0, gain: 1000)
        check(scrollUpLeft.x == 0 && scrollUpLeft.y > 0,
              "A physical upward two-finger stroke must produce vertical scrolling, narrow end left")
        let scrollSideRight = right.scrollDelta(contactDX: 0, contactDY: 0.05, gain: 1000)
        check(scrollSideRight.y == 0 && scrollSideRight.x < 0,
              "A stroke toward the narrow end must produce horizontal scrolling")

        print("PASS: \(assertions) orientation assertions; no cursor events posted.")
    }
}
