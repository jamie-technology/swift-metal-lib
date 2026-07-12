// examples/vscale/vscale.swift — vector-typed compute kernel (SIMD4<Float> ->
// AIR float4), written with GPU attributes. `@Device` buffers lower to
// `<4 x float> addrspace(1)*`; `input[i] * 2.0` dispatches the SIMD scalar
// operator on the loaded value. `swift-frontend -emit-metallib` owns the
// pipeline (no `smc`).

@Compute
@_silgen_name("vscale")
public func vscale(@Binding(to: 0) @Device _ input: UnsafePointer<SIMD4<Float>>,
                   @Binding(to: 1) @Device _ output: UnsafeMutablePointer<SIMD4<Float>>,
                   @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    output[i] = input[i] * 2.0
}
