// 3-D dispatch: a uint3 (SIMD3<UInt32>) thread position. The compiler rewrites
// the padded <4 x i32> builtin param to the <3 x i32> the driver expects.
@Compute @_silgen_name("grid3d")
public func grid3d(@Binding(to: 0) @Device _ out: UnsafeMutablePointer<UInt32>,
                  @ThreadPositionInGrid _ gid: SIMD3<UInt32>) {
    let x = Int(gid.x), y = Int(gid.y), z = Int(gid.z)
    out[z * 64 + y * 8 + x] = gid.x &+ gid.y &* 100 &+ gid.z &* 10000
}
