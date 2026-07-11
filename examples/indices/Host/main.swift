// Host for the `indices` example: verifies both thread builtins.
import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/indices/indices.metallib"
let tpt = 64
let n = tpt * 4096   // multiple of the threadgroup size

let ctx = try ComputeContext(metallibPath: metallib)
let bufGrid = ctx.buffer(count: n, of: UInt32.self)
let bufLocal = ctx.buffer(count: n, of: UInt32.self)

try ctx.dispatch("indices", buffers: [bufGrid, bufLocal], count: n, threadsPerGroup: tpt)

let grid = bufGrid.array(UInt32.self, count: n)
let local = bufLocal.array(UInt32.self, count: n)
var bad = 0
for i in 0..<n where grid[i] != UInt32(i) || local[i] != UInt32(i % tpt) {
    if bad < 5 { print("  mismatch at \(i): grid=\(grid[i]) local=\(local[i]) (want \(i), \(i % tpt))") }
    bad += 1
}
if bad == 0 {
    print("✅ indices: thread_position_in_grid AND _in_threadgroup correct for all \(n) threads")
} else { print("❌ indices: \(bad) mismatches"); exit(1) }
