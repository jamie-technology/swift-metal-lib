// Histogram — each thread atomically increments the bin for its input value.
// Concurrent writes to shared bins require atomics (uses the Atomics package).
@Compute
@_silgen_name("histogram")
public func histogram(@Binding(to: 0) @Device _ data: UnsafePointer<UInt32>,
                      @Binding(to: 1) @Device _ bins: UnsafeMutablePointer<UInt32>,
                      @ThreadPositionInGrid _ gid: UInt32) {
    let bin = Int(data[Int(gid)] % 16)
    _ = atomicFetchAdd(bins + bin, 1)
}
