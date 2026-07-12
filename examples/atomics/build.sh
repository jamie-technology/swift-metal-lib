#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name atomics \
    packages/Atomics/Atomics.swift examples/atomics/atomics.swift -o examples/atomics/atomics.metallib
swift build >/dev/null
.build/debug/atomics-example examples/atomics/atomics.metallib
