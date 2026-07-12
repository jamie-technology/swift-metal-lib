// Threadgroup shared memory + barrier: a per-threadgroup sum reduction.
//
// `@Threadgroup` puts `scratch` in the threadgroup address space (AIR
// addrspace 3) — memory shared by all threads in a threadgroup, its length set
// by the host. `threadgroupBarrier()` lowers to the `air.wg.barrier` intrinsic,
// synchronizing the threadgroup so every thread's write to `scratch` is visible
// before thread 0 sums it.

// The threadgroup barrier intrinsic (flags = mem_threadgroup, scope = 1).
@_silgen_name("air.wg.barrier")
func _airWgBarrier(_ flags: UInt32, _ scope: UInt32)

@inline(__always)
func threadgroupBarrier() { _airWgBarrier(2, 1) }

@Compute
@_silgen_name("reduce")
public func reduce(@Binding(to: 0) @Device _ inp: UnsafePointer<Float>,
                   @Binding(to: 1) @Device _ out: UnsafeMutablePointer<Float>,
                   @Binding(to: 2) @Threadgroup _ scratch: UnsafeMutablePointer<Float>,
                   @ThreadPositionInGrid _ gid: UInt32,
                   @ThreadIndexInThreadgroup _ lid: UInt32,
                   @ThreadgroupPositionInGrid _ tgid: UInt32) {
    let l = Int(lid)
    scratch[l] = inp[Int(gid)]     // each thread stages one element
    threadgroupBarrier()           // wait for all writes
    if l == 0 {
        var sum: Float = 0
        for i in 0..<256 { sum += scratch[i] }
        out[Int(tgid)] = sum       // one output per threadgroup
    }
}
