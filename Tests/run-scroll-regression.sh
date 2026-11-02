#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/scroll-regression
# Keep the production fileprivate handler accessible without changing its visibility.
cat Sources/EventInterceptor.swift > .build/scroll-regression/main.swift
cat >> .build/scroll-regression/main.swift <<'SWIFT'

ScrollWheelRegression.run { event in
    EventInterceptor.shared.handle(type: .scrollWheel, event: event)
}
SWIFT
sources=()
for source in Sources/*.swift; do
    case "$source" in
        Sources/main.swift|Sources/EventInterceptor.swift) ;;
        *) sources+=("$source") ;;
    esac
done
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc "${sources[@]}" Tests/ScrollWheelRegression.swift .build/scroll-regression/main.swift \
    -import-objc-header Sources/MultitouchBridge.h \
    -F /System/Library/PrivateFrameworks -framework MultitouchSupport \
    -framework AppKit -framework SwiftUI -framework QuartzCore -framework IOKit \
    -target arm64-apple-macos26.0 -o .build/scroll-regression/MMTScrollRegression
.build/scroll-regression/MMTScrollRegression
