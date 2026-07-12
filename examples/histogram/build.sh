#!/bin/bash
# Build the histogram kernel (atomic increments) — uses the Atomics package.
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name histogram \
    packages/Atomics/Atomics.swift examples/histogram/histogram.swift \
    -o examples/histogram/histogram.metallib
swift build >/dev/null
.build/debug/histogram-example examples/histogram/histogram.metallib
