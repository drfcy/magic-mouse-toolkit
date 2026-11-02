#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/physical-press-regression
cat Sources/EventInterceptor.swift > .build/physical-press-regression/main.swift
cat >> .build/physical-press-regression/main.swift <<'SWIFT'

extension EventInterceptor {
    func runPhysicalPressRegression() {
        magicMouseButtonSenders = [123]
        PhysicalPressRegression.run { type, event, sender in
            self.remapTrackpadRightPress(type: type, event: event, senderID: sender)
        }
    }
}
EventInterceptor.shared.runPhysicalPressRegression()
SWIFT
sources=()
for source in Sources/*.swift; do
    case "$source" in
        Sources/main.swift|Sources/EventInterceptor.swift) ;;
        *) sources+=("$source") ;;
    esac
done
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc "${sources[@]}" Tests/PhysicalPressRegression.swift .build/physical-press-regression/main.swift \
    -import-objc-header Sources/MultitouchBridge.h \
    -F /System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit \
    -target arm64-apple-macos26.0 -o .build/physical-press-regression/MMTPhysicalPressRegression
.build/physical-press-regression/MMTPhysicalPressRegression
