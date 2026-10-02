// SIMDGroupMatrix — the cooperative 8×8 matrix-multiply primitive, over the
// `air.simdgroup_matrix_8x8_*` intrinsics. One SIMD-group holds and multiplies a
// whole 8×8 tile; at the IR level a matrix is a flat `<64 x float>`
// (`SIMD64<Float>`). The building block for a hand-tiled GEMM.
//
// Compile alongside a kernel that uses it:
//   swift-frontend -emit-metallib -O -parse-as-library \
//       packages/SIMDGroupMatrix/SIMDGroupMatrix.swift my_kernel.swift -o my.metallib
//
// Note: Swift passes a `SIMD64<Float>` (256 bytes) indirectly, but the AIR
// intrinsics take/return it by value (`<64 x float>`). The fork's AIR normalizer
// rewrites the indirect calling convention of `air.simdgroup_matrix_*` to
// by-value (see docs/fork-changes.md).

/// An 8×8 matrix of `Float`, held cooperatively across a SIMD-group.
public struct SIMDGroupMatrix {
    @usableFromInline var storage: SIMD64<Float>
    @inlinable init(_ s: SIMD64<Float>) { storage = s }
}

@_silgen_name("air.simdgroup_matrix_8x8_init_filled.v64f32.f32")
func _sgFill(_ v: Float) -> SIMD64<Float>
@_silgen_name("air.simdgroup_matrix_8x8_load.v64f32.p1f32")
func _sgLoad(@Device _ p: UnsafePointer<Float>, _ dims: SIMD2<Int64>,
             _ stride: SIMD2<Int64>, _ origin: SIMD2<Int64>) -> SIMD64<Float>
@_silgen_name("air.simdgroup_matrix_8x8_multiply_accumulate.v64f32.v64f32.v64f32.v64f32")
func _sgMMA(_ a: SIMD64<Float>, _ b: SIMD64<Float>, _ c: SIMD64<Float>) -> SIMD64<Float>
@_silgen_name("air.simdgroup_matrix_8x8_store.v64f32.p1f32")
func _sgStore(_ v: SIMD64<Float>, @Device _ p: UnsafeMutablePointer<Float>,
              _ dims: SIMD2<Int64>, _ stride: SIMD2<Int64>, _ origin: SIMD2<Int64>)

public extension SIMDGroupMatrix {
    /// An 8×8 matrix with every element set to `v`.
    static func filled(_ v: Float) -> SIMDGroupMatrix { SIMDGroupMatrix(_sgFill(v)) }

    /// Load an 8×8 tile from device memory, `elementsPerRow` apart row to row.
    static func load(from p: UnsafePointer<Float>,
                     elementsPerRow: Int64 = 8) -> SIMDGroupMatrix {
        SIMDGroupMatrix(_sgLoad(p, SIMD2(8, 8), SIMD2(1, elementsPerRow), SIMD2(0, 0)))
    }

    /// `self * b + c`, the fused multiply-accumulate.
    func multiplyAccumulate(_ b: SIMDGroupMatrix,
                            _ c: SIMDGroupMatrix) -> SIMDGroupMatrix {
        SIMDGroupMatrix(_sgMMA(storage, b.storage, c.storage))
    }

    /// Store this tile to device memory, `elementsPerRow` apart row to row.
    func store(to p: UnsafeMutablePointer<Float>, elementsPerRow: Int64 = 8) {
        _sgStore(storage, p, SIMD2(8, 8), SIMD2(1, elementsPerRow), SIMD2(0, 0))
    }
}
