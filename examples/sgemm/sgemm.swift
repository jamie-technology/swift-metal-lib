// sgemm — an 8×8 tile multiply, C = A·B, written with the SIMDGroupMatrix
// package. One SIMD-group (32 threads) cooperatively loads A and B, runs a
// fused multiply-accumulate into a zero accumulator, and stores the result.
@Compute
@_silgen_name("sgemm")
public func sgemm(@Binding(to: 0) @Device _ A: UnsafePointer<Float>,
                  @Binding(to: 1) @Device _ B: UnsafePointer<Float>,
                  @Binding(to: 2) @Device _ C: UnsafeMutablePointer<Float>) {
    let a = SIMDGroupMatrix.load(from: A)
    let b = SIMDGroupMatrix.load(from: B)
    let acc = SIMDGroupMatrix.filled(0)
    let c = a.multiplyAccumulate(b, acc)
    c.store(to: C)
}
