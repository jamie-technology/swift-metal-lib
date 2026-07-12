@Compute @_silgen_name("brighten")
public func brighten(_ img: ReadWriteTexture2D<Float>,
                     @ThreadPositionInGrid _ gid: SIMD2<UInt32>) {
    let c = img.read(gid)
    img.write(c * 1.5, to: gid)
}
