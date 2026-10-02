#!/bin/bash
# Build the sgemm kernel (8x8 simdgroup-matrix multiply) — uses the
# SIMDGroupMatrix package.
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name sgemm \
    packages/SIMDGroupMatrix/SIMDGroupMatrix.swift examples/sgemm/sgemm.swift \
    -o examples/sgemm/sgemm.metallib
swift build >/dev/null
.build/debug/sgemm-example examples/sgemm/sgemm.metallib
