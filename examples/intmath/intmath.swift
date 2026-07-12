// Integer arithmetic kernel. Swift's checked `*`/`+` emit overflow-trap
// branches (llvm.smul/sadd.with.overflow + a conditional br to llvm.trap); the
// normalization pass strips the `!prof` branch_weights metadata that metal-as's
// LLVM can't parse, so integer kernels assemble and run.
@Compute
@_silgen_name("intmath")
public func intmath(@Binding(to: 0) @Device _ a: UnsafePointer<Int32>,
                    @Binding(to: 1) @Device _ out: UnsafeMutablePointer<Int32>,
                    @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] * 3 + 7
}
