// The add kernel with the address space expressed natively via @Device —
// IRGen emits ptr addrspace(1) directly (no post-processing rewrite).
@Compute
@_silgen_name("devadd")
public func devadd(@Binding(to: 0) @Device _ a: UnsafePointer<Float>,
                   @Binding(to: 1) @Device _ b: UnsafePointer<Float>,
                   @Binding(to: 2) @Device _ out: UnsafeMutablePointer<Float>,
                   @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] + b[i]
}
