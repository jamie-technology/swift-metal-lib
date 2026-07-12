import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/utexture/utexture.metallib"
let W = 32, H = 32
let ctx = try ComputeContext(metallibPath: lib)
var px = [UInt32](repeating: 0, count: W*H*4)
for i in 0..<(W*H) { px[i*4+0]=10; px[i*4+1]=20; px[i*4+2]=30; px[i*4+3]=40 }
let src = ctx.textureUInt(width: W, height: H, pixels: px, usage: .shaderRead)
let dst = ctx.textureUInt(width: W, height: H, usage: .shaderWrite)
try ctx.dispatchTextures("uinc", textures: [src, dst], width: W, height: H)
let out = dst.uints()
var ok = true
for i in 0..<(W*H) where out[i*4]==11 && out[i*4+1]==22 && out[i*4+2]==33 && out[i*4+3]==44 { continue }
if !(out[0]==11 && out[1]==22 && out[2]==33 && out[3]==44) { ok = false }
print(ok ? "✅ utexture: uint texel add correct (out[0] rgba = \(out[0]),\(out[1]),\(out[2]),\(out[3]))"
         : "❌ utexture: out[0..3] = \(out[0]),\(out[1]),\(out[2]),\(out[3])")
