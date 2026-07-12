#!/bin/bash
# Build the indices kernel to a loadable .metallib in ONE command — the compiler
# owns the whole pipeline (Swift -> AIR -> metal-as -> metallib), no smc.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name indices \
    examples/indices/indices.swift -o examples/indices/indices.metallib

swift build >/dev/null
.build/debug/indices-example examples/indices/indices.metallib
