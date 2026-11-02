#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/touch-scroll-regression
cat Sources/TrackpadModeController.swift > .build/touch-scroll-regression/main.swift
cat >> .build/touch-scroll-regression/main.swift <<'SWIFT'

extension TrackpadModeController {
    func runContactScrollRegression() {
        AppSettings.shared.registerDefaults()
        var settings = AppSettings.shared.makeSnapshot()
        settings.trackpadModeOrientation = 1
        settings.threeFingerTapEnabled = false
        var assertions = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value,message)
            assertions += 1
        }
        var time = CACurrentMediaTime()
        func frame(_ contacts: [(Int32,Float,Float)]) {
            time += 0.015
            let touches = contacts.map { id,x,y -> MTTouch in
                var touch = MTTouch()
                touch.identifier = id; touch.state = 4
                touch.normalized.position.x = x; touch.normalized.position.y = y
                return touch
            }
            accScrollX = 0; accScrollY = 0
            touches.withUnsafeBufferPointer {
                handleContactFrame(touches:$0,timestamp:time,settings:settings)
            }
        }
        frame([(1,0.3,0.4),(2,0.6,0.7)])
        check(accScrollX == 0 && accScrollY == 0, "Landing must not jump")
        frame([(2,0.58,0.7),(1,0.28,0.4)])
        check(abs(accScrollX) < 0.001 && accScrollY > 19 && accScrollGestureActive,
              "Physical upward motion with head right must reach the vertical accumulator")
        check(!twoFingerTap.isTracking, "A scrolling gesture must not later become a right click")
        frame([(1,0.27,0.4)])
        check(accScrollY > 9 && accScrollGestureActive, "Brief dropout must still reach the drain accumulator")
        check(accDX == 0 && accDY == 0, "A dropped finger must not resume cursor motion")
        frame([(1,0.26,0.4),(2,0.1,0.7)])
        check(accScrollY > 9 && accScrollY < 11, "A returning contact must not cause a large scroll")
        frame([(1,0.25,0.4),(2,0.09,0.7),(3,0.5,0.9)])
        check(!accScrollGestureActive && accScrollY == 0, "Three fingers must end software scrolling")
        frame([(1,0.24,0.4),(2,0.08,0.7)])
        frame([(1,0.21,0.4),(2,0.05,0.7)])
        check(!accScrollGestureActive && accScrollY == 0,
              "Lifting one of three fingers must not accidentally become a two-finger scroll")
        frame([])
        settings.trackpadModeOrientation = 0
        frame([(1,0.3,0.4),(2,0.6,0.7)])
        frame([(1,0.25,0.4),(2,0.55,0.7)])
        check(accScrollX == 0 && accScrollY == 0 && !accScrollGestureActive,
              "Upright scrolling must remain on the existing native path")
        frame([])
        settings.trackpadModeOrientation = 2
        frame([(1,0.3,0.4),(2,0.6,0.7)])
        frame([(1,0.32,0.4),(2,0.62,0.7)])
        check(abs(accScrollX) < 0.001 && accScrollY > 19,
              "Physical upward motion with head left must also scroll vertically")
        frame([])
        print("PASS: \(assertions) production contact-routing assertions; no drain timer, event tap or events posted.")
    }
}
TrackpadModeController.shared.runContactScrollRegression()
SWIFT
sources=()
for source in Sources/*.swift; do
    case "$source" in
        Sources/main.swift|Sources/TrackpadModeController.swift) ;;
        *) sources+=("$source") ;;
    esac
done
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc "${sources[@]}" .build/touch-scroll-regression/main.swift \
    -import-objc-header Sources/MultitouchBridge.h \
    -F /System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit \
    -target arm64-apple-macos26.0 -o .build/touch-scroll-regression/MMTContactScrollRegression
.build/touch-scroll-regression/MMTContactScrollRegression
