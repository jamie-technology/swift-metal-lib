// Host program for the `constdata` example. Loads the compiler-produced
// constdata.metallib, dispatches it over N elements, and checks the result
// against the CPU — where the same gain table lives.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/constdata/constdata.metallib"

let n = 1 << 20
let gain: [Float] = [1, 2, 4, 8, 16, 32, 64, 128]

let ctx = try ComputeContext(metallibPath: metallib)

let inp = (0..<n).map { Float($0) }
let bufIn = ctx.buffer(inp)
let bufOut = ctx.buffer(count: n, of: Float.self)

try ctx.dispatch("constdata", buffers: [bufIn, bufOut], count: n)

let out = bufOut.array(Float.self, count: n)
var mismatches = 0
for i in 0..<n where out[i] != inp[i] * gain[i % 8] {
    if mismatches < 5 { print("  mismatch at \(i): \(out[i]) != \(inp[i] * gain[i % 8])") }
    mismatches += 1
}

if mismatches == 0 {
    print("✅ constdata: GPU result matches CPU for all \(n) elements  (out[10] = \(out[10]))")
} else {
    print("❌ constdata: \(mismatches) mismatches")
    exit(1)
}
