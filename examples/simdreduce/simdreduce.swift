// SIMD-group reduction — one Apple SIMD-group is 32 lanes executing in
// lockstep. All 32 threads cooperatively sum their inputs with `simdSum`
// (no threadgroup memory, no barrier); every lane then writes the group total.
// Uses the SIMDGroup package.
@Compute
@_silgen_name("simdreduce")
public func simdreduce(@Binding(to: 0) @Device _ input: UnsafePointer<Float>,
                       @Binding(to: 1) @Device _ output: UnsafeMutablePointer<Float>,
                       @ThreadPositionInGrid _ gid: UInt32) {
    let v = input[Int(gid)]
    output[Int(gid)] = simdSum(v)
}
