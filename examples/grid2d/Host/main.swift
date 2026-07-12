// Host program for the `grid2d` example — 2-D dispatch over a W×H grid. Each
// thread computes its flat index from a device-loaded width and writes a value
// derived from its uint2 position.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/grid2d/grid2d.metallib"

let W = 256, H = 192
let ctx = try ComputeContext(metallibPath: metallib)

let out = ctx.buffer(count: W * H, of: UInt32.self)
let dims = ctx.buffer([UInt32(W), UInt32(H)])

try ctx.dispatch2D("grid2d", buffers: [out, dims], width: W, height: H)

let got = out.array(UInt32.self, count: W * H)
var mismatches = 0
for y in 0..<H {
    for x in 0..<W where got[y * W + x] != UInt32(x) &* 1000 &+ UInt32(y) {
        if mismatches < 5 { print("  mismatch at (\(x),\(y)): \(got[y*W+x])") }
        mismatches += 1
    }
}

if mismatches == 0 {
    print("✅ grid2d: uint2 dispatch + device-scalar arithmetic correct for all "
          + "\(W*H) threads  (out[1,2] = \(got[2*W+1]))")
} else {
    print("❌ grid2d: \(mismatches) mismatches")
    exit(1)
}
