// examples/indices/indices.swift — multi-builtin compute kernel, written with
// GPU attributes. Two distinct thread builtins in one signature, disambiguated
// by @ThreadPositionInGrid vs @ThreadPositionInThreadgroup. The host verifies
// each thread's global and threadgroup-local index.

@Compute
@_silgen_name("indices")
public func indices(@Binding(to: 0) _ gridPos: UnsafeMutablePointer<UInt32>,
                    @Binding(to: 1) _ localPos: UnsafeMutablePointer<UInt32>,
                    @ThreadPositionInGrid _ gid: UInt32,
                    @ThreadPositionInThreadgroup _ lid: UInt32) {
    gridPos[Int(gid)] = gid
    localPos[Int(gid)] = lid
}
