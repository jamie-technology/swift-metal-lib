// examples/add/add.swift — the canonical elementwise-add compute kernel,
// written with the swift-gpu fork's GPU attributes.
//
// The compiler records @Compute / @Binding / @ThreadPositionInGrid into
// !swiftgpu.kernels metadata; `smc` reads that to build the AIR binding
// contract. No source re-parsing. `@_silgen_name` fixes the AIR symbol name.
//
//   kernel void add(device const float* a   [[buffer(0)]],   // the MSL analogue
//                   device const float* b   [[buffer(1)]],
//                   device float*       out [[buffer(2)]],
//                   uint                gid [[thread_position_in_grid]]);

@Compute
@_silgen_name("add")
public func add(@Binding(to: 0) _ a: UnsafePointer<Float>,
                @Binding(to: 1) _ b: UnsafePointer<Float>,
                @Binding(to: 2) _ out: UnsafeMutablePointer<Float>,
                @ThreadPositionInGrid _ gid: UInt32) {
    let i = Int(gid)
    out[i] = a[i] + b[i]
}
