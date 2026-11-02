@main
struct TwoFingerTapRegression {
    static func main() {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }

        var tap = TwoFingerTapTracker()
        tap.begin(firstID: 1, firstX: 0.2, firstY: 0.5,
                  secondID: 2, secondX: 0.8, secondY: 0.5, at: 1)
        tap.update(firstID: 2, firstX: 0.802, firstY: 0.501,
                   secondID: 1, secondX: 0.201, secondY: 0.501)
        check(tap.finish(at: 1.12, maxDuration: 0.25, minFrames: 2),
              "A stationary tap should survive contact-order changes")
        check(!tap.isTracking, "Finish must reset tracking")

        var scroll = TwoFingerTapTracker()
        scroll.begin(firstID: 1, firstX: 0.2, firstY: 0.5,
                     secondID: 2, secondX: 0.8, secondY: 0.5, at: 2)
        scroll.update(firstID: 1, firstX: 0.2, firstY: 0.55,
                      secondID: 2, secondX: 0.8, secondY: 0.55)
        check(!scroll.finish(at: 2.12, maxDuration: 0.25, minFrames: 2),
              "A short two-finger scroll must not right-click")

        var held = TwoFingerTapTracker()
        held.begin(firstID: 1, firstX: 0.2, firstY: 0.5,
                   secondID: 2, secondX: 0.8, secondY: 0.5, at: 3)
        held.update(firstID: 1, firstX: 0.2, firstY: 0.5,
                    secondID: 2, secondX: 0.8, secondY: 0.5)
        check(!held.finish(at: 3.3, maxDuration: 0.25, minFrames: 2),
              "A held two-finger contact must not right-click")

        var replaced = TwoFingerTapTracker()
        replaced.begin(firstID: 1, firstX: 0.2, firstY: 0.5,
                       secondID: 2, secondX: 0.8, secondY: 0.5, at: 4)
        replaced.update(firstID: 1, firstX: 0.2, firstY: 0.5,
                        secondID: 3, secondX: 0.8, secondY: 0.5)
        check(!replaced.finish(at: 4.1, maxDuration: 0.25, minFrames: 2),
              "Replacing a finger must cancel the tap")

        print("PASS: \(checks) two-finger tap assertions")
    }
}
