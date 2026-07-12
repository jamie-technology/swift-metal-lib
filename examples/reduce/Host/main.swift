// Host program for the `reduce` example — per-threadgroup sum reduction using
// threadgroup shared memory + a barrier.

import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "examples/reduce/reduce.metallib"

let groupSize = 256
let groups = 4096
let n = groupSize * groups

let ctx = try ComputeContext(metallibPath: metallib)

let inp = (0..<n).map { _ in Float(1) }   // all ones → each group sums to 256
let bufIn = ctx.buffer(inp)
let bufOut = ctx.buffer(count: groups, of: Float.self)

try ctx.dispatchThreadgroups(
    "reduce",
    buffers: [bufIn, bufOut],
    threadgroupMemory: [0: groupSize * MemoryLayout<Float>.stride],
    threadgroups: groups,
    threadsPerThreadgroup: groupSize)

let out = bufOut.array(Float.self, count: groups)
var mismatches = 0
for g in 0..<groups {
    let expected = inp[(g * groupSize)..<((g + 1) * groupSize)].reduce(0, +)
    if out[g] != expected {
        if mismatches < 5 { print("  group \(g): \(out[g]) != \(expected)") }
        mismatches += 1
    }
}

if mismatches == 0 {
    print("✅ reduce: threadgroup shared memory + barrier correct for all \(groups) "
          + "groups  (out[0] = \(out[0]))")
} else {
    print("❌ reduce: \(mismatches) mismatches")
    exit(1)
}
