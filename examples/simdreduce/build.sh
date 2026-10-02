#!/bin/bash
# Build the simdreduce kernel (SIMD-group sum) — uses the SIMDGroup package.
set -euo pipefail
cd "$(dirname "$0")/../.."
SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"
"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name simdreduce \
    packages/SIMDGroup/SIMDGroup.swift examples/simdreduce/simdreduce.swift \
    -o examples/simdreduce/simdreduce.metallib
swift build >/dev/null
.build/debug/simdreduce-example examples/simdreduce/simdreduce.metallib
