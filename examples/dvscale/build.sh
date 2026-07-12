#!/bin/bash
# Build the @Device SIMD4 scale kernel to a loadable .metallib in ONE command —
# the compiler owns the whole pipeline (Swift -> AIR -> metal-as -> metallib).
# Exercises value-generic SIMD arithmetic on a value loaded from a device pointer.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name dvscale \
    examples/dvscale/dvscale.swift -o examples/dvscale/dvscale.metallib

swift build >/dev/null
.build/debug/dvscale-example examples/dvscale/dvscale.metallib
