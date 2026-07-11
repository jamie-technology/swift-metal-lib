// examples/indices/indices.swift — multi-builtin compute kernel.
//
// Two hardware builtins in one signature — inference can't tell them apart, so
// the intent is stated with per-parameter markers (the stand-ins for the future
// @ThreadPositionInGrid / @ThreadPositionInThreadgroup attributes). Writes each
// thread's global and threadgroup-local index so the host can verify both.

@_silgen_name("indices")
public func indices(_ gridPos: UnsafeMutablePointer<UInt32>,   // @binding(0)
                    _ localPos: UnsafeMutablePointer<UInt32>,   // @binding(1)
                    _ gid: UInt32,                              // @threadPositionInGrid
                    _ lid: UInt32) {                            // @threadPositionInThreadgroup
    gridPos[Int(gid)] = gid
    localPos[Int(gid)] = lid
}
