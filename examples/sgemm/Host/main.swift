import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/sgemm/sgemm.metallib"
let ctx = try ComputeContext(metallibPath: lib)
// A = 8x8 identity, B[i] = i  =>  C = A·B = B
var A = [Float](repeating: 0, count: 64)
for i in 0..<8 { A[i*8 + i] = 1 }
let B = (0..<64).map { Float($0) }
let bA = ctx.buffer(A), bB = ctx.buffer(B), bC = ctx.buffer(count: 64, of: Float.self)
// One SIMD-group (32 threads) cooperatively computes the 8x8 tile.
try ctx.dispatchThreadgroups("sgemm", buffers: [bA, bB, bC],
                             threadgroups: 1, threadsPerThreadgroup: 32)
let C = bC.array(Float.self, count: 64)
let ok = zip(C, B).allSatisfy { abs($0 - $1) < 1e-4 }
print(ok ? "✅ sgemm: C = I·B = B via simdgroup_matrix (C[0..4]=\(Array(C.prefix(4))))"
         : "❌ sgemm: C[0..8]=\(Array(C.prefix(8))) expected \(Array(B.prefix(8)))")
