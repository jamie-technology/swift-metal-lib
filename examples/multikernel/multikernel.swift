// Two @Compute kernels in one module → two `air.kernel` entries in one
// metallib. The host loads the library once and dispatches each by name.
@Compute
@_silgen_name("scale2")
public func scale2(@Binding(to: 0) @Device _ a: UnsafePointer<Float>,
                   @Binding(to: 1) @Device _ out: UnsafeMutablePointer<Float>,
                   @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] * 2.0
}

@Compute
@_silgen_name("negate")
public func negate(@Binding(to: 0) @Device _ a: UnsafePointer<Float>,
                   @Binding(to: 1) @Device _ out: UnsafeMutablePointer<Float>,
                   @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = -a[i]
}
