#!/bin/bash
# Build the @Device add kernel to a loadable .metallib in ONE command — the
# compiler owns the whole pipeline (Swift -> AIR -> metal-as -> metallib), no smc.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library \
    examples/devadd/devadd.swift -o examples/devadd/devadd.metallib

swift build >/dev/null
.build/debug/devadd-example examples/devadd/devadd.metallib
