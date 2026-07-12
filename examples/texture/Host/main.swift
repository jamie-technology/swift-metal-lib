// Host for the texture `invert` kernel: RGB inverted, alpha preserved.
import Foundation
import MetalSwift

let metallib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/texture/texture.metallib"
let W = 64, H = 64
let ctx = try ComputeContext(metallibPath: metallib)

var pixels = [Float](repeating: 0, count: W*H*4)
for i in 0..<(W*H) {
    pixels[i*4+0] = 0.25; pixels[i*4+1] = 0.5; pixels[i*4+2] = 0.75; pixels[i*4+3] = 1.0
}
let src = ctx.texture(width: W, height: H, pixels: pixels, usage: .shaderRead)
let dst = ctx.texture(width: W, height: H, usage: .shaderWrite)

try ctx.dispatchTextures("invert", textures: [src, dst], width: W, height: H)

let out = dst.floats()
var ok = true
for i in 0..<(W*H) {
    if abs(out[i*4+0] - 0.75) > 1e-5 || abs(out[i*4+1] - 0.5) > 1e-5 ||
       abs(out[i*4+2] - 0.25) > 1e-5 || abs(out[i*4+3] - 1.0) > 1e-5 { ok = false; break }
}
print(ok ? "✅ texture: invert correct (out[0] rgba = \(out[0]),\(out[1]),\(out[2]),\(out[3]))"
         : "❌ texture: mismatch")
