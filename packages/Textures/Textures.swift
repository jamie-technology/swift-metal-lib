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

// MARK: - Half / UInt / Int element formats (2-D)
//
// The element type selects the intrinsic (half -> .v4f16, uint -> .u.v4i32,
// int -> .s.v4i32) and the metadata type name (texture2d<half|uint|int, …>).

@_silgen_name("air.read_texture_2d.v4f16")
func _airReadTex2Dh(_ t: Texture2D<Float16>, _ s: _Sampler, _ c: SIMD2<UInt32>,
                    _ o: SIMD2<Int32>, _ lod: Int32, _ f: Int32) -> (SIMD4<Float16>, UInt8)
@_silgen_name("air.write_texture_2d.v4f16")
func _airWriteTex2Dh(_ t: WriteTexture2D<Float16>, _ c: SIMD2<UInt32>,
                     _ color: SIMD4<Float16>, _ lod: Int32, _ f: Int32)
@_silgen_name("air.read_texture_2d.u.v4i32")
func _airReadTex2Du(_ t: Texture2D<UInt32>, _ s: _Sampler, _ c: SIMD2<UInt32>,
                    _ o: SIMD2<Int32>, _ lod: Int32, _ f: Int32) -> (SIMD4<UInt32>, UInt8)
@_silgen_name("air.write_texture_2d.u.v4i32")
func _airWriteTex2Du(_ t: WriteTexture2D<UInt32>, _ c: SIMD2<UInt32>,
                     _ color: SIMD4<UInt32>, _ lod: Int32, _ f: Int32)
@_silgen_name("air.read_texture_2d.s.v4i32")
func _airReadTex2Di(_ t: Texture2D<Int32>, _ s: _Sampler, _ c: SIMD2<UInt32>,
                    _ o: SIMD2<Int32>, _ lod: Int32, _ f: Int32) -> (SIMD4<Int32>, UInt8)
@_silgen_name("air.write_texture_2d.s.v4i32")
func _airWriteTex2Di(_ t: WriteTexture2D<Int32>, _ c: SIMD2<UInt32>,
                     _ color: SIMD4<Int32>, _ lod: Int32, _ f: Int32)

public extension Texture2D where T == Float16 {
    func read(_ coord: SIMD2<UInt32>) -> SIMD4<Float16> {
        _airReadTex2Dh(self, _airGetReadSampler(), coord, SIMD2<Int32>(0, 0), 0, 1).0
    }
}
public extension WriteTexture2D where T == Float16 {
    func write(_ color: SIMD4<Float16>, to coord: SIMD2<UInt32>) {
        _airWriteTex2Dh(self, coord, color, 0, 2)
    }
}
public extension Texture2D where T == UInt32 {
    func read(_ coord: SIMD2<UInt32>) -> SIMD4<UInt32> {
        _airReadTex2Du(self, _airGetReadSampler(), coord, SIMD2<Int32>(0, 0), 0, 1).0
    }
}
public extension WriteTexture2D where T == UInt32 {
    func write(_ color: SIMD4<UInt32>, to coord: SIMD2<UInt32>) {
        _airWriteTex2Du(self, coord, color, 0, 2)
    }
}
public extension Texture2D where T == Int32 {
    func read(_ coord: SIMD2<UInt32>) -> SIMD4<Int32> {
        _airReadTex2Di(self, _airGetReadSampler(), coord, SIMD2<Int32>(0, 0), 0, 1).0
    }
}
public extension WriteTexture2D where T == Int32 {
    func write(_ color: SIMD4<Int32>, to coord: SIMD2<UInt32>) {
        _airWriteTex2Di(self, coord, color, 0, 2)
    }
}

// MARK: - 3-D textures
//
// 3-D dispatch works — the compiler rewrites the padded SIMD3<UInt32> builtin
// (<4 x i32>) to the <3 x i32> the driver wants. See examples/texture3d.

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
