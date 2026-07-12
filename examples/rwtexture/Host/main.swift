// In-place read_write texture: brighten each pixel by 1.5x.
import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/rwtexture/rwtexture.metallib"
let W = 64, H = 64
let ctx = try ComputeContext(metallibPath: lib)
var px = [Float](repeating: 0, count: W*H*4)
for i in 0..<(W*H) { px[i*4+0]=0.1; px[i*4+1]=0.2; px[i*4+2]=0.3; px[i*4+3]=0.4 }
let img = ctx.texture(width: W, height: H, pixels: px)   // read+write usage (default)
try ctx.dispatchTextures("brighten", textures: [img], width: W, height: H)
let out = img.floats()
var ok = true
for i in 0..<(W*H) {
    if abs(out[i*4+0]-0.15) > 1e-5 || abs(out[i*4+1]-0.3) > 1e-5 ||
       abs(out[i*4+2]-0.45) > 1e-5 || abs(out[i*4+3]-0.6) > 1e-5 { ok = false; break }
}
print(ok ? "✅ rwtexture: in-place read_write brighten correct (out[0] r=\(out[0]))"
         : "❌ rwtexture: out[0..3] = \(out[0]),\(out[1]),\(out[2]),\(out[3])")
