// Host program for the `dvscale` example. Loads the compiler-produced
// dvscale.metallib, dispatches it over N SIMD4<Float> elements, and checks the
// result against the CPU.

import Foundation
import MetalSwift
import simd

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/dvscale/dvscale.metallib"

let n = 1 << 20  // 1,048,576 SIMD4<Float> vectors

let ctx = try ComputeContext(metallibPath: metallib)

let inp = (0..<n).map { i in
    SIMD4<Float>(Float(i), Float(i) + 0.25, Float(i) + 0.5, Float(i) + 0.75)
}
let bufIn = ctx.buffer(inp)
let bufOut = ctx.buffer(count: n, of: SIMD4<Float>.self)

try ctx.dispatch("dvscale", buffers: [bufIn, bufOut], count: n)

let out = bufOut.array(SIMD4<Float>.self, count: n)
var mismatches = 0
for i in 0..<n where out[i] != inp[i] * 2.0 {
    if mismatches < 5 { print("  mismatch at \(i): \(out[i]) != \(inp[i] * 2.0)") }
    mismatches += 1
}

if mismatches == 0 {
    print("✅ dvscale: GPU result matches CPU for all \(n) vectors  (out[42] = \(out[42]))")
} else {
    print("❌ dvscale: \(mismatches) mismatches")
    exit(1)
}
