import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/histogram/histogram.metallib"
let n = 1 << 20, bins = 16
let ctx = try ComputeContext(metallibPath: lib)
let data = (0..<n).map { UInt32($0 % bins) }   // each bin hit n/16 times
let bufData = ctx.buffer(data)
let bufBins = ctx.buffer(count: bins, of: UInt32.self)
try ctx.dispatch("histogram", buffers: [bufData, bufBins], count: n)
let got = bufBins.array(UInt32.self, count: bins)
let expected = UInt32(n / bins)
let ok = got.allSatisfy { $0 == expected }
print(ok ? "✅ histogram: atomic bins all == \(expected) (\(got[0]), \(got[1]), …)"
         : "❌ histogram: \(got)")
