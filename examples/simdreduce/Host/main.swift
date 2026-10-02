import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/simdreduce/simdreduce.metallib"
let width = 32   // one Apple SIMD-group
let ctx = try ComputeContext(metallibPath: lib)
let input = (0..<width).map { Float($0 + 1) }        // 1, 2, …, 32
let bufIn = ctx.buffer(input)
let bufOut = ctx.buffer(count: width, of: Float.self)
// One threadgroup of 32 threads => exactly one SIMD-group covers the whole grid.
try ctx.dispatchThreadgroups("simdreduce", buffers: [bufIn, bufOut],
                             threadgroups: 1, threadsPerThreadgroup: width)
let got = bufOut.array(Float.self, count: width)
let expected = Float(width * (width + 1) / 2)         // 528
let ok = got.allSatisfy { $0 == expected }
print(ok ? "✅ simdreduce: every lane got the group sum \(expected)"
         : "❌ simdreduce: expected all \(expected), got \(got.prefix(4))…")
