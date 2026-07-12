// Image invert kernel — reads a texel, inverts RGB, preserves alpha, writes it.
// Uses the Textures package types (Texture2D / WriteTexture2D); the compiler
// lowers them to air.texture arguments.
@Compute
@_silgen_name("invert")
public func invert(_ src: Texture2D<Float>, _ dst: WriteTexture2D<Float>,
                   @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let c = src.read(gid)
    dst.write(SIMD4<Float>(1 - c.x, 1 - c.y, 1 - c.z, c.w), to: gid)
}
