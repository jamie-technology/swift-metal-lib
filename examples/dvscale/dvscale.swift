// Vector scale kernel: multiply each `device SIMD4<Float>` by a scalar.
//
// This exercises value-generic SIMD arithmetic on a value loaded from a device
// pointer. `inp[i]` is a `device SIMD4<Float>`; `* 2.0` dispatches the SIMD
// protocol-extension operator with `Self = device SIMD4<Float>`. The address
// space qualifies storage only — it drops on load, so the arithmetic lowers to
// a plain `fmul <4 x float>` while the loads/stores stay `ptr addrspace(1)`.
@Compute
@_silgen_name("dvscale")
public func dvscale(@Binding(to: 0) @Device _ inp: UnsafePointer<SIMD4<Float>>,
                    @Binding(to: 1) @Device _ out: UnsafeMutablePointer<SIMD4<Float>>,
                    @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = inp[i] * 2.0
}
