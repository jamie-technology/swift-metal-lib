// Integer texture: read a uint4 texel, add 1 to each channel, write it back.
// Exercises Texture2D<UInt32>/WriteTexture2D<UInt32> (rgba32Uint, .u.v4i32).
@Compute @_silgen_name("uinc")
public func uinc(_ src: Texture2D<UInt32>, _ dst: WriteTexture2D<UInt32>,
                 @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let c = src.read(gid)
    dst.write(c &+ SIMD4<UInt32>(1, 2, 3, 4), to: gid)
}
