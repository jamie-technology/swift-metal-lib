// examples/add/add.swift — the canonical elementwise-add compute kernel.
//
// This is the Swift analogue of metal-air-documentation's 00_minimal_add.metal:
//
//     kernel void add(device const float* a   [[buffer(0)]],
//                     device const float* b   [[buffer(1)]],
//                     device float*       out [[buffer(2)]],
//                     uint                gid [[thread_position_in_grid]])
//     { out[gid] = a[gid] + b[gid]; }
//
// Today `smc` *infers* the binding contract from the signature: pointer
// parameters become `device` buffers (slot 0,1,2 in order) and the trailing
// scalar becomes [[thread_position_in_grid]]. `@_silgen_name` fixes the AIR
// symbol so the runtime can look the kernel up by name.
//
// The intended end-state, once the compiler carries these attributes, is:
//
//     @Compute
//     func add(@Device @Const a: Buffer<Float>,      // @Binding(to: 0)
//              @Device @Const b: Buffer<Float>,      // @Binding(to: 1)
//              @Device      out: MutableBuffer<Float>,// @Binding(to: 2)
//              @ThreadPositionInGrid gid: UInt32) {
//         out[gid] = a[gid] + b[gid]
//     }
//
// The signature below lowers to *exactly* that ABI via the inference path.

@_silgen_name("add")
public func add(_ a: UnsafePointer<Float>,
                _ b: UnsafePointer<Float>,
                _ out: UnsafeMutablePointer<Float>,
                _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] + b[i]
}
