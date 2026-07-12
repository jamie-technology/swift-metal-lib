#!/bin/bash
# Build the Swift-authored texture `invert` kernel to a metallib. The Textures
# package (packages/Textures/Textures.swift) provides the texture types; the
# compiler lowers them to air.texture arguments (see docs/textures.md).
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name texture \
    packages/Textures/Textures.swift examples/texture/invert.swift \
    -o examples/texture/texture.metallib

swift build >/dev/null
.build/debug/texture-example examples/texture/texture.metallib
