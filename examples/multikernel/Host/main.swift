// Host program for the `multikernel` example. Loads one metallib and dispatches
// two different kernels (`scale2` and `negate`) from it.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/multikernel/multikernel.metallib"

let n = 1 << 20
let ctx = try ComputeContext(metallibPath: metallib)

let a = (0..<n).map { Float($0) }
let bufA = ctx.buffer(a)

// Kernel 1: scale2
let outScale = ctx.buffer(count: n, of: Float.self)
try ctx.dispatch("scale2", buffers: [bufA, outScale], count: n)
let scaled = outScale.array(Float.self, count: n)

// Kernel 2: negate
let outNeg = ctx.buffer(count: n, of: Float.self)
try ctx.dispatch("negate", buffers: [bufA, outNeg], count: n)
let negated = outNeg.array(Float.self, count: n)

var mismatches = 0
for i in 0..<n {
    if scaled[i] != a[i] * 2.0 { mismatches += 1 }
    if negated[i] != -a[i] { mismatches += 1 }
}

if mismatches == 0 {
    print("✅ multikernel: both kernels dispatched from one metallib correctly "
          + "(scale2[3] = \(scaled[3]), negate[3] = \(negated[3]))")
} else {
    print("❌ multikernel: \(mismatches) mismatches")
    exit(1)
}
