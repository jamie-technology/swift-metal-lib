// MetalSwift — host-side helper for driving a *graphics* pipeline (a @Vertex +
// @Fragment pair compiled by the fork to air.vertex / air.fragment entry
// points). Like ComputeContext, this is ordinary Metal.framework interop; it
// renders offscreen into a texture and hands back the pixels so examples can
// verify a shader's output without a window.

#if canImport(Metal)
import Metal
import Foundation

/// A GPU device plus a compiled library, ready to build render pipelines and
/// draw a vertex/fragment pair into an offscreen texture.
public final class RenderContext {
    public let device: MTLDevice
    public let library: MTLLibrary
    public let queue: MTLCommandQueue

    public init(metallibPath: String) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw GPUError(message: "no Metal device")
        }
        self.device = device
        self.library = try device.makeLibrary(URL: URL(fileURLWithPath: metallibPath))
        guard let queue = device.makeCommandQueue() else {
            throw GPUError(message: "could not create command queue")
        }
        self.queue = queue
    }

    /// Build a render pipeline state from a vertex + fragment function pair.
    public func pipeline(vertex: String, fragment: String,
                         pixelFormat: MTLPixelFormat = .bgra8Unorm)
        throws -> MTLRenderPipelineState {
        guard let vfn = library.makeFunction(name: vertex) else {
            throw GPUError(message: "vertex '\(vertex)' not found; available: \(library.functionNames)")
        }
        guard let ffn = library.makeFunction(name: fragment) else {
            throw GPUError(message: "fragment '\(fragment)' not found; available: \(library.functionNames)")
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vfn
        d.fragmentFunction = ffn
        d.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: d)
    }

    /// Render `vertexCount` vertices of the pair into a fresh `width`×`height`
    /// BGRA8 texture and return the pixel bytes (BGRA, row-major, 4 per pixel).
    public func render(vertex: String, fragment: String, vertexCount: Int,
                       width: Int, height: Int,
                       clear: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1))
        throws -> [UInt8] {
        let pso = try pipeline(vertex: vertex, fragment: fragment)
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        guard let tex = device.makeTexture(descriptor: td) else {
            throw GPUError(message: "could not allocate render target")
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = clear
        rp.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rp) else {
            throw GPUError(message: "could not encode render pass")
        }
        enc.setRenderPipelineState(pso)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU render failed: \(e)") }
        var px = [UInt8](repeating: 0, count: width * height * 4)
        tex.getBytes(&px, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }
}
#endif
