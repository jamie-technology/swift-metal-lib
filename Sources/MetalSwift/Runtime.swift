// MetalSwift — thin host-side helpers for driving kernels compiled by `smc`.
//
// This is ordinary Metal.framework interop; it exists so example/host code can
// load a .metallib and dispatch a 1-D compute kernel without boilerplate. It is
// intentionally minimal — the interesting work is in the compiler, not here.

#if canImport(Metal)
import Metal
import Foundation

public struct GPUError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// A GPU device plus a compiled library, ready to build pipelines and dispatch.
public final class ComputeContext {
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

    public func pipeline(_ function: String) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: function) else {
            throw GPUError(message: "function '\(function)' not found; available: \(library.functionNames)")
        }
        return try device.makeComputePipelineState(function: fn)
    }

    /// Dispatch `function` over `count` threads, binding `buffers` to slots 0…n.
    public func dispatch(_ function: String,
                         buffers: [MTLBuffer],
                         count: Int,
                         threadsPerGroup: Int = 64) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, b) in buffers.enumerated() { enc.setBuffer(b, offset: 0, index: i) }
        enc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Dispatch an explicit number of threadgroups, optionally allocating
    /// threadgroup (shared) memory. `threadgroupMemory` maps a threadgroup
    /// binding index to a byte length. Use this for reductions and other kernels
    /// that use `@Threadgroup` shared storage + `threadgroupBarrier`.
    public func dispatchThreadgroups(_ function: String,
                                     buffers: [MTLBuffer],
                                     threadgroupMemory: [Int: Int] = [:],
                                     threadgroups: Int,
                                     threadsPerThreadgroup: Int) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, b) in buffers.enumerated() { enc.setBuffer(b, offset: 0, index: i) }
        for (index, length) in threadgroupMemory {
            enc.setThreadgroupMemoryLength(length, index: index)
        }
        enc.dispatchThreadgroups(MTLSize(width: threadgroups, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: threadsPerThreadgroup,
                                                                height: 1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Dispatch over a 2-D grid — for kernels taking a `SIMD2<UInt32>`
    /// `@ThreadPositionInGrid` (MSL `uint2`).
    public func dispatch2D(_ function: String,
                           buffers: [MTLBuffer],
                           width: Int, height: Int,
                           threadsPerGroup: (Int, Int) = (8, 8)) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, b) in buffers.enumerated() { enc.setBuffer(b, offset: 0, index: i) }
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: threadsPerGroup.0,
                                                           height: threadsPerGroup.1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Make an `rgba32Float` 2-D texture, optionally initialised from `pixels`
    /// (row-major, 4 floats/pixel). `usage` controls read/write access.
    public func texture(width: Int, height: Int,
                        pixels: [Float]? = nil,
                        usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        desc.usage = usage
        let tex = device.makeTexture(descriptor: desc)!
        if let pixels {
            pixels.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride)
            }
        }
        return tex
    }

    /// Make an `rgba32Uint` 2-D texture (for `Texture2D<UInt32>` kernels),
    /// optionally initialised from `pixels` (row-major, 4 uints/pixel).
    public func textureUInt(width: Int, height: Int,
                            pixels: [UInt32]? = nil,
                            usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Uint, width: width, height: height, mipmapped: false)
        desc.usage = usage
        let tex = device.makeTexture(descriptor: desc)!
        if let pixels {
            pixels.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<UInt32>.stride)
            }
        }
        return tex
    }

    /// Dispatch a kernel with buffer arguments over a 3-D grid (uint3 position).
    public func dispatchThreads3D(_ function: String, buffers: [MTLBuffer],
                                  width: Int, height: Int, depth: Int,
                                  threadsPerGroup: (Int, Int, Int) = (4, 4, 4)) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, b) in buffers.enumerated() { enc.setBuffer(b, offset: 0, index: i) }
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: depth),
                            threadsPerThreadgroup: MTLSize(width: threadsPerGroup.0,
                                                           height: threadsPerGroup.1, depth: threadsPerGroup.2))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Make an `rgba32Float` 3-D texture, optionally initialised from `pixels`.
    public func texture3D(width: Int, height: Int, depth: Int,
                          pixels: [Float]? = nil,
                          usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .rgba32Float
        desc.width = width; desc.height = height; desc.depth = depth
        desc.usage = usage
        let tex = device.makeTexture(descriptor: desc)!
        if let pixels {
            pixels.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake3D(0, 0, 0, width, height, depth), mipmapLevel: 0, slice: 0,
                            withBytes: raw.baseAddress!,
                            bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                            bytesPerImage: width * height * 4 * MemoryLayout<Float>.stride)
            }
        }
        return tex
    }

    /// Dispatch a texture kernel over a 3-D grid (uint3 thread position).
    public func dispatchTextures3D(_ function: String, textures: [MTLTexture],
                                   width: Int, height: Int, depth: Int,
                                   threadsPerGroup: (Int, Int, Int) = (4, 4, 4)) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, t) in textures.enumerated() { enc.setTexture(t, index: i) }
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: depth),
                            threadsPerThreadgroup: MTLSize(width: threadsPerGroup.0,
                                                           height: threadsPerGroup.1, depth: threadsPerGroup.2))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Dispatch a kernel that takes `[[texture(i)]]` arguments over a 2-D grid.
    public func dispatchTextures(_ function: String,
                                 textures: [MTLTexture],
                                 width: Int, height: Int,
                                 threadsPerGroup: (Int, Int) = (8, 8)) throws {
        let pso = try pipeline(function)
        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else {
            throw GPUError(message: "could not encode command buffer")
        }
        enc.setComputePipelineState(pso)
        for (i, t) in textures.enumerated() { enc.setTexture(t, index: i) }
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: threadsPerGroup.0,
                                                           height: threadsPerGroup.1, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw GPUError(message: "GPU execution failed: \(e)") }
    }

    /// Make a device buffer initialised from `array`.
    public func buffer<T>(_ array: [T]) -> MTLBuffer {
        var a = array
        return device.makeBuffer(bytes: &a, length: MemoryLayout<T>.stride * a.count)!
    }

    /// Make a zeroed device buffer holding `count` elements of `T`.
    public func buffer<T>(count: Int, of: T.Type) -> MTLBuffer {
        device.makeBuffer(length: MemoryLayout<T>.stride * count)!
    }
}

public extension MTLBuffer {
    /// View the buffer's contents as `[T]` (host-visible on unified memory).
    func array<T>(_ type: T.Type, count: Int) -> [T] {
        let p = contents().bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: p, count: count))
    }
}

public extension MTLTexture {
    /// Read an `rgba32Float` texture back as row-major `[Float]` (4 per pixel).
    func floats() -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            getBytes(raw.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return out
    }

    /// Read an `rgba32Uint` texture back as row-major `[UInt32]` (4 per pixel).
    func uints() -> [UInt32] {
        var out = [UInt32](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            getBytes(raw.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<UInt32>.stride,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return out
    }

    /// Read an `rgba32Float` 3-D texture back as `[Float]` (4 per voxel).
    func floats3D() -> [Float] {
        var out = [Float](repeating: 0, count: width * height * depth * 4)
        out.withUnsafeMutableBytes { raw in
            getBytes(raw.baseAddress!, bytesPerRow: width * 4 * MemoryLayout<Float>.stride,
                     bytesPerImage: width * height * 4 * MemoryLayout<Float>.stride,
                     from: MTLRegionMake3D(0, 0, 0, width, height, depth), mipmapLevel: 0, slice: 0)
        }
        return out
    }
}
#endif
