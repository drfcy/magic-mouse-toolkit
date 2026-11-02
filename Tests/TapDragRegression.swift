@main
struct TapDragRegression {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }

        var drag = TapDragTracker()
        check(!drag.begin(at: 0), "A first touch alone must not drag")
        drag.arm(afterLeftTapAt: 0.1)
        check(drag.begin(at: 0.3), "A timely second touch should be a candidate")
        check(drag.isCandidate && !drag.isDragging, "A second touch must not press immediately")
        check(!drag.advance(contactDX: 0.004, contactDY: 0), "Small jitter must not start dragging")
        check(drag.advance(contactDX: 0.015, contactDY: 0), "Intentional travel must start dragging")
        check(drag.isDragging && !drag.advance(contactDX: 0.015, contactDY: 0),
              "Mouse-down must happen only once")
        check(drag.end(), "Lifting after a drag requires mouse-up")

        drag.arm(afterLeftTapAt: 1)
        check(drag.begin(at: 1.2), "Second tap can still be recognized")
        check(!drag.end(), "A second tap without travel must remain a click")

        drag.arm(afterLeftTapAt: 2)
        check(!drag.begin(at: 2.6), "An unrelated later touch must not drag")
        check(!drag.end(), "Unarmed motion needs no mouse-up")

        drag.arm(afterLeftTapAt: 3)
        check(drag.begin(at: 3.2), "Drag candidate should begin")
        check(!drag.cancel(), "Cancelling before mouse-down needs no mouse-up")
        drag.arm(afterLeftTapAt: 4)
        check(drag.begin(at: 4.1), "Drag candidate should begin again")
        check(drag.advance(contactDX: 0, contactDY: 0.01), "Long-axis movement should start dragging")
        check(drag.cancel(), "Cancelling an active drag must release the mouse")

        print("PASS: \(checks) tap-drag assertions")
    }
}
