#!/bin/bash
# Build the 2-D dispatch kernel (uint2 thread position) to a loadable .metallib.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name grid2d \
    examples/grid2d/grid2d.swift -o examples/grid2d/grid2d.metallib

swift build >/dev/null
.build/debug/grid2d-example examples/grid2d/grid2d.metallib
