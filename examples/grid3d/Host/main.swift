import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/grid3d/grid3d.metallib"
let W=8,H=8,D=8
let ctx = try ComputeContext(metallibPath: lib)
let out = ctx.buffer(count: W*H*D, of: UInt32.self)
try ctx.dispatchThreads3D("grid3d", buffers: [out], width: W, height: H, depth: D)
let g = out.array(UInt32.self, count: W*H*D)
var ok = true
for z in 0..<D { for y in 0..<H { for x in 0..<W {
    if g[z*64+y*8+x] != UInt32(x) &+ UInt32(y) &* 100 &+ UInt32(z) &* 10000 { ok=false } } } }
print(ok ? "✅ grid3d: uint3 3D dispatch correct for all \(W*H*D) threads (g[1,2,3]=\(g[3*64+2*8+1]))" : "❌ grid3d mismatch")
