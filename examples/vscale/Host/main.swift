// Host for the `vscale` example: doubles each float4 and checks vs CPU.
import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/vscale/vscale.metallib"
let n = 1 << 18

let ctx = try ComputeContext(metallibPath: metallib)
let input = (0..<n).map { i in SIMD4<Float>(Float(i), Float(i) + 1, Float(i) + 2, Float(i) + 3) }
let bufIn = ctx.buffer(input)
let bufOut = ctx.buffer(count: n, of: SIMD4<Float>.self)

try ctx.dispatch("vscale", buffers: [bufIn, bufOut], count: n)

let out = bufOut.array(SIMD4<Float>.self, count: n)
var bad = 0
for i in 0..<n where out[i] != input[i] * 2 {
    if bad < 5 { print("  mismatch at \(i): \(out[i]) != \(input[i] * 2)") }
    bad += 1
}
if bad == 0 {
    print("✅ vscale: GPU float4 result matches CPU for all \(n) vectors  (out[42] = \(out[42]))")
} else { print("❌ vscale: \(bad) mismatches"); exit(1) }
