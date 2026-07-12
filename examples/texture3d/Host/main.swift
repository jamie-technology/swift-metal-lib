import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/texture3d/texture3d.metallib"
let W = 16, H = 16, D = 16
let ctx = try ComputeContext(metallibPath: lib)
var px = [Float](repeating: 0, count: W*H*D*4)
for i in 0..<(W*H*D) { px[i*4+0]=1; px[i*4+1]=2; px[i*4+2]=3; px[i*4+3]=4 }
let src = ctx.texture3D(width: W, height: H, depth: D, pixels: px, usage: .shaderRead)
let dst = ctx.texture3D(width: W, height: H, depth: D, usage: .shaderWrite)
try ctx.dispatchTextures3D("scale3d", textures: [src, dst], width: W, height: H, depth: D)
let out = dst.floats3D()
var ok = true
for i in 0..<(W*H*D) where abs(out[i*4]-0.5) > 1e-5 || abs(out[i*4+1]-1.0) > 1e-5 { ok = false; break }
print(ok ? "✅ texture3d: uint3 3D read/write scale correct (out[0] r=\(out[0]))" : "❌ texture3d: out[0..3]=\(out[0]),\(out[1]),\(out[2]),\(out[3])")
