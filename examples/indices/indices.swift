// examples/indices/indices.swift — multi-builtin compute kernel, written with
// GPU attributes. Two distinct thread builtins in one signature, disambiguated
// by @ThreadPositionInGrid vs @ThreadPositionInThreadgroup. `@Device` buffers
// lower to `i32 addrspace(1)*`; the host verifies each thread's global and
// threadgroup-local index. `swift-frontend -emit-metallib` owns the pipeline.

@Compute
@_silgen_name("indices")
public func indices(@Binding(to: 0) @Device _ gridPos: UnsafeMutablePointer<UInt32>,
                    @Binding(to: 1) @Device _ localPos: UnsafeMutablePointer<UInt32>,
                    @ThreadPositionInGrid _ gid: UInt32,
                    @ThreadPositionInThreadgroup _ lid: UInt32) {
    gridPos[Int(gid)] = gid
    localPos[Int(gid)] = lid
}
