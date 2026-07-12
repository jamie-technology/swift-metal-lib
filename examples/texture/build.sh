#!/bin/bash
# Textures — the first *package*. Host support (ComputeContext.texture /
# dispatchTextures) is native and GPU-verified. The Swift-authored texture
# kernel needs compiler texture-type support (see docs/textures.md); until then
# the `invert` kernel is hand-authored in AIR (opaque `ptr addrspace(1)`
# textures, which the driver accepts via air.texture metadata) and assembled
# with metal-as/metallib — proving the whole pipeline + host path end-to-end.
set -euo pipefail
cd "$(dirname "$0")/../.."
xcrun metal-as examples/texture/invert.air.ll -o /tmp/invert.air
xcrun metallib  /tmp/invert.air -o examples/texture/texture.metallib
swift build >/dev/null
.build/debug/texture-example examples/texture/texture.metallib
