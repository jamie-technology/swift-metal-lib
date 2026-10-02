#!/bin/bash
# Build the triangle graphics pipeline (@Vertex + @Fragment) into a metallib
# with air.vertex / air.fragment entry points, then render + verify offscreen.
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name triangle \
    examples/triangle/triangle.swift \
    -o examples/triangle/triangle.metallib
swift build >/dev/null
.build/debug/triangle-example examples/triangle/triangle.metallib
