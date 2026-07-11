#!/bin/bash
# Compile every example shader with smc and run its host on the GPU.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build

run() { # <name> <kernel>
  local name=$1 kernel=$2
  .build/debug/smc "examples/$name/$name.swift" --kernel "$kernel" -o "examples/$name/$name.metallib"
  ".build/debug/${name}-example" "examples/$name/$name.metallib"
}

run add    add
run vscale vscale
run indices indices
echo "— all examples passed —"
