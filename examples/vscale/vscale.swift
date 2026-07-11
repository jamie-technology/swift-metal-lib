// examples/vscale/vscale.swift — vector-typed compute kernel.
//
// Exercises `SIMD4<Float>` buffers (AIR `float4`, 16-byte stride). swiftc lowers
// the loads/stores to `<4 x float>`; smc flattens Swift's SIMD wrapper structs
// to that payload type and reflects the element as `float4` in the metadata.
//
// Buffer element types and the read/read_write access are recovered from the
// Swift source signature (UnsafePointer = read, UnsafeMutablePointer = write).

@_silgen_name("vscale")
public func vscale(_ input: UnsafePointer<SIMD4<Float>>,        // @binding(0)
                   _ output: UnsafeMutablePointer<SIMD4<Float>>, // @binding(1)
                   _ gid: UInt32) {                              // @threadPositionInGrid
    let i = Int(gid)
    output[i] = input[i] * 2.0
}
