// 2-D dispatch: a `SIMD2<UInt32>` thread position (MSL `uint2`). Swift's
// SIMD2<UInt32> lowers to `<2 x i32>`, matching MSL's uint2 ABI exactly, so 2-D
// grids work end-to-end; the compiler records the builtin's type as `uint2`.
//
// This also exercises device *scalar* values in ordinary arithmetic: `w` is
// loaded from a device buffer and multiplied by a (non-device) thread index,
// and a computed value is stored into a device location. The address-space
// qualifier drops on load, so these mix freely with plain values.
@Compute
@_silgen_name("grid2d")
public func grid2d(@Binding(to: 0) @Device _ out: UnsafeMutablePointer<UInt32>,
                   @Binding(to: 1) @Device _ dims: UnsafePointer<UInt32>,
                   @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let w = dims[0]                          // device UInt32 → used as UInt32
    let idx = Int(gid.y &* w &+ gid.x)
    out[idx] = gid.x &* 1000 &+ gid.y        // non-device value → device store
}
