// Host program for the `intmath` example. Verifies integer arithmetic (with
// Swift's overflow-checked operators) runs correctly on the GPU.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/intmath/intmath.metallib"

let n = 1 << 20

let ctx = try ComputeContext(metallibPath: metallib)

let a = (0..<n).map { Int32($0 % 1000) }   // small values: no real overflow
let bufA = ctx.buffer(a)
let bufOut = ctx.buffer(count: n, of: Int32.self)

try ctx.dispatch("intmath", buffers: [bufA, bufOut], count: n)

let out = bufOut.array(Int32.self, count: n)
var mismatches = 0
for i in 0..<n where out[i] != a[i] * 3 + 7 {
    if mismatches < 5 { print("  mismatch at \(i): \(out[i]) != \(a[i] * 3 + 7)") }
    mismatches += 1
}

if mismatches == 0 {
    print("✅ intmath: GPU result matches CPU for all \(n) elements  (out[10] = \(out[10]))")
} else {
    print("❌ intmath: \(mismatches) mismatches")
    exit(1)
}
