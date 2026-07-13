// Bilinear sampling: upsample a source texture through a linear Sampler. Each
// output pixel samples the source at its normalized center; the hardware
// filters between texels. Demonstrates Texture2D.sample + a Sampler argument.
@Compute
@_silgen_name("upsample")
public func upsample(_ src: Texture2D<Float>, _ s: Sampler,
                     @Binding(to: 0) @Device _ out: UnsafeMutablePointer<SIMD4<Float>>,
                     @Binding(to: 1) @Device _ dims: UnsafePointer<UInt32>,
                     @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let outW = dims[0]
    let uv = SIMD2<Float>((Float(gid.x) + 0.5) / Float(outW),
                          (Float(gid.y) + 0.5) / Float(outW))
    out[Int(gid.y &* outW &+ gid.x)] = src.sample(s, uv)
}
