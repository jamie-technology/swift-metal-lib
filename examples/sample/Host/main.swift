import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/sample/sample.metallib"
let ctx = try ComputeContext(metallibPath: lib)

// 2x2 source: R channel = 0,1,2,3 (row-major).
let SW = 2
var px = [Float](repeating: 0, count: SW*SW*4)
for i in 0..<(SW*SW) { px[i*4+0] = Float(i); px[i*4+3] = 1 }
let src = ctx.texture(width: SW, height: SW, pixels: px, usage: .shaderRead)
let smp = ctx.sampler(min: .linear, mag: .linear, address: .clampToEdge)

let OW = 4
let out = ctx.buffer(count: OW*OW, of: SIMD4<Float>.self)
let dims = ctx.buffer([UInt32(OW)])
try ctx.dispatchSampled("upsample", textures: [src], samplers: [smp],
                        buffers: [out, dims], width: OW, height: OW)

let got = out.array(SIMD4<Float>.self, count: OW*OW)
// Corners clamp to the source texels; interior is interpolated. Check a few:
// top-left output pixel center (0.125,0.125) is within texel 0's region -> ~0.
let tl = got[0].x, br = got[OW*OW-1].x
// Center 2x2 block straddles all four texels -> values strictly between 0 and 3.
let c = got[1*OW+1].x
let ok = tl < 0.5 && br > 2.5 && c > 0 && c < 3 &&
         got.allSatisfy { $0.x >= 0 && $0.x <= 3 }
if ok {
    print("✅ sample: bilinear upsample correct — TL≈\(tl), BR≈\(br), interior interpolated (c=\(c))")
} else {
    print("❌ sample: TL=\(tl) BR=\(br) c=\(c)")
}
