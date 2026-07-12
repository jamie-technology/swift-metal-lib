// Exercises the Atomics package beyond fetch-add: signed Int32 min/max, Float
// atomic add, and a compare-exchange CAS loop (increment under contention).
@Compute
@_silgen_name("atomics")
public func atomics(@Binding(to: 0) @Device _ data: UnsafePointer<Int32>,
                    @Binding(to: 1) @Device _ imin: UnsafeMutablePointer<Int32>,
                    @Binding(to: 2) @Device _ imax: UnsafeMutablePointer<Int32>,
                    @Binding(to: 3) @Device _ fsum: UnsafeMutablePointer<Float>,
                    @Binding(to: 4) @Device _ counter: UnsafeMutablePointer<UInt32>,
                    @ThreadPositionInGrid _ gid: UInt32) {
    let v = data[Int(gid)]
    _ = atomicFetchMin(imin, v)          // signed min
    _ = atomicFetchMax(imax, v)          // signed max
    _ = atomicFetchAdd(fsum, Float(v))   // float add
    // compare-exchange CAS loop: increment the counter exactly once per thread.
    var cur = atomicLoad(counter)        // CAS loop: increment once per thread
    while !atomicCompareExchange(counter, &cur, cur &+ 1) {}
}
