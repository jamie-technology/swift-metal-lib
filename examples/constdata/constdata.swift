// Program-scope constant data: a lookup table baked into the module and read
// from MSL `constant` address space (addrspace 2).
//
// `InlineArray` is a fixed-size *value* type (no heap, unlike `Array`), so the
// literal lowers to a static `constant` global. The kernel indexes it directly;
// the compiler places it in constant memory and GEPs into `addrspace(2)`.
let gain: InlineArray<8, Float> = [1, 2, 4, 8, 16, 32, 64, 128]

@Compute
@_silgen_name("constdata")
public func constdata(@Binding(to: 0) @Device _ inp: UnsafePointer<Float>,
                      @Binding(to: 1) @Device _ out: UnsafeMutablePointer<Float>,
                      @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = inp[i] * gain[i % 8]
}
