import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/atomics/atomics.metallib"
let n = 16384
let ctx = try ComputeContext(metallibPath: lib)
let data = (0..<n).map { Int32($0 - n/2) }          // -8192 ... 8191
let bufData = ctx.buffer(data)
let bufMin = ctx.buffer([Int32.max]); let bufMax = ctx.buffer([Int32.min])
let bufSum = ctx.buffer([Float(0)]);  let bufCtr = ctx.buffer([UInt32(0)])
try ctx.dispatch("atomics", buffers: [bufData, bufMin, bufMax, bufSum, bufCtr], count: n)
let gmin = bufMin.array(Int32.self, count: 1)[0]
let gmax = bufMax.array(Int32.self, count: 1)[0]
let gsum = bufSum.array(Float.self, count: 1)[0]
let gctr = bufCtr.array(UInt32.self, count: 1)[0]
let emin = data.min()!, emax = data.max()!, esum = Float(data.reduce(0) { $0 + Int($1) })
let ok = gmin == emin && gmax == emax && gsum == esum && gctr == UInt32(n)
print(ok ? "✅ atomics: min=\(gmin) max=\(gmax) sum=\(gsum) casCounter=\(gctr) — all correct"
         : "❌ atomics: min=\(gmin)/\(emin) max=\(gmax)/\(emax) sum=\(gsum)/\(esum) ctr=\(gctr)/\(n)")
