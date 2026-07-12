#!/bin/bash
# Build the constant-data kernel to a loadable .metallib in ONE command. The
# program-scope `InlineArray` lookup table is baked into the module and read
# from MSL constant memory (addrspace 2).
set -euo pipefail
cd "$(dirname "$0")/../.."

SWIFT_FRONTEND="${SWIFT_GPU_SWIFTC:-$HOME/Developer/swift-gpu-fork/build/Ninja-RelWithDebInfoAssert+swift-DebugAssert/swift-macosx-arm64/bin/swiftc}"
SWIFT_FRONTEND="${SWIFT_FRONTEND%swiftc}swift-frontend"

"$SWIFT_FRONTEND" -emit-metallib -O -parse-as-library -module-name constdata \
    examples/constdata/constdata.swift -o examples/constdata/constdata.metallib

swift build >/dev/null
.build/debug/constdata-example examples/constdata/constdata.metallib
