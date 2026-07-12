#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name texture3d \
    packages/Textures/Textures.swift examples/texture3d/scale3d.swift -o examples/texture3d/texture3d.metallib
swift build >/dev/null
.build/debug/texture3d-example examples/texture3d/texture3d.metallib
