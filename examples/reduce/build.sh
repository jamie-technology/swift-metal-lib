#!/bin/bash
# Build the threadgroup-reduction kernel (shared memory + barrier) to a metallib.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name reduce \
    examples/reduce/reduce.swift -o examples/reduce/reduce.metallib

swift build >/dev/null
.build/debug/reduce-example examples/reduce/reduce.metallib
