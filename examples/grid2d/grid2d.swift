// 2-D dispatch: a `SIMD2<UInt32>` thread position (MSL `uint2`). Swift's
// SIMD2<UInt32> lowers to `<2 x i32>`, matching MSL's uint2 ABI exactly, so 2-D
// grids work end-to-end; the compiler records the builtin's type as `uint2` in
// the air.kernel metadata. This kernel transposes a 256×192 float matrix — each
// (x, y) thread copies inp[x*192 + y] to out[y*256 + x].
@Compute
@_silgen_name("grid2d")
public func grid2d(@Binding(to: 0) @Device _ out: UnsafeMutablePointer<Float>,
                   @Binding(to: 1) @Device _ inp: UnsafePointer<Float>,
                   @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let x = Int(gid.x)   // 0..<256
    let y = Int(gid.y)   // 0..<192
    out[y * 256 + x] = inp[x * 192 + y]
}
