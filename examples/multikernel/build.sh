#!/bin/bash
# Build a module with two @Compute kernels into ONE metallib; the host
# dispatches each by name.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name multikernel \
    examples/multikernel/multikernel.swift -o examples/multikernel/multikernel.metallib

swift build >/dev/null
.build/debug/multikernel-example examples/multikernel/multikernel.metallib
