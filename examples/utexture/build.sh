#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name utexture \
    packages/Textures/Textures.swift examples/utexture/utexture.swift -o examples/utexture/utexture.metallib
swift build >/dev/null
.build/debug/utexture-example examples/utexture/utexture.metallib
