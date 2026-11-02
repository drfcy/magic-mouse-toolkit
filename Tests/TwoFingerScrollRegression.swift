@main
struct TwoFingerScrollRegression {
    static func main() {
        typealias Contact = TwoFingerScrollTracker.Contact
        var assertions = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            assertions += 1
        }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.000001 }
        func contact(_ id: Int32, _ x: Double, _ y: Double = 0.5) -> Contact {
            Contact(id: id, x: x, y: y)
        }
        var tracker = TwoFingerScrollTracker()
        // The first observed failure: all reported frames contained one blob.
        for index in 0..<100 {
            let delta = tracker.update(count: 1, first: contact(1,Double(index)/200),
                                       second: nil, at: Double(index)/60)
            check(delta.x == 0 && delta.y == 0 && !tracker.isScrolling,
                  "A single reported contact must never be invented into a scroll gesture")
        }

        let start = tracker.update(count: 2, first: contact(1,0.3), second: contact(2,0.6), at: 2)
        check(start.x == 0 && !tracker.isScrolling, "Finger landing must establish a baseline")
        let jitter = tracker.update(count: 2, first: contact(2,0.601), second: contact(1,0.301), at: 2.015)
        check(jitter.x == 0 && !tracker.isScrolling, "Submillimeter contact fluctuations must not start scrolling")
        let motion = tracker.update(count: 2, first: contact(2,0.612), second: contact(1,0.312), at: 2.030)
        check(near(motion.x,0.012) && tracker.isScrolling,
              "Slow motion must accumulate past the threshold without losing distance; order does not matter")

        let dropout = tracker.update(count: 1, first: contact(1,0.322), second: nil, at: 2.045)
        check(near(dropout.x,0.010) && tracker.isScrolling,
              "A known surviving finger may bridge a brief confirmed-scroll dropout")
        let returned = tracker.update(count: 2, first: contact(1,0.332), second: contact(2,0.8), at: 2.060)
        check(near(returned.x,0.010), "Returning finger must rebase instead of causing a centroid jump")
        let resumed = tracker.update(count: 2, first: contact(1,0.342), second: contact(2,0.81), at: 2.075)
        check(near(resumed.x,0.010), "A resumed pair must continue at its actual speed")
        let expired = tracker.update(count: 1, first: contact(1,0.4), second: nil, at: 2.180)
        check(expired.x == 0 && !tracker.isScrolling, "A prolonged one-finger contact must stop scrolling")

        _ = tracker.update(count: 2, first: contact(1,0.3), second: contact(2,0.6), at: 3)
        _ = tracker.update(count: 2, first: contact(1,0.32), second: contact(2,0.62), at: 3.015)
        let replaced = tracker.update(count: 2, first: contact(3,0.1), second: contact(4,0.8), at: 3.030)
        check(replaced.x == 0 && replaced.y == 0, "New contact identities must never jump between centroids")
        let lift = tracker.update(count: 0, first: nil, second: nil, at: 3.045)
        check(lift.x == 0 && !tracker.isScrolling, "All-finger release must end tracking immediately")
        _ = tracker.update(count: 2, first: contact(1,0.3), second: contact(2,0.6), at: 4)
        _ = tracker.update(count: 2, first: contact(1,0.32), second: contact(2,0.62), at: 4.015)
        let three = tracker.update(count: 3, first: contact(1,0.4), second: contact(2,0.7), at: 4.030)
        check(three.x == 0 && !tracker.isScrolling, "Three-finger input must cancel the two-finger tracker")

        var sequence = TouchScrollSequence()
        check(sequence.consume(x:0.4,y:0.3,active:true).isEmpty, "Fractional motion must carry forward")
        let began = sequence.consume(x:0.7,y:0.8,active:true)
        check(began.count == 1 && began[0].phase == 1 && began[0].x == 1 && began[0].y == 1,
              "First actual motion must begin a pixel-scroll sequence")
        check(sequence.consume(x:0,y:0,active:true).isEmpty, "A short pause must not end or repeat scrolling")
        let changed = sequence.consume(x:0,y:-4,active:true)
        check(changed.count == 1 && changed[0].phase == 2 && changed[0].y == -3,
              "Further movement must preserve fractional carry and direction")
        let ended = sequence.consume(x:0,y:0,active:false)
        check(ended.count == 1 && ended[0].phase == 4 && ended[0].x == 0 && ended[0].y == 0,
              "Release must post exactly one zero-delta end phase")
        check(sequence.consume(x:0,y:0,active:false).isEmpty, "No duplicate end events after teardown")
        check(sequence.consume(x:0.8,y:0,active:true).isEmpty, "Subpixel remainder must not leak to a new gesture")
        let quick = sequence.consume(x:1,y:0,active:false)
        check(quick.count == 2 && quick[0].phase == 1 && quick[1].phase == 4,
              "A gesture released before drain must still begin and end in order")
        print("PASS: \(assertions) continuous two-finger scroll assertions; no input events posted.")
    }
}
