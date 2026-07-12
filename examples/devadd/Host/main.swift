// Host program for the `add` example. Loads the smc-compiled add.metallib,
// dispatches it over N elements, and checks the result against the CPU.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/devadd/devadd.metallib"

let n = 1 << 20  // 1,048,576 elements

let ctx = try ComputeContext(metallibPath: metallib)

let a = (0..<n).map { Float($0) }
let b = (0..<n).map { Float(2 * $0) }
let bufA = ctx.buffer(a)
let bufB = ctx.buffer(b)
let bufOut = ctx.buffer(count: n, of: Float.self)

try ctx.dispatch("devadd", buffers: [bufA, bufB, bufOut], count: n)

let out = bufOut.array(Float.self, count: n)
var mismatches = 0
for i in 0..<n where out[i] != a[i] + b[i] {
    if mismatches < 5 { print("  mismatch at \(i): \(out[i]) != \(a[i] + b[i])") }
    mismatches += 1
}

if mismatches == 0 {
    print("✅ devadd: GPU result matches CPU for all \(n) elements  (out[42] = \(out[42]))")
} else {
    print("❌ devadd: \(mismatches) mismatches")
    exit(1)
}
