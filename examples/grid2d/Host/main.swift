// Host program for the `grid2d` example — 2-D dispatch over a 256×192 grid,
// verifying each thread's uint2 thread_position_in_grid via a matrix transpose.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/grid2d/grid2d.metallib"

let W = 256, H = 192
let ctx = try ComputeContext(metallibPath: metallib)

let inp = (0..<W * H).map { Float($0) }
let bufIn = ctx.buffer(inp)
let bufOut = ctx.buffer(count: W * H, of: Float.self)

try ctx.dispatch2D("grid2d", buffers: [bufOut, bufIn], width: W, height: H)

let out = bufOut.array(Float.self, count: W * H)
var mismatches = 0
for x in 0..<W {
    for y in 0..<H where out[y * W + x] != inp[x * H + y] {
        if mismatches < 5 { print("  mismatch at (\(x),\(y))") }
        mismatches += 1
    }
}

if mismatches == 0 {
    print("✅ grid2d: uint2 thread_position_in_grid correct — 256×192 transpose "
          + "matches for all \(W*H) threads")
} else {
    print("❌ grid2d: \(mismatches) mismatches")
    exit(1)
}
