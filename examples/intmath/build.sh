#!/bin/bash
# Build the integer-arithmetic kernel to a loadable .metallib in ONE command.
# Exercises Swift's overflow-checked integer operators (llvm.*.with.overflow +
# trap branches) whose !prof metadata the normalization pass strips.
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name intmath \
    examples/intmath/intmath.swift -o examples/intmath/intmath.metallib

swift build >/dev/null
.build/debug/intmath-example examples/intmath/intmath.metallib
