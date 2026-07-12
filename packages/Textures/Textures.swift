// Textures — the first swift-metal *package*. The GPU-side surface: texture
// handle types + read/write, layered on the compiler's texture support (the
// compiler recognizes `Texture2D`/`WriteTexture2D` by name → an `air.texture`
// argument lowered to a device-address-space handle; see docs/textures.md).
//
// Compile this file alongside a kernel that uses textures, e.g.
//   swift-frontend -emit-metallib -O -parse-as-library \
//       packages/Textures/Textures.swift my_kernel.swift -o my.metallib
//
// The host half lives in the MetalSwift module (`ComputeContext.texture`,
// `dispatchTextures`, `MTLTexture.floats()`).

/// A sampled/readable 2-D texture bound at `[[texture(i)]]`.
public struct Texture2D<T> { @Device var _handle: UnsafePointer<UInt8> }

/// A writable 2-D texture bound at `[[texture(i)]]`.
public struct WriteTexture2D<T> { @Device var _handle: UnsafeMutablePointer<UInt8> }

/// A read+write 2-D texture bound at `[[texture(i)]]` (MSL `access::read_write`).
public struct ReadWriteTexture2D<T> { @Device var _handle: UnsafeMutablePointer<UInt8> }

/// An opaque sampler handle (constant address space), produced by the driver.
struct _Sampler { @Constant var _h: UnsafePointer<UInt8> }

@_silgen_name("air.get_read_sampler")
func _airGetReadSampler() -> _Sampler

@_silgen_name("air.read_texture_2d.v4f32")
func _airReadTexture2D(_ t: Texture2D<Float>, _ sampler: _Sampler,
                       _ coord: SIMD2<UInt32>, _ offset: SIMD2<Int32>,
                       _ lod: Int32, _ flags: Int32) -> (SIMD4<Float>, UInt8)
@_silgen_name("air.write_texture_2d.v4f32")
func _airWriteTexture2D(_ t: WriteTexture2D<Float>, _ coord: SIMD2<UInt32>,
                        _ color: SIMD4<Float>, _ lod: Int32, _ flags: Int32)

public extension Texture2D where T == Float {
    /// Read the texel at integer `coord`.
    func read(_ coord: SIMD2<UInt32>) -> SIMD4<Float> {
        _airReadTexture2D(self, _airGetReadSampler(), coord,
                          SIMD2<Int32>(0, 0), 0, 1).0
    }
}

public extension WriteTexture2D where T == Float {
    /// Write `color` to the texel at integer `coord`.
    func write(_ color: SIMD4<Float>, to coord: SIMD2<UInt32>) {
        _airWriteTexture2D(self, coord, color, 0, 2)
    }
}

public extension ReadWriteTexture2D where T == Float {
    // All texture handles lower to an opaque `ptr addrspace(1)`, so a read_write
    // handle can reuse the read/write intrinsics via a (no-op) reinterpret.
    /// Read the texel at integer `coord`.
    func read(_ coord: SIMD2<UInt32>) -> SIMD4<Float> {
        _airReadTexture2D(unsafeBitCast(self, to: Texture2D<Float>.self),
                          _airGetReadSampler(), coord, SIMD2<Int32>(0, 0), 0, 1).0
    }
    /// Write `color` to the texel at integer `coord`.
    func write(_ color: SIMD4<Float>, to coord: SIMD2<UInt32>) {
        _airWriteTexture2D(unsafeBitCast(self, to: WriteTexture2D<Float>.self),
                           coord, color, 0, 2)
    }
}

// MARK: - 3-D textures
//
// NOTE: the read/write intrinsics + metadata are correct, but *dispatching* a 3-D
// grid needs a uint3 `thread_position_in_grid`, and Swift's SIMD3<UInt32> lowers
// to <4 x i32> (padded) where the driver wants <3 x i32> — so 3-D dispatch is
// blocked on the same uint3 gap as 3-D grids generally (see docs/textures.md).

/// A sampled/readable 3-D texture bound at `[[texture(i)]]`.
public struct Texture3D<T> { @Device var _handle: UnsafePointer<UInt8> }
/// A writable 3-D texture bound at `[[texture(i)]]`.
public struct WriteTexture3D<T> { @Device var _handle: UnsafeMutablePointer<UInt8> }

@_silgen_name("air.read_texture_3d.v4f32")
func _airReadTexture3D(_ t: Texture3D<Float>, _ s: _Sampler, _ c: SIMD3<UInt32>,
                       _ o: SIMD3<Int32>, _ lod: Int32, _ f: Int32) -> (SIMD4<Float>, UInt8)
@_silgen_name("air.write_texture_3d.v4f32")
func _airWriteTexture3D(_ t: WriteTexture3D<Float>, _ c: SIMD3<UInt32>,
                        _ color: SIMD4<Float>, _ lod: Int32, _ f: Int32)

public extension Texture3D where T == Float {
    func read(_ coord: SIMD3<UInt32>) -> SIMD4<Float> {
        _airReadTexture3D(self, _airGetReadSampler(), coord, SIMD3<Int32>(0,0,0), 0, 1).0
    }
}
public extension WriteTexture3D where T == Float {
    func write(_ color: SIMD4<Float>, to coord: SIMD3<UInt32>) {
        _airWriteTexture3D(self, coord, color, 0, 2)
    }
}
