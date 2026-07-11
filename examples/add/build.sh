#!/bin/bash
# Build and run the `add` example end-to-end:
#   Swift shader  --smc-->  add.metallib  --host-->  GPU result
set -euo pipefail
cd "$(dirname "$0")/../.."

swift build
.build/debug/smc examples/add/add.swift --kernel add --emit-air -o examples/add/add.metallib
.build/debug/add-example examples/add/add.metallib
