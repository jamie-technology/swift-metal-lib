// examples/add/add.swift — the canonical elementwise-add compute kernel,
// written with the swift-gpu fork's GPU attributes. `@Device` puts the buffers
// in the device address space; the compiler emits `ptr addrspace(1)` natively
// and `swift-frontend -emit-metallib` owns the whole pipeline (no `smc`).
//
//   kernel void add(device const float* a   [[buffer(0)]],   // the MSL analogue
//                   device const float* b   [[buffer(1)]],
//                   device float*       out [[buffer(2)]],
//                   uint                gid [[thread_position_in_grid]]);

@Compute
@_silgen_name("add")
public func add(@Binding(to: 0) @Device _ a: UnsafePointer<Float>,
                @Binding(to: 1) @Device _ b: UnsafePointer<Float>,
                @Binding(to: 2) @Device _ out: UnsafeMutablePointer<Float>,
                @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] + b[i]
}
