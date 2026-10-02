import Foundation
import MetalSwift
let lib = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "examples/triangle/triangle.metallib"
let w = 16, h = 16
let ctx = try RenderContext(metallibPath: lib)
// The triangle covers the whole viewport, so every pixel should be red.
let px = try ctx.render(vertex: "triangle_vertex", fragment: "triangle_fragment",
                        vertexCount: 3, width: w, height: h)
func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    let i = (y * w + x) * 4           // BGRA
    return (px[i], px[i+1], px[i+2], px[i+3])
}
let (b, g, r, a) = pixel(w/2, h/2)
let ok = r > 200 && g < 50 && b < 50 && a == 255
print(ok ? "✅ triangle: rendered red (center BGRA = \(b),\(g),\(r),\(a))"
         : "❌ triangle: unexpected center BGRA = \(b),\(g),\(r),\(a)")
