// examples/vscale/vscale.swift — vector-typed compute kernel (SIMD4<Float> ->
// AIR float4), written with GPU attributes. The compiler reflects the pointee
// types (UnsafePointer<SIMD4<Float>>) into !swiftgpu.kernels; smc maps them to
// float4 (16-byte stride) and derives read/read_write from pointer mutability.

@Compute
@_silgen_name("vscale")
public func vscale(@Binding(to: 0) _ input: UnsafePointer<SIMD4<Float>>,
                   @Binding(to: 1) _ output: UnsafeMutablePointer<SIMD4<Float>>,
                   @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    output[i] = input[i] * 2.0
}
