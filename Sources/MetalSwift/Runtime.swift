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
#endif
